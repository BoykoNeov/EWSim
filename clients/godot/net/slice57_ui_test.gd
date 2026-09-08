extends SceneTree
# Headless UI test for the slice-57 ASPECT wire's HUD — and it is a SHORT file on purpose, because
# ⭐⭐⭐ SLICE 57 SHIPS NO NEW CLIENT BRANCH AND NO NEW MARKER. Its wire IS slice 55's with the
# picture error tilted and the window's SHAPE on a slider, so it raises `fanbeam_view` and takes the
# same HUD. A marker per FILE would make markers name files instead of capabilities.
#
# ⚠⚠ SO WHAT IS THIS FILE FOR? Because the slider makes the SHAPE move over a 80x range at run time,
# and slice 55's HUD was written against ONE authored pair. Two of its lines were literally true on
# that pair and FALSE on this wire, and this file exists to keep them derived:
#
#   1. ⭐⭐⭐ THE MARGIN TAIL. `_fanbeam_margin_text` ended "— the el axis is idle" UNCONDITIONALLY.
#      True on slice 55's arm (7.98° of 8.0° left, 99.7 %). At slice 57's HIGH wall the elevation
#      margin is 0.21° of a 2.29° half-width — 9 % — and the axis is not idle, it is nearly spent.
#      That is the slice-50 defect class exactly: every number on screen correct and the sentence
#      they add up to wrong. The tail is now DERIVED and this file drives it through all three of
#      its states.
#   2. ⭐⭐ THE CURE LINE quoted "a 10° DISC ... 11.3° of azimuth" — two hardcoded slice-55
#      constants stated as fact. Both are now computed from the window the wire reports.
#
#   3. ⚠ AND THE WIDTHS ARE A REAL NEW HAZARD, not a formality: no authored pair in this repo is
#      wider than 12.5°, but dragging this slider to its ceiling flies (63.2456°, 1.5811°) — longer
#      strings than any earlier wire ever produced. Measured in PIXELS at the slider's EXTREMES,
#      never at its authored arm (slice 46 shipped a 100-CHARACTER tooth that passed green while
#      every line clipped).
#
# Run:  godot --headless --path clients/godot --script res://net/slice57_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.
#
# ⚠ THE DISPATCH ORDER STILL HAS NO HEADLESS PROOF — both text chains are `if/elif` inside
# `_draw_airframe3d_hud`, which `--headless` never runs (slice 50 shipped a bug there that only the
# WINDOWED SHOT could see). The fourth proof is what shows the branch is reached.
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const MID := "m1"
const HUD_ORIGIN := 430.0
const HUD_ROOM := 400.0

# THE BUDGET, and the three shapes it is spent as. ⚠ The authored PAIR (12.5, 8.0) is NOT what flies
# — `gimbal_fov_aspect: 4.0` re-shapes it — so every number here is a FLOWN one.
const R_ACQ := 3038.16
const T_ACQ := 4.939
# aspect 4.0 (the shipped arm), 1.25 (the low wall) and 19.0 (the high wall), plus the slider's own
# extremes 0.5 and 40.0. Margins are the FRAME-sampled pairs measured at gate 3.
const A_MID := 20.0
const B_MID := 5.0
const AM_MID := 9.873
const BM_MID := 2.918
const A_LO := 11.1803
const B_LO := 8.9443
const AM_LO := 1.053
const BM_LO := 6.863
const A_HI := 43.5890
const B_HI := 2.2942
const AM_HI := 33.462
const BM_HI := 0.213
const A_CEIL := 63.2456
const B_CEIL := 1.5811

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb55

func _handshake() -> Dictionary:
	return {
		"name": "slice57_aspect",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": MID,
		"seeker_detect_view": true,
		"midcourse_view": true,
		"search_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"fanbeam_view": true,
		"knobs": [
			{"target": MID, "key": "gimbal_fov_aspect", "min": 0.5, "max": 40.0, "value": 4.0,
			 "label": "WINDOW ASPECT a/b at HELD aperture — locks only in 1.20-19.67; watch the two MARGINS"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}

func _initialize() -> void:
	print("S57UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_handshake())

	# ══ TOOTH 1 — ROUTE, AND IT IS DELIBERATELY THE SAME ONE ══════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-57 handshake (airframe_6dof) must enter _mode=airframe3d, got '%s'" % sb._mode)
	if not sb._fanbeam_view:
		return _fail("⭐⭐⭐ a slice-57 wire must take slice 55's OWN branch — the marker is raised on the `gimbal_fov_el_deg` comp key, so it is a CAPABILITY (any two-axis window) and this wire authors one. Adding a marker of its own would make markers name FILES instead of capabilities")
	print("S57UI_ROUTE  airframe3d + fanbeam_view — slice 55's branch, no marker of its own")

	# ══ TOOTH 2 — ⭐⭐⭐ THE MARGIN TAIL IS DERIVED, AND HAS THREE STATES ═══════════════════════
	var m_mid: String = sb._fanbeam_margin_text(AM_MID, BM_MID, A_MID, B_MID)
	var m_lo: String = sb._fanbeam_margin_text(AM_LO, BM_LO, A_LO, B_LO)
	var m_hi: String = sb._fanbeam_margin_text(AM_HI, BM_HI, A_HI, B_HI)
	# At the LOW wall the elevation half-width is 77 % unused — it IS idle, and so it must read.
	if not ("el axis idle" in m_lo):
		return _fail("at the LOW wall (%.4f of %.4f el left) the elevation axis is idle and the line must say so (got '%s')" % [BM_LO, B_LO, m_lo])
	# ⭐⭐⭐ AT THE HIGH WALL IT IS NOT, AND THIS IS THE ASSERTION THE WHOLE FILE EXISTS FOR.
	if "el axis idle" in m_hi:
		return _fail("⭐⭐⭐ at the HIGH wall only %.3f° of a %.3f° elevation half-width is left — 9 %% — and the line must NOT call that axis idle (got '%s'). This string was hardcoded until slice 57 and it was TRUE on slice 55's single authored pair; a slider that moves the shape over 80x makes a fixed sentence a lie. Every number on screen correct and the verdict they add up to wrong is the slice-50 defect class" % [BM_HI, B_HI, m_hi])
	if not ("az axis idle" in m_hi):
		return _fail("…and at the HIGH wall it is the AZIMUTH axis that is idle (%.3f° of %.3f° left) — the tail must name whichever one actually is (got '%s')" % [AM_HI, A_HI, m_hi])
	# …and the SHIPPED arm sits between the two, where neither axis is idle.
	if "idle" in m_mid:
		return _fail("⭐⭐ on the shipped arm BOTH axes are working (az %.3f of %.1f, el %.3f of %.1f) and the line must say so rather than pick one (got '%s')" % [AM_MID, A_MID, BM_MID, B_MID, m_mid])
	if not ("both axes working" in m_mid):
		return _fail("…and it must say which (got '%s')" % m_mid)
	# ⚠ THE SIGN IS STILL THE VERDICT, on either axis, unchanged from slice 55.
	if not ("OUTSIDE" in sb._fanbeam_margin_text(-0.4, 3.2, A_MID, B_MID)):
		return _fail("a negative AZIMUTH margin must still read OUTSIDE")
	if not ("OUTSIDE" in sb._fanbeam_margin_text(3.0, -0.2, A_MID, B_MID)):
		return _fail("…and a negative ELEVATION margin too — the window is the ∞-norm")
	print("S57UI_MARGIN lo:'%s'" % m_lo)
	print("S57UI_MARGIN hi:'%s'" % m_hi)

	# ══ TOOTH 3 — ⭐⭐ THE CURE LINE IS DERIVED, NOT A REMEMBERED PAIR OF NUMBERS ══════════════
	var c_mid: String = sb._fanbeam_cure_text(true, A_MID, B_MID, AM_MID, BM_MID)
	var c_hi: String = sb._fanbeam_cure_text(true, A_HI, B_HI, AM_HI, BM_HI)
	if not ("10.0" in c_mid):
		return _fail("⭐⭐ the cure line must name the GAIN-MATCHED disc sqrt(a*b) computed from the wire — at held aperture that is 10.0° on EVERY arm, which is the point (got '%s')" % c_mid)
	if not ("10.1" in c_mid or "10.13" in c_mid or ("%.1f" % (A_MID - AM_MID)) in c_mid):
		return _fail("…and the azimuth actually being used, `a - am` = %.1f°, also off the wire rather than slice 55's remembered 11.3 (got '%s')" % [A_MID - AM_MID, c_mid])
	# ⭐ AT THE HIGH WALL THE OTHER BRANCH FIRES — the elevation axis is doing the work, and the
	# advice inverts: narrowing it further is what fails.
	if not ("el axis is working" in c_hi):
		return _fail("⭐ at the HIGH wall the elevation margin is under half its half-width, so the cure line must warn that narrowing it fails (got '%s')" % c_hi)
	print("S57UI_CURE   mid:'%s'" % c_mid)
	print("S57UI_CURE   hi:'%s'" % c_hi)

	# ══ TOOTH 4 — ⭐⭐ THE COST LINE READS 100 deg^2 AT EVERY SHAPE ════════════════════════════
	# The whole slice: the product is held while the shape moves. If the HUD's own product drifts
	# with the slider, the picture says the aperture is being SPENT and the lesson inverts.
	for pair in [[A_LO, B_LO], [A_MID, B_MID], [A_HI, B_HI], [A_CEIL, B_CEIL]]:
		var w: String = sb._fanbeam_window_text(pair[0], pair[1], R_ACQ)
		if not ("100 deg^2" in w):
			return _fail("⭐⭐⭐ the window line must read 100 deg^2 at aspect (%.4f, %.4f) — the product is HELD and the shape is what moves (got '%s')" % [pair[0], pair[1], w])
		if not ("3038" in w):
			return _fail("…and the same reach on the same line at every shape (got '%s')" % w)
	print("S57UI_COST   the product reads 100 deg^2 and the reach 3038 m at every shape")

	# ══ TOOTH 5 — ⚠ WIDTHS AT THE SLIDER'S **EXTREMES**, IN PIXELS ════════════════════════════
	# ⚠⚠ No authored pair in this repo is wider than 12.5°; this slider's ceiling flies 63.2456°.
	# Measuring at the shipped arm would pass green while the widest arm clipped.
	var lines: Array = [
		sb._fanbeam_window_text(A_CEIL, B_CEIL, R_ACQ),
		sb._fanbeam_rival_text(A_CEIL, B_CEIL),
		sb._fanbeam_margin_text(-12.345, -0.987, A_CEIL, B_CEIL),
		sb._fanbeam_margin_text(61.234, 0.123, A_CEIL, B_CEIL),
		sb._fanbeam_cure_text(true, A_CEIL, B_CEIL, 61.234, 0.123),
		sb._fanbeam_window_text(7.0711, 14.1421, R_ACQ),
		sb._fanbeam_margin_text(6.0, 13.5, 7.0711, 14.1421),
	]
	for s in lines:
		var w2: float = sb._font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w2 > HUD_ROOM:
			return _fail("⚠ line '%s' is %.0f px wide against a %.0f px column — measured at the SLIDER's extremes, which is where the numbers are longest" % [s, w2, HUD_ROOM])
	var head: String = sb._fanbeam_verdict_label(A_CEIL, B_CEIL, false, -1.0, false, false)
	if sb._font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x > HUD_ROOM:
		return _fail("headline '%s' overflows the column" % head)
	print("S57UI_WIDTH  every line fits %.0f px at the slider's widest AND tallest arms" % HUD_ROOM)

	# ══ TOOTH 6 — ⭐ THE HEADLINE'S TALL BRANCH IS REACHABLE FROM THIS SLIDER ══════════════════
	# Slice 55 could only reach `b > a` by authoring a second file. Here it is aspect < 1, which is
	# inside the slider's own domain — so the losing direction is a DRAG rather than a claim.
	var h_tall: String = sb._fanbeam_verdict_label(7.0711, 14.1421, false, -1.0, false, false)
	if not ("TALL" in h_tall):
		return _fail("⭐ at aspect 0.5 the window is TALLER than it is wide and the headline must say so (got '%s') — on this wire that state is one drag away, not a second file" % h_tall)
	var h_narrow: String = sb._fanbeam_verdict_label(A_CEIL, B_CEIL, false, -1.0, false, false)
	if not ("narrow" in h_narrow):
		return _fail("…and at the ceiling it fails the other way (got '%s')" % h_narrow)
	print("S57UI_HEAD   '%s' / '%s'" % [h_tall, h_narrow])

	# ══ TOOTH 7 — ONE SLIDER → set_param ON THE MISSILE'S ASPECT ══════════════════════════════
	var sliders: Array = _find_all_sliders(sb)
	if sliders.size() != 1:
		return _fail("convention 9: exactly ONE slider, got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 19.0
	sliders[0].emit_signal("value_changed", 19.0)
	var found := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "gimbal_fov_aspect" \
				and str(d.get("target", "")) == MID:
			found = true
	if not found:
		return _fail("⚠⚠ the slider must send set_param on the MISSILE's `gimbal_fov_aspect` with the field named `target` — the server reads `cmd[:target]`, so a wrong field name does not error, it is silently ignored and every arm flies the authored shape (slice 40's first-run bug, and slice 57's verifier reproduced it verbatim)")
	print("S57UI_WIRE   one slider → set_param(m1.gimbal_fov_aspect)")

	# ══ TOOTH 8 — ⭐ THE MIRROR: slice 55's own wire is UNCHANGED by all of this ═══════════════
	# The two lines this slice made derived are shared, so slice 55's arm has to be re-checked here
	# as well as in its own file: on (12.5, 8.0) with 7.98° of elevation left the tail must still
	# read "the el axis is idle", because on THAT wire it is true.
	_sb55 = _build_sandbox()
	var m55: String = _sb55._fanbeam_margin_text(1.1446, 7.9797, 12.5, 8.0)
	if not ("el axis idle" in m55):
		return _fail("⭐ making the tail derived must not change slice 55's own verdict — 7.98° of 8.0° IS idle (got '%s')" % m55)
	print("S57UI_PRIOR  slice 55's own arm still reads 'the el axis is idle'")

	return _pass()

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here and the PIXEL width
	# tooth would CRASH on it rather than fail. Assign the SAME font `_draw` uses.
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
	print("S57UI OK: a fixed aperture can cover a two-axis uncertainty only if the two errors " +
		"MULTIPLY to less than it, and inside that band the shape is free — bit-for-bit free. " +
		"⭐⭐⭐ WHICH IS WHY THE MARGINS ARE THE HUD's JOB HERE: the flight is identical from " +
		"aspect 1.25 to 19.0 and each end sits a fifth of a degree from a cliff, at OPPOSITE ends. " +
		"A line that says 'the el axis is idle' whatever the wire reports would hide exactly that.")
	_teardown()
	quit(0)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb55]:
		if sb != null and sb is Node:
			sb.free()

func _fail(msg: String, code: int = 1) -> bool:
	push_error("S57UI FAIL: " + msg)
	print("S57UI FAIL: ", msg)
	_teardown()
	quit(code)
	return true
