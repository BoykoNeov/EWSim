extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-50 gate-3 verifier — THE ASPECT-DEPENDENT ENGAGEMENT.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice50_defensive.yaml
#   godot --headless --path clients/godot --script res://net/slice50_verify.gd     (exit 0 = pass)
#
# THE LESSON. Every slice from 26 to 49 treats "can the seeker see it?" as a question about the
# MISSILE — the window, the aperture, the transmit power, the sweep rate. This one asks what happens
# when the horizon moves because THE TARGET DID SOMETHING. The missile launches with a comfortable
# lock on a target flying broadside; the target turns its nose toward the missile at 3 g; the echo
# collapses, the horizon retreats back through the closing range, and the seeker LOSES A TARGET IT
# ALREADY HAD, while the range is still falling.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE, AND IT IS THE HALF A GROUND RADAR CANNOT SAY. Slice
# 49 already proved the detection half on a radar (a constant echo can be gained while closing and
# never lost, so no smaller `rcs_m2` fakes a shape). Quoting THAT here would be slice 49's finding
# wearing this slice's name. What is new is about an INTERCEPT: the missile flies the rest of the
# engagement on a FROZEN ESTIMATE, holding a heading error it can no longer learn about.
#
# ⭐⭐ THE GAUGE IS `ω_LOS · t_go` AT THE LOSS, IN DEGREES — "the heading error the missile went
# blind holding". Under PN the loop drives the line-of-sight rate toward zero while it can still
# see; whatever rate is left at the last look is a heading error, and `t_go` says how much flying
# was left to hold it through. Swap "seeker" for "radar" and the sentence does not become false, it
# becomes EMPTY: a radar does not fly, does not act on the estimate, has no collision course to be
# off and no time-to-go. Every noun loses its referent.
#
# ⚠⚠ THE MISS IS BANNED AND THIS SLICE RE-EARNED THE BAN. Above the slider's ceiling the CPA
# reverses FOUR times (1033 → 1039 → 618 → 1671 → 1505 → 1814 m) and re-acquisition itself goes
# non-monotone (F = 14 re-acquires while 12 and 16 do not), because a blind coast is an open-loop
# integration of a frozen estimate whose closest approach is chaotic in the initial condition. The
# gauge is read AT the loss for exactly that reason — everything upstream of the blind run is
# orderly and everything downstream of it is a divergence being sampled.
#
# ⚠ AND THE GAUGE IS MEASURED ON THE **EMITTED** GRID, WHICH IS NOT THE GRID THE PROBE USED. The
# core ticks at 1 ms and emits every 16, so the 1 → 0 transition a client can see lands up to one
# emission interval after the true loss and the gauge reads 5.702° where the per-tick probe measured
# 5.771°. The shift is DETERMINISTIC, so it pins — but it must be pinned from the frames a client is
# actually handed. ⭐ The same shape as the differencing-window lesson: when a gauge is latched at a
# TRANSITION, the emission interval is part of the estimator.
#
# ⚠⚠ TWO OF SLICE 49's TEETH DELIBERATELY DO **NOT** TRANSFER, and each absence is a decision:
#   1. NO "THE CONTROL MUST FLICKER". Slice 49's sphere control CAN fail because a Swerling-1 echo
#      is exponentially distributed and its radar draws a `Pd`. THIS gate is DETERMINISTIC — a hard
#      threshold, no draw (`missile.jl`'s own comment says so, and it is load-bearing: a `Pd` draw
#      here would be a class-(b) draw-topology hazard AND would destroy the structural proof, which
#      needs the threshold to be crossed exactly once in exactly one direction). ⇒ the sphere holds
#      its target on 100.0 % of frames, and that EXACTNESS is the assertion rather than a bound.
#   2. NO LOSS-RUN / DETECTED-% GAUGE. Both are functions of the same 0/1 detection trace and both
#      are sentences a ground radar says without difficulty — they are reported here as READOUTS and
#      asserted only as corroboration. Making either the headline would be slice 49's finding
#      re-denominated, which is the one failure this slice could not afford.
#
# ⚠⚠ AND ONE PRE-REGISTERED CONJUNCT IS **NOT APPLICABLE HERE**, recorded rather than dropped. The
# plan's §0.6 required the gauge's tick test to be `seeker_detect == 1` AND slice 48's RIM-MARGIN
# rule (`margin@lock > ω_LOS·dt`), on the reasoning that a retreating horizon manufactures exactly
# the state slice 48 caught: a lock taken with less window margin than one tick of LOS drift, which
# is consumed and buys nothing. **That rule is about the ANGULAR window and this loss is a RANGE-gate
# loss.** `missile.jl` ships the two verdicts as separate lamps on purpose — `gimbal_valid` carries
# the FOV conjunction, `seeker_detect` is the range verdict ALONE — and on this wire the head is
# tracking a target it holds, with the angular margin never in question, while the RANGE margin
# passes through zero at kilometres per second. ⇒ the conjunct would be a no-op that looked like a
# safeguard. ⭐ THE GENERAL FORM: a rule inherited from another slice must be re-checked against the
# QUANTITY it constrains, not just the situation it was written for.
#
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slices 25 and 49). Do not "tidy" this.
# ─────────────────────────────────────────────────────────────────────────────────────────────

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 3600.0
const SimClientScript := preload("res://net/SimClient.gd")

const MID := "m1"
const TID := "tgt1"

# ⚠⚠ `STEPS` MUST BE A MULTIPLE OF THE SCENARIO'S `emit_every` (16) or `_drain_scan` waits forever,
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this; the core pins `emit_every`
# as a test so an edit to either breaks here first). 8000 = 16 × 500.
# ⚠ AND 8.0 s IS CHOSEN AGAINST THE ENGAGEMENT RATHER THAN ROUNDED TO: CPA is at ~8.21 s, the latest
# loss is at 3.28 s and the latest RE-acquisition at 7.28 s, so this window contains every transition
# the lesson is made of and stops SHORT of the closest-approach spike (`ewsim-missile-verifier-
# sampling`: never read a loop state inside the r → 0 endgame).
const STEPS := 8000

# THE SLIDER — the target body's length/width ratio. FLOOR 1.0 is a SPHERE and the lesson's null;
# 7.0 is the last arm that still never loses the lock (the REAL control — see `_build_arms`); the
# authored wire opens at 8.0, mid-lesson; 10.0 is the ceiling, and it is 10 rather than slice 49's
# 12 because at 11+ the missile never re-acquires and the wire changes mechanism.
const F_SPHERE := 1.0
const F_NULL := 7.0
const F_AUTH := 8.0
const F_TOP := 10.0

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const RCS_BROADSIDE := 1.0        # m² — the BROADSIDE cross-section, which is what `rcs_m2` means
                                  # once a fineness is present (slice 49's normalization decision)
const R0_M := 6118.0              # the launch range — INSIDE the 8079 m broadside horizon
const RACQ0_M := 8079.0           # …and the horizon it is inside, at t = 0

# THE MEASURED COLUMN (`docs/plans/slice50.md` §7.1, re-measured on THIS grid — see the header).
# ⚠ THE TOOTH IS THE ORDER AND THE SEPARATION, NOT THE DIGIT.
const GAUGE_NULL_MAX := 1.0e-12   # deg — the null is EXACT: no loss, no latch, no number
const GAUGE_AUTH_MIN := 1.5       # deg — measured 2.380
const GAUGE_TOP_MIN := 4.0        # deg — measured 5.702
const GAUGE_SEP_MIN := 2.0        # ×   — measured 2.40× from the authored arm to the ceiling
const DET_NULL_EXACT := 1.0       # the sphere and F = 7 hold the target on EVERY frame (see above)
const DET_AUTH_MAX := 0.85        # measured 73.8 %
const DET_TOP_MAX := 0.50         # measured 37.2 %
const SIGMA_RATIO_MIN := 100.0    # ×   — measured 452× between the sphere and F = 7 at the
                                  # IDENTICAL geometry, over the WHOLE flight
const BROADSIDE_TOL := 1.0        # deg — the first frame must be broadside (where the curve PEAKS)
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
var _n_keys := 0                  # frames carrying ALL SIX keys the lesson needs — the never-stale
                                  # tooth, and on this slice it is the ONLY thing that can tell the
                                  # null's honest 0.000° from a defaulted one (they are equal)
var _first_det := false           # ⭐ the missile must START with the lock, or a loss is not a loss
var _first_asp := -1.0            # …and it must start BROADSIDE, where the curve peaks
var _first_sigma := -1.0
var _first_racq := -1.0
var _first_r := -1.0
var _min_asp := 1.0e30
var _max_sigma := -1.0e30
var _prev_det := -1.0             # the edge detector (−1 = no frame yet, so frame 1 is not an edge)
var _latched := false
var _gauge := 0.0                 # ⭐⭐⭐ THE GAUGE: ω_LOS · t_go at the loss, DEGREES
var _t_loss := -1.0
var _r_loss := -1.0
var _racq_loss := -1.0
var _loss_frame := -1
var _regained := false
var _regain_t := -1.0
var _pos_trace: Array = []
var _sig_trace: Array = []
var _racq_trace: Array = []

func _initialize() -> void:
	print("S50V_INIT godot=", Engine.get_version_info().string)
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
	# ⭐⭐ 1. THE LESSON'S NULL — a sphere, aspect-independent BY CONSTRUCTION.
	_arms.append({"tag": "sphere", "f": F_SPHERE})
	# ⭐⭐⭐ 2. THE REAL CONTROL, AND IT IS NOT THE SPHERE. At F = 1 the mechanism is switched off
	#    entirely, so a separation against it proves only that the mechanism exists. F = 7 is the
	#    SAME mechanism, sub-threshold: the echo is 452× dimmer than the sphere's at the identical
	#    geometry, the horizon really does retreat, and the lock is STILL never lost. That is what
	#    makes the threshold a threshold rather than a slope, and it is the arm that would catch a
	#    lesson that had quietly become "any shape at all loses the lock".
	_arms.append({"tag": "null", "f": F_NULL})
	# ⭐⭐⭐ 3. THE AUTHORED WIRE — the arm that ships, and the one the showcase opens on.
	_arms.append({"tag": "auth", "f": F_AUTH})
	# ⭐ 4. THE CEILING — more of the same, which is the point: the top of the slider must not be a
	#    new regime. ⚠ IT IS 10 AND NOT SLICE 49's 12 BECAUSE 11+ **IS** A NEW REGIME (the missile
	#    never re-acquires, and its miss is a divergence being sampled).
	_arms.append({"tag": "top", "f": F_TOP})
	# ⭐ 5. DETERMINISM — same seed, same slider ⇒ the same flight AND the same seeing AND the same
	#    gauge (convention 2, the master check).
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
	# ⚠⚠ AND THE `reset` IS ALSO WHAT MAKES THESE ARMS HONEST FOR **THIS** GAUGE SPECIFICALLY. The
	# gauge is latched at an INSTANT whose meaning is the whole from-launch history that led to it,
	# so a `set_param` sent mid-flight would produce a number that is not this slice's under this
	# slice's label. The client's own HUD DISARMS its latch on a live drag for exactly that reason
	# (and `slice50_ui_test.gd` is the only one of the four proofs that reaches a drag at all).
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
		"gauge": _gauge, "t_loss": _t_loss, "r_loss": _r_loss, "racq_loss": _racq_loss,
		"loss_frame": _loss_frame, "latched": _latched,
		"regained": _regained, "regain_t": _regain_t,
		"first_det": _first_det, "first_asp": _first_asp, "first_sigma": _first_sigma,
		"first_racq": _first_racq, "first_r": _first_r,
		"min_asp": _min_asp, "max_sigma": _max_sigma, "keys": _n_keys,
		"pos": _pos_trace.duplicate(true), "sig": _sig_trace.duplicate(),
		"racq": _racq_trace.duplicate(),
	}
	_res[tag] = m
	# ⚠ THE SENTINELS ARE RENDERED AS WORDS, NOT PRINTED AS NUMBERS. `_t_loss` / `_r_loss` are −1 on
	# an arm that never loses the lock, and "t=-1.000 s / r=-1.0 m" reads as a MEASUREMENT of a
	# negative time — the same class as `%.2f` printing a live 2.5e-4 as "0.00", one readout over.
	# On this slice it matters more than usual: the null's honest state and a dead instrument are
	# already indistinguishable by value, so nothing here may add a third zero-shaped thing.
	var when := "never lost" if not bool(m["latched"]) else \
				("t=%6.3f s / r=%7.1f m" % [m["t_loss"], m["r_loss"]])
	print(("S50V_ARM   %-7s F=%5.1f  ->  owed %6.3f deg at %-22s  lock back: %-3s  " +
		   "held %5.1f pct of frames   aspect %5.1f -> %5.1f deg   frames=%d") %
		  [tag, m["f"], m["gauge"], when, "yes" if m["regained"] else "n/a" if not m["latched"] else "no",
		   100.0 * det_frac, m["first_asp"], m["min_asp"], m["frames"]])

	if not (_n_frames == STEPS / 16):
		return "arm %s: the run must produce a full frame history (got %d of %d)" % [tag, _n_frames, STEPS / 16]
	# ⭐⭐⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47/48/49), AND ON THIS SLICE IT IS LOAD-BEARING IN A
	# WAY IT HAS NEVER BEEN BEFORE. The lesson's NULL reads 0.000° and a MISSING `seeker_tgo_s` read
	# downstream through `.get(k, 0.0)` ALSO reads 0.000° — **the legitimate value and the failure
	# mode are the same number**, so no value assertion anywhere in this file can tell them apart.
	# Key PRESENCE is the only thing that can, which is why it is counted as a SET and asserted on
	# every frame of every arm, and why the client tracks it independently of the value it reads.
	if not (_n_keys == _n_frames):
		return (("arm %s: all six seeker/aspect keys must ship on EVERY frame (%d of %d). On this " +
				"slice that is not hygiene: the null's honest 0.000 deg and a defaulted 0.000 deg " +
				"from a missing `seeker_tgo_s` are THE SAME NUMBER, so presence is the only thing " +
				"that separates a measured null from a dead instrument") % [tag, _n_keys, _n_frames])
	# ⭐⭐ IT MUST START WITH THE LOCK, OR A LOSS IS NOT A LOSS. This is the premise the whole slice
	# rests on and it is what separates arm B from a slice-46/47/48 "never acquired" story: the
	# missile is launched INSIDE the broadside horizon, holding the target, and the question is
	# whether the target can TAKE THAT BACK.
	if not _first_det:
		return (("arm %s: the missile must hold the lock on the FIRST frame — it launches at %.0f m " +
				"INSIDE an %.0f m broadside horizon, and an arm that starts blind is measuring a " +
				"failure to acquire, which is slices 46-48's subject and not this one's") %
				[tag, R0_M, RACQ0_M])
	# …and it must start BROADSIDE, which is where an aspect curve PEAKS. ⚠ This is also the cheap
	# consistency check on `aspect_angle`'s CONVENTION (0 = nose-on, 90 = broadside): if the vector
	# were built observer→target the angle would reflect about 90°, invisible under the model's
	# fore/aft symmetry and silently wrong everywhere else. ⭐ AND IT IS WHAT MAKES THE ARMS
	# COMPARABLE AT ALL — `rcs_aspect(σ, F, π/2) = σ` for EVERY fineness, so every arm of the slider
	# opens on the identical cross-section and any later difference is the TURN.
	if absf(_first_asp - 90.0) > BROADSIDE_TOL:
		return (("arm %s: the first frame must read BROADSIDE (%.3f deg, want 90) — every arm must " +
				"open on the SAME cross-section, which is only true at the curve's peak, and this " +
				"is also the check on aspect_angle's own convention (0 = nose-on)") % [tag, _first_asp])
	# …and at broadside σ_eff IS the authored broadside RCS, at every fineness. ⚠ ASSERTED AS A
	# NEAR-EQUALITY WITH A MEASURED TOLERANCE: the first frame a client sees is `emit_every` = 16
	# ticks AFTER launch, so the nose has already come ~0.04° off broadside. The EXACT identity lives
	# where it can be stated exactly, in the core (`test_rcs_aspect.jl` pins θ = π/2 to 1e-12); a
	# frame-sampled client cannot see t = 0 and must not pretend to.
	if absf(_first_sigma - RCS_BROADSIDE) > 1.0e-3 * RCS_BROADSIDE:
		return (("arm %s: the first frame must read essentially the authored broadside RCS (%.6f vs " +
				"%.3f m²) — it is 16 ticks after launch, which is a fraction of a degree off " +
				"broadside, not 0.1 %%") % [tag, _first_sigma, RCS_BROADSIDE])
	# ⭐ AN EXACT EXTERNAL ANCHOR, ASSERTED AS ONE: broadside is the PEAK of a prolate body's curve,
	# so no frame on any arm may ever come back BRIGHTER than the authored `rcs_m2`.
	if _max_sigma > RCS_BROADSIDE + 1.0e-12:
		return (("arm %s: no frame may be BRIGHTER than the authored broadside RCS (%.12f > %.3f m²) " +
				"— broadside is the peak of a prolate body's curve, and a σ above it means the " +
				"normalization has come undone") % [tag, _max_sigma, RCS_BROADSIDE])
	# ⭐ THE NOSE MUST ACTUALLY COME ROUND. The turn is the mechanism, not the staging — a
	# straight-flying target could not produce this lesson at any fineness, which is precisely why
	# this wire could not be slice 48's (its target's aspect walks the WRONG WAY, toward broadside,
	# so its horizon EXPANDS).
	if not (_min_asp < 60.0):
		return (("arm %s: the aspect must travel well off broadside inside the window (minimum " +
				"%.1f deg) — a target that does not turn its nose toward the missile cannot show " +
				"this at any fineness") % [tag, _min_asp])
	# ⚠⚠ THE LAUNCH CONDITION, ASSERTED RATHER THAN ASSUMED, AND IT IS THE ONE §0.3's ARITHMETIC GOT
	# WRONG. The drop-out exists only if the horizon crosses the range BEFORE closest approach, and
	# that condition has `r₀²` in the DENOMINATOR — so launching DEEPER inside the horizon makes the
	# crossing HARDER, not easier. The RATIO `R_acq/r₀` is the design variable, and an edit that
	# quietly moved either number would delete the lesson while every other assertion here still
	# passed. ⭐ THE TRANSFERABLE FORM: a design condition evaluated AT a crossing has not shown the
	# crossing EXISTS.
	if not (_first_racq > _first_r):
		return (("arm %s: the missile must launch INSIDE the broadside horizon (R_acq %.0f m vs " +
				"range %.0f m) — otherwise it never had a lock to lose and this is a slice-46 " +
				"acquisition story") % [tag, _first_racq, _first_r])
	if absf(_first_r - R0_M) > 20.0 or absf(_first_racq - RACQ0_M) > 20.0:
		return (("arm %s: the launch geometry has moved (r0 %.0f m want %.0f, R_acq %.0f m want " +
				"%.0f) — their RATIO is what decides whether the horizon crosses the range before " +
				"CPA at all, and a deeper launch makes the drop-out HARDER, not easier") %
				[tag, _first_r, R0_M, _first_racq, RACQ0_M])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var sph: Dictionary = _res["sphere"]
	var nul: Dictionary = _res["null"]
	var aut: Dictionary = _res["auth"]
	var top: Dictionary = _res["top"]

	# ⭐⭐ 1. THE TWO NULL ARMS — AND THE SECOND ONE IS THE REAL CONTROL.
	# ⚠ THE SPHERE HOLDS ITS TARGET ON **EVERY** FRAME, ASSERTED AS AN EXACTNESS RATHER THAN AS A
	# BOUND, and that is a genuine difference from slice 49 rather than a tightening for its own
	# sake. Slice 49's radar draws a Swerling-1 `Pd`, so its sphere control flickers and its file
	# asserts that it does. THIS gate is DETERMINISTIC — a hard threshold with no draw — so for a
	# constant echo `r ≤ R_acq` is one threshold against a range that only comes down, crossed once
	# and inward. A sphere that dropped even one frame here would mean the gate had acquired a draw.
	for a in [sph, nul]:
		print("S50V_NULL  F=%.1f: held the lock on %.1f%% of frames, gauge %.9f deg (aspect swept %.1f -> %.1f)" %
			  [a["f"], 100.0 * float(a["det"]), a["gauge"], a["first_asp"], a["min_asp"]])
		if not (float(a["det"]) == DET_NULL_EXACT):
			return _fail(("F = %.1f must hold the lock on EVERY frame (%.4f) — this gate is " +
						  "DETERMINISTIC, no `Pd` draw, so for a fixed-enough echo detection is one " +
						  "threshold against a range that only comes down. A dropped frame here " +
						  "means the gate has acquired a draw, which would also destroy the " +
						  "structural proof this slice rests on") % [a["f"], float(a["det"])])
		if bool(a["latched"]):
			return _fail("F = %.1f must never latch the gauge — it never loses the lock" % a["f"])
		if not (absf(float(a["gauge"])) <= GAUGE_NULL_MAX):
			return _fail(("F = %.1f must read the gauge as an EXACT zero (%.12f deg) — this is a " +
						  "MEASURED null, not a defaulted one, and the difference is proved by the " +
						  "byte-identity below rather than by the number") % [a["f"], a["gauge"]])

	# ⭐⭐⭐ 2. …AND THE F = 7 CONTROL IS THE ONE THAT MAKES THE THRESHOLD A THRESHOLD. Its echo is
	# hundreds of times dimmer than the sphere's at the identical geometry — the mechanism is fully
	# switched ON — and the lock is still never lost. Without this arm the lesson could quietly have
	# been "any shape at all loses the lock", which is a slope and not a threshold.
	var sig_ratio := 0.0
	var n_sig: int = mini(sph["sig"].size(), nul["sig"].size())
	for i in range(n_sig):
		sig_ratio = maxf(sig_ratio, float(sph["sig"][i]) / maxf(float(nul["sig"][i]), 1.0e-30))
	print("S50V_CONTROL F=%.1f: echo up to %.1fx dimmer than the sphere at the IDENTICAL geometry (%.1f dB), and the lock is STILL never lost" %
		  [nul["f"], sig_ratio, 10.0 * (log(sig_ratio) / log(10.0))])
	if not (sig_ratio >= SIGMA_RATIO_MIN):
		return _fail(("the F = %.1f control must be a SUB-THRESHOLD arm of the SAME mechanism, not " +
					  "a second null (echo only %.1fx dimmer, bound %.0f) — and this doubles as the " +
					  "slider's own tripwire: a `set_param` that is accepted and never CONSUMED " +
					  "passes every sent-vs-echoed check there is and fails exactly here") %
					 [nul["f"], sig_ratio, SIGMA_RATIO_MIN])

	# ⭐⭐⭐ 3. THE SLICE. The lock is TAKEN BACK while the range is still falling — and then GIVEN
	# BACK, with a heading error the missile could not learn about while it was blind.
	for a in [aut, top]:
		print(("S50V_LESSON F=%.1f: LOCK TAKEN BACK at t=%.3f s, r=%.0f m (launched at %.0f m — " +
			   "STILL CLOSING), horizon had retreated to %.0f m; owed %.3f deg; lock back at t=%.3f s") %
			  [a["f"], a["t_loss"], a["r_loss"], a["first_r"], a["racq_loss"], a["gauge"], a["regain_t"]])
		if not bool(a["latched"]):
			return _fail(("F = %.1f must LOSE the lock it launched with — that is the whole slice, " +
						  "and an arm that never loses it has nothing to measure") % a["f"])
		# ⭐⭐⭐ THE STRUCTURAL ASSERTION, AND IT IS THE ONE NO CONSTANT `rcs_m2` CAN SATISFY. The
		# range at the loss is SMALLER than the range at launch: the target was lost while getting
		# CLOSER. A fixed horizon has `dR_acq/dt = 0`, so it is crossed exactly once and inward, and
		# cannot take a lock back at any value. ⚠ This is the half of the sentence slice 49 already
		# proved on a ground radar — it is asserted here because it is the PREMISE of the new half,
		# not because it is this slice's finding.
		if not (float(a["r_loss"]) < float(a["first_r"]) - 100.0):
			return _fail(("F = %.1f lost the lock at %.0f m having launched at %.0f m — the loss " +
						  "must happen while the range is still FALLING. A constant echo cannot do " +
						  "this at any value: a fixed horizon is crossed once and inward") %
						 [a["f"], a["r_loss"], a["first_r"]])
		# …and the horizon must have RETREATED to meet it, rather than the range having run out to
		# reach a horizon that stood still. This is the mechanism, separated from the outcome.
		if not (float(a["racq_loss"]) < float(a["first_racq"]) - 100.0):
			return _fail(("F = %.1f: the HORIZON must be what moved (R_acq %.0f m at the loss vs " +
						  "%.0f m at launch) — if it stood still then the range simply ran out and " +
						  "this is slice 46's lesson, not this one") %
						 [a["f"], a["racq_loss"], a["first_racq"]])
		# ⭐⭐ …AND IT MUST BE GIVEN BACK. This is what separates the teachable domain from the region
		# above it: below the ceiling the missile re-acquires and the price is a heading error it now
		# has less time to remove; at F ≥ 11 it never does, flies blind through CPA, and its miss
		# reverses four times across the remaining domain. A slider whose top was that region would
		# hand a student a place where dialling further makes things unpredictably better.
		if not bool(a["regained"]):
			return _fail(("F = %.1f never re-acquired — the slider's CEILING is set at %.0f for " +
						  "exactly this reason, and an arm inside the domain that flies blind " +
						  "through CPA means the ceiling has moved into the chaotic region") %
						 [a["f"], F_TOP])
	if not (float(aut["gauge"]) >= GAUGE_AUTH_MIN):
		return _fail("the authored wire must owe a real heading error (%.3f deg, bound %.1f)" %
					 [aut["gauge"], GAUGE_AUTH_MIN])
	if not (float(top["gauge"]) >= GAUGE_TOP_MIN):
		return _fail("the ceiling must owe substantially more (%.3f deg, bound %.1f)" %
					 [top["gauge"], GAUGE_TOP_MIN])
	# ⚠ THE DETECTED FRACTION AND THE BLIND TIME ARE **READOUTS**, ASSERTED ONLY AS CORROBORATION.
	# Both are functions of the same 0/1 trace and both are sentences a ground radar says without
	# difficulty — making either the headline would be slice 49's finding re-denominated, which is
	# the one failure this slice could not afford (there is no model to fall back on: the physics
	# shipped with slice 49, so only the LESSON was ever in question).
	if not (float(aut["det"]) <= DET_AUTH_MAX and float(top["det"]) <= DET_TOP_MAX):
		return _fail("corroboration: the shaped arms must spend real time blind (%.3f / %.3f)" %
					 [aut["det"], top["det"]])

	# ⭐⭐ 4. THE LADDER IS MONOTONE IN THE GAUGE. `k` (28), `ω_n` (40), `σ_seek` (25), the authority
	# (48) and the loss COUNT (49) all died as gauges on non-monotonicity; this one is asserted.
	# ⚠ `held pct`, NOT `held %%`. A `%`-formatted string with NO argument list never has its `%%`
	# unescaped, so the header would print a literal double percent under a table of clean numbers —
	# the harmless end of the same silent-format family that makes an unknown specifier print the
	# format string itself on a green run.
	print("S50V_AXIS       F   owed deg     t_loss     r_loss   held pct   lock back")
	var prev_gauge := -1.0
	for tag in ["sphere", "null", "auth", "top"]:
		var a: Dictionary = _res[tag]
		print("S50V_AXIS   %5.1f %10.3f %10s %10s %10.1f   %s" %
			  [a["f"], a["gauge"],
			   "—" if not a["latched"] else "%.3f s" % float(a["t_loss"]),
			   "—" if not a["latched"] else "%.0f m" % float(a["r_loss"]),
			   100.0 * float(a["det"]),
			   "yes" if a["regained"] else ("never lost" if not a["latched"] else "NO")])
		if not (float(a["gauge"]) >= prev_gauge):
			return _fail(("the heading error owed must RISE with fineness (%.3f deg at F = %.1f, " +
						  "after %.3f) — a non-monotone gauge is not a lesson, and this project has " +
						  "disqualified five for exactly that") % [a["gauge"], a["f"], prev_gauge])
		prev_gauge = float(a["gauge"])
	# …and the two shaped arms must actually SEPARATE, or the slider's top half is decorative.
	var sep: float = float(top["gauge"]) / maxf(float(aut["gauge"]), 1.0e-9)
	print("S50V_SEP    from the authored wire to the ceiling: %.3f -> %.3f deg (%.2fx)" %
		  [aut["gauge"], top["gauge"], sep])
	if not (sep >= GAUGE_SEP_MIN):
		return _fail("the ceiling must owe materially more than the authored wire (%.2fx, bound %.1f)" %
					 [sep, GAUGE_SEP_MIN])
	# ⭐ AND THE LOSS MOVES EARLIER AND FURTHER OUT AS THE BODY GETS SLENDERER — a second, independent
	# reading of the same mechanism, and the one that says WHY the gauge rises: the horizon retreats
	# sooner, so PN has had less time to null ω before the picture goes.
	# ⚠⚠ AND THIS FILE MUST NOT CLAIM THE MECHANISM IS ISOLATED. The loss also moves to LONGER RANGE,
	# and under PN on a collision course ω falls with range — so both effects push the same way and a
	# monotone rise cannot discriminate between them. The SIGN is confirmed; the mechanism is
	# consistent-but-not-isolated, and saying so is the difference between a finding and a story.
	if not (float(top["t_loss"]) < float(aut["t_loss"]) and float(top["r_loss"]) > float(aut["r_loss"])):
		return _fail(("the loss must move EARLIER (%.3f vs %.3f s) and FURTHER OUT (%.0f vs %.0f m) " +
					  "as the body slims — that is the mechanism showing through the gauge") %
					 [top["t_loss"], aut["t_loss"], top["r_loss"], aut["r_loss"]])

	# ⭐⭐⭐ 5. THE BYTE-IDENTITY, AND IT IS WHAT TURNS THE NULL FROM A DEFINITION INTO A MEASUREMENT.
	# `rcs_aspect` touches the DETECTION and nothing else — it is not in the dynamics — and
	# `ManeuveringTarget` never reads the missile, so a shape that changes no verdict changes NOTHING.
	# Across the whole null region the engagement is byte-for-byte the one that ships WITHOUT this
	# slice. ⇒ a gauge reading 0 there is reporting a measured null, which is the difference between
	# an EXTENSION and an INTERPOLATION — and it is also this slice's answer to the confound that
	# killed slice 41: a turn moves the trajectory as well as the aspect, so every arm flies the
	# IDENTICAL manoeuvre and any difference is ASPECT and cannot be geometry.
	var d_null: float = _max_pos_diff(sph["pos"], nul["pos"], sph["pos"].size())
	print("S50V_FLIGHT F=%.1f vs F=%.1f over ALL %d frames: max|Δpos| = %.12f m — the mechanism is fully ON at F=%.1f (%.0fx dimmer) and the FLIGHT is bit-identical" %
		  [sph["f"], nul["f"], sph["pos"].size(), d_null, nul["f"], sig_ratio])
	if not (d_null <= EXACT):
		return _fail(("a shape that changes no VERDICT must change nothing at all (%.12f m over the " +
					  "whole flight) — `rcs_aspect` touches the detection and is not in the " +
					  "dynamics, so a shape reaching the mover is a second, unnamed path into the " +
					  "physics") % d_null)
	# ⭐⭐ …AND EVERY SHAPED ARM IS BIT-IDENTICAL TO THE SPHERE UNTIL THE LAST FRAME IT STILL HELD THE
	# LOCK. That is what makes the gauge a function of THE LOSS INSTANT ALONE, and it is why the
	# choice among at-loss quantities (ω, r, t_go, their product) is a choice of UNITS and not of
	# information — the one that ships was chosen on which sentence survives swapping the seeker for
	# a radar, which is the only thing that separates them.
	# ⚠ THE TOOTH IS SITED AT `loss_frame − 1`, NOT AT THE LOSS FRAME. The emitted grid is 16 ticks
	# coarse, so the frame a client SEES the loss on sits up to 15 ticks after the loss itself and
	# the arm has already coasted a few milliseconds (7.4e-8 m at the authored arm, 2.0e-5 m at the
	# ceiling). That divergence is the coast, measured correctly; siting the tooth one frame later
	# would read it as a failure of the identity.
	for tag in ["auth", "top"]:
		var a: Dictionary = _res[tag]
		var k: int = int(a["loss_frame"]) - 1
		var d_pre: float = _max_pos_diff(sph["pos"], a["pos"], k)
		print("S50V_PREFIX F=%.1f vs the sphere, up to the LAST FRAME IT STILL HELD THE LOCK (%d of %d): max|Δpos| = %.12f m" %
			  [a["f"], k, a["pos"].size(), d_pre])
		if not (d_pre <= EXACT):
			return _fail(("F = %.1f must fly the sphere's engagement EXACTLY until it loses the " +
						  "picture (%.12f m over %d frames) — that identity is what makes every " +
						  "at-loss quantity a function of the loss INSTANT alone") %
						 [a["f"], d_pre, k])

	# ⭐ 6. DETERMINISM — the master check (convention 2). Same seed, same slider ⇒ the same flight,
	# the same seeing, and the same GAUGE built out of them.
	var rep: Dictionary = _res["replay"]
	var d_rep: float = _max_pos_diff(aut["pos"], rep["pos"], aut["pos"].size())
	var d_sig: float = _max_abs_diff(aut["sig"], rep["sig"])
	# ⚠⚠ `%.12f` AND NOT `%.12e`. `%e` is NOT a GDScript specifier: an unknown one makes the WHOLE
	# format fail SILENTLY and print the FORMAT STRING itself, on a run that exits 0. Slice 21's bug,
	# reproduced verbatim by slices 25 and 49 — caught only by READING the output of a PASSING run.
	print("S50V_REPLAY max|Δpos| = %.12f m, max|Δsigma| = %.12f m², gauge %.9f vs %.9f deg" %
		  [d_rep, d_sig, aut["gauge"], rep["gauge"]])
	if not (d_rep <= EXACT and d_sig <= EXACT):
		return _fail("replay differs (%.12f m / %.12f m²) — determinism is the master check" %
					 [d_rep, d_sig])
	if not (absf(float(aut["gauge"]) - float(rep["gauge"])) <= EXACT):
		return _fail(("…and the GAUGE must replay too (%.9f vs %.9f deg) — a wire whose telemetry " +
					  "replayed while the LATCH built out of it did not would pass the line above") %
					 [aut["gauge"], rep["gauge"]])

	# ⚠ THE WINDOWED SHOT'S OWN AIM, MEASURED HERE RATHER THAN GUESSED. Convention 14's fourth proof
	# has no headless equivalent, and a shot that lands on the else-branch of the thing the slice
	# added proves nothing about it (the slice-19 rule). ⭐ THE RIGHT FRAME IS INSIDE THE BLIND RUN
	# AND AFTER THE LATCH: that is the only state in which the headline reads "BLIND SINCE x° WAS
	# OWED" with a number in it, which is the sentence the slice ships.
	var shot_t: float = float(aut["t_loss"]) + 0.5 * (float(aut["regain_t"]) - float(aut["t_loss"]))
	var shot_n: int = 16 * int(round(shot_t / (16.0 * _dt)))
	print(("S50V_SHOT   the authored arm is blind from t = %.3f to %.3f s -> aim the windowed shot " +
		   "at step n = %d (t = %.3f s), which is INSIDE it and AFTER the latch") %
		  [aut["t_loss"], aut["regain_t"], shot_n, shot_n * _dt])

	print("S50V PASS  ", _arms.size(), " arms")
	quit(0)
	return true

# --- plumbing ---------------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice50_defensive":
		return "wrong scenario '%s' — run scenarios/slice50_defensive.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER. Without it `seeker_detect_view` takes this wire and slice 46's horizon block
	# draws it — every number TRUE (the horizon is real, the margin is real, the authority is real)
	# and the slice invisible, because none of those lines can say that the horizon is MOVING, that
	# the TARGET is what moved it, or that a lock the missile already had was taken back.
	if not bool(f.get("seeker_aspect_view", false)):
		return ("a slice-50 handshake must ship seeker_aspect_view=true — without it slice 46's " +
				"horizon block takes the wire and prints five true numbers about a stationary " +
				"horizon on a scenario whose whole subject is a horizon that RETREATS")
	# ⚠⚠ AND SLICE 49's MARKER MUST BE **ABSENT**, WHICH IS A CORE FIX AND NOT A CLIENT ONE.
	# `_aspect_view_info` raises on ANY shaped target, so this wire tripped it — and slice 49's HUD
	# keys every line off a RADAR observer, which here does not exist. The block would have rendered
	# against an empty-string observer: "HOLDING IT: 90° broadside / echo 0 m² — 0.0 dB below
	# broadside / range 0.0 km  Pd 0.00  SEEN" over a target turning nose-on at 3 g and seconds from
	# being lost. Six defaulted numbers, no failing test, and the two loudest asserting the exact
	# opposite of the lesson. The core now REQUIRES the observer: half a pair is not a marker.
	if bool(f.get("aspect_view", false)):
		return ("a slice-50 wire must NOT raise slice 49's `aspect_view` — it names a RADAR observer " +
				"this wire does not have, and its HUD would render six DEFAULTED numbers (the " +
				"loudest of them '90° broadside' and 'SEEN') over a target about to vanish")
	# ⚠ AN ASPECT BELONGS TO A TARGET–OBSERVER **PAIR**, and the two ids are NOT interchangeable: the
	# telemetry is keyed on the OBSERVER (the missile) while the prose names the TARGET.
	if str(f.get("seeker_aspect_target", "")) != TID:
		return "the marker must name the shaped TARGET (got '%s', want '%s')" % [str(f.get("seeker_aspect_target", "")), TID]
	if str(f.get("seeker_aspect_observer", "")) != MID:
		return (("the marker must name the MISSILE the aspect is measured from (got '%s', want " +
				"'%s') — it is also the id every telemetry key is prefixed with, and the missile's " +
				"aspect on this target is a DIFFERENT number from a ground radar's at the same " +
				"instant") % [str(f.get("seeker_aspect_observer", "")), MID])
	# ⭐ THIS WIRE IS THE 3-D AIRFRAME VIEW, exactly as slices 46/47/48 are — the HUD's 430 px width
	# budget is a property of that view (slice 49's 390 was the SPATIAL view's altitude labels).
	for k in ["airframe_view", "airframe_6dof", "seeker_detect_view"]:
		if not bool(f.get(k, false)):
			return ("a slice-50 wire must raise %s — it is slice 48's missile (6-DOF, a link budget) " +
					"with the search and the midcourse removed, and slice 46's BUTTON is still this " +
					"slice's own A/B: press it and the horizon goes away and the lock is never lost") % k
	# ⚠ …AND IT MUST NOT RAISE 47's OR 48's, or their HUDs take the wire ahead of nothing: this
	# missile does not search (it holds the lock at launch) and does not fly a midcourse belief.
	for k in ["search_view", "midcourse_view"]:
		if bool(f.get(k, false)):
			return ("a slice-50 wire must NOT raise %s — this missile HAS the lock at launch, and a " +
					"search or a belief beside the target's shape is two mechanisms in one scenario " +
					"(convention 9)") % k
	for k in ["range_axis_m", "pri_axis_us", "terrain_grid"]:
		if f.has(k):
			return "a slice-50 wire must not carry %s — it would flip the client out of the 3-D view" % k
	var fid: Dictionary = f.get("fidelity", {})
	for pair in [["airframe", "six_dof"], ["autopilot", "alpha"], ["guidance", "pn"],
				 ["seeker", "filtered"], ["seeker_axes", "az_el"], ["seeker_detect", "snr"]]:
		if str(fid.get(str(pair[0]), "")) != str(pair[1]):
			return (("fidelity `%s` must be `%s` (got '%s') — these are slice 46/47/48's six keys " +
					"unchanged to the digit, so nothing about the MISSILE moved and any difference " +
					"is the target's") % [str(pair[0]), str(pair[1]), str(fid.get(str(pair[0]), ""))])
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "rcs_fineness":
		return ("exactly ONE knob, the TARGET's `rcs_fineness` (convention 9). `a_lat_mps2` is " +
				"TWO-SIDED — the turn rate sets how fast the nose comes round AND the whole " +
				"intercept triangle, which is the confound the sphere control exists to close; " +
				"`rcs_m2` moves the horizon UNDER the lesson; `detect_pt_w`/`gimbal_fov_deg` are " +
				"slice 46's axis and pairing them with the shape is two mechanisms; `turn_plane` is " +
				"refused BY TYPE (set_param carries one Float64)")
	if str(kn[0].get("target", "")) != TID:
		return "the slider must address the TARGET (`%s`) — the shape is the target's. Got '%s'" % [TID, str(kn[0].get("target", ""))]
	if not (float(kn[0].get("min", -1.0)) == F_SPHERE and float(kn[0].get("max", 0.0)) == F_TOP):
		return (("the slider must span %.0f–%.0f. ⚠ THE CEILING IS **10 AND NOT SLICE 49's 12**, on " +
				 "a measurement: at F >= 11 the missile never re-acquires, flies blind through CPA, " +
				 "and both its miss and its re-acquisition go NON-MONOTONE — a divergence being " +
				 "sampled rather than more of the lesson") % [F_SPHERE, F_TOP])
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR — the gauge is 0.000 deg everywhere below 7 and then " +
				"1.18 -> 5.77 in the top three units, and that flat region must READ as a region: " +
				"slenderness buys nothing until it buys everything")
	return ""

func _reset_scan_accum() -> void:
	_n_frames = 0; _n_det = 0; _n_keys = 0
	_first_det = false; _first_asp = -1.0; _first_sigma = -1.0
	_first_racq = -1.0; _first_r = -1.0
	_min_asp = 1.0e30; _max_sigma = -1.0e30
	_prev_det = -1.0; _latched = false
	_gauge = 0.0; _t_loss = -1.0; _r_loss = -1.0; _racq_loss = -1.0; _loss_frame = -1
	_regained = false; _regain_t = -1.0
	_pos_trace.clear(); _sig_trace.clear(); _racq_trace.clear()

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
	var mp := _ent_pos(f, MID)
	if mp.is_empty():
		return
	var t := float(f.get("t", 0.0))
	_pos_trace.append(mp)
	_n_frames += 1
	# ⚠ ALL SIX KEYS COUNTED TOGETHER, not any-of: the never-stale claim is about the SET, and a wire
	# that dropped one would otherwise pass on the strength of the other five. `seeker_tgo_s` is in
	# the list twice over — it is the slice's own new key AND the only one whose absence is
	# indistinguishable from the lesson's null by any value test.
	if tel.has(MID + ".seeker_detect") and tel.has(MID + ".seeker_tgo_s") \
			and tel.has(MID + ".los_rate") and tel.has(MID + ".los_range") \
			and tel.has(MID + ".seeker_r_acq_m") and tel.has(MID + ".target_aspect_deg"):
		_n_keys += 1
	var det := float(tel.get(MID + ".seeker_detect", -1.0))
	if det >= 0.5:
		_n_det += 1
	var asp := float(tel.get(MID + ".target_aspect_deg", -1.0))
	var sig := float(tel.get(MID + ".rcs_eff_m2", -1.0))
	var racq := float(tel.get(MID + ".seeker_r_acq_m", 0.0))
	var r := float(tel.get(MID + ".los_range", 0.0))
	_sig_trace.append(sig)
	_racq_trace.append(racq)
	if _n_frames == 1:
		_first_det = det >= 0.5
		_first_asp = asp
		_first_sigma = sig
		_first_racq = racq
		_first_r = r
	_min_asp = minf(_min_asp, asp)
	_max_sigma = maxf(_max_sigma, sig)
	# ⭐⭐⭐ THE GAUGE, computed here INDEPENDENTLY of the client's own instrument (convention 11: an
	# independent recompute, not the same call twice). Same definition, different code — the FIRST
	# 1 → 0 edge, and `los_rate · seeker_tgo_s` sampled at it, in degrees.
	# ⚠ `_prev_det` STARTS AT −1 SO FRAME 1 CANNOT BE AN EDGE. A 0.0 seed would make a wire that
	# opens already-blind latch on frame one, sampling the start of the RECORDING as though it were
	# an instant of loss.
	# ⚠ THE **FIRST** EDGE ONLY. Arms in the teachable domain lose the lock once and get it back
	# once; a later edge would be sampled downstream of a blind coast, and everything downstream of a
	# blind coast is a divergence (the same quantity read at RE-ACQUISITION moves 3.1x at half dt,
	# and the CPA on that row moves 20x).
	if _prev_det == 1.0 and det == 0.0 and not _latched:
		_latched = true
		_gauge = rad_to_deg(float(tel.get(MID + ".los_rate", 0.0)) * float(tel.get(MID + ".seeker_tgo_s", 0.0)))
		_t_loss = t
		_r_loss = r
		_racq_loss = racq
		_loss_frame = _n_frames
	elif _prev_det == 0.0 and det == 1.0 and _latched and not _regained:
		_regained = true
		_regain_t = t
	_prev_det = 1.0 if det >= 0.5 else 0.0

func _ent_pos(f: Dictionary, id: String) -> Array:
	for e in f.get("entities", []):
		if str(e.get("id", "")) == id:
			var p: Array = e.get("pos", [])
			if p.size() >= 3:
				return [float(p[0]), float(p[1]), float(p[2])]
	return []

func _max_pos_diff(a: Array, b: Array, n_want: int) -> float:
	var n: int = mini(mini(a.size(), b.size()), n_want)
	if n <= 0:
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
	push_error("S50V FAIL: " + msg)
	print("S50V FAIL: ", msg)
	quit(code)
	return true
