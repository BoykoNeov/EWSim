extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-55 gate-3 verifier — **WHERE DO YOU SPEND THE APERTURE?**
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice55_fanbeam.yaml
#   godot --headless --path clients/godot --script res://net/slice55_verify.gd     (exit 0 = pass)
#
# THE LESSON. A detector window costs GAIN: `G = eta*4pi/Omega` and `Omega = theta_az*theta_el`, so a
# window costs what its PRODUCT costs. 12.5 x 8.0 = 100 = 10 x 10 — this seeker and slice 48's
# subtend the same solid angle, have the same gain and see EXACTLY the same distance. Nothing here
# is bought. The aperture is only SPENT DIFFERENTLY: 12.5° of azimuth where the cue error actually
# is, paid for in elevation the seeker never uses.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE, AND IT IS ONE NUMBER: **`seeker_r_acq_m` IS SLICE
# 48's OWN 3038.16 m, TO NINE DIGITS, ON A WIRE THAT HITS WHERE SLICE 48 MISSES BY 1039.88 m.** The
# server serves ONE client and then exits, so the disc cannot be flown beside this — the horizon IS
# the held-aperture claim, checkable inside one session, and without it the shape reads as free
# coverage, which is the claim slices 42/43 earned a ban for and slice 46 upheld.
#
# ⭐⭐⭐ AND THE SECOND CLAIM, WHICH IS A **NULL WITH ITS BOUND** RATHER THAN A CURVE. The slider is
# slice 48's own sweep rate — the whole lesson there (never / pinned / cheap, 1039.88 m down to
# 0.31 m over 0…240 °/s) — and here it is INERT: every position returns the same acquisition
# instant and a BIT-IDENTICAL trajectory, because the target was never lost in the first place.
# ⚠⚠ THE KNOB IS STILL LIVE AND STILL REACHES THE PHYSICS — `search_rate_dps` reads back off the
# wire on every arm — so this is a measured null and not a dead knob (the slice-19 / slice-36 shape
# the loader exists to prevent). *You only search because you were blind, and this seeker was not.*
#
# ⚠⚠ `search_t_lock_s` IS −1.0 ON EVERY ARM AND THAT IS NOT A FAILURE. Slice 48's headline gauge is
# defined only where a SWEEP RAN; a fan beam wide enough to hold the cue error never enters the
# search arm, so the sentinel is correct and the ACQUISITION clock is a separate core latch
# (`gimbal_t_acq_s`). A HUD built on the first key alone prints "never found it" over an intercept,
# which is `docs/CONVENTIONS.md` §14's defaulted-value trap with the sign flipped.
#
# ⚠ THE MISS IS NOT THE GAUGE (`docs/PROHIBITIONS.md` §2) — it is a bound here, and a loose one: a
# HIT samples COARSELY on a 16-tick emit grid where a MISS samples faithfully
# ([[ewsim-missile-verifier-sampling]]). The gauges are the acquisition instant, the horizon, and
# the MARGIN PAIR, all read from LATCHED or per-tick core keys.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"
const TID := "tgt1"

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16) or `_drain_scan` waits forever,
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 9600 = 16 * 600, and it
# is sized past the LATEST CPA in the set (the authored arm turns at ~7.4 s).
const STEPS := 9600
const PRESS_AT := 3200            # a multiple of 16, and BEFORE the 4.935 s acquisition, so the
                                  # press is what removes the blind phase
const DRAG_AT := 3200             # a multiple of 16, and MID-BLIND — the drag lands while the
                                  # missile is still flying its belief, which is the only stretch
                                  # of this engagement a sweep rate could possibly matter in

const RUNG_ON := "snr"
const RUNG_OFF := "none"

# THE AUTHORED WINDOW — the pair IS the point, and the product is the aperture.
const WIN_AZ := 12.5
const WIN_EL := 8.0
const WIN_AREA := 100.0           # = 10.0 x 10.0, the disc slice 48 ships
const GAIN_DISC := 10.0           # …and sqrt(12.5 * 8.0), the GAIN-MATCHED control disc
const STOP_AUTH := 45.0
const RATE_AUTH := 240.0

# ⭐⭐⭐ THE HELD APERTURE, AS METRES. Slice 48's own horizon on slice 48's own wire, and the whole
# rival rests on this being EQUAL rather than merely close.
const R_ACQ := 3038.1613444
const R_ACQ_TOL := 1.0e-4         # metres — this is an identity, not a fit

# THE ACQUISITION INSTANT (`gimbal_t_acq_s`, latched in the core) and the CPA it buys.
const T_ACQ := 4.935
const T_ACQ_TOL := 0.02           # s — the 16-tick emit grid is 0.016 s
const HIT_MAX := 10.0             # ⚠ a HIT samples COARSELY: the true CPA is 0.085 m. This bound is
                                  # a sanity rail against slice 48's 1039.88 m, never the lesson.
const MISS_DISC := 1039.88        # …the number this wire is measured AGAINST, published, not flown

# ⚠⚠ THE MARGIN PAIR IS ASSERTED AS **FRACTIONS OF THEIR OWN HALF-WIDTHS**, NOT AS DEGREES, AND
# THAT IS FRAME SAMPLING RATHER THAN A LOOSENING. The core's per-tick pair at the acquiring tick is
# +1.1446° / +7.9797° (pinned in `core/test/test_search.jl`); a client sees one frame in
# `emit_every` = 16 ticks, so the FIRST VALID FRAME is up to 15 ticks late and the head has slewed
# further onto the target by then — +2.855° of azimuth here. The DEGREES are a joint property of the
# geometry and the emit grid; the FRACTIONS are the claim: nearly the whole elevation half-width
# still idle beside a fifth of the azimuth one already spent.
const EL_FRAC_MIN := 0.98         # el margin / 8.0°  — the unswept axis is untouched
const AZ_FRAC_MAX := 0.35         # az margin / 12.5° — and the swept one is being used

const T_PRESS_ACQ := 3.199        # the mid-press arm's own acquisition instant
const RHO_TOP := 240.0
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _pending_press := ""
var _pending_drag := -1.0

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0
var _t_acq := -1.0
var _t_lock_key := -1.0
var _auth_peak := 0.0
var _n_searching := 0
var _n_boxkey := 0                # frames carrying THIS slice's own keys
var _az_at := NAN                 # the margin pair at the FIRST valid frame
var _el_at := NAN
var _az_min := 1.0e30
var _el_min := 1.0e30
var _n_sign := 0                  # valid frames whose margin pair contradicts the verdict
var _az_seen := 0.0
var _el_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _rho_seen := -1.0
var _racq_peak := 0.0
var _t_srch_first := -1.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S55V_INIT godot=", Engine.get_version_info().string)
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
	# ⭐⭐ THE MID-RUN ARM'S SECOND LEG. The server DRAINS EVERY QUEUED COMMAND BEFORE IT STEPS AT
	# ALL, so [step K, set_fidelity, step N-K] sent back-to-back applies the toggle at tick 0 and
	# silently measures a from-launch arm instead (slice 37's finding).
	if _pending_press != "":
		var rung := _pending_press
		_pending_press = ""
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": rung})
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS - PRESS_AT})
		return false
	if _pending_drag >= 0.0:
		var rho_new := _pending_drag
		_pending_drag = -1.0
		_client.send(_set_param_cmd(MID, "seeker_search_rate_dps", rho_new))
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS - DRAG_AT})
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
	# 1) THE SHIPPED WIRE, AS AUTHORED — the reference every other arm is compared against.
	_arms.append({"tag": "authored", "rho": 0.0})
	# 2) ⭐ DETERMINISM — same seed, same slider, same rung ⇒ the same missile to the last bit.
	_arms.append({"tag": "replay", "rho": 0.0})
	# 3) ⭐⭐⭐ THE SLIDER, ACROSS ITS WHOLE DOMAIN, AND IT MUST DO NOTHING. Slice 48's headline axis,
	#    inert here — same acquisition instant, same trajectory to the last bit, at every position.
	for rho in [60.0, 120.0, RHO_TOP]:
		_arms.append({"tag": "r%d" % int(rho), "rho": rho})
	# 4) ⭐⭐⭐ THE LIVE DRAG, MID-BLIND — the one path no other proof walks (`docs/PROHIBITIONS.md`
	#    §6 retracted the ban on dragging inside a verifier). ⚠⚠ AND WHAT MUST SURVIVE IT IS THE
	#    WHOLE FLIGHT: slice 54's harder half is that something has to be asserted UNMOVED, and here
	#    the unmoved thing is the trajectory while the knob itself demonstrably reaches the wire.
	_arms.append({"tag": "drag", "rho": 0.0, "drag": RHO_TOP})
	# 5) ⭐⭐ THE BUTTON, AT BOTH ENDS OF THE SLIDER. With the horizon off there is no blind phase at
	#    all, so the two must be BIT-IDENTICAL to each other — and the acquisition latch reads a
	#    REAL 0.0, which is exactly why its sentinel had to be −1.0 and not zero.
	_arms.append({"tag": "off_lo", "rho": 0.0, "rung": RUNG_OFF})
	_arms.append({"tag": "off_hi", "rho": RHO_TOP, "rung": RUNG_OFF})
	# 6) ⭐ THE PRESS ITSELF, MID-FLIGHT, WHILE STILL BLIND.
	_arms.append({"tag": "midpress", "rho": 0.0, "press": RUNG_OFF})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `snr` and the slider to its
	# authored 0.0 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", RUNG_ON)) != RUNG_ON:
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": str(arm["rung"])})
	_client.send(_set_param_cmd(MID, "seeker_search_rate_dps", float(arm["rho"])))
	if arm.has("press"):
		_pending_press = str(arm["press"])
		_t_target = PRESS_AT * _dt
		_client.send({"type": "step", "n": PRESS_AT})
	elif arm.has("drag"):
		_pending_drag = float(arm["drag"])
		_t_target = DRAG_AT * _dt
		_client.send({"type": "step", "n": DRAG_AT})
	else:
		_t_target = STEPS * _dt
		_client.send({"type": "step", "n": STEPS})

func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var blind: bool = str(arm.get("rung", RUNG_ON)) == RUNG_ON
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate,
		"tacq": _t_acq, "tlock": _t_lock_key, "auth": _auth_peak,
		"searching": _n_searching, "boxkey": _n_boxkey,
		"az_at": _az_at, "el_at": _el_at, "az_min": _az_min, "el_min": _el_min,
		"sign": _n_sign, "az": _az_seen, "el": _el_seen, "stop": _stop_seen,
		"rate": _rate_seen, "rho_seen": _rho_seen, "racq": _racq_peak,
		"rho": float(arm["rho"]), "blind": blind,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S55V_ARM   %-9s rho=%6.1f deg/s rung=%-4s  ->  t_acq=%s  t_lock=%s  R_acq=%9.4f m  " +
		   "margins az=%+7.3f el=%+7.3f  auth=%5.1f%%  miss=%9.4f  search_frames=%d") %
		  [tag, m["rho"], RUNG_ON if blind else RUNG_OFF, _lock_str(m["tacq"]), _lock_str(m["tlock"]),
		   m["racq"], m["az_at"], m["el_at"], 100.0 * m["auth"], m["miss"], m["searching"]])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA") %
				[tag, STEPS, _min_los])
	# THE AUTHORED WINDOW, ON EVERY ARM: nothing in this file touches it, and the PRODUCT is the
	# aperture the whole comparison holds fixed.
	if not (_az_seen == WIN_AZ and _el_seen == WIN_EL):
		return (("arm %s: the window must be the AUTHORED %.1f° az x %.1f° el (got %.4f x %.4f). " +
				"⚠⚠ THE PAIR IS THE POINT: change one of them and the seeker's REACH moves too, " +
				"and the comparison against slice 48 stops being about the SHAPE at all — the exact " +
				"error this slice's own gate 0 made and had to publish (27 arms of it)") %
				[tag, WIN_AZ, WIN_EL, _az_seen, _el_seen])
	if not (absf(_az_seen * _el_seen - WIN_AREA) < EXACT):
		return ("arm %s: the two half-widths must MULTIPLY to %.1f deg^2 — the aperture of the %.1f° " +
				"disc slice 48 ships (got %.6f)") % [tag, WIN_AREA, GAIN_DISC, _az_seen * _el_seen]
	if not (_stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH):
		return (("arm %s: the trunnion / servo must be the AUTHORED %.1f / %.1f (got %.3f / %.3f) — " +
				"⚠ the STOP is still CIRCULAR behind a rectangular window, which is a documented " +
				"mismatch (slice 45 measured a per-axis stop to be worth nothing) and not an " +
				"oversight") % [tag, STOP_AUTH, RATE_AUTH, _stop_seen, _rate_seen])
	# ⚠ THE SLIDER'S OWN TRIPWIRE (slice 19's discipline): the sweep rate is READ BACK OFF THE WIRE,
	# so each arm proves the slider reached THE PHYSICS rather than merely being accepted by the
	# server. ⚠⚠ AND ON THIS WIRE THAT IS THE **WHOLE** POINT OF THE NULL: a knob that never
	# arrived would produce the same identical trajectories and mean nothing at all.
	var rho_want: float = float(arm["drag"]) if arm.has("drag") else float(arm["rho"])
	if not (absf(_rho_seen - rho_want) < EXACT):
		return (("arm %s: the wire must report the sweep rate the slider sent (%.4f vs %.4f) — a " +
				"set_param that is accepted and never consumed passes every other check in this " +
				"file, and would turn this slice's NULL into a dead knob") %
				[tag, _rho_seen, rho_want])
	# ⭐⭐⭐ THE SIGN IDENTITY: the margin pair IS the flying predicate. The window is the ∞-norm, so
	# a look is inside iff NEITHER axis is over — a valid frame with a negative margin on either
	# axis would mean the readout and the gate are two different opinions.
	if _n_sign > 0:
		return (("arm %s: %d frames report the target AVAILABLE while a per-axis margin is negative " +
				"— the pair is built from the same numbers `off_axis_ratio` consumes, so this is " +
				"the readout and the gate disagreeing") % [tag, _n_sign])
	# ⚠ SLICE 48's OWN GAUGE IS UNDEFINED HERE, ON EVERY ARM, AND IT MUST STAY THAT WAY.
	if _t_lock_key >= 0.0:
		return (("arm %s: `search_t_lock_s` must be the sentinel −1.0 on this wire (got %.4f) — a " +
				"stamped search clock would mean the head ENTERED the search arm, and this slice's " +
				"whole claim is that a fan beam wide enough to hold the cue error never has to") %
				[tag, _t_lock_key])
	if _n_searching > 0:
		return (("arm %s: the head must never enter the search state BEFORE it acquires (got %d " +
				"sweeping frames, first at t = %.3f s) — " +
				"*you only search because you were blind, and this seeker was not*") %
				[tag, _n_searching, _t_srch_first])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var au: Dictionary = _res["authored"]

	# ── 1. THE SHIPPED ARM: it acquires, and it hits ──────────────────────────────────────────
	if not (absf(float(au["tacq"]) - T_ACQ) < T_ACQ_TOL):
		return _fail("authored: the acquisition instant must be %.3f s (got %s)" %
					 [T_ACQ, _lock_str(au["tacq"])])
	if not (float(au["miss"]) < HIT_MAX):
		return _fail(("authored: this window must HIT (%.4f m against a %.1f m rail) — slice 48's " +
					  "disc of the SAME aperture misses the same target by %.2f m on the same " +
					  "geometry, having never acquired at all") %
					 [au["miss"], HIT_MAX, MISS_DISC])
	if not (int(au["boxkey"]) > 100):
		return _fail("authored: the two-axis window's own keys must be on the wire (got %d frames)" %
					 int(au["boxkey"]))

	# ── 2. ⭐⭐⭐ THE HELD APERTURE — the one number the rival rests on ─────────────────────────
	if not (absf(float(au["racq"]) - R_ACQ) < R_ACQ_TOL):
		return _fail(("⭐⭐⭐ authored: the horizon must be slice 48's OWN %.4f m (got %.4f). This is " +
					  "the whole claim: `G = eta*4pi/(theta_az*theta_el)`, so 12.5 x 8.0 = 100 = " +
					  "10 x 10 costs the same gain and reaches the same distance. If this drifts, " +
					  "the wire is measuring REACH and calling it SHAPE — and a shape that also " +
					  "bought reach is 'a wider window is free' (42/43, killed by 46) wearing a " +
					  "rectangle") % [R_ACQ, au["racq"]])

	# ── 3. ⭐⭐ THE MARGIN PAIR — the lesson in two numbers ────────────────────────────────────
	var el_frac := float(au["el_at"]) / WIN_EL
	var az_frac := float(au["az_at"]) / WIN_AZ
	if not (el_frac > EL_FRAC_MIN):
		return _fail(("authored: at acquisition the elevation half-width must be essentially UNUSED " +
					  "(%.4f of it left, against a %.2f floor) — only %.3f° of the 8° is doing any " +
					  "work at all") % [el_frac, EL_FRAC_MIN, WIN_EL - float(au["el_at"])])
	if not (az_frac < AZ_FRAC_MAX):
		return _fail(("authored: at acquisition most of the AZIMUTH half-width must be SPENT " +
					  "(%.4f left, against a %.2f ceiling) — the cue error is 11.34° against a " +
					  "12.5° window, which is the whole reason this shape acquires at all") %
					 [az_frac, AZ_FRAC_MAX])
	if not (el_frac > 2.5 * az_frac):
		return _fail(("⭐⭐⭐ authored: THE TWO AXES MUST BE WILDLY UNEQUALLY USED (az %+.3f°, el %+.3f°) — " +
					  "that inequality IS the slice. The azimuth half-width is spent down to a " +
					  "sliver on the axis the cue error is actually in, while all but a fiftieth " +
					  "of a degree of the elevation half-width sits unused. A round window of the " +
					  "same cost spends 10° on that idle axis, which is the 1.14° of azimuth it " +
					  "does not have") % [au["az_at"], au["el_at"]])

	# ── 4. ⭐ DETERMINISM ─────────────────────────────────────────────────────────────────────
	if _max_pos_diff(au["pos"], _res["replay"]["pos"]) > 0.0:
		return _fail("replay: same seed + same slider + same rung must be BIT-identical (max Δpos %.3e m)" %
					 _max_pos_diff(au["pos"], _res["replay"]["pos"]))

	# ── 5. ⭐⭐⭐ THE NULL, WITH ITS BOUND — the slider does nothing, and it is LIVE ────────────
	for tag in ["r60", "r120", "r240", "drag"]:
		var a: Dictionary = _res[tag]
		var d := _max_pos_diff(au["pos"], a["pos"])
		if d > 0.0:
			return _fail(("⭐⭐⭐ %s: slice 48's headline slider must be INERT on this wire — the " +
						  "trajectory must be BIT-identical to the authored arm (max Δpos %.3e m at " +
						  "rho = %.0f °/s). On slice 48's disc this same slider runs 1039.88 m down " +
						  "to 0.31 m; here nothing moves, because the target was never lost") %
						 [tag, d, a["rho_seen"]])
		if not (float(a["tacq"]) == float(au["tacq"])):
			return _fail("%s: the acquisition instant must be unmoved (%s vs %s)" %
						 [tag, _lock_str(a["tacq"]), _lock_str(au["tacq"])])
	# ⚠⚠ …AND THE KNOB REACHED THE WIRE ON EVERY ONE OF THEM, WHICH IS WHAT MAKES THIS A MEASURED
	# NULL RATHER THAN A DEAD KNOB. The drag arm carries it hardest: the value changed MID-FLIGHT,
	# the wire reports the new one, and the missile does not notice.
	if not (float(_res["drag"]["rho_seen"]) == RHO_TOP):
		return _fail(("drag: the wire must report %.0f °/s after the mid-flight drag (got %.4f) — " +
					  "without this the identical trajectory proves nothing at all") %
					 [RHO_TOP, _res["drag"]["rho_seen"]])
	if _max_pos_diff(_res["r240"]["pos"], _res["drag"]["pos"]) > 0.0:
		return _fail("drag: a rate dragged in mid-blind must land on the from-launch arm's own flight")

	# ── 6. ⭐⭐ THE BUTTON — and the 0.0 that proves the sentinel had to be −1.0 ────────────────
	var lo: Dictionary = _res["off_lo"]
	var hi: Dictionary = _res["off_hi"]
	if _max_pos_diff(lo["pos"], hi["pos"]) > 0.0:
		return _fail(("off_lo/off_hi: with the horizon OFF there is no blind phase at ANY sweep " +
					  "rate, so the two ends of the slider must be BIT-identical (max Δpos %.3e m)") %
					 _max_pos_diff(lo["pos"], hi["pos"]))
	if not (float(lo["racq"]) == 0.0):
		return _fail("off_lo: with `seeker_detect: none` there is no horizon to report (got %.4f m)" %
					 lo["racq"])
	if not (float(lo["tacq"]) == 0.0):
		return _fail(("⭐⭐ off_lo: the acquisition latch must read a REAL 0.0 here — the window holds " +
					  "the target from the very first tick once the receiver is free (got %s). This " +
					  "arm is why the sentinel is −1.0 and not zero: a client's `.get(k, 0.0)` must " +
					  "not be able to print 'acquired at once' for 'never acquired'") %
					 _lock_str(lo["tacq"]))
	if not (float(lo["miss"]) < HIT_MAX):
		return _fail("off_lo: with no horizon this window hits trivially (got %.4f m)" % lo["miss"])

	# ── 7. ⭐ THE PRESS, MID-FLIGHT ───────────────────────────────────────────────────────────
	var mp: Dictionary = _res["midpress"]
	if not (absf(float(mp["tacq"]) - T_PRESS_ACQ) < T_ACQ_TOL):
		return _fail(("midpress: pressing the button at %.2f s must move the acquisition instant to " +
					  "%.3f s (got %s) — the horizon is what was holding the seeker blind, and it " +
					  "is also the entire reason a window's SHAPE is a design decision at all") %
					 [PRESS_AT * _dt, T_PRESS_ACQ, _lock_str(mp["tacq"])])
	if not (float(mp["miss"]) < HIT_MAX):
		return _fail("midpress: the press arm must still hit (got %.4f m)" % mp["miss"])

	print("S55V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice55_fanbeam":
		return "wrong scenario '%s' — run scenarios/slice55_fanbeam.yaml" % str(f.get("name", ""))
	# ⭐⭐⭐ THE 15th MARKER, AND IT IS THE ONE THAT SEPARATES THIS WIRE FROM SLICE 48's. This file
	# authors slice 48's search anchor, so `search_view` is raised HERE TOO and can no longer tell
	# the two apart — and slice 48's block would draw its SWEEP gauge, which is the one number that
	# does not exist on this wire.
	if not bool(f.get("fanbeam_view", false)):
		return ("a slice-55 handshake must ship fanbeam_view=true — it is raised on the " +
				"`gimbal_fov_el_deg` comp key, so the gate is a CAPABILITY (any wire that authors " +
				"a two-axis window) rather than a file. Without it the client draws slice 48's " +
				"block, whose gauge is a sweep clock that never stamps here, and reports 'NOT " +
				"SEARCHING: head frozen' over a 0.09 m intercept")
	for k in ["search_view", "midcourse_view", "seeker_detect_view", "gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-55 wire IS a slice-48 wire with its detector window turned on its " +
					"side, so it must still raise %s — the superset relation is what makes the new " +
					"marker a BRANCH SELECTOR rather than a hole plug") % k
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view",
			  "search_realized_view", "seeker_aspect_view"]:
		if bool(f.get(k, false)):
			return ("a slice-55 wire must NOT raise %s — it would either put a second mechanism " +
					"beside this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "seeker_search_rate_dps":
		return ("exactly ONE knob, the MISSILE's `seeker_search_rate_dps` (convention 9), and it is " +
				"slice 48's OWN slider INHERITED so the A/B is exact — it is here to be measured as " +
				"INERT. ⚠⚠ `gimbal_fov_el_deg` is THE OBVIOUS CANDIDATE AND IT IS THE TRAP: " +
				"dragging it alone moves the PRODUCT, hence the gain, hence the horizon, so it " +
				"would teach REACH while appearing to teach SHAPE. Holding the aperture needs BOTH " +
				"keys moved together and `set_param` carries one Float64 ⇒ the shape is AUTHORED " +
				"and the contrast is against a SECOND FILE, which is what a RIVAL is")
	if not (float(kn[0].get("min", -1.0)) == 0.0 and float(kn[0].get("max", 0.0)) == RHO_TOP):
		return ("the slider must span slice 48's own 0–%.0f °/s, unchanged — a null measured over a " +
				"different domain from the lesson it is a null of would prove nothing") % RHO_TOP
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _t_acq = -1.0; _t_lock_key = -1.0; _auth_peak = 0.0
	_n_searching = 0; _n_boxkey = 0; _n_sign = 0
	_az_at = NAN; _el_at = NAN; _az_min = 1.0e30; _el_min = 1.0e30
	_az_seen = 0.0; _el_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0; _rho_seen = -1.0
	_racq_peak = 0.0; _t_srch_first = -1.0
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
	var mp: Array = _missile_pos(f)
	if mp.is_empty():
		return
	_pos_trace.append(mp)
	var los := float(tel.get(MID + ".los_range", 1.0e30))
	# ⚠ FIRST-DESCENDING-BAND ONLY: once the range turns, the post-CPA re-crossings are a different
	# engagement — and they climb back through the 200 m gate from the FAR side.
	if _closing:
		if los > _prev_los and _prev_los < 1.0e29:
			_closing = false
			_turned = true
		else:
			_min_los = minf(_min_los, los)
	_prev_los = los
	if not _closing:
		return
	_az_seen = float(tel.get(MID + ".gimbal_fov_deg", _az_seen))
	_el_seen = float(tel.get(MID + ".gimbal_fov_el_deg", _el_seen))
	_stop_seen = float(tel.get(MID + ".gimbal_stop_deg", _stop_seen))
	_rate_seen = float(tel.get(MID + ".gimbal_rate_dps", _rate_seen))
	_rho_seen = float(tel.get(MID + ".search_rate_dps", _rho_seen))
	_racq_peak = maxf(_racq_peak, float(tel.get(MID + ".seeker_r_acq_m", 0.0)))
	# ⚠⚠ BOTH SEARCH GAUGES ARE READ **BEFORE THE ACQUISITION ONLY**, and that is not a convenience.
	# This missile flies through the target and out the other side; from ~9.18 s the seeker has lost
	# a target that is now BEHIND it and the head starts hunting again, exactly as it should. That
	# episode is a different engagement (slice 52 met the same post-intercept re-search and fenced
	# it off the same way), and counting it would make "the head never had to search" false for a
	# reason that has nothing to do with the window's shape.
	if _t_acq < 0.0:
		_t_lock_key = maxf(_t_lock_key, float(tel.get(MID + ".search_t_lock_s", -1.0)))
		if float(tel.get(MID + ".head_searching", 0.0)) >= 0.5:
			_n_searching += 1
			if _t_srch_first < 0.0:
				_t_srch_first = float(f.get("t", -1.0))
	# ⭐⭐⭐ THIS SLICE'S OWN KEYS — the two-axis window's margins and the core's acquisition latch.
	# ⚠ THE LATCH IS READ, NEVER DIFFERENCED HERE: `gimbal_valid` beside it is LIVE and this client
	# sees one frame in 16 ticks, so a client-side first-valid-frame stamp would be quantized to the
	# emit grid — slice 53's rule that a quantity counted in SAMPLES changes meaning when the sample
	# rate does.
	if tel.has(MID + ".gimbal_fov_el_margin_deg"):
		_n_boxkey += 1
		var am := float(tel[MID + ".gimbal_fov_az_margin_deg"])
		var bm := float(tel[MID + ".gimbal_fov_el_margin_deg"])
		_az_min = minf(_az_min, am)
		_el_min = minf(_el_min, bm)
		var avail := float(tel.get(MID + ".gimbal_valid", 0.0)) >= 0.5
		if avail:
			if am < 0.0 or bm < 0.0:
				_n_sign += 1
			if is_nan(_az_at):
				_az_at = am
				_el_at = bm
		_t_acq = float(tel.get(MID + ".gimbal_t_acq_s", -1.0))
	if los > 200.0:
		_n_gate += 1
		if _t_acq >= 0.0:
			_auth_peak = maxf(_auth_peak, float(tel.get(MID + ".a_cmd_frac", 0.0)))

func _lock_str(tl: float) -> String:
	return "NEVER" if tl < 0.0 else "%.4f s" % tl

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

# ⚠ THE FIELD IS `target`, NOT `entity` — slice 40's own first-run bug. ⚠ AND THE TARGET IS `m1`:
# the search is the MISSILE's own seeker.
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
	push_error("S55V FAIL: " + msg)
	print("S55V FAIL: ", msg)
	quit(code)
	return true
