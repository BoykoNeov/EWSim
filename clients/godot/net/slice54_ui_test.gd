extends SceneTree
# Headless UI test for the slice-54 GIVE-UP view routing + HUD — the piece slice54_verify.gd cannot
# reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn smoke-load
# proves the scene loads. Neither exercises the CLIENT routing, the dispatch, or the HUD this slice
# adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14)
# — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐⭐ THE ONE THING THIS FILE EXISTS FOR ABOVE ALL OTHERS: **THE DISPATCH IS IN A DIFFERENT VIEW
# FROM THE FAMILY'S.** A slice-54 wire is a `:cfar` scenario, so `_draw()` goes to `_draw_cfar()` and
# `_spatial_hud_kind()` — the chain every marker since slice 49 has lived in — IS NEVER REACHED.
# The first draft of this slice put the branch there, where it read as "handled first" while being
# unreachable: a claim that looks satisfied and does nothing, which is the exact shape this project
# keeps having to retract. The block now has its own chain, `_cfar_hud_kind()`, and this file asserts
# BOTH — that the give-up branch wins its own view, AND that it is absent from the spatial one.
#
# ⭐⭐ AND THE SECOND REASON: **THE CLIENT MUST NOT REDUCE THE CURVE TO AN ARGMAX.** Gate-0 §2.5.3
# measured that the best cell is a coin flip between neighbours on a nearly flat top (peak NET moves
# 1.9 % across a 4× gate) while the SHAPE is invariant. The headline line therefore names YOUR
# setting's score, never the curve's best, and this file asserts that as a string — a readout that
# printed "best = 3" would give a number the plan proved is not reproducible the authority of a
# measurement.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-54 handshake enters _mode=cfar and records the marker + its observer
#   2. ⭐⭐⭐ THE DISPATCH: `_cfar_hud_kind()` in all three states — AND the spatial chain ignores it
#   3. ⭐⭐⭐ THE HEADLINE NAMES YOUR SETTING, NEVER THE CURVE'S BEST
#   4. ⚠⚠ THE RULE TRAVELS WITH THE SCORE — §2.8.2's binding constraint, asserted as a string
#   5. ⭐⭐⭐ THE DRAG'S OWN SENTENCE — a re-armed score beside a full curve must SAY it re-armed
#   6. ⭐⭐ PRESENCE DECIDES: an EMPTY curve is "no look yet", not a curve of zeros
#   7. ⚠ every key `_draw_giveup_hud_lines` reads is present and scalar, and no default is a LIE
#   8. ONE slider → set_param on the RADAR's `track_drop_looks`
#   9. ⚠ WIDTHS: the block's lines fit the family's 430 px origin
#
# Run:  godot --headless --path clients/godot --script res://net/slice54_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.
#
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const RAD := "radar1"
const TID := "tgt1"

# The CFAR view's right-hand column. The family's origin is `vp.x − 430`; this view has no altitude
# tick labels up the right edge (that is the SPATIAL backdrop, which cost slice 49 the 390 budget),
# so the full 430 is available — but the block is authored to 380 px of plot plus its text, and this
# file measures it rather than trusting the arithmetic.
const HUD_ORIGIN := 430.0
const HUD_ROOM := 420.0

# THE WIRE's OWN COLUMN (seed 101, `docs/plans/slice54.md` §5.3 and the scenario header).
const CURVE := [228, 299, 307, 277, 285, 250, 207, 207, 168, 141, 108, 57, 73, 20, -16, 97]
const ND_AUTH := 3

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_none

func _giveup_tel(n_drop: int, look: int, scored_from: int, curve, alive := true) -> Dictionary:
	var d := {
		RAD + ".snr_db": 14.2,
		RAD + ".pd": 0.71,
		RAD + ".detected": true,
		RAD + ".visible": true,
		RAD + ".track_drop_looks": float(n_drop),
		RAD + ".track_revisit_s": 0.1,
		RAD + ".track_gate_cells": 1.0,
		RAD + ".track_ok_cells": 1.0,
		RAD + ".track_alive": alive,
		RAD + ".track_misses": 0.0,
		RAD + ".track_look": float(look),
		RAD + ".track_scored_from": float(scored_from),
		RAD + ".track_range_m": 41230.5,
		RAD + ".track_rdot": 298.7,
		RAD + ".track_err_m": 62.4,
		RAD + ".track_good_looks": 550.0,
		RAD + ".track_bad_looks": 243.0,
		RAD + ".track_net": 307.0,
	}
	# ⚠⚠ PRESENCE, NOT A SENTINEL. The curve ships only once a look has run; `null` models ABSENT,
	# which is a different state from a curve of zeros and must render differently (slice 50).
	if curve != null:
		var arr: Array = []
		for v in curve:
			arr.append(float(v))
		d[RAD + ".track_sweep_net"] = arr
		d[RAD + ".track_sweep_good"] = arr.duplicate()
		d[RAD + ".track_sweep_bad"] = arr.duplicate()
		d[RAD + ".track_sweep_max"] = float(arr.size())
		d[RAD + ".track_sweep_gate_max"] = 1.0
	return d

func _handshake(giveup: bool) -> Dictionary:
	var h := {
		"name": "slice54_giveup",
		"knobs": [
			{"target": RAD, "key": "track_drop_looks", "min": 1.0, "max": 16.0, "value": 3.0,
			 "label": "PATIENCE — give up after this many missed looks. 1 = no memory; the curve shows the rest"},
		],
		"fidelity": {"cfar": "ca", "propagation": "free_space"},
		"dt_physics": 1.0e-3,
		# ⚠ A slice-54 wire is a `:cfar` scenario: the handshake carries the RANGE AXIS, which is
		# what puts the client in `_mode = "cfar"` in the first place. Without it this fixture would
		# test the give-up block in a view it never renders in.
		"range_axis_m": _range_axis(),
	}
	if giveup:
		h["giveup_view"] = true
		h["giveup_observer"] = RAD
	return h

func _range_axis() -> Array:
	var a: Array = []
	for i in range(64):
		a.append(float(i) * 149.896229)
	return a

func _initialize() -> void:
	print("S54UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_handshake(true))

	# ══ TOOTH 1 — ROUTE ══════════════════════════════════════════════════════════════════════════
	if sb._mode != "cfar":
		return _fail("a slice-54 handshake must enter the CFAR profile view, got '%s' — the whole slice is about threshold crossings in a range profile, and the give-up block draws over that profile" % sb._mode)
	if not sb._giveup_view:
		return _fail("the client must record the `giveup_view` handshake marker")
	if sb._giveup_observer != RAD:
		return _fail("the marker must carry the RADAR whose curve the wire ships (got '%s') — every `track_*` line is keyed off it, so an empty one renders a dozen defaulted numbers on a green run" % sb._giveup_observer)
	print("S54UI_ROUTE  cfar view entered; giveup_view up, observer '%s' recorded" % sb._giveup_observer)

	# ══ TOOTH 2 — ⭐⭐⭐ THE DISPATCH, AND THE VIEW IT IS ACTUALLY IN ═════════════════════════════
	# ⚠⚠ CONVENTION 14's BLIND SPOT, ANSWERED — and answered in the RIGHT VIEW. An `if` inside
	# `_draw` has no headless proof (slice 50's finding); `_cfar_hud_kind()` is a pure function read
	# by BOTH `_draw_cfar` and this file (convention 7: one list, no drift).
	if sb._cfar_hud_kind() != "giveup":
		return _fail("⭐⭐⭐ with the marker up the give-up block must own the CFAR view's column, got '%s'" % sb._cfar_hud_kind())
	_sb_none = _build_sandbox()
	_sb_none._on_scenario(_handshake(false))
	if _sb_none._cfar_hud_kind() != "":
		return _fail("⚠ with NO marker the column must stay empty, got '%s' — every slice-3 CFAR wire draws exactly what it drew before" % _sb_none._cfar_hud_kind())
	# ⚠⚠ AND THE OTHER HALF, WHICH IS THIS FILE'S REASON FOR EXISTING: the SPATIAL chain must NOT
	# claim this marker. The branch was there in the first draft and was unreachable — a slice-54
	# wire never enters the spatial view at all — so it read as handled while doing nothing.
	if sb._spatial_hud_kind() == "giveup":
		return _fail("⭐⭐⭐ the SPATIAL chain must not claim the give-up marker: a slice-54 wire is a `:cfar` scenario, so `_spatial_hud_kind()` is never reached and a branch there is unreachable code that READS as handled. The block's chain is `_cfar_hud_kind()`")
	print("S54UI_DISPATCH marker→'giveup' in the CFAR chain, none→'', and the SPATIAL chain does not claim it")

	# ══ TOOTH 3 — ⭐⭐⭐ THE HEADLINE NAMES YOUR SETTING, NEVER THE CURVE'S BEST ══════════════════
	# The curve's argmax here is n_drop 3 (307) and the fixture's slider is on 3 as well, so a
	# headline that printed the BEST would be indistinguishable. Read it at a setting that is NOT
	# the peak — that is the whole tooth.
	var head_off: String = sb._giveup_headline(_arr(CURVE), 16, 1, 2000)
	if not ("16" in head_off):
		return _fail("the headline must name YOUR setting: at n_drop 16 it reads '%s'" % head_off)
	if "307" in head_off:
		return _fail("⭐⭐⭐ the headline printed the CURVE'S PEAK (+307) while the slider sat on 16: '%s'. Gate-0 §2.5.3 measured the argmax is a coin flip between neighbours on a nearly flat top — a readout that names it gives a number the plan proved is not reproducible the authority of a measurement. The curve is the teaching object; this line says where YOU are on it" % head_off)
	if not ("97" in head_off):
		return _fail("…and it must carry the score AT that setting (+97): '%s'" % head_off)
	var head_pk: String = sb._giveup_headline(_arr(CURVE), ND_AUTH, 1, 2000)
	if not ("307" in head_pk):
		return _fail("at the authored setting the headline must read its own score (+307): '%s'" % head_pk)
	print("S54UI_HEADLINE '%s' / '%s' — YOUR point, not the curve's best" % [head_pk, head_off])

	# ══ TOOTH 4 — ⚠⚠ THE RULE TRAVELS WITH THE SCORE (§2.8.2) ═══════════════════════════════════
	# The COUNT of looks is a JOINT property of the give-up rule, the tracker's GATE and the gauge's
	# BAND: the same physics reads a best patience of 5, 7, 9 or 11 depending on the last two. Only
	# the DIRECTION is physics. A score drawn without them is not reproducible.
	sb._telemetry = _giveup_tel(ND_AUTH, 2000, 1, CURVE)
	for k in ["track_revisit_s", "track_gate_cells", "track_ok_cells"]:
		if not sb._giveup_has(k):
			return _fail("⚠⚠ the HUD must be able to read `%s` — the score is a joint property of the rule, the gate and the band, and a figure without them is not a measurement" % k)
	if absf(sb._giveup_f("track_revisit_s", -1.0) - 0.1) > 1.0e-9:
		return _fail("the HUD must read the revisit off the wire, not assume it")
	print("S54UI_RULE   revisit %.2f s, gate +-%d cells, band %d cells — all read off the wire" %
		  [sb._giveup_f("track_revisit_s", 0.0), int(sb._giveup_f("track_gate_cells", 0.0)),
		   int(sb._giveup_f("track_ok_cells", 0.0))])

	# ══ TOOTH 5 — ⭐⭐⭐ THE DRAG'S OWN SENTENCE ═════════════════════════════════════════════════
	# ⚠⚠ A drag RE-ARMS your score and LEAVES THE CURVE ALONE. Without a line saying so, the user
	# sees a full curve beside a near-zero personal score and reads a broken instrument — slice 52's
	# peak-hold trap, one instrument over. This is the client half of that split.
	var s_fresh: String = sb._giveup_scored_text(1, 2000)
	var s_drag: String = sb._giveup_scored_text(1001, 2000)
	if s_fresh == s_drag:
		return _fail("⭐⭐⭐ a re-armed score must READ differently from one that has run all pass — both say '%s'. The curve survives a drag and your own score does not, and a view that cannot say which is which turns the drag into an apparent fault" % s_fresh)
	if not ("1001" in s_drag):
		return _fail("the re-armed line must name the look it re-armed at: '%s'" % s_drag)
	if not ("1000" in s_drag):
		return _fail("…and how much of the pass this setting actually owns (1000 looks): '%s'" % s_drag)
	print("S54UI_DRAG   fresh: '%s' | after a drag: '%s'" % [s_fresh, s_drag])

	# ══ TOOTH 6 — ⭐⭐ PRESENCE DECIDES ═════════════════════════════════════════════════════════
	# An ABSENT curve (no look yet) is a different state from a curve of zeros, and `.get(k, [])`
	# must not manufacture one. ⚠ A defaulted 16 zeros would draw a flat line through the middle of
	# the panel — a perfectly plausible reading of a rule that breaks even at every patience.
	sb._telemetry = _giveup_tel(ND_AUTH, 0, 1, null)
	if not sb._giveup_curve().is_empty():
		return _fail("⭐⭐ an absent curve must read as EMPTY, not as zeros — a defaulted flat line is a plausible reading of `this rule breaks even everywhere`, which is the worst possible lie for this gauge (slice 50: presence decides)")
	var head_wait: String = sb._giveup_headline([], ND_AUTH, 1, 0)
	if "+0" in head_wait or "0 looks" in head_wait:
		return _fail("…and the headline must say it is WAITING, not print a zero score: '%s'" % head_wait)
	print("S54UI_NULL   no look yet → empty curve, headline '%s'" % head_wait)

	# ══ TOOTH 7 — ⚠ EVERY KEY THE BLOCK READS IS REAL, AND NO DEFAULT IS A LIE ══════════════════
	sb._telemetry = _giveup_tel(ND_AUTH, 2000, 1, CURVE)
	for k in ["track_drop_looks", "track_look", "track_scored_from", "track_revisit_s",
			  "track_gate_cells", "track_ok_cells"]:
		if not sb._telemetry.has(RAD + "." + k):
			return _fail("the fixture must carry `%s` — this tooth is what keeps the block's reads honest" % k)
		var v = sb._telemetry[RAD + "." + k]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return _fail("`%s` must be a scalar on the wire" % k)
	if sb._giveup_curve().size() != 16:
		return _fail("the curve must arrive as a 16-cell Array, got %d" % sb._giveup_curve().size())

	# ══ TOOTH 8 — ONE SLIDER, ON THE RADAR ═════════════════════════════════════════════════════
	# ⚠ THE RADAR IS `radar1`, NOT THE TARGET — the opposite of slice 53, whose slider sat on `tgt1`.
	# The give-up rule belongs to the SENSOR: it is a property of how the radar decides, not of what
	# it is looking at. ⚠⚠ Every telemetry key this HUD reads is ALSO the radar's, so here the two
	# agree — which is exactly why a tooth copied from slice 53 could pass while addressing the
	# wrong entity, and why this one drives the REAL slider rather than calling a handler by name.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 16.0
	sliders[0].value_changed.emit(16.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "track_drop_looks":
			if str(d.get("target", "")) != RAD:
				return _fail("⚠ the slider must address the RADAR (`%s`) — the give-up rule is the sensor's, not the target's. Got '%s'" % [RAD, str(d.get("target", ""))])
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the radar's `track_drop_looks` — got %s" % str(mock.sent))
	print("S54UI_KNOB   one slider → set_param(%s.track_drop_looks)" % RAD)

	# ══ TOOTH 9 — ⚠ WIDTHS ════════════════════════════════════════════════════════════════════
	# A HUD width budget is in PIXELS and belongs to the VIEW (slices 46/49 paid for this). The
	# origin is right-anchored, so no window size rescues an over-wide line.
	var f := ThemeDB.fallback_font
	var lines := [
		sb._giveup_headline(_arr(CURVE), ND_AUTH, 1, 2000),
		s_drag,
		"rule: a look every %.2f s | gate +-%d cells | on-target within %d" % [0.1, 1, 1],
		"net looks on target vs patience 1..%d  (all on THIS pass)" % 16,
		str(sb._giveup_lesson_text(_arr(CURVE))),
	]
	for ln in lines:
		var w := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if w > HUD_ROOM:
			return _fail("⚠ HUD line overruns the %d px column at %d px: '%s'" % [int(HUD_ROOM), int(w), ln])
	print("S54UI_WIDTH  %d lines all inside %d px" % [lines.size(), int(HUD_ROOM)])

	return _pass()

func _arr(a) -> Array:
	var out: Array = []
	for v in a:
		out.append(float(v))
	return out

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here and the PIXEL width
	# tooth would CRASH on it rather than fail. Assign the SAME font `_draw` uses, from the same
	# source, or the tooth measures a different typeface than the one in the photograph.
	sb._font = ThemeDB.fallback_font
	return sb

func _find_all_sliders(node) -> Array:
	var out: Array = []
	if node == null or not (node is Node):
		return out
	for c in node.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_all_sliders(c))
	return out

func _pass() -> bool:
	print("S54UI OK: there is no such thing as the right amount of patience — how long to hold a " +
		"track through a gap is set by how dirty the picture is, and the on-screen half has to " +
		"show the WHOLE CURVE rather than a best setting. ⭐⭐⭐ THE DISPATCH LIVES IN THE CFAR " +
		"VIEW AND NOT THE SPATIAL ONE: the first draft put it in the family's usual chain, where " +
		"it was UNREACHABLE and still read as handled. ⭐⭐ AND THE HEADLINE NAMES YOUR SETTING, " +
		"never the curve's peak — gate-0 measured that peak is a coin flip between neighbours.")
	_teardown()
	quit(0)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_none]:
		if sb != null and sb is Node and is_instance_valid(sb):
			sb.free()

func _fail(msg: String) -> bool:
	push_error("S54UI FAIL: " + msg)
	print("S54UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true
