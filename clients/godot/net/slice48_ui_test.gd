extends SceneTree
# Headless UI test for the slice-48 SEARCH view routing + HUD — the piece slice48_verify.gd cannot
# reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn smoke-load
# proves the scene loads. Neither exercises the CLIENT routing or the HUD this slice adds, and
# ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14) — which is
# why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐ THE MARKER DOES **ONE** JOB, the slice-47 shape rather than 37/40/46's. This wire IS slice 47's
# wire (which IS slice 46's) with the trunnion widened and a search pattern on the head, so it raises
# `midcourse_view` and `seeker_detect_view` TOO:
#   THE BUTTON must stay slice 46's `seeker_detect`, because pressing it is still this slice's own
#     A/B (no horizon ⇒ no blind phase ⇒ nothing to search for).
#   THE HUD must be this slice's, because slice 47's block would otherwise draw the CUE ERROR over a
#     missile whose whole story is what it did AFTER that cue turned out to be wrong. Every number on
#     47's HUD is TRUE here — the belief is real, the cue error is real, the window is real — and the
#     slice would be invisible anyway. The family's recurring failure, caught by ORDERING.
#   THE 3-D SITE stays slice 47's on purpose: the magenta segment to the believed intercept point is
#     exactly what the head is sweeping ABOUT, so it becomes the CENTRE OF THE SEARCH rather than a
#     leftover, and a slice-48 branch there would redraw the same line.
#
# ⭐⭐⭐ AND THE SHARPEST TOOTH IN THE FILE IS THAT **A HEAD THAT NEVER LOOKED IS NOT A SEARCH THAT
# FAILED.** At ρ = 0 the anchor is authored and the head does not sweep at all — that is THE NULL,
# exactly what ships without this slice, and it is the arm the showcase opens on. A headline that
# said "NEVER FOUND IT" there would credit the missile with having looked.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-48 handshake routes to _mode=airframe3d, records the marker beside 46's and 47's
#   2. ⭐⭐ THE BUTTON IS **NOT** STOLEN — it stays on slice 46's `seeker_detect`
#   3. ⭐⭐ THE MIRROR: strip the marker and the HUD falls back to slice 47's, which is all-true and
#      never mentions the sweep — the failure this marker exists to prevent
#   4. ⭐⭐⭐ THE NULL READS DIFFERENTLY FROM A FAILED SEARCH (ρ = 0 vs a sweep that ran out of time)
#   5. ⭐ the ONE new latch, fed by the core's key; the other three are slice 47's, READ not twinned
#   6. ⭐ the VERDICT in its five states, all distinct, none naming the miss
#   7. ⚠ WIDTHS: two budgets, ~55 px-checked body and ~30 headline (slice 46's shots paid for this)
#   8. every key `_draw_search_hud_lines` reads is present and scalar — and the −1.0 SENTINEL never
#      reaches the screen as a time
#   9. ONE slider → set_param on the MISSILE's `seeker_search_rate_dps`
#  10. ⭐ THE MIRROR THE OTHER WAY: a slice-47 wire must NOT raise the new marker and keeps its HUD
#
# Run:  godot --headless --path clients/godot --script res://net/slice48_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb47

# The fixture reproduces the wire's own shape: while SEARCHING the window is refusing the target
# (`gimbal_valid` 0) and the deficit is live; once found, the search keys freeze and the latched
# `search_t_lock_s` holds. ⚠ `search_t_lock_s` is −1.0 until a lock — never 0.0, which is a real
# value (a search that found it on its first tick).
func _srch_tel(searching: bool, deficit: float, valid: bool, auth: float,
			   t_lock: float, rate: float) -> Dictionary:
	return {
		"m1.los_range": 3037.0 if searching else 1200.0,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 10.0,
		"m1.gimbal_stop_deg": 45.0,
		"m1.gimbal_fov_margin_deg": -deficit,
		"m1.gimbal_rate_dps": 240.0,
		"m1.head_off_deg": 10.0 + deficit,
		"m1.head_rate_dps": 60.0,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 22.4,
		"m1.look_body_deg": 22.4,
		"m1.look_body_az_deg": -22.4,
		"m1.lead_angle_deg": 2.2,
		"m1.seeker_r_acq_m": 3037.0,
		"m1.seeker_range_margin_m": 100.0,
		"m1.seeker_snr_db": 12.2,
		"m1.seeker_detect": 1.0,
		"m1.seeker_aperture_m": 0.0548,
		# slice 47's keys — this wire authors the midcourse anchor, so they all ship, and this HUD
		# READS the latches they feed rather than minting twins (convention 7: one source, no drift).
		"m1.head_cued": 0.0,
		"m1.head_cue_err_deg": 0.0,
		"m1.head_cue_err_handover_deg": 11.337,
		"m1.midcourse_active": 0.0 if valid else 1.0,
		"m1.midcourse_tgo": 1.2,
		"m1.midcourse_pip_err_m": 697.0,
		"m1.midcourse_pip_x": 6100.0, "m1.midcourse_pip_y": 2400.0, "m1.midcourse_pip_z": 4200.0,
		# ⭐ THE SLICE'S OWN KEYS.
		"m1.head_searching": 1.0 if searching else 0.0,
		"m1.search_offset_deg": -12.4 if searching else 0.0,
		"m1.search_deficit_deg": deficit if searching else 0.0,
		"m1.search_elapsed_s": 0.42 if searching else 1.02,
		"m1.search_t_lock_s": t_lock,
		"m1.search_rate_dps": rate,
		"m1.search_coverage_deg": 25.0,
		"m1.a_cmd_frac": auth,
		"m1.a_cmd": 3000.0 * auth,
		"m1.a_demand": 3000.0 * auth,
		"m1.saturated": 0.0,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.09,
		"m1.omega_q": 0.02, "m1.omega_r": 0.05,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

# The BLIND frame — the head is still cued on the belief, which is what sets slice 47's `_mid_was_cued`
# latch, and this HUD's headline is built on it (a wire with no blind phase has nothing to search for).
func _blind_tel() -> Dictionary:
	var t := _srch_tel(false, 0.0, false, 0.03, -1.0, 60.0)
	t["m1.head_cued"] = 1.0
	t["m1.head_cue_err_deg"] = 8.4
	t["m1.seeker_detect"] = 0.0
	t["m1.gimbal_valid"] = 0.0
	t["m1.los_range"] = 6400.0
	t["m1.midcourse_active"] = 1.0
	return t

func _srch_handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice48_search",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠⚠ BOTH OF THE EARLIER MARKERS ARE RAISED HERE AND THAT IS THE HAZARD, not their absence:
		# this wire IS slice 47's, so 47's HUD branch is live and all of its numbers are TRUE on it.
		# The new marker has to be checked FIRST or the slice is invisible with nothing looking wrong.
		"seeker_detect_view": true,
		"midcourse_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "seeker_search_rate_dps", "min": 0.0, "max": 240.0, "value": 0.0,
			 "label": "SEEKER SWEEP RATE (deg/s) — watch t_lock and the AUTHORITY LEFT"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["search_view"] = true
	return h

func _initialize() -> void:
	print("S48UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_srch_handshake(true))

	# ══ TOOTH 1 — ROUTE ══════════════════════════════════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-48 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._search_view:
		return _fail("the client must record the `search_view` handshake marker")
	if not (sb._seeker_detect_view and sb._midcourse_view and sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠⚠ a slice-48 wire IS a slice-47 wire (which IS slice 46's) with a search on the head, so it must STILL raise seeker_detect_view / midcourse_view / gimbal_view / gimbal_rate_view. Got %s/%s/%s/%s" % [sb._seeker_detect_view, sb._midcourse_view, sb._gimbal_view, sb._gimbal_rate_view])
	if sb._radome_view or sb._seeker_fov_view or sb._gimbal_servo_view or sb._gimbal_frame_view:
		return _fail("⚠ a slice-48 wire must raise no other slice's marker — no glass, no body-fixed window, and no rung that would steal the shared button")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — this wire keeps slice 47's belief segment, which is the CENTRE the head sweeps about")
	print("S48UI_ROUTE  airframe3d + search_view recorded beside slice 46's and 47's markers")

	# ══ TOOTH 2 — ⭐⭐ THE BUTTON IS **NOT** STOLEN ═══════════════════════════════════════════════
	if sb._fid_kind != "seeker_detect":
		return _fail("⭐⭐ the button must STAY on slice 46's `seeker_detect` (got %s) — pressing it is still this slice's own A/B, and a search branch in the button chain would take the one control this lesson has" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("the shared button must be visible — the press is half this lesson too")
	sb._update_fid_btn()
	if not sb._prop_btn.text.begins_with("detect:"):
		return _fail("⚠ the label must still say `detect:` — got '%s'" % sb._prop_btn.text)
	print("S48UI_BUTTON the button stays slice 46's `seeker_detect` ('%s') — this marker takes the HUD and nothing else" % sb._prop_btn.text)

	# ══ TOOTH 3 — ⭐⭐ THE MIRROR: without the marker, slice 47's HUD takes the wire ══════════════
	# ⚠⚠ THE "EVERY NUMBER TRUE" FAILURE AGAIN, one slice further on: slice 47's HUD is not WRONG on
	# a slice-48 wire — the belief is real, the latched cue error is real, the window is real. It
	# simply never says that the head is SWEEPING, how much gap is left to cover, or that the clock
	# being spent is the engagement's. Nothing on screen looks broken, and the slice is invisible.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_srch_handshake(false))
	if _sb_nomarker._search_view:
		return _fail("the no-marker mirror must NOT record search_view")
	if not _sb_nomarker._midcourse_view:
		return _fail("⭐⭐ THE HOLE: without the new marker the wire must fall to slice 47's HUD — that fallback is exactly the failure being prevented, and it must be reproduced here or the mirror proves nothing")
	if _sb_nomarker._mode != sb._mode or _sb_nomarker._fid_kind != sb._fid_kind:
		return _fail("⚠ the two must share the VIEW and the BUTTON — what the marker changes is the HUD branch alone. Got %s/%s vs %s/%s" % [_sb_nomarker._mode, _sb_nomarker._fid_kind, sb._mode, sb._fid_kind])
	print("S48UI_MIRROR without the marker the wire falls to slice 47's HUD — every number on it TRUE, and the sweep never mentioned")

	# ══ TOOTH 4 — ⭐⭐⭐ THE NULL IS NOT A FAILED SEARCH ═══════════════════════════════════════════
	# The showcase OPENS at ρ = 0, where the anchor is authored and the head never sweeps: that is
	# what ships without this slice. Drive both histories through the real latch path and require the
	# headline to tell them apart.
	var st := {"entities": [
		{"id": "m1", "kind": "missile", "pos": [1200.0, 400.0, 3400.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 3000.0, 4200.0]},
	]}
	var sb_null = _build_sandbox()
	sb_null._on_scenario(_srch_handshake(true))
	sb_null._telemetry = _blind_tel()                       # a real blind phase…
	sb_null._airframe3d_on_state(st)
	sb_null._telemetry = _srch_tel(false, 1.337, false, 0.0, -1.0, 0.0)   # …and a head that never swept
	sb_null._airframe3d_on_state(st)
	if not sb_null._mid_was_cued:
		return _fail("the null fixture must still have flown BLIND — otherwise the headline falls to 'NO BLIND PHASE' and this tooth proves nothing")
	if sb_null._srch_was_searching:
		return _fail("⭐⭐⭐ at ρ = 0 the head must NEVER be recorded as searching — the branch is gated on ρ > 0 as well as on the anchor, and the NULL must be the shipped wire")
	var v_null: String = sb_null._search_verdict_label(sb_null._mid_was_cued, sb_null._srch_was_searching,
			sb_null._srch_searching_now(), sb_null._mid_acquired, sb_null._srch_deficit_deg(),
			sb_null._srch_t_lock_s())
	var sb_lost = _build_sandbox()
	sb_lost._on_scenario(_srch_handshake(true))
	sb_lost._telemetry = _blind_tel()
	sb_lost._airframe3d_on_state(st)
	sb_lost._telemetry = _srch_tel(true, 1.337, false, 0.0, -1.0, 36.0)   # …a sweep that RAN
	sb_lost._airframe3d_on_state(st)
	sb_lost._telemetry = _srch_tel(false, 0.0, false, 0.0, -1.0, 36.0)    # …and ran out of engagement
	sb_lost._airframe3d_on_state(st)
	if not sb_lost._srch_was_searching:
		return _fail("the failed-search fixture must have recorded a sweep, or the pair below is not a pair")
	var v_lost: String = sb_lost._search_verdict_label(sb_lost._mid_was_cued, sb_lost._srch_was_searching,
			sb_lost._srch_searching_now(), sb_lost._mid_acquired, sb_lost._srch_deficit_deg(),
			sb_lost._srch_t_lock_s())
	if v_null == v_lost:
		return _fail("⭐⭐⭐ a head that NEVER LOOKED and a search that ran out of time must read differently — both say '%s'. The first is the slider's floor and the shipped wire; the second is a search that was too slow, and calling the null 'never found it' credits the missile with having looked" % v_null)
	if str(v_lost).to_lower().contains("not searching"):
		return _fail("…and the FAILED search must not be described as one that never looked: '%s'" % v_lost)
	# …and the body lines must part company too, not just the headline.
	var mech_null: String = sb_null._search_sweep_text(false, false, 0.0, 25.0, 0.0, 0.0)
	var mech_lost: String = sb_lost._search_sweep_text(true, false, 36.0, 25.0, 0.0, 2.04)
	if mech_null == mech_lost:
		return _fail("the mechanism line must distinguish a head that cannot look around from one that has finished looking")
	sb_null.free(); sb_lost.free()
	print("S48UI_NULL   ρ = 0 reads '%s'; a sweep that ran out of time reads '%s'" % [v_null, v_lost])

	# ══ TOOTH 5 — ⭐ THE ONE NEW LATCH, AND THE THREE IT DELIBERATELY DOES NOT TWIN ═══════════════
	sb._telemetry = _blind_tel()
	sb._airframe3d_on_state(st)
	sb._telemetry = _srch_tel(true, 1.337, false, 0.0, -1.0, 60.0)
	sb._airframe3d_on_state(st)
	if not sb._srch_was_searching:
		return _fail("⭐ the search latch must set on a frame carrying `head_searching` = 1")
	if not sb._mid_was_cued:
		return _fail("the blind-phase latch is slice 47's and this HUD READS it — a missile that never flew blind has nothing to search for")
	sb._telemetry = _srch_tel(false, 0.0, true, 0.9037, 1.023, 60.0)
	sb._airframe3d_on_state(st)
	if not sb._mid_acquired:
		return _fail("the acquisition latch is slice 47's `gimbal_valid` one and this HUD READS it — a second 'did it acquire' instrument is convention 7's exact failure")
	if absf(sb._mid_auth_peak - 0.9037) > 1.0e-9:
		return _fail("the POST-HANDOVER authority peak must track the core's `a_cmd_frac` (got %.6f)" % sb._mid_auth_peak)
	# ⭐⭐⭐ AND RESET CLEARS THE NEW LATCH — the SIXTH time this family has had to fix the
	# stale-instrument-across-reset class. Without it, a re-launch at ρ = 0 (the NULL, the arm the
	# showcase opens on) would display "NEVER FOUND IT" as though the head had looked.
	if not sb._srch_was_searching:
		return _fail("the fixture must have the latch SET before the reset tooth, or it proves nothing")
	sb._on_reset_pressed()
	if sb._srch_was_searching or sb._mid_was_cued or sb._mid_acquired or sb._mid_auth_peak != 0.0:
		return _fail("⭐⭐⭐ Reset must clear the search latch AND slice 47's three (got searched=%s cued=%s acquired=%s peak=%.4f) — a stale one paints a re-launched NULL as a search that failed" % [sb._srch_was_searching, sb._mid_was_cued, sb._mid_acquired, sb._mid_auth_peak])
	print("S48UI_LATCH  one new latch, three read from slice 47, and Reset clears all four")

	# ══ TOOTH 6 — ⭐ THE VERDICT IN ALL FIVE STATES ═══════════════════════════════════════════════
	var v_none: String = sb._search_verdict_label(false, false, false, true, 0.0, -1.0)
	var v_frozen: String = sb._search_verdict_label(true, false, false, false, 1.337, -1.0)
	var v_hunt: String = sb._search_verdict_label(true, true, true, false, 1.337, -1.0)
	var v_found: String = sb._search_verdict_label(true, true, false, true, 0.0, 1.023)
	var v_slow: String = sb._search_verdict_label(true, true, false, false, 2.4, -1.0)
	for pair in [[v_none, "NO BLIND PHASE"], [v_frozen, "NOT SEARCHING"], [v_hunt, "SEARCHING"],
				 [v_found, "FOUND IT"], [v_slow, "NEVER FOUND IT"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("the verdict for that state must name '%s', got '%s'" % [pair[1], pair[0]])
	var seen := {}
	for line in [v_none, v_frozen, v_hunt, v_found, v_slow]:
		if seen.has(line):
			return _fail("all five verdict states must be DISTINCT — '%s' repeats" % line)
		seen[line] = true
	# ⚠⚠ AND NONE OF THEM MAY NAME THE MISS. On this wire a lock that arrives too late reads as a
	# clean 677 m "miss" that says nothing about what went wrong, and the arms below the floor all
	# miss by exactly the same 1039.88 m whatever the slider is doing. A headline built on it is what
	# killed slices 44 and 45.
	for line in [v_none, v_frozen, v_hunt, v_found, v_slow]:
		if str(line).to_lower().contains("miss ") or str(line).to_lower().contains("cpa"):
			return _fail("⚠⚠ the headline must NEVER name the miss — it carries no signal on this axis. Got '%s'" % line)
	# ⭐ AND THE −1.0 SENTINEL MUST NEVER REACH THE SCREEN AS A TIME. `search_t_lock_s` is −1.0 until
	# a lock happens, which is the state EVERY arm below the floor is in for the whole flight.
	for line in [v_none, v_frozen, v_hunt, v_slow,
				 sb._search_gap_text(true, false, false, 0.0, 2.4, -1.0),
				 sb._search_gap_text(false, false, false, 0.0, 1.337, -1.0)]:
		if str(line).contains("-1.0") or str(line).contains("-1 s"):
			return _fail("⭐ the never-locked SENTINEL (−1.0) reached the screen as a time: '%s'" % line)
	# ⭐⭐⭐ AND NEITHER MAY A DEFAULTED **ZERO** REACH THE GAP LINE — A DEFECT THE WINDOWED SHOT
	# CAUGHT AND NOTHING ELSE WOULD HAVE. `search_deficit_deg` is LIVE and honestly 0.0 whenever the
	# head is not sweeping, so the first version of this HUD printed "gap 0.00° beyond the window" on
	# the arm the showcase OPENS ON — a frozen head, 1.34° outside its window and falling further
	# behind every tick, described on screen as sitting exactly on the rim. The two non-sweeping
	# states fall back to the LATCHED handover gap and say so.
	for pair in [[sb._search_gap_text(false, false, false, 0.0, 1.337, -1.0), "1.34"],
				 [sb._search_gap_text(true, false, false, 0.0, 1.337, -1.0), "1.34"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("⭐⭐⭐ a NON-SWEEPING state must show the LATCHED handover gap, not the live deficit's honest 0.0 — got '%s'" % pair[0])
		if str(pair[0]).contains("0.00"):
			return _fail("⭐⭐⭐ the gap line printed a DEFAULTED ZERO as a gap: '%s'. On the null arm the target is 1.34° outside the window, and a 0.00° reads as sitting exactly on the rim" % pair[0])
	print("S48UI_GAPZERO the two non-sweeping states show the latched handover gap, never the live 0.0")

	print("S48UI_VERDICT five distinct states, none naming the miss, and the −1 sentinel never printed as a time")

	# ══ TOOTH 7 — ⚠ THE WIDTH BUDGETS, IN PIXELS ═════════════════════════════════════════════════
	# ⚠⚠ MEASURED IN **PIXELS**, NOT CHARACTERS — slice 46 shipped a 100/96-CHARACTER tooth that
	# passed GREEN while every body line AND every headline ran off the right edge at 1152 px and
	# again at 1920 px. The origin is `vp.x − 430`, ANCHORED TO THE RIGHT EDGE, so there is no window
	# size at which an over-wide line fits, and `° ± ⇒ —` are one `length()` each and many pixels each.
	var body := [sb._search_sweep_text(false, false, 0.0, 25.0, 0.0, 0.0),
				 sb._search_sweep_text(true, false, 60.0, 25.0, 0.0, 1.02),
				 sb._search_sweep_text(true, true, 240.0, 25.0, -24.9, 12.34),
				 sb._search_gap_text(false, false, false, 0.0, 1.337, -1.0),
				 sb._search_gap_text(true, true, false, 2.437, 1.337, -1.0),
				 sb._search_gap_text(true, false, false, 0.0, 1.337, -1.0),
				 sb._search_gap_text(true, false, true, 0.0, 1.337, 12.345),
				 sb._search_authority_text(true, false, 0.0, 0.0),
				 sb._search_authority_text(false, true, 0.903, 1.0),
				 sb._search_authority_text(false, false, 0.0, 0.0),
				 sb._search_cure_text(false, false),
				 sb._search_cure_text(true, false),
				 sb._search_cure_text(true, true),
				 "range 1200 m — the MISS says nothing here"]
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > 430.0:
			return _fail("⚠⚠ HUD BODY line is %.0f px wide at 15 px, over the 430 px the origin `vp.x − 430` leaves — it clips at EVERY window size, because the origin is anchored to the RIGHT edge. '%s'" % [w, line])
	var heads := [v_none, v_frozen, v_hunt, v_found, v_slow]
	for line in heads:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > 430.0:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px wide at 20 px, over 430 px — a SEPARATE and much tighter budget, because it is drawn LARGER from the same origin. '%s'" % [wh, line])
	if _maxlen(body) > 60:
		return _fail("a body line is %d chars — the family's measured budget is ~55" % _maxlen(body))
	if _maxlen(heads) > 32:
		return _fail("a headline is %d chars, over the family's measured 30 — the explanatory clause belongs in a body line" % _maxlen(heads))
	# ⚠ AND NONE MAY CONTAIN A LITERAL UNSUBSTITUTED SPECIFIER — the silent-format bug (slice 21,
	# reproduced by slice 25) shows up as the FORMAT STRING itself on screen, on a GREEN run.
	for line in body + heads:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	print("S48UI_WIDTH  body ≤ %d chars / %.0f px, headline ≤ %d chars / %.0f px, against 430 px of room" % [
			_maxlen(body), _maxpx(fnt, body, 15), _maxlen(heads), _maxpx(fnt, heads, 20)])

	# ══ TOOTH 7b — ⚠⚠ THE READOUT MUST **FIT**, AND A WINDOWED SHOT IS WHAT CAUGHT IT ════════════
	# Slice 47 fixed this widget once, with a single-step 14 → 11 shrink sized on its own ~72 keys
	# (24 rows × 15 px = 360 against 388 px of room). This wire ships SEVEN MORE keys — 27 rows ×
	# 15 = 405 — so the last row of every column printed straight through the §12 approximation
	# badge at the foot of the panel. ⭐ A HARD-CODED STEP GUARANTEES THE NEXT SLICE RE-OPENS IT, so
	# the shrink now SOLVES for the size that fits, and this tooth asserts the fit rather than the
	# step. ⚠ Height only: three columns at their natural width already reach the HUD's origin at
	# `vp.x − 430`, so a fourth column is not available and DOWN is the only direction left.
	var many := {}
	for i in range(80):
		many["m1.k%02d" % i] = float(i)
	sb._telemetry = many
	sb._update_readout()
	var cols := [sb._readout, sb._readout2, sb._readout3]
	var used := 0
	var fs := 0
	var rows_max := 0
	for c in cols:
		if c == null:
			continue
		if str(c.text) != "":
			used += 1
			rows_max = maxi(rows_max, str(c.text).split("
").size())
		fs = maxi(fs, c.get_theme_font_size("font_size"))
	if used != 3:
		return _fail("80 keys must fill all THREE columns (got %d) — the split is what keeps the panel off the HUD's origin" % used)
	# 388 px of room (a 648 px window less the panel above and the badge below), ~1.36 px of row per
	# point of font. This is the arithmetic the shrink solves, asserted from the outside.
	if float(rows_max) * float(fs) * 1.36 > 388.0:
		return _fail("⚠⚠ %d rows at font %d need %.0f px and the panel has 388 — the last row of every column prints through the §12 badge, which is exactly what the windowed shot showed" % [rows_max, fs, float(rows_max) * float(fs) * 1.36])
	# …and a SHORT list must NOT be shrunk: the fix is for the overflow case only.
	var few := {}
	for i in range(20):
		few["m1.k%02d" % i] = float(i)
	sb._telemetry = few
	sb._update_readout()
	var fs_few: int = sb._readout.get_theme_font_size("font_size")
	if fs_few != 14:
		return _fail("a SHORT key list must keep the family's font 14 (got %d) — the shrink is for the overflow case alone" % fs_few)
	print("S48UI_READOUT 80 keys -> 3 columns, %d rows at font %d = %.0f px of 388; 20 keys -> font %d" % [rows_max, fs, float(rows_max) * float(fs) * 1.36, fs_few])

	# ══ TOOTH 8 — every key the HUD reads is present and scalar ═══════════════════════════════════
	var need := ["m1.head_searching", "m1.search_offset_deg", "m1.search_deficit_deg",
				 "m1.search_elapsed_s", "m1.search_t_lock_s", "m1.search_rate_dps",
				 "m1.search_coverage_deg", "m1.gimbal_fov_deg", "m1.gimbal_valid",
				 "m1.a_cmd_frac", "m1.los_range"]
	var tel := _srch_tel(true, 1.337, false, 0.0, -1.0, 60.0)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		if typeof(tel[k]) != TYPE_FLOAT and typeof(tel[k]) != TYPE_INT:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	print("S48UI_KEYS   all %d HUD keys present and scalar" % need.size())

	# ══ TOOTH 9 — ONE slider → set_param on the MISSILE ═══════════════════════════════════════════
	# ⚠ THE TARGET IS `m1`. Slice 46's slider was the TARGET's own RCS and slice 47's was the
	# MISSILE's belief; this one is the MISSILE's own seeker. Copying 46's call site verbatim sends a
	# knob the server refuses by name — loud, and therefore survivable — but the reverse would not be.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 60.0
	sliders[0].value_changed.emit(60.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "seeker_search_rate_dps":
			if str(d.get("target", "")) != "m1":
				return _fail("⚠ the slider must address the MISSILE (`m1`) — the search is the missile's seeker. Got '%s'" % str(d.get("target", "")))
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the missile's `seeker_search_rate_dps` — got %s" % str(mock.sent))
	print("S48UI_WIRE   one slider → set_param(m1.seeker_search_rate_dps)")

	# ══ TOOTH 10 — ⭐ THE MIRROR THE OTHER WAY: a slice-47 wire keeps its own HUD ═════════════════
	_sb47 = _build_sandbox()
	var h47 := {
		"name": "slice47_midcourse", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "seeker_detect_view": true, "midcourse_view": true,
		"gimbal_view": true, "gimbal_rate_view": true,
		"knobs": [{"target": "m1", "key": "midcourse_err_gain", "min": 0.0, "max": 50.0,
				   "value": 38.0, "label": "LAUNCH PICTURE ERROR"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	_sb47._on_scenario(h47)
	if _sb47._search_view:
		return _fail("a slice-47 wire must NOT raise `search_view` — it authors no search anchor")
	if not _sb47._midcourse_view:
		return _fail("⭐ …and it must keep its own HUD marker — the new branch is checked FIRST at both text sites, so a bug there would steal slice 47's own wire")
	if _sb47._fid_kind != "seeker_detect":
		return _fail("⭐ …and its button too (got %s)" % _sb47._fid_kind)
	print("S48UI_PRIOR  a slice-47 wire raises no search marker and keeps its HUD — the new first-checked branch steals nothing")

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
	print("S48UI OK: a missile whose receiver opens onto empty sky can still LOOK AROUND, and what a " +
		"search really spends is not head travel but the ENGAGEMENT'S OWN CLOCK. ⭐⭐⭐ Below a sweep " +
		"rate the target is never found at all; above it the missile finds it EVERY TIME and still " +
		"misses, by 677 m falling to 32 m, because a lock that arrives late is worth almost nothing. " +
		"⭐⭐ THE CLIENT HALF IS A MARKER THAT TAKES THE HUD AND **NOT** THE BUTTON — slice 47's " +
		"shape — because this wire IS slice 47's wire and 47's HUD is all-true on it while never " +
		"mentioning the sweep. ⭐⭐⭐ AND THE SHARPEST TOOTH IS THAT A HEAD THAT NEVER LOOKED IS NOT " +
		"A SEARCH THAT FAILED: at ρ = 0 the head does not sweep at all, which is exactly what ships " +
		"without this slice and is the arm the showcase opens on.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S48UI FAIL: " + msg)
	print("S48UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb47]:
		if sb != null and is_instance_valid(sb):
			sb.free()
