extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-52 gate-3 verifier — **HOW WIDE SHOULD A SEEKER SEARCH?**
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice52_coverage.yaml
#   godot --headless --path clients/godot --script res://net/slice52_verify.gd     (exit 0 = pass)
#
# THE LESSON. Slice 48 asked how FAST a blinded seeker should sweep and found one instruction:
# faster, up to the servo's own limit. This asks how WIDE, and the answer is not a maximum — it is
# a MATCH. Too narrow and the band never reaches the target at any duration; every degree wider
# than necessary is paid TWICE, in travel spent before the head ever looks at the right half of the
# sky.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE: **THE AXIS IS TWO-SIDED, AND SLICE 48's OWN
# AUTHORED NUMBER IS ON THE WRONG SIDE OF IT.** At 25° — the width slice 48 shipped and never
# varied — this missile finds the target every time, flies pinned at 100 % of its manoeuvre limit,
# and still misses by 32 m. At 6° it arrives at 7 cm having spent a quarter of the airframe. At
# 4.75° it never finds it at all. Nothing on slice 48's HUD could have said so, because slice 48
# never moved this knob.
#
# ⭐⭐⭐ AND THE SECOND CLAIM, WHICH IS WHY THIS SLICE SHIPS AN INSTRUMENT: **THE HEAD DOES NOT FLY
# THE COVERAGE YOU AUTHOR.** The command is a triangle of amplitude exactly S; between it and the
# sky sits a 0.05 s lag, and a sweep's period is `4S/ρ` — so the narrower the sweep the less of it
# survives. 27 % at 1°, 65 % at 5°, 95 % at 40°. At the cliff the gap to cover was 2.80°, the
# authored band 5.00°, and the FLOWN band 3.24° — which is what actually decides it.
#
# ⚠⚠ THE MISS IS FORBIDDEN AS THE GAUGE, in the same BIT-IDENTITY form slice 48 used: across the
# whole floor region (1 … 4.75°) the head sweeps for four seconds at four different widths and the
# missile flies the IDENTICAL trajectory to the last bit. Nothing the head does reaches the
# guidance until something is LOCKED. ⇒ the gauge is `search_t_lock_s`, the REACH (flown band vs
# the gap), and the authority as a THREE-REGION verdict.
#
# ⚠⚠ THE AUTHORITY IS **NOT MONOTONE IN S AND THIS FILE DOES NOT PRETEND IT IS** — and its regions
# sit the OPPOSITE way round from slice 48's: cheap immediately above the cliff (0.23 at 5°),
# climbing to pinned at 25–35°, then easing to 0.93 at 40° once the lock is so late that the
# geometry has run out. The monotone axis asserted here is `t_lock`, which RISES 0.266 → 1.638 s
# across the domain without a reversal — ⚠ rising, where slice 48's fell, because this knob's
# expensive end is up.
#
# ⚠⚠ NOTHING IS READ PAST THE FIRST LOCK OR OFF A LOCAL SLOPE (gate 2's two rules). `t_lock` is
# quantized at `dt`, so the 5 → 6 chord reads BELOW the kernel's own `2/ρ` bound by a third of a
# tick; the excess is read over a WIDE bracket or not at all.
#
# ⚠ EVERY NUMBER IS FRAME-SAMPLED (`emit_every = 16`) and the error is ASYMMETRIC — a MISS samples
# faithfully, a HIT samples COARSELY ([[ewsim-missile-verifier-sampling]]). The degrees and seconds
# below are read from LATCHED keys for exactly that reason.
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
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 11200 = 16 * 700, and it
# is sized off the LATEST CPA in the sweep (the wide arms lock at 6.6 s and fly on), not off the
# showcase arm's.
const STEPS := 11200
const PRESS_AT := 3200            # a multiple of 16, and BEFORE the 4.936 s handover, so the press
                                  # is what removes the blind phase
const DRAG_AT := 5296             # a multiple of 16, and MID-SEARCH (the sweep opens at 4936, the
                                  # authored 25° arm locks at 5959) — the drag arm's first leg

const RUNG_ON := "snr"
const RUNG_OFF := "none"

# THE SLIDER — the sweep's HALF-AMPLITUDE, degrees. ⚠ NEITHER ENDPOINT IS ZERO, which is the
# difference from slice 48's slider: a coverage of 0 is not a head that does not sweep, it is a
# search authored with nowhere to look, and the loader refuses it.
const S_FLOOR := 1.0              # the domain floor — a head that VISIBLY sweeps and never gets there
const S_LAST_FAIL := 4.75         # the last width that never acquires
const S_FIRST_LOCK := 5.00        # …and the first that does, a quarter of a degree away
const S_AUTH48 := 25.0            # ⭐⭐ slice 48's OWN authored coverage — pinned, and still missing
const S_TOP := 40.0               # the ceiling: the last cell the mechanical stop stays out of
const LADDER := [5.0, 6.0, 10.0, 16.0, 20.0, 25.0, 30.0, 35.0, 40.0]   # the LOCKING domain, in order

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const WIN_AUTH := 10.0            # the detector window (a RADIUS, not a full cone)
const STOP_AUTH := 45.0           # the trunnion — and the slider stops BELOW it, deliberately
const RATE_AUTH := 240.0          # slice 46's measured servo isolation, inherited
const RHO_AUTH := 60.0            # ⭐⭐ THE SWEEP RATE, AUTHORED — a measured choice, not a copy
const CROSS_SPEED := 200.0

# ⭐ THE HANDOVER, IDENTICAL ON EVERY ARM — the search cannot move it, because it starts there.
const CUE_HAND := 11.3371         # the latched cue error at the instant the receiver opened
const DEFICIT := 1.3423           # …minus the window: the gap the sweep has to cover at onset
const DEG_TOL := 0.15             # frame sampling + the servo's own lag

const T_HAND := 4.936             # s — when the receiver opens, on every arm
const HIT_MAX := 10.0             # a HIT, frame-sampled — a sanity bound, NEVER the lesson.
                                  # ⚠ TEN AND NOT FIVE, AND IT IS THE EMIT GRID RATHER THAN A
                                  # LOOSENING: **a HIT samples COARSELY** and a MISS faithfully
                                  # ([[ewsim-missile-verifier-sampling]]) — the 6° arm's true CPA
                                  # is 0.07 m and one frame in 16 reads it as 4.72. The bound still
                                  # separates it from the pinned arm's 32 m by more than 3×, which
                                  # is the only comparison it is asked to make.
const MISS_FLOOR := 1000.0        # the floor region's miss — a VERDICT, not metres
const MISS_PINNED := 30.0         # …and the PINNED region must still miss by more than this
const MISS_PRESS_MAX := 30.0      # the press arm's own bound (a HIT samples COARSELY)
const AUTH_PINNED := 0.99
const AUTH_CHEAP := 0.50
const HOLD_OK := 80.0             # % of post-lock frames with the target available
const EXACT := 1.0e-9

# ⭐⭐⭐ THE INSTRUMENT's OWN NUMBERS — the flown band as a fraction of the commanded one, measured
# over the ACQUISITION (the lock ends the measurement).
const FRAC_FLOOR := 0.2659        # at S = 1: the head flies barely a quarter of what it is told
const FRAC_TOP := 0.9492          # at S = 40
const FRAC_TOL := 0.01            # frame sampling — these are peaks read off a 16-tick grid

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0
var _pending_press := ""
var _pending_drag := 0.0          # ⭐ the MID-SEARCH drag arm — the one path no other proof walks

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}

var _min_los := 1.0e30
var _prev_los := 1.0e30
var _closing := true
var _turned := false
var _n_gate := 0
var _n_post := 0
var _n_held := 0
var _t_lock_frame := -1.0
var _auth_peak := 0.0
var _n_sat_pre := 0
var _n_sat_post := 0
var _n_cued := 0
var _n_searching := 0
var _cue_hand := 0.0
var _def_first := -1.0
var _def_max := 0.0
var _t_lock_key := -1.0
var _elapsed_max := 0.0
var _n_srchkey := 0
var _n_realkey := 0               # ⭐ frames carrying the slice's OWN instrument keys
var _told_peak := 0.0             # the COMMANDED peak, off the wire's own latch
var _flown_peak := 0.0            # …and the peak the head actually flew
# ⚠ THE **LAST** VALUES, NOT THE RUNNING MAXIMA. A peak-of-peaks cannot see a knob that FELL, which
# is exactly the bug the drag arm exists to catch: the running max would keep the pre-drag 21.84.
var _told_last := 0.0
var _flown_last := 0.0
var _head_peak := 0.0             # the body angle, for the trunnion claim
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _rho_seen := 0.0
var _cov_seen := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S52V_INIT godot=", Engine.get_version_info().string)
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
	if _pending_drag > 0.0:
		var s_new := _pending_drag
		_pending_drag = 0.0
		_client.send(_set_param_cmd(MID, "seeker_search_coverage_deg", s_new))
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
	# 1) ⭐⭐ THE FLOOR REGION — four widths that all fail, and the point is that they fail
	#    IDENTICALLY while the head sweeps four visibly different bands.
	for s in [S_FLOOR, 2.0, 4.0, S_LAST_FAIL]:
		_arms.append({"tag": "s%s" % _sname(s), "S": s})
	# 2) ⭐⭐⭐ THE LADDER over the LOCKING domain, in order — `t_lock` RISING monotonically, the
	#    three regions, and slice 48's own 25° sitting in the expensive one.
	for s in LADDER:
		_arms.append({"tag": "s%s" % _sname(s), "S": s})
	# 3) ⭐ DETERMINISM — same seed, same slider, same rung ⇒ the same missile to the last bit.
	_arms.append({"tag": "replay", "S": S_AUTH48})
	# 4) ⭐⭐ THE BUTTON, AT BOTH ENDS OF THE SLIDER. With the horizon off there is nothing to search
	#    for at ANY width, so these two must be BIT-IDENTICAL to each other.
	_arms.append({"tag": "off_lo", "S": S_FLOOR, "rung": RUNG_OFF})
	_arms.append({"tag": "off_hi", "S": S_TOP, "rung": RUNG_OFF})
	# 5) ⭐ THE PRESS ITSELF, MID-FLIGHT, WHILE STILL BLIND, with the slider at its FLOOR — a width
	#    that otherwise never finds the target at all.
	_arms.append({"tag": "midpress", "S": S_FLOOR, "press": RUNG_OFF})
	# 6) ⭐⭐⭐ THE MID-SEARCH DRAG — **the only arm in any of the four proofs that moves the slider
	#    while the physics is running**, and it is here because slice 49's rule says a live drag
	#    reaches none of them. Narrowing 25° → 6° mid-search is the direction this HUD's own cure
	#    line asks for, and before the seam re-armed its peaks it left the band drawing a 22° sweep
	#    over a head covering ±6 for the rest of the flight.
	_arms.append({"tag": "drag", "S": S_AUTH48, "drag": 6.0})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	# ⚠ `reset` RELOADS THE YAML, so the rung returns to the authored `snr` and the slider to its
	# authored 25.0 every arm — each arm must re-send its own. That is what makes these arms the
	# CLIENT's path (a slider drag and a button press) rather than a set of scenario variants.
	_client.send({"type": "reset"})
	if str(arm.get("rung", RUNG_ON)) != RUNG_ON:
		_client.send({"type": "set_fidelity", "key": "seeker_detect", "value": str(arm["rung"])})
	_client.send(_set_param_cmd(MID, "seeker_search_coverage_deg", float(arm["S"])))
	if arm.has("press"):
		_pending_press = str(arm["press"])
		_t_target = PRESS_AT * _dt
		_client.send({"type": "step", "n": PRESS_AT})
	elif arm.has("drag"):
		# ⚠ A MULTIPLE OF `emit_every` (16), and MID-SEARCH: the sweep opens at tick 4936 and the
		# authored 25° arm locks at 5959, so 5296 is inside the acquisition on both sides.
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
	var pressed: bool = arm.has("press")
	# ⚠⚠ NaN, NOT 0.0, WHEN THERE ARE NO POST-LOCK FRAMES (slice 33's finding): the floor arms have
	# none at all, so a `sum/max(n,1)` would print a perfect `hold = 100 %` on precisely the cells
	# that carry the lesson.
	var hold := NAN if _n_post == 0 else 100.0 * float(_n_held) / float(_n_post)
	var frac := (_flown_peak / _told_peak) if _told_peak > 0.0 else NAN
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate, "hold": hold,
		"tlock": _t_lock_key, "tlock_frame": _t_lock_frame, "auth": _auth_peak,
		"sat": _n_sat_pre, "sat_post": _n_sat_post, "cued": _n_cued,
		"searching": _n_searching, "cue": _cue_hand, "def": _def_first, "def_max": _def_max,
		"elapsed": _elapsed_max, "srchkey": _n_srchkey, "realkey": _n_realkey,
		"told": _told_peak, "flown": _flown_peak, "frac": frac, "head": _head_peak,
		"told_last": _told_last, "flown_last": _flown_last,
		"S": float(arm["S"]), "cov_seen": _cov_seen, "rho_seen": _rho_seen,
		"blind": blind, "win": _win_seen, "stop": _stop_seen, "rate": _rate_seen,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S52V_ARM   %-9s S=%6.2f deg rung=%-4s  ->  t_lock=%s  told=%6.2f flown=%6.2f (%s)  " +
		   "auth=%6.1f%%  hold=%6.2f%%  miss=%9.4f  search_frames=%d") %
		  [tag, m["S"], RUNG_ON if blind else RUNG_OFF, _lock_str(m["tlock"]),
		   m["told"], m["flown"], _frac_str(m["frac"]), 100.0 * m["auth"], m["hold"],
		   m["miss"], m["searching"]])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA") %
				[tag, STEPS, _min_los])
	# THE AUTHORED FOUR, ON EVERY ARM: nothing in this file touches them, and that is the point.
	# ⚠ THE SWEEP RATE IS ONE OF THEM HERE, where in slice 48 it was the slider — this wire authors
	# 60 °/s and the whole three-region ladder depends on it.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH
			and _rho_seen == RHO_AUTH):
		return (("arm %s: the window / stop / servo / SWEEP RATE must be the AUTHORED %.1f / %.1f / " +
				"%.1f / %.1f (got %.3f / %.3f / %.3f / %.3f). ⚠ The RATE is a FIXTURE on this wire: " +
				"at 240 °/s the whole coverage ladder is benign and the slider teaches nothing") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, RHO_AUTH,
				 _win_seen, _stop_seen, _rate_seen, _rho_seen])
	# ⚠ THE SLIDER'S OWN TRIPWIRE (slice 19's discipline): the coverage is READ BACK OFF THE WIRE, so
	# each arm proves the slider reached THE PHYSICS rather than merely being accepted by the server.
	if not arm.has("drag") and absf(_cov_seen - float(arm["S"])) > 1.0e-9:
		return (("arm %s: the wire must report the coverage the slider sent (%.4f vs %.4f) — a " +
				"set_param that is accepted and never consumed passes every other check here") %
				[tag, _cov_seen, float(arm["S"])])
	# ⚠⚠ SLICE 35's RATE LIMIT MUST NEVER BIND BEFORE THE LOCK. The servo is authored at 240 °/s
	# against a 60 °/s sweep exactly so a failure to reach the target is attributable to the WIDTH.
	if arm.has("drag"):
		# ⭐⭐ AND THE DRAG ARM IS EXEMPT BECAUSE OF WHAT IT MEASURES, NOT TO GET PAST A CHECK:
		# `search_sweep` is continuous in TIME and **discontinuous in `S`**, so moving the slider
		# steps the commanded offset — at a fixed phase a 25° triangle and a 6° one are simply in
		# different places — and the servo rate-limits through that step. It is the one thing on
		# this wire that a slider drag does and a sweep never can, it lasts a couple of frames, and
		# it is asserted as a BOUNDED TRANSIENT rather than skipped.
		if not (_n_sat_pre > 0 and _n_sat_pre <= 8):
			return (("arm %s: a live drag STEPS the commanded offset (the sweep is discontinuous in " +
					"S), so the servo must rate-limit through it BRIEFLY — got %d saturated frames " +
					"before the lock, expected 1…8. Zero would mean the drag never reached the " +
					"physics; many would mean the step is not being absorbed") % [tag, _n_sat_pre])
	elif not (_n_sat_pre == 0):
		return (("arm %s: slice 35's rate limit bound on %d frames BEFORE the lock — a sweep the " +
				"servo cannot execute is not a test of the sweep WIDTH. (It had %d frames after " +
				"the lock, which is the ENDGAME and is not this slice's mechanism)") %
				[tag, _n_sat_pre, _n_sat_post])
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47/48): both key families are ANCHOR-gated and must
	# ship on EVERY frame of this wire, freezing or zeroing rather than vanishing. A key that stops
	# emitting makes a client's `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test — and here
	# that zero would say "the head never moved", which is this slider's own floor verdict.
	if not (_n_srchkey > 100 and _n_realkey > 100):
		return (("arm %s: the search keys (%d) AND this slice's realized keys (%d) are ANCHOR-gated " +
				"and must ship on EVERY frame") % [tag, _n_srchkey, _n_realkey])
	# ⭐⭐⭐ THE INSTRUMENT'S OWN CLAIM, ON EVERY SINGLE ARM: the head never flies what it is told.
	# ⚠ GATED ON `_told_peak > 0`, NOT ON `_n_searching`, AND THAT IS A MEASUREMENT RATHER THAN A
	# LOOSENING: the horizon-OFF arms register exactly ONE searching frame — the tick the branch
	# opens, where `search_sweep(0) === 0.0` by construction (gate 1 tooth 1) — so both peaks are a
	# true 0.0 there and "strictly inside" has nothing to compare. An arm that swept a BAND is the
	# subject of this claim; an arm that swept a POINT is not.
	if _told_peak > 0.0 and not (_flown_peak < _told_peak and _flown_peak > 0.0):
		return (("arm %s: the FLOWN sweep (%.4f°) must be strictly inside the COMMANDED one " +
				"(%.4f°) and non-zero — a lag is a low-pass, and a head that reached its command " +
				"exactly would mean the instrument is reading the command twice") %
				[tag, _flown_peak, _told_peak])
	if blind:
		if not (_n_cued > 100):
			return (("arm %s: this wire must actually FLY BLIND (%d cued frames) — without a blind " +
					"phase there is nothing to search for and nothing here is measured") % [tag, _n_cued])
		# ⭐⭐ THE HANDOVER IS THE SAME ON EVERY ARM, AND THAT IS LOAD-BEARING: the search STARTS at
		# the handover, so it cannot move it. Every width therefore faces the IDENTICAL gap, and the
		# only thing the slider changes is how much of the sky the band covers.
		# ⚠ The PRESS arm is exempt — it hands over 1.7 s earlier, and the handover error is the
		# picture error TIMES the time spent blind (slice 47 §7.2).
		if pressed:
			pass
		elif absf(_cue_hand - CUE_HAND) > DEG_TOL:
			return (("arm %s: the latched handover error must be the wire's %.4f° (got %.4f°) — an " +
					"arm that faces a different gap is not comparable to the others") %
					[tag, CUE_HAND, _cue_hand])
		# ⭐⭐⭐ THE DEFICIT IS THE CUE ERROR MINUS THE WINDOW — slice 43's currency, asserted here so
		# the HUD's gauge and the wire's cannot become two opinions.
		if not pressed and absf(_def_first - (CUE_HAND - WIN_AUTH)) > DEG_TOL:
			return (("arm %s: the deficit on the first searching frame must be the handover error " +
					"minus the window (%.4f° vs %.4f° − %.1f°)") %
					[tag, _def_first, CUE_HAND, WIN_AUTH])
		# ⚠ THE HEAD SWEEPS ON **EVERY** ARM OF THIS WIRE — including the floor. That is the
		# difference from slice 48's slider, whose floor is a head that never moves at all: here the
		# failure being taught is REACH, not inaction, and a floor arm that did not sweep would be
		# teaching slice 48's lesson under this slice's label.
		if pressed:
			# ⭐⭐ AND THE PRESS ARM MUST NEVER HAVE SWEPT AT ALL — which is not an exemption but
			# THE CLAIM. The horizon is removed at 3.2 s, before the 4.936 s handover, so the
			# receiver never opens onto empty sky and there is nothing to look for. *You only
			# search because you were blind* — slice 48's sentence, re-earned on this wire's own
			# slider, where the width is irrelevant because no search happens at any value.
			if _n_searching != 0:
				return (("arm %s: the pressed arm must never SEARCH (%d frames) — the horizon is " +
						"removed before the handover, so the missile is never blind and the width " +
						"has nothing to do") % [tag, _n_searching])
		elif not (_n_searching > 10):
			return (("arm %s: the head must SWEEP on every arm of this wire (%d frames) — the rate " +
					"is AUTHORED at 60 °/s, so there is no slider position that stops it") %
					[tag, _n_searching])
	else:
		# ⚠ THE BUTTON'S ARMS ARE NEVER BLIND, BY CONSTRUCTION — asserted rather than assumed,
		# because it is the premise of the byte-identity claim in the verdict.
		if not (_n_cued == 0 and _cue_hand == 0.0):
			return (("arm %s: with the horizon off the seeker has its target from tick 1, so the head " +
					"is never cued (got %d cued frames, cue %.4f°)") % [tag, _n_cued, _cue_hand])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	# ⭐⭐⭐ 1. THE CLIFF — a QUARTER OF A DEGREE apart, and one of them never acquires at all.
	var lo: Dictionary = _res["s%s" % _sname(S_LAST_FAIL)]
	var hi: Dictionary = _res["s%s" % _sname(S_FIRST_LOCK)]
	print("S52V_CLIFF  %.2f deg -> %s, miss %.2f m   ||   %.2f deg -> %s, miss %.2f m" %
		  [lo["S"], _lock_str(lo["tlock"]), lo["miss"], hi["S"], _lock_str(hi["tlock"]), hi["miss"]])
	if not (float(lo["tlock"]) < 0.0 and float(hi["tlock"]) > 0.0):
		return _fail(("a QUARTER OF A DEGREE of sweep width must separate NEVER ACQUIRING from " +
					  "acquiring (%s vs %s) — and gate 0 re-flew both cells at dt/2 with the cliff " +
					  "not moving at all, which is where slices 42 and 51 died") %
					 [_lock_str(lo["tlock"]), _lock_str(hi["tlock"])])
	if not (float(lo["miss"]) > MISS_FLOOR):
		return _fail("the last failing width must miss by more than %.0f m (got %.2f)" %
					 [MISS_FLOOR, lo["miss"]])

	# ⭐⭐⭐ 2. THE FLOWN BAND IS WHAT SETS THE CLIFF, NOT THE ONE YOU AUTHORED. At 5.00° the gap to
	# cover was 2.80° and the AUTHORED band overshoots it by nearly two degrees — so a student
	# sizing this sweep from the authored number alone would predict the floor near 3°. What
	# actually just barely clears the gap is the 3.24° the head FLEW.
	print(("S52V_FLOWN  at the cliff: told %.2f deg, FLOWN %.2f deg (%.1f%%), gap at onset %.4f deg " +
		   "growing at ~6.8 deg/s") %
		  [hi["told"], hi["flown"], 100.0 * float(hi["frac"]), hi["def"]])
	if not (float(hi["flown"]) < 0.75 * float(hi["told"])):
		return _fail(("at the cliff the head must fly much LESS than it is told (%.3f of %.3f) — " +
					  "if the two agreed, the authored number would be the design number and this " +
					  "slice's instrument would have nothing to say") % [hi["flown"], hi["told"]])
	if not (float(lo["flown"]) < float(hi["flown"])):
		return _fail("…and the failing cell must fly a NARROWER band than the first locking one (%.3f vs %.3f)" %
					 [lo["flown"], hi["flown"]])

	# ⭐⭐⭐ 3. THE MISS IS FORBIDDEN AS THE GAUGE — AS A BIT-IDENTITY. Four widths across the floor
	# region, four visibly different bands, one trajectory.
	var base: Dictionary = _res["s%s" % _sname(S_FLOOR)]
	for s in [2.0, 4.0, S_LAST_FAIL]:
		var a: Dictionary = _res["s%s" % _sname(s)]
		var d: float = _max_pos_diff(base["pos"], a["pos"])
		print("S52V_NOISE  S %.2f vs %.2f: max|Δpos| = %.12f m over %d frames (flown %.3f vs %.3f deg)" %
			  [S_FLOOR, s, d, base["pos"].size(), base["flown"], a["flown"]])
		if not (d <= EXACT):
			return _fail(("across the floor region the trajectory must be BIT-IDENTICAL (max|Δpos| " +
						  "= %.12f m at S = %.2f) — nothing the head does reaches the guidance " +
						  "until something LOCKS, and that is what makes the miss useless here") % [d, s])
		if not (float(a["flown"]) > float(base["flown"]) + 0.1):
			return _fail(("…and the heads must differ VISIBLY (%.4f vs %.4f deg flown at S = %.2f " +
						  "vs %.2f) — if the bands were the same, the identity above is trivial") %
						 [a["flown"], base["flown"], s, S_FLOOR])
		if not (absf(float(a["miss"]) - float(base["miss"])) <= EXACT):
			return _fail("…and their misses must be the same NUMBER, not merely close (%.6f vs %.6f)" %
						 [a["miss"], base["miss"]])

	# ⭐⭐ 4. THE AXIS — `t_lock` RISES monotonically with the width, and the FLOWN FRACTION rises
	# with it too. ⚠ RISING: this knob's expensive end is UP, which is the whole difference from
	# slice 48's.
	print("S52V_AXIS       S deg   t_lock s    told    flown   flown/told     auth %     miss m")
	var prev_t := -1.0
	var prev_f := -1.0
	for s in LADDER:
		var a: Dictionary = _res["s%s" % _sname(s)]
		print("S52V_AXIS   %9.2f %10.4f %8.3f %8.3f %12.4f %10.2f %11.4f" %
			  [a["S"], a["tlock"], a["told"], a["flown"], a["frac"],
			   100.0 * float(a["auth"]), a["miss"]])
		if not (float(a["tlock"]) >= 0.0):
			return _fail("arm S = %.2f must acquire — every width above the cliff does" % s)
		if not (float(a["tlock"]) > prev_t):
			return _fail(("the time to find the target must RISE monotonically with the sweep width " +
						  "(%.4f s at %.2f°, after %.4f s) — a non-monotone gauge is not a lesson, " +
						  "and this project has disqualified five sliders for exactly that") %
						 [a["tlock"], s, prev_t])
		prev_t = float(a["tlock"])
		if not (float(a["frac"]) > prev_f):
			return _fail(("…and the fraction of the commanded sweep the head actually FLIES must " +
						  "rise with the width too (%.4f at %.2f°, after %.4f) — a sweep's period " +
						  "is 4S/ρ against a FIXED 0.05 s of lag, so the narrower it is the less " +
						  "of it survives") % [a["frac"], s, prev_f])
		prev_f = float(a["frac"])
		if not (float(a["hold"]) > HOLD_OK):
			return _fail("arm S = %.2f must hold its track once acquired (hold %.2f %%)" % [s, a["hold"]])
	# …and the two ENDS of that fraction are pinned, because "it rises" would be satisfied by a
	# fraction that never left 0.99.
	var f_lo: float = float(_res["s%s" % _sname(S_FLOOR)]["frac"])
	var f_hi: float = float(_res["s%s" % _sname(S_TOP)]["frac"])
	print("S52V_LAG    the head flies %.4f of a %.2f deg sweep and %.4f of a %.2f deg one" %
		  [f_lo, S_FLOOR, f_hi, S_TOP])
	if not (absf(f_lo - FRAC_FLOOR) < FRAC_TOL and absf(f_hi - FRAC_TOP) < FRAC_TOL):
		return _fail(("the flown fraction must be %.4f at %.2f° and %.4f at %.2f° (got %.4f / %.4f) " +
					  "— this is the number the whole instrument exists to report") %
					 [FRAC_FLOOR, S_FLOOR, FRAC_TOP, S_TOP, f_lo, f_hi])

	# ⭐⭐⭐ 5. THE TWO SIDES, AND SLICE 48's OWN NUMBER IS ON THE WRONG ONE. Immediately above the
	# cliff the missile arrives for a quarter of its airframe; at the width slice 48 shipped it is
	# pinned at the limit and misses by 32 m.
	var cheap: Dictionary = _res["s%s" % _sname(6.0)]
	var pinned: Dictionary = _res["s%s" % _sname(S_AUTH48)]
	print(("S52V_TWOSIDE %.2f deg: found in %.4f s, spent %.1f%% of a_max, ARRIVED at %.2f m   ||   " +
		   "%.2f deg (slice 48's): found in %.4f s, spent %.1f%%, MISSED by %.2f m") %
		  [cheap["S"], cheap["tlock"], 100.0 * float(cheap["auth"]), cheap["miss"],
		   pinned["S"], pinned["tlock"], 100.0 * float(pinned["auth"]), pinned["miss"]])
	if not (float(cheap["auth"]) < AUTH_CHEAP and float(cheap["miss"]) < HIT_MAX):
		return _fail(("the width just above the cliff must arrive CHEAPLY (%.4f of a_max, %.2f m) — " +
					  "if the best cell were expensive too, there would be no optimum to find") %
					 [cheap["auth"], cheap["miss"]])
	if not (float(pinned["auth"]) >= AUTH_PINNED and float(pinned["miss"]) > MISS_PINNED):
		return _fail(("⭐⭐⭐ slice 48's OWN authored 25° must be PINNED at the airframe's limit " +
					  "(%.4f of a_max) AND STILL MISS (%.2f m) — that is the whole slice: the " +
					  "number the previous slice shipped is four times wider than this engagement " +
					  "needs, and nothing on its HUD could have said so") %
					 [pinned["auth"], pinned["miss"]])
	if not (float(pinned["tlock"]) > 3.0 * float(cheap["tlock"])):
		return _fail(("…and the wide arm must take much LONGER to find the same target (%.4f s vs " +
					  "%.4f s) — the price of the extra width is travel, spent before the head " +
					  "ever looks at the right half of the sky") % [pinned["tlock"], cheap["tlock"]])
	# ⚠ THE 2S LAW, READ OVER A **WIDE** BRACKET AND NEVER AS A LOCAL SLOPE. `t_lock` is quantized
	# at `dt`, so the 5 → 6 chord reads BELOW the kernel's `2/ρ` by a third of a tick and would
	# report the wrong sign. Over 5 → 40 the flown cost is ~0.0392 s per degree against the
	# fixed-target law's 2/60 = 0.0333: the excess is the RACE — the target moves while you are
	# looking the wrong way.
	var top: Dictionary = _res["s%s" % _sname(S_TOP)]
	var chord: float = (float(top["tlock"]) - float(hi["tlock"])) / (S_TOP - S_FIRST_LOCK)
	print("S52V_COST   d(t_lock)/dS over %.2f -> %.2f deg = %.6f s/deg, against the 2/rho law's %.6f" %
		  [S_FIRST_LOCK, S_TOP, chord, 2.0 / RHO_AUTH])
	if not (chord > 2.0 / RHO_AUTH):
		return _fail(("the flown cost per degree (%.6f s) must EXCEED the fixed-target 2/rho law " +
					  "(%.6f s) — the excess is the deficit growing while the sweep travels, and " +
					  "if it vanished the target would not be moving") % [chord, 2.0 / RHO_AUTH])

	# ⚠ 6. THE TRUNNION IS NOT IN THE MEASUREMENT — the slider's ceiling is measured, not rounded.
	print("S52V_STOP   at the ceiling (%.1f deg) the head peaks at %.3f deg against a %.1f deg stop" %
		  [S_TOP, top["head"], STOP_AUTH])
	if not (float(top["head"]) < STOP_AUTH - 1.0):
		return _fail(("the slider's ceiling must keep the mechanical stop OUT of the acquisition " +
					  "(head peaked at %.3f° against a %.1f° trunnion) — a showcase whose top cell " +
					  "is clamped teaches the trunnion beside the coverage") % [top["head"], STOP_AUTH])

	# ⭐ 7. DETERMINISM — the master check (convention 2).
	var d_rep: float = _max_pos_diff(_res["s%s" % _sname(S_AUTH48)]["pos"], _res["replay"]["pos"])
	print("S52V_REPLAY S %.2f max|Δpos| = %.12f m over %d frames" %
		  [S_AUTH48, d_rep, _res["replay"]["pos"].size()])
	if not (d_rep <= EXACT):
		return _fail("replay differs by %.12f m — determinism is the master check" % d_rep)

	# ⭐⭐ 8. THE BUTTON — AND IT IS A BYTE-IDENTITY CLAIM. With the horizon off the seeker has its
	# target from tick 1, so there is nothing to search for AT ANY WIDTH.
	var d_off: float = _max_pos_diff(_res["off_lo"]["pos"], _res["off_hi"]["pos"])
	print("S52V_BUTTON horizon OFF: S %.2f vs %.2f -> max|Δpos| = %.12f m over %d frames (miss %.3f / %.3f)" %
		  [S_FLOOR, S_TOP, d_off, _res["off_lo"]["pos"].size(),
		   _res["off_lo"]["miss"], _res["off_hi"]["miss"]])
	if not (d_off <= EXACT):
		return _fail(("with the horizon off the slider must do NOTHING (max|Δpos| = %.12f m) — a " +
					  "wire where the sweep leaks into a seeing missile has a second, unnamed path " +
					  "into the guidance") % d_off)
	if not (float(_res["off_lo"]["miss"]) < HIT_MAX):
		return _fail("with the horizon off the missile must simply hit (%.3f m)" % _res["off_lo"]["miss"])

	# ⭐ 9. THE MID-RUN PRESS — the horizon removed at 3.2 s, while the missile is still blind, with
	# the slider at a width that otherwise never finds anything. *You only search because you were
	# blind.*
	var mp: Dictionary = _res["midpress"]
	print(("S52V_PRESS  press at %.3f s with the sweep at %.2f deg -> lock at %.3f s, miss %.3f m " +
		   "(the same width misses by %.1f m with the horizon left on)") %
		  [PRESS_AT * _dt, S_FLOOR, mp["tlock_frame"], mp["miss"], _res["s%s" % _sname(S_FLOOR)]["miss"]])
	if not (mp["cued"] > 100 and float(mp["tlock_frame"]) >= PRESS_AT * _dt - 0.05
			and float(mp["tlock_frame"]) <= PRESS_AT * _dt + 0.05):
		return _fail(("the mid-run press must acquire within a frame or two of itself (press %.3f s, " +
					  "lock %.3f s, %d cued frames before it)") %
					 [PRESS_AT * _dt, mp["tlock_frame"], mp["cued"]])
	if not (float(mp["miss"]) < MISS_PRESS_MAX):
		return _fail(("…and removing the horizon early must SAVE the shot (%.3f m) at a width that " +
					  "otherwise never finds the target at all") % mp["miss"])
	if not (mp["searching"] == 0):
		return _fail(("…and it must never have searched (%d frames) — the save is the BUTTON's and " +
					  "not the width's") % mp["searching"])

	# ⭐⭐⭐ 10. THE MID-SEARCH DRAG — the state slice 49's rule says no proof of this family visits.
	# Narrow the sweep while the head is hunting and BOTH peaks must re-arm: the band's width is the
	# COMMANDED peak, and a stale one draws a 22° sweep over a head now covering ±6 for the rest of
	# the flight, with the headline naming a width the slider does not show.
	var dg: Dictionary = _res["drag"]
	print(("S52V_DRAG   dragged %.1f -> %.1f deg at %.3f s; the wire then reports told %.3f / flown " +
		   "%.3f deg (an un-dragged 6.00 deg arm reads %.3f / %.3f)") %
		  [S_AUTH48, 6.0, DRAG_AT * _dt, dg["told_last"], dg["flown_last"],
		   _res["s%s" % _sname(6.0)]["told"], _res["s%s" % _sname(6.0)]["flown"]])
	if not (float(dg["told_last"]) < 0.5 * S_AUTH48):
		return _fail(("⭐⭐⭐ after narrowing the sweep the COMMANDED peak must re-arm (%.3f° against " +
					  "the %.1f° it was dragged away from) — a peak that only ever grows is stale " +
					  "for the rest of the flight, and the HUD draws its band from THIS key") %
					 [dg["told_last"], S_AUTH48])
	if not (absf(float(dg["told_last"]) - 6.0) < 0.2):
		return _fail("…and it must settle on the width now authored (%.3f° vs 6.0°)" % dg["told_last"])
	if not (float(dg["flown_last"]) < float(dg["told_last"])):
		return _fail(("…and the REALIZED peak must re-arm with it (%.3f° against a %.3f° command) — " +
					  "the head is what a drag cannot move instantly, so a peak restarted at the " +
					  "moment it re-enters the new band samples it AT THE RIM and reports a " +
					  "flattering ~99 %% where the un-dragged arm measures 69 %%") %
					 [dg["flown_last"], dg["told_last"]])
	if not (absf(float(dg["flown_last"]) / maxf(float(dg["told_last"]), 1e-9) - 0.6929) < 0.08):
		return _fail(("…and it must land on the UN-DRAGGED 6° arm's own fraction (%.4f vs 0.6929) — " +
					  "that is what separates 'measures the new sweep' from 'merely forgot the old " +
					  "one'") % [float(dg["flown_last"]) / maxf(float(dg["told_last"]), 1e-9)])

	print("S52V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice52_coverage":
		return "wrong scenario '%s' — run scenarios/slice52_coverage.yaml" % str(f.get("name", ""))
	# ⭐⭐⭐ THE 14th MARKER, AND IT IS THE ONE THAT SEPARATES THIS WIRE FROM SLICE 48's. This file
	# authors slice 48's search anchor, so `search_view` is raised HERE TOO and can no longer tell
	# the two apart — without this marker the client draws slice 48's block, every number on it
	# TRUE, and never says that the WIDTH is what is being dialled.
	if not bool(f.get("search_realized_view", false)):
		return ("a slice-52 handshake must ship search_realized_view=true — it is raised on the " +
				"`seeker_search_realized` comp key, which is an INSTRUMENT (the head's own flown " +
				"sweep) and not a view flag")
	for k in ["search_view", "midcourse_view", "seeker_detect_view", "gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-52 wire IS a slice-48 wire with a different slider, so it must still " +
					"raise %s — the superset relation is what makes the new marker a BRANCH " +
					"SELECTOR rather than a hole plug") % k
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view",
			  "seeker_aspect_view"]:
		if bool(f.get(k, false)):
			return ("a slice-52 wire must NOT raise %s — it would either put a second mechanism " +
					"beside this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "seeker_search_coverage_deg":
		return ("exactly ONE knob, the MISSILE's `seeker_search_coverage_deg` (convention 9). " +
				"`seeker_search_rate_dps` is slice 48's OWN slider and the two COMPOSE — the floor " +
				"is 5.00° at 60 °/s and 7.50° at 240, so dragging both would move the floor and the " +
				"width at once; `midcourse_err_gain` is what SETS the right width and cannot also " +
				"be an input to the question; `rcs_m2` is slice 46's; `gimbal_fov_deg` is TWO-SIDED " +
				"since slice 46 and would move the DEFICIT as well")
	if not (float(kn[0].get("min", -1.0)) == S_FLOOR and float(kn[0].get("max", 0.0)) == S_TOP):
		return (("the slider must span %.1f–%.1f°. ⚠⚠ THE FLOOR IS NOT ZERO, and that is the " +
				 "difference from slice 48's slider: a coverage of 0 is not a head that does not " +
				 "sweep, it is a search with nowhere to look, and the loader refuses it. %.1f° is a " +
				 "head that VISIBLY sweeps and still never gets there. The ceiling is the last cell " +
				 "the 45° trunnion stays out of — the head peaks at 42.49° there") %
				[S_FLOOR, S_TOP, S_FLOOR])
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR — the cost is (t_lock rises at ~0.04 s per degree), and " +
				"the floor region (1 → 4.75°) is a tenth of the travel and must READ as a region")
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _n_post = 0; _n_held = 0; _t_lock_frame = -1.0
	_auth_peak = 0.0; _n_sat_pre = 0; _n_sat_post = 0; _n_cued = 0; _n_searching = 0
	_cue_hand = 0.0; _def_first = -1.0; _def_max = 0.0; _t_lock_key = -1.0
	_elapsed_max = 0.0; _n_srchkey = 0; _n_realkey = 0
	_told_peak = 0.0; _flown_peak = 0.0; _head_peak = 0.0
	_told_last = 0.0; _flown_last = 0.0
	_win_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0; _rho_seen = 0.0; _cov_seen = 0.0
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
	var t := float(f.get("t", 0.0))
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
	_win_seen = float(tel.get(MID + ".gimbal_fov_deg", _win_seen))
	_stop_seen = float(tel.get(MID + ".gimbal_stop_deg", _stop_seen))
	_rate_seen = float(tel.get(MID + ".gimbal_rate_dps", _rate_seen))
	_rho_seen = float(tel.get(MID + ".search_rate_dps", _rho_seen))
	_cov_seen = float(tel.get(MID + ".search_coverage_deg", _cov_seen))
	if tel.has(MID + ".head_searching"):
		_n_srchkey += 1
		_t_lock_key = float(tel.get(MID + ".search_t_lock_s", -1.0))
		_elapsed_max = maxf(_elapsed_max, float(tel.get(MID + ".search_elapsed_s", 0.0)))
		if float(tel[MID + ".head_searching"]) >= 0.5:
			_n_searching += 1
			var d := float(tel.get(MID + ".search_deficit_deg", 0.0))
			_def_max = maxf(_def_max, d)
			if _def_first < 0.0:
				_def_first = d
	# ⭐⭐⭐ THE SLICE'S OWN KEYS, and they are read from the CORE'S LATCHES rather than peak-held
	# here: a client sees one frame in `emit_every` = 16 ticks and would sample the excursion's
	# shoulders, which is exactly what slice 47 paid to learn.
	# ⚠⚠ AND THE WIDTH IS `search_offset_peak_deg`, NEVER `search_coverage_deg` — gate 2 tooth I
	# measured that the coverage echo reports the bag finite-clamped (1e9 on a NaN) beside a sweep
	# of exactly zero, so a band sized from it would be a billion degrees wide over a still head.
	if tel.has(MID + ".search_realized_peak_deg"):
		_n_realkey += 1
		# ⚠ BEFORE THE LOCK ONLY, so the post-intercept re-search cannot widen either peak. That
		# episode is this slice's fourth encounter with the trap.
		_told_last = float(tel.get(MID + ".search_offset_peak_deg", 0.0))
		_flown_last = float(tel[MID + ".search_realized_peak_deg"])
		if _t_lock_frame < 0.0:
			_told_peak = maxf(_told_peak, float(tel.get(MID + ".search_offset_peak_deg", 0.0)))
			_flown_peak = maxf(_flown_peak, float(tel[MID + ".search_realized_peak_deg"]))
			if float(tel.get(MID + ".head_searching", 0.0)) >= 0.5:
				_head_peak = maxf(_head_peak, absf(float(tel.get(MID + ".head_angle_deg", 0.0))))
	if float(tel.get(MID + ".head_cued", 0.0)) >= 0.5:
		_n_cued += 1
	if tel.has(MID + ".head_cue_err_handover_deg"):
		_cue_hand = float(tel[MID + ".head_cue_err_handover_deg"])
	if los > 200.0:
		_n_gate += 1
		var avail := float(tel.get(MID + ".gimbal_valid", 1.0)) >= 0.5
		if avail and _t_lock_frame < 0.0:
			_t_lock_frame = t
		if _t_lock_frame >= 0.0:
			_n_post += 1
			if avail:
				_n_held += 1
			_auth_peak = maxf(_auth_peak, float(tel.get(MID + ".a_cmd_frac", 0.0)))
		# ⚠⚠ SPLIT AT THE LOCK (slice 48's gate-3 correction, inherited): every saturated tick on
		# this family's arms falls inside the ENDGAME, where the LOS swings past the head faster
		# than the servo can follow and the resumed search chases it. The isolation claim that
		# matters is BEFORE the lock, where a saturating servo really would make "the band did not
		# reach the target" unattributable to the WIDTH.
		if float(tel.get(MID + ".head_rate_sat", 0.0)) >= 0.5:
			if _t_lock_frame < 0.0:
				_n_sat_pre += 1
			else:
				_n_sat_post += 1

func _sname(s: float) -> String:
	# ⚠ A STABLE TAG FOR A FRACTIONAL SLIDER POSITION — `%d` would collapse 4.75 onto 4 and the arm
	# dictionary would silently overwrite one arm with another (slice 48's tags were integers).
	return ("%.2f" % s).replace(".", "p")

func _frac_str(f: float) -> String:
	return "n/a" if is_nan(f) else "%.1f%%" % (100.0 * f)

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
	push_error("S52V FAIL: " + msg)
	print("S52V FAIL: ", msg)
	quit(code)
	return true
