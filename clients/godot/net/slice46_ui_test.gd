extends SceneTree
# Headless UI test for the slice-46 DETECTION-HORIZON view routing + HUD — the piece
# slice46_verify.gd can't reach. The verifier drives SimClient directly (the wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing or the verdict
# this slice adds, and ⚠ ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL
# (convention 14) — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A MARKER THAT DOES **BOTH** JOBS — the third of this family to
# un-drop the shared button (37's and 40's were the first two), and the FIRST whose button half is
# needed because the wire raises NO drop marker at all rather than three:
#   THE BUTTON — this wire authors NO GLASS (a radome would put slice 26's parasitic loop beside a
#     lesson about detection) so `radome_view` is absent, and the loader refuses `seeker_fov_deg`
#     beside a head so `seeker_fov_view` is absent too. BOTH of the client's drop branches fail, the
#     dispatch falls through to slice 25's `seeker_axes` cycler, and the button comes back as the
#     WRONG rung — whose other position leaves the horizon live beside slice 25's unrelated 2000 m
#     blind miss. Slice 36's own failure, and its 5th occurrence.
#   THE HUD — `gimbal_rate_view` IS raised here, so without the branch slice 35's block draws a
#     DEMAND-vs-CAP pair against a servo AUTHORED AT 240 °/s PRECISELY SO IT NEVER BINDS. Every
#     number TRUE, the verdict "servo FREE", and the link budget holding the seeker blind for the
#     first 7 seconds never mentioned.
#
# ⭐⭐⭐ AND THE HEADLINE THIS BRANCH DRAWS IS THE ONLY ONE IN THE FAMILY THAT IS **NOT** COLOURED BY A
# TRACK-LOSS LATCH. On this wire every arm above 0.0002 m² holds its track and hits, and the arm in
# the deepest trouble is the one flying at 100 % of `a_max` while still hitting — a latch-coloured
# headline would paint that cell calm, which is precisely the mistake that killed this physics at
# slice 44. The colour rides the AUTHORITY PEAK.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-46 handshake routes to _mode=airframe3d with the button VISIBLE at BOTH sites, on the
#      NEW `seeker_detect` kind
#   2. ⭐⭐ THE MIRROR: strip the marker and the button falls through to slice 25's `seeker_axes`
#   3. ⭐⭐ the AUTHORITY peak-hold and the BLIND latch are fed by the core's own keys and by nothing
#      the client computes
#   4. ⭐ the VERDICT in its four states, including the one no other branch can name
#   5. ⭐⭐ the TWO LAMPS separate ANGLE from RANGE — one lamp could not
#   6. ⚠ WIDTHS: two budgets, ~55 for body lines and ~30 for headlines (slice 38's shots paid for it)
#   7. every key `_draw_horizon_hud_lines` reads is present and scalar
#   8. ONE slider → set_param AND a button → set_fidelity, on the RIGHT key and the RIGHT ring order
#   9. ⭐ THE MIRROR THE OTHER WAY: a slice-40 wire must NOT raise the new marker and keeps its own
#
# Run:  godot --headless --path clients/godot --script res://net/slice46_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb40

func _horizon_tel(racq: float, r: float, auth: float, detect: bool) -> Dictionary:
	return {
		"m1.los_range": r,
		"m1.gimbal_valid": 1.0 if detect else 0.0,
		"m1.gimbal_fov_deg": 10.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": 8.15,
		"m1.gimbal_rate_dps": 240.0,
		"m1.head_off_deg": 1.85,
		"m1.head_rate_dps": 3.1,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 17.4,
		"m1.look_body_deg": 17.4,
		"m1.look_body_az_deg": -17.4,
		"m1.lead_angle_deg": 2.2,
		# ⭐ THE SLICE'S OWN KEYS.
		"m1.seeker_r_acq_m": racq,
		"m1.seeker_range_margin_m": racq - r,
		"m1.seeker_snr_db": 4.2 if detect else -6.7,
		"m1.seeker_detect": 1.0 if detect else 0.0,
		"m1.seeker_aperture_m": 0.0548,
		"m1.a_cmd_frac": auth,
		"m1.a_cmd": 3000.0 * auth,
		"m1.a_demand": 3000.0 * auth,
		"m1.saturated": 0.0,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.09,
		"m1.omega_q": 0.02, "m1.omega_r": 0.05,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _horizon_handshake(marker: bool, rung: String = "snr") -> Dictionary:
	var h := {
		"name": "slice46_horizon",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠⚠ THE HAZARD IS THE **ABSENCE** HERE, not the presence: no `radome_view` (no glass on this
		# wire) and no `seeker_fov_view` (refused beside a head), so BOTH drop branches fail and the
		# dispatch would reach slice 25's cycler. `gimbal_rate_view` is raised and takes the HUD.
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "tgt1", "key": "rcs_m2", "min": 0.0001, "max": 1.0, "value": 0.001,
			 "log": true, "label": "TARGET RCS (m²) — drag DOWN and watch the AUTHORITY gauge"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": rung},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["seeker_detect_view"] = true
	return h

func _initialize() -> void:
	print("S46UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_horizon_handshake(true))

	# ══ TOOTH 1 — ROUTE, and the button lands on the NEW rung ════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-46 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._seeker_detect_view:
		return _fail("the client must record the `seeker_detect_view` handshake marker")
	if not (sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠ a slice-46 wire is a gimballed rate-limited head PLUS a link budget, so it must still raise both of those markers — `gimbal_rate_view` is the one that would take the HUD. Got gim=%s rate=%s" % [sb._gimbal_view, sb._gimbal_rate_view])
	if sb._radome_view or sb._seeker_fov_view:
		return _fail("⚠⚠ a slice-46 wire must raise NEITHER drop marker — there is no glass (a radome would put slice 26's parasitic loop beside a lesson about detection) and a body-fixed window is refused beside a head. Their ABSENCE is the hazard this marker exists for. Got rad=%s fov=%s" % [sb._radome_view, sb._seeker_fov_view])
	if sb._gimbal_servo_view or sb._gimbal_frame_view:
		return _fail("⚠ a slice-46 wire must NOT raise another slice's RUNG marker — it would point the shared button at `head_servo` or `seeker_head` instead of `seeker_detect` (convention 9: one button, one lesson)")
	if not sb._prop_btn.visible:
		return _fail("⭐⭐ a slice-46 handshake must show the shared button — the press IS half the lesson (the same missile stops needing a horizon)")
	if sb._fid_kind != "seeker_detect":
		return _fail("⭐ …and it must take the NEW `_fid_kind` (got %s) — falling through to `seeker_axes` would point the button at slice 25's rung, whose other position leaves the horizon live beside an unrelated 2000 m blind miss" % sb._fid_kind)
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — slice 46 reuses the slice-23 3-D view wholesale")
	sb._update_fid_btn()
	if not (sb._prop_btn.visible and sb._prop_btn.text.contains("snr")):
		return _fail("_update_fid_btn must keep the button visible and label it with the LIVE rung, got visible=%s '%s'" % [sb._prop_btn.visible, sb._prop_btn.text])
	if not sb._prop_btn.text.begins_with("detect:"):
		return _fail("⚠ the label must say `detect:` and not `seeker:` — slice 25's arm already owns that word on the same button, and a student cycling one would read the other's name. Got '%s'" % sb._prop_btn.text)
	print("S46UI_ROUTE  airframe3d + seeker_detect_view recorded, NEITHER drop marker raised, button on the NEW kind labelled '%s'" % sb._prop_btn.text)

	# ══ TOOTH 2 — ⭐⭐ THE MIRROR: strip the marker and the button lands on the WRONG rung ═════════
	# ⚠⚠ THIS MIRROR IS THE OPPOSITE SHAPE FROM SLICE 40's, and the difference is the whole reason
	# the marker's button half is load-bearing here. There the button VANISHED (three markers dropped
	# it); here it stays VISIBLE and quietly becomes slice 25's `seeker_axes` cycler — a failure that
	# looks fine on screen, which is worse.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_horizon_handshake(false))
	if _sb_nomarker._seeker_detect_view:
		return _fail("the no-marker mirror must NOT record seeker_detect_view")
	if _sb_nomarker._fid_kind == "seeker_detect":
		return _fail("⭐⭐ THE HOLE: without `seeker_detect_view` the dispatch must NOT reach this slice's kind by accident — if it does, the marker is not what is routing and this tooth proves nothing")
	if _sb_nomarker._fid_kind != "seeker_axes":
		return _fail("⭐⭐ THE HOLE: without the marker the dispatch falls through to slice 25's `seeker_axes` cycler (got %s) — that is the failure this marker exists to prevent, and it must be reproduced here or the mirror is not testing it" % _sb_nomarker._fid_kind)
	if _sb_nomarker._mode != sb._mode:
		return _fail("⚠ the two must still share the VIEW — what the marker changes is the button and the HUD branch. Got %s/%s" % [_sb_nomarker._mode, sb._mode])
	print("S46UI_MIRROR without the marker the button stays VISIBLE and silently becomes slice 25's `seeker_axes` cycler — a failure that looks fine on screen, which is why the mirror is here")

	# ══ TOOTH 3 — ⭐⭐ THE TWO INSTRUMENTS ARE FED BY THE CORE'S KEYS AND NOTHING ELSE ═════════════
	# The peak-hold and the latch are the only client-side state this slice adds. Convention 13: the
	# core owns the RATIO (`a_cmd_frac`, because `a_max` is a comp key that is nowhere on the wire);
	# the client only remembers the largest one it has seen.
	var st := {"entities": [
		{"id": "m1", "kind": "missile", "pos": [1200.0, 400.0, 3400.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]}
	sb._telemetry = _horizon_tel(1436.7, 6400.0, 0.031, false)
	sb._airframe3d_on_state(st)
	if not sb._detect_blind:
		return _fail("⭐ the BLIND latch must set on a frame whose RANGE lamp is out — the seeker opens this flight outside its own horizon, which is the state the whole lesson is about")
	if absf(sb._authority_peak - 0.031) > 1.0e-9:
		return _fail("the authority peak must track the core's `a_cmd_frac` exactly (got %.6f)" % sb._authority_peak)
	sb._telemetry = _horizon_tel(1436.7, 1400.0, 0.2355, true)
	sb._airframe3d_on_state(st)
	if absf(sb._authority_peak - 0.2355) > 1.0e-9:
		return _fail("the peak must RISE with the live value (got %.6f)" % sb._authority_peak)
	sb._telemetry = _horizon_tel(1436.7, 900.0, 0.05, true)
	sb._airframe3d_on_state(st)
	if absf(sb._authority_peak - 0.2355) > 1.0e-9:
		return _fail("⭐ …and it must NOT fall back — a budget's question is how much was EVER needed at once, which is a maximum and not an average (slice 35's EMA answers a different question). Got %.6f" % sb._authority_peak)
	if not sb._detect_blind:
		return _fail("⚠ the latch must not clear when the horizon later opens — `was blind earlier` is a thing the HUD says, and a latch that forgot it could not")
	print("S46UI_INSTR  authority peak-holds (0.031 → 0.2355, does NOT fall back) and the blind latch REMEMBERS")

	# ══ TOOTH 4 — ⭐ THE VERDICT IN ALL FOUR STATES ═══════════════════════════════════════════════
	# ⚠ The third one is the state no other branch in this family can name: an arm that is HITTING and
	# is nonetheless in the deepest trouble on the wire, because it is spending everything it has.
	var v_off: String = sb._horizon_verdict_label(false, false, 0.031)
	var v_sees: String = sb._horizon_verdict_label(false, true, 0.2355)
	var v_spent: String = sb._horizon_verdict_label(false, true, 1.0)
	var v_blind: String = sb._horizon_verdict_label(true, true, 0.2355)
	# ⚠ THE SPENT STATE IS ASSERTED ON THE WORD, NOT ON "100%" — the headline budget is ~30 chars and
	# the NUMBER lives one line down, in `_horizon_authority_text`, where there is room for it. What the
	# headline owes is the VERDICT ("PAID IN FULL"); what it must never own is the miss (checked below).
	for pair in [[v_off, "no horizon"], [v_spent, "PAID IN FULL"], [v_blind, "BLIND"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("the verdict for that state must name '%s', got '%s'" % [pair[1], pair[0]])
	if v_sees == v_spent or v_sees == v_blind or v_off == v_sees:
		return _fail("all four verdict states must be DISTINCT — got off='%s' sees='%s' spent='%s' blind='%s'" % [v_off, v_sees, v_spent, v_blind])
	if str(v_spent).to_lower().contains("miss") or str(v_sees).to_lower().contains("miss"):
		return _fail("⚠⚠ the headline must NEVER name the miss — across this button the miss moves by less than the width of the target while the authority swings 9×, and a headline built on it is exactly what killed this physics at slice 44. Got '%s'" % v_spent)
	# …and the NUMBER the headline gave up must be present in the body line that took it over, or the
	# compression to the family's 30-char budget quietly deleted the slice's headline figure.
	if not sb._horizon_authority_text(1.0, 1.0).contains("100%"):
		return _fail("⚠⚠ the authority line must carry the '100%' the headline gave up when it was cut to the family's 30-char budget — otherwise the compression deleted the one number this slice exists to show. Got '%s'" % sb._horizon_authority_text(1.0, 1.0))
	print("S46UI_VERDICT four distinct states; the spent one names the VERDICT, the body line carries the 100%, and neither names the miss")

	# ══ TOOTH 5 — ⭐⭐ TWO LAMPS, BECAUSE ONE COULD NOT SAY WHICH LIMIT RAN OUT ════════════════════
	var lamp_ok: String = sb._horizon_lamps_text(8.15, false, false, true)
	var lamp_rng: String = sb._horizon_lamps_text(8.15, true, true, true)
	var lamp_ang: String = sb._horizon_lamps_text(-0.4, false, true, true)
	if not (lamp_rng.contains("BLIND") and lamp_ok.contains("sees")):
		return _fail("the RANGE lamp must say which state it is in — got '%s' / '%s'" % [lamp_ok, lamp_rng])
	if not lamp_ang.contains(" out"):
		return _fail("the ANGLE lamp must flag a negative margin independently of the range one — a seeker out of ANGLE needs a wider window or a faster servo, one out of RANGE needs aperture, power, integration or a bigger target. Got '%s'" % lamp_ang)
	if lamp_ok == lamp_rng or lamp_ok == lamp_ang or lamp_rng == lamp_ang:
		return _fail("the three lamp states must be distinct")
	# ⚠⚠ …AND THE RANGE LINE ONE ROW UP OWES THE SAME HONESTY, for the same reason and caught by the
	# same photograph: on `none` the core emits no detect keys at all, so the client's `.get(…, 0.0)`
	# would otherwise print a DEFAULTED horizon of 0 m and a margin of +0 m as though a test had been
	# run and passed. A line that makes no comparison must not look like one that made a favourable one.
	var rng_off: String = sb._horizon_range_text(2858.0, 0.0, 0.0, false)
	if rng_off.contains("horizon 0") or rng_off.contains("+0 m"):
		return _fail("⚠⚠ the ungated range line must NOT render the defaulted zeros as a comparison — got '%s'" % rng_off)
	if not rng_off.contains("2858"):
		return _fail("…but it must still report the RANGE, which is live on both rungs — got '%s'" % rng_off)
	print("S46UI_UNGATED range line and RANGE lamp both decline to report a test that was never run — '%s' / '%s'" % [rng_off, sb._horizon_lamps_text(9.97, false, false, false)])

	print("S46UI_LAMPS  ANGLE and RANGE report separately — '%s'" % lamp_rng)

	# ══ TOOTH 6 — ⚠ THE WIDTH BUDGETS (slice 38's windowed shots paid for these) ══════════════════
	var body := [sb._horizon_mech_text(true, 10.0, 0.0548, 1436.7),
				 sb._horizon_mech_text(false, 10.0, 0.0548, 1436.7),
				 sb._horizon_range_text(6400.0, 1436.7, -4963.3, true),
				 sb._horizon_range_text(1400.0, 1436.7, 36.7, true),
				 sb._horizon_range_text(2858.0, 0.0, 0.0, false),
				 sb._horizon_authority_text(0.2355, 1.0),
				 sb._horizon_authority_text(0.031, 0.031),
				 lamp_ok, lamp_rng, lamp_ang,
				 sb._horizon_cure_text(true), sb._horizon_cure_text(false)]
	# ⭐⭐ THE TOOTH MEASURES **PIXELS**, NOT CHARACTERS — and that is the whole finding of this
	# slice's first three windowed shots. A char budget of 100/96 passed GREEN while all five body
	# lines AND all four headlines ran off the right edge at 1152 px AND again at 1920 px. Two
	# separate reasons, both fatal to the proxy:
	#   1. THE FAMILY'S BUDGET IS 55/30 (slice 38 measured it and wrote it into its own tooth). Slice
	#      46 invented 100/96 instead of inheriting it. A budget a slice declares for itself is not a
	#      budget — the number has to come from the origin, which is `vp.x − 430`: 430 px of room,
	#      ANCHORED TO THE RIGHT EDGE, so widening the window moves the origin too and clips exactly
	#      the same. There is no window size at which a 90-char line fits.
	#   2. `⇒ ° ← | — ⭐` ARE ONE `length()` EACH AND MANY PIXELS EACH. These lines are dense with
	#      them, so the char count under-reads the real width by a further margin that varies per line.
	# ⇒ assert on `get_string_size(...).x`, at the SAME font and size `_draw_horizon_hud_lines` uses
	# (15 px body / 20 px headline), against the SAME 430 px the origin leaves. The char asserts stay
	# beside it at the family's 55/30 for consistency with slices 38/40 — but the pixel one is the one
	# that can no longer disagree with a photograph.
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > 430.0:
			return _fail("⚠⚠ HUD BODY line is %.0f px wide at 15 px, over the 430 px the origin `vp.x − 430` leaves — it clips at EVERY window size, because the origin is anchored to the RIGHT edge. '%s'" % [w, line])
	for line in [v_off, v_sees, v_spent, v_blind]:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > 430.0:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px wide at 20 px, over 430 px — a SEPARATE and much tighter budget than the body lines', because it is drawn LARGER from the same origin. '%s'" % [wh, line])
	if _maxlen(body) > 55:
		return _fail("a body line is %d chars, over the FAMILY's measured 55 (slice 38's tooth) — slice 46 must inherit that number, not declare its own" % _maxlen(body))
	if _maxlen([v_off, v_sees, v_spent, v_blind]) > 30:
		return _fail("a headline is %d chars, over the family's measured 30 — the explanatory clause belongs in a body line" % _maxlen([v_off, v_sees, v_spent, v_blind]))
	# ⚠ AND NONE OF THEM MAY CONTAIN A LITERAL `%` — the silent-format bug (slice 21, reproduced by
	# slice 25) shows up as the FORMAT STRING itself on screen, on a GREEN run.
	for line in body:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	print("S46UI_WIDTH  body ≤ %d chars / %.0f px, headline ≤ %d chars / %.0f px, against 430 px of room — no unsubstituted specifiers" % [
			_maxlen(body), _maxpx(fnt, body, 15),
			_maxlen([v_off, v_sees, v_spent, v_blind]), _maxpx(fnt, [v_off, v_sees, v_spent, v_blind], 20)])

	# ══ TOOTH 7 — every key the HUD reads is present and scalar ═══════════════════════════════════
	var need := ["m1.seeker_r_acq_m", "m1.seeker_range_margin_m", "m1.seeker_snr_db",
				 "m1.seeker_detect", "m1.seeker_aperture_m", "m1.a_cmd_frac",
				 "m1.gimbal_fov_deg", "m1.gimbal_fov_margin_deg", "m1.los_range"]
	var tel := _horizon_tel(1436.7, 1400.0, 0.2355, true)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		if typeof(tel[k]) != TYPE_FLOAT and typeof(tel[k]) != TYPE_INT:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	print("S46UI_KEYS   all %d HUD keys present and scalar" % need.size())

	# ══ TOOTH 8 — ONE slider → set_param, and the button → set_fidelity on the RIGHT key ══════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 0.0005
	sliders[0].value_changed.emit(0.0005)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "rcs_m2":
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the TARGET's `rcs_m2` — got %s" % str(mock.sent))
	mock.sent.clear()
	sb._on_seeker_detect_pressed()
	var saw_fid := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "seeker_detect":
			saw_fid = true
			# ⚠⚠ THE RING ORDER IS THE CORE'S TUPLE AND NOT THE SHOWCASE'S OPENING RUNG — the wire
			# opens on `snr` (index 1), so the FIRST press must land on `none`, the cure.
			if str(d.get("value", "")) != "none":
				return _fail("⭐ the first press on a wire that opens at `snr` must reach `none` (the cure), got '%s'" % str(d.get("value", "")))
	if not saw_fid:
		return _fail("the button must send set_fidelity on `seeker_detect` — got %s" % str(mock.sent))
	if str(sb._fidelity.get("seeker_detect", "")) != "none":
		return _fail("the client must own the DISPLAYED rung locally (the server applies it next tick)")
	sb._update_fid_btn()
	if not sb._prop_btn.text.contains("none"):
		return _fail("…and the button's label must follow it, got '%s'" % sb._prop_btn.text)
	print("S46UI_WIRE   one slider → set_param(rcs_m2); the button → set_fidelity(seeker_detect) landing on `none` first")

	# ══ TOOTH 9 — ⭐ THE MIRROR THE OTHER WAY: a slice-40 wire keeps its own routing ══════════════
	_sb40 = _build_sandbox()
	var h40 := {
		"name": "slice40_resonance", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"gimbal_rate_view": true, "gimbal_servo_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_zeta", "min": 0.05, "max": 1.0, "value": 0.10,
				   "label": "GIMBAL DAMPING"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "head_servo": "second_order"},
		"dt_physics": 1.0e-3,
	}
	_sb40._on_scenario(h40)
	if _sb40._seeker_detect_view:
		return _fail("a slice-40 wire must NOT raise `seeker_detect_view` — it authors no link budget")
	if _sb40._fid_kind != "head_servo":
		return _fail("⭐ …and it must keep its OWN kind (got %s) — the new branch is checked FIRST at all three dispatch sites, so a bug there would steal every earlier wire's button" % _sb40._fid_kind)
	print("S46UI_PRIOR  a slice-40 wire keeps `head_servo` — the new first-checked branch steals nothing")

	return _pass()

func _maxpx(fnt: Font, a: Array, sz: int) -> float:
	# The pixel twin of `_maxlen`, at the size the HUD actually draws with. Reported on the PASS line
	# so the margin against 430 px is visible in the log and not just at the moment a tooth trips.
	var m := 0.0
	for s in a:
		m = maxf(m, fnt.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	return m

func _maxlen(a: Array) -> int:
	var m := 0
	for s in a:
		m = maxi(m, str(s).length())
	return m

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here, and the PIXEL width
	# tooth (tooth 6) crashes on it rather than failing. Assign the SAME font `_draw` uses, from the
	# same source, or the tooth measures a different typeface than the one in the photograph.
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
	print("S46UI OK: slices 32/34 made 'can the seeker see it?' an ANGLE question alone; a link " +
		"budget makes it a RANGE question too, and the two halves are ONE design variable — the " +
		"window IS the beamwidth that implies the aperture that sets the reach, so `R_acq · fov` is " +
		"a constant of the design. ⭐⭐ THE CLIENT HALF IS A MARKER THAT DOES BOTH JOBS, and its " +
		"button half is load-bearing for a NEW reason: this wire raises NO drop marker at all (no " +
		"glass, and a body-fixed window is refused beside a head), so without it the button stays " +
		"VISIBLE and silently becomes slice 25's cycler — a failure that looks fine on screen. " +
		"⭐⭐⭐ AND THE HEADLINE IS THE ONLY ONE IN THIS FAMILY NOT COLOURED BY A TRACK-LOSS LATCH: " +
		"every arm above 0.0002 m² holds and hits, and the one in the deepest trouble is the one " +
		"flying at 100 % of a_max while still hitting. A latch would paint it calm — which is " +
		"exactly the reading that killed this physics at slice 44. ⭐⭐ TWO LAMPS, because a seeker " +
		"out of ANGLE needs a wider window or a faster servo while one out of RANGE needs aperture, " +
		"power, integration or a bigger target, and `gimbal_valid` is the conjunction and could " +
		"never say which. ⚠ Two width budgets pinned, and slice 40 still routes where it did.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S46UI FAIL: " + msg)
	print("S46UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb40]:
		if sb != null and is_instance_valid(sb):
			sb.free()
