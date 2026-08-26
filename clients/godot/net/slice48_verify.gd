extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-48 gate-3 verifier — THE SEEKER SEARCH PATTERN.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice48_search.yaml
#   godot --headless --path clients/godot --script res://net/slice48_verify.gd     (exit 0 = pass)
#
# THE LESSON. Slice 47 leaves a missile whose receiver opens onto empty sky — the head pointed where
# the launch picture said the target would be, the target further out than the window is wide, and
# the head doing nothing at all for the rest of the flight. Give it a SEARCH and it can look around.
# What it spends doing so is not head travel: it is the ENGAGEMENT'S OWN CLOCK.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE: **FINDING THE TARGET IS NOT THE SAME AS MAKING THE
# SHOT.** Below 36 °/s the sweep never covers the gap in time and the missile never acquires at all.
# Between 36 and 60 it acquires EVERY TIME — and is pinned at up to 100 % of its manoeuvre limit and
# still misses, by 677 m falling to 32 m. The edge is between 60 and 65 °/s, where the lock arrives
# **0.086 s** sooner and the engagement inverts: 100 % of `a_max` and a 32 m miss becomes 33 % and
# 0.48 m. Nothing about the SEARCH looks different across that edge.
#
# ⚠⚠ AND THE MISS IS ASSERTED **FORBIDDEN AS THE GAUGE** IN ITS STRONGEST FORM YET — as a
# BIT-IDENTITY rather than as a non-monotonicity. Across the whole floor region (ρ = 0 … 35) the head
# sweeps for 6.26 s, 6265 ticks of a servo working hard, and the missile flies the IDENTICAL
# trajectory to the last bit: `max|Δpos| == 0`. Nothing the head does reaches the guidance until
# something is LOCKED. A verifier reading miss over that region would report a slider that does
# nothing — which is how slices 44 and 45 died.
#
# ⚠⚠ THE AUTHORITY IS **NOT MONOTONE IN ρ AND THIS FILE DOES NOT PRETEND IT IS**: it climbs 71 →
# 100 % as the lock gets late enough to demand everything, then falls to 23 % once the lock is early
# enough that little is demanded. That is the physics. ⇒ the monotone axis asserted here is
# `t_search` (2.040 → 0.267 s, no reversals) and the authority is checked as a THREE-REGION VERDICT.
#
# ⚠⚠ THE AUTHORITY IS READ WITH **BOTH** GATES — r > 200 m AND the FIRST DESCENDING BAND — and that
# pairing is a gate-3 correction rather than inherited hygiene: the gate-0 and gate-2 probes gated on
# range alone, and the POST-CPA RE-CROSSING climbs back through 200 m from the far side. ρ = 36 reads
# 78.2 % that way and 71.2 % correctly. [[ewsim-missile-verifier-sampling]]'s first rule, in a fourth
# slice.
#
# ⭐⭐ THE BUTTON IS THE SLICE'S OWN CONTROL, AND IT IS A BYTE-IDENTITY CLAIM. Press `seeker_detect`
# to `none` and the horizon goes away; the seeker has its target from tick 1 and there is nothing to
# search for. ⇒ WITH THE BUTTON PRESSED THE SLIDER MUST DO **NOTHING AT ALL** — two arms at opposite
# ends of its domain, bit-identical. *You only search because you were blind.*
#
# ⚠ THE BROKEN ARMS NEVER LOCK, so `search_t_lock_s` is **−1.0** on exactly the cells that carry the
# lesson (0.0 is a real value — a search that found it on its first tick). Every per-arm check below
# is written to be defined without a lock.
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
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 11200 = 16 * 700.
# ⚠ AND IT IS SIZED OFF THE **LATEST** CPA IN THE SWEEP, NOT THE SHOWCASE ARM's: the arms that lock
# late fly on to 9.53 s while the null turns at 8.51 s, so sizing on either end alone would leave
# half the ladder still closing at the end and `_turned` would fail them.
const STEPS := 11200
const PRESS_AT := 3200            # a multiple of 16, and BEFORE the 4.936 s handover, so the press
                                  # is what removes the blind phase

const RUNG_ON := "snr"
const RUNG_OFF := "none"

# THE SLIDER — the commanded sweep rate, °/s. The DEFAULT is the domain FLOOR and it is a true NULL:
# a head that does not sweep at all, which is exactly what ships without this slice.
const RHO_NULL := 0.0
const RHO_FLOOR_LO := 35.0        # the last rate that NEVER acquires
const RHO_FLOOR_HI := 36.0        # …and the first that does, one °/s away
const RHO_EDGE_LO := 60.0         # ⭐⭐ pinned at 100 % of a_max and STILL missing (32.09 m)
const RHO_EDGE_HI := 65.0         # ⭐⭐ 0.086 s sooner: 32.7 % of a_max and 0.48 m
const RHO_TOP := 240.0            # the ceiling — the servo's own maximum slew rate
const LADDER := [36.0, 40.0, 45.0, 50.0, 60.0, 65.0, 120.0, 240.0]   # the LOCKING domain, in order

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const WIN_AUTH := 10.0            # the detector window
const STOP_AUTH := 45.0           # ⚠ 45, NOT slice 47's 30 — a search needs somewhere to look, and a
                                  # 30° trunnion is a search that cannot leave its cue (gate-0 §4.4)
const RATE_AUTH := 240.0          # slice 46's measured isolation, inherited
const COV_AUTH := 25.0            # the sweep's half-amplitude, AUTHORED (§0.7's reserve axis)
const CROSS_SPEED := 200.0

# ⭐ THE HANDOVER, IDENTICAL ON EVERY ARM — the search cannot move it, because it starts there.
const CUE_HAND := 11.3371         # the latched cue error at the instant the receiver opened
const DEFICIT := 1.3423           # …minus the window: the gap the sweep has to cover
const DEG_TOL := 0.15             # frame sampling + the servo's own lag

const T_HAND := 4.936             # s — when the receiver opens, on every arm
const HIT_MAX := 5.0              # a HIT, frame-sampled — a sanity bound, NEVER the lesson
const MISS_FLOOR := 1000.0        # the floor region's miss — a VERDICT, not metres
const MISS_PINNED := 30.0         # the pinned region must still MISS by more than this
const MISS_PRESS_MAX := 30.0      # ⚠ the PRESS arm's own bound, and it is a VERDICT rather than
                                  # metres: the same slider position misses by 1039.88 m with the
                                  # horizon left on. Frame-sampled it reads 5.05 m (a HIT samples
                                  # COARSELY — [[ewsim-missile-verifier-sampling]]), so a 5 m bound
                                  # would be measuring the emit grid rather than the engagement.
const AUTH_PINNED := 0.99         # …while spending essentially everything
const AUTH_CHEAP := 0.50          # …and the cheap region must spend less than this
const HOLD_OK := 80.0             # % of post-lock frames with the target available
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
var _n_gate := 0
var _n_post := 0
var _n_held := 0
var _t_lock_frame := -1.0         # the frame-sampled lock instant (cross-check only)
var _auth_peak := 0.0             # ⭐ post-lock, gated at r > 200 m AND on the closing band
var _n_sat_pre := 0               # ⭐ slice 35's rate limit BEFORE the lock — the isolation, 0
var _n_sat_post := 0              # …and after it, which is the ENDGAME and is not this slice's
var _n_cued := 0                  # frames the head was flying the BELIEF (the blind phase)
var _n_searching := 0             # ⭐ frames the head was SWEEPING
var _cue_hand := 0.0              # the LATCHED handover error (slice 47's key, inherited)
var _def_max := 0.0               # the deficit's peak while searching
var _def_first := -1.0            # …and its value on the FIRST searching frame
var _t_lock_key := -1.0           # ⭐⭐ the LATCHED search-to-lock time — the slice, in one number
var _elapsed_max := 0.0           # how long the head swept for
var _n_srchkey := 0               # frames carrying the search keys — anchor-gated, never-stale
var _win_seen := 0.0
var _stop_seen := 0.0
var _rate_seen := 0.0
var _cov_seen := 0.0
var _rho_seen := 0.0
var _pos_trace: Array = []

func _initialize() -> void:
	print("S48V_INIT godot=", Engine.get_version_info().string)
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
	# ⭐⭐ THE MID-RUN ARM'S SECOND LEG. The server DRAINS EVERY QUEUED COMMAND BEFORE IT STEPS AT ALL,
	# so [step K, set_fidelity, step N-K] sent back-to-back applies the toggle at tick 0 and silently
	# measures a from-launch arm instead (slice 37's finding).
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
	# 1) ⭐⭐ THE FLOOR REGION — three rates that all fail, and the point is that they fail IDENTICALLY
	#    while the head does completely different things. `r0` is the authored default and a true
	#    null (the head never sweeps at all).
	_arms.append({"tag": "r0", "rho": RHO_NULL})
	_arms.append({"tag": "r20", "rho": 20.0})
	_arms.append({"tag": "r35", "rho": RHO_FLOOR_LO})
	# 2) ⭐⭐⭐ THE LADDER over the LOCKING domain, in order — the axis (`t_search` falling
	#    monotonically), the three regions, and the edge between 60 and 65.
	for rho in LADDER:
		_arms.append({"tag": "r%d" % int(round(rho)), "rho": rho})
	# 3) ⭐ DETERMINISM — same seed, same slider, same rung ⇒ the same missile to the last bit.
	_arms.append({"tag": "replay", "rho": RHO_EDGE_HI})
	# 4) ⭐⭐ THE BUTTON, AT BOTH ENDS OF THE SLIDER. With the horizon off there is nothing to search
	#    for, so these two must be BIT-IDENTICAL to each other.
	_arms.append({"tag": "off_lo", "rho": RHO_NULL, "rung": RUNG_OFF})
	_arms.append({"tag": "off_hi", "rho": RHO_TOP, "rung": RUNG_OFF})
	# 5) ⭐ THE PRESS ITSELF, MID-FLIGHT, WHILE STILL BLIND — a `set_fidelity` reaching this rung with
	#    the midcourse arm still flying and the tracker still uninitialised. It must acquire at once:
	#    the belief-cued head has been pointing within a degree and a half of the window the whole
	#    time, and only the RANGE half was refusing it.
	_arms.append({"tag": "midpress", "rho": RHO_NULL, "press": RUNG_OFF})

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
	# ⚠ SENT ON EVERY ARM INCLUDING THE DEFAULT ONE, so the `r0` arm proves the SLIDER's own path to
	# its authored value rather than merely inheriting it from the YAML.
	_client.send(_set_param_cmd(MID, "seeker_search_rate_dps", float(arm["rho"])))
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
	# ⚠⚠ NaN, NOT 0.0, WHEN THERE ARE NO POST-LOCK FRAMES (slice 33's finding): the floor arms have
	# none at all, so a `sum/max(n,1)` would print a beautifully perfect `hold = 100 %` on precisely
	# the cells that carry the lesson.
	var hold := NAN if _n_post == 0 else 100.0 * float(_n_held) / float(_n_post)
	var m := {
		"miss": _min_los, "turned": _turned, "gate": _n_gate, "hold": hold,
		"tlock": _t_lock_key, "tlock_frame": _t_lock_frame, "auth": _auth_peak,
		"sat": _n_sat_pre, "sat_post": _n_sat_post, "cued": _n_cued,
		"searching": _n_searching, "cue": _cue_hand,
		"def": _def_first, "def_max": _def_max, "elapsed": _elapsed_max,
		"srchkey": _n_srchkey, "rho": float(arm["rho"]), "rho_seen": _rho_seen,
		"blind": blind, "win": _win_seen, "stop": _stop_seen, "rate": _rate_seen, "cov": _cov_seen,
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S48V_ARM   %-9s rho=%6.1f deg/s rung=%-4s  ->  t_search=%s  auth_peak=%6.1f%%  " +
		   "hold=%6.2f%%  miss=%9.4f  search_frames=%d  blind_frames=%d  sat=%d") %
		  [tag, m["rho"], RUNG_ON if blind else RUNG_OFF, _lock_str(m["tlock"]),
		   100.0 * m["auth"], m["hold"], m["miss"], m["searching"], m["cued"], m["sat"]])
	if not (_n_gate > 100):
		return "arm %s: the r > 200 m window must contain frames to measure (got %d)" % [tag, _n_gate]
	if not _turned:
		return (("arm %s: the engagement must reach CPA inside %d steps — this arm was still closing " +
				"at the end, so its miss (%.3f m) is a last closing range and not a CPA. ⚠ The " +
				"LATE-LOCKING arms fly on to 9.53 s and STEPS is sized off THEM") %
				[tag, STEPS, _min_los])
	# THE AUTHORED FOUR, ON EVERY ARM: nothing in this file touches them, and that is the point.
	if not (_win_seen == WIN_AUTH and _stop_seen == STOP_AUTH and _rate_seen == RATE_AUTH
			and _cov_seen == COV_AUTH):
		return (("arm %s: the window / stop / servo / coverage must be the AUTHORED %.1f / %.1f / " +
				"%.1f / %.1f (got %.3f / %.3f / %.3f / %.3f). ⚠ The STOP is 45 here and NOT slice " +
				"47's 30: a search needs somewhere to look, and a 30° trunnion silently eats the " +
				"sweep on a third of every search tick") %
				[tag, WIN_AUTH, STOP_AUTH, RATE_AUTH, COV_AUTH,
				 _win_seen, _stop_seen, _rate_seen, _cov_seen])
	# ⚠ THE SLIDER'S OWN TRIPWIRE (slice 19's discipline): the rate is READ BACK OFF THE WIRE, so each
	# arm proves the slider reached THE PHYSICS rather than merely being accepted by the server. A
	# `set_param` that is swallowed passes a sent-vs-echoed check and fails this one.
	if absf(_rho_seen - float(arm["rho"])) > 1.0e-9:
		return (("arm %s: the wire must report the sweep rate the slider sent (%.3f vs %.3f) — a " +
				"set_param that is accepted and never consumed passes every other check here") %
				[tag, _rho_seen, float(arm["rho"])])
	# ⚠⚠ SLICE 35's RATE LIMIT MUST NEVER BIND, ON ANY ARM. The servo is authored at 240 °/s exactly
	# so that a failure to cover the gap in time can be attributed to the SWEEP RATE and not to a
	# servo that could not execute it — and on this wire that matters more than anywhere before,
	# because a search IS pointing and nothing else.
	if not (_n_sat_pre == 0):
		return (("arm %s: slice 35's rate limit bound on %d frames BEFORE the lock — a sweep the servo " +
				"cannot execute is not a test of the sweep RATE, which is the whole slider. (Frames " +
				"AFTER the lock are the ENDGAME breach, where the LOS swings past the head faster " +
				"than 240 °/s and the resumed search chases it; this arm had %d of those, and they " +
				"are after the engagement is decided)") % [tag, _n_sat_pre, _n_sat_post])
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47): the search keys are ANCHOR-gated, so they ship on
	# EVERY frame of this wire — including before the search starts and after it ends, when the
	# values freeze or zero rather than vanishing. A key that stops emitting makes the HUD's
	# `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test (`docs/CONVENTIONS.md` §14).
	if not (_n_srchkey > 100):
		return (("arm %s: the search keys are ANCHOR-gated and must ship on EVERY frame (got %d) — " +
				"a key that stops emitting reads as a defaulted zero downstream") % [tag, _n_srchkey])
	if blind:
		if not (_n_cued > 100):
			return (("arm %s: this wire must actually FLY BLIND (%d cued frames) — without a blind " +
					"phase there is nothing to search for and nothing here is measured") % [tag, _n_cued])
		# ⭐⭐ THE HANDOVER IS THE SAME ON EVERY ARM, AND THAT IS LOAD-BEARING RATHER THAN INCIDENTAL:
		# the search STARTS at the handover, so it cannot move it. Every arm therefore faces the
		# IDENTICAL gap, and the only thing the slider changes is how fast that gap is swept.
		# ⚠⚠ THE PRESS ARM IS EXEMPT, AND THE EXEMPTION IS A FINDING RATHER THAN A LOOPHOLE — this
		# check FAILED it on the file's first run, at 5.1084° against the wire's 11.3371°. ⭐⭐ THE
		# HANDOVER ERROR IS THE PICTURE ERROR TIMES THE TIME SPENT BLIND (slice 47 §7.2): the belief
		# and the truth start together and separate at a rate the picture error sets, so opening the
		# receiver at 3.2 s instead of 4.936 s hands over at LESS THAN HALF the angle on an identical
		# slider value. The press arm's own version of the claim is asserted in the verdict instead.
		if pressed:
			pass
		elif absf(_cue_hand - CUE_HAND) > DEG_TOL:
			return (("arm %s: the latched handover error must be the wire's %.4f° (got %.4f°) — the " +
					"search begins where the cue ends, so it cannot move it, and an arm that faces " +
					"a different gap is not comparable to the others") % [tag, CUE_HAND, _cue_hand])
		# ⭐⭐⭐ THE DEFICIT IS THE CUE ERROR MINUS THE WINDOW, and asserting the identity here is what
		# keeps the two from becoming two opinions. It is slice 43's currency: the cost of acquiring
		# is `|err| − fov`, NOT the pointing error.
		if not pressed and float(arm["rho"]) > 0.0 and absf(_def_first - (CUE_HAND - WIN_AUTH)) > DEG_TOL:
			return (("arm %s: the deficit on the first searching frame must be the handover error " +
					"minus the window (%.4f° vs %.4f° − %.1f°) — if those part company the HUD's " +
					"gauge and the wire's are two different quantities") %
					[tag, _def_first, CUE_HAND, WIN_AUTH])
		# THE SEARCH MUST ACTUALLY RUN — except at ρ = 0, where it must NOT.
		if float(arm["rho"]) > 0.0 and not (_n_searching > 10):
			return (("arm %s: the head must actually SWEEP (%d searching frames) — a pattern the seam " +
					"never executes is the failure this probe family has been bitten by four times") %
					[tag, _n_searching])
		if float(arm["rho"]) == 0.0 and _n_searching != 0:
			return (("arm %s: at ρ = 0 the head must NOT search (%d frames) — the branch is gated on " +
					"ρ > 0 as well as on the anchor, and the slider's floor must be the SHIPPED wire") %
					[tag, _n_searching])
	else:
		# ⚠ THE BUTTON'S ARMS ARE NEVER BLIND, BY CONSTRUCTION — asserted rather than assumed, because
		# it is the premise of the byte-identity claim in the verdict.
		if not (_n_cued == 0 and _cue_hand == 0.0):
			return (("arm %s: with the horizon off the seeker has its target from tick 1, so the head " +
					"is never cued (got %d cued frames, cue %.4f°)") % [tag, _n_cued, _cue_hand])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	# ⭐⭐⭐ 1. THE FLOOR — one °/s apart, and one of them never acquires at all.
	var lo: Dictionary = _res["r35"]
	var hi: Dictionary = _res["r36"]
	print("S48V_FLOOR  %.0f deg/s -> %s, miss %.2f m   ||   %.0f deg/s -> %s, miss %.2f m" %
		  [lo["rho"], _lock_str(lo["tlock"]), lo["miss"], hi["rho"], _lock_str(hi["tlock"]), hi["miss"]])
	if not (float(lo["tlock"]) < 0.0 and float(hi["tlock"]) > 0.0):
		return _fail(("ONE °/s of sweep rate must separate NEVER ACQUIRING from acquiring (%s vs %s) " +
					  "— the floor is the slider's own null and it must be reachable by a drag") %
					 [_lock_str(lo["tlock"]), _lock_str(hi["tlock"])])
	if not (float(lo["miss"]) > MISS_FLOOR):
		return _fail("the floor arm must miss by more than %.0f m (got %.2f)" % [MISS_FLOOR, lo["miss"]])

	# ⭐⭐⭐ 2. THE MISS IS FORBIDDEN AS THE GAUGE — AS A BIT-IDENTITY. Across the whole floor region
	# the head sweeps for seconds and the missile flies the SAME trajectory to the last bit, because
	# nothing the head does reaches the guidance until something is LOCKED.
	var null_arm: Dictionary = _res["r0"]
	var d_floor: float = _max_pos_diff(null_arm["pos"], lo["pos"])
	print(("S48V_NOISE  rho 0 vs %.0f: max|Δpos| = %.12f m over %d frames, while the head swept " +
		   "%d frames / %.3f s at the top of the region and 0 at the bottom") %
		  [lo["rho"], d_floor, null_arm["pos"].size(), lo["searching"], lo["elapsed"]])
	if not (d_floor <= EXACT):
		return _fail(("across the floor region the trajectory must be BIT-IDENTICAL (max|Δpos| = " +
					  "%.12f m) — nothing the head does reaches the guidance until something LOCKS, " +
					  "and that is what makes the miss useless as this slice's gauge") % d_floor)
	if not (lo["searching"] > 100 and null_arm["searching"] == 0):
		return _fail(("…and the two arms must differ VISIBLY in what the head did (%d vs %d searching " +
					  "frames) — if neither swept, the identity above is trivial and proves nothing") %
					 [lo["searching"], null_arm["searching"]])
	if not (absf(float(lo["miss"]) - float(null_arm["miss"])) <= EXACT):
		return _fail("…and their misses must be the same number, not merely close (%.6f vs %.6f)" %
					 [lo["miss"], null_arm["miss"]])

	# ⭐⭐ 3. THE AXIS — `t_search` falls MONOTONICALLY across the locking domain. This is the one
	# gauge that is a line here; the authority is a three-region verdict and the miss is nothing.
	# ⚠ A PLAIN LITERAL, SO THE PERCENTS ARE SINGLE. `%%` is an ESCAPE for the `%` OPERATOR, and
	# this line applies no operator — the first run printed "auth %%" on screen. The same family of
	# defect as slice 21's silent-format bug, one level milder.
	print("S48V_AXIS     rho deg/s   t_search s      auth %      hold %      miss m")
	var prev_t := 1.0e30
	for rho in LADDER:
		var a: Dictionary = _res["r%d" % int(round(rho))]
		print("S48V_AXIS   %11.1f %12.4f %10.2f %10.2f %11.4f" %
			  [a["rho"], a["tlock"], 100.0 * float(a["auth"]), a["hold"], a["miss"]])
		if not (float(a["tlock"]) >= 0.0):
			return _fail("arm r%d must acquire — every rate above the floor does" % int(round(rho)))
		if not (float(a["tlock"]) < prev_t):
			return _fail(("the time to find the target must fall MONOTONICALLY with the sweep rate " +
						  "(%.4f s at %.0f °/s, after %.4f s) — a non-monotone axis is not a lesson, " +
						  "and this project has disqualified four sliders for exactly that") %
						 [a["tlock"], a["rho"], prev_t])
		prev_t = float(a["tlock"])
		if not (float(a["hold"]) > HOLD_OK):
			return _fail("arm r%d must hold its track once acquired (hold %.2f %%)" % [int(round(rho)), a["hold"]])

	# ⭐⭐⭐ 4. THE EDGE — 0.086 s of earlier lock, and the engagement inverts. This is the slice.
	var e_lo: Dictionary = _res["r%d" % int(RHO_EDGE_LO)]
	var e_hi: Dictionary = _res["r%d" % int(RHO_EDGE_HI)]
	var dt_lock: float = float(e_lo["tlock"]) - float(e_hi["tlock"])
	print(("S48V_EDGE   %.0f deg/s: found in %.4f s, spent %.1f%% of a_max, MISSED by %.2f m   ||   " +
		   "%.0f deg/s: found %.4f s sooner, spent %.1f%%, arrived at %.2f m") %
		  [e_lo["rho"], e_lo["tlock"], 100.0 * float(e_lo["auth"]), e_lo["miss"],
		   e_hi["rho"], dt_lock, 100.0 * float(e_hi["auth"]), e_hi["miss"]])
	if not (float(e_lo["auth"]) >= AUTH_PINNED and float(e_lo["miss"]) > MISS_PINNED):
		return _fail(("⭐⭐⭐ the arm below the edge must be PINNED at the airframe's limit (%.4f of " +
					  "a_max) AND STILL MISS (%.2f m) — 'it found the target' and 'it made the shot' " +
					  "are different claims, and that difference is the whole slice") %
					 [e_lo["auth"], e_lo["miss"]])
	if not (float(e_hi["auth"]) < AUTH_CHEAP and float(e_hi["miss"]) < HIT_MAX):
		return _fail(("…and the arm above it must arrive CHEAPLY (%.4f of a_max, %.2f m) — if both " +
					  "sides of the edge cost the same, there is no edge") %
					 [e_hi["auth"], e_hi["miss"]])
	if not (dt_lock > 0.0 and dt_lock < 0.25):
		return _fail(("…and the two must be separated by a SMALL slice of time (%.4f s) — the claim is " +
					  "that a twelfth of a second of searching inverts the engagement, not that a " +
					  "much earlier lock helps, which would be obvious") % dt_lock)

	# ⭐⭐ 5. THE THREE REGIONS, each asserted for its own reason.
	for rho in [45.0, 50.0, 60.0]:
		var a: Dictionary = _res["r%d" % int(round(rho))]
		if not (float(a["auth"]) >= AUTH_PINNED and float(a["miss"]) > MISS_PINNED):
			return _fail(("the PINNED region must spend everything and still miss — r%d spent %.4f of " +
						  "a_max and missed by %.2f m. That region IS the lesson: the missile finds " +
						  "the target every time, flies at its limit, and arrives too late anyway") %
						 [int(round(rho)), a["auth"], a["miss"]])
	var top: Dictionary = _res["r%d" % int(RHO_TOP)]
	if not (float(top["auth"]) < AUTH_CHEAP and float(top["miss"]) < HIT_MAX):
		return _fail(("the TOP of the slider must arrive cheaply (%.4f of a_max, %.2f m) — a slider " +
					  "whose upper half is indistinguishable from its middle has a decorative half") %
					 [top["auth"], top["miss"]])
	print("S48V_REGION never (≤%.0f) / found-but-pinned-and-missing (%.0f–%.0f) / found-early-and-cheap (≥%.0f)" %
		  [RHO_FLOOR_LO, RHO_FLOOR_HI, RHO_EDGE_LO, RHO_EDGE_HI])

	# ⭐ 6. DETERMINISM — the master check (convention 2).
	var d_rep: float = _max_pos_diff(_res["r%d" % int(RHO_EDGE_HI)]["pos"], _res["replay"]["pos"])
	print("S48V_REPLAY r%d max|Δpos| = %.12f m over %d frames" %
		  [int(RHO_EDGE_HI), d_rep, _res["replay"]["pos"].size()])
	if not (d_rep <= EXACT):
		return _fail("replay differs by %.12f m — determinism is the master check" % d_rep)

	# ⭐⭐ 7. THE BUTTON — AND IT IS A BYTE-IDENTITY CLAIM. With the horizon off the seeker has its
	# target from tick 1, so there is nothing to search for and the slider is read by nothing.
	# *You only search because you were blind.*
	var d_off: float = _max_pos_diff(_res["off_lo"]["pos"], _res["off_hi"]["pos"])
	print("S48V_BUTTON horizon OFF: rho %.0f vs %.0f -> max|Δpos| = %.12f m over %d frames (miss %.3f / %.3f)" %
		  [RHO_NULL, RHO_TOP, d_off, _res["off_lo"]["pos"].size(),
		   _res["off_lo"]["miss"], _res["off_hi"]["miss"]])
	if not (d_off <= EXACT):
		return _fail(("with the horizon off the slider must do NOTHING (max|Δpos| = %.12f m) — the " +
					  "search is gated on the target being outside the window while the receiver can " +
					  "hear it, and a wire where the sweep leaks into a seeing missile has a second, " +
					  "unnamed path into the guidance") % d_off)
	if not (float(_res["off_lo"]["miss"]) < HIT_MAX):
		return _fail("with the horizon off the missile must simply hit (%.3f m)" % _res["off_lo"]["miss"])

	# ⭐ 8. THE MID-RUN PRESS — the horizon removed at 3.2 s, WHILE THE MISSILE IS STILL BLIND and
	# flying its (wrong) picture, with the slider at its NULL. It must acquire essentially at once:
	# the belief-cued head has been pointing 1.34° outside the window the whole time and only the
	# RANGE half was refusing it. ⚠ This is also the only place a `set_fidelity` is proven to reach
	# this rung with the midcourse arm LIVE.
	var mp: Dictionary = _res["midpress"]
	print(("S48V_PRESS  press at %.3f s with the sweep at %.0f deg/s -> lock at %.3f s, miss %.3f m " +
		   "(the same slider position misses by %.1f m with the horizon left on)") %
		  [PRESS_AT * _dt, RHO_NULL, mp["tlock_frame"], mp["miss"], _res["r0"]["miss"]])
	# ⭐⭐⭐ AND THE PRESS ARM CARRIES A LESSON THE LADDER CANNOT: **THE HANDOVER ERROR IS THE PICTURE
	# ERROR TIMES THE TIME SPENT BLIND** (slice 47 §7.2, re-measured here on a wire it was not
	# measured on). Identical slider, identical belief, identical trajectory up to the press — and a
	# handover error less than half the size, because the belief and the truth have had a third less
	# time to separate. ⇒ the DEFICIT a search has to cover is not a property of the picture error at
	# all; it is a property of WHEN the receiver opens.
	print("S48V_DURATION same picture error: blind to %.3f s -> %.4f deg, blind to %.3f s -> %.4f deg" %
		  [PRESS_AT * _dt, mp["cue"], T_HAND, _res["r0"]["cue"]])
	if not (float(mp["cue"]) < 0.75 * float(_res["r0"]["cue"])):
		return _fail(("the same picture error handed over EARLY must give a much smaller angle " +
					  "(%.4f deg at %.3f s against %.4f deg at %.3f s) — if it does not, the deficit " +
					  "is not accumulating with time and the mechanism is not the one this slice " +
					  "and slice 47 both claim") %
					 [mp["cue"], PRESS_AT * _dt, _res["r0"]["cue"], T_HAND])
	if not (mp["cued"] > 100 and float(mp["tlock_frame"]) >= PRESS_AT * _dt - 0.05
			and float(mp["tlock_frame"]) <= PRESS_AT * _dt + 0.05):
		return _fail(("the mid-run press must acquire within a frame or two of itself (press %.3f s, " +
					  "lock %.3f s, %d cued frames before it) — the cued head was 1.34° outside the " +
					  "window and only the RANGE half was refusing it") %
					 [PRESS_AT * _dt, mp["tlock_frame"], mp["cued"]])
	if not (float(mp["miss"]) < MISS_PRESS_MAX):
		return _fail(("…and removing the horizon early must SAVE the shot (%.3f m) at a sweep rate " +
					  "that otherwise never finds the target at all — which is the whole 'you only " +
					  "search because you were blind' claim, stated as an intervention") % mp["miss"])
	if not (mp["searching"] == 0):
		return _fail(("…and it must never have searched (%d frames) — the slider is at its null on " +
					  "this arm, so the save is the BUTTON's and not the sweep's") % mp["searching"])

	print("S48V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice48_search":
		return "wrong scenario '%s' — run scenarios/slice48_search.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, RAISED **BESIDE** 46's AND 47's RATHER THAN INSTEAD OF THEM. This is slice 47's
	# wire with the trunnion widened and a search on the head, so 46's button is still the sharpest
	# A/B it has and 47's belief segment is still what the head sweeps ABOUT.
	if not bool(f.get("search_view", false)):
		return ("a slice-48 handshake must ship search_view=true — without it the client draws slice " +
				"47's HUD over a missile whose whole story is what the head did AFTER the cue turned " +
				"out to be wrong, and the sweep never reaches the screen")
	for k in ["midcourse_view", "seeker_detect_view", "gimbal_view", "gimbal_rate_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-48 wire IS a slice-47 wire (which IS slice 46's) with a search on the " +
					"head, so it must still raise %s — the superset relation is what makes the new " +
					"marker a BRANCH SELECTOR rather than a hole plug") % k
	for k in ["radome_view", "seeker_fov_view", "gimbal_servo_view", "gimbal_frame_view"]:
		if bool(f.get(k, false)):
			return ("a slice-48 wire must NOT raise %s — it would either put a second mechanism " +
					"beside this lesson or point the shared button at another slice's rung") % k
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "seeker_search_rate_dps":
		return ("exactly ONE knob, the MISSILE's `seeker_search_rate_dps` (convention 9). " +
				"`seeker_search_coverage_deg` is the RESERVE axis and its own slice; " +
				"`midcourse_err_gain` is retired to an authored key here (it would move the deficit " +
				"under this lesson); `rcs_m2` is slice 46's axis and would move the horizon, the " +
				"blind duration and the handover range at once; `gimbal_fov_deg` is TWO-SIDED since " +
				"slice 46; and the belief-error VECTORS are refused at load BY TYPE")
	if not (float(kn[0].get("min", -1.0)) == 0.0 and float(kn[0].get("max", 0.0)) == RHO_TOP):
		return (("the slider must span 0–%.0f °/s: the floor is a TRUE NULL (a head that does not " +
				 "sweep at all — exactly what ships without this slice) and the ceiling is the " +
				 "servo's own maximum slew rate, so the top of the slider is the hardware's limit " +
				 "rather than an arbitrary number") % RHO_TOP)
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR — the floor region (0–35 °/s) is a seventh of the travel " +
				"and must READ as a region, which is exactly what a log slider would destroy")
	return ""

func _reset_scan_accum() -> void:
	_min_los = 1.0e30; _prev_los = 1.0e30; _closing = true; _turned = false
	_n_gate = 0; _n_post = 0; _n_held = 0; _t_lock_frame = -1.0
	_auth_peak = 0.0; _n_sat_pre = 0; _n_sat_post = 0; _n_cued = 0; _n_searching = 0
	_cue_hand = 0.0; _def_max = 0.0; _def_first = -1.0; _t_lock_key = -1.0
	_elapsed_max = 0.0; _n_srchkey = 0
	_win_seen = 0.0; _stop_seen = 0.0; _rate_seen = 0.0; _cov_seen = 0.0; _rho_seen = 0.0
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
	# ⚠ `entities` IS AN ARRAY OF RECORDS, not a dictionary keyed by id (the wire's own shape).
	var mp: Array = _missile_pos(f)
	if mp.is_empty():
		return
	_pos_trace.append(mp)
	var t := float(f.get("t", 0.0))
	var los := float(tel.get(MID + ".los_range", 1.0e30))
	# ⚠ FIRST-DESCENDING-BAND ONLY: once the range turns, the post-CPA re-crossings are a different
	# engagement — and on this wire they climb back through the 200 m gate from the FAR side, which
	# is how the gate-0 probes read 78.2 % where the closing band says 71.2.
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
	_cov_seen = float(tel.get(MID + ".search_coverage_deg", _cov_seen))
	_rho_seen = float(tel.get(MID + ".search_rate_dps", _rho_seen))
	# ⭐⭐ THE LATCHED KEYS. `search_t_lock_s` holds −1.0 until a lock and then freezes at the time
	# the search took; `search_elapsed_s` freezes at the total. Both are read as latches rather than
	# frame-sampled, because a client sees one frame in `emit_every` = 16 ticks and the numbers this
	# file asserts in seconds are 0.086 s apart at the edge.
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
			# ⚠ BOTH GATES: post-lock, r > 200 m, AND on the closing band (the early return above).
			_auth_peak = maxf(_auth_peak, float(tel.get(MID + ".a_cmd_frac", 0.0)))
		# ⚠⚠ SPLIT AT THE LOCK, AND THE SPLIT IS A GATE-3 MEASUREMENT RATHER THAN A LOOPHOLE. This
		# file first asserted slice 47's flat `sat == 0` and r36 failed it on 9 frames. Logging when:
		# EVERY saturated tick on EVERY arm falls at t ≥ 9.22 s — 2.3 s AFTER the lock and inside the
		# ENDGAME, where the LOS swings past the head faster than 240 °/s and the target leaves the
		# window (slice 34 measured that breach on every arm of this family). What is new is that the
		# search now RESUMES there instead of the head holding, so the head CHASES and the servo
		# pegs. It is after the engagement is decided and it is not this slice's mechanism — but the
		# isolation claim it was standing in for is real, so it is asserted where it means something:
		# BEFORE THE LOCK, where a saturating servo really would make "the sweep did not cover the
		# gap in time" unattributable to the sweep RATE.
		if float(tel.get(MID + ".head_rate_sat", 0.0)) >= 0.5:
			if _t_lock_frame < 0.0:
				_n_sat_pre += 1
			else:
				_n_sat_post += 1

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
# slice 46's slider lived on `tgt1` (the target's RCS), slice 47's on `m1` (the belief), and this one
# on `m1` too (the missile's own seeker).
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
	push_error("S48V FAIL: " + msg)
	print("S48V FAIL: ", msg)
	quit(code)
	return true
