extends SceneTree
# Headless UI test for the slice-47 MIDCOURSE view routing + HUD — the piece slice47_verify.gd
# can't reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT routing or the HUD this slice
# adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14)
# — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A MARKER THAT DOES **ONE** JOB, AND THAT IS THE DIFFERENCE FROM
# SLICE 46's. This wire IS slice 46's wire with a blind phase in front of it, so it raises
# `seeker_detect_view` TOO — the button is already correct and this marker must NOT take it. What it
# takes is the HUD, and the hazard is the opposite shape from every earlier marker in this family:
#   THE BUTTON must stay slice 46's `seeker_detect`, because pressing it is this slice's own A/B
#     (no horizon ⇒ no blind phase ⇒ the picture stops mattering). A marker that also grabbed
#     `_fid_kind` would be a REGRESSION, not a hole plug, and tooth 2 asserts it does not.
#   THE HUD must be this slice's, because slice 46's block would otherwise draw a link-budget
#     verdict over a missile whose first six seconds are spent flying a BELIEF. Every number on that
#     HUD is TRUE on this wire — the horizon is real, the margin is real, the authority gauge is
#     real — and the slice would be invisible anyway. This family's recurring failure, and the first
#     time the "every number true" version has been caught by ORDERING rather than by a hole.
#
# ⭐⭐⭐ AND THE SHARPEST TOOTH IN THE FILE IS THAT THE HUD READS THE **LATCHED** CUE ERROR. The
# instantaneous `head_cue_err_deg` is 0.0 the moment the head tracks — true (a tracking head has no
# cue), and it means a HUD built on it would show the number climbing all through the blind phase
# and then SNAP TO ZERO at exactly the instant the lesson happens. Tooth 4 drives that transition
# and asserts the displayed number does not move.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-47 handshake routes to _mode=airframe3d, records the marker, and the HUD is this one
#   2. ⭐⭐ THE BUTTON IS **NOT** STOLEN — it stays on slice 46's `seeker_detect`, first press `none`
#   3. ⭐⭐ THE MIRROR: strip the marker and the HUD falls back to slice 46's, which is all-true and
#      says nothing about the belief — the failure this marker exists to prevent
#   4. ⭐⭐⭐ the HUD reads the LATCHED cue error, so the headline does not snap to zero at handover
#   5. ⭐ the three client latches, fed by the core's keys and by nothing the client computes —
#      including the POST-HANDOVER authority peak, which is deliberately not slice 46's whole-flight one
#   6. ⭐ the VERDICT in its four states, and none of them names the miss
#   7. ⚠ WIDTHS: two budgets, ~55 px-checked body and ~30 headline (slice 46's shots paid for this)
#   8. every key `_draw_midcourse_hud_lines` reads is present and scalar
#   9. ONE slider → set_param on the MISSILE's `midcourse_err_gain` (not the target's rcs)
#  10. ⭐ THE MIRROR THE OTHER WAY: a slice-46 wire must NOT raise the new marker and keeps its HUD
#
# Run:  godot --headless --path clients/godot --script res://net/slice47_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb46

# `cued` drives BOTH the mode key and the instantaneous cue error, exactly as the wire does: while
# cued the two agree; once tracking, `head_cue_err_deg` goes to 0.0 and the LATCHED key holds.
func _mid_tel(cued: bool, cue_latched: float, valid: bool, auth: float) -> Dictionary:
	return {
		"m1.los_range": 6400.0 if cued else 1200.0,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 10.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": 10.0 - cue_latched,
		"m1.gimbal_rate_dps": 240.0,
		"m1.head_off_deg": cue_latched,
		"m1.head_rate_dps": 3.1,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 17.4,
		"m1.look_body_deg": 17.4,
		"m1.look_body_az_deg": -17.4,
		"m1.lead_angle_deg": 2.2,
		"m1.seeker_r_acq_m": 1436.7,
		"m1.seeker_range_margin_m": 1436.7 - (6400.0 if cued else 1200.0),
		"m1.seeker_snr_db": -6.7 if cued else 12.2,
		"m1.seeker_detect": 0.0 if cued else 1.0,
		"m1.seeker_aperture_m": 0.0548,
		# ⭐ THE SLICE'S OWN KEYS. ⚠ `head_cue_err_deg` is 0.0 once TRACKING and the latched one is
		# not — that asymmetry is the whole point of tooth 4, and this fixture reproduces it.
		"m1.head_cued": 1.0 if cued else 0.0,
		"m1.head_cue_err_deg": cue_latched if cued else 0.0,
		"m1.head_cue_err_handover_deg": cue_latched,
		"m1.midcourse_active": 1.0 if cued else 0.0,
		"m1.midcourse_tgo": 2.4 if cued else 0.0,
		"m1.midcourse_pip_err_m": 296.9,
		"m1.midcourse_pip_x": 6100.0, "m1.midcourse_pip_y": 2400.0, "m1.midcourse_pip_z": 4200.0,
		"m1.a_cmd_frac": auth,
		"m1.a_cmd": 3000.0 * auth,
		"m1.a_demand": 3000.0 * auth,
		"m1.saturated": 0.0,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.09,
		"m1.omega_q": 0.02, "m1.omega_r": 0.05,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _mid_handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice47_midcourse",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠⚠ `seeker_detect_view` IS RAISED HERE AND THAT IS THE HAZARD, not its absence: this wire
		# IS slice 46's, so 46's HUD branch is live and all of its numbers are TRUE on it. The new
		# marker has to be checked FIRST or the slice is invisible with nothing looking wrong.
		"seeker_detect_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "midcourse_err_gain", "min": 0.0, "max": 50.0, "value": 38.0,
			 "label": "LAUNCH PICTURE ERROR (m/s too slow) — watch the CUE vs the WINDOW"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["midcourse_view"] = true
	return h

func _initialize() -> void:
	print("S47UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_mid_handshake(true))

	# ══ TOOTH 1 — ROUTE ══════════════════════════════════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-47 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._midcourse_view:
		return _fail("the client must record the `midcourse_view` handshake marker")
	if not (sb._seeker_detect_view and sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠⚠ a slice-47 wire IS a slice-46 wire with a blind phase in front, so it must STILL raise seeker_detect_view / gimbal_view / gimbal_rate_view. Got %s/%s/%s" % [sb._seeker_detect_view, sb._gimbal_view, sb._gimbal_rate_view])
	if sb._radome_view or sb._seeker_fov_view or sb._gimbal_servo_view or sb._gimbal_frame_view:
		return _fail("⚠ a slice-47 wire must raise no other slice's marker — no glass, no body-fixed window, and no rung that would steal the shared button")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — slice 47 reuses the slice-23 3-D view wholesale, and DRAWS the belief point into its LOS mesh")
	print("S47UI_ROUTE  airframe3d + midcourse_view recorded beside slice 46's three markers")

	# ══ TOOTH 2 — ⭐⭐ THE BUTTON IS **NOT** STOLEN ═══════════════════════════════════════════════
	# ⚠⚠ THE OPPOSITE SHAPE FROM EVERY EARLIER MARKER IN THIS FAMILY. 37/40/46 each added a marker to
	# UN-DROP the shared button; this one must leave it exactly where 46 put it, because pressing it
	# IS this slice's control — remove the horizon and the picture error stops being read at all.
	# A slice-47 branch in the button chain would be a regression that looks like a feature.
	if sb._fid_kind != "seeker_detect":
		return _fail("⭐⭐ the button must STAY on slice 46's `seeker_detect` (got %s) — pressing it is slice 47's own A/B, and a midcourse branch in the button chain would take the one control this lesson has" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("the shared button must be visible — the press is half this lesson too")
	sb._update_fid_btn()
	if not sb._prop_btn.text.begins_with("detect:"):
		return _fail("⚠ the label must still say `detect:` — got '%s'" % sb._prop_btn.text)
	print("S47UI_BUTTON the button stays slice 46's `seeker_detect` ('%s') — this marker takes the HUD and nothing else" % sb._prop_btn.text)

	# ══ TOOTH 3 — ⭐⭐ THE MIRROR: without the marker, slice 46's HUD takes the wire ══════════════
	# ⚠⚠ AND THE FAILURE IT REPRODUCES IS THE "EVERY NUMBER TRUE" ONE, which is the worst kind this
	# family has met: slice 46's HUD is not WRONG on a slice-47 wire — the horizon, the margin and
	# the authority gauge are all live and all correct. It simply never mentions that the missile is
	# flying a BELIEF, how wrong it is, or that the whole engagement turns on one angle at one
	# instant. Nothing on screen looks broken, and the slice is invisible.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_mid_handshake(false))
	if _sb_nomarker._midcourse_view:
		return _fail("the no-marker mirror must NOT record midcourse_view")
	if not _sb_nomarker._seeker_detect_view:
		return _fail("⭐⭐ THE HOLE: without the new marker the wire must fall to slice 46's HUD — that fallback is exactly the failure being prevented, and it must be reproduced here or the mirror proves nothing")
	if _sb_nomarker._mode != sb._mode or _sb_nomarker._fid_kind != sb._fid_kind:
		return _fail("⚠ the two must share the VIEW and the BUTTON — what the marker changes is the HUD branch alone. Got %s/%s vs %s/%s" % [_sb_nomarker._mode, _sb_nomarker._fid_kind, sb._mode, sb._fid_kind])
	print("S47UI_MIRROR without the marker the wire falls to slice 46's HUD — every number on it TRUE, and the belief never mentioned")

	# ══ TOOTH 4 — ⭐⭐⭐ THE HUD READS THE **LATCHED** CUE ERROR ═══════════════════════════════════
	# The transition that would break a HUD built on the instantaneous key, driven directly: one
	# frame still blind at 9.7846°, the next tracking. `head_cue_err_deg` goes to 0.0 there (a
	# tracking head has no cue — true) and the displayed number must NOT move.
	var st := {"entities": [
		{"id": "m1", "kind": "missile", "pos": [1200.0, 400.0, 3400.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 3000.0, 4200.0]},
	]}
	sb._telemetry = _mid_tel(true, 9.7846, false, 0.0457)
	sb._airframe3d_on_state(st)
	var cue_blind: float = sb._mid_cue_deg()
	var head_blind: String = sb._midcourse_verdict_label(sb._mid_cued_now(), sb._mid_was_cued,
			sb._mid_acquired, cue_blind, sb._mid_fov_deg())
	sb._telemetry = _mid_tel(false, 9.7846, true, 0.2705)
	sb._airframe3d_on_state(st)
	var cue_after: float = sb._mid_cue_deg()
	if absf(cue_blind - 9.7846) > 1.0e-9 or absf(cue_after - 9.7846) > 1.0e-9:
		return _fail("⭐⭐⭐ the HUD must read the LATCHED `head_cue_err_handover_deg` on BOTH sides of the handover (got %.4f° blind, %.4f° after). Reading `head_cue_err_deg` gives 0.0 the moment the head tracks — the number would climb all through the blind phase and SNAP TO ZERO at exactly the instant the lesson happens" % [cue_blind, cue_after])
	if float(sb._telemetry["m1.head_cue_err_deg"]) != 0.0:
		return _fail("the fixture must reproduce the wire: the INSTANTANEOUS key is 0.0 once tracking, or this tooth is not testing the hazard")
	print("S47UI_LATCH  the displayed cue error holds %.4f° across the handover while the instantaneous key goes to 0.0" % cue_after)

	# ══ TOOTH 5 — ⭐ THE THREE LATCHES, FED BY THE CORE'S KEYS AND NOTHING ELSE ═══════════════════
	if not sb._mid_was_cued:
		return _fail("⭐ the blind-phase latch must set on a frame with `head_cued` — a missile that never flew blind has no midcourse lesson, and the HUD says so")
	if not sb._mid_acquired:
		return _fail("the acquisition latch must set on a frame with `gimbal_valid` — that conjunction is the real handover, and while blind the range half holds it at 0")
	if absf(sb._mid_auth_peak - 0.2705) > 1.0e-9:
		return _fail("the POST-HANDOVER authority peak must track the core's `a_cmd_frac` (got %.6f)" % sb._mid_auth_peak)
	# ⭐⭐ AND IT MUST NOT HAVE COUNTED THE BLIND FRAME, which is the whole difference from slice 46's
	# whole-flight peak one line above it in the source. A missile that never acquires keeps flying
	# its midcourse to CPA and reaches the law's own geometric ceiling (22.77 % of a_max) long AFTER
	# the handover would have been — a CONSEQUENCE of never acquiring rather than its cause. A
	# whole-flight gauge would paint that arm as one that had spent its budget.
	var sb_blind = _build_sandbox()
	sb_blind._on_scenario(_mid_handshake(true))
	sb_blind._telemetry = _mid_tel(true, 13.0441, false, 0.2277)
	sb_blind._airframe3d_on_state(st)
	if sb_blind._mid_auth_peak != 0.0:
		return _fail("⭐⭐ the post-handover gauge must read ZERO while the missile is still BLIND (got %.6f) — a broken arm's late midcourse command is the law's geometric ceiling, not a bill it paid at handover, and slice 46's whole-flight peak (%.6f here) is the number this one exists not to be" % [sb_blind._mid_auth_peak, sb_blind._authority_peak])
	if sb_blind._authority_peak == 0.0:
		return _fail("…while slice 46's whole-flight peak beside it DOES count that frame — if both read zero the two gauges are the same one and this tooth proves nothing")
	sb_blind.free()
	print("S47UI_INSTR  post-handover authority = %.4f (blind frames excluded); slice 46's whole-flight peak stays a separate gauge" % sb._mid_auth_peak)

	# ⭐⭐⭐ TOOTH 5b — THE GAUGE IS RANGE-GATED AT r > 200 m, AND UNGATED IT READS **BACKWARDS**.
	# Measured on the shipped wire: ungated, all SEVEN arms that acquire pin at 100.00 % of `a_max`
	# (the r → 0 endgame spikes every guidance quantity) while the two arms that NEVER ACQUIRE read
	# 22.77 %, because a missile that never handed over never flies an endgame. The 4.27 → 27.97 %
	# walk that IS this slice's gauge would be a flat ceiling with the FAILURES sitting below it.
	# ⚠ The windowed shots looked correct only because they were taken at 1050–1200 m.
	var endgame := _mid_tel(false, 9.7846, true, 1.0)
	endgame["m1.los_range"] = 150.0                     # inside the endgame
	sb._telemetry = endgame
	sb._airframe3d_on_state(st)
	if absf(sb._mid_auth_peak - 0.2705) > 1.0e-9:
		return _fail("⭐⭐⭐ the authority gauge must IGNORE frames inside r < 200 m (peak moved to %.6f on a 100 %% endgame frame) — ungated, every arm that acquires pins at 100 %% while the arms that NEVER acquire read 22.77 %%, so the gauge reads BACKWARDS. This is CLAUDE.md's standing 'DO NOT QUOTE 44 §VII.1's 100.00 %%' warning in a new widget" % sb._mid_auth_peak)
	print("S47UI_GATE   a 100 %% frame at r = 150 m leaves the peak at %.4f — the HUD and the verifier read the same gate" % sb._mid_auth_peak)

	# ⭐⭐⭐ TOOTH 5c — RESET CLEARS ALL THREE LATCHES, AND `_mid_acquired` IS THE SHARP ONE. It is a
	# ONE-WAY latch, so without the clear, pressing Reset after an arm that acquired and re-flying a
	# BROKEN one leaves the headline reading "HANDED OVER" over a missile that never acquired — the
	# single most misleading thing this HUD can display, and the exact verdict the slice exists to
	# show going the other way. ⚠ THE FIFTH TIME THIS FAMILY HAS SHIPPED THE STALE-INSTRUMENT-ACROSS-
	# RESET CLASS (26's ring, 35's duty, 36's two, 46's two), and the first four of the slice's own
	# proofs could not see it: the verifier never instantiates Sandbox, and the shot harness resets
	# BEFORE its first flight, when there is nothing stale yet.
	if not (sb._mid_was_cued and sb._mid_acquired and sb._mid_auth_peak > 0.0):
		return _fail("the fixture must have all three latches SET before the reset tooth, or it proves nothing")
	sb._on_reset_pressed()
	if sb._mid_was_cued or sb._mid_acquired or sb._mid_auth_peak != 0.0:
		return _fail("⭐⭐⭐ Reset must clear all three midcourse latches (got was_cued=%s acquired=%s peak=%.4f) — a stale `_mid_acquired` paints a re-launched BROKEN arm as HANDED OVER" % [sb._mid_was_cued, sb._mid_acquired, sb._mid_auth_peak])
	var v_after: String = sb._midcourse_verdict_label(sb._mid_cued_now(), sb._mid_was_cued,
			sb._mid_acquired, 0.0, 10.0)
	if not str(v_after).contains("NO BLIND PHASE"):
		return _fail("…and the headline must fall back to its no-history state after a reset, got '%s'" % v_after)
	print("S47UI_RESET  all three latches clear and the headline falls back to '%s'" % v_after)

	# ══ TOOTH 6 — ⭐ THE VERDICT IN ALL FOUR STATES ═══════════════════════════════════════════════
	var v_none: String = sb._midcourse_verdict_label(false, false, true, 0.0, 10.0)
	var v_blind: String = sb._midcourse_verdict_label(true, true, false, 6.2, 10.0)
	var v_ok: String = sb._midcourse_verdict_label(false, true, true, 9.7846, 10.0)
	var v_lost: String = sb._midcourse_verdict_label(false, true, false, 10.0505, 10.0)
	for pair in [[v_none, "NO BLIND PHASE"], [v_blind, "BLIND"], [v_ok, "HANDED OVER"], [v_lost, "MISSED THE WINDOW"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("the verdict for that state must name '%s', got '%s'" % [pair[1], pair[0]])
	if v_none == v_blind or v_ok == v_lost or v_blind == v_ok:
		return _fail("all four verdict states must be DISTINCT — got '%s' / '%s' / '%s' / '%s'" % [v_none, v_blind, v_ok, v_lost])
	# ⚠⚠ AND NONE OF THEM MAY NAME THE MISS. Over this slider's surviving domain the miss walks
	# 0.135 → 0.124 → 0.273 → 0.314 → 1.333 → 0.692 → 2.542 m — up and down by 20× — while the
	# authority rises 6.6× monotonically. A headline built on it is exactly what killed slices 44
	# and 45, and it would read as NOISE here rather than merely as the wrong column.
	for line in [v_none, v_blind, v_ok, v_lost]:
		if str(line).to_lower().contains("miss ") or str(line).to_lower().contains("cpa"):
			return _fail("⚠⚠ the headline must NEVER name the miss — it carries no signal on this axis at all. Got '%s'" % line)
	# ⭐ THE TWO SIDES OF THE CLIFF MUST READ DIFFERENTLY FOR A QUARTER OF A DEGREE, because that is
	# what the wire does: 9.7846° arrives, 10.0505° never acquires.
	if v_ok == v_lost:
		return _fail("⭐⭐⭐ the two cliff arms differ by 0.27° and one of them never acquires — the headline must say so")
	# ⭐⭐⭐ AND THE OWNERSHIP LINE READS `midcourse_active`, **NOT** `head_cued` — A DEFECT THE
	# WINDOWED SHOT CAUGHT AND NOTHING ELSE WOULD HAVE. The two flags are gated on DIFFERENT things
	# (§6.8 item 5): the head's cue stops when the RECEIVER OPENS, the guidance arm stops when the
	# TRACKER INITIALISES. On a broken arm — the receiver hears the target, the angle gate refuses it,
	# no lock — the first has stopped and the second has not, so a line keyed off `cued` announced
	# "PN owns it now" over a missile still flying its stale belief to CPA. On the arm that carries
	# the lesson. Every other number in that photograph was correct.
	var own_blind: String = sb._midcourse_belief_text(true, true, 296.9, 2.4)
	var own_broken: String = sb._midcourse_belief_text(true, false, 318.7, 1.2)
	var own_done: String = sb._midcourse_belief_text(false, false, 296.9, 0.0)
	if own_broken == own_done:
		return _fail("⭐⭐⭐ a missile whose receiver has opened but which NEVER ACQUIRED is still flying its midcourse (`midcourse_active` = 1) — the ownership line must NOT say PN owns it. Got '%s' for both states" % own_broken)
	if str(own_broken).to_lower().contains("pn owns"):
		return _fail("⚠⚠ the broken arm's line claims PN ownership over a missile still flying its belief: '%s'" % own_broken)
	if not str(own_done).to_lower().contains("pn owns"):
		return _fail("…and the genuinely handed-over state must say so: '%s'" % own_done)
	if own_blind == own_broken:
		return _fail("blind and broken are different states and must read differently: '%s'" % own_blind)
	print("S47UI_OWNER  the ownership line reads `midcourse_active`, not `head_cued`: '%s' / '%s' / '%s'" % [own_blind, own_broken, own_done])

	print("S47UI_VERDICT four distinct states, none naming the miss; the cliff's two sides read '%s' vs '%s'" % [v_ok, v_lost])

	# ══ TOOTH 7 — ⚠ THE WIDTH BUDGETS, IN PIXELS ═════════════════════════════════════════════════
	# ⚠⚠ MEASURED IN **PIXELS**, NOT CHARACTERS, and that is slice 46's own hard-won finding: it
	# shipped a 100/96-CHARACTER tooth that passed GREEN while every body line AND every headline ran
	# off the right edge at 1152 px and again at 1920 px. The origin is `vp.x − 430` — ANCHORED TO
	# THE RIGHT EDGE — so there is no window size at which an over-wide line fits, and `° ⇒ — ⭐` are
	# one `length()` each and many pixels each.
	var body := [sb._midcourse_belief_text(true, true, 296.9, 2.4),
				 sb._midcourse_belief_text(true, false, 296.9, 2.4),
				 sb._midcourse_belief_text(false, false, 296.9, 0.0),
				 sb._midcourse_window_text(true, false, 6.2, 10.0),
				 sb._midcourse_window_text(false, true, 9.7846, 10.0),
				 sb._midcourse_window_text(false, false, 10.0505, 10.0),
				 sb._midcourse_authority_text(true, false, 0.0457, 0.0),
				 sb._midcourse_authority_text(false, true, 0.1, 0.2705),
				 sb._midcourse_authority_text(false, false, 0.0, 0.0),
				 sb._midcourse_cure_text(true, false),
				 sb._midcourse_cure_text(false, true),
				 sb._midcourse_cure_text(false, false),
				 "range 1200 m — the MISS says nothing here"]
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > 430.0:
			return _fail("⚠⚠ HUD BODY line is %.0f px wide at 15 px, over the 430 px the origin `vp.x − 430` leaves — it clips at EVERY window size, because the origin is anchored to the RIGHT edge. '%s'" % [w, line])
	for line in [v_none, v_blind, v_ok, v_lost]:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > 430.0:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px wide at 20 px, over 430 px — a SEPARATE and much tighter budget, because it is drawn LARGER from the same origin. '%s'" % [wh, line])
	if _maxlen(body) > 60:
		return _fail("a body line is %d chars — the family's measured budget is ~55 and the pixel check is the binding one, but a line this long is a smell" % _maxlen(body))
	if _maxlen([v_none, v_blind, v_ok, v_lost]) > 32:
		return _fail("a headline is %d chars, over the family's measured 30 — the explanatory clause belongs in a body line" % _maxlen([v_none, v_blind, v_ok, v_lost]))
	# ⚠ AND NONE OF THEM MAY CONTAIN A LITERAL UNSUBSTITUTED SPECIFIER — the silent-format bug
	# (slice 21, reproduced by slice 25) shows up as the FORMAT STRING itself on screen, on a GREEN run.
	for line in body:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	print("S47UI_WIDTH  body ≤ %d chars / %.0f px, headline ≤ %d chars / %.0f px, against 430 px of room" % [
			_maxlen(body), _maxpx(fnt, body, 15),
			_maxlen([v_none, v_blind, v_ok, v_lost]), _maxpx(fnt, [v_none, v_blind, v_ok, v_lost], 20)])

	# ══ TOOTH 7b — ⚠⚠ THE **OTHER** WIDGET's BUDGET, AND A WINDOWED SHOT IS WHAT FOUND IT ═════
	# Slice 46's finding was that HUD lines can be too WIDE; this wire found the same failure class in
	# the generic telemetry readout, where there are simply too MANY of them. Three columns of 18 hold
	# ~54 keys and a slice-47 wire ships ~72 (46's set plus nine midcourse keys): the third column ran
	# off the BOTTOM of a 1152×648 window, silently losing ~15 scalars, while the columns grew right
	# until they touched the `_draw` HUD's origin at `vp.x − 430`. A fourth column cannot be the
	# answer — three at their natural width already reach that origin — so the type shrinks instead,
	# which buys height AND width at once.
	var many := {}
	for i in range(72):
		many["m1.k%02d" % i] = float(i)
	sb._telemetry = many
	sb._update_readout()
	var cols := [sb._readout, sb._readout2, sb._readout3]
	var used := 0
	var fs := 0
	for c in cols:
		if c == null:
			continue
		if str(c.text) != "":
			used += 1
		fs = maxi(fs, c.get_theme_font_size("font_size"))
	if used != 3:
		return _fail("72 keys must fill all THREE columns (got %d) — the split is what keeps the panel off the HUD's origin" % used)
	if fs > 11:
		return _fail("⚠⚠ 72 keys at font %d overflow a 648 px window — the readout must shrink its type past three full columns, because there is no fourth column available (three already reach `vp.x − 430`)" % fs)
	# …and a SHORT list must NOT be shrunk: the fix is for the overflow case only, and a client-wide
	# font drop would make every earlier slice's readout smaller for no reason.
	var few := {}
	for i in range(20):
		few["m1.k%02d" % i] = float(i)
	sb._telemetry = few
	sb._update_readout()
	var fs_few: int = sb._readout.get_theme_font_size("font_size")
	if fs_few != 14:
		return _fail("a SHORT key list must keep the family's font 14 (got %d) — the shrink is for the overflow case alone" % fs_few)
	print("S47UI_READOUT 72 keys -> 3 columns at font %d (fits 648 px); 20 keys -> font %d, unchanged" % [fs, fs_few])

	# ══ TOOTH 8 — every key the HUD reads is present and scalar ═══════════════════════════════════
	var need := ["m1.head_cued", "m1.head_cue_err_handover_deg", "m1.gimbal_fov_deg",
				 "m1.midcourse_active", "m1.midcourse_tgo", "m1.midcourse_pip_err_m",
				 "m1.midcourse_pip_x", "m1.midcourse_pip_y", "m1.midcourse_pip_z",
				 "m1.a_cmd_frac", "m1.gimbal_valid", "m1.los_range"]
	var tel := _mid_tel(true, 9.7846, false, 0.0457)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		if typeof(tel[k]) != TYPE_FLOAT and typeof(tel[k]) != TYPE_INT:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	print("S47UI_KEYS   all %d HUD keys present and scalar" % need.size())

	# ══ TOOTH 9 — ONE slider → set_param on the MISSILE ═══════════════════════════════════════════
	# ⚠ THE TARGET OF THE `set_param` IS `m1`, NOT `tgt1`. Slice 46's slider was the TARGET's own RCS;
	# this one is the MISSILE's BELIEF about the target. A verifier or client that copies 46's call
	# site verbatim sends a knob the server refuses by name — loud, and therefore survivable — but the
	# reverse would not be, so the entity is asserted here and not just the key.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 39.0
	sliders[0].value_changed.emit(39.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "midcourse_err_gain":
			if str(d.get("target", "")) != "m1":
				return _fail("⚠ the slider must address the MISSILE (`m1`), not the target — the belief is the missile's. Got '%s'" % str(d.get("target", "")))
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the missile's `midcourse_err_gain` — got %s" % str(mock.sent))
	print("S47UI_WIRE   one slider → set_param(m1.midcourse_err_gain) — the MISSILE's belief, not the target's rcs")

	# ══ TOOTH 10 — ⭐ THE MIRROR THE OTHER WAY: a slice-46 wire keeps its own HUD ═════════════════
	_sb46 = _build_sandbox()
	var h46 := {
		"name": "slice46_horizon", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "seeker_detect_view": true, "gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [{"target": "tgt1", "key": "rcs_m2", "min": 0.0001, "max": 1.0, "value": 0.001,
				   "log": true, "label": "TARGET RCS"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	_sb46._on_scenario(h46)
	if _sb46._midcourse_view:
		return _fail("a slice-46 wire must NOT raise `midcourse_view` — it authors no midcourse anchor")
	if _sb46._fid_kind != "seeker_detect":
		return _fail("⭐ …and it must keep its own button (got %s) — the new branch is checked FIRST at both HUD sites, so a bug there would steal slice 46's own wire" % _sb46._fid_kind)
	print("S47UI_PRIOR  a slice-46 wire raises no midcourse marker and keeps its HUD — the new first-checked branch steals nothing")

	return _pass()

func _maxpx(fnt: Font, a: Array, sz: int) -> float:
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
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here and the PIXEL width
	# tooth crashes on it rather than failing. Assign the SAME font `_draw` uses, from the same
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
	print("S47UI OK: a missile that cannot see its target flies on ONE SNAPSHOT AND A LINE, and " +
		"being told wrong costs nothing visible until the receiver opens — then it is paid all at " +
		"once. ⭐⭐⭐ THE CLIFF IS THE WINDOW: the handover error crosses the authored 10° detector " +
		"window between 38 and 39 m/s of picture error, and the engagement flips THERE. ⭐⭐ THE " +
		"CLIENT HALF IS A MARKER THAT TAKES THE HUD AND **NOT** THE BUTTON, which is the opposite " +
		"shape from 37/40/46: this wire IS slice 46's, so the button is already the right one and " +
		"pressing it is this slice's own control (no horizon ⇒ no blind phase ⇒ the picture stops " +
		"mattering). What it must not inherit is 46's HUD, whose every number is TRUE here and " +
		"which never mentions the belief — the 'all-true and invisible' failure, caught by ORDERING " +
		"rather than by a hole. ⭐⭐⭐ AND THE HUD READS THE **LATCHED** CUE ERROR: the " +
		"instantaneous key is 0.0 the moment the head tracks, so a HUD built on it would snap to " +
		"zero at exactly the instant the lesson happens. ⚠ The authority gauge excludes the blind " +
		"frames, because a broken arm's late midcourse command is the law's geometric ceiling and " +
		"not a bill it paid at handover.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S47UI FAIL: " + msg)
	print("S47UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb46]:
		if sb != null and is_instance_valid(sb):
			sb.free()
