extends SceneTree
# Headless UI test for the slice-49 ASPECT view routing + HUD — the piece slice49_verify.gd cannot
# reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn smoke-load
# proves the scene loads. Neither exercises the CLIENT routing, the button drop, or the HUD this
# slice adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL
# (convention 14) — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐ THE MARKER DOES **BOTH** JOBS — the HUD **and** the BUTTON — and this is the first of the
# family to land in the SPATIAL (elevation) view rather than the 3-D airframe one:
#   THE BUTTON JOB IS A **DROP**, and it is not optional. The scenario authors `propagation:
#     free_space`, so without a branch this wire falls through `_setup_spatial_fid_btn`'s final
#     `else` to `_fid_kind = "propagation"` and keeps the `free_space ↔ two_ray` toggle `_build_ui`
#     already wired. A student could then press MULTIPATH LOBING on top of a scenario whose target
#     vanishes because of its HEADING, and the drop-out would have two candidate explanations on
#     screen at once. Convention 9's exact prohibition.
#   THE HUD JOB is the aspect block itself: without it the client draws the correct spatial view
#     with the target simply going grey, and never says WHY.
#   ⚠ THERE IS NO VIEW JOB. `Sandbox.gd`'s dispatch falls through to the spatial radar view without
#     the marker — which IS the right view — so the marker-hole check comes back NEGATIVE on that
#     one axis. Slice 35 drew this distinction and recorded it *because getting it backwards teaches
#     the next slice the wrong rule*; the plan's own §13 got it backwards once and was corrected.
#
# ⭐⭐⭐ AND THE SHARPEST TOOTH IN THE FILE IS THAT **THE GAUGE STOPS AT CPA.** The number this slice
# is measured on is the longest loss run WHILE CLOSING. On this scenario the target passes its
# closest approach at ~7.8 km and opens again nose-off, so it stays invisible for the rest of the
# run — a whole-flight clock would keep counting and drift ABOVE the 36.50 s the ladder quotes, i.e.
# print a number that is not this slice's under this slice's label. That is asserted here, on a
# fixture that goes past CPA and stays lost.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-49 handshake stays in _mode=spatial and records the marker AND THE PAIR
#   2. ⭐⭐ THE BUTTON IS DROPPED — and stays dropped through `_update_fid_btn`
#   3. ⭐⭐ THE MIRROR: strip the marker and the MULTIPATH button comes back on this wire
#   4. ⭐⭐⭐ THE PAIR IS NOT SYMMETRIC — the keys are the OBSERVER's, the prose names the TARGET
#   5. ⭐⭐⭐ THE GAUGE: it accumulates while closing, banks its maximum, and STOPS AT CPA
#   6. ⭐ Reset clears all six instruments
#   7. ⭐ the VERDICT in its four states, all distinct, none naming a detected-% or a loss COUNT
#   8. ⚠⚠ WIDTHS: **390 px, not the family's 430** — this view has altitude labels up the right edge
#   9. every key `_draw_aspect_hud_lines` reads is present and scalar, and no default is a LIE
#  10. ONE slider → set_param on the TARGET's `rcs_fineness`
#  11. ⭐ THE MIRROR THE OTHER WAY: a slice-2 wire raises no marker and keeps its propagation button
#
# Run:  godot --headless --path clients/godot --script res://net/slice49_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const RAD := "radar1"
const TID := "tgt1"

# ⚠ THE BUDGET IS 390 px AND NOT THE FAMILY'S 430, AND THE REASON IS THIS VIEW AND NOT THIS SLICE.
# Slices 34–48 drew into the 3-D airframe view, whose right edge is empty. The SPATIAL view puts its
# ALTITUDE TICK LABELS up the right edge (`_draw_spatial_backdrop`: `vp.x − 34`, with "alt (km)" at
# `vp.x − 52`), so a line drawn from `vp.x − 430` that uses all 430 runs straight through them — at
# EVERY window size, because both origins are anchored to the right edge. Inheriting 430 here would
# have been slice 46's clipped-HUD defect committed on purpose.
const HUD_ORIGIN := 430.0
const LABEL_GUTTER := 40.0
const HUD_ROOM := HUD_ORIGIN - LABEL_GUTTER      # 390

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb2

# The fixture reproduces the wire's own shape: the four aspect keys ride the target's SHAPE, so on
# this wire they ship on EVERY frame — including while the target is comfortably held, when they
# freeze at broadside values rather than vanishing.
func _asp_tel(deg: float, sigma: float, loss_db: float, range_m: float, det: bool, pd: float) -> Dictionary:
	return {
		RAD + ".snr_db": 21.4 if det else -4.2,
		RAD + ".pd": pd,
		RAD + ".detected": det,
		RAD + ".visible": true,
		RAD + ".target_aspect_deg": deg,
		RAD + ".rcs_eff_m2": sigma,
		RAD + ".rcs_loss_db": loss_db,
		RAD + ".target_range_m": range_m,
	}

func _asp_handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice49_aspect",
		"knobs": [
			{"target": TID, "key": "rcs_fineness", "min": 1.0, "max": 12.0, "value": 8.0,
			 "label": "Target fineness L/r (1 = sphere)"},
		],
		"fidelity": {"propagation": "free_space", "detection": "analytic"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["aspect_view"] = true
		h["aspect_target"] = TID
		h["aspect_observer"] = RAD
	return h

func _st(x: float, t: float) -> Dictionary:
	# The elevation view's entity stream. ⚠ `entities` is an ARRAY OF RECORDS (the wire's own shape).
	return {"t": t, "entities": [
		{"id": RAD, "kind": "radar", "pos": [0.0, 0.0, 30.0]},
		{"id": TID, "kind": "target", "pos": [x, 12000.0, 5000.0]},
	]}

func _feed(sb, t: float, range_m: float, det: bool, deg := 40.0) -> void:
	# One frame through the REAL client path, so the gauge is exercised where it actually lives.
	sb._telemetry = _asp_tel(deg, 0.0004, 34.5, range_m, det, 0.02 if not det else 0.94)
	sb._spatial_on_state(_st(1000.0 + t * 10.0, t))

func _initialize() -> void:
	print("S49UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_asp_handshake(true))

	# ══ TOOTH 1 — ROUTE, AND THE PAIR ════════════════════════════════════════════════════════════
	if sb._mode != "spatial":
		return _fail("a slice-49 handshake must STAY in the spatial elevation view, got %s — this is a ground radar watching an aircraft turn, and the marker deliberately does NOT pick a view" % sb._mode)
	if not sb._aspect_view:
		return _fail("the client must record the `aspect_view` handshake marker")
	if sb._aspect_target != TID or sb._aspect_observer != RAD:
		return _fail("⚠ an aspect belongs to a target–observer PAIR and the marker carries both: got target '%s' / observer '%s'. A HUD reading 'aspect 25°' with no subject is this family's ~13th stale readout" % [sb._aspect_target, sb._aspect_observer])
	print("S49UI_ROUTE  spatial view kept, aspect_view + the %s→%s pair recorded" % [sb._aspect_target, sb._aspect_observer])

	# ══ TOOTH 2 — ⭐⭐ THE BUTTON IS DROPPED, AND STAYS DROPPED ═══════════════════════════════════
	if sb._fid_kind != "aspect":
		return _fail("⭐⭐ the marker must claim the shared button (got _fid_kind '%s') — this wire AUTHORS `propagation: free_space`, so every other branch falls through to the propagation cycler" % sb._fid_kind)
	if sb._prop_btn.visible:
		return _fail("⭐⭐ the shared button must be HIDDEN: there is nothing here to cycle (the lesson is the ONE fineness slider) and what it would offer is `free_space ↔ two_ray` — MULTIPATH LOBING on a scenario whose target vanishes for a completely different reason")
	if sb._prop_btn.pressed.is_connected(sb._on_prop_pressed):
		return _fail("…and its `_on_prop_pressed` connection must be dropped too, or a stray press still sends set_fidelity(propagation)")
	# ⚠ THE DEFENSIVE RE-SHOW (the slice-16/26 shape): `_update_fid_btn` runs after
	# `_setup_spatial_fid_btn` on every handshake and again on every reset, and its `_:` default falls
	# to `_update_prop_btn`, which would LABEL the dropped button "prop: free_space" — a two_ray
	# toggle advertising itself on a wire that must not offer one.
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("⚠ `_update_fid_btn` re-showed the dropped button — it runs again on every reset, so the drop needs its own case at BOTH sites (slice 16/26 found this twice)")
	if str(sb._prop_btn.text).begins_with("prop:"):
		return _fail("⚠ …and it must not be LABELLED 'prop:' either — got '%s', which advertises a multipath toggle this wire must not offer" % sb._prop_btn.text)
	print("S49UI_BUTTON the free_space↔two_ray toggle is DROPPED and stays dropped through _update_fid_btn")

	# ══ TOOTH 3 — ⭐⭐ THE MIRROR: without the marker the MULTIPATH BUTTON COMES BACK ═════════════
	# ⚠⚠ AND THE HOLE HERE IS NOT A VIEW. The dispatch falls through to the spatial radar view
	# without the marker, which IS the correct view — so this is a BRANCH SELECTOR and a
	# BUTTON-DROPPER, not a hole plug. What is actually wrong without it is narrower and still real,
	# and both halves are reproduced here or the mirror proves nothing.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_asp_handshake(false))
	if _sb_nomarker._aspect_view:
		return _fail("the no-marker mirror must NOT record aspect_view")
	if _sb_nomarker._mode != "spatial":
		return _fail("⚠ the two must share the VIEW — the marker changes the BUTTON and the HUD, not the view. Got %s vs %s" % [_sb_nomarker._mode, sb._mode])
	if _sb_nomarker._fid_kind != "propagation" or not _sb_nomarker._prop_btn.visible:
		return _fail("⭐⭐ THE HOLE: without the marker this wire must fall to the PROPAGATION cycler with the button visible — that fallback is exactly the failure being prevented (a MULTIPATH lesson offered on top of this one), and it must be reproduced here or the mirror proves nothing. Got '%s' / visible=%s" % [_sb_nomarker._fid_kind, _sb_nomarker._prop_btn.visible])
	print("S49UI_MIRROR without the marker the wire keeps the view and REGAINS the free_space↔two_ray button — the exact failure the marker prevents")

	# ══ TOOTH 4 — ⭐⭐⭐ THE PAIR IS NOT SYMMETRIC ════════════════════════════════════════════════
	# The telemetry is keyed on the **RADAR** (`radar1.target_aspect_deg`) while the prose names the
	# **TARGET**. Read the keys off the target by mistake and every `.get(k, default)` fires — which
	# on this HUD is the loudest possible lie, because a defaulted aspect of 0° means NOSE-ON, the
	# one state the whole lesson is about. That is why `_asp_deg`'s default is 90 and not 0.
	if sb._asp_key("target_aspect_deg") != RAD + ".target_aspect_deg":
		return _fail("⭐⭐⭐ the HUD must form its keys off the OBSERVER (got '%s') — the wire is keyed on the radar, not on the target the prose names" % sb._asp_key("target_aspect_deg"))
	sb._telemetry = {}
	if absf(sb._asp_deg() - 90.0) > 1.0e-9:
		return _fail("⭐⭐⭐ with no key on the wire the aspect must default to BROADSIDE (90°), got %.3f — a defaulted 0.0 reads as NOSE-ON, i.e. it asserts the very state this slice exists to show, on a frame that carries no evidence at all" % sb._asp_deg())
	if sb._asp_detected():
		pass    # a missing `detected` defaults to TRUE (no evidence of a loss is not a loss)
	var pair_line: String = sb._asp_aspect_text(sb._aspect_target, sb._aspect_observer, 24.0)
	if not (pair_line.contains(TID) and pair_line.contains(RAD)):
		return _fail("⭐ the aspect line must NAME THE PAIR — the same aircraft is broadside to one radar and nose-on to another in the same tick. Got '%s'" % pair_line)
	print("S49UI_PAIR   keys off '%s', prose names both: '%s'" % [sb._aspect_observer, pair_line])

	# ══ TOOTH 5 — ⭐⭐⭐ THE GAUGE ACCUMULATES, BANKS, AND **STOPS AT CPA** ═══════════════════════
	var g = _build_sandbox()
	g._on_scenario(_asp_handshake(true))
	_feed(g, 0.0, 18000.0, true, 88.0)          # held, broadside, and the window opens closing
	if g._asp_loss_s != 0.0 or not g._asp_closing:
		return _fail("the gauge must start empty and closing (%.3f s, closing=%s)" % [g._asp_loss_s, g._asp_closing])
	_feed(g, 1.0, 17700.0, false)               # …lost
	_feed(g, 5.0, 16500.0, false)
	_feed(g, 9.0, 15300.0, false)
	if absf(g._asp_run_s() - 8.0) > 1.0e-9:
		return _fail("the LIVE run must be the time since the loss began (%.4f s, want 8.0)" % g._asp_run_s())
	_feed(g, 10.0, 15000.0, true)               # …back: the run is banked
	if absf(g._asp_loss_s - 8.0) > 1.0e-9 or absf(g._asp_loss_km - 2.4) > 1.0e-9:
		return _fail("the banked run must be 8.0 s / 2.4 km (got %.4f s / %.4f km) — the seconds AND the closing range given up, which is what makes the drop-out a lesson rather than a number" % [g._asp_loss_s, g._asp_loss_km])
	if g._asp_run_s() != 0.0:
		return _fail("…and a re-detect must close the live run (%.4f s)" % g._asp_run_s())
	# ⭐⭐⭐ NOW PAST CPA, AND STILL LOST — the whole-flight-drift defect, asserted.
	_feed(g, 11.0, 15100.0, false)              # the range turns: one frame of opening ends the window
	if g._asp_closing:
		return _fail("one frame of OPENING range must close the gauge's window — the target has turned and everything after it is the outbound leg")
	for k in range(30):
		_feed(g, 12.0 + float(k), 15100.0 + 300.0 * float(k), false)
	if absf(g._asp_loss_s - 8.0) > 1.0e-9:
		return _fail("⭐⭐⭐ THE GAUGE MUST STOP AT CPA: after 30 s of being lost on the OUTBOUND leg it reads %.4f s instead of the 8.0 s it earned while closing. A whole-flight clock never stops on this scenario — the target opens nose-off and stays invisible — so it would drift above the 36.50 s the ladder quotes and print a number that is not this slice's" % g._asp_loss_s)
	var v_past: String = g._asp_verdict_label(g._asp_closing, false, g._asp_run_s(), g._asp_loss_s, 20.0)
	if not v_past.contains("CPA"):
		return _fail("…and the headline must SAY the gauge is closed rather than freezing a stale one silently. Got '%s'" % v_past)
	print("S49UI_GAUGE  8.00 s / 2.40 km banked while closing, and 30 s of being lost AFTER CPA adds nothing")

	# ══ TOOTH 6 — ⭐ RESET CLEARS ALL SIX ════════════════════════════════════════════════════════
	# ⚠⚠ THE SEVENTH TIME THIS FAMILY HAS HAD TO FIX THE STALE-INSTRUMENT-ACROSS-RESET CLASS (26's
	# ring, 35's duty, 36's two, 46's two, 47's three, 48's one). `_asp_loss_s` is a FROZEN MAXIMUM,
	# so without the clear a re-launch at the slider's FLOOR — a sphere, the arm that is essentially
	# never lost — would open displaying the previous arm's whole drop-out as though the round target
	# had done it. That is this HUD's single most misleading state, and it is the exact comparison
	# the slice exists to show going the other way.
	if g._asp_loss_s == 0.0:
		return _fail("the fixture must have the gauge LOADED before the reset tooth, or it proves nothing")
	g._on_reset_pressed()
	if not (g._asp_loss_s == 0.0 and g._asp_loss_km == 0.0 and g._asp_closing
			and g._asp_prev_range == 0.0 and is_nan(g._asp_run_t0) and g._asp_t == 0.0):
		return _fail("⭐ Reset must clear all six (loss=%.3f km=%.3f closing=%s prev=%.1f run_t0=%s t=%.3f) — a stale maximum paints a re-launched SPHERE with the previous arm's drop-out, and a stale `closing=false` leaves a fresh 18 km launch reading 'PAST CPA' forever" % [g._asp_loss_s, g._asp_loss_km, g._asp_closing, g._asp_prev_range, g._asp_run_t0, g._asp_t])
	g.free()
	print("S49UI_RESET  all six instruments cleared by the Reset button")

	# ══ TOOTH 7 — ⭐ THE VERDICT IN ALL FOUR STATES ══════════════════════════════════════════════
	var v_hold: String = sb._asp_verdict_label(true, true, 0.0, 0.0, 89.0)
	var v_gone: String = sb._asp_verdict_label(true, false, 12.4, 12.4, 22.0)
	var v_back: String = sb._asp_verdict_label(true, true, 0.0, 27.0, 61.0)
	var v_cpa: String = sb._asp_verdict_label(false, false, 4.0, 27.0, 18.0)
	for pair in [[v_hold, "HOLDING"], [v_gone, "GONE"], [v_back, "BACK"], [v_cpa, "PAST CPA"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("the verdict for that state must name '%s', got '%s'" % [pair[1], pair[0]])
	var seen := {}
	for line in [v_hold, v_gone, v_back, v_cpa]:
		if seen.has(line):
			return _fail("all four verdict states must be DISTINCT — '%s' repeats" % line)
		seen[line] = true
	# ⚠⚠ AND NONE OF THEM MAY NAME A **DETECTED %** OR A LOSS **COUNT**. The scenario header
	# disqualifies both explicitly: the count is measured NON-MONOTONE in fineness (41 → 133 → 53 →
	# 42 — a middling body chatters at the threshold while a slender one drops out and STAYS out), and
	# a detected-% mixes the outbound leg back in. Putting either in the headline would put a
	# non-monotone number where the student's eye goes first, which is how four sliders died here.
	for line in [v_hold, v_gone, v_back, v_cpa]:
		var low := str(line).to_lower()
		if low.contains("%") or low.contains(" times") or low.contains("losses"):
			return _fail("⚠⚠ the headline must never name a detected-%% or a loss COUNT — both are non-monotone in the slider. Got '%s'" % line)
	# ⭐ AND THE HOLDING STATE MUST NOT PRINT A ZERO GAUGE AS A RESULT. The sphere arm is essentially
	# never lost, and "longest closing loss 0.0 s" reads as an instrument nothing has fed rather than
	# as the finding it is (slice 48's defaulted-zero class, one widget over).
	var g_none: String = sb._asp_loss_text(true, true, 0.0, 0.0, 0.0, 0.0)
	if g_none.contains("0.0 s"):
		return _fail("⭐ the never-lost state printed a 0.0 s gauge: '%s'. On the sphere arm that IS the result, and it deserves a sentence rather than a zero" % g_none)
	# ⚠ A PLAIN LITERAL, SO THE PERCENT IS SINGLE. `%%` is an ESCAPE for the `%` OPERATOR and this
	# line applies no operator — the first run printed "detected-%%" on screen. Slice 48 hit this
	# exact defect on its own verdict line; it is the silent-format family, one level milder.
	print("S49UI_VERDICT four distinct states, none naming a detected-% or a loss count; the null gets a sentence")

	# ══ TOOTH 8 — ⚠⚠ THE WIDTH BUDGETS, IN PIXELS, AGAINST 390 AND NOT 430 ══════════════════════
	var body := [sb._asp_aspect_text(TID, RAD, 24.0),
				 sb._asp_aspect_text("interceptor1", "search_radar1", 156.0),
				 sb._asp_cost_text(0.000434, 34.45),
				 sb._asp_cost_text(4.0, 0.0),
				 sb._asp_cost_text(0.0000123, 41.48),
				 sb._asp_detect_text(true, 18000.0, 0.94),
				 sb._asp_detect_text(false, 12345.0, 0.02),
				 sb._asp_detect_text(false, 15484.0, 2.5e-4),
				 sb._asp_loss_text(true, true, 0.0, 0.0, 0.0, 0.0),
				 sb._asp_loss_text(true, false, 12.4, 3.7, 12.4, 3.7),
				 sb._asp_loss_text(true, true, 0.0, 0.0, 26.99, 5.84),
				 sb._asp_loss_text(false, false, 4.0, 1.2, 26.99, 5.84),
				 sb._asp_cure_text(0.0),
				 sb._asp_cure_text(26.99)]
	var heads := [v_hold, v_gone, v_back, v_cpa]
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > HUD_ROOM:
			return _fail("⚠⚠ HUD BODY line is %.0f px at 15 px, over the %.0f px this view leaves — the origin `vp.x − %.0f` is anchored to the RIGHT edge and the ALTITUDE TICK LABELS sit at `vp.x − 34`, so it clips at every window size and a wider window moves both. '%s'" % [w, HUD_ROOM, HUD_ORIGIN, line])
	for line in heads:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > HUD_ROOM:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px at 20 px, over %.0f — a SEPARATE and much tighter budget, because it is drawn LARGER from the same origin. '%s'" % [wh, HUD_ROOM, line])
	# ⚠ AND A MARGIN IS REQUIRED, NOT JUST A FIT. The first run passed at exactly 390.0 px of 390 —
	# one glyph from clipping, and a "pass" that a font substitution or a longer entity id would turn
	# into slice 46's defect. 12 px is about one and a half characters at this size.
	var widest_body: float = _maxpx(fnt, body, 15)
	if widest_body > HUD_ROOM - 12.0:
		return _fail("⚠ the widest body line is %.1f px of %.0f — it FITS, but with under 12 px to spare, which is one glyph from clipping. '%s'" % [widest_body, HUD_ROOM, _widest(fnt, body, 15)])
	if _maxlen(heads) > 32:
		return _fail("a headline is %d chars, over the family's measured 30 — the explanatory clause belongs in a body line" % _maxlen(heads))
	# ⚠ AND NONE MAY CONTAIN A LITERAL UNSUBSTITUTED SPECIFIER — the silent-format bug (slice 21,
	# reproduced by slice 25, and by THIS SLICE's own verifier on its first green run) shows up as
	# the FORMAT STRING itself on screen, on a run that passes.
	for line in body + heads:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	# ⚠ THE WIDEST LINE IS NAMED, NOT JUST MEASURED. The first run reported "390 px against 390" —
	# a pass sitting exactly on the limit, which is indistinguishable from a fail until you know
	# WHICH line it is and whether that line is one a real scenario can produce.
	print("S49UI_WIDTH  body ≤ %d chars / %.1f px, headline ≤ %d chars / %.1f px, against %.0f px of room (NOT 430 — the altitude labels own the rest)" % [
			_maxlen(body), _maxpx(fnt, body, 15), _maxlen(heads), _maxpx(fnt, heads, 20), HUD_ROOM])
	print("S49UI_WIDEST body: '%s' (%.1f px)   headline: '%s' (%.1f px)" %
		  [_widest(fnt, body, 15), _maxpx(fnt, body, 15), _widest(fnt, heads, 20), _maxpx(fnt, heads, 20)])

	# ══ TOOTH 9 — every key the HUD reads is present and scalar, and the WORDS follow the angle ══
	var need := [RAD + ".target_aspect_deg", RAD + ".rcs_eff_m2", RAD + ".rcs_loss_db",
				 RAD + ".target_range_m", RAD + ".pd", RAD + ".detected"]
	var tel := _asp_tel(24.0, 0.0004, 34.5, 12000.0, false, 0.02)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		var ty := typeof(tel[k])
		if ty != TYPE_FLOAT and ty != TYPE_INT and ty != TYPE_BOOL:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	# ⚠ FORE/AFT SYMMETRY IS A NAMED APPROXIMATION: σ(θ) ≡ σ(π−θ), so 156° returns the same echo as
	# 24° and the HUD must say TAIL-ON rather than nose-on. Printing "nose-on" over a fleeing target
	# would be a lie the physics does not make.
	for pair in [[0.0, "nose-on"], [24.0, "nose-on"], [50.0, "quartering"], [90.0, "broadside"],
				 [130.0, "quartering"], [156.0, "tail-on"], [180.0, "tail-on"]]:
		if sb._asp_word(float(pair[0])) != str(pair[1]):
			return _fail("⚠ %.0f° must read '%s', got '%s' — the model is fore/aft SYMMETRIC, so the words must name the tail rather than pretend it can tell the ends apart" % [pair[0], pair[1], sb._asp_word(float(pair[0]))])
	# ⚠⚠ AND A TINY-BUT-REAL Pd MUST NOT PRINT AS "0.00" — A DEFECT THE WINDOWED SHOT CAUGHT AND
	# NOTHING ELSE WOULD HAVE. Deep inside the drop-out the wire's `pd` is 2.5e-4; under a "%.2f" the
	# HUD showed "Pd 0.00", which is an IMPOSSIBILITY rather than a small number, and is identical on
	# screen to a Pd of 1e-12. Slice 8's `de_frac` defect exactly (rk4's 1e-14 and euler's 2.5e-4 both
	# printing "0.00", making the integrator button look dead).
	for pd in [2.5e-4, 1.0e-9, 0.004]:
		var line: String = sb._asp_detect_text(false, 15484.0, pd)
		if line.contains("Pd 0.00") or line.contains("Pd 0 "):
			return _fail("⚠⚠ a live Pd of %.9f printed as a zero: '%s'. That is an impossibility on screen, and indistinguishable from a Pd twelve orders of magnitude smaller" % [pd, line])
	print("S49UI_PDZERO a Pd of 2.5e-4 survives to the screen instead of rounding to an impossible 0.00")
	print("S49UI_KEYS   all %d HUD keys present and scalar; the words follow the angle through tail-on" % need.size())

	# ══ TOOTH 10 — ONE slider → set_param on the TARGET ══════════════════════════════════════════
	# ⚠ THE TARGET IS `tgt1`, NOT THE RADAR. The shape is the target's — and every telemetry key this
	# HUD reads is prefixed with the RADAR's id, so the two ids appear side by side all through this
	# slice and copying the wrong one is a live hazard rather than a theoretical one.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 12.0
	sliders[0].value_changed.emit(12.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "rcs_fineness":
			if str(d.get("target", "")) != TID:
				return _fail("⚠ the slider must address the TARGET (`%s`) — the shape is the target's, while every telemetry key here is the RADAR's. Got '%s'" % [TID, str(d.get("target", ""))])
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the target's `rcs_fineness` — got %s" % str(mock.sent))
	print("S49UI_WIRE   one slider → set_param(%s.rcs_fineness)" % TID)

	# ══ TOOTH 11 — ⭐ THE MIRROR THE OTHER WAY: a slice-2 wire keeps its propagation button ══════
	_sb2 = _build_sandbox()
	_sb2._on_scenario({
		"name": "slice2_tworay",
		"knobs": [{"target": TID, "key": "rcs_m2", "min": 0.1, "max": 20.0, "value": 4.0,
				   "label": "Target RCS (m²)"}],
		"fidelity": {"propagation": "free_space", "detection": "analytic"},
		"dt_physics": 1.0e-3,
	})
	if _sb2._aspect_view or _sb2._aspect_target != "" or _sb2._aspect_observer != "":
		return _fail("a slice-2 wire must raise no aspect marker and name no pair — it authors no shape")
	if _sb2._fid_kind != "propagation" or not _sb2._prop_btn.visible:
		return _fail("⭐ …and it must KEEP its own multipath button (got '%s' / visible=%s) — the new branch is checked FIRST in the button chain, so a bug there would steal slice 2's own lesson" % [_sb2._fid_kind, _sb2._prop_btn.visible])
	print("S49UI_PRIOR  a slice-2 wire raises no marker and keeps its free_space↔two_ray button — the new first-checked branch steals nothing")

	return _pass()

func _maxpx(fnt: Font, a: Array, sz: int) -> float:
	var m := 0.0
	for s in a:
		m = maxf(m, fnt.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	return m

func _widest(fnt: Font, a: Array, sz: int) -> String:
	var m := -1.0
	var best := ""
	for x in a:
		var w: float = fnt.get_string_size(str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if w > m:
			m = w
			best = str(x)
	return best

func _maxlen(a: Array) -> int:
	var m := 0
	for s in a:
		m = maxi(m, str(s).length())
	return m

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here and the PIXEL width
	# tooth would CRASH on it rather than fail. Assign the SAME font `_draw` uses, from the same
	# source, or the tooth measures a different typeface than the one in the photograph.
	sb._font = ThemeDB.fallback_font
	return sb

func _find_all_sliders(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_all_sliders(c))
	return out

func _pass() -> bool:
	print("S49UI OK: a target's echo is not a number it carries around — it is a property of its " +
		"SHAPE and its HEADING, and the on-screen half has to say WHICH WAY it is pointing and WHAT " +
		"THAT COSTS. ⭐⭐ THE MARKER TAKES THE HUD **AND** THE BUTTON, and the button job is a DROP: " +
		"this wire authors `propagation: free_space`, so without it the client offers MULTIPATH " +
		"LOBING on a scenario whose target vanishes because of its heading, and the drop-out gets a " +
		"second candidate explanation. ⭐⭐⭐ AND THE SHARPEST TOOTH IS THAT THE GAUGE STOPS AT CPA: " +
		"the number is the longest loss WHILE CLOSING, the target opens again nose-off and stays " +
		"invisible, and a whole-flight clock would drift above the ladder's own 36.50 s while " +
		"looking perfectly reasonable on screen.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S49UI FAIL: " + msg)
	print("S49UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb2]:
		if sb != null and is_instance_valid(sb):
			sb.free()
