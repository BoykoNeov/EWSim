extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-49 gate-3 verifier — ASPECT-DEPENDENT RADAR CROSS-SECTION.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice49_aspect.yaml
#   godot --headless --path clients/godot --script res://net/slice49_verify.gd     (exit 0 = pass)
#
# THE LESSON. A target's echo is not a number it carries around — it is a property of its SHAPE and
# its HEADING. A ground radar holds a 4 m² aircraft comfortably at 18 km; the aircraft turns its
# nose toward the radar and VANISHES, for tens of seconds and kilometres of closing range, while
# getting CLOSER the whole time.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE, AND IT IS WHY A SMALLER `rcs_m2` CANNOT FAKE IT: for
# a CONSTANT echo, detection is a monotone function of RANGE — `r ≤ R_acq`, one threshold against a
# range that only comes down on an approach. So a constant target can be GAINED while closing and
# never LOST. The sphere control here IS lost (Swerling-1 fading is real, and this file asserts that
# it fades) — what it cannot do is STAY lost. The authored wire stays lost two orders of magnitude
# longer, on the same radar, the same flight and the same broadside cross-section.
#
# ⭐⭐ AND THE SHARPEST TOOTH IS A BYTE-IDENTITY THE OTHER WAY UP FROM SLICE 48's. Across the WHOLE
# slider the target flies the IDENTICAL trajectory to the last bit — `max|Δpos| == 0` — and its
# aspect angle traces the identical curve, because the shape is read by the SEEING and by nothing
# else. The slider changes nothing about the flight and everything about what the radar gets back.
#
# ⚠ THE GAUGE IS THE LONGEST LOSS RUN **WHILE CLOSING**, in seconds and in kilometres of range given
# up. It is NOT the loss COUNT (measured NON-MONOTONE in fineness — 41 → 133 → 53 → 42, because a
# middling body chatters at the threshold while a slender one drops out and stays out) and it is not
# a detected-%, which mixes the outbound leg back in. Non-monotone gauges are how sliders die here.
#
# ⚠⚠ TWO OF SLICE 48's TEETH DELIBERATELY DO **NOT** TRANSFER, and each absence is a decision:
#   1. NO `_turned` / CPA CHECK. The target flies a 6 km-radius circle at 300 m/s — a ~126 s period —
#      so at 40 s every arm is still on its inbound leg. Slice 48's "must reach CPA inside STEPS"
#      would fail every one of them. The MIRROR is asserted instead: the range must fall on EVERY
#      frame, so the "while closing" window covers the whole run by construction rather than by a
#      filter. That is a stronger statement than the filter would have been.
#   2. NO SLIDER READ-BACK KEY. `rcs_fineness` is not echoed on the wire (it is a SHAPE, not a
#      measurement), so slice 48's `_rho_seen` tooth has no analogue. Its job — proving a `set_param`
#      reached THE PHYSICS rather than merely being accepted — is done in this slice's own currency:
#      `rcs_eff_m2` must DIFFER across arms at the IDENTICAL geometry, which a swallowed set_param
#      fails. (The geometry is identical because of the byte-identity above, so this is a clean
#      comparison frame-by-frame rather than an approximate one.)
#   3. NO BYTE-IDENTITY CLAIM FOR THE SPHERE ARM. `rcs_fineness = 1` and the key ABSENT are two
#      different things that must not be conflated — `sin²θ + cos²θ` is 1 in algebra and not always
#      1.0 in floating point. The `===` proof is gate 2's Julia tooth; here the sphere is the
#      LESSON's null only, and it is asserted as a NUMBER (0 dB at every frame).
#
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const RAD := "radar1"
const TID := "tgt1"

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16) or `_drain_scan` waits forever,
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this; the core pins `emit_every`
# as a test so an edit to either breaks there first). 40000 = 16 × 2500.
# ⚠ AND IT IS 40 s WHERE EVERY VERIFIER IN THIS ARC FLEW ~9 s: this lesson takes tens of seconds of
# flight to appear at all, so the budget was decided in the plan (§15) before the script was written
# rather than discovered mid-run. Three arms plus a replay = 160 000 ticks.
const STEPS := 40000

# THE SLIDER — the body's length/width ratio. FLOOR 1.0 is a SPHERE and the lesson's null (a sphere
# is aspect-independent by construction); the authored wire opens at 8.0, mid-lesson; 12.0 is the
# ceiling, still a physically ordinary airframe.
const F_SPHERE := 1.0
const F_AUTH := 8.0
const F_TOP := 12.0

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const RCS_BROADSIDE := 4.0        # m² — the BROADSIDE cross-section, which is what `rcs_m2` means
                                  # once a fineness is present (the normalization decision)
const R0_M := 18000.0             # the launch range, and the target must START detected there

# THE 40 s COLUMN, MEASURED (plan §15) — the file asserts against numbers rather than hopes.
const LOSS_SPHERE_MAX := 0.5      # measured 0.20 s: two looks of the 10 Hz cadence, no more
const SPAN_SPHERE_MAX := 100.0    # m — …and essentially no closing range given up
const LOSS_AUTH_MIN := 15.0       # measured 27.00 s. ⚠ THE TOOTH IS THE ORDER, NOT THE DIGIT
const SPAN_AUTH_MIN := 4000.0     # m — measured 5.8 km
const SEPARATION_MIN := 50.0      # ×  — measured 135× at 40 s. "Two orders of magnitude" is the
                                  # honest headline and the AUTHORED arm is the one that ships
const DET_SPHERE_MIN := 0.90      # measured 98.2 % of frames
const DET_AUTH_MAX := 0.35        # measured 20.2 %
const NOSE_ON_MAX := 30.0         # deg — the aspect must actually TRAVEL to nose-on, or nothing
                                  # in this scenario is being exercised
const BROADSIDE_TOL := 1.0        # deg — the first frame must be broadside (where the curve PEAKS)
const DB_TOL := 1.0e-9            # the sphere's 0 dB is EXACT arithmetic, not an approximation
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

# --- per-arm accumulators ---------------------------------------------------------------------
var _n_frames := 0
var _n_det := 0
var _n_keys := 0                  # frames carrying the slice's four keys — the never-stale tooth
var _first_det := false           # ⭐ the target must START detected, or a loss is not a loss
var _first_asp := -1.0            # …and it must start BROADSIDE, where the curve peaks
var _first_sigma := -1.0
var _min_asp := 1.0e30            # how far round the nose actually came
var _max_loss_db := -1.0e30
var _min_loss_db := 1.0e30
var _prev_range := -1.0
var _opened := false              # did the range EVER stop falling? (it must not, inside 40 s)
var _run_t0 := -1.0               # the current loss run's start (−1 = holding)
var _run_r0 := 0.0
var _loss_s := 0.0                # ⭐ THE GAUGE: longest CLOSING loss run
var _loss_km := 0.0               # …and the closing range given up over THAT run
var _loss_t0 := -1.0              # …and when it began, so the windowed shot can be AIMED
var _pos_trace: Array = []
var _asp_trace: Array = []
var _sig_trace: Array = []

func _initialize() -> void:
	print("S49V_INIT godot=", Engine.get_version_info().string)
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

# --- the flight plan --------------------------------------------------------------------------

func _build_arms() -> void:
	# ⭐⭐ 1. THE CONTROL, AND IT IS A CONTROL THAT CAN FAIL. A sphere is aspect-independent BY
	#    CONSTRUCTION, so this is the lesson's null — and Swerling-1 fading means it still drops out.
	#    A non-fluctuating detector would hand it a perfect 100 % and make the comparison a tautology.
	_arms.append({"tag": "sphere", "f": F_SPHERE})
	# ⭐⭐⭐ 2. THE AUTHORED WIRE — the arm that ships, and the one the showcase opens on.
	_arms.append({"tag": "auth", "f": F_AUTH})
	# ⭐ 3. THE CEILING — more of the same, which is the point: the top of the slider is not a new
	#    regime, and a slider whose upper half were indistinguishable from its middle would be
	#    decorative. It is asserted MONOTONE against the authored arm, not merely different.
	_arms.append({"tag": "top", "f": F_TOP})
	# ⭐ 4. DETERMINISM — same seed, same slider ⇒ the same flight AND the same seeing (convention 2,
	#    the master check).
	_arms.append({"tag": "replay", "f": F_AUTH})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the fineness returns to the authored 8.0 every arm and each must
	# re-send its own. That is what makes these arms the CLIENT's path — a slider drag — rather than
	# a set of scenario variants. ⚠ SENT ON EVERY ARM INCLUDING THE AUTHORED ONE, so that arm proves
	# the SLIDER's path to its own value rather than merely inheriting it from the file.
	_client.send({"type": "reset"})
	_client.send({"type": "set_param", "target": TID, "key": "rcs_fineness", "value": float(arm["f"])})
	_t_target = STEPS * _dt
	_client.send({"type": "step", "n": STEPS})

func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var det_frac := 0.0 if _n_frames == 0 else float(_n_det) / float(_n_frames)
	var m := {
		"f": float(arm["f"]), "frames": _n_frames, "det": det_frac,
		"loss": _loss_s, "loss_km": _loss_km, "loss_t0": _loss_t0,
		"first_det": _first_det, "first_asp": _first_asp, "first_sigma": _first_sigma,
		"min_asp": _min_asp, "db_max": _max_loss_db, "db_min": _min_loss_db,
		"opened": _opened, "keys": _n_keys,
		"pos": _pos_trace.duplicate(true), "asp": _asp_trace.duplicate(),
		"sig": _sig_trace.duplicate(),
	}
	_res[tag] = m
	print(("S49V_ARM   %-7s F=%5.1f  ->  longest closing loss = %6.2f s (%5.2f km given up)  " +
		   "detected %5.1f%%  aspect %5.1f -> %5.1f deg  loss %6.2f..%6.2f dB  frames=%d") %
		  [tag, m["f"], m["loss"], m["loss_km"], 100.0 * m["det"],
		   m["first_asp"], m["min_asp"], m["db_min"], m["db_max"], m["frames"]])

	if not (_n_frames > 2000):
		return "arm %s: the run must produce a full frame history (got %d of ~2500)" % [tag, _n_frames]
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47/48): the four slice-49 keys are KEY-PRESENCE gated on
	# the target's shape, so on this wire they ship on EVERY frame. A key that stops emitting makes
	# the HUD's `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test (`docs/CONVENTIONS.md` §14) —
	# and here that default would read "0 dB below broadside", i.e. a target at its BRIGHTEST, on the
	# exact frames where it is at its dimmest.
	if not (_n_keys == _n_frames):
		return (("arm %s: all four aspect keys must ship on EVERY frame (%d of %d) — a key that stops " +
				"emitting reads downstream as a defaulted zero, which on `rcs_loss_db` is the " +
				"loudest possible lie: 0 dB is a target at its BRIGHTEST") % [tag, _n_keys, _n_frames])
	# ⭐⭐ IT MUST START DETECTED, OR A LOSS IS NOT A LOSS. Gate 0's first probe started the target
	# nose-on and beyond the horizon; its null meant nothing, because a probe that starts undetected
	# cannot measure a drop-out.
	if not _first_det:
		return (("arm %s: the target must be DETECTED on the first frame — it starts BROADSIDE at " +
				"%.0f km, its brightest aspect, and an arm that starts invisible cannot measure a " +
				"drop-out at all (gate 0's own first mistake)") % [tag, R0_M / 1000.0])
	# …and it must start BROADSIDE, which is where an aspect curve PEAKS. ⚠ This is also the cheap
	# consistency check on `aspect_angle`'s CONVENTION: 0 = nose-on, 90 = broadside. If the vector
	# were built observer→target the angle would reflect about 90° — invisible under the model's
	# fore/aft symmetry, and a silently wrong number everywhere else.
	if absf(_first_asp - 90.0) > BROADSIDE_TOL:
		return (("arm %s: the first frame must read BROADSIDE (%.3f deg, want 90) — the scenario is " +
				"built to start at the curve's PEAK, and this is also the check on aspect_angle's " +
				"own convention (0 = nose-on)") % [tag, _first_asp])
	# …and at broadside σ_eff IS the authored broadside RCS. That identity is what lets `rcs_m2` keep
	# its meaning under this model, and it holds at EVERY fineness.
	# ⚠⚠ ASSERTED AS A NEAR-EQUALITY WITH A **MEASURED** TOLERANCE, AND THE FIRST DRAFT DEMANDED
	# EXACTNESS AND FAILED — correctly. The first frame a client ever sees is `emit_every` = 16 ticks
	# AFTER launch, so the nose has already come ~0.09° off broadside and σ reads 3.999867 at F = 8.
	# The exact identity lives where it can be stated exactly, in the core (`test_rcs_aspect.jl` pins
	# it at θ = π/2 to 1e-12); a frame-sampled client cannot see t = 0 and must not pretend to.
	# ⭐ THE OTHER HALF IS AN EXACT EXTERNAL ANCHOR AND IS ASSERTED AS ONE: for a prolate body
	# broadside is the PEAK of the curve, so no frame may ever come back BRIGHTER than `rcs_m2`.
	if absf(_first_sigma - RCS_BROADSIDE) > 1.0e-3 * RCS_BROADSIDE:
		return (("arm %s: the first frame must read essentially the authored broadside RCS (%.6f vs " +
				"%.1f m²) — it is 16 ticks after launch, which is ~0.09° off broadside, not 1 %%") %
				[tag, _first_sigma, RCS_BROADSIDE])
	if _first_sigma > RCS_BROADSIDE + 1.0e-12:
		return (("arm %s: no frame may be BRIGHTER than the authored broadside RCS (%.9f > %.1f m²) " +
				"— broadside is the peak of a prolate body's curve, and a σ above it means the " +
				"normalization has come undone") % [tag, _first_sigma, RCS_BROADSIDE])
	# ⭐ THE NOSE MUST ACTUALLY COME ROUND. The turn is the mechanism, not the staging — a
	# straight-flying target could never produce this lesson at any fineness.
	if not (_min_asp < NOSE_ON_MAX):
		return (("arm %s: the aspect must travel from broadside to NOSE-ON inside the window (got a " +
				"minimum of %.1f deg) — a target that does not turn its nose toward the radar cannot " +
				"show this at any fineness") % [tag, _min_asp])
	# ⚠⚠ THE WINDOW: the range must FALL on every frame. This is the mirror of slice 48's CPA check
	# and it replaces it — on a ~126 s circle nothing reaches CPA in 40 s, so rather than filtering
	# for the closing band this file asserts that the whole run IS the closing band.
	if _opened:
		return (("arm %s: the range must fall on every frame of the 40 s window — the gauge is the " +
				"longest loss WHILE CLOSING, and if the target has already turned then part of this " +
				"run is the outbound leg and the number is not the slice's") % tag)
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var sph: Dictionary = _res["sphere"]
	var aut: Dictionary = _res["auth"]
	var top: Dictionary = _res["top"]

	# ⭐⭐ 1. THE CONTROL IS A CONTROL THAT CAN FAIL — AND THAT IS WHY `swerling: 1` IS LOAD-BEARING.
	# A 4 m² target ~21 dB above threshold still fades below it occasionally, because a Swerling-1
	# echo is exponentially distributed. What it cannot do is STAY lost.
	print("S49V_CONTROL sphere: lost for at most %.2f s (%.0f m given up), detected on %.1f%% of frames" %
		  [sph["loss"], 1000.0 * float(sph["loss_km"]), 100.0 * float(sph["det"])])
	if not (float(sph["loss"]) <= LOSS_SPHERE_MAX):
		return _fail(("the sphere control must never STAY lost (%.2f s, bound %.2f) — for a constant " +
					  "echo detection is `r ≤ R_acq`, one threshold against a range that only comes " +
					  "down, so a loss can only ever be a fade") % [sph["loss"], LOSS_SPHERE_MAX])
	if not (1000.0 * float(sph["loss_km"]) <= SPAN_SPHERE_MAX):
		return _fail("the sphere control must give up essentially no closing range (%.0f m)" %
					 (1000.0 * float(sph["loss_km"])))
	if not (float(sph["det"]) >= DET_SPHERE_MIN):
		return _fail("the sphere control must hold its target ~all the way in (%.1f%%)" %
					 (100.0 * float(sph["det"])))
	# ⚠⚠ …AND IT MUST ACTUALLY FLICKER. A control that CANNOT fail makes the comparison below a
	# tautology, which is exactly what a non-fluctuating detector would produce here.
	if not (float(sph["det"]) < 1.0):
		return _fail(("the sphere control must FLICKER at least once (detected on 100.0%% of frames) " +
					  "— `swerling: 1` is load-bearing in this scenario precisely so the control CAN " +
					  "fail, and a control that cannot fail makes the whole comparison a tautology"))
	# ⭐ AND THE SPHERE IS AN EXACT NULL IN dB: aspect-independent by construction, so `rcs_loss_db`
	# is 0.0 on EVERY frame however far round the nose comes. This is the LESSON's null, and it is
	# asserted as a number rather than as a byte-identity — `F = 1` and the key ABSENT are different
	# things (gate 2 owns that distinction, with `===`).
	if not (absf(float(sph["db_max"])) <= DB_TOL and absf(float(sph["db_min"])) <= DB_TOL):
		return _fail(("a sphere must be aspect-INDEPENDENT: `rcs_loss_db` ran %s … %s dB over a " +
					  "run whose aspect swept %.1f° → %.1f°. That is the model's own null and it must " +
					  "be exact") % [_sci(float(sph["db_min"])), _sci(float(sph["db_max"])),
									 sph["first_asp"], sph["min_asp"]])

	# ⭐⭐⭐ 2. THE AUTHORED WIRE — the target vanishes WHILE IT IS STILL CLOSING.
	print(("S49V_LESSON F=%.0f: gone for %.2f s while CLOSING, %.2f km of range given up, detected " +
		   "on %.1f%% of frames (the sphere: %.2f s) -> %.0fx") %
		  [aut["f"], aut["loss"], aut["loss_km"], 100.0 * float(aut["det"]), sph["loss"],
		   float(aut["loss"]) / maxf(float(sph["loss"]), 1.0e-9)])
	if not (float(aut["loss"]) >= LOSS_AUTH_MIN):
		return _fail(("the authored wire must lose the target for tens of seconds while closing " +
					  "(%.2f s, bound %.1f)") % [aut["loss"], LOSS_AUTH_MIN])
	if not (1000.0 * float(aut["loss_km"]) >= SPAN_AUTH_MIN):
		return _fail(("…and it must give up kilometres of CLOSING range doing it (%.0f m, bound %.0f) " +
					  "— the range is what makes the drop-out a lesson rather than a number") %
					 [1000.0 * float(aut["loss_km"]), SPAN_AUTH_MIN])
	if not (float(aut["det"]) <= DET_AUTH_MAX):
		return _fail("…and it must be invisible for most of the run (detected %.1f%%)" %
					 (100.0 * float(aut["det"])))
	var sep: float = float(aut["loss"]) / maxf(float(sph["loss"]), 1.0e-9)
	if not (sep >= SEPARATION_MIN):
		return _fail(("⭐⭐⭐ THE SLICE: the same radar, the same flight and the same BROADSIDE " +
					  "cross-section, and only the SHAPE differs — the loss must be two orders of " +
					  "magnitude longer (%.1fx, bound %.0f)") % [sep, SEPARATION_MIN])

	# ⭐⭐⭐ 3. THE BYTE-IDENTITY, AND IT IS THE OTHER WAY UP FROM SLICE 48's. Slice 48 asserted that a
	# slider which LOOKED busy reached nothing; here the slider reaches everything about the SEEING
	# and nothing at all about the FLYING. The target flies the identical trajectory to the last bit
	# across the whole domain, so every arm is measured at the IDENTICAL geometry — which is what
	# makes the σ comparison below a clean one rather than an approximate one.
	var d_pos: float = _max_pos_diff(sph["pos"], top["pos"])
	var d_asp: float = _max_abs_diff(sph["asp"], top["asp"])
	print("S49V_FLIGHT F=%.0f vs F=%.0f: max|Δpos| = %.12f m, max|Δaspect| = %.12f deg over %d frames" %
		  [sph["f"], top["f"], d_pos, d_asp, sph["pos"].size()])
	if not (d_pos <= EXACT and d_asp <= EXACT):
		return _fail(("the shape must be read by the SEEING and by nothing else — across the slider " +
					  "the flight differs by %.12f m and the aspect by %.12f deg. A shape that " +
					  "reaches the mover is a second, unnamed path into the physics") % [d_pos, d_asp])

	# ⭐⭐ 4. …AND THE SLIDER REACHED THE PHYSICS, ASSERTED IN THIS SLICE'S OWN CURRENCY. There is no
	# `rcs_fineness` echo on the wire (a shape is not a measurement), so slice 48's read-back tooth
	# has no analogue. What stands in for it is stronger: at the IDENTICAL geometry, frame for frame,
	# the effective cross-sections must differ — which a `set_param` that is accepted and never
	# consumed fails, while it passes every sent-vs-echoed check there is.
	var sig_ratio := 0.0
	var n_sig: int = mini(sph["sig"].size(), top["sig"].size())
	for i in range(n_sig):
		sig_ratio = maxf(sig_ratio, float(sph["sig"][i]) / maxf(float(top["sig"][i]), 1.0e-30))
	print("S49V_SIGMA  same geometry, different shape: sigma_eff differs by up to %.0fx (%.1f dB)" %
		  [sig_ratio, 10.0 * (log(sig_ratio) / log(10.0))])
	if not (sig_ratio > 100.0):
		return _fail(("at the identical geometry the two shapes must return wildly different echoes " +
					  "(max ratio %.3f) — this is the slider's own tripwire, and a set_param that is " +
					  "accepted and never consumed passes every other check in this file") % sig_ratio)

	# ⭐⭐ 5. THE LADDER IS MONOTONE IN THE GAUGE. `k` (28), `ω_n` (40) and `σ_seek` (25) all died as
	# sliders on non-monotonicity; this one is asserted, not assumed.
	# ⚠ THREE ARMS IS **TWO INTERVALS**, AND THIS FILE DOES NOT CALL THAT A LADDER. The full seven-
	# column ladder is measured in the CORE (plan §13, and `test_rcs_aspect.jl` pins five columns of
	# it); §15 pre-registered three arms here because each one costs 40 000 ticks.
	print("S49V_AXIS       F   closing loss s   km given up      detected %      peak dB down")
	var prev_loss := -1.0
	var prev_det := 2.0
	for tag in ["sphere", "auth", "top"]:
		var a: Dictionary = _res[tag]
		print("S49V_AXIS   %5.1f %16.2f %13.2f %15.1f %17.1f" %
			  [a["f"], a["loss"], a["loss_km"], 100.0 * float(a["det"]), a["db_max"]])
		if not (float(a["loss"]) > prev_loss):
			return _fail(("the longest closing loss must RISE with fineness (%.2f s at F = %.1f, " +
						  "after %.2f s) — a non-monotone gauge is not a lesson, and this project " +
						  "has disqualified four sliders for exactly that") %
						 [a["loss"], a["f"], prev_loss])
		if not (float(a["det"]) < prev_det):
			return _fail(("…and the detected fraction must fall with it (%.3f at F = %.1f, after " +
						  "%.3f) — a second, independent gauge agreeing") % [a["det"], a["f"], prev_det])
		if not (float(a["db_max"]) > 0.0 or float(a["f"]) == F_SPHERE):
			return _fail("arm F = %.1f must go QUIETER than broadside at some point (%.3f dB)" %
						 [a["f"], a["db_max"]])
		prev_loss = float(a["loss"])
		prev_det = float(a["det"])

	# ⭐ 6. DETERMINISM — the master check (convention 2). Same seed, same slider ⇒ the same flight
	# AND the same seeing, to the last bit, including the gauge built out of them.
	var d_rep: float = _max_pos_diff(aut["pos"], _res["replay"]["pos"])
	var d_sig: float = _max_abs_diff(aut["sig"], _res["replay"]["sig"])
	# ⚠⚠ `%.12f` AND NOT `%.12e`, AND THIS LINE SHIPPED WRONG ONCE. `%e` is NOT a GDScript specifier:
	# an unknown one makes the WHOLE format fail SILENTLY and print the FORMAT STRING itself, on a
	# run that exits 0. Slice 21's bug, reproduced verbatim by slice 25, and now by this file — it is
	# caught only by reading the output of a PASSING run, which is why CLAUDE.md carries it.
	print("S49V_REPLAY max|Δpos| = %.12f m, max|Δsigma| = %.12f m², gauge %.4f vs %.4f s" %
		  [d_rep, d_sig, aut["loss"], _res["replay"]["loss"]])
	if not (d_rep <= EXACT and d_sig <= EXACT):
		return _fail("replay differs (%.12f m / %.12f m²) — determinism is the master check" %
					 [d_rep, d_sig])
	if not (absf(float(aut["loss"]) - float(_res["replay"]["loss"])) <= EXACT):
		return _fail(("…and the GAUGE must replay too (%.6f vs %.6f s) — a detector whose draws " +
					  "replayed while its verdicts did not would pass the line above") %
					 [aut["loss"], _res["replay"]["loss"]])

	# ⚠ THE WINDOWED SHOT'S OWN AIM, MEASURED HERE RATHER THAN GUESSED. Convention 14's fourth proof
	# has no headless equivalent, and a shot that lands on the else-branch of the thing the slice
	# added proves nothing about it (the slice-19 rule). This is the tick to freeze at.
	var shot_t: float = float(aut["loss_t0"]) + 0.5 * float(aut["loss"])
	var shot_n: int = 16 * int(round(shot_t / (16.0 * _dt)))
	print(("S49V_SHOT   the drop-out at F = %.0f opens at t = %.3f s and runs %.2f s -> aim the " +
		   "windowed shot at step n = %d (t = %.3f s), which is INSIDE it") %
		  [aut["f"], aut["loss_t0"], aut["loss"], shot_n, shot_n * _dt])

	print("S49V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice49_aspect":
		return "wrong scenario '%s' — run scenarios/slice49_aspect.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, AND WITHOUT IT THIS WIRE IS A SLICE-2 WIRE TO THE CLIENT: it would draw the
	# correct spatial view (there is no hole) but the aspect block would not be drawn at all, and the
	# shared button would offer `free_space ↔ two_ray` — a lesson about MULTIPATH LOBING on a
	# scenario whose target vanishes for a completely different reason. Two mechanisms in one view
	# is what convention 9 exists to prevent.
	if not bool(f.get("aspect_view", false)):
		return ("a slice-49 handshake must ship aspect_view=true — without it the aspect block is " +
				"never drawn and the client offers a MULTIPATH button on a scenario whose target " +
				"vanishes because of its HEADING")
	# ⚠ AN ASPECT BELONGS TO A TARGET–OBSERVER **PAIR**. A HUD reading "aspect 25°" with no subject
	# would be this family's ~13th stale readout — and the two ids are NOT interchangeable: the
	# telemetry is keyed on the OBSERVER while the prose names the TARGET.
	if str(f.get("aspect_target", "")) != TID:
		return "the marker must name the shaped TARGET (got '%s', want '%s')" % [str(f.get("aspect_target", "")), TID]
	if str(f.get("aspect_observer", "")) != RAD:
		return ("the marker must name the OBSERVER the aspect is measured from (got '%s', want " +
				"'%s') — it is also the id every telemetry key is prefixed with") % [str(f.get("aspect_observer", "")), RAD]
	for k in ["search_view", "midcourse_view", "seeker_detect_view", "radome_view", "gimbal_view",
			  "seeker_fov_view", "airframe_view", "airframe_6dof"]:
		if bool(f.get(k, false)):
			return ("a slice-49 wire must NOT raise %s — this is a GROUND RADAR watching an aircraft " +
					"turn, not a missile, and any of those would route the client into another " +
					"slice's view or steal the shared button") % k
	for k in ["range_axis_m", "pri_axis_us", "terrain_grid"]:
		if f.has(k):
			return ("a slice-49 wire must not carry %s — it would flip the client out of the spatial " +
					"elevation view entirely") % k
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("propagation", "")) != "free_space":
		return ("`propagation` must be authored `free_space` and PINNED (got '%s') — slice 2's " +
				"two_ray adds multipath lobing AND a horizon mask, two more ways for a target to " +
				"vanish, on a scenario about a third way (convention 9)") % str(fid.get("propagation", ""))
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "rcs_fineness":
		return ("exactly ONE knob, the TARGET's `rcs_fineness` (convention 9). `rcs_m2` and `pt_w` " +
				"would move the HORIZON under the lesson — a dimmer target vanishes sooner for a " +
				"reason that has nothing to do with which way it points; `a_lat_mps2` is TWO-SIDED " +
				"(the turn radius sets how fast the nose comes round AND how close it ever gets, " +
				"`R0 − 2·R_turn`); `pfa` moves the CONTROL's chatter; `turn_plane` is refused BY TYPE")
	if str(kn[0].get("target", "")) != TID:
		return "the slider must address the TARGET (`%s`) — the shape is the target's. Got '%s'" % [TID, str(kn[0].get("target", ""))]
	if not (float(kn[0].get("min", -1.0)) == F_SPHERE and float(kn[0].get("max", 0.0)) == F_TOP):
		return (("the slider must span %.0f–%.0f: the floor is a SPHERE (the lesson's null, " +
				 "aspect-independent by construction) and the ceiling is past the point where the " +
				 "lesson has fully arrived, so the top is 'more of the same' rather than a new regime") %
				[F_SPHERE, F_TOP])
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR — what the axis buys is concentrated at the TOP (0.2 s at " +
				"F = 2, 40 s at F = 10), so a log slider would stretch exactly the region where " +
				"nothing changes. The flat bottom third must READ as a region: slenderness buys you " +
				"nothing until it buys you everything")
	return ""

func _reset_scan_accum() -> void:
	_n_frames = 0; _n_det = 0; _n_keys = 0
	_first_det = false; _first_asp = -1.0; _first_sigma = -1.0
	_min_asp = 1.0e30; _max_loss_db = -1.0e30; _min_loss_db = 1.0e30
	_prev_range = -1.0; _opened = false
	_run_t0 = -1.0; _run_r0 = 0.0
	_loss_s = 0.0; _loss_km = 0.0; _loss_t0 = -1.0
	_pos_trace.clear(); _asp_trace.clear(); _sig_trace.clear()

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
	# ⚠ `entities` IS AN ARRAY OF RECORDS, not a dictionary keyed by id (the wire's own shape).
	var tp := _target_pos(f)
	if tp.is_empty():
		return
	var t := float(f.get("t", 0.0))
	_pos_trace.append(tp)
	_n_frames += 1
	var det := _wire_bool(tel, RAD + ".detected")
	if det:
		_n_det += 1
	if _n_frames == 1:
		_first_det = det
	# ⚠ ALL FOUR KEYS COUNTED TOGETHER, not any-of: the never-stale claim is about the SET, and a
	# wire that dropped one of them would otherwise pass on the strength of the other three.
	if tel.has(RAD + ".target_aspect_deg") and tel.has(RAD + ".rcs_eff_m2") \
			and tel.has(RAD + ".rcs_loss_db") and tel.has(RAD + ".target_range_m"):
		_n_keys += 1
	var asp := float(tel.get(RAD + ".target_aspect_deg", -1.0))
	var sig := float(tel.get(RAD + ".rcs_eff_m2", -1.0))
	var db := float(tel.get(RAD + ".rcs_loss_db", 0.0))
	var r := float(tel.get(RAD + ".target_range_m", 0.0))
	_asp_trace.append(asp)
	_sig_trace.append(sig)
	if _n_frames == 1:
		_first_asp = asp
		_first_sigma = sig
	_min_asp = minf(_min_asp, asp)
	_max_loss_db = maxf(_max_loss_db, db)
	_min_loss_db = minf(_min_loss_db, db)
	# THE WINDOW — and the whole run must be inside it (see `_finish_arm`).
	if _prev_range > 0.0 and r > _prev_range:
		_opened = true
	_prev_range = r
	# ⭐ THE GAUGE, recomputed here INDEPENDENTLY of the client's own instrument (convention 11: an
	# independent recompute, not the same call twice). Same definition, different code — the longest
	# run of consecutive undetected frames, priced in seconds and in kilometres given up.
	if not det:
		if _run_t0 < 0.0:
			_run_t0 = t
			_run_r0 = r
		var run := t - _run_t0
		if run > _loss_s:
			_loss_s = run
			_loss_km = maxf(0.0, _run_r0 - r) / 1000.0
			_loss_t0 = _run_t0
	else:
		_run_t0 = -1.0

func _sci(v: float) -> String:
	# ⚠⚠ GDScript's `%` HAS NO `%e` AND NO `%g`, so a near-zero residual has to be rendered by hand or
	# it is unprintable: `%.3f` of 1e-16 is "0.000", which reads as a PASS inside a FAILURE message.
	# This slice shipped `%.3e` here on its first run — in a branch nothing had ever executed, which
	# is the worst place for the silent-format bug to hide (slice 21's defect, third occurrence).
	# The same mantissa-exponent construction `Sandbox.gd:_fmt` uses, for the same reason.
	if v == 0.0:
		return "0"
	var a := absf(v)
	if a >= 0.01 and a < 1.0e6:
		return "%.6f" % v
	var ex := int(floor(log(a) / log(10.0)))
	return "%.3fe%d" % [v / pow(10.0, ex), ex]

func _wire_bool(tel: Dictionary, k: String) -> bool:
	# `detected` ships as a JSON bool; be tolerant of a numeric 0/1 without ever defaulting to TRUE
	# on a missing key (which would silently turn every drop-out into a hold).
	if not tel.has(k):
		return false
	var v = tel[k]
	return bool(v) if typeof(v) == TYPE_BOOL else float(v) >= 0.5

func _target_pos(f: Dictionary) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == TID:
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

func _max_abs_diff(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n == 0:
		return INF
	var d := 0.0
	for i in range(n):
		d = maxf(d, absf(float(a[i]) - float(b[i])))
	return d

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
	push_error("S49V FAIL: " + msg)
	print("S49V FAIL: ", msg)
	quit(code)
	return true
