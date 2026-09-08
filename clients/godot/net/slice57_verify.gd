extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-57 gate-3 verifier — **THE APERTURE IS A BUDGET, AND THE SHAPE IS BOUNDED AT BOTH
# ENDS.** Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn
# renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice57_aspect.yaml
#   godot --headless --path clients/godot --script res://net/slice57_verify.gd     (exit 0 = pass)
#
# THE LESSON. A window costs what its PRODUCT costs (`G = eta*4pi/Omega`, `Omega = theta_az*theta_el`).
# Hold the product and the shape is free to move — but only inside a band: the head acquires iff some
# look sits inside BOTH half-widths, i.e. `A^2/w <= r <= w/E^2`, which is non-empty iff `A*E <= w`.
# On this wire A = 10.9614 deg and E = 2.2549 deg, so the band is PREDICTED [1.202, 19.668] before
# any arm flies. This file flies arms either side of BOTH walls.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE IS A **PAIR**: the slider changes lock/no-lock at two
# places, and `seeker_r_acq_m` NEVER MOVES — 3038.1613444 m on every single arm, acquiring or not.
# Without the second half the first is "a wider window is free" (42/43, killed by 46) wearing a
# slider. With it, every degree of azimuth is visibly paid for in elevation.
#
# ⭐⭐⭐ AND THE SECOND CLAIM IS A **NULL WITH ITS BOUND**, which is why this slice is a REGIME and
# not a CURVE. INSIDE the band every arm is BIT-IDENTICAL — 1.25 through 19.0, a factor of 15.2 in
# shape, the same 9600 ticks to the last bit. The mechanism is not "shape does not matter": the
# window decides WHETHER and the link budget decides WHEN (the acquisition instant equals the
# horizon crossing), so once the same look is accepted every downstream state is the same bits.
# ⇒ **A BIT-IDENTICAL FLIGHT IS NOT AN EQUALLY GOOD DESIGN.** The two end arms of that identical
# flight each sit a fraction of a degree from a cliff, at OPPOSITE ends, and only the MARGIN PAIR
# knows it. This file asserts exactly that: same bits, opposite margins.
#
# ⚠⚠ THE GAUGE THIS SLICE PRE-REGISTERED WAS `search_t_lock_s` AND GATE 0 REFUSED IT TWICE — it
# reads -1.0 for the whole intercept (the head is CUED and never sweeps, slice 55's finding) and
# where an acquisition instant exists it is the RANGE crossing, i.e. the link budget's number and
# not the window's. A number that cannot rank two windows is not this slice's gauge; the MARGINS
# are. See `docs/LESSONS.md`:880.
#
# ⚠ THE MISS IS NOT THE GAUGE (`docs/PROHIBITIONS.md` §2) — it is a bound here, and a loose one: a
# HIT samples COARSELY on a 16-tick emit grid where a MISS samples faithfully
# ([[ewsim-missile-verifier-sampling]]).
# ⚠ THE MARGINS ARE ASSERTED AS FRACTIONS OF THEIR OWN HALF-WIDTHS, slice 55's discipline verbatim:
# the client sees one frame in 16 ticks, so the first VALID frame is up to 15 ticks late and the
# head has slewed further on by then (+0.83 deg of azimuth here). The DEGREES are a joint property
# of the geometry and the emit grid; the FRACTIONS are the claim.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16) or `_drain_scan` waits forever,
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 9600 = 16 * 600.
const STEPS := 9600
const DRAG_AT := 3200             # a multiple of 16, and MID-BLIND — before the 4.939 s acquisition

const RUNG_ON := "snr"
const RUNG_OFF := "none"

# THE BUDGET. The AUTHORED pair is 12.5 x 8.0 = 100 deg^2 and it is NOT what flies: the aspect key
# re-shapes it, so the shipped arm flies (20.0, 5.0). Holding the PRODUCT is the whole comparison.
const WIN_AREA := 100.0
const ASPECT_AUTH := 4.0
const WIN_AZ_AUTH := 20.0         # = sqrt(100 * 4)
const WIN_EL_AUTH := 5.0          # = sqrt(100 / 4)
const STOP_AUTH := 45.0
const RATE_AUTH := 240.0

# ⭐⭐⭐ THE HELD APERTURE, AS METRES — slice 48/55's own horizon, on every arm of the slider.
const R_ACQ := 3038.1613444
const R_ACQ_TOL := 1.0e-4         # metres — this is an identity, not a fit

const T_ACQ := 4.939
const T_ACQ_TOL := 0.02           # s — the 16-tick emit grid is 0.016 s
const HIT_MAX := 10.0             # ⚠ a HIT samples COARSELY: the true CPA is 0.05 m. A sanity rail.
const MISS_BAND := 500.0          # …and a no-acquisition arm is nowhere near it (1021.18 m)

# THE PREDICTED WALLS, FROM THE TWO POINTING ERRORS — recomputed here rather than copied, so this
# file states the LAW and not a pair of remembered numbers.
const ERR_AZ := 10.9614
const ERR_EL := 2.2549
const SLIDER_MIN := 0.5
const SLIDER_MAX := 40.0

# The margin fractions at the two END arms of the band (frame-sampled, hence these bounds).
const FRAC_TIGHT := 0.12          # the spent axis at each wall: az/a = 0.0942, el/b = 0.0927
const FRAC_LOOSE := 0.60          # …and the idle one: el/b = 0.7673, az/a = 0.7677
const EXACT := 1.0e-9

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
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
var _n_searching := 0
var _n_boxkey := 0
var _az_at := NAN
var _el_at := NAN
var _n_sign := 0
var _az_seen := 0.0
var _el_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _asp_seen := -1.0
var _racq_peak := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S57V_INIT godot=", Engine.get_version_info().string)
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
	# ALL, so [step K, set_param, step N-K] sent back-to-back applies the drag at tick 0 and
	# silently measures a from-launch arm instead (slice 37's finding).
	if _pending_drag >= 0.0:
		var asp_new := _pending_drag
		_pending_drag = -1.0
		_client.send(_set_param_cmd(MID, "gimbal_fov_aspect", asp_new))
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
	_arms.append({"tag": "authored", "asp": ASPECT_AUTH, "acq": true})
	# 2) ⭐ DETERMINISM — same seed, same slider ⇒ the same missile to the last bit.
	_arms.append({"tag": "replay", "asp": ASPECT_AUTH, "acq": true})
	# 3) ⭐⭐⭐ INSIDE THE BAND, ACROSS 15.2x OF SHAPE — every one acquires, and every one is
	#    BIT-IDENTICAL to the authored arm. This is the NULL, and it is the honest half of the
	#    slice: `docs/LESSONS.md`:880 disqualifies a flat interior as a RANKING gauge, so it is
	#    shipped as a measured absence WITH its bound rather than dressed up as a curve.
	_arms.append({"tag": "in_lo", "asp": 1.25, "acq": true})
	_arms.append({"tag": "in_2", "asp": 2.0, "acq": true})
	_arms.append({"tag": "in_8", "asp": 8.0, "acq": true})
	_arms.append({"tag": "in_hi", "asp": 19.0, "acq": true})
	# 4) ⭐⭐⭐ OUTSIDE IT, AT BOTH ENDS, AND THEY FAIL FOR **DIFFERENT** REASONS — the low arms have
	#    too little AZIMUTH for a 10.96 deg cue error, the high ones too little ELEVATION for a
	#    2.25 deg one. Two walls, one budget. ⚠ Each pair straddles a wall by one slider step.
	_arms.append({"tag": "out_floor", "asp": SLIDER_MIN, "acq": false})
	_arms.append({"tag": "out_lo", "asp": 1.20, "acq": false})
	_arms.append({"tag": "out_hi", "asp": 19.7, "acq": false})
	_arms.append({"tag": "out_ceil", "asp": SLIDER_MAX, "acq": false})
	# 5) ⭐⭐⭐ THE LIVE DRAG, MID-BLIND, IN **BOTH** DIRECTIONS — the one path no other proof walks
	#    (`docs/PROHIBITIONS.md` §6 retracted the ban on dragging inside a verifier). A window that
	#    is re-shaped while the missile is still flying its belief must land on the from-launch arm
	#    of the shape it was dragged TO, in either direction. ⚠ This is also the slider's tripwire:
	#    the wire reports the ratio back, so a `set_param` that is accepted and never consumed
	#    cannot pass.
	_arms.append({"tag": "drag_out", "asp": ASPECT_AUTH, "drag": 25.0, "acq": false})
	_arms.append({"tag": "drag_in", "asp": 25.0, "drag": ASPECT_AUTH, "acq": true})
	# 6) ⭐⭐ THE BUTTON, AT BOTH ENDS OF THE SLIDER AND OUTSIDE THE BAND AT BOTH. With the horizon
	#    off there is no blind phase, so the picture error never grows and the head is on target
	#    from the first tick — **BOTH WALLS DISAPPEAR AT ONCE**, which is the sharpest statement of
	#    why an aperture is a budget: it is one only because reach is finite.
	_arms.append({"tag": "off_lo", "asp": SLIDER_MIN, "rung": RUNG_OFF, "acq": true})
	_arms.append({"tag": "off_hi", "asp": SLIDER_MAX, "rung": RUNG_OFF, "acq": true})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `snr` and the slider to its
	# authored 4.0 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", RUNG_ON)) != RUNG_ON:
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": str(arm["rung"])})
	_client.send(_set_param_cmd(MID, "gimbal_fov_aspect", float(arm["asp"])))
	if arm.has("drag"):
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
	var asp_want: float = float(arm["drag"]) if arm.has("drag") else float(arm["asp"])
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate,
		"tacq": _t_acq, "tlock": _t_lock_key, "boxkey": _n_boxkey,
		"az_at": _az_at, "el_at": _el_at, "sign": _n_sign,
		"az": _az_seen, "el": _el_seen, "stop": _stop_seen, "rate": _rate_seen,
		"asp_seen": _asp_seen, "racq": _racq_peak, "asp": asp_want, "blind": blind,
		"acq_want": bool(arm["acq"]), "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S57V_ARM   %-10s aspect=%6.2f rung=%-4s  ->  window=%7.4f x %6.4f  t_acq=%s  " +
		   "R_acq=%9.4f m  margins az=%+8.3f el=%+7.3f  miss=%9.4f") %
		  [tag, m["asp"], RUNG_ON if blind else RUNG_OFF, m["az"], m["el"], _lock_str(m["tacq"]),
		   m["racq"], m["az_at"], m["el_at"], m["miss"]])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA") %
				[tag, STEPS, _min_los])
	# ⭐⭐⭐ THE ONE NUMBER THE WHOLE SLICE RESTS ON, ON **EVERY** ARM: the product of the two
	# half-widths is the authored budget. If this drifts by a digit the slider is buying reach and
	# calling it shape — which is 'a wider window is free' (42/43, killed by 46) wearing a slider.
	if not (absf(_az_seen * _el_seen - WIN_AREA) < 1.0e-6):
		return (("arm %s: the two half-widths must MULTIPLY to the authored %.1f deg^2 (got %.4f x " +
				"%.4f = %.9f). ⚠⚠ THE PRODUCT IS THE BUDGET: the aspect slider re-shapes it and " +
				"must never spend it, or this wire measures REACH and calls it SHAPE") %
				[tag, WIN_AREA, _az_seen, _el_seen, _az_seen * _el_seen])
	# ⚠ THE SLIDER'S OWN TRIPWIRE (slice 19's discipline): the RATIO is read back off the wire, so
	# each arm proves the slider reached THE PHYSICS rather than merely being accepted by the
	# server. ⚠⚠ It is checked against the two half-widths the wire ALSO reports, which is what
	# makes it a consistency check and not a restatement of what was sent.
	if not (absf(_az_seen / _el_seen - asp_want) < 1.0e-6):
		return (("arm %s: the wire's own half-widths must carry the ratio the slider sent " +
				"(%.6f vs %.6f) — a set_param that is accepted and never consumed passes every " +
				"other check in this file") % [tag, _az_seen / _el_seen, asp_want])
	if not (_stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH):
		return (("arm %s: the trunnion / servo must be the AUTHORED %.1f / %.1f (got %.3f / %.3f) — " +
				"⚠ the STOP is still CIRCULAR behind a rectangular window, slice 55's documented " +
				"mismatch, inherited") % [tag, STOP_AUTH, RATE_AUTH, _stop_seen, _rate_seen])
	# ⭐⭐⭐ THE SIGN IDENTITY: the margin pair IS the flying predicate. The window is the ∞-norm, so
	# a look is inside iff NEITHER axis is over — a valid frame with a negative margin on either
	# axis would mean the readout and the gate are two different opinions.
	if _n_sign > 0:
		return (("arm %s: %d frames report the target AVAILABLE while a per-axis margin is negative " +
				"— the pair is built from the same numbers `off_axis_ratio` consumes, so this is " +
				"the readout and the gate disagreeing") % [tag, _n_sign])
	# ⚠ SLICE 48's OWN GAUGE IS UNDEFINED HERE, ON EVERY ARM, AND IT MUST STAY THAT WAY.
	if _t_lock_key >= 0.0:
		return (("arm %s: `search_t_lock_s` must be the sentinel -1.0 on this wire (got %.4f) — a " +
				"stamped search clock would mean the head ENTERED the search arm, and this whole " +
				"engagement is CUED") % [tag, _t_lock_key])
	if _n_searching > 0:
		return ("arm %s: the head must never enter the search state (got %d sweeping frames)" %
				[tag, _n_searching])
	# ⭐⭐⭐ THE BAND ITSELF, ARM BY ARM.
	var acq := _t_acq >= 0.0
	if acq != bool(arm["acq"]):
		return (("⭐⭐⭐ arm %s (aspect %.2f): expected %s. The band is A^2/w <= r <= w/E^2 with " +
				"A = %.4f deg, E = %.4f deg and w = %.1f deg^2, i.e. [%.3f, %.3f] — PREDICTED from " +
				"the two pointing errors, never fitted to the flights. A wall in the wrong place " +
				"means the law is wrong, and that is worth more than this slice's headline") %
				[tag, asp_want, "ACQUISITION" if bool(arm["acq"]) else "NO acquisition",
				 ERR_AZ, ERR_EL, WIN_AREA, ERR_AZ * ERR_AZ / WIN_AREA, WIN_AREA / (ERR_EL * ERR_EL)])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var au: Dictionary = _res["authored"]

	# ── 1. THE SHIPPED ARM: the authored pair is the BUDGET, not the flown window ─────────────
	if not (absf(float(au["az"]) - WIN_AZ_AUTH) < 1.0e-6 and
			absf(float(au["el"]) - WIN_EL_AUTH) < 1.0e-6):
		return _fail(("⭐⭐⭐ authored: this file must FLY (%.1f, %.1f) and not the authored " +
					  "(12.5, 8.0) — the pair sets the BUDGET (12.5 x 8.0 = 100 deg^2) and " +
					  "`gimbal_fov_aspect: %.1f` spends it. Reading the authored pair back means " +
					  "the loader's rewrite has stopped happening and the slider is decorative " +
					  "(got %.4f x %.4f)") %
					 [WIN_AZ_AUTH, WIN_EL_AUTH, ASPECT_AUTH, au["az"], au["el"]])
	if not (absf(float(au["tacq"]) - T_ACQ) < T_ACQ_TOL):
		return _fail("authored: the acquisition instant must be %.3f s (got %s)" %
					 [T_ACQ, _lock_str(au["tacq"])])
	if not (float(au["miss"]) < HIT_MAX):
		return _fail("authored: this window must HIT (%.4f m against a %.1f m rail)" %
					 [au["miss"], HIT_MAX])
	if not (int(au["boxkey"]) > 100):
		return _fail("authored: the two-axis window's own keys must be on the wire (got %d frames)" %
					 int(au["boxkey"]))

	# ── 2. ⭐⭐⭐ THE HELD APERTURE, ON EVERY ARM OF THE SLIDER ─────────────────────────────────
	for tag in _res.keys():
		var a: Dictionary = _res[tag]
		if not bool(a["blind"]):
			continue                       # the button removes the horizon by design — checked below
		if not (absf(float(a["racq"]) - R_ACQ) < R_ACQ_TOL):
			return _fail(("⭐⭐⭐ %s: the horizon must be %.4f m on EVERY arm (got %.4f). This is the " +
						  "half of the claim without which the other half is 'a wider window is " +
						  "free': the slider changes lock/no-lock at two places and the REACH never " +
						  "moves, so every degree of azimuth is paid for in elevation") %
						 [tag, R_ACQ, a["racq"]])

	# ── 3. ⭐ DETERMINISM ─────────────────────────────────────────────────────────────────────
	if _max_pos_diff(au["pos"], _res["replay"]["pos"]) > 0.0:
		return _fail("replay: same seed + same slider must be BIT-identical (max Δpos %.3e m)" %
					 _max_pos_diff(au["pos"], _res["replay"]["pos"]))

	# ── 4. ⭐⭐⭐ THE NULL, WITH ITS BOUND — 15.2x of shape, and the SAME BITS ──────────────────
	for tag in ["in_lo", "in_2", "in_8", "in_hi"]:
		var a: Dictionary = _res[tag]
		var d := _max_pos_diff(au["pos"], a["pos"])
		if d > 0.0:
			return _fail(("⭐⭐⭐ %s: inside the band every arm must be BIT-identical to the authored " +
						  "one (max Δpos %.3e m at aspect %.2f). The mechanism is not 'shape does " +
						  "not matter' — the window decides WHETHER and the link budget decides " +
						  "WHEN, so once the same look is accepted every downstream state is the " +
						  "same bits. This is shipped as a measured NULL with its bound, never as " +
						  "a curve (`docs/LESSONS.md`:880)") % [tag, d, a["asp"]])
		if not (float(a["tacq"]) == float(au["tacq"])):
			return _fail("%s: the acquisition instant must be unmoved (%s vs %s)" %
						 [tag, _lock_str(a["tacq"]), _lock_str(au["tacq"])])

	# ── 5. ⭐⭐⭐ …AND THE MARGINS SAY THOSE IDENTICAL FLIGHTS ARE NOT THE SAME DESIGN ──────────
	var lo: Dictionary = _res["in_lo"]
	var hi: Dictionary = _res["in_hi"]
	var lo_az := float(lo["az_at"]) / float(lo["az"])
	var lo_el := float(lo["el_at"]) / float(lo["el"])
	var hi_az := float(hi["az_at"]) / float(hi["az"])
	var hi_el := float(hi["el_at"]) / float(hi["el"])
	if not (lo_az < FRAC_TIGHT and lo_el > FRAC_LOOSE):
		return _fail(("in_lo: at the LOW wall the azimuth half-width must be nearly spent and the " +
					  "elevation one nearly idle (az %.4f of its own, el %.4f) — the arm fails by " +
					  "running out of AZIMUTH, and the margin is the only thing that says so") %
					 [lo_az, lo_el])
	if not (hi_el < FRAC_TIGHT and hi_az > FRAC_LOOSE):
		return _fail(("in_hi: at the HIGH wall it is the other way round (az %.4f, el %.4f) — this " +
					  "arm fails by running out of ELEVATION, and it flies the IDENTICAL " +
					  "trajectory to the one that fails for the opposite reason") % [hi_az, hi_el])
	if not (float(lo["az_at"]) < float(au["az_at"]) and float(au["az_at"]) < float(hi["az_at"])):
		return _fail("the azimuth margin must RISE across the band (%.3f, %.3f, %.3f)" %
					 [lo["az_at"], au["az_at"], hi["az_at"]])
	if not (float(lo["el_at"]) > float(au["el_at"]) and float(au["el_at"]) > float(hi["el_at"])):
		return _fail(("⭐⭐⭐ the elevation margin must FALL across the same band while the azimuth " +
					  "one rises (%.3f, %.3f, %.3f) — one budget, two axes, and the crossing is " +
					  "the design") % [lo["el_at"], au["el_at"], hi["el_at"]])

	# ── 6. ⭐⭐⭐ THE WALLS ARE PREDICTED, NOT FITTED ───────────────────────────────────────────
	var wall_lo := ERR_AZ * ERR_AZ / WIN_AREA
	var wall_hi := WIN_AREA / (ERR_EL * ERR_EL)
	if not (float(_res["out_lo"]["asp"]) < wall_lo and wall_lo <= float(lo["asp"])):
		return _fail(("⭐⭐⭐ the LOW wall must land inside its flown bracket (%.3f, %.3f] — " +
					  "predicted A^2/w = %.4f from the azimuth pointing error alone") %
					 [_res["out_lo"]["asp"], lo["asp"], wall_lo])
	if not (float(hi["asp"]) <= wall_hi and wall_hi < float(_res["out_hi"]["asp"])):
		return _fail(("⭐⭐⭐ the HIGH wall must land inside its flown bracket [%.3f, %.3f) — " +
					  "predicted w/E^2 = %.4f from the elevation pointing error alone") %
					 [hi["asp"], _res["out_hi"]["asp"], wall_hi])
	if not (ERR_AZ * ERR_EL < WIN_AREA):
		return _fail("a band exists at all only because A*E (%.3f) is below the aperture (%.1f)" %
					 [ERR_AZ * ERR_EL, WIN_AREA])

	# ── 7. ⭐⭐⭐ THE LIVE DRAG, BOTH WAYS ──────────────────────────────────────────────────────
	if _max_pos_diff(_res["drag_out"]["pos"], _res["out_hi"]["pos"]) > 0.0:
		return _fail(("drag_out: a window re-shaped OUT of the band mid-blind must land on the " +
					  "from-launch flight of the shape it was dragged to"))
	if _max_pos_diff(_res["drag_in"]["pos"], au["pos"]) > 0.0:
		return _fail(("⭐⭐ drag_in: and the same in reverse — a window dragged INTO the band while " +
					  "the missile is still flying its belief must land on the authored arm's own " +
					  "flight. Both directions, because a knob that only works one way is a latch"))

	# ── 8. ⭐⭐ THE BUTTON — the band exists only because the aperture is finite ────────────────
	var ol: Dictionary = _res["off_lo"]
	var oh: Dictionary = _res["off_hi"]
	if not (float(ol["racq"]) == 0.0 and float(oh["racq"]) == 0.0):
		return _fail("off_*: with `seeker_detect: none` there is no horizon to report (%.4f, %.4f)" %
					 [ol["racq"], oh["racq"]])
	if not (float(ol["tacq"]) == 0.0 and float(oh["tacq"]) == 0.0):
		return _fail(("⭐⭐ off_*: the acquisition latch must read a REAL 0.0 — with no horizon there " +
					  "is no blind phase, so the picture error never grows and the head is on " +
					  "target from the first tick (%s, %s). ⚠ This arm is why the sentinel is -1.0 " +
					  "and not zero") % [_lock_str(ol["tacq"]), _lock_str(oh["tacq"])])
	if _max_pos_diff(ol["pos"], oh["pos"]) > 0.0:
		return _fail(("⭐⭐⭐ off_lo/off_hi: with the horizon OFF, aspect %.1f and aspect %.1f — one " +
					  "outside EACH wall — must be BIT-identical, because BOTH WALLS ARE GONE. " +
					  "That is the sharpest statement of why an aperture is a budget: it is one " +
					  "only because reach is finite (max Δpos %.3e m)") %
					 [SLIDER_MIN, SLIDER_MAX, _max_pos_diff(ol["pos"], oh["pos"])])

	print("S57V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice57_aspect":
		return "wrong scenario '%s' — run scenarios/slice57_aspect.yaml" % str(f.get("name", ""))
	# ⚠ NO NEW MARKER, AND THAT IS DELIBERATE. This wire IS slice 55's with the picture error tilted
	# and the window's shape put on a slider, so it raises `fanbeam_view` and takes the SAME HUD.
	# The two files differ in an AUTHORED WINDOW and in which knob is live, never in an instrument —
	# a marker per FILE would make markers name files instead of capabilities.
	if not bool(f.get("fanbeam_view", false)):
		return ("a slice-57 handshake must ship fanbeam_view=true — it is raised on the " +
				"`gimbal_fov_el_deg` comp key, so the gate is a CAPABILITY (any wire that authors " +
				"a two-axis window) rather than a file, and this wire authors one")
	for k in ["search_view", "midcourse_view", "seeker_detect_view", "gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-57 wire IS a slice-55 wire with its window's shape on a slider, so it " +
					"must still raise %s — the superset relation is what keeps the marker a BRANCH " +
					"SELECTOR rather than a hole plug") % k
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view",
			  "search_realized_view", "seeker_aspect_view"]:
		if bool(f.get(k, false)):
			return ("a slice-57 wire must NOT raise %s — it would either put a second mechanism " +
					"beside this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "gimbal_fov_aspect":
		return ("exactly ONE knob, the MISSILE's `gimbal_fov_aspect` (convention 9). ⚠⚠ Dragging " +
				"`gimbal_fov_deg` or `gimbal_fov_el_deg` ALONE is the trap slice 55 named and " +
				"measured: it moves the PRODUCT, hence the gain, hence the horizon, so it teaches " +
				"REACH while appearing to teach SHAPE. Holding the aperture needs BOTH keys moved " +
				"together and `set_param` carries one Float64 ⇒ the author writes the pair (its " +
				"product is the budget) and the SLIDER carries the ratio")
	if not (float(kn[0].get("min", -1.0)) == SLIDER_MIN and
			float(kn[0].get("max", 0.0)) == SLIDER_MAX):
		return ("the slider must span %.1f–%.1f, which is chosen to put BOTH walls of the band " +
				"well inside it — a domain that clipped a wall would show a slice-48-shaped " +
				"monotone slider and hide the lesson") % [SLIDER_MIN, SLIDER_MAX]
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _t_acq = -1.0; _t_lock_key = -1.0
	_n_searching = 0; _n_boxkey = 0; _n_sign = 0
	_az_at = NAN; _el_at = NAN
	_az_seen = 0.0; _el_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0; _asp_seen = -1.0
	_racq_peak = 0.0
	_pos_trace.clear()

func _drain_scan() -> bool:
	while true:
		var f := _take("state")
		if f.is_empty():
			return false
		_scan(f)
		if float(f.get("t", 0.0)) >= _t_target - 1.0e-9:
			return true
	# ⚠ UNREACHABLE, AND REQUIRED: GDScript's flow analysis does not treat `while true` as
	# always-returning, so without this the whole FILE fails to parse (slice 55 carries the same
	# line for the same reason).
	return false

func _scan(f: Dictionary) -> void:
	var tel: Dictionary = f.get("telemetry", {})
	var mp: Array = _missile_pos(f)
	if mp.is_empty():
		return
	_pos_trace.append(mp)
	var los := float(tel.get(MID + ".los_range", 1.0e30))
	# ⚠ FIRST-DESCENDING-BAND ONLY: once the range turns, the post-CPA re-crossings are a different
	# engagement — and they climb back through the 200 m gate from the FAR side
	# ([[ewsim-missile-verifier-sampling]]).
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
	_racq_peak = maxf(_racq_peak, float(tel.get(MID + ".seeker_r_acq_m", 0.0)))
	# ⚠⚠ BOTH SEARCH GAUGES ARE READ **BEFORE THE ACQUISITION ONLY**, slice 55's fence verbatim:
	# this missile flies through the target and out the other side, and from ~9.2 s the head is
	# hunting a target that is now BEHIND it. That episode is a different engagement and counting it
	# would make "the head never had to search" false for a reason that has nothing to do with the
	# window's shape.
	if _t_acq < 0.0:
		_t_lock_key = maxf(_t_lock_key, float(tel.get(MID + ".search_t_lock_s", -1.0)))
		if float(tel.get(MID + ".head_searching", 0.0)) >= 0.5:
			_n_searching += 1
	# ⭐⭐⭐ THIS SLICE'S GAUGE — the two-axis margins, plus the core's acquisition latch.
	# ⚠ THE LATCH IS READ, NEVER DIFFERENCED HERE: this client sees one frame in 16 ticks, so a
	# client-side stamp would be quantized to the emit grid (slice 53's rule that a quantity counted
	# in SAMPLES changes meaning when the sample rate does).
	if tel.has(MID + ".gimbal_fov_el_margin_deg"):
		_n_boxkey += 1
		var am := float(tel[MID + ".gimbal_fov_az_margin_deg"])
		var bm := float(tel[MID + ".gimbal_fov_el_margin_deg"])
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

# ⚠⚠ THE FIELD IS `target`, NOT `id` AND NOT `entity` — slice 40's own first-run bug, and this file
# reproduced it verbatim on ITS first run. The server reads `cmd[:target]`, so a wrong field name
# does not error: the drag is simply never applied and every arm silently flies the AUTHORED shape.
# ⚠ The tripwire in `_finish_arm` (the wire must carry back the ratio the slider sent) is what
# caught it, which is exactly why slice 19's read-back discipline exists.
func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

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
		for k in range(3):
			d = maxf(d, absf(float(p[k]) - float(q[k])))
	return d

func _take(kind: String) -> Dictionary:
	for i in range(_inbox.size()):
		if str(_inbox[i].get("type", "")) == kind:
			var f: Dictionary = _inbox[i]
			_inbox.remove_at(i)
			return f
	return {}

func _lock_str(v: float) -> String:
	return "none" if v < 0.0 else "%.4f" % v

func _tag() -> String:
	return "none" if _idx < 0 or _idx >= _arms.size() else str(_arms[_idx]["tag"])

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _fail(msg: String, code := 1) -> bool:
	print("S57V FAIL  ", msg)
	quit(code)
	return true
