extends SceneTree
# Headless UI test for the slice-52 SEARCH-WIDTH view routing + HUD — the piece slice52_verify.gd
# cannot reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT routing or the HUD this slice
# adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14)
# — which is why every line of this slice's HUD, **and the band's geometry**, is a pure helper this
# file calls.
#
# ⭐⭐⭐ THE MARKER EXISTS FOR A REASON NO EARLIER ONE IN THIS FAMILY HAD. Every previous marker
# separated wires that differed in PHYSICS. This wire IS slice 48's wire — the same missile, the
# same anchor, the same blind phase — with a different SLIDER, so it raises `search_view` too and
# that marker can no longer tell them apart. Slice 48's block is ALL TRUE here: the sweep is real,
# the gap is real, the lock time is real. What it cannot say is that the WIDTH is what is being
# dialled, that a band too narrow never reaches at any duration, or that the head is flying less
# than it was told. Every number right, and the slice invisible.
#
# ⭐⭐ THE MARKER DOES **ONE** JOB, the 47/48/50 shape: it takes the HUD and deliberately NOT the
# button. Slice 46's `seeker_detect` is still this slice's own A/B — press it and the horizon goes
# away, the missile is never blind, and there is nothing to search for at ANY width.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-52 handshake routes to _mode=airframe3d and records the marker beside 46/47/48's
#   2. ⭐⭐ THE BUTTON IS **NOT** STOLEN — it stays on slice 46's `seeker_detect`
#   3. ⭐⭐⭐ THE MIRROR: strip the marker and the HUD falls back to SLICE 48's — all-true, and
#      never a word about the width. That fallback IS the failure this marker prevents.
#   4. ⭐ NO NEW LATCH: the three this HUD reads are 47's and 48's, so Reset needs no new line
#   5. ⭐ the VERDICT in its five states, all distinct, none naming the miss, and the FLOOR's
#      verdict is a REACH failure ("too narrow") rather than slice 48's deadline ("too slow")
#   6. ⭐⭐⭐ THE BAND'S GEOMETRY — flown inside told inside travel, the ticks walking outward, the
#      clamp at the trunnion, and a negative gap collapsing to the centre
#   7. ⚠⚠ THE BAND IS SIZED FROM `search_offset_peak_deg` AND **NEVER** FROM THE COVERAGE ECHO
#      (gate 2 tooth I: the echo reports 1e9 on a NaN beside a sweep of exactly zero)
#   8. ⚠ WIDTHS: two budgets, ~55 px-checked body and ~30 headline
#   9. every key `_draw_s52_hud_lines` reads is present and scalar
#  10. ONE slider → set_param on the MISSILE's `seeker_search_coverage_deg`
#  11. ⭐ THE MIRROR THE OTHER WAY: a slice-48 wire must NOT raise the new marker and keeps its HUD
#
# Run:  godot --headless --path clients/godot --script res://net/slice52_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb48

# The fixture reproduces the wire's own shape: while SEARCHING the window is refusing the target
# (`gimbal_valid` 0) and the deficit is live; once found, the search keys freeze and the latched
# `search_t_lock_s` holds. ⚠ `search_t_lock_s` is −1.0 until a lock — never 0.0, which is a real
# value (a search that found it on its first tick).
func _s52_tel(searching: bool, deficit: float, valid: bool, auth: float,
			  t_lock: float, told: float, flown: float) -> Dictionary:
	return {
		"m1.los_range": 3037.0 if searching else 1200.0,
		"m1.closing_speed": 698.7,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 10.0,
		"m1.gimbal_stop_deg": 45.0,
		"m1.gimbal_fov_margin_deg": -deficit,
		"m1.gimbal_rate_dps": 240.0,
		"m1.head_off_deg": 10.0 + deficit,
		"m1.head_rate_dps": 60.0,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 27.5,
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
		# slice 48's keys — the anchor is authored here too, so the whole family ships.
		"m1.head_searching": 1.0 if searching else 0.0,
		"m1.search_offset_deg": -12.4 if searching else 0.0,
		"m1.search_deficit_deg": deficit if searching else 0.0,
		"m1.search_elapsed_s": 0.42 if searching else 1.02,
		"m1.search_t_lock_s": t_lock,
		"m1.search_rate_dps": 60.0,
		"m1.search_coverage_deg": 25.0,
		# ⭐ THE SLICE'S OWN THREE. `search_offset_peak_deg` is what the band is SIZED from —
		# never `search_coverage_deg`, which is the echo (tooth 7).
		"m1.search_offset_peak_deg": told,
		"m1.search_realized_peak_deg": flown,
		"m1.search_realized_deg": -0.62 * flown,
		"m1.a_cmd_frac": auth,
		"m1.a_cmd": 3000.0 * auth,
		"m1.a_demand": 3000.0 * auth,
		"m1.saturated": 0.0,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.09,
		"m1.omega_q": 0.02, "m1.omega_r": 0.05,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

# The BLIND frame — the head is still cued on the belief, which is what sets slice 47's
# `_mid_was_cued` latch, and this HUD's headline is built on it.
func _blind_tel() -> Dictionary:
	var t := _s52_tel(false, 0.0, false, 0.03, -1.0, 0.0, 0.0)
	t["m1.head_cued"] = 1.0
	t["m1.head_cue_err_deg"] = 8.4
	t["m1.seeker_detect"] = 0.0
	t["m1.gimbal_valid"] = 0.0
	t["m1.los_range"] = 6400.0
	t["m1.midcourse_active"] = 1.0
	return t

func _s52_handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice52_coverage",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠⚠ **THREE** EARLIER MARKERS ARE RAISED HERE AND THAT IS THE HAZARD, not their absence —
		# and `search_view` is the dangerous one, because slice 48's block is about the same head
		# doing the same thing and every number on it is TRUE.
		"seeker_detect_view": true,
		"midcourse_view": true,
		"search_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "seeker_search_coverage_deg", "min": 1.0, "max": 40.0,
			 "value": 25.0, "label": "SEEKER SWEEP WIDTH (deg) — too narrow never reaches it"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["search_realized_view"] = true
	return h

func _initialize() -> void:
	print("S52UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_s52_handshake(true))

	# ══ TOOTH 1 — ROUTE ══════════════════════════════════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-52 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._s52_view:
		return _fail("the client must record the `search_realized_view` handshake marker")
	if not (sb._search_view and sb._seeker_detect_view and sb._midcourse_view
			and sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠⚠ a slice-52 wire IS a slice-48 wire (which IS 47's, which IS 46's) with a different SLIDER, so it must STILL raise search_view / midcourse_view / seeker_detect_view / gimbal_view / gimbal_rate_view. Got %s/%s/%s/%s/%s" % [sb._search_view, sb._midcourse_view, sb._seeker_detect_view, sb._gimbal_view, sb._gimbal_rate_view])
	if sb._radome_view or sb._seeker_fov_view or sb._gimbal_servo_view or sb._gimbal_frame_view:
		return _fail("⚠ a slice-52 wire must raise no other slice's marker — no glass, no body-fixed window, and no rung that would steal the shared button")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — this wire keeps slice 47's belief segment, which is the CENTRE the head sweeps about")
	print("S52UI_ROUTE  airframe3d + search_realized_view recorded beside 46/47/48's markers")

	# ══ TOOTH 2 — ⭐⭐ THE BUTTON IS **NOT** STOLEN ═══════════════════════════════════════════════
	if sb._fid_kind != "seeker_detect":
		return _fail("⭐⭐ the button must STAY on slice 46's `seeker_detect` (got %s) — pressing it is still this slice's own A/B: no horizon, no blind phase, nothing to search for at ANY width" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("the shared button must be visible — the press is half this lesson too")
	sb._update_fid_btn()
	if not sb._prop_btn.text.begins_with("detect:"):
		return _fail("⚠ the label must still say `detect:` — got '%s'" % sb._prop_btn.text)
	print("S52UI_BUTTON the button stays slice 46's `seeker_detect` ('%s')" % sb._prop_btn.text)

	# ══ TOOTH 3 — ⭐⭐⭐ THE MIRROR: without the marker, SLICE 48's HUD takes the wire ════════════
	# ⚠⚠ AND THIS IS THE FIRST TIME IN THIS FAMILY THAT THE FALLBACK IS THE **IMMEDIATELY PRECEDING
	# SLICE'S OWN BLOCK ABOUT THE SAME HEAD.** Slice 48's HUD is not wrong here — it is measuring the
	# same sweep on the same wire. It simply never says that the WIDTH is the slider, that a band too
	# narrow never reaches the target at any duration, or that the head flies less than it is told.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_s52_handshake(false))
	if _sb_nomarker._s52_view:
		return _fail("the no-marker mirror must NOT record search_realized_view")
	if not _sb_nomarker._search_view:
		return _fail("⭐⭐⭐ THE HOLE: without the new marker the wire must fall to SLICE 48's HUD — that fallback is exactly the failure being prevented, and it must be reproduced here or the mirror proves nothing")
	if _sb_nomarker._mode != sb._mode or _sb_nomarker._fid_kind != sb._fid_kind:
		return _fail("⚠ the two must share the VIEW and the BUTTON — what the marker changes is the HUD branch alone. Got %s/%s vs %s/%s" % [_sb_nomarker._mode, _sb_nomarker._fid_kind, sb._mode, sb._fid_kind])
	print("S52UI_MIRROR without the marker the wire falls to slice 48's HUD — every number on it TRUE, and the WIDTH never mentioned")

	# ══ TOOTH 4 — ⭐ NO NEW LATCH: this HUD reads 47's two and 48's one ═══════════════════════════
	var st := {"entities": [
		{"id": "m1", "kind": "missile", "pos": [1200.0, 400.0, 3400.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 3000.0, 4200.0]},
	]}
	sb._telemetry = _blind_tel()
	sb._airframe3d_on_state(st)
	sb._telemetry = _s52_tel(true, 1.337, false, 0.0, -1.0, 8.0, 5.2)
	sb._airframe3d_on_state(st)
	if not (sb._mid_was_cued and sb._srch_was_searching):
		return _fail("⭐ the blind-phase latch (slice 47's) and the search latch (slice 48's) must both set — this HUD READS them and mints none of its own, which is why it adds nothing to Reset")
	sb._telemetry = _s52_tel(false, 0.0, true, 0.9037, 1.023, 25.0, 22.95)
	sb._airframe3d_on_state(st)
	if not sb._mid_acquired:
		return _fail("the acquisition latch is slice 47's `gimbal_valid` one and this HUD READS it — a second 'did it acquire' instrument is convention 7's exact failure")
	if absf(sb._mid_auth_peak - 0.9037) > 1.0e-9:
		return _fail("the POST-HANDOVER authority peak must track the core's `a_cmd_frac` (got %.6f)" % sb._mid_auth_peak)
	sb._on_reset_pressed()
	if sb._srch_was_searching or sb._mid_was_cued or sb._mid_acquired or sb._mid_auth_peak != 0.0:
		return _fail("⭐ Reset must clear the three latches this HUD reads (got searched=%s cued=%s acquired=%s peak=%.4f) — a stale one paints a re-launched floor arm as a search that succeeded" % [sb._srch_was_searching, sb._mid_was_cued, sb._mid_acquired, sb._mid_auth_peak])
	print("S52UI_LATCH  three latches READ (47's two + 48's one), none minted, and Reset clears all three")

	# ══ TOOTH 5 — ⭐ THE VERDICT IN ALL FIVE STATES ═══════════════════════════════════════════════
	var v_none: String = sb._s52_verdict_label(false, false, false, true, 25.0, 0.0, -1.0)
	var v_frozen: String = sb._s52_verdict_label(true, false, false, false, 0.0, 1.337, -1.0)
	var v_hunt: String = sb._s52_verdict_label(true, true, true, false, 25.0, 2.437, -1.0)
	var v_found: String = sb._s52_verdict_label(true, true, false, true, 25.0, 0.0, 1.023)
	var v_narrow: String = sb._s52_verdict_label(true, true, false, false, 4.75, 8.4, -1.0)
	for pair in [[v_none, "NO BLIND PHASE"], [v_frozen, "NOT SWEEPING"], [v_hunt, "SWEEPING"],
				 [v_found, "FOUND IT"], [v_narrow, "TOO NARROW"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("the verdict for that state must name '%s', got '%s'" % [pair[1], pair[0]])
	var seen := {}
	for line in [v_none, v_frozen, v_hunt, v_found, v_narrow]:
		if seen.has(line):
			return _fail("all five verdict states must be DISTINCT — '%s' repeats" % line)
		seen[line] = true
	# ⭐⭐ AND THE FLOOR'S VERDICT MUST BE A **REACH** FAILURE, NOT SLICE 48's DEADLINE. There the
	# sweep was too slow to cover the gap before the engagement ended; here it can run at full rate
	# for the whole flight and never get there at all. Calling it "too slow" would be slice 48's
	# lesson wearing this slice's label.
	if str(v_narrow).to_lower().contains("slow"):
		return _fail("⭐⭐ the floor verdict must be a REACH failure, not a deadline — got '%s'" % v_narrow)
	# ⚠⚠ AND NONE OF THEM MAY NAME THE MISS. Across the whole floor region the missile flies a
	# BIT-IDENTICAL trajectory to the same 1039.88 m whatever the head is doing.
	for line in [v_none, v_frozen, v_hunt, v_found, v_narrow]:
		if str(line).to_lower().contains("miss ") or str(line).to_lower().contains("cpa"):
			return _fail("⚠⚠ the headline must NEVER name the miss — it carries no signal on this axis. Got '%s'" % line)
	# ⭐ AND THE −1.0 SENTINEL MUST NEVER REACH THE SCREEN AS A TIME.
	for line in [v_none, v_frozen, v_hunt, v_narrow,
				 sb._s52_reach_text(true, false, false, 3.0, 8.4, -1.0),
				 sb._s52_reach_text(false, false, false, 0.0, 1.337, -1.0)]:
		if str(line).contains("-1.0") or str(line).contains("-1 s"):
			return _fail("⭐ the never-locked SENTINEL (−1.0) reached the screen as a time: '%s'" % line)
	# ⭐⭐⭐ AND NEITHER MAY A DEFAULTED **ZERO** REACH THE REACH LINE — slice 48's windowed-shot
	# defect, inherited with its fix. `search_deficit_deg` is LIVE and honestly 0.0 whenever the head
	# is not sweeping, so a HUD reading it off the search branch says "there is no gap left" on the
	# two states where that is most wrong.
	for pair in [[sb._s52_reach_text(false, false, false, 0.0, 1.337, -1.0), "1.34"],
				 [sb._s52_reach_text(true, false, false, 3.0, 1.337, -1.0), "1.34"]]:
		if not str(pair[0]).contains(str(pair[1])):
			return _fail("⭐⭐⭐ a NON-SWEEPING state must show the LATCHED handover gap, not the live deficit's honest 0.0 — got '%s'" % pair[0])
	print("S52UI_VERDICT five distinct states, the floor is a REACH failure, none names the miss")

	# ══ TOOTH 6 — ⭐⭐⭐ THE BAND'S GEOMETRY ══════════════════════════════════════════════════════
	# The one drawing this slice ships, and it is a FUNCTION so it has a headless proof at all
	# (convention 14: `_draw` never runs under `--headless`, and slice 50 shipped a dispatch bug that
	# only a windowed shot could see). The relations below are the picture's whole meaning.
	var g: Array = sb._s52_band_rects(1490.0, 212.0, 25.0, 22.95, 8.35, 45.0, -12.4)
	var by := {}
	for r in g:
		by[str(r["kind"])] = r["rect"]
	for k in ["travel", "told", "flown", "need_neg", "need_pos", "head"]:
		if not by.has(k):
			return _fail("the band must draw '%s'" % k)
	var travel: Rect2 = by["travel"]
	var told: Rect2 = by["told"]
	var flown: Rect2 = by["flown"]
	if not travel.encloses(told):
		return _fail("⭐ the COMMANDED band must sit inside the head's mechanical travel (%s vs %s)" % [told, travel])
	if not told.encloses(flown):
		return _fail("⭐⭐⭐ the FLOWN band must sit strictly inside the COMMANDED one — that containment IS this slice's instrument, and a picture where they coincided would be drawing the command twice (%s vs %s)" % [flown, told])
	if not (flown.size.x < told.size.x - 1.0):
		return _fail("…and VISIBLY inside it: %.1f px vs %.1f px is not a difference a student can see" % [flown.size.x, told.size.x])
	# …all three concentric on the sweep CENTRE, which is what makes the ticks readable as a gap.
	var cx: float = travel.position.x + travel.size.x * 0.5
	for pair in [["told", told], ["flown", flown]]:
		var r: Rect2 = pair[1]
		if absf(r.position.x + r.size.x * 0.5 - cx) > 0.01:
			return _fail("the '%s' band must be centred on the sweep centre (%.3f vs %.3f)" % [pair[0], r.position.x + r.size.x * 0.5, cx])
	# ⭐⭐ THE TICKS WALK OUTWARD AS THE GAP GROWS — the RACE, and the reason a wide sweep can still
	# be too late: the belief the sweep is centred on is drifting away from the truth at ~6.8 °/s.
	var g_early: Array = sb._s52_band_rects(1490.0, 212.0, 25.0, 22.95, 1.34, 45.0)
	var g_late: Array = sb._s52_band_rects(1490.0, 212.0, 25.0, 22.95, 8.35, 45.0)
	var x_early: float = _kind_rect(g_early, "need_pos").position.x
	var x_late: float = _kind_rect(g_late, "need_pos").position.x
	if not (x_late > x_early + 5.0):
		return _fail("⭐⭐ the gap ticks must WALK OUTWARD as the deficit grows (%.1f -> %.1f px) — the race is the mechanism behind every 'wide enough and still too late' arm" % [x_early, x_late])
	# ⚠ A NEGATIVE GAP IS A REAL STATE (the deficit is `|err| − fov`, so it goes negative the moment
	# the target is inside the window) and it must collapse to the centre rather than draw backwards.
	var g_in: Array = sb._s52_band_rects(1490.0, 212.0, 25.0, 22.95, -3.0, 45.0)
	if absf(_kind_rect(g_in, "need_pos").position.x - _kind_rect(g_in, "need_neg").position.x) > 0.01:
		return _fail("⚠ a NEGATIVE gap (the target already inside the window) must collapse the two ticks onto the centre, not draw them crossed")
	# ⚠ AND EVERYTHING IS CLAMPED TO THE STRIP: a width past the trunnion is reachable by a drag
	# (the slider is clamped at the CONSUMER, not by the author), and a rectangle painted off the
	# column would draw over the 3-D view rather than failing.
	var g_wide: Array = sb._s52_band_rects(1490.0, 212.0, 900.0, 900.0, 900.0, 45.0, 900.0)
	var strip: Rect2 = _kind_rect(g_wide, "travel")
	for k in ["told", "flown", "head"]:
		var rk: Rect2 = _kind_rect(g_wide, k)
		if not (rk.position.x >= strip.position.x - 2.0
				and rk.position.x + rk.size.x <= strip.position.x + strip.size.x + 2.0):
			return _fail("⚠ a '%s' past the head's travel must CLAMP to the strip — got %s outside %s" % [k, rk, strip])
	# ⭐ AND THE LIVE HEAD MARKER SITS INSIDE THE FLOWN BAND — it is the same head, so a marker
	# outside the peak it set would mean the two keys are measuring different things. It is drawn on
	# the SIGNED side it is actually on, which is what makes the band move rather than merely grow.
	# ⚠ COMPARED IN **X ONLY**: the marker is deliberately TALLER than the band it sits in (it has to
	# read against a filled rectangle), so a `Rect2.encloses` would fail on the vertical and say
	# nothing about the angle, which is the only axis carrying meaning here.
	var head: Rect2 = _kind_rect(g, "head")
	if not (head.position.x >= flown.position.x - 2.0
			and head.position.x + head.size.x <= flown.position.x + flown.size.x + 2.0):
		return _fail("⭐ the LIVE head marker must lie inside the band it has swept (%s vs %s) — the peak IS this marker's own running maximum" % [head, flown])
	if not (head.position.x < cx):
		return _fail("⚠ a NEGATIVE live offset must draw on the negative side of the centre (%.1f vs %.1f)" % [head.position.x, cx])
	# ⚠⚠ THE POST-DRAG TRANSIT, WHICH IS THE ONE STATE ONLY A **DRAG** REACHES — and slice 49's rule
	# is that a drag reaches none of the four proofs, so it is asserted here or nowhere. Narrow the
	# sweep mid-search and the command re-arms on the next tick while the head is still out at the
	# old excursion: `flown > told`, impossible in steady state. The BAND draws the flown fill wider
	# than the told outline, which is the correct picture (the head is outside the new band), and the
	# TEXT must name it rather than print a fraction over 100 %.
	var g_tr: Array = sb._s52_band_rects(1490.0, 212.0, 2.1, 18.9, 5.0, 45.0, -18.9)
	if not (_kind_rect(g_tr, "flown").size.x > _kind_rect(g_tr, "told").size.x):
		return _fail("⚠⚠ during the post-drag transit the FLOWN band must draw wider than the freshly re-armed TOLD one — that is the head being outside the new sweep, and hiding it would be the stale-peak bug drawn as if it were fine")
	var tr_txt: String = sb._s52_sweep_text(true, 2.1, 18.9, 0.6)
	if tr_txt.contains("%") or not tr_txt.to_lower().contains("narrow"):
		return _fail("⚠⚠ the transit state must be NAMED, not printed as a fraction over 100 %% — got '%s'" % tr_txt)
	print("S52UI_BAND   flown ⊂ told ⊂ travel, concentric, live head inside; the ticks walk %.1f -> %.1f px; the post-drag transit reads '%s'" % [x_early, x_late, tr_txt])

	# ══ TOOTH 7 — ⚠⚠ THE BAND IS **NEVER** SIZED FROM THE COVERAGE ECHO ══════════════════════════
	# Gate 2 tooth I measured that `search_coverage_deg` echoes the comp bag FINITE-CLAMPED while the
	# kernel floors a non-finite sweep to exactly 0.0 — so on a NaN the wire reports 1e9 beside a
	# head standing still, and a band sized from it would be a billion degrees wide over a motionless
	# seeker. The width comes from `search_offset_peak_deg`, a peak of the COMMAND.
	sb._telemetry = _s52_tel(true, 1.337, false, 0.0, -1.0, 8.0, 5.2)
	sb._telemetry["m1.search_coverage_deg"] = 1.0e9
	if absf(sb._s52_told_deg() - 8.0) > 1.0e-9:
		return _fail("⚠⚠ the band's width must come from `search_offset_peak_deg` (8.0) and NOT from the coverage ECHO (1e9) — got %.3f. A HUD reading the echo draws a billion degrees over a head that is not moving" % sb._s52_told_deg())
	var wide_g: Array = sb._s52_band_rects(1490.0, 212.0, sb._s52_told_deg(), sb._s52_flown_deg(),
			sb._s52_need_deg(true), 45.0)
	if not _kind_rect(wide_g, "travel").encloses(_kind_rect(wide_g, "told")):
		return _fail("…and the drawn band must therefore stay inside the strip on that frame")
	print("S52UI_ECHO   a 1e9 coverage echo does not reach the band — the width is a peak of the COMMAND")

	# ══ TOOTH 8 — ⚠ THE WIDTH BUDGETS, IN PIXELS ═════════════════════════════════════════════════
	# ⚠⚠ MEASURED IN **PIXELS**, NOT CHARACTERS — slice 46 shipped a CHARACTER tooth that passed
	# GREEN while every line ran off the right edge at 1152 px and again at 1920. The origin is
	# `vp.x − 430`, ANCHORED TO THE RIGHT EDGE, so there is no window size at which an over-wide line
	# fits, and `° ± ⇒ —` are one `length()` each and many pixels each.
	var body := [sb._s52_sweep_text(false, 0.0, 0.0, 0.0),
				 sb._s52_sweep_text(true, 25.0, 22.95, 1.02),
				 sb._s52_sweep_text(true, 40.0, 37.95, 12.34),
				 sb._s52_sweep_text(true, 2.1, 18.9, 0.6),
				 sb._s52_reach_text(false, false, false, 0.0, 1.337, -1.0),
				 sb._s52_reach_text(true, true, false, 3.24, 2.804, -1.0),
				 sb._s52_reach_text(true, false, false, 3.02, 8.400, -1.0),
				 sb._s52_reach_text(true, false, true, 22.95, 0.0, 12.345),
				 sb._s52_cure_text(false, false),
				 sb._s52_cure_text(true, false),
				 sb._s52_cure_text(true, true),
				 sb._search_authority_text(true, false, 0.0, 0.0),
				 sb._search_authority_text(false, true, 0.903, 1.0),
				 sb._search_authority_text(false, false, 0.0, 0.0),
				 "closing at 699 m/s — the MISS says nothing here"]
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > 430.0:
			return _fail("⚠⚠ HUD BODY line is %.0f px wide at 15 px, over the 430 px the origin `vp.x − 430` leaves — it clips at EVERY window size. '%s'" % [w, line])
	var heads := [v_none, v_frozen, v_hunt, v_found, v_narrow]
	for line in heads:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > 430.0:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px wide at 20 px, over 430 px — a SEPARATE and much tighter budget, because it is drawn LARGER from the same origin. '%s'" % [wh, line])
	if _maxlen(body) > 60:
		return _fail("a body line is %d chars — the family's measured budget is ~55" % _maxlen(body))
	if _maxlen(heads) > 32:
		return _fail("a headline is %d chars, over the family's measured 30" % _maxlen(heads))
	# ⚠ AND NONE MAY CONTAIN A LITERAL UNSUBSTITUTED SPECIFIER — the silent-format bug (slice 21,
	# reproduced by slice 25) shows up as the FORMAT STRING itself on screen, on a GREEN run.
	for line in body + heads:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	print("S52UI_WIDTH  body ≤ %d chars / %.0f px, headline ≤ %d chars / %.0f px, against 430 px" % [
			_maxlen(body), _maxpx(fnt, body, 15), _maxlen(heads), _maxpx(fnt, heads, 20)])

	# ══ TOOTH 9 — every key the HUD reads is present and scalar ══════════════════════════════════
	var need := ["m1.head_searching", "m1.search_offset_deg", "m1.search_deficit_deg",
				 "m1.search_elapsed_s", "m1.search_t_lock_s", "m1.search_rate_dps",
				 "m1.search_coverage_deg", "m1.search_offset_peak_deg",
				 "m1.search_realized_peak_deg", "m1.search_realized_deg",
				 "m1.gimbal_fov_deg", "m1.gimbal_stop_deg", "m1.gimbal_valid",
				 "m1.a_cmd_frac", "m1.los_range", "m1.closing_speed",
				 "m1.head_cue_err_handover_deg"]
	var tel := _s52_tel(true, 1.337, false, 0.0, -1.0, 8.0, 5.2)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		if typeof(tel[k]) != TYPE_FLOAT and typeof(tel[k]) != TYPE_INT:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	print("S52UI_KEYS   all %d HUD keys present and scalar" % need.size())

	# ══ TOOTH 10 — ONE slider → set_param on the MISSILE ═════════════════════════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 6.0
	sliders[0].value_changed.emit(6.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "seeker_search_coverage_deg":
			if str(d.get("target", "")) != "m1":
				return _fail("⚠ the slider must address the MISSILE (`m1`) — the search is the missile's seeker. Got '%s'" % str(d.get("target", "")))
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the missile's `seeker_search_coverage_deg` — got %s" % str(mock.sent))
	print("S52UI_WIRE   one slider → set_param(m1.seeker_search_coverage_deg)")

	# ══ TOOTH 11 — ⭐ THE MIRROR THE OTHER WAY: a slice-48 wire keeps its own HUD ════════════════
	_sb48 = _build_sandbox()
	var h48 := {
		"name": "slice48_search", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "seeker_detect_view": true, "midcourse_view": true,
		"search_view": true, "gimbal_view": true, "gimbal_rate_view": true,
		"knobs": [{"target": "m1", "key": "seeker_search_rate_dps", "min": 0.0, "max": 240.0,
				   "value": 0.0, "label": "SEEKER SWEEP RATE"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
	}
	_sb48._on_scenario(h48)
	if _sb48._s52_view:
		return _fail("a slice-48 wire must NOT raise `search_realized_view` — it authors the search and NOT the instrument, which is the whole thing that keeps its frames byte-identical")
	if not _sb48._search_view:
		return _fail("⭐ …and it must keep its own HUD marker — the new branch is checked FIRST at both text sites, so a bug there would steal slice 48's own wire")
	if _sb48._fid_kind != "seeker_detect":
		return _fail("⭐ …and its button too (got %s)" % _sb48._fid_kind)
	print("S52UI_PRIOR  a slice-48 wire raises no realized marker and keeps its HUD — the new first-checked branch steals nothing")

	return _pass()

func _kind_rect(g: Array, kind: String) -> Rect2:
	for r in g:
		if str(r["kind"]) == kind:
			return r["rect"]
	return Rect2()

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
	print("S52UI OK: a sweep must be SIZED to the uncertainty you actually have. ⭐⭐⭐ Too narrow " +
		"and the band never reaches the target at any duration — 4.75° never finds it, 5.00° finds " +
		"it in a quarter of a second — and every degree wider than necessary is paid TWICE, in " +
		"travel spent before the head ever looks at the right half of the sky: slice 48's own " +
		"authored 25° is pinned at 100 % of the airframe and still misses by 32 m where 6° arrives " +
		"at 7 cm. ⭐⭐⭐ AND THE HEAD DOES NOT FLY THE COVERAGE YOU AUTHOR — 27 % of a 1° sweep, " +
		"95 % of a 40° one — so the band the student is shown is the one the head FLEW, never the " +
		"number in the file. ⭐⭐ THE CLIENT HALF IS A MARKER WHOSE FALLBACK IS THE PREVIOUS " +
		"SLICE'S OWN BLOCK ABOUT THE SAME HEAD: every number on it true, and the width never " +
		"mentioned.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S52UI FAIL: " + msg)
	print("S52UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb48]:
		if sb != null and is_instance_valid(sb):
			sb.free()
