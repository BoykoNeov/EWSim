extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-53 gate-3 verifier — A TAIL LOBE, and the two ends of one pass.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice53_taillobe.yaml
#   godot --headless --path clients/godot --script res://net/slice53_verify.gd     (exit 0 = pass)
#
# THE LESSON. Which way a target points does not only change how BRIGHT it is — it changes it
# ASYMMETRICALLY. The same aircraft, on the same straight pass, at the same range, is held far
# longer running away than it was ever seen coming in, and no single cross-section number can say
# that.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE, AND IT IS ONE NUMBER: **the INBOUND edge is
# IDENTICAL TO THE BIT at every setting of the slider, while the OUTBOUND edge moves by kilometres.**
# The kernel's lobe is `max(0, −cos θ)²`, identically ZERO on the whole forward hemisphere, and this
# wire's track opens at an aspect of 52.7° — forward of broadside — so at that moment the multiplier
# is exactly 1.0 and no `G` can reach it. That is what makes the gauge an EXACT PAIRED difference
# rather than a difference of two noisy things, and it is why no `rcs_m2` and no `rcs_fineness` can
# imitate it: both are fore/aft symmetric, so they move BOTH ends together.
#
# ⚠⚠ THE GAUGE IS `track_asym_m` AND IT IS QUOTED WITH ITS RULE OR IT IS NOT A MEASUREMENT. The
# metres are a JOINT property of the tail lobe and the TRACKER: at a halved revisit with a matched
# give-up TIME the same physics reads +2191 m more at `G` = 20 (plan §2.14). The SIGN and the
# monotonicity are the target's; the SIZE is the pair's. `track_revisit_s` and `track_drop_looks`
# ship on every frame beside the metres, and this file asserts that they do.
#
# ⚠ AND THE NULL IS NOISE, NOT ZERO. Identical σ on the two legs still means different Swerling-1
# draws, so `G` = 1 reads +583 m on this seed (−658 … +968 m over the 8 gate-0 seeds). The
# attributability bar was fixed in writing before the ladder was flown — max-null × 3 = 2905 m — and
# the authored arm clears it by construction, not by luck. This file asserts the SEPARATION, never
# a zero.
#
# ⭐⭐ THE FIFTH ARM IS A **LIVE DRAG**, AND IT IS THE FIRST GATE-3 PROOF IN THIS PROJECT TO DO ONE.
# `CLAUDE.md` records that no gate-3 proof drags a slider (slice 52) and that a live drag invalidates
# a latch as a Reset does (slice 50). Gate 2's follow-up put the invalidation in the CORE precisely
# because a verifier reads the WIRE and would otherwise read a stale latch as a live measurement —
# so the path exists only if something exercises it, and this is that something.
#
# ⚠⚠ EVERY ARM READS `track_pass_dirty` = TRUE, INCLUDING THE CLEAN ONES, AND THAT IS THIS FILE'S
# OWN CONSTRUCTION RATHER THAN A DEFECT. `reset` RELOADS the YAML — so the gain returns to the
# authored 20 and each arm must re-send its own — and `set_param` marks the tracker dirty
# unconditionally and knob-agnostically, which is the one place the core can notice a knob moving.
# The flag therefore says "a knob moved after this run began", which is TRUE here. What separates
# the drag arm is not the flag: it is that `track_asym_m` is **ABSENT** at the end, because the
# GAIN edge was deleted past closest approach and can never be re-declared. Asserted both ways.
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
# as a test so an edit to either breaks there first). 120000 = 16 × 7500.
# ⚠ AND THE LENGTH IS A MEASUREMENT, NOT A ROUND NUMBER. The latest edge this file reads is declared
# at look 950 (`G` = 50, t = 95.0 s), so 120 s leaves 250 looks of margin against a give-up depth of
# 3 — the censoring check P7a §C made arm-specific, asserted at the arm whose edge is LATEST rather
# than at whichever one is convenient (slice 52's trap).
const STEPS := 120000
const DRAG_AT := 60000            # …and the drag arm splits there: PAST closest approach (t = 50 s)
                                  # and past the gain edge (look 375, t = 37.5 s), so both edges'
                                  # preconditions exist before the knob moves.

# THE SLIDER — the tail-to-nose brightness ratio. FLOOR 1.0 is the lesson's NULL (a fore/aft
# symmetric target, the bracket exactly 1.0); the wire opens at 20.0, mid-lesson; 50.0 is the
# ceiling, +17.0 dB tail-vs-nose and still −19.1 dB below broadside — an ordinary airframe.
const G_NULL := 1.0
const G_AUTH := 20.0
const G_TOP := 50.0

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing in this file touches them).
const RCS_BROADSIDE := 4.0        # m² — the BROADSIDE cross-section (slice 49's sharpened `rcs_m2`)
const REVISIT_S := 0.1            # …and the two halves of the rule the metres are quoted with
const N_DROP := 3

# THE 120 s COLUMN, MEASURED (probe `g3_wire.jl`, and core-pinned in `core/test/test_track.jl`).
# ⚠ EXTERNAL ANCHORS: 6243.9596 m is `docs/plans/slice53.md` §4.2's own printed inbound-gain
# invariant for seed 250, produced by a different program on a different day (convention 11).
const GAIN_M := 6243.9596
const GAIN_LOOK := 375
const LOSS_NULL_M := 6827.07
const LOSS_AUTH_M := 9760.43
const LOSS_TOP_M := 14357.92
const LOSS_TOP_LOOK := 950
const ASYM_NULL_M := 583.11
const ASYM_AUTH_M := 3516.47
const ASYM_TOP_M := 8113.96
# ⚠ THE ATTRIBUTABILITY BAR, FIXED BEFORE THE LADDER WAS FLOWN (plan §0.5 F3): max-null × 3 over the
# 8 gate-0 seeds. The authored arm must clear the NULL by at least this, or the gauge is measuring
# the detector rather than the lobe.
const F3_BAR_M := 2905.0
const EXACT := 1.0e-9
const M_TOL := 1.0                # m — the arms are deterministic; this is a typo guard, not slack

var _client
var _inbox: Array = []
var _dt := 1.0e-3
var _handshaked := false
var _t0 := 0.0
var _t_target := 0.0

var _arms: Array = []
var _idx := -1
var _res: Dictionary = {}
var _dragged := false

# --- per-arm accumulators ----------------------------------------------------------------------
var _n_frames := 0
var _n_keys := 0                  # frames carrying ALL eleven track keys — the never-stale tooth
var _n_rule := 0                  # …and frames carrying the RULE beside them (§2.14)
var _n_asym := 0                  # frames on which `track_asym_m` was PRESENT
var _first_asp := -1.0
var _max_asp := -1.0
var _asp_at_gain := -1.0          # ⭐ the aspect at the look the GAIN edge was declared
var _seen_gain_look := -1
var _prev_range := -1.0
var _turned := false              # did the range ever stop falling? (it must — this is a fly-past)
var _pos_trace: Array = []
var _asym_present_last := false

func _initialize() -> void:
	print("S53V_INIT godot=", Engine.get_version_info().string)
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
	# ⭐⭐ THE DRAG, MID-ARM. `_drain_scan` returns at the split point on the drag arm; the knob moves
	# HERE, between two `step` commands, through the same `set_param` a slider sends — which is the
	# whole point (a hook nothing calls is the same defect as a key nothing reads).
	var arm: Dictionary = _arms[_idx]
	if arm.has("drag_to") and not _dragged:
		_dragged = true
		_client.send({"type": "set_param", "target": TID, "key": "rcs_tail_gain",
					  "value": float(arm["drag_to"])})
		_t_target = float(STEPS) * _dt
		_client.send({"type": "step", "n": STEPS - DRAG_AT})
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
	# ⭐⭐ 1. THE NULL, AND IT IS A CONTROL THAT CANNOT BE SILENT. At `G` = 1 the model is fore/aft
	#    SYMMETRIC — the two legs present the identical σ at equal range — so the gauge reads pure
	#    Swerling-1 fading noise, which on this seed is +583 m and NOT zero. A control that read a
	#    clean zero would mean the detector had been switched off, and the comparison below would be
	#    a tautology instead of a separation.
	_arms.append({"tag": "null", "g": G_NULL})
	# ⭐⭐⭐ 2. THE AUTHORED WIRE — the arm that ships, and the one the showcase opens on.
	_arms.append({"tag": "auth", "g": G_AUTH})
	# ⭐ 3. THE CEILING — asserted MONOTONE against the authored arm, not merely different. The 20→50
	#    interval is the only one that moves all 8 gate-0 seeds, which is what a ceiling of 20 could
	#    not have offered.
	_arms.append({"tag": "top", "g": G_TOP})
	# ⭐ 4. DETERMINISM — same seed, same slider ⇒ the same flight AND the same two edges (convention
	#    2, the master check).
	_arms.append({"tag": "replay", "g": G_AUTH})
	# ⭐⭐ 5. THE LIVE DRAG, PAST CLOSEST APPROACH. Opens at the authored 20 with the gain edge already
	#    declared, then moves to 50 at t = 60 s. The core deletes BOTH edges at the next look and
	#    `:trk_past_cpa` is never cleared, so the inbound edge can never be re-declared — the LOSS
	#    edge comes back (at the NEW setting's value), the GAIN edge does not, and the gauge is gone.
	_arms.append({"tag": "drag", "g": G_AUTH, "drag_to": G_TOP})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	_dragged = false
	# ⚠ `reset` RELOADS THE YAML, so the tail gain returns to the authored 20.0 every arm and each
	# must re-send its own. That is what makes these arms the CLIENT's path — a slider — rather than
	# a set of scenario variants. ⚠ SENT ON EVERY ARM INCLUDING THE AUTHORED ONE, so that arm proves
	# the SLIDER's path to its own value rather than merely inheriting it from the file.
	# ⚠⚠ AND IT IS ALSO WHY EVERY ARM READS `track_pass_dirty` = TRUE — see the file header. The flag
	# is knob-agnostic and time-agnostic by design, so it fires here too; what separates the drag arm
	# is the ABSENT gauge, not the flag.
	_client.send({"type": "reset"})
	_client.send({"type": "set_param", "target": TID, "key": "rcs_tail_gain", "value": float(arm["g"])})
	if arm.has("drag_to"):
		_t_target = float(DRAG_AT) * _dt
		_client.send({"type": "step", "n": DRAG_AT})
	else:
		_t_target = float(STEPS) * _dt
		_client.send({"type": "step", "n": STEPS})

func _finish_arm() -> String:
	var arm: Dictionary = _arms[_idx]
	var tag := str(arm["tag"])
	var tel: Dictionary = _last_tel
	var m := {
		"g": float(arm["g"]), "frames": _n_frames, "keys": _n_keys, "rule": _n_rule,
		"gain": float(tel.get(RAD + ".track_gain_range_m", -1.0)),
		"gain_look": int(float(tel.get(RAD + ".track_gain_look", -1.0))),
		"loss": float(tel.get(RAD + ".track_loss_range_m", -1.0)),
		"loss_look": int(float(tel.get(RAD + ".track_loss_look", -1.0))),
		"asym": float(tel.get(RAD + ".track_asym_m", 0.0)),
		"has_asym": tel.has(RAD + ".track_asym_m"),
		"n_asym": _n_asym,
		"dirty": _wire_bool(tel, RAD + ".track_pass_dirty"),
		"look": int(float(tel.get(RAD + ".track_look", -1.0))),
		"revisit": float(tel.get(RAD + ".track_revisit_s", -1.0)),
		"n_drop": int(float(tel.get(RAD + ".track_drop_looks", -1.0))),
		"first_asp": _first_asp, "max_asp": _max_asp, "asp_at_gain": _asp_at_gain,
		"turned": _turned, "pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S53V_ARM   %-6s G=%5.1f  ->  in %8.2f m @look %3d   out %9.2f m @look %3d   " +
		   "asym %s   aspect %5.1f -> %5.1f deg  looks=%d frames=%d") %
		  [tag, m["g"], m["gain"], m["gain_look"], m["loss"], m["loss_look"],
		   ("%+9.2f m" % m["asym"]) if m["has_asym"] else "  ABSENT ",
		   m["first_asp"], m["max_asp"], m["look"], m["frames"]])

	if not (_n_frames > 7000):
		return "arm %s: the run must produce a full frame history (got %d of ~7500)" % [tag, _n_frames]
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47/48/49): the eleven track keys are KEY-PRESENCE gated
	# on the RADAR's own `track_drop_looks`, so on this wire they ship on EVERY frame. A key that
	# stops emitting makes the HUD's `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test
	# (`docs/CONVENTIONS.md` §14) — and here the loudest such default would be a `track_asym_m` of
	# 0.0, which is the LESSON'S OWN NULL: a perfectly symmetric target, printed over a pass that
	# has produced nothing at all.
	if not (_n_keys == _n_frames):
		return (("arm %s: the ten always-on track keys must ship on EVERY frame (%d of %d) — a key " +
				"that stops emitting reads downstream as a defaulted zero, and on this gauge a " +
				"defaulted zero IS the lesson's null") % [tag, _n_keys, _n_frames])
	# ⚠⚠ AND THE RULE MUST TRAVEL WITH THEM ON EVERY ONE (§2.14). The metres are a joint property of
	# the tail lobe and the tracker, so a frame that carried the number without `revisit_s` and the
	# give-up depth would be a frame a client could quote a non-measurement from.
	if not (_n_rule == _n_frames):
		return ("arm %s: `track_revisit_s` + `track_drop_looks` must ship on EVERY frame (%d of %d) — the metres are a joint property of the lobe and the TRACKER (+2191 m at G = 20 from retuning the tracker alone), so a figure without its rule is not a measurement" % [tag, _n_rule, _n_frames])
	if absf(float(m["revisit"]) - REVISIT_S) > EXACT or int(m["n_drop"]) != N_DROP:
		return ("arm %s: the wire must carry the AUTHORED rule (revisit %.4f s, give up at %d) — every number this file prints was measured under it" % [tag, float(m["revisit"]), int(m["n_drop"])])
	# ⭐⭐ THE PASS MUST ACTUALLY BE A PASS. The tracker's leg is the range rate's SIGN and assumes ONE
	# closest approach (a named approximation); a run that never turned would leave the whole flight
	# on the inbound leg and no outbound edge could exist at all.
	if not _turned:
		return ("arm %s: the range must stop falling inside the window — this is a straight FLY-PAST and the gauge is the difference between its two ENDS, which do not exist without a closest approach" % tag)
	# ⭐⭐ IT MUST START NOSE-ON AND END TAIL-ON, or the rear hemisphere is never swept while
	# detectable and the whole slice has no wire (plan F1/F2). ⚠ This is also the cheap consistency
	# check on `aspect_angle`'s CONVENTION: 0 = nose-on, 180 = tail-on. A vector built the other way
	# round would reflect the sweep about 90° — which was SILENT until this slice, and is exactly the
	# promissory note `frames.jl` left for the moment a tail lobe existed.
	if not (m["first_asp"] < 30.0):
		return ("arm %s: the pass must OPEN nose-on (%.1f deg) — the forward hemisphere is where the lobe is exactly 1.0, so this is the half of the flight the slider cannot touch" % [tag, float(m["first_asp"])])
	if not (m["max_asp"] > 150.0):
		return ("arm %s: the pass must reach TAIL-ON (%.1f deg) — a wire that never sweeps the rear hemisphere while detectable cannot carry this lesson at all, and a stern chase (one aspect, one number) is the reparameterization that would kill it" % [tag, float(m["max_asp"])])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var nul: Dictionary = _res["null"]
	var aut: Dictionary = _res["auth"]
	var top: Dictionary = _res["top"]
	var rep: Dictionary = _res["replay"]
	var drg: Dictionary = _res["drag"]

	# ══ 1. ⭐⭐⭐ THE INBOUND EDGE IS IDENTICAL TO THE BIT AT EVERY SETTING ═══════════════════════
	# This is the whole paired construction, and it is asserted as an EXACT equality rather than a
	# tolerance: the kernel's lobe is identically zero on the forward hemisphere, so at the look the
	# track opens the multiplier is exactly 1.0 and `G` is not in the arithmetic at all.
	print("S53V_PAIRED  in-edge  null %.6f m @look %d | auth %.6f @%d | top %.6f @%d  (aspect there: %.2f deg)" %
		  [nul["gain"], nul["gain_look"], aut["gain"], aut["gain_look"], top["gain"], top["gain_look"],
		   float(nul["asp_at_gain"])])
	for a in [aut, top]:
		if float(a["gain"]) != float(nul["gain"]) or int(a["gain_look"]) != int(nul["gain_look"]):
			return _fail(("⭐⭐⭐ THE INBOUND EDGE MUST NOT MOVE: G=%.0f opened at %.6f m (look %d) " +
						  "against the null's %.6f m (look %d). The lobe is `max(0, −cos θ)²`, " +
						  "identically ZERO forward of broadside, and this track opens at %.1f deg — " +
						  "so no G can reach it, and the gauge below is only an exact PAIRED " +
						  "difference because of that") %
						 [float(a["g"]), float(a["gain"]), int(a["gain_look"]), float(nul["gain"]),
						  int(nul["gain_look"]), float(nul["asp_at_gain"])])
	if not (float(nul["asp_at_gain"]) > 0.0 and float(nul["asp_at_gain"]) < 90.0):
		return _fail(("⭐⭐ …and the REASON must hold: the gain edge is declared at %.2f deg, which " +
					  "must be FORWARD of broadside. Past 90° the slider would move both ends and " +
					  "this stops being a paired gauge") % float(nul["asp_at_gain"]))
	if absf(float(nul["gain"]) - GAIN_M) > M_TOL or int(nul["gain_look"]) != GAIN_LOOK:
		return _fail(("the inbound edge must match the EXTERNAL anchor %.4f m @ look %d (got %.4f @ " +
					  "%d) — that number is `docs/plans/slice53.md` §4.2's own printed invariant for " +
					  "seed 250, produced by a different program on a different day") %
					 [GAIN_M, GAIN_LOOK, float(nul["gain"]), int(nul["gain_look"])])

	# ══ 2. ⭐⭐⭐ THE OUTBOUND EDGE MOVES, MONOTONICALLY, BY KILOMETRES ═══════════════════════════
	print("S53V_LADDER  out-edge null %.2f m @%d | auth %.2f @%d | top %.2f @%d   asym %+.2f | %+.2f | %+.2f m" %
		  [nul["loss"], nul["loss_look"], aut["loss"], aut["loss_look"], top["loss"], top["loss_look"],
		   nul["asym"], aut["asym"], top["asym"]])
	if not (float(nul["loss"]) < float(aut["loss"]) and float(aut["loss"]) < float(top["loss"])):
		return _fail(("⭐⭐⭐ the OUTBOUND edge must rise monotonically with G (%.2f / %.2f / %.2f m) " +
					  "— a non-monotone showcase slider is how `k` (28), `ω_n` (40) and `σ_seek` (25) " +
					  "died on this arc") % [float(nul["loss"]), float(aut["loss"]), float(top["loss"])])
	for pair in [[nul, LOSS_NULL_M, ASYM_NULL_M], [aut, LOSS_AUTH_M, ASYM_AUTH_M],
				 [top, LOSS_TOP_M, ASYM_TOP_M]]:
		var a: Dictionary = pair[0]
		if not bool(a["has_asym"]):
			return _fail("arm %.0f must SHIP `track_asym_m` — both edges exist" % float(a["g"]))
		if absf(float(a["loss"]) - float(pair[1])) > M_TOL:
			return _fail("arm G=%.0f: out-edge %.2f m, measured %.2f" % [float(a["g"]), float(a["loss"]), float(pair[1])])
		if absf(float(a["asym"]) - float(pair[2])) > M_TOL:
			return _fail("arm G=%.0f: asymmetry %.2f m, measured %.2f" % [float(a["g"]), float(a["asym"]), float(pair[2])])
		# ⭐⭐ AND THE GAUGE IS A SUBTRACTION OF TWO WIRE VALUES, NOT A THIRD MEASUREMENT. Convention
		# 13's identity, checked on the wire so no client ever has a reason to recompute it.
		if absf(float(a["asym"]) - (float(a["loss"]) - float(a["gain"]))) > EXACT:
			return _fail(("arm G=%.0f: `track_asym_m` (%.9f) must be exactly out − in (%.9f) — the " +
						  "HUD and this file read ONE quantity computed ONCE, and a third number " +
						  "here would be convention 7's failure with extra steps") %
						 [float(a["g"]), float(a["asym"]), float(a["loss"]) - float(a["gain"])])

	# ══ 3. ⚠ THE NULL IS NOISE, AND THE SEPARATION IS AGAINST A PRE-REGISTERED BAR ══════════════
	# ⚠⚠ NOT "the null is zero". Identical σ on the two legs still means different Swerling-1 draws,
	# so the null is a few hundred metres of EITHER sign, and asserting a zero here would be
	# asserting that the detector had been switched off. The bar was fixed in writing before the
	# ladder was flown (plan §0.5 F3): max-null × 3 over the 8 gate-0 seeds = 2905 m.
	if absf(float(nul["asym"])) < 1.0:
		return _fail(("⚠⚠ the null read %.4f m — essentially zero, which on a Swerling-1 detector " +
					  "means the fading has stopped. A control that CANNOT read non-zero makes the " +
					  "separation below a tautology") % float(nul["asym"]))
	if not (float(aut["asym"]) - float(nul["asym"]) > F3_BAR_M):
		return _fail(("⚠⚠ the AUTHORED arm must clear the null by more than the pre-registered " +
					  "attributability bar (%.2f − %.2f = %.2f m, bar %.0f) — below it the gauge is " +
					  "measuring the detector rather than the lobe, and the seed was chosen on " +
					  "exactly this criterion (seed 53 opens at +1820 m and FAILS it)") %
					 [float(aut["asym"]), float(nul["asym"]),
					  float(aut["asym"]) - float(nul["asym"]), F3_BAR_M])
	print("S53V_NULL    null %+.2f m (fading noise, not zero) → authored %+.2f m: a separation of %.0f m against the pre-registered bar of %.0f" %
		  [nul["asym"], aut["asym"], float(aut["asym"]) - float(nul["asym"]), F3_BAR_M])

	# ══ 4. ⭐ THE FLIGHT IS BYTE-IDENTICAL ACROSS THE WHOLE SLIDER ══════════════════════════════
	# Slice 49's sharpest tooth, one key over: the shape is read by the SEEING and by nothing else,
	# so the slider changes NOTHING about the trajectory and EVERYTHING about what comes back.
	var d_slider := _max_pos_diff(nul["pos"], top["pos"])
	if d_slider != 0.0:
		return _fail(("⭐ the target must fly the IDENTICAL trajectory at every G (max|Δpos| = %s m) " +
					  "— a tail lobe is a property of the SEEING, and a slider that moved the flight " +
					  "would be teaching something else") % _sci(d_slider))
	# ⭐ DETERMINISM (convention 2): same seed, same slider ⇒ the same flight AND the same two edges.
	var d_rep := _max_pos_diff(aut["pos"], rep["pos"])
	if d_rep != 0.0:
		return _fail("⭐ the replay must be bit-identical (max|Δpos| = %s m)" % _sci(d_rep))
	if float(rep["gain"]) != float(aut["gain"]) or float(rep["loss"]) != float(aut["loss"]) \
			or float(rep["asym"]) != float(aut["asym"]) \
			or int(rep["loss_look"]) != int(aut["loss_look"]):
		return _fail(("⭐ …and the two EDGES must replay bit-identically too (in %.9f/%.9f, out " +
					  "%.9f/%.9f) — the trajectory repeating is not the same claim as the SEEING " +
					  "repeating, and this gauge is entirely a property of the seeing") %
					 [float(aut["gain"]), float(rep["gain"]), float(aut["loss"]), float(rep["loss"])])
	print("S53V_IDENT   max|Δpos| = 0 across the whole slider AND on replay; both edges replay to the bit")

	# ══ 5. ⚠ NOT CENSORED, AT THE ARM WHOSE EDGE IS LATEST ═════════════════════════════════════
	# ⚠⚠ ARM-SPECIFIC (slice 52's trap: a probe's "has this drained?" test must be arm-specific or
	# the next capture re-photographs the last one). The window has to outlast the LAST edge by more
	# than the give-up depth, or the "loss" is the run ending rather than the track being given up.
	var margin := int(top["look"]) - int(top["loss_look"])
	if not (margin > 10 * N_DROP):
		return _fail(("⚠ the outbound edge sits %d looks from the end of the window against a give-up " +
					  "depth of %d — too close to distinguish a track being GIVEN UP from the run " +
					  "simply stopping") % [margin, N_DROP])
	if int(top["loss_look"]) != LOSS_TOP_LOOK:
		return _fail("the ceiling arm's edge must be declared at look %d (got %d)" % [LOSS_TOP_LOOK, int(top["loss_look"])])
	print("S53V_WINDOW  the latest edge (G=%.0f) is declared at look %d of %d — %d looks of margin against a give-up depth of %d" %
		  [top["g"], int(top["loss_look"]), int(top["look"]), margin, N_DROP])

	# ══ 6. ⭐⭐ THE LIVE DRAG — THE FIRST GATE-3 PROOF IN THIS PROJECT TO DRAG A SLIDER ═════════
	# ⚠⚠ AND THE SEPARATOR IS **NOT** `track_pass_dirty`. Every arm here reads it true, because
	# `reset` reloads the YAML and each arm re-sends its own gain — see the file header. What the
	# drag changes is that the GAIN edge was deleted PAST closest approach, and `:trk_past_cpa` is
	# never cleared, so it can never be re-declared.
	print("S53V_DRAG    after a drag at t=%.0f s: in-edge %.1f (sentinel −1 = never re-declared), out-edge %.2f @look %d, gauge %s, dirty=%s" %
		  [float(DRAG_AT) * _dt, float(drg["gain"]), float(drg["loss"]), int(drg["loss_look"]),
		   "PRESENT" if bool(drg["has_asym"]) else "ABSENT", str(bool(drg["dirty"]))])
	if bool(drg["has_asym"]):
		return _fail(("⭐⭐ a drag past closest approach must END the pass's measurement: " +
					  "`track_asym_m` is still on the wire at %+.2f m. The inbound half of that " +
					  "difference was declared under a setting that is no longer live, and a " +
					  "headless proof reading it would be green and false") % float(drg["asym"]))
	if float(drg["gain"]) != -1.0 or int(drg["gain_look"]) != -1:
		return _fail(("⭐⭐ …and the inbound edge must be the NOT-YET sentinel rather than a stale " +
					  "range (got %.4f @ look %d). Past CPA it can never be re-declared, which is " +
					  "why the gauge is gone rather than merely refreshed") %
					 [float(drg["gain"]), int(drg["gain_look"])])
	if not bool(drg["dirty"]):
		return _fail("the drag must raise `track_pass_dirty` — only a Reset clears it, because `reset` reloads the scenario and the comp bag with it")
	# ⭐⭐⭐ AND THE SHARPEST HALF: THE **OUTBOUND** EDGE COMES BACK, AT THE NEW SETTING'S OWN VALUE.
	# It is the same 14357.92 m at look 950 the clean G=50 arm declares — so the number the core is
	# refusing to show would have been RIGHT on this particular arm, because this particular knob
	# happens not to move the inbound edge. The tracker is generic and is not told which knob moved
	# (`pt_w`, `pfa` or `rcs_m2` would move both), and an instrument may refuse to show a figure it
	# can no longer stand behind even when it would have been correct. That is the whole argument
	# for the conservatism, and it is checkable here rather than only assertable in a docstring.
	if absf(float(drg["loss"]) - float(top["loss"])) > EXACT or int(drg["loss_look"]) != int(top["loss_look"]):
		return _fail(("⭐⭐⭐ the OUTBOUND edge must be re-declared under the NEW setting and match the " +
					  "clean G=%.0f arm to the bit (%.6f @%d vs %.6f @%d) — that is what makes the " +
					  "refusal above a conservative choice rather than a broken instrument") %
					 [float(top["g"]), float(drg["loss"]), int(drg["loss_look"]),
					  float(top["loss"]), int(top["loss_look"])])
	# ⭐ …AND THE LIVE LINES KEEP RUNNING THROUGH THE DRAG. The latch belongs to the SETTING; the
	# tick's own state belongs to the TICK, and blanking it would make the slider a screen that goes
	# dark when you touch it rather than a teaching instrument.
	if int(drg["look"]) != int(top["look"]):
		return _fail("the drag arm's look counter must keep running (%d vs %d)" % [int(drg["look"]), int(top["look"])])
	if int(drg["n_asym"]) != 0:
		return _fail(("the drag arm must never have shipped a gauge at all (%d frames did) — the " +
					  "loss edge is declared long after the drag, and the gain edge never is") % int(drg["n_asym"]))
	print("S53V_REFUSE  the refused number would have been RIGHT here (the out-edge came back at exactly the clean G=50 value) — and the tracker is generic and does not know that")

	return _pass()

func _pass() -> bool:
	var nul: Dictionary = _res["null"]
	var aut: Dictionary = _res["auth"]
	var top: Dictionary = _res["top"]
	print(("S53V OK: a fleeing target is not the target you saw coming. On ONE straight pass, at " +
		   "revisit %.2f s with the track given up after %d missed looks, this radar first got the " +
		   "aircraft at %.2f km coming in — the SAME %.2f km at every setting of the slider, to the " +
		   "bit, because the tail lobe is identically 1.0 forward of broadside and the track opens " +
		   "at %.1f deg. Going away it was still holding it at %.2f km (null), %.2f km (authored " +
		   "G=%.0f) and %.2f km (ceiling G=%.0f). ⭐⭐⭐ ONE END OF THE PASS IS UNTOUCHABLE AND THE " +
		   "OTHER IS THE SLIDER, which is why no `rcs_m2` and no `rcs_fineness` can imitate this: " +
		   "both are fore/aft SYMMETRIC and move BOTH ends together. ⚠ The null is not zero — it is " +
		   "%+.0f m of Swerling-1 fading noise — and the authored arm clears it by %.0f m against a " +
		   "bar fixed at %.0f before the ladder was flown. ⭐⭐ And a live drag past closest approach " +
		   "ENDS the measurement: the outbound edge is re-declared under the new setting, the " +
		   "inbound one never can be, and the core refuses the difference rather than showing one " +
		   "measured across two configurations.") %
		  [REVISIT_S, N_DROP, float(nul["gain"]) / 1000.0, float(nul["gain"]) / 1000.0,
		   float(nul["asp_at_gain"]), float(nul["loss"]) / 1000.0, float(aut["loss"]) / 1000.0,
		   float(aut["g"]), float(top["loss"]) / 1000.0, float(top["g"]),
		   float(nul["asym"]), float(aut["asym"]) - float(nul["asym"]), F3_BAR_M])
	quit(0)
	return true

# --- handshake + plumbing ----------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	if str(f.get("name", "")) != "slice53_taillobe":
		return "wrong scenario '%s' — run scenarios/slice53_taillobe.yaml" % str(f.get("name", ""))
	# ⭐⭐ THE MARKER, AND WITHOUT IT THIS WIRE IS A SLICE-49 WIRE TO THE CLIENT — which is worse than
	# being an unknown one. It would draw slice 49's block, whose gauge is the longest loss run WHILE
	# CLOSING: a DURATION on the inbound leg, in the same right-anchored column, under a headline
	# that belongs to this slice.
	if not bool(f.get("tail_view", false)):
		return ("a slice-53 handshake must ship tail_view=true — without it the client falls through " +
				"to slice 49's aspect block and prints that slice's gauge in this slice's column")
	# ⚠ THE MARKER IS THE **PAIR**: an asymmetry belongs to a target's rear hemisphere AND a radar's
	# give-up rule, and the two ids are NOT interchangeable — the telemetry is keyed on the OBSERVER
	# while the prose names the TARGET.
	if str(f.get("tail_target", "")) != TID:
		return "the marker must name the tail-lobed TARGET (got '%s', want '%s')" % [str(f.get("tail_target", "")), TID]
	if str(f.get("tail_observer", "")) != RAD:
		return "the marker must name the TRACKING RADAR the pass is measured from (got '%s', want '%s') — it is also the id every telemetry key is prefixed with" % [str(f.get("tail_observer", "")), RAD]
	# ⚠⚠ …AND SLICE 49's MARKER MUST ALSO BE UP, WHICH IS THE OPPOSITE OF SLICE 50's TOOTH. This
	# target carries an `:rcs_fineness`, so `_aspect_view_info` raises on it exactly as on slice 49's
	# wire — and that marker still owns the BUTTON job here (dropping the `free_space ↔ two_ray`
	# toggle, correct for slice 49's own reason). Asserting its ABSENCE would be asserting that this
	# wire has no shape, which is the thing the tail lobe modulates.
	if not bool(f.get("aspect_view", false)):
		return ("a slice-53 wire must ALSO raise aspect_view — its target carries an `rcs_fineness`, " +
				"and that marker keeps the button job (dropping the multipath toggle). The client " +
				"resolves the two in `_spatial_hud_kind()`, which is checked by slice53_ui_test.gd")
	for k in ["search_view", "midcourse_view", "seeker_detect_view", "radome_view", "gimbal_view",
			  "seeker_fov_view", "seeker_aspect_view", "airframe_view", "airframe_6dof"]:
		if bool(f.get(k, false)):
			return ("a slice-53 wire must NOT raise %s — this is a GROUND RADAR watching an aircraft " +
					"fly past, not a missile, and any of those would route the client into another " +
					"slice's view or steal the shared button") % k
	for k in ["range_axis_m", "pri_axis_us", "terrain_grid"]:
		if f.has(k):
			return "a slice-53 wire must not carry %s — it would flip the client out of the spatial elevation view entirely" % k
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("propagation", "")) != "free_space":
		return ("`propagation` must be authored `free_space` and PINNED (got '%s') — slice 2's " +
				"two_ray adds multipath lobing AND a horizon mask, two more ways for a target to " +
				"vanish, on a scenario about a third way (convention 9)") % str(fid.get("propagation", ""))
	var kn: Array = f.get("knobs", [])
	if kn.size() != 1 or str(kn[0].get("key", "")) != "rcs_tail_gain":
		return ("exactly ONE knob, the TARGET's `rcs_tail_gain` (convention 9). ⚠⚠ `rcs_m2` and " +
				"`rcs_fineness` are disqualified by the slice's own theorem — both are fore/aft " +
				"SYMMETRIC, so neither can produce ANY asymmetry and dragging one would move both " +
				"ends together; `revisit_s` and `track_drop_looks` SET the metres, so they are the " +
				"measurement's rule and cannot also be its input")
	if str(kn[0].get("target", "")) != TID:
		return "the slider must address the TARGET (`%s`) — the lobe is the target's, while every telemetry key here is the RADAR's. Got '%s'" % [TID, str(kn[0].get("target", ""))]
	if not (float(kn[0].get("min", -1.0)) == G_NULL and float(kn[0].get("max", 0.0)) == G_TOP):
		return (("the slider must span %.0f–%.0f: the floor is the LESSON'S NULL (a fore/aft " +
				 "symmetric target, the bracket exactly 1.0) and the ceiling was chosen against 20 " +
				 "and against 100 on the STAIRCASE — 20 puts no all-seed-clean drag on the slider at " +
				 "all, and 100 spends its top decile dead on 8 of 8 seeds") % [G_NULL, G_TOP])
	if float(kn[0].get("value", -1.0)) != G_AUTH:
		return "the wire must OPEN at G = %.0f, mid-lesson — it gives two drags that provably move on all 8 gate-0 seeds (20→50, the only all-seed-clean interval, and 20→1, back to the null). Got %.2f" % [G_AUTH, float(kn[0].get("value", -1.0))]
	if bool(kn[0].get("log", false)):
		return ("the slider must be LINEAR, and NOT for slice 49's or slice 52's reason — do not " +
				"copy their wording. The rule is *put the half-effect near the middle of the drag*, " +
				"and which axis does that is a MEASUREMENT: the half-effect of a 1→50 domain sits at " +
				"G = 20.2, which is 39.2 %% of a LINEAR drag but 76.8 %% of a LOG one. Slice 49 " +
				"refused a log axis because its payoff was concentrated at the TOP; this knob's is " +
				"concentrated at the BOTTOM. Opposite reason, same answer")
	return ""

var _last_tel: Dictionary = {}

func _reset_scan_accum() -> void:
	_n_frames = 0; _n_keys = 0; _n_rule = 0; _n_asym = 0
	_first_asp = -1.0; _max_asp = -1.0; _asp_at_gain = -1.0; _seen_gain_look = -1
	_prev_range = -1.0; _turned = false
	_pos_trace.clear(); _last_tel = {}; _asym_present_last = false

func _drain_scan() -> bool:
	while true:
		var f := _take("state")
		if f.is_empty():
			return false
		_scan(f)
		if float(f.get("t", 0.0)) >= _t_target - 1.0e-9:
			return true
	return false

# The eleven always-on track keys. ⚠ COUNTED AS A SET, not any-of: the never-stale claim is about
# the whole family, and a wire that dropped one would otherwise pass on the strength of the rest.
# ⚠⚠ `track_asym_m` IS DELIBERATELY NOT IN IT — its ABSENCE is a state (the pass has not finished),
# and 0.0 is the lesson's own null, so a "must always be present" tooth on it would assert the
# opposite of the rule the core is built on.
const TRACK_KEYS := ["track_alive", "track_closing", "track_misses", "track_look",
					 "track_gain_range_m", "track_gain_look", "track_loss_range_m",
					 "track_loss_look", "track_pass_dirty"]
const ASPECT_KEYS := ["target_aspect_deg", "rcs_eff_m2", "rcs_loss_db", "target_range_m"]

func _scan(f: Dictionary) -> void:
	var tel: Dictionary = f.get("telemetry", {})
	var tp := _target_pos(f)
	if tp.is_empty():
		return
	_pos_trace.append(tp)
	_n_frames += 1
	_last_tel = tel
	var all_keys := true
	for k in TRACK_KEYS:
		if not tel.has(RAD + "." + k):
			all_keys = false
	for k in ASPECT_KEYS:
		if not tel.has(RAD + "." + k):
			all_keys = false
	if all_keys:
		_n_keys += 1
	# ⚠⚠ THE RULE, COUNTED SEPARATELY FROM THE NUMBERS (§2.14). Two counters rather than one, because
	# "the metres shipped" and "the rule shipped with them" are two claims and a single counter would
	# let either cover for the other.
	if tel.has(RAD + ".track_revisit_s") and tel.has(RAD + ".track_drop_looks"):
		_n_rule += 1
	_asym_present_last = tel.has(RAD + ".track_asym_m")
	if _asym_present_last:
		_n_asym += 1
	var asp := float(tel.get(RAD + ".target_aspect_deg", -1.0))
	if _n_frames == 1:
		_first_asp = asp
	_max_asp = maxf(_max_asp, asp)
	# ⭐ THE ASPECT AT THE LOOK THE GAIN EDGE WAS DECLARED — sampled on the TRANSITION, because the
	# edge is latched and the aspect is not. It is the whole argument for why that edge cannot move.
	var gl := int(float(tel.get(RAD + ".track_gain_look", -1.0)))
	if gl > 0 and gl != _seen_gain_look:
		_seen_gain_look = gl
		_asp_at_gain = asp
	# THE PASS — the range must stop falling, or there are no two ends to take a difference of.
	var r := float(tel.get(RAD + ".target_range_m", 0.0))
	if _prev_range > 0.0 and r > _prev_range:
		_turned = true
	_prev_range = r

func _sci(v: float) -> String:
	# ⚠⚠ GDScript's `%` HAS NO `%e` AND NO `%g`, so a near-zero residual has to be rendered by hand or
	# it is unprintable: `%.3f` of 1e-16 is "0.000", which reads as a PASS inside a FAILURE message.
	if v == 0.0:
		return "0"
	var a := absf(v)
	if a >= 0.01 and a < 1.0e6:
		return "%.6f" % v
	var ex := int(floor(log(a) / log(10.0)))
	return "%.3fe%d" % [v / pow(10.0, ex), ex]

func _wire_bool(tel: Dictionary, k: String) -> bool:
	# `track_pass_dirty` ships as a JSON bool; be tolerant of a numeric 0/1 without ever defaulting
	# to TRUE on a missing key (which would silently turn a clean pass into a refused one).
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
	push_error("S53V FAIL: " + msg)
	print("S53V FAIL: ", msg)
	quit(code)
	return true
