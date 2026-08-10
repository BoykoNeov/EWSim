extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-36 gate-3 verifier — THE HANDOVER BASKET: THE CHEAPEST PLACE TO HAND A SEEKER ITS
# TARGET IS NOT AT THE TARGET. Drives the REAL Julia server through SimClient.gd (the same protocol
# code Sandbox.tscn renders off).
#
#   pwsh tools/julia.ps1 --project=core tools/server.jl scenarios/slice36_handover.yaml
#   godot --headless --path clients/godot --script res://net/slice36_verify.gd     (exit 0 = pass)
#   …then the same two commands with scenarios/slice36_biased.yaml
#
# ⚠ ONE VERIFIER, TWO WIRES, AUTO-DETECTED FROM THE HANDSHAKE NAME (slice 22's shape). The pair IS the
# A/B: `gimbal_handover_err_deg` is consumed ONCE at tick 1 and never read again, so it cannot be a
# knob (slice 19's dead-knob class, and `_parse_knobs` refuses it BY NAME), and the contrast has to be
# two files — slice 34's precedent. Each half asserts its own claim AND every shared invariant.
#
# THE LESSON. Since slice 34 the head has been handed its target PERFECTLY: tick 1 initialises it to
# the clamped truth look angles. Slice 35 found that a rate limit makes the resulting ACQUISITION TURN
# the largest slew demand in the whole engagement and gated it away with a band and a wide window.
# Make the handover an AUTHORED quantity and the question that was gated away has an answer nobody in
# the arc predicted: THE WINDOW A SEEKER NEEDS IS NOT |err|. The body-frame LOS is not a fixed target
# — it travels +18.11 deg -> -15.15 deg over the approach, a 33.2 deg EXCURSION, as the missile swings
# its nose onto the collision course. A head handed over ON the LOS must chase that whole journey and a
# rate-limited servo falls 12.35 deg behind doing it; a head handed over part-way ALONG it never falls
# further behind than the offset it started with. So the requirement is a V — left arm |err| (the
# tick-1 peak, an INITIAL CONDITION), right arm the CHASE COST — and the cheapest basket is the KINK.
#
# ⭐⭐ WHAT THIS FILE MEASURES, AND IT IS A PAIR OF VERDICTS AT THE SAME SERVO: at 8 deg/s behind a
# 10 deg window the PERFECT handover loses its track and misses by ~3290 m, while the SAME head handed
# over 6 deg "wrong" holds all the way in and hits. Zero is OUTSIDE the basket that holds.
#
# ⚠⚠ THE REQUIREMENT IS READ ONLY OFF ARMS THAT **HELD**, AND THAT IS NOT A CONVENIENCE — IT IS THE
# TWO-RUN DISCIPLINE's FIFTH QUANTITY, WHICH FAILS **LARGE**. `head_off_peak_deg` on a never-acquired
# arm is the POST-BREAK RUNAWAY: the head holds with no error signal while the LOS leaves, so it reads
# 65-120 deg against real requirements of 10-18 deg. Slice 34's frozen `head_angle_deg` failed
# plausibly-but-TOO-SMALL; this one fails large, so a reader who takes it for a requirement
# over-designs by ~8x. The window here is AUTHORED (not a knob), so this file has NO free-window arm at
# all — what licenses reading a requirement off a windowed arm is a measurement: on an arm that HELD,
# the windowed peak IS the free-window requirement, `===` in 6/6 cells (core suite, gate 3).
# ⚠⚠ AND THE PEAK IS AN **APPROACH** QUANTITY: it runs to ~179.5 deg at CPA on EVERY arm, hit or miss,
# because the target is behind the head by then. PHASE ENDGAME asserts exactly that, because it is why
# the client FREEZES the display at r > 200 m (`_handover_peak_hold`) — a HUD printing the raw key
# would end every clean intercept displaying a 179 deg "requirement": slice 19's lying picture.
#
# ⚠ NO GLASS ON THIS WIRE — the first radome-free missile wire of this arc and the first since slice 25
# (a handover error is EXACTLY inert on the trajectory without a window or an index, so the wire that
# isolates the basket has no radome at all). PHASE MARKER asserts the `radome_*` keys are ABSENT from
# the telemetry, which is also what makes slice 35's inherited HUD a FABRICATION rather than a reading:
# its "cure" line would print `R̂ +0.000   aim point +0.000` for keys that do not exist.
#
# ⚠ THE FLOOR FINDING IS NOT HERE AND THAT IS DELIBERATE: the biased wire breaks at 6 deg/s (its
# requirement crosses the window), which is WHY the domain stops at 8 — but 6 is OUTSIDE the declared
# slider domain, so it is not client-drivable and it lives in `test_missile.jl` (slice 27/28's
# relocation precedent). Same for the REVERSED-CROSSING control (target velocity is not a comp key) and
# for the CAGE-vs-AIM separation (two stops on one wire would break convention 9).
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and the constants below are sized off FRAME
# columns ([[ewsim-missile-verifier-sampling]] — the error is ASYMMETRIC: a MISS samples faithfully, a
# HIT samples COARSELY). Gate 2 measured the emit grid's under-read of the requirement at 0.0004-0.003
# deg, i.e. 0.03-0.27 % of the margin that decides a verdict, and the frame grid agrees with the ticks
# on the BREAK verdict in every cell — so the tolerances here are 0.01 deg and that is ~3x the measured
# gap.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 2400.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"                 # the interceptor — the one slider lives here

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16). The server emits every 16th tick,
# so a STEPS that is not a multiple makes the last frame land BELOW `STEPS*dt` and `_drain_scan` waits
# forever, SILENTLY, with no output at all (slice 31 lost an hour to exactly this and it reads like a
# slow wire). 12800 = 16 * 800.
# ⚠ SIZED OFF THE SLOWEST ARM, MEASURED: a HELD arm reaches CPA at ~10.58 s and a BROKEN one at ~8.4 s,
# so 12.8 s leaves ~2 s of headroom — and EVERY arm asserts it REACHED CPA rather than trusting that.
const STEPS := 12800

# THE SERVO SLIDER — the ONE live knob, and its DEFAULT IS ITS FLOOR because the showcase opens on the
# disease (slice 35's precedent): at 8 deg/s wire A is BROKEN and wire B HELD, at the same servo.
const RATE_LO := 8.0              # the floor AND the shipped default on both wires
const RATE_10 := 10.0             # the last BROKEN cell on wire A — the bracket's lower side
const RATE_11 := 11.0             # the first HELD cell on wire A — the RESCUE, and the bracket's top
const RATE_12 := 12.0
const RATE_40 := 40.0
const RATE_HI := 60.0

const WIN_AUTH := 10.0            # the AUTHORED detector window (not a knob — see the handshake)
const STOP_AUTH := 30.0           # the AUTHORED mechanical stop, which never binds on either wire
const MODEL_VALID_DEG := 30.0     # the small-angle bend budget 28/29/30/31 each declared

# ⚠ MEASURED CONSTANTS, labelled as such wherever they appear (here and in `test_missile.jl`). They
# come from FREE-WINDOW arms flown in the core suite and from the 210-cell fine grid at 0.5 deg/s
# (`docs/plans/slice36.md` §3 Finding 2) — flown fine BECAUSE THE REQUIREMENT IS NON-MONOTONE IN BOTH
# SLIDERS, so a corner sweep is not evidence about the interior (the advisor's blocking catch at this
# gate, and slice 35's own gate-3 finding one slice earlier).
const REQ_A_AT_FLOOR := 12.346    # wire A's requirement at 8 deg/s — UNREACHABLE on a windowed wire
const REQ_A_11 := 9.515           # …at 11 deg/s (HELD, so this file measures it directly)
const REQ_A_12 := 8.840
const REQ_A_60 := 2.112
const REQ_B_FLOOR := 8.091        # wire B's WORST cell anywhere in the domain, against a 10 deg window
const REQ_B_FLAT := 6.000         # …and its FLAT value from 11 deg/s up: |err| EXACTLY
const MISS_A_BROKEN := 3290.078   # wire A at its default: the PERFECT handover's miss
const MISS_HELD := 0.19116        # every arm that HOLDS, on EITHER wire, to 64 bits (core suite)
const AZ_BIRTH := 18.105          # the body-frame LOS azimuth at the handover (SIGNED)
const EXCURSION := 32.0           # …and it crosses through zero: the mechanism, as a span. ⚠ A FLOOR
                                  # on the FRAME grid, under the ~33.2 deg the core suite measures per
                                  # tick — and the arms also assert an UPPER bound, because on a BROKEN
                                  # arm this same span reads 132 deg (the runaway, ~4x)
const PEAK_CPA := 179.4998        # the endgame value of the running max, on EVERY arm
const TOL := 0.01                 # ~3x the measured emit-grid under-read of the requirement
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _wire := ""                   # "handover" (err = 0) or "biased" (err = -6) — auto-detected

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
var _max_off := 0.0               # the instantaneous tracking error's own frame-sampled maximum
var _peak_gated := 0.0            # …the CORE's running max, read at the last frame with r > 200 m
var _peak_raw := 0.0              # …and read at the LAST frame of all: the ENDGAME (see PHASE ENDGAME)
var _min_marg := 1.0e30           # the SIGNED detector budget — THE SIGN IS THE VERDICT
var _n_band := 0                  # closing frames with 500 < r < 3000 — the isolation window
var _n_aero := 0
var _n_defl := 0
var _err_seen := 0.0              # the AUTHORED handover error, READ OFF THE WIRE (never assumed)
var _rate_seen := 0.0
var _win_seen := 0.0
var _stop_seen := 0.0
var _az_first := NAN              # the SIGNED body-frame LOS azimuth at the first frame…
var _az_lo := 1.0e30              # …and its excursion: the MECHANISM
var _az_hi := -1.0e30
var _body_lo := 1.0e30            # the `hypot` beside it, which CANNOT show a sign
var _n_glass := 0                 # frames shipping ANY `radome_*` key — must be 0 (no glass)
var _pos_trace: Array = []

func _initialize() -> void:
	print("S36V_INIT godot=", Engine.get_version_info().string)
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

# ⚠ EVERY ARM DECLARES THE VERDICT IT EXPECTS (`held`), AND `_finish_arm` ASSERTS IT. That is not
# bookkeeping: the per-arm invariants DIFFER between the two verdicts and asserting the wrong set is
# how a broken arm's numbers get read as a design (see `_finish_arm`).
func _build_arms() -> void:
	# 1) THE SHIPPED WIRE, untouched (the servo at its floor, which is the default) — and its REPLAY.
	_arms.append({"tag": "open", "held": _wire == "biased"})
	_arms.append({"tag": "replay", "held": _wire == "biased"})
	if _wire == "handover":
		# 2) ⭐⭐ THE MEASURED BRACKET. The requirement CROSSES the authored window inside the slider's
		#    domain, so the track is lost below the bracket and held above it — and the bracket is
		#    quoted CELL TO CELL because the requirement is NON-MONOTONE in the rate.
		_arms.append({"tag": "r10", "rate": RATE_10, "held": false})
		_arms.append({"tag": "r11", "rate": RATE_11, "held": true})
		# 3) THE RIGHT ARM OF THE V, above the bracket: the requirement keeps FALLING as the servo
		#    speeds up, and no cell pokes back over the window (the fine grid's CONTIGUITY property,
		#    re-derived here from this run's own arms rather than trusted).
		_arms.append({"tag": "r12", "rate": RATE_12, "held": true})
		_arms.append({"tag": "r60", "rate": RATE_HI, "held": true})
	else:
		# 2') ⭐⭐ THE SLIDER THAT STOPS MATTERING. Every cell HELD, and the requirement FLAT at |err|
		#     from 11 deg/s up — the left arm of the V is an INITIAL CONDITION and no bandwidth
		#     touches an initial condition. That is the free direction slice 35 could not find.
		_arms.append({"tag": "r11", "rate": RATE_11, "held": true})
		_arms.append({"tag": "r40", "rate": RATE_40, "held": true})
		_arms.append({"tag": "r60", "rate": RATE_HI, "held": true})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	var cmds: Array = []
	if arm.has("rate"):
		cmds.append(_set_param_cmd(MID, "gimbal_rate_dps", float(arm["rate"])))
	_reset_scan_accum()
	_inbox.clear()
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = STEPS * _dt
	_client.send({"type": "step", "n": STEPS})

# Record the arm, and assert the invariants that must hold on EVERY arm — plus the ones that hold only
# on its OWN side of the verdict.
func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var want_held: bool = bool(arm["held"])
	var out_pc: float = 100.0 * float(_n_out) / maxf(float(_n_gate), 1.0)
	var m := {
		"miss": _min_los, "turned": _turned, "out": out_pc, "gate": _n_gate,
		"head": _max_head, "off": _max_off, "peak": _peak_gated, "peakraw": _peak_raw,
		"marg": NAN if _min_marg > 1.0e29 else _min_marg,
		"band": _n_band, "aero": _n_aero, "defl": _n_defl,
		"err": _err_seen, "rate": _rate_seen, "win": _win_seen, "stop": _stop_seen,
		"az0": _az_first, "azlo": _az_lo, "azhi": _az_hi, "bodylo": _body_lo,
		"glass": _n_glass, "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S36V_ARM   %-7s servo=%.1f deg/s  err=%+.1f deg  ->  miss=%.3f  requirement(peak)=%.3f  " +
		   "off_max=%.3f  window=%.1f  margin_min=%.2f  head_max=%.3f  out=%.3f%% of %d gated  " +
		   "band=%d  aero=%d  defl=%d  peak_at_CPA=%.4f  LOS az %+.3f..%+.3f (span %.3f)  cpa=%s") %
		  [tag, m["rate"], m["err"], m["miss"], m["peak"], m["off"], m["win"], m["marg"],
		   m["head"], out_pc, m["gate"], m["band"], m["aero"], m["defl"], m["peakraw"],
		   m["azhi"], m["azlo"], float(m["azhi"]) - float(m["azlo"]),
		   "Y" if m["turned"] else "N"])
	if not (_n_gate > 100):
		return ("arm %s: the r > 200 m window must contain frames to measure (got %d) — every angle, " +
				"budget and out-of-window assert on this arm would be vacuous") % [tag, _n_gate]
	if not _turned:
		return ("arm %s: the engagement must actually reach CPA inside %d steps — this arm was still " +
				"closing at the end, so its miss (%.3f m) is a last closing range and not a CPA at " +
				"all. ToF spans ~8.4 s (broken) to ~10.6 s (held), so STEPS is sized off the SLOWEST " +
				"arm and every arm asserts this rather than trusting the sizing") % [tag, STEPS, _min_los]
	# THE VERDICT ITSELF, ASSERTED RATHER THAN OBSERVED — and the shipped `gimbal_valid` is what says
	# it (convention 13: the client never re-tests the window).
	if want_held and out_pc != 0.0:
		return ("arm %s: this arm must HOLD its track (%.3f %% of gated frames out of window). The " +
				"requirement is read off HELD arms only, so a break here does not merely change a " +
				"number — it makes the number a POST-BREAK RUNAWAY (65-120 deg) wearing a " +
				"requirement's name") % [tag, out_pc]
	if not want_held and out_pc == 0.0:
		return ("arm %s: this arm must LOSE its track — it is the foil, and if it holds, the slice's " +
				"headline (that ZERO is outside the basket) is false on this wire") % tag
	# ⚠ THE ISOLATION IS `defl_sat`, and it must be EXACTLY 0 on every arm, held or broken (slice 32's
	# POINTING-miss isolation, and slice 33's warning that saturation can discriminate in NEITHER
	# direction). `aero_sat` is asserted as a COUNT and not a percentage — gate 1 paid a FAILING tooth
	# to learn that a `%5.1f` print of `0.0` was hiding 0.047 %, and read as counts the claim is
	# STRONGER: exactly ONE tick, the launch transient, at the same range on every arm.
	if _n_defl != 0:
		return ("arm %s: `defl_sat` must be EXACTLY 0 (got %d) — with the fin out of authority the " +
				"engagement stops being about where the head was pointed") % [tag, _n_defl]
	if _n_aero > 2:
		return ("arm %s: `aero_sat` fired on %d gated frames; it is the LAUNCH TRANSIENT (exactly one " +
				"tick, at r = 6383 m, INDEPENDENT of the handover error — measured bit-identical " +
				"across err 0/-2/-4/-6/-8) and anything more means this arm is fighting the aero " +
				"ceiling, which would be slice 19's mechanism and not the basket's") % [tag, _n_aero]
	# ⚠⚠ THE BAND IS THE OTHER WAY ROUND FROM EVERY SLICE 28-35 VERIFIER, AND THAT INVERSION IS THE
	# POSITIVE FACT §0.1 RESTS ON. A broken arm's CPA is 3.3 km, so it NEVER ENTERS [500, 3000] m —
	# the band is EMPTY, and a band metric on it would be "quiet from zero samples" (slice 33's
	# gate-2 catch, which slice 36's gate 1 then repeated in three vacuous asserts). So: the held arms
	# must HAVE a band, the broken ones must NOT, and this file computes no band statistic at all.
	# ⚠ IN **FRAMES**, NOT TICKS — the first draft asserted 1000 and failed at 271, which is exactly
	# 4341 ticks / 16. Every count in this file is frame-sampled and the thresholds have to be too.
	if want_held and _n_band < 100:
		return ("arm %s: a HELD arm must spend real time in the [500, 3000] m band (got %d frames)") % \
			   [tag, _n_band]
	if not want_held and _n_band != 0:
		return ("arm %s: a BROKEN arm's band must be EMPTY (got %d frames) — its CPA is ~3.3 km, which " +
				"is why NO band metric may carry this slice's claim and why the headline is the MISS " +
				"(slice 32's shape, not slice 33/35's)") % [tag, _n_band]
	# ⚠ THE MECHANICAL STOP MUST NOT BIND ON EITHER WIRE, or slice 34's two budgets stop being
	# separable (a clamped head cannot reach the LOS, so its deficit is charged to the DETECTOR
	# allowance). Measured margin: 11.9 deg on wire A, 14.8 deg on wire B, over 210 fine-grid cells.
	if not (_max_head < _stop_seen and _max_head < MODEL_VALID_DEG):
		return ("arm %s: the head's travel (%.3f deg) must stay inside BOTH the mechanical stop " +
				"(%.3f deg) and the small-angle bend budget 28/29/30/31 each declared (%.0f deg)") % \
			   [tag, _max_head, _stop_seen, MODEL_VALID_DEG]
	# ⚠⚠ NO GLASS, ASSERTED ON THE WIRE. This is what makes slice 35's inherited HUD a FABRICATION
	# rather than a reading: its "cure" line reads `radome_slope_est` / `radome_slope_worst`, and if
	# they are absent it prints +0.000 for each. The marker exists because of this absence, so the
	# absence is asserted rather than assumed.
	if _n_glass != 0:
		return ("arm %s: %d frames shipped a `radome_*` key — this wire must carry NO GLASS (the " +
				"first radome-free missile wire of this arc). With glass, the isolation would " +
				"discriminate in NEITHER direction (aero_sat 27-48 %% on the broken rows, slice 33's " +
				"inversion) and the basket would not be the only mechanism on screen") % [tag, _n_glass]
	# ⭐⭐ THE MECHANISM: the SIGNED body-frame LOS azimuth is born at the perfect handover angle and
	# CROSSES THROUGH ZERO. ⚠ It is a property of the ENGAGEMENT, not of the head, so on arms that HOLD
	# it is the same journey at every servo rate and on both wires — which is exactly why the basket's
	# rate-dependence is a statement about the engagement.
	# ⚠⚠ AND IT IS THE TWO-RUN DISCIPLINE's **SIXTH** QUANTITY, WHICH THIS FILE'S FIRST RUN GOT WRONG:
	# on a BROKEN arm the missile is in a runaway geometry, so this same azimuth reads −114.162 deg and
	# an "excursion" of 132.165 deg — four times the mechanism. That is slice 32's finding ("a broken
	# arm's own lead is inflated by the runaway it is in") and slice 29's P10a, in a new quantity, and it
	# fails LARGE exactly as the running max does. ⇒ THE MECHANISM IS READ OFF ARMS THAT HELD, and the
	# broken arms assert the RUNAWAY instead — as the positive fact it is.
	if is_nan(_az_first):
		return ("arm %s: the wire must ship `look_body_az_deg` — the SIGNED body-frame LOS azimuth. " +
				"Without it the HUD cannot draw the mechanism at all: `look_body_deg` beside it is a " +
				"`hypot`, and gate 0 got the mechanism WRONG on exactly that evidence (a hypot cannot " +
				"show a sign — the #1 SIGN TRAP's 10th occurrence)") % tag
	if not (absf(_az_first - AZ_BIRTH) < 0.2):
		return ("arm %s: the first frame's body-frame LOS azimuth is %.3f deg, expected ~%.3f — this " +
				"is the launch attitude's own number (elevation_deg = 12, load-consumed) and it is " +
				"what the handover error is measured against") % [tag, _az_first, AZ_BIRTH]
	if want_held:
		if not (_az_hi - _az_lo > EXCURSION):
			return ("arm %s: the body-frame LOS azimuth must travel more than %.1f deg (got %.3f: " +
					"%.3f -> %.3f). That EXCURSION is the whole mechanism — a head handed over ON the " +
					"LOS must chase the entire journey, one handed over part-way along it starts with " +
					"a head start") % [tag, EXCURSION, _az_hi - _az_lo, _az_hi, _az_lo]
		if not (_az_hi - _az_lo < 2.0 * EXCURSION):
			return ("arm %s: …and it must NOT read a runaway (got %.3f deg). On a HELD arm this is the " +
					"engagement's own journey; a figure several times larger means the arm is in a " +
					"post-break geometry and the number is not the mechanism at all") % [
				   tag, _az_hi - _az_lo]
		if not (_az_lo < -14.0 and _az_hi > 15.0):
			return ("arm %s: the excursion must CROSS THROUGH ZERO (got %.3f -> %.3f). A journey that " +
					"merely settled would be gate 0's refuted story, and it is the crossing that " +
					"makes a BIASED handover a head start rather than an error") % [tag, _az_hi, _az_lo]
	else:
		# ⚠⚠ THE POSITIVE FACT ON A BROKEN ARM, asserted rather than skipped: the azimuth RUNS AWAY
		# past anything the engagement itself produces, which is precisely why the mechanism may not be
		# read here. Slice 33's discipline — the free read is itself MEASURED, never assumed.
		if not (_az_hi - _az_lo > 3.0 * EXCURSION):
			return ("arm %s: a BROKEN arm's azimuth must RUN AWAY (got a %.3f deg span). If it did not, " +
					"reading the mechanism off a broken arm would be harmless — and the whole reason " +
					"this file reads it off HELD arms only is that here it inflates ~4x") % [
				   tag, _az_hi - _az_lo]
	if not (_body_lo >= 0.0 and _body_lo < 1.0):
		return ("arm %s: `look_body_deg` (the `hypot`) must stay non-negative AND pass through the " +
				"nose (got min %.4f) — that is the sign trap pinned rather than narrated: the same " +
				"journey reads as a gentle settle through an unsigned lens") % [tag, _body_lo]
	return ""

# --- the verdict ----------------------------------------------------------------------------

func _verdict() -> bool:
	var op: Dictionary = _res["open"]
	var rp: Dictionary = _res["replay"]
	var r11: Dictionary = _res["r11"]
	var r60: Dictionary = _res["r60"]

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE REPLAY — held-seed bit-identity across a `reset` (convention 14). Class 4a: the seeker
	# draws 2 randn/tick and the seed is load-bearing, so this is SEEDED determinism and not
	# "RNG-free".
	var d := _pos_max_diff(op["pos"], rp["pos"])
	print("S36V_REPLAY   max|Δpos| over %d frames = %.3f m" % [op["pos"].size(), d])
	if not (d == 0.0):
		return _fail("REPLAY: the same seed and the same scenario must reproduce the trace BIT-IDENTICALLY (max|Δpos| = %.6f m over %d frames)" % [d, op["pos"].size()])
	if not (op["miss"] == rp["miss"]):
		return _fail("REPLAY: the CPA must be bit-identical (%.9f vs %.9f)" % [op["miss"], rp["miss"]])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE ENDGAME — the display problem, measured. ⚠⚠ `head_off_peak_deg` is a RUNNING MAXIMUM, so
	# it reads the clean requirement unchanged from r = 3000 m down to r = 200 m and then runs to
	# ~179.5 deg AT CPA ON EVERY ARM, HIT OR MISS: the target is simply behind the head by then, and A
	# PEAK CANNOT FORGET. That is why the client freezes its display at r > 200 m
	# (`_handover_peak_hold`, proven headless in `slice36_ui_test.gd`) and why gate 2 DROPPED a signed
	# peak-MARGIN key: it would have latched on 100 % of arms, including every hit.
	# ⚠⚠ THE ASSERT IS AGAINST THE **WINDOW**, NOT AGAINST 179.4998, AND THAT IS A SAMPLING FACT RATHER
	# THAN A WEAKER CLAIM. The 179.4998 deg figure is PER-TICK at the exact CPA (gate 2's own
	# measurement); on a FRAME grid the last sample lands wherever `emit_every` puts it, and this run
	# measures 179.98 on a HELD arm against ~129 on a BROKEN one (whose CPA is 3.3 km, so its LOS swing
	# is gentler). What the phase claims — and what the client's freeze exists for — is that the raw key
	# becomes ABSURD AS A REQUIREMENT, so it is asserted against the thing a reader would compare it to.
	for tag in _res.keys():
		var a: Dictionary = _res[tag]
		if not (float(a["peakraw"]) > 10.0 * float(a["win"])):
			return _fail(("ENDGAME %s: the raw running max at the LAST frame is %.4f deg and must " +
						  "exceed TEN TIMES the %.1f deg window. If it ever stops doing so the " +
						  "client's display freeze stops being necessary — and while it does, a HUD " +
						  "that printed the raw key would end every clean intercept showing a " +
						  "three-figure 'requirement': slice 19's lying picture in a new widget. " +
						  "(Per-tick at the exact CPA the core measures %.4f deg on every arm.)") %
						 [tag, a["peakraw"], a["win"], PEAK_CPA])
		if not (float(a["peakraw"]) > float(a["peak"])):
			return _fail(("ENDGAME %s: the endgame value (%.4f) must EXCEED the gated one (%.4f), or " +
						  "the two are not measuring what this phase claims") %
						 [tag, a["peakraw"], a["peak"]])
	# ⚠ QUOTED OFF AN ARM THAT **HELD**, for the same reason PHASE MECHANISM is: on a broken arm the
	# gated value is itself the post-break runaway, so the pair would not be showing the display problem
	# — it would be showing two runaways. On a held arm the gated number IS the requirement.
	print("S36V_ENDGAME  on a HELD arm the running max reads %.3f deg while r > 200 m and %.4f deg at the last frame — an APPROACH quantity, and the reason the HUD freezes its display (per-tick at the exact CPA the core measures %.4f on every arm)" %
		  [float(r11["peak"]), float(r11["peakraw"]), PEAK_CPA])

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# PHASE MECHANISM — the excursion, quoted from this run's own arms. ⚠⚠ **OFF AN ARM THAT HELD**,
	# ALWAYS, and this file's first run quoted the shipped (broken) arm and printed a 132.165 deg
	# "excursion" — the two-run discipline's SIXTH quantity, inflated ~4x by the runaway the arm is in
	# (slice 32's finding about the lead angle, and slice 29's P10a, in a new quantity). On a HELD arm it
	# is the ENGAGEMENT's own journey, identical at every servo rate and on both wires.
	var mech: Dictionary = r11        # HELD on both wires, at both wires' bracket cell
	print("S36V_MECH     body-frame LOS azimuth %+.3f deg -> %+.3f deg (a %.3f deg EXCURSION, THROUGH ZERO) on a HELD arm, while the `hypot` beside it bottoms out at %.4f and can show none of it" %
		  [float(mech["azhi"]), float(mech["azlo"]),
		   float(mech["azhi"]) - float(mech["azlo"]), float(mech["bodylo"])])
	if _wire == "handover":
		print("S36V_MECH2    …and the SHIPPED arm's own span reads %.3f deg — the RUNAWAY it is in, ~%.1fx the mechanism, which is why no excursion may be read off a broken arm (the two-run discipline's SIXTH quantity)" %
			  [float(op["azhi"]) - float(op["azlo"]),
			   (float(op["azhi"]) - float(op["azlo"])) / maxf(float(mech["azhi"]) - float(mech["azlo"]), 1.0e-9)])

	if _wire == "handover":
		var r10: Dictionary = _res["r10"]
		var r12: Dictionary = _res["r12"]
		# ─────────────────────────────────────────────────────────────────────────────────────
		# PHASE FOIL — ⭐⭐ THE PERFECT HANDOVER LOSES ITS TRACK. Same servo, same window, same seed as
		# the biased twin; the ONLY difference is that this head was handed its target exactly right.
		if not (absf(float(op["err"])) < EXACT):
			return _fail("FOIL: this wire must author err = 0 (the wire reports %+.6f) — it is the FOIL, and the whole headline is that ZERO is outside the basket" % float(op["err"]))
		if not (absf(float(op["miss"]) - MISS_A_BROKEN) < 1.0):
			return _fail("FOIL: the perfect handover must miss by ~%.1f m (got %.3f)" % [MISS_A_BROKEN, float(op["miss"])])
		# ⚠⚠ AND ITS OWN PEAK IS **NOT** A REQUIREMENT — the two-run discipline's fifth quantity,
		# failing LARGE. Asserted as a factor against the MEASURED free-window requirement (a core-suite
		# constant, labelled), because that is the mistake a reader of a break table actually makes.
		if not (float(op["peak"]) > 100.0):
			return _fail("FOIL: a broken arm's running max must be the POST-BREAK RUNAWAY (got %.3f deg) — the head holds with no error signal while the LOS leaves" % float(op["peak"]))
		if not (float(op["peak"]) > 8.0 * REQ_A_FLOOR_REF()):
			return _fail("FOIL: the runaway (%.3f deg) must exceed the real requirement (%.3f deg, MEASURED free-window in the core suite) by more than 8x — that factor IS the over-design a reader who mistakes one for the other would buy" % [float(op["peak"]), REQ_A_FLOOR_REF()])
		# ─────────────────────────────────────────────────────────────────────────────────────
		# PHASE BRACKET — ⭐⭐ THE CURE, AND IT IS A MEASURED BRACKET. The requirement CROSSES the
		# authored window inside the slider's domain, so buying a faster servo buys the track back —
		# and the crossing is quoted CELL TO CELL because the requirement is NON-MONOTONE in the rate
		# (the fine grid found the ≥-window set CONTIGUOUS and anchored at the floor; this run
		# re-derives the same property from its own arms).
		if not (float(r10["out"]) > 0.0 and float(r11["out"]) == 0.0):
			return _fail("BRACKET: the verdict must turn between %.0f and %.0f deg/s (got out = %.3f %% and %.3f %%)" % [RATE_10, RATE_11, float(r10["out"]), float(r11["out"])])
		for cell in [[r11, REQ_A_11], [r12, REQ_A_12], [r60, REQ_A_60]]:
			var a: Dictionary = cell[0]
			var want: float = float(cell[1])
			if not (absf(float(a["peak"]) - want) < TOL):
				return _fail("BRACKET: the requirement at %.0f deg/s is %.3f deg, expected %.3f (MEASURED free-window; on a HELD arm the windowed peak IS the free-window requirement, `===` in 6/6 core-suite cells)" % [float(a["rate"]), float(a["peak"]), want])
			if not (float(a["peak"]) < float(a["win"])):
				return _fail("BRACKET: a HELD arm's requirement (%.3f deg) must be inside its window (%.3f deg) — slice 32's predicate, in the basket's own currency, and read off THIS arm rather than asserted" % [float(a["peak"]), float(a["win"])])
		# ⭐ THE RIGHT ARM OF THE V IS MONOTONE ABOVE THE BRACKET, and no cell pokes back over the
		# window. The fine grid is what established contiguity over 105 cells; these four arms are what
		# this run can say for itself, and the file quotes both rather than trusting either alone.
		if not (float(r11["peak"]) > float(r12["peak"]) and float(r12["peak"]) > float(r60["peak"])):
			return _fail("BRACKET: the requirement must FALL as the servo speeds up above the bracket (got %.3f / %.3f / %.3f at %.0f / %.0f / %.0f deg/s)" % [float(r11["peak"]), float(r12["peak"]), float(r60["peak"]), RATE_11, RATE_12, RATE_HI])
		# ─────────────────────────────────────────────────────────────────────────────────────
		# PHASE FREE — ⭐ THE PRICE OF THE CURE IS EXACTLY ZERO, AND SO IS THE PRICE OF THE BIAS.
		# On a glass-free wire the head reaches the trajectory through the DETECTOR WINDOW and through
		# nothing else, so every arm that HOLDS flies the SAME TRAJECTORY — regardless of servo rate.
		# ⚠ `== 0.0`, not a tolerance: this is bit-identity, and it is the strongest form of slice 32's
		# "the cost column is 0".
		var dfree := _pos_max_diff(r11["pos"], r60["pos"])
		if not (dfree == 0.0):
			return _fail("FREE: two HELD arms at %.0f and %.0f deg/s must fly BIT-IDENTICAL trajectories (max|Δpos| = %.9f m) — with no glass the head reaches the trajectory through the detector window and nothing else, so a difference here means an unaccounted head->trajectory path" % [RATE_11, RATE_HI, dfree])
		# ⚠⚠ THE CPA IS COMPARED **BETWEEN ARMS**, NEVER AGAINST THE PER-TICK NUMBER, and that is
		# [[ewsim-missile-verifier-sampling]]'s asymmetry: a MISS samples faithfully (the foil's 3290.079
		# against a per-tick 3290.078) while a HIT samples COARSELY — this grid reads 0.762 m where the
		# core suite measures 0.19116 to 64 bits. The bit-identity between two held arms is the strong
		# claim and it survives the grid; a tolerance against MISS_HELD would only measure `emit_every`.
		if not (float(r11["miss"]) == float(r60["miss"])):
			return _fail("FREE: two held arms must land on the SAME frame-sampled CPA to the bit (got %.9f and %.9f) — their trajectories are bit-identical, so anything else means the sampling is not the only difference" % [float(r11["miss"]), float(r60["miss"])])
		if not (float(r11["miss"]) < 40.0):
			return _fail("FREE: a held arm must HIT (frame-sampled CPA %.3f m against a per-tick %.5f m measured in the core suite; the bound is a sanity check, never the metric)" % [float(r11["miss"]), MISS_HELD])
		print("S36V_FOIL     err %+.1f at %.0f deg/s: BROKEN, miss %.3f m, and its running max reads %.3f deg — the POST-BREAK RUNAWAY, %.1fx the real %.3f deg requirement" %
			  [float(op["err"]), float(op["rate"]), float(op["miss"]), float(op["peak"]), float(op["peak"]) / REQ_A_FLOOR_REF(), REQ_A_FLOOR_REF()])
		print("S36V_BRACKET  the servo buys it back: BROKEN at %.0f deg/s -> HELD at %.0f (requirement %.3f -> %.3f against a %.1f deg window), falling to %.3f at %.0f deg/s" %
			  [RATE_10, RATE_11, float(r10["peak"]), float(r11["peak"]), float(r11["win"]), float(r60["peak"]), RATE_HI])
	else:
		var r40: Dictionary = _res["r40"]
		# ─────────────────────────────────────────────────────────────────────────────────────
		# PHASE HOLD — ⭐⭐ THE BIASED HANDOVER KEEPS THE TRACK THE PERFECT ONE LOSES, at the SAME
		# servo, behind the SAME window, on the SAME seed. `_finish_arm` already asserted every arm
		# held; this phase is about the SHAPE of the requirement.
		if not (absf(float(op["err"]) + 6.0) < EXACT):
			return _fail("HOLD: this wire must author err = -6 (the wire reports %+.6f)" % float(op["err"]))
		# ⚠ A SANITY BOUND, NEVER A TOLERANCE AGAINST THE PER-TICK NUMBER — a HIT samples COARSELY
		# ([[ewsim-missile-verifier-sampling]]): the core suite measures 0.19116 m to 64 bits while this
		# frame grid reads sub-metre-to-metres. What is pinned tightly is the BETWEEN-ARM identity below.
		if not (float(op["miss"]) < 40.0):
			return _fail("HOLD: the biased handover must HIT (per-tick %.5f m in the core suite; this frame grid read %.3f m, and the bound is a sanity check rather than the metric)" % [MISS_HELD, float(op["miss"])])
		if not (absf(float(op["peak"]) - REQ_B_FLOOR) < TOL):
			return _fail("HOLD: the requirement at the servo FLOOR is %.3f deg, expected %.3f (MEASURED) — this is the WORST cell anywhere in the declared domain, and it is what the 10 deg window has to clear" % [float(op["peak"]), REQ_B_FLOOR])
		if not (float(op["win"]) - float(op["peak"]) > 1.9):
			return _fail("HOLD: the window must clear the worst requirement by more than 1.9 deg (got %.3f against %.3f) — the margin is MEASURED on a 0.5 deg/s fine grid, not at the corners, because the requirement is non-monotone in both sliders" % [float(op["win"]), float(op["peak"])])
		# ─────────────────────────────────────────────────────────────────────────────────────
		# PHASE FLAT — ⭐⭐ THE SLIDER STOPS MATTERING, AND THE FLATNESS IS EXACT. From 11 deg/s up the
		# requirement IS `|err|`: the left arm of the V is an INITIAL CONDITION — the tick-1 peak,
		# before the servo has done anything — and no bandwidth touches an initial condition. THAT is
		# the free direction slice 35 could not find, and it is not on slice 35's axis.
		for a in [r11, r40, r60]:
			if not (absf(float(a["peak"]) - REQ_B_FLAT) < TOL):
				return _fail("FLAT: at %.0f deg/s the requirement is %.3f deg, expected |err| = %.3f exactly" % [float(a["rate"]), float(a["peak"]), REQ_B_FLAT])
		if not (float(r11["peak"]) == float(r40["peak"]) and float(r40["peak"]) == float(r60["peak"])):
			return _fail("FLAT: the requirement must be IDENTICAL across the servo domain above the bracket (got %.9f / %.9f / %.9f) — 'flat' here is not an approximation, it is the same initial condition read three times" % [float(r11["peak"]), float(r40["peak"]), float(r60["peak"])])
		# …and the trajectory is identical too, on every held arm: the price of the bias is exactly 0.
		var dflat := _pos_max_diff(r11["pos"], r60["pos"])
		if not (dflat == 0.0):
			return _fail("FLAT: two HELD arms at %.0f and %.0f deg/s must fly BIT-IDENTICAL trajectories (max|Δpos| = %.9f m)" % [RATE_11, RATE_HI, dflat])
		if not (float(r11["miss"]) == float(r60["miss"]) and float(r60["miss"]) == float(op["miss"])):
			return _fail("FLAT: and every held arm on this wire must land on the SAME frame-sampled CPA to the bit (got %.9f / %.9f / %.9f) — the price of the bias is EXACTLY zero and so is the price of the servo" % [float(op["miss"]), float(r11["miss"]), float(r60["miss"])])
		print("S36V_HOLD     err %+.1f at %.0f deg/s: HELD, miss %.3f m, requirement %.3f deg against a %.1f deg window (%.3f deg of margin — the WORST cell in the whole domain)" %
			  [float(op["err"]), float(op["rate"]), float(op["miss"]), float(op["peak"]), float(op["win"]), float(op["win"]) - float(op["peak"])])
		print("S36V_FLAT     and the slider stops mattering: %.3f / %.3f / %.3f deg at %.0f / %.0f / %.0f deg/s — |err| EXACTLY, an initial condition no bandwidth touches" %
			  [float(r11["peak"]), float(r40["peak"]), float(r60["peak"]), RATE_11, RATE_40, RATE_HI])
		# ⭐⭐ AND THIS WIRE REVISES GATE 2's OWN GO/NO-GO, WHICH IS WORTH MORE THAN THE ASSERT. Gate 2
		# asked whether the running max could be justified by slice 33's EMIT-GRID finding, measured the
		# frame-vs-tick gap at 0.0004-0.003 deg (0.03-0.27 % of the deciding margin) and answered NO —
		# so the key ships on CONVENTION 13 instead. ⚠⚠ THAT MEASUREMENT WAS TAKEN ON CELLS WHERE THE
		# PEAK IS A SMOOTH MID-FLIGHT MAXIMUM (the chase cost), AND IT DOES NOT GENERALIZE TO THIS WIRE:
		# above the bracket the requirement is the TICK-1 PEAK — an INITIAL CONDITION, one tick wide —
		# and a client receiving one tick in sixteen never sees it. The instantaneous frame maximum
		# under-reads it by 0.25-1.00 deg here (a student would read 5.0 deg where the design number is
		# 6.0), against 0.009 deg on the foil wire. ⇒ gate 2's verdict was right about the cells it
		# measured; the biased wire is where an emit-grid justification is genuinely earned.
		for a in [r11, r40, r60]:
			if not (float(a["peak"]) - float(a["off"]) > 0.2):
				return _fail(("FLAT: at %.0f deg/s the shipped running max (%.3f) must EXCEED the " +
							  "frame-sampled instantaneous maximum (%.3f) by a real margin — the " +
							  "requirement here is a ONE-TICK initial condition and the client sees " +
							  "one tick in sixteen, which is why the core holds the max. If the two " +
							  "agreed, a client-side maximum would be a legitimate substitute") %
							 [float(a["rate"]), float(a["peak"]), float(a["off"])])
		print("S36V_ONETICK  and the frame grid CANNOT SEE that requirement: the shipped running max reads %.3f / %.3f / %.3f deg where the frame-sampled instantaneous max reads %.3f / %.3f / %.3f — a %.3f-%.3f deg under-read of a ONE-TICK initial condition, against 0.009 deg on the foil wire's smooth chase peak (gate 2 measured only the latter and concluded the emit grid was NOT the reason for the key)" %
			  [float(r11["peak"]), float(r40["peak"]), float(r60["peak"]),
			   float(r11["off"]), float(r40["off"]), float(r60["off"]),
			   float(r11["peak"]) - float(r11["off"]), float(r60["peak"]) - float(r60["off"])])
	return _pass()

# The MEASURED free-window requirement at wire A's default servo — a core-suite constant, and it is
# UNREACHABLE from a live wire because the window is AUTHORED (not a knob). Wrapped in a function so
# every use is a call to one labelled place rather than a bare number in a message.
func REQ_A_FLOOR_REF() -> float:
	return REQ_A_AT_FLOOR

# --- the drain ------------------------------------------------------------------------------

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_turned = false
	_n_gate = 0
	_n_out = 0
	_max_head = 0.0
	_max_off = 0.0
	_peak_gated = 0.0
	_peak_raw = 0.0
	_min_marg = 1.0e30
	_n_band = 0
	_n_aero = 0
	_n_defl = 0
	_err_seen = 0.0
	_rate_seen = 0.0
	_win_seen = 0.0
	_stop_seen = 0.0
	_az_first = NAN
	_az_lo = 1.0e30
	_az_hi = -1.0e30
	_body_lo = 1.0e30
	_n_glass = 0
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
		if tel.has(MID + ".gimbal_handover_err_deg"):
			_err_seen = float(tel[MID + ".gimbal_handover_err_deg"])
		if tel.has(MID + ".gimbal_rate_dps"):
			_rate_seen = float(tel[MID + ".gimbal_rate_dps"])
		if tel.has(MID + ".gimbal_fov_deg"):
			_win_seen = float(tel[MID + ".gimbal_fov_deg"])
		if tel.has(MID + ".gimbal_stop_deg"):
			_stop_seen = float(tel[MID + ".gimbal_stop_deg"])
		# ⚠ THE ENDGAME SAMPLE IS TAKEN **UNGATED AND LAST**, which is the whole point of PHASE
		# ENDGAME: the running max is an APPROACH quantity and its post-CPA value is the thing the
		# client must never print. Read here, asserted there.
		if tel.has(MID + ".head_off_peak_deg"):
			_peak_raw = float(tel[MID + ".head_off_peak_deg"])
		# NO GLASS — counted rather than assumed, because the marker's whole justification is that
		# slice 35's HUD would print these keys as +0.000 when they are absent.
		for gk in ["radome_slope", "radome_slope_est", "radome_slope_worst", "radome_residual",
				   "radome_eps"]:
			if tel.has(MID + "." + gk):
				_n_glass += 1
		if tel.has(MID + ".los_range"):
			var r := float(tel[MID + ".los_range"])
			if r > _prev_los:
				_closing = false
				_turned = true
			if _closing:
				_min_los = minf(_min_los, r)
				# ⭐⭐ THE MECHANISM — SIGNED, and gated on the CLOSING LEG **AND** r > 200 m. Both halves
				# were paid for. ⚠ The launch transient IS the subject here (§0.1's inversion of the usual
				# caution: 26-35 all had to gate it AWAY to see their loop, and the band that protected
				# them would delete this slice), so the gate must not exclude the START. ⚠⚠ BUT WITHOUT
				# THE **CLOSING** GATE THIS READS THE POST-CPA GEOMETRY, and the first run of this file
				# measured a 359.778 deg "excursion" on a HELD arm — the azimuth wrapping through ±180 deg
				# once the target is BEHIND the missile. That is slice 32's gate-3 correction verbatim
				# (its 180 deg identity holds ON THE CLOSING LEG and is false over the whole run) and
				# [[ewsim-missile-verifier-sampling]]'s post-CPA re-crossing, in a new quantity. ⚠ And the
				# r > 200 m half is separately needed: the core suite's own first draft of this tooth was
				# ungated by range and FAILED at a 182 deg span from the endgame swing.
				if r > 200.0:
					if tel.has(MID + ".look_body_az_deg"):
						var az := float(tel[MID + ".look_body_az_deg"])
						if is_nan(_az_first):
							_az_first = az
						_az_lo = minf(_az_lo, az)
						_az_hi = maxf(_az_hi, az)
					if tel.has(MID + ".look_body_deg"):
						_body_lo = minf(_body_lo, float(tel[MID + ".look_body_deg"]))
				# WINDOW 1 — the WHOLE-APPROACH window, RANGE-GATED at r > 200 m. ⚠ Ungated, the
				# endgame LOS swing makes a QUIET arm read a few tenths of a percent out and its
				# tracking error read TENS of degrees (slice 33's five failing asserts, slice 34's
				# inherited fix) — and it makes the running max read 179.5 deg on every arm.
				# ⚠⚠ THIS IS WHERE THE REQUIREMENT LIVES ON THIS WIRE, and unlike slices 33/34/35
				# there is no band alternative: acquisition is over by r ~ 4900 m, so the [500, 3000] m
				# band that carried their metrics begins AFTER this slice's subject has finished.
				if r > 200.0:
					_n_gate += 1
					_max_head = maxf(_max_head, float(tel.get(MID + ".head_angle_deg", 0.0)))
					_max_off = maxf(_max_off, float(tel.get(MID + ".head_off_deg", 0.0)))
					if tel.has(MID + ".head_off_peak_deg"):
						_peak_gated = maxf(_peak_gated, float(tel[MID + ".head_off_peak_deg"]))
					if tel.has(MID + ".gimbal_fov_margin_deg"):
						_min_marg = minf(_min_marg, float(tel[MID + ".gimbal_fov_margin_deg"]))
					# ⚠ `gimbal_valid`, NEVER `seeker_valid`: different booleans about different
					# windows, and the loader refuses the combination.
					if float(tel.get(MID + ".gimbal_valid", 1.0)) < 0.5:
						_n_out += 1
					if float(tel.get(MID + ".aero_sat", 0.0)) > 0.5:
						_n_aero += 1
					if float(tel.get(MID + ".defl_sat", 0.0)) > 0.5:
						_n_defl += 1
				# WINDOW 2 — 28-35's [500, 3000] m band, kept for ONE purpose only: to assert that a
				# BROKEN arm never enters it. No metric is computed here (see `_finish_arm`).
				if r > 500.0 and r < 3000.0:
					_n_band += 1
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
	var nm := str(f.get("name", ""))
	if nm == "slice36_handover":
		_wire = "handover"
	elif nm == "slice36_biased":
		_wire = "biased"
	else:
		return "expected 'slice36_handover' or 'slice36_biased', got '%s' — ONE verifier auto-detects which half of the pair it is on (slice 22's shape), and the pair IS the A/B because the authored key cannot be a knob" % nm
	if not bool(f.get("airframe_view", false)):
		return "a slice-36 handshake must ship airframe_view=true (the airframe view discriminator)"
	if not bool(f.get("airframe_6dof", false)):
		return "a slice-36 handshake must ship airframe_6dof=true (the 3-D-airframe discriminator)"
	if not bool(f.get("gimbal_view", false)):
		return "a slice-36 wire carries a HEAD, so it must ship gimbal_view=true"
	if not bool(f.get("gimbal_rate_view", false)):
		return "a slice-36 wire carries a RATE-LIMITED head, so it must ship gimbal_rate_view=true — and note that this is exactly why a NEW marker was needed: `gimbal_rate_view` alone would route this wire to slice 35's HUD"
	# ⭐⭐ THE NEW MARKER, AND ⚠⚠ THE RE-CHECK CAME BACK **POSITIVE** — the opposite of slice 35's, and
	# it does TWO jobs where every earlier marker in this family did one. THE BUTTON: slices 26-35 all
	# dropped the shared fidelity button by riding `radome_view`, which is keyed on authored GLASS.
	# This is the arc's first no-glass wire, so `radome_view` is ABSENT and `seeker_fov_view` is absent
	# too (the loader refuses `seeker_fov_deg` beside a head) — both of the client's drop branches fail,
	# its dispatch falls through to slice 25's `seeker_axes` cycler, and the button COMES BACK, whose
	# other position (`:pitch_plane`) leaves the handover error live beside slice 25's unrelated 2000 m
	# blind miss. THE HUD: `gimbal_rate_view` IS raised here, so slice 35's block would take the wire
	# and its own "cure" line would print `R̂ +0.000   aim point R0+2A +0.000` for keys that DO NOT
	# EXIST (the stale-readout class's 9th occurrence, on another slice's payoff line).
	if not bool(f.get("gimbal_handover_view", false)):
		return "a slice-36 handshake must ship gimbal_handover_view=true — it plugs a BUTTON hole at both client sites (this is the first no-glass wire of the arc, so `radome_view` no longer drops the button for free) AND selects the HUD branch (without it slice 35's lines take the wire and fabricate two zeros of absent glass). Slice 35's 'a branch selector, not a hole plug' does NOT transfer to it"
	# ⭐⭐ THE TWO ABSENCES ARE THE FINDING, asserted as the POSITIVE facts they are.
	if f.has("radome_view"):
		return "a slice-36 wire must NOT raise radome_view — it carries NO GLASS, and that absence is precisely why the button drop stopped being free (slices 26-35 all rode this marker for it)"
	if f.has("seeker_fov_view"):
		return "a slice-36 wire must NOT raise seeker_fov_view — the loader refuses `seeker_fov_deg` beside a head (a gimballed seeker has no body-fixed window; its body-fixed limit is the mechanical STOP)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("seeker_axes", "")) != "az_el":
		return "a slice-36 scenario must HOLD :seeker_axes at az_el — a two-angle seeker is what HAS a look angle at all, and the loader refuses the gimbal keys without `two_angle: true`. Got %s" % str(fid.get("seeker_axes", "<absent>"))
	if str(fid.get("airframe", "")) != "six_dof":
		return "a slice-36 scenario must HOLD :airframe at six_dof — the head AND the attitude it is measured against are gated on that LIVE rung, so they freeze and resume together. Got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-36 scenario must AUTHOR the autopilot at :alpha, got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-36 scenario must hold :guidance at :pn, got %s" % str(fid.get("guidance", "<absent>"))
	if str(fid.get("seeker", "")) != "filtered":
		return "a slice-36 scenario must HOLD :seeker at :filtered, got %s" % str(fid.get("seeker", "<absent>"))
	if fid.has("steering"):
		return "a slice-36 scenario must OMIT the `steering` key (the loader default :skid_to_turn is the held plant — a bank_to_turn wire binds the aero ceiling 93.2 % of its approach, a THIRD mechanism)"
	if f.has("range_axis_m") or f.has("pri_axis_us") or f.has("terrain_grid"):
		return "a slice-36 scenario must NOT ship range_axis_m / pri_axis_us / terrain_grid (each flips the client to a different view)"
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = str(k.get("target", ""))
	if not keys.has("gimbal_rate_dps"):
		return "the slice-36 wire must expose the 'gimbal_rate_dps' slider — slice 35's servo, and here it is the CURE on one wire and the knob that stops mattering on the other"
	if str(keys["gimbal_rate_dps"]) != MID:
		return "the servo knob must target the interceptor '%s'" % MID
	if keys.size() != 1:
		return "the slice-36 wire must expose EXACTLY ONE knob (got %d) — convention 9 satisfied by a MEASUREMENT rather than by counting sliders: gate 0 measured that the authored error and the servo are ONE AXIS, because the servo MOVES THE ARGMIN of the basket (-2 deg at 40 deg/s, -8 deg at 8 deg/s, a 1.54x saving), and slice 35 is the err = 0 ROW of this slice's own grid" % keys.size()
	# ⚠⚠ THE AUTHORED KEY MUST NOT BE A KNOB, AND THAT IS ENFORCED IN THE LOADER BY NAME. It is
	# consumed exactly once, at tick 1, and never read again — slice 19's `speed` and slice 21's launch
	# altitude, the 5th occurrence in this arc and the first caught BEFORE the key was written. Slice
	# 19's NOT-A-DEAD-KNOB TRIPWIRE would FAIL on it, which is why this file runs NO set-param sweep on
	# it and the contrast is two scenarios instead.
	if keys.has("gimbal_handover_err_deg"):
		return "slice 36 must NOT expose a 'gimbal_handover_err_deg' knob — it is structurally DEAD (consumed once at tick 1), `_parse_knobs` refuses it BY NAME (the first by-name refusal in the project), and the existing guard would NOT have caught it because that guard only rejects knobs whose comp key does not exist"
	if keys.has("gimbal_fov_deg"):
		return "slice 36 must NOT expose a 'gimbal_fov_deg' knob — the window is what the requirement is READ AGAINST here, and slice 35 already found that a live window turns a rate-limited wire's break into an ACQUISITION break"
	if keys.has("radome_slope_est") or keys.has("radome_slope") or keys.has("radome_ripple"):
		return "slice 36 must NOT expose ANY radome knob — this wire has NO GLASS, so every one of them would be a DEAD knob (slice 35's own `radome_slope_est` slider goes with the glass)"
	if keys.has("gimbal_tau_s"):
		return "slice 36 must NOT expose a 'gimbal_tau_s' knob — slice 34's gate 2 measured it CONFOUNDED, which is a STRONGER reason to keep a key authored than a dead one"
	if keys.has("gimbal_stop_deg"):
		return "slice 36 must NOT expose a 'gimbal_stop_deg' knob — gate 0 measured that shrinking the stop REACHES THE SAME RESCUE by a DIFFERENT mechanism (it CAGES the head: `head_max === stop` exactly, and the birth angle SATURATES so the V's right arm is unreachable by it). That separation ships as a tooth in `test_missile.jl`; two stops on one wire would break convention 9"
	if keys.has("cross_speed_mps"):
		return "slice 36 must NOT expose 'cross_speed_mps' — it is slice 32's OWN axis (it moves the LEAD), and here it is also this slice's own CONTROL: reverse the crossing and the requirement is exactly |err| at every servo rate"
	if keys.has("af_alpha_max") or keys.has("alpha_max"):
		return "slice 36 must NOT expose an 'alpha_max' knob — slice 26's instrument for a ring this wire does not have"
	if keys.has("n_pn") or keys.has("rho"):
		return "slice 36 must NOT expose 'n_pn' or 'rho' — they move the guidance loop itself"
	if keys.has("sigma_seek"):
		return "slice 36 must NOT expose 'sigma_seek' — a knob that DEGRADES the lesson beside it"
	if keys.has("elevation_deg"):
		return "slice 36 must NOT expose 'elevation_deg' — the slice-19 DEAD-knob class, and on this wire it is ALSO what the handover error is measured against (it sets the tick-1 body-frame LOS at +18.105 deg, which is why the declared domain's endpoints are where they are)"
	if keys.has("speed"):
		return "slice 36 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (the slice-19 DEAD-KNOB finding)"
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
	var r11: Dictionary = _res["r11"]
	var r60: Dictionary = _res["r60"]
	# ⚠⚠ THE MECHANISM IS QUOTED OFF `r11`, AN ARM THAT **HELD**, NEVER OFF `op` — see PHASE MECHANISM.
	# ⚠⚠ AND THE ARGUMENT COUNT IS PART OF THE PROOF: this file's first run printed its whole headline as
	# a RAW FORMAT STRING on a GREEN EXIT, because the `[%s wire]` specifier had no argument. That is
	# slice 21's `%.2e` and slice 25's `%g` bug in a THIRD form — an argument-count mismatch rather than
	# an unknown specifier — and it fails the same way: silently, on a passing run. A number that does
	# not print is not a proof.
	var head := ("S36V OK [%s wire]: since slice 34 the head has been handed its target PERFECTLY, a " +
		"§1 condition slice 35 then had to gate away with a band and a wide window because the " +
		"ACQUISITION TURN is the largest slew demand in the whole engagement. Make the handover an " +
		"AUTHORED quantity and the question that was gated away has an answer nobody in the arc " +
		"predicted: ⭐⭐ THE WINDOW A SEEKER NEEDS IS NOT |err|. The body-frame LOS is not a fixed " +
		"target — this run measures it travelling %+.3f -> %+.3f deg, a %.3f deg EXCURSION THROUGH " +
		"ZERO, while the `hypot` beside it bottoms out at %.4f and can show none of it (the #1 SIGN " +
		"TRAP's 10th occurrence, in a diagnostic: gate 0's first mechanism story was inferred from " +
		"that hypot and was WRONG). A head handed over ON the LOS must chase the whole journey; one " +
		"handed over part-way ALONG it starts with a head start. ") % \
		[_wire, float(r11["azhi"]), float(r11["azlo"]),
		 float(r11["azhi"]) - float(r11["azlo"]), float(r11["bodylo"])]
	var body := ""
	if _wire == "handover":
		var r10: Dictionary = _res["r10"]
		var r12: Dictionary = _res["r12"]
		body = ("⭐⭐ SO THE PERFECT HANDOVER LOSES ITS TRACK: err %+.1f deg at %.0f deg/s behind a %.1f " +
			"deg window misses by %.3f m, with `defl_sat` EXACTLY 0 and `aero_sat` the ONE launch " +
			"transient tick — slice 32's POINTING miss, full authority and no idea where to point it. " +
			"⭐⭐ AND THE CURE IS A MEASURED BRACKET: BROKEN at %.0f deg/s (%.3f deg) -> HELD at %.0f " +
			"(%.3f deg), never interpolated, because the requirement is NON-MONOTONE in the rate (the " +
			"210-cell 0.5 deg/s grid found the ≥-window set CONTIGUOUS and anchored at the floor, and " +
			"these arms re-derive the property rather than trusting it). Above the bracket it FALLS " +
			"monotonically %.3f -> %.3f -> %.3f deg at %.0f / %.0f / %.0f deg/s. ⚠⚠ THE BROKEN ARM's " +
			"OWN PEAK IS NOT A REQUIREMENT AND THIS FILE SAYS SO: it reads %.3f deg — the POST-BREAK " +
			"RUNAWAY, %.1fx the real %.3f deg (MEASURED free-window, core suite) — the two-run " +
			"discipline's FIFTH quantity, failing LARGE where slice 34's frozen head angle failed " +
			"plausibly-but-small. ⭐ AND THE CURE IS FREE IN ACCURACY, BIT-EXACTLY: two HELD arms at " +
			"%.0f and %.0f deg/s fly IDENTICAL trajectories (max|Δpos| = 0.0) and land at the same " +
			"%.5f m. ") % [float(op["err"]), float(op["rate"]), float(op["win"]), float(op["miss"]),
			RATE_10, float(r10["peak"]), RATE_11, float(r11["peak"]),
			float(r11["peak"]), float(r12["peak"]), float(r60["peak"]), RATE_11, RATE_12, RATE_HI,
			float(op["peak"]), float(op["peak"]) / REQ_A_FLOOR_REF(), REQ_A_FLOOR_REF(),
			RATE_11, RATE_HI, float(r11["miss"])]
	else:
		var r40: Dictionary = _res["r40"]
		body = ("⭐⭐ SO A HANDOVER 6 deg 'WRONG' KEEPS THE TRACK A PERFECT ONE LOSES — same servo, same " +
			"window, same seed: err %+.1f deg at %.0f deg/s HOLDS all the way in and hits at %.3f m, " +
			"with a requirement of %.3f deg against the %.1f deg window (%.3f deg of margin, and this " +
			"is the WORST cell anywhere in the declared domain, measured on a 0.5 deg/s fine grid " +
			"rather than at the corners). ⭐⭐ AND IT BUYS WHAT SLICE 35 SAID COULD NOT BE BOUGHT. Slice " +
			"35 shipped the arc's first TWO-SIDED knob: one servo slider, two bounds, no free " +
			"direction. Here the slider STOPS MATTERING — %.3f / %.3f / %.3f deg at %.0f / %.0f / %.0f " +
			"deg/s, IDENTICAL to the bit, because the left arm of the requirement's V is |err| EXACTLY: " +
			"the tick-1 peak, an INITIAL CONDITION, and no bandwidth touches an initial condition. " +
			"That is the free direction slice 35 could not find, and it is not on slice 35's axis. " +
			"⚠ AND IT BUYS MARGIN, NOT IMMUNITY: one bracket BELOW the declared domain (6 deg/s) this " +
			"same wire breaks too, which is what the floor is measured on — flown in `test_missile.jl` " +
			"because it is outside the slider's range and so not client-drivable. ") % [
			float(op["err"]), float(op["rate"]), float(op["miss"]), float(op["peak"]),
			 float(op["win"]), float(op["win"]) - float(op["peak"]),
			 float(r11["peak"]), float(r40["peak"]), float(r60["peak"]), RATE_11, RATE_40, RATE_HI]
	print(head + body + ("⚠⚠ THE REQUIREMENT IS AN **APPROACH** QUANTITY AND THE ENDGAME PROVES IT: on a " +
		"HELD arm the running max reads %.3f deg while r > 200 m and %.4f deg at the last frame, " +
		"because the target is behind the head by then and a PEAK CANNOT FORGET. That is why the client " +
		"FREEZES its display (`_handover_peak_hold`, proven headless) and why gate 2 DROPPED a signed " +
		"peak-MARGIN key — it would have latched on 100 %% of arms including every hit. ⚠ NO GLASS ON " +
		"THIS WIRE (%d frames carried a `radome_*` key), the first radome-free missile wire of this arc " +
		"— which is ALSO why the button drop stopped being free: slices 26-35 all rode `radome_view` " +
		"for it, so `gimbal_handover_view` plugs a BUTTON hole at both client sites AND selects the " +
		"HUD branch, and slice 35's 'branch selector, not a hole plug' does not transfer. ⚠ NO new cap, " +
		"rung, instability or draw: one comp key, an AUTHORED quantity where there was a truth read, " +
		"and the finding that its optimum is not zero. Class 4a, the TWELFTH consecutive RNG-live " +
		"slice, replay bit-identical (max|Δpos| = 0.0), button DROPPED (12th — and the FIRST that " +
		"needed an edit to stay dropped).") %
		[float(r11["peak"]), float(r11["peakraw"]), int(op["glass"])])
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S36V FAIL: " + msg)
	print("S36V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
