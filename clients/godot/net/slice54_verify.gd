extends SceneTree
# ─────────────────────────────────────────────────────────────────────────────────────────────
# Headless slice-54 gate-3 verifier — THE GIVE-UP RULE, and the curve behind the slider.
# Drives the REAL Julia server through SimClient.gd (the same protocol code Sandbox.tscn renders off).
#
#   & tools/julia.ps1 --project=core tools/server.jl scenarios/slice54_giveup.yaml
#   godot --headless --path clients/godot --script res://net/slice54_verify.gd     (exit 0 = pass)
#
# THE LESSON. There is no such thing as the right amount of patience. How long to hold a track
# through a gap is set by how dirty your picture is — and the same rule that saves a fading target
# on a clean picture will marry you to a noise blip on a dirty one.
#
# ⭐⭐⭐ THE ASSERTION THIS FILE EXISTS TO MAKE, AND IT IS THE MIRROR OF SLICE 53's: **the CURVE is
# identical to the bit at every position of the slider, while YOUR POINT ON IT moves.** The 16
# shadow arms are scored on the SAME picture the authored track sees, and none of them reads
# `track_drop_looks` — so the slider selects which arm is yours and can move nothing else. That is
# what makes the curve a PAIRED comparison (identical draws) rather than sixteen separate flights,
# and it is why one 200 s pass says what the gate-0 ladder needed six seeds to say.
#
# ⚠⚠ THE SCORE IS QUOTED WITH ITS RULE OR IT IS NOT A MEASUREMENT. Gate-0 §2.8.2 measured that the
# COUNT of looks is a JOINT property of the give-up rule, the tracker's GATE and the gauge's BAND:
# the same physics reads a best patience of 5, 7, 9 or 11 depending on two constants that are not
# physics. THE DIRECTION IS PHYSICS; THE COUNT IS NOT. `track_revisit_s`, `track_gate_cells` and
# `track_ok_cells` ship on every frame beside the score, and this file asserts that they do.
#
# ⚠⚠ AND THIS FILE NEVER ASSERTS AN ARGMAX AS THE LESSON. Gate-0 §2.5.3 measured that the best cell
# is a coin flip between neighbours on a nearly flat top (peak NET moves 1.9 % across a 4× gate)
# while the SHAPE is invariant. What is asserted is the SHAPE — it rises from `n_drop` = 1, it peaks
# in the interior, and it falls by `n_drop` = 16 — plus the exact per-cell column as a determinism
# check. The argmax appears only inside that exact column, never as a standalone claim.
#
# ⭐⭐ THE FIFTH ARM IS A LIVE DRAG, and it proves the split the view depends on: a drag RE-ARMS
# your own score and LEAVES THE CURVE ALONE. The sweep is not a measurement OF your setting, it is
# the curve your setting indexes into — so `track_scored_from` jumps while `track_sweep_net` keeps
# accumulating. Slice 53 established that a gate-3 proof MUST drag once a latch lives on the wire;
# here the drag also proves that something does NOT reset, which is the harder half.
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
# SILENTLY, with no output at all (slice 31 lost an hour to exactly this). 200000 = 16 × 12500, and
# 200 s is the whole authored pass: the target runs 20 km → 80 km and the fade is the lesson.
const STEPS := 200000
const DRAG_AT := 100000           # …and the drag arm splits at t = 100 s, half way out, with the
                                  # curve already well populated so "it kept accumulating" is a
                                  # claim about a real number and not about a pair of zeros.

# THE SLIDER — the give-up rule, a COUNT OF CONSECUTIVE MISSED LOOKS. FLOOR 1 is a detector with no
# memory at all (the lesson's null); the wire opens at 3, its measured peak; 16 is the ceiling and
# the sweep's width, past the peak by a factor of five.
const ND_HASTY := 1
const ND_AUTH := 3
const ND_PATIENT := 16

# THE AUTHORED WIRE, asserted unchanged on every arm (nothing here touches them).
const REVISIT_S := 0.1
const OK_CELLS := 1
const GATE_CELLS := 1             # ⭐ the PRE-REGISTERED rule |rdot|·revisit_s/Δr = 300·0.1/149.896
                                  #   = 0.20 → 1 cell (plan §2.5.1), EVALUATED by the core per look
const SWEEP_N := 16

# ⚠ EXTERNAL ANCHOR (convention 11): this column is `docs/plans/slice54.md` §5.3's own printed curve
# for seed 101 and the header table of `scenarios/slice54_giveup.yaml`, produced by a different
# program on a different day. If the wire and the doc ever disagree, THIS is what catches it — which
# is the failure the previous slice's last commit is named after.
const CURVE := [228, 299, 307, 277, 285, 250, 207, 207, 168, 141, 108, 57, 73, 20, -16, 97]
const PEAK_AT := 3                # …the argmax of that exact column, asserted only WITH it

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
var _last_tel: Dictionary = {}

# --- per-arm accumulators ----------------------------------------------------------------------
var _n_frames := 0
var _n_keys := 0                  # frames carrying the whole always-on track family
var _n_rule := 0                  # …and frames carrying the RULE beside them (§2.8.2)
var _n_curve := 0                 # …and frames carrying a full-length curve
var _gate_seen: Array = []        # every distinct `track_gate_cells` the arm reported
var _sweep_at_drag: Array = []    # the curve at the split point, on the drag arm
var _scored_at_drag := -1
var _pos_trace: Array = []

func _initialize() -> void:
	print("S54V_INIT godot=", Engine.get_version_info().string)
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
	# ⭐⭐ THE DRAG, MID-ARM — through the same `set_param` a slider sends, between two `step`s.
	var arm: Dictionary = _arms[_idx]
	if arm.has("drag_to") and not _dragged:
		_dragged = true
		# Photograph the curve and the scoring window BEFORE the knob moves, so "the curve survived"
		# is a comparison against a real column rather than an assertion about the end state alone.
		_sweep_at_drag = _curve_of(_last_tel)
		_scored_at_drag = int(float(_last_tel.get(RAD + ".track_scored_from", -1.0)))
		_client.send({"type": "set_param", "target": RAD, "key": "track_drop_looks",
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
	# ⭐⭐⭐ 1. THE AUTHORED WIRE — the arm that ships and the one the showcase opens on. Its exact
	#    16-cell column is asserted against the plan's own printed numbers.
	_arms.append({"tag": "auth", "nd": ND_AUTH})
	# ⭐⭐ 2. NO MEMORY AT ALL — give up on the first missed look. The lesson's null, and a REAL
	#    setting rather than a degenerate one: on a clean picture it is never wrong, it is just blind
	#    a lot. Its own score must be the curve's FIRST cell.
	_arms.append({"tag": "hasty", "nd": ND_HASTY})
	# ⭐⭐ 3. PATIENCE PAST ITS WORTH — and this is the half of the lesson that is easy to miss. Its
	#    score must be the curve's LAST cell, and must be WORSE than the authored arm's.
	_arms.append({"tag": "patient", "nd": ND_PATIENT})
	# ⭐ 4. DETERMINISM — same seed, same slider ⇒ the same flight and the same curve (convention 2).
	_arms.append({"tag": "replay", "nd": ND_AUTH})
	# ⭐⭐ 5. THE LIVE DRAG. Opens at the authored 3, moves to 16 half way out. YOUR score re-arms
	#    (`track_scored_from` jumps to the drag's look); THE CURVE DOES NOT — it keeps accumulating,
	#    because it is not a measurement of your setting.
	_arms.append({"tag": "drag", "nd": ND_AUTH, "drag_to": ND_PATIENT})

func _launch_arm() -> void:
	_idx += 1
	var arm: Dictionary = _arms[_idx]
	_reset_scan_accum()
	_inbox.clear()
	_dragged = false
	# ⚠ `reset` RELOADS THE YAML, so `track_drop_looks` returns to the authored 3 every arm and each
	# must re-send its own. That is what makes these arms the CLIENT's path — a slider — rather than
	# a set of scenario variants. ⚠ SENT ON EVERY ARM INCLUDING THE AUTHORED ONE, so that arm proves
	# the SLIDER's path to its own value rather than merely inheriting it from the file.
	_client.send({"type": "reset"})
	_client.send({"type": "set_param", "target": RAD, "key": "track_drop_looks",
				  "value": float(arm["nd"])})
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
	var curve := _curve_of(tel)
	var nd := int(float(tel.get(RAD + ".track_drop_looks", -1.0)))
	var m := {
		"nd": nd, "frames": _n_frames, "keys": _n_keys, "rule": _n_rule, "n_curve": _n_curve,
		"curve": curve,
		"net": float(tel.get(RAD + ".track_net", 0.0)),
		"good": float(tel.get(RAD + ".track_good_looks", 0.0)),
		"bad": float(tel.get(RAD + ".track_bad_looks", 0.0)),
		"look": int(float(tel.get(RAD + ".track_look", -1.0))),
		"scored_from": int(float(tel.get(RAD + ".track_scored_from", -1.0))),
		"revisit": float(tel.get(RAD + ".track_revisit_s", -1.0)),
		"ok_cells": int(float(tel.get(RAD + ".track_ok_cells", -1.0))),
		"gate_max": int(float(tel.get(RAD + ".track_sweep_gate_max", -1.0))),
		"gates": _gate_seen.duplicate(),
		"pos": _pos_trace.duplicate(true),
	}
	_res[tag] = m
	print(("S54V_ARM   %-8s n_drop=%2d  ->  your net %+5d (good %d bad %d)   " +
		   "curve[%d] %+5d   looks=%d scored_from=%d frames=%d") %
		  [tag, nd, int(m["net"]), int(m["good"]), int(m["bad"]),
		   nd, (int(curve[nd - 1]) if (nd >= 1 and nd <= curve.size()) else 0),
		   m["look"], m["scored_from"], m["frames"]])

	if not (_n_frames > 12000):
		return "arm %s: the run must produce a full frame history (got %d of ~12500)" % [tag, _n_frames]
	# ⭐ THE NEVER-STALE DISCIPLINE (34/38/46/47/48/49/53): the track family is KEY-PRESENCE gated on
	# the radar's own `track_drop_looks`, so on this wire it ships on EVERY frame. A key that stops
	# emitting makes the HUD's `.get(k, 0.0)` print a DEFAULTED ZERO as a passed test
	# (`docs/CONVENTIONS.md` §14) — and a defaulted net of 0 reads as "the rule broke even", which is
	# a perfectly plausible reading of this gauge and therefore the worst possible default.
	if not (_n_keys == _n_frames):
		return ("arm %s: the always-on track keys must ship on EVERY frame (%d of %d) — a key that stops emitting reads downstream as a defaulted zero, and a defaulted net of 0 reads as `the rule broke even`" % [tag, _n_keys, _n_frames])
	# ⚠⚠ AND THE RULE MUST TRAVEL WITH THEM ON EVERY ONE (§2.8.2).
	if not (_n_rule == _n_frames):
		return ("arm %s: `track_revisit_s` + `track_gate_cells` + `track_ok_cells` must ship on EVERY frame (%d of %d) — the count of looks is a joint property of the rule, the gate and the band (the same physics reads 5, 7, 9 or 11 depending on the last two), so a score without them is not a measurement" % [tag, _n_rule, _n_frames])
	if not (_n_curve == _n_frames):
		return ("arm %s: the CURVE must ship on every frame (%d of %d) — it is the teaching object, and a client that had to wait for it would draw an argmax off a partial column" % [tag, _n_curve, _n_frames])
	if absf(float(m["revisit"]) - REVISIT_S) > 1.0e-9 or int(m["ok_cells"]) != OK_CELLS:
		return ("arm %s: the wire must carry the AUTHORED rule (revisit %.4f s, on-target band %d cells) — every number this file prints was measured under it" % [tag, float(m["revisit"]), int(m["ok_cells"])])
	if int(m["nd"]) != int(arm["nd"]) and not arm.has("drag_to"):
		return "arm %s: the slider did not take (asked %d, wire says %d)" % [tag, int(arm["nd"]), int(m["nd"])]
	# ⭐⭐⭐ THE PRE-REGISTERED GATE, ASSERTED AS THE ONLY VALUE EVER SEEN. Plan §2.5.1 ruled the gate
	# to ±1 cell by a rule fixed BEFORE the probes flew, and §5.2 re-derived it on this wire rather
	# than inheriting it. If the core ever reports anything else here, the shipped gate is not the
	# pre-registered one and every number in the plan is quoted under the wrong rule.
	if not (_gate_seen.size() == 1 and int(_gate_seen[0]) == GATE_CELLS):
		return ("arm %s: the tracker's gate must be the pre-registered %d cell at every look (saw %s) — |rdot|*revisit/dr = 300*0.1/149.896 = 0.20 -> 1, and the core evaluates that per look rather than trusting the arithmetic" % [tag, GATE_CELLS, str(_gate_seen)])
	# ⚠ …and the SWEEP's own widest gate, which includes the SEDUCED arms whose rate estimates run up
	# after a capture. If the cap ever binds, the gate stops being the pre-registered rule.
	if not (int(m["gate_max"]) == GATE_CELLS):
		return ("arm %s: the sweep's widest gate must also be %d cell (saw %d) — a seduced arm that had to widen its window would mean the cap is binding somewhere in the showcase" % [tag, GATE_CELLS, int(m["gate_max"])])
	if not (curve.size() == SWEEP_N):
		return "arm %s: the curve must carry %d cells (got %d)" % [tag, SWEEP_N, curve.size()]
	# ⭐⭐ YOUR SCORE IS YOUR POINT ON THE CURVE — the identity the whole view rests on. If these ever
	# disagreed, the slider and the curve would be describing different trackers and the block would
	# be inviting a comparison that does not hold.
	if not arm.has("drag_to"):
		if absf(float(m["net"]) - float(curve[nd - 1])) > 1.0e-9:
			return ("arm %s: your own score (%+d) must BE the curve's cell at your setting (%+d) — the slider selects an arm of the sweep, it does not run a different tracker" % [tag, int(m["net"]), int(curve[nd - 1])])
	return ""

# --- the verdict ------------------------------------------------------------------------------

func _verdict() -> bool:
	var auth: Dictionary = _res["auth"]
	var hasty: Dictionary = _res["hasty"]
	var patient: Dictionary = _res["patient"]
	var replay: Dictionary = _res["replay"]
	var drag: Dictionary = _res["drag"]
	var c: Array = auth["curve"]

	# ⭐⭐⭐ 1. THE HEADLINE: THE CURVE IS IDENTICAL TO THE BIT AT EVERY SLIDER POSITION. The 16 shadow
	# arms are scored on the same picture and none of them reads `track_drop_looks`, so the slider
	# can move which arm is YOURS and nothing else. This is what makes the curve a PAIRED comparison
	# — the mirror of slice 53's invariant inbound edge, and the reason one pass replaces sixteen.
	for tag in ["hasty", "patient", "replay"]:
		var o: Array = _res[tag]["curve"]
		for i in range(SWEEP_N):
			if int(o[i]) != int(c[i]):
				return _fail(("the CURVE must be identical at every slider position: arm %s cell %d reads %+d against the authored arm's %+d. The sweep is scored on the same picture and reads no slider — if it moves, the arms are not a paired comparison and the block invites a comparison that does not hold" % [tag, i + 1, int(o[i]), int(c[i])]))

	# ⭐⭐ 2. THE EXACT COLUMN, against the plan's own printed numbers (convention 11: an EXTERNAL
	# anchor, a different program on a different day). This is also the determinism check.
	for i in range(SWEEP_N):
		if int(c[i]) != int(CURVE[i]):
			return _fail(("the curve must match the plan's printed column for seed 101: cell %d reads %+d, `docs/plans/slice54.md` §5.3 and the scenario header both say %+d. A wire that disagrees with its own documentation is the exact failure the previous slice's last commit is named after" % [i + 1, int(c[i]), int(CURVE[i])]))
	if int(_argmax(c)) != PEAK_AT:
		return _fail("the authored column's peak must sit at n_drop %d (got %d)" % [PEAK_AT, int(_argmax(c))])

	# ⭐⭐⭐ 3. THE SHAPE — WHICH IS THE LESSON, AND IS ASSERTED AS A SHAPE. It RISES from no memory at
	# all, it PEAKS in the interior, and it FALLS by the ceiling. ⚠ The argmax is NOT asserted on its
	# own anywhere: gate-0 §2.5.3 measured it is a coin flip between neighbours on a nearly flat top.
	if not (int(_argmax(c)) >= 2 and int(_argmax(c)) <= SWEEP_N - 1):
		return _fail("the curve must peak in the INTERIOR — a peak at either end is slice 48's monotone shape and teaches that a knob has a right answer at its endpoint")
	if not (float(c[0]) < float(c[_argmax(c) - 1])):
		return _fail("patience must BUY something: net at n_drop 1 (%+d) must be below the peak (%+d)" % [int(c[0]), int(c[_argmax(c) - 1])])
	if not (float(c[SWEEP_N - 1]) < float(c[_argmax(c) - 1])):
		return _fail("patience must COST something: net at n_drop %d (%+d) must be below the peak (%+d) — without the fall this is a monotone knob, not a design lesson" % [SWEEP_N, int(c[SWEEP_N - 1]), int(c[_argmax(c) - 1])])

	# ⭐⭐ 4. THE THREE ARMS ARE THE THREE POINTS OF THAT SHAPE, read off the slider rather than the
	# curve — so the slider is proved to select a REAL track and not merely an index.
	if not (float(hasty["net"]) < float(auth["net"])):
		return _fail("no memory at all (%+d) must score WORSE than the authored rule (%+d)" % [int(hasty["net"]), int(auth["net"])])
	if not (float(patient["net"]) < float(auth["net"])):
		return _fail("patience past its worth (%+d) must score WORSE than the authored rule (%+d) — this is the half of the lesson a monotone knob would hide" % [int(patient["net"]), int(auth["net"])])
	# …and being WRONG is what patience buys: the patient arm must hold more wrong looks than the
	# hasty one. ⚠ Scored on POSITION, never on duration (gate-0 F3).
	if not (float(patient["bad"]) > float(hasty["bad"])):
		return _fail("the patient rule must spend MORE looks in the wrong place (%d) than the hasty one (%d) — a dropped track re-opens on the loudest cell in the picture, and that is the cost patience buys" % [int(patient["bad"]), int(hasty["bad"])])

	# ⭐ 5. DETERMINISM (convention 2, the master check).
	if _max_pos_diff(auth["pos"], replay["pos"]) > 0.0:
		return _fail("same seed + same slider must replay bit-identically (max pos diff %s m)" % _sci(_max_pos_diff(auth["pos"], replay["pos"])))
	if absf(float(auth["net"]) - float(replay["net"])) > 1.0e-9:
		return _fail("same seed + same slider must give the same score (%+d vs %+d)" % [int(auth["net"]), int(replay["net"])])

	# ⭐⭐⭐ 6. THE DRAG: YOUR SCORE RE-ARMS, THE CURVE DOES NOT. This is the split the view depends on,
	# and it is the harder half of slice 53's rule — that file proved a drag INVALIDATES a latch;
	# this one must prove that something deliberately SURVIVES one.
	if not (int(drag["scored_from"]) > 1):
		return _fail("a live drag must RE-ARM your own score — `track_scored_from` still reads %d, so the number after the drag is a mixture of two settings reported as one measurement (slice 52's peak-hold trap)" % int(drag["scored_from"]))
	if not (int(drag["scored_from"]) > int(_scored_at_drag)):
		return _fail("`track_scored_from` must move at the drag (was %d, still %d)" % [int(_scored_at_drag), int(drag["scored_from"])])
	if _sweep_at_drag.size() != SWEEP_N:
		return _fail("the curve must already be populated at the drag point (got %d cells)" % _sweep_at_drag.size())
	var grew := 0
	for i in range(SWEEP_N):
		if int(drag["curve"][i]) != int(_sweep_at_drag[i]):
			grew += 1
	if grew == 0:
		return _fail("the CURVE must keep accumulating through a drag — it is not a measurement of your setting, it is the curve your setting indexes into, and blanking it would erase the thing the user is reading")
	# …and having survived, it must still be the SAME curve the un-dragged arms produced: the drag
	# changed which arm is yours, not the picture.
	for i in range(SWEEP_N):
		if int(drag["curve"][i]) != int(c[i]):
			return _fail("the curve after a drag must equal the un-dragged arms' curve at cell %d (%+d vs %+d) — the drag selects an arm, it does not re-fly the pass" % [i + 1, int(drag["curve"][i]), int(c[i])])

	print("S54V_CURVE ", _curve_str(c))
	print(("S54V_SHAPE rises %+d -> %+d (peak at n_drop %d), falls to %+d by %d " +
		   "| holding %dx too long costs %d%% of the peak") %
		  [int(c[0]), int(c[PEAK_AT - 1]), PEAK_AT, int(c[SWEEP_N - 1]), SWEEP_N,
		   int(SWEEP_N / PEAK_AT),
		   int(round(100.0 * (1.0 - float(c[SWEEP_N - 1]) / float(c[PEAK_AT - 1]))))])
	print("S54V_RULE  a look every %.2f s | gate +-%d cells | on-target within %d cells" %
		  [REVISIT_S, GATE_CELLS, OK_CELLS])
	print("S54V PASS")
	quit(0)
	return true

# --- handshake / scan --------------------------------------------------------------------------

func _check_handshake(f: Dictionary) -> String:
	# ⭐⭐ THE VIEW MARKER, gated in the CORE on the AUTHOR's `track_sweep_max` and never on the
	# slider's value — this slice's slider is dragged to its own null as the lesson, and a
	# value-gated marker would go dark on exactly that arm (slice 53's rule, this instrument).
	if not bool(f.get("giveup_view", false)):
		return "handshake must raise `giveup_view` — without it the client draws no curve and the whole slider is a number with no context"
	if str(f.get("giveup_observer", "")) != RAD:
		return "handshake must name the radar whose curve the wire carries (got '%s')" % str(f.get("giveup_observer", ""))
	var knobs: Array = f.get("knobs", [])
	var found := false
	for k in knobs:
		if str(k.get("key", "")) == "track_drop_looks":
			found = true
	if not found:
		return "the wire must declare `track_drop_looks` as a knob — `set_param` refuses anything else, so an undeclared slider is a slider that cannot move"
	return ""

const TRACK_KEYS := ["track_alive", "track_misses", "track_look", "track_scored_from",
					 "track_range_m", "track_rdot", "track_net", "track_good_looks",
					 "track_bad_looks", "track_drop_looks", "track_err_m"]
const RULE_KEYS := ["track_revisit_s", "track_gate_cells", "track_ok_cells"]

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
	if all_keys:
		_n_keys += 1
	# ⚠⚠ THE RULE, COUNTED SEPARATELY FROM THE NUMBERS. Two counters rather than one, because "the
	# score shipped" and "the rule shipped with it" are two claims and one counter would let either
	# cover for the other.
	var all_rule := true
	for k in RULE_KEYS:
		if not tel.has(RAD + "." + k):
			all_rule = false
	if all_rule:
		_n_rule += 1
	if _curve_of(tel).size() == SWEEP_N:
		_n_curve += 1
	var g := int(float(tel.get(RAD + ".track_gate_cells", -1.0)))
	if g > 0 and not _gate_seen.has(g):
		_gate_seen.append(g)

func _curve_of(tel: Dictionary) -> Array:
	var v = tel.get(RAD + ".track_sweep_net", null)
	return (v as Array) if v is Array else []

func _curve_str(c: Array) -> String:
	var s := ""
	for v in c:
		s += "%+d " % int(v)
	return s

func _argmax(c: Array) -> int:
	var bi := 0
	for i in range(c.size()):
		if float(c[i]) > float(c[bi]):
			bi = i
	return bi + 1

func _reset_scan_accum() -> void:
	_n_frames = 0
	_n_keys = 0
	_n_rule = 0
	_n_curve = 0
	_gate_seen = []
	_pos_trace = []
	_last_tel = {}

func _drain_scan() -> bool:
	while true:
		var f := _take("state")
		if f.is_empty():
			return false
		_scan(f)
		if float(f.get("t", 0.0)) >= _t_target - 1.0e-9:
			return true
	return false

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
	push_error("S54V FAIL: " + msg)
	print("S54V FAIL: ", msg)
	quit(code)
	return true
