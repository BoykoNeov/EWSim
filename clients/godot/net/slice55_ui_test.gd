extends SceneTree
# Headless UI test for the slice-55 FAN-BEAM view routing + HUD — the piece slice55_verify.gd cannot
# reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn smoke-load
# proves the scene loads. Neither exercises the CLIENT routing, the marker, or the HUD this slice
# adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14)
# — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐⭐ THE ONE THING THIS FILE EXISTS FOR ABOVE ALL OTHERS: **SLICE 48's BLOCK IS NOT MERELY
# INCOMPLETE ON THIS WIRE, IT IS BACKWARDS.** Its gauge is `search_t_lock_s`, seconds from the
# SWEEP's start — and a fan beam wide enough to hold the midcourse cue error never enters the search
# arm at all, so the key holds its honest sentinel −1.0 across a flight that acquires at 4.94 s and
# hits at 0.09 m. Left to slice 48's branch this wire would print "NOT SEARCHING: head frozen" over
# an intercept: every number true, the verdict inverted. That is `docs/CONVENTIONS.md` §14's
# defaulted-value trap with the sign flipped, and it is why the 15th marker exists.
#
# ⭐⭐ AND THE SECOND REASON: **THE COST MUST BE ON SCREEN BESIDE THE SHAPE.** A window drawn without
# its horizon is "a wider window is free" — the claim slices 42/43 earned a ban for and slice 46
# upheld. This file asserts that the window line carries the PRODUCT (the aperture) and the REACH
# (what it bought), and that the rival line names the gain-matched disc `sqrt(a*b)` rather than
# either geometric analogy the plan pre-registered and rejected.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-55 handshake enters _mode=airframe3d and records `fanbeam_view` beside 46/47/48's
#   2. ⭐⭐⭐ THE HEADLINE MUST NOT BE SLICE 48's — five states, and the null is its own sentence
#   3. ⭐⭐⭐ THE SENTINEL IS EXPLAINED: −1.0 reads "never ran", never "never found it"
#   4. ⭐⭐ THE COST TRAVELS WITH THE SHAPE — the product AND the reach, on the same line
#   5. ⭐⭐ THE MARGIN PAIR IS THE VERDICT — a negative half must say OUTSIDE
#   6. ⚠ every key `_draw_fanbeam_hud_lines` reads is present and scalar, and no default is a LIE
#   7. ONE slider → set_param on the MISSILE's `seeker_search_rate_dps`
#   8. ⚠ WIDTHS: the block's lines fit the family's 430 px origin, measured in PIXELS
#   9. ⭐ THE MIRROR: a slice-48 wire raises no fan-beam marker and keeps its own HUD
#
# Run:  godot --headless --path clients/godot --script res://net/slice55_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.
#
# ⚠ THE DISPATCH ORDER ITSELF STILL HAS NO HEADLESS PROOF. Both text chains are `if/elif` inside
# `_draw_airframe3d_hud`, which `--headless` never runs (slice 50 shipped a bug there that only the
# WINDOWED SHOT could see). What this file can prove is that the MARKER is parsed and that every
# string the branch draws is correct; the fourth proof is what shows the branch is reached.
#
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const MID := "m1"

# The family's right-hand column: the origin is `vp.x − 430`, and the 3-D airframe backdrop carries
# altitude tick labels up the right edge (slice 49 paid 390 px for exactly this), so the honest room
# is less than the origin. Measured in PIXELS, never characters — slice 46 shipped a 100-CHARACTER
# tooth that passed green while every line clipped.
const HUD_ORIGIN := 430.0
const HUD_ROOM := 400.0

# THE AUTHORED WINDOW, and the numbers the shipped wire actually produces.
const WIN_AZ := 12.5
const WIN_EL := 8.0
const R_ACQ := 3038.16
const T_ACQ := 4.935
const AZ_MARGIN := 1.1446
const EL_MARGIN := 7.9797

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb48
var _sb_nomarker

func _fb_tel(t_acq: float, az_m: float, el_m: float, searching: bool, rho: float,
			 valid: bool) -> Dictionary:
	return {
		MID + ".gimbal_fov_deg": WIN_AZ,
		MID + ".gimbal_fov_el_deg": WIN_EL,
		MID + ".gimbal_fov_az_margin_deg": az_m,
		MID + ".gimbal_fov_el_margin_deg": el_m,
		MID + ".gimbal_fov_margin_deg": 1.16,
		MID + ".gimbal_t_acq_s": t_acq,
		MID + ".gimbal_valid": 1.0 if valid else 0.0,
		MID + ".gimbal_stop_deg": 45.0,
		MID + ".gimbal_rate_dps": 240.0,
		MID + ".seeker_r_acq_m": R_ACQ,
		MID + ".search_rate_dps": rho,
		MID + ".search_coverage_deg": 25.0,
		MID + ".search_t_lock_s": -1.0,
		MID + ".search_deficit_deg": 0.0,
		MID + ".search_elapsed_s": 0.0,
		MID + ".head_searching": 1.0 if searching else 0.0,
		MID + ".head_cued": 0.0,
		MID + ".los_range": 2400.0,
		MID + ".a_cmd_frac": 0.45,
	}

func _handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice55_fanbeam",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": MID,
		# ⚠⚠ FOUR EARLIER MARKERS ARE RAISED HERE AND THAT IS THE HAZARD, not their absence — and
		# `search_view` is the dangerous one, because slice 48's block is about the same head on the
		# same wire and its numbers are all TRUE except the one it is built around.
		"seeker_detect_view": true,
		"midcourse_view": true,
		"search_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": MID, "key": "seeker_search_rate_dps", "min": 0.0, "max": 240.0,
			 "value": 0.0,
			 "label": "SEEKER SWEEP RATE (deg/s) — INERT here: nothing to search for. Compare slice48_search"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["fanbeam_view"] = true
	return h

func _initialize() -> void:
	print("S55UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_handshake(true))

	# ══ TOOTH 1 — ROUTE ══════════════════════════════════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-55 handshake (airframe_6dof) must enter _mode=airframe3d, got '%s'" % sb._mode)
	if not sb._fanbeam_view:
		return _fail("the client must record the `fanbeam_view` handshake marker — it is raised on the `gimbal_fov_el_deg` comp key, so the gate is a CAPABILITY and not a file")
	for f in [sb._search_view, sb._midcourse_view, sb._seeker_detect_view, sb._gimbal_view,
			  sb._gimbal_rate_view]:
		if not f:
			return _fail("a slice-55 wire IS a slice-48 wire with its window turned on its side — every earlier marker must still be recorded, which is what makes the new one a BRANCH SELECTOR rather than a hole plug")
	if sb._s52_view:
		return _fail("a slice-55 wire authors no `seeker_search_realized` instrument, so slice 52's marker must stay down")
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_handshake(false))
	if _sb_nomarker._fanbeam_view:
		return _fail("the no-marker mirror must NOT record fanbeam_view")
	print("S55UI_ROUTE  airframe3d + fanbeam_view recorded beside 46/47/48's markers")

	# ══ TOOTH 2 — ⭐⭐⭐ THE HEADLINE, AND IT MUST NOT BE SLICE 48's ══════════════════════════════
	var h_atonce: String = sb._fanbeam_verdict_label(WIN_AZ, WIN_EL, true, T_ACQ, false, false)
	var h_found: String = sb._fanbeam_verdict_label(WIN_AZ, WIN_EL, true, 6.4, true, false)
	var h_tall: String = sb._fanbeam_verdict_label(6.0, 16.7, false, -1.0, false, false)
	var h_never: String = sb._fanbeam_verdict_label(WIN_AZ, WIN_EL, false, -1.0, false, false)
	# ⚠⚠ THE BLIND STATE, AND IT IS THE ONE THIS BLOCK GOT WRONG FIRST. The shipped wire spends its
	# first 4.94 s under the horizon; without a state of its own the headline read "NEVER SAW IT:
	# too narrow" for half the engagement — a past-tense verdict about a window that had not yet
	# been given anything to see.
	var h_blind: String = sb._fanbeam_verdict_label(WIN_AZ, WIN_EL, false, -1.0, false, true)
	if h_blind == h_never or not ("BLIND" in h_blind):
		return _fail("⭐⭐⭐ a seeker still under its HORIZON must not be told its window is too narrow: blind reads '%s' against never-acquired '%s'" % [h_blind, h_never])
	for pair in [["at once", h_atonce], ["found", h_found], ["tall", h_tall], ["never", h_never],
				 ["blind", h_blind]]:
		if str(pair[1]).strip_edges() == "":
			return _fail("the %s headline must say something" % pair[0])
	if h_atonce == h_found or h_atonce == h_tall or h_tall == h_never:
		return _fail("⭐⭐ four distinct states must read as four distinct sentences: '%s' / '%s' / '%s' / '%s'" %
					 [h_atonce, h_found, h_tall, h_never])
	if not ("4.9" in h_atonce):
		return _fail("the acquiring headline must carry the acquisition INSTANT (got '%s') — that clock is the core's `gimbal_t_acq_s` latch, not slice 48's sweep clock" % h_atonce)
	# ⭐⭐⭐ THE LOSING DIRECTION MUST HAVE ITS OWN SENTENCE. A tall window spends the identical
	# budget on the axis nothing ever moves in and is BIT-IDENTICAL to the disc over 9600 ticks —
	# without a state that names it, the block ships a free lunch instead of a trade.
	if not ("TALL" in h_tall):
		return _fail("⭐⭐⭐ a window taller than it is wide must be named as such (got '%s') — the same aperture spent on the UNSWEPT axis buys literally nothing, and that losing direction is what makes this a trade rather than a claim" % h_tall)
	print("S55UI_HEADLINE '%s' / '%s' / '%s' / '%s'" % [h_atonce, h_found, h_tall, h_never])

	# ══ TOOTH 3 — ⭐⭐⭐ THE SENTINEL IS EXPLAINED, NOT PRINTED ══════════════════════════════════
	# `search_t_lock_s` is −1.0 on every arm of this wire. Slice 48's own wording for that state is
	# "never found it" / "head frozen" — over an intercept. This line must say WHICH of the two
	# things a −1.0 means here: not a search that failed, a search that never had to run.
	var s_null: String = sb._fanbeam_search_text(true, false, false, 0.0, -1.0)
	var s_sweep: String = sb._fanbeam_search_text(true, true, true, 240.0, -1.0)
	var s_found: String = sb._fanbeam_search_text(true, true, false, 60.0, 1.02)
	var s_off: String = sb._fanbeam_search_text(false, false, false, 0.0, -1.0)
	# ⭐⭐⭐ THE TWO NULLS ARE DIFFERENT NULLS — the defect the WINDOWED SHOT caught. A wire with NO
	# search authored ("the head cannot look around", slice 48's own wording for a head that cannot)
	# must not read the same as a wire whose full search pattern was simply never needed.
	if s_null == s_off:
		return _fail("⭐⭐⭐ a seeker whose authored search NEVER RAN must not read like a seeker that has no search at all — both said '%s'. The shipped wire authors a 25° pattern at 0°/s and never needs it; slice 48's floor is a head that cannot look around" % s_null)
	if not ("cannot look around" in s_off):
		return _fail("…and the no-search-at-all state keeps slice 48's own wording (got '%s')" % s_off)
	if not ("NEVER RAN" in s_null):
		return _fail("⭐⭐⭐ with the sweep clock at −1.0 and the head never searching, the line must say the search NEVER RAN (got '%s'). Slice 48's block reads the same key and says 'never found it' — every number true, the verdict inverted, over a 0.09 m intercept" % s_null)
	if "never found" in s_null.to_lower():
		return _fail("⚠⚠ the null must not be worded as a FAILED search: '%s'" % s_null)
	if s_null == s_sweep or s_null == s_found or s_null == s_off:
		return _fail("the four search states must read distinctly: '%s' / '%s' / '%s' / '%s'" %
					 [s_null, s_sweep, s_found, s_off])
	if not ("1.02" in s_found):
		return _fail("…and where a sweep DID run, the line must still carry its clock (got '%s')" % s_found)
	print("S55UI_SENTINEL '%s'" % s_null)

	# ══ TOOTH 4 — ⭐⭐ THE COST TRAVELS WITH THE SHAPE ═══════════════════════════════════════════
	var w_line: String = sb._fanbeam_window_text(WIN_AZ, WIN_EL, R_ACQ)
	if not ("100" in w_line):
		return _fail("⭐⭐ the window line must carry the PRODUCT (%.1f x %.1f = 100 deg^2) — that product IS the aperture, and it is the only thing that makes this comparable to a disc (got '%s')" % [WIN_AZ, WIN_EL, w_line])
	if not ("3038" in w_line):
		return _fail("⭐⭐⭐ …and the REACH on the same line (got '%s'). A window drawn without its horizon is 'a wider window is free' — the claim slices 42/43 earned a ban for and slice 46 upheld" % w_line)
	if absf(sb._fb_area_deg2(WIN_AZ, WIN_EL) - 100.0) > 1.0e-9:
		return _fail("the product must be the two half-widths multiplied, nothing else")
	# ⭐⭐ THE CONTROL IS THE GAIN-MATCHED DISC sqrt(a*b) — the only one of the three candidates the
	# link budget has a consumer for. The arithmetic mean (10.25) and the equal-AREA radius (11.28)
	# are geometric analogies that nothing in this simulator reads.
	var r_line: String = sb._fanbeam_rival_text(WIN_AZ, WIN_EL)
	if not ("10.0" in r_line):
		return _fail("⭐⭐⭐ the rival line must name the GAIN-MATCHED disc sqrt(12.5*8.0) = 10.0° (got '%s'). Sum-matching would print 10.3 and area-matching 11.3, and neither has a consumer anywhere in this simulator — `aperture_gain` defines the budget as G = eta*4pi/(theta_az*theta_el)" % r_line)
	if "11.3" in r_line or "10.2" in r_line:
		return _fail("⚠⚠ the rival line printed a sum- or area-matched disc: '%s'" % r_line)
	print("S55UI_COST   '%s' | '%s'" % [w_line, r_line])

	# ══ TOOTH 5 — ⭐⭐ THE MARGIN PAIR IS THE VERDICT ═══════════════════════════════════════════
	var m_ok: String = sb._fanbeam_margin_text(AZ_MARGIN, EL_MARGIN, WIN_AZ, WIN_EL)
	var m_out: String = sb._fanbeam_margin_text(-0.4, 3.2, WIN_AZ, WIN_EL)
	var m_out_el: String = sb._fanbeam_margin_text(3.0, -0.2, WIN_AZ, WIN_EL)
	if not ("OUTSIDE" in m_out and "OUTSIDE" in m_out_el):
		return _fail("⭐⭐ a negative margin on EITHER axis must read OUTSIDE — the window is the ∞-norm, so a look is inside iff neither axis is over (got '%s' / '%s')" % [m_out, m_out_el])
	if "OUTSIDE" in m_ok:
		return _fail("…and a pair that is inside on both axes must not (got '%s')" % m_ok)
	if not ("1.14" in m_ok and "7.98" in m_ok):
		return _fail("⭐⭐⭐ the inside line must carry BOTH margins (got '%s') — the whole lesson is that they are wildly UNEQUAL: the azimuth spent down to a sliver on the axis the error is in, and all but a fiftieth of a degree of elevation idle. A worst-of would print the sliver and hide the waste that paid for it" % m_ok)
	print("S55UI_MARGIN '%s'" % m_ok)

	# ══ TOOTH 6 — ⚠ EVERY KEY THE BLOCK READS IS PRESENT, AND NO DEFAULT IS A LIE ══════════════
	sb._telemetry = _fb_tel(T_ACQ, AZ_MARGIN, EL_MARGIN, false, 0.0, true)
	sb._af3d_missile = MID
	for k in ["gimbal_fov_deg", "gimbal_fov_el_deg", "gimbal_fov_az_margin_deg",
			  "gimbal_fov_el_margin_deg", "gimbal_t_acq_s", "seeker_r_acq_m", "search_rate_dps"]:
		if not sb._telemetry.has(MID + "." + k):
			return _fail("the HUD reads `%s` and the wire must ship it" % k)
	if absf(sb._fb_t_acq_s() - T_ACQ) > 1.0e-9:
		return _fail("the acquisition latch must be read off the wire, not reconstructed")
	# ⚠⚠ AND THE SENTINEL MUST SURVIVE A MISSING KEY AS −1.0, NEVER AS 0.0: on a wire that has not
	# acquired yet the key is present and negative, but a client whose default was 0.0 would print
	# "acquired at t = 0" for "never acquired" — and 0.0 is a REAL value here (press the button and
	# the window holds the target from the first tick).
	sb._telemetry = {}
	if sb._fb_t_acq_s() != -1.0:
		return _fail("⚠⚠ the acquisition clock must default to the SENTINEL −1.0, got %.3f — 0.0 is a real value of this quantity (the button arm reads exactly that), so a defaulted zero prints 'acquired at once' for 'never acquired'" % sb._fb_t_acq_s())
	print("S55UI_KEYS   seven keys present; the clock defaults to −1.0 and not to a real value")

	# ══ TOOTH 7 — ONE SLIDER → set_param ON THE MISSILE ════════════════════════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9), got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 120.0
	sliders[0].value_changed.emit(120.0)
	var ok := false
	for c in mock.sent:
		if str(c.get("type", "")) == "set_param" and str(c.get("target", "")) == MID \
				and str(c.get("key", "")) == "seeker_search_rate_dps":
			ok = true
	if not ok:
		return _fail("dragging the slider must send set_param on the missile's `seeker_search_rate_dps` — got %s" % str(mock.sent))
	print("S55UI_WIRE   one slider → set_param(m1.seeker_search_rate_dps)")

	# ══ TOOTH 8 — ⚠ WIDTHS, IN PIXELS ═════════════════════════════════════════════════════════
	for s in [w_line, r_line, m_ok, m_out, s_null, s_sweep, s_found, s_off,
			  sb._fanbeam_cure_text(false, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN),
			  sb._fanbeam_cure_text(true, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN),
			  sb._fanbeam_cure_text(true, WIN_AZ, WIN_EL, AZ_MARGIN, 0.2),
			  sb._fanbeam_cure_text(false, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN, true)]:
		pass
	# ⚠⚠ AND THE CURE LINE'S OWN ORDERING, which the shot caught: `_detect_blind` is a LATCH, so an
	# ACQUIRED seeker whose blind phase is long over must not still be told it is waiting on the
	# horizon. Two verdicts about the same instant is this family's recurring HUD failure.
	if "waiting" in sb._fanbeam_cure_text(true, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN, true):
		return _fail("⭐⭐⭐ an ACQUIRED seeker must not read 'waiting on the horizon' just because the blind LATCH is still set — the windowed shot found exactly that beside a green SAW IT AT ONCE headline")
	if not ("waiting" in sb._fanbeam_cure_text(false, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN, true)):
		return _fail("…and a seeker that has NOT acquired and is still under the horizon must say so")
	for s in [w_line, r_line, m_ok, m_out, s_null, s_sweep, s_found, s_off,
			  sb._fanbeam_cure_text(false, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN),
			  sb._fanbeam_cure_text(true, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN),
			  sb._fanbeam_cure_text(true, WIN_AZ, WIN_EL, AZ_MARGIN, 0.2),
			  sb._fanbeam_cure_text(false, WIN_AZ, WIN_EL, AZ_MARGIN, EL_MARGIN, true)]:
		var w: float = sb._font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > HUD_ROOM:
			return _fail("HUD line '%s' is %.0f px wide against %.0f px of column — slice 46 shipped a CHARACTER budget that passed green while every line clipped" % [s, w, HUD_ROOM])
	for s in [h_atonce, h_found, h_tall, h_never, h_blind]:
		var w2: float = sb._font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if w2 > HUD_ROOM:
			return _fail("headline '%s' is %.0f px wide against %.0f px" % [s, w2, HUD_ROOM])
	print("S55UI_WIDTH  every line fits the %.0f px column at its own font size" % HUD_ROOM)

	# ══ TOOTH 9 — ⭐ THE MIRROR: a slice-48 wire keeps its own HUD ═════════════════════════════
	_sb48 = _build_sandbox()
	var h48 := {
		"name": "slice48_search", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": MID, "seeker_detect_view": true, "midcourse_view": true,
		"search_view": true, "gimbal_view": true, "gimbal_rate_view": true,
		"knobs": [{"target": MID, "key": "seeker_search_rate_dps", "min": 0.0, "max": 240.0,
				   "value": 0.0, "label": "SEEKER SWEEP RATE"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	_sb48._on_scenario(h48)
	if _sb48._fanbeam_view:
		return _fail("a slice-48 wire authors a ROUND window, so it must raise no fan-beam marker — that is what keeps every slice 34–54 frame byte-identical")
	if not _sb48._search_view:
		return _fail("⭐ …and it must keep its own HUD marker — the new branch is checked FIRST at both text sites, so a bug there would steal slice 48's own wire")
	if _sb48._fid_kind != "seeker_detect":
		return _fail("⭐ …and its button too (got %s)" % _sb48._fid_kind)
	print("S55UI_PRIOR  a slice-48 wire raises no fan-beam marker and keeps its HUD")

	return _pass()

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
	print("S55UI OK: a round detector window is not a baseline — it is one arbitrary point on an " +
		"aspect-ratio axis, and on a missile that has to LOOK AROUND it is not the good one. " +
		"⭐⭐⭐ THE SEARCH CLOCK READS −1.0 OVER AN INTERCEPT AND THAT IS THE LESSON, NOT A BUG: " +
		"you only search because you were blind, and this seeker was not. Slice 48's block reads " +
		"the same key and would call it 'head frozen'. ⭐⭐ AND THE COST IS ON THE SAME LINE AS " +
		"THE SHAPE — 12.5 x 8.0 = 100 deg^2 and 3038 m, the disc's own aperture and the disc's own " +
		"horizon.")
	_teardown()
	quit(0)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb48, _sb_nomarker]:
		if sb != null and sb is Node:
			sb.free()

func _fail(msg: String, code: int = 1) -> bool:
	push_error("S55UI FAIL: " + msg)
	print("S55UI FAIL: ", msg)
	_teardown()
	quit(code)
	return true
