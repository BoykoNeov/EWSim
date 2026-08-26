extends SceneTree
# Headless UI test for the slice-50 ASPECT-DEPENDENT ENGAGEMENT — routing, the latch, and the HUD:
# the piece `slice50_verify.gd` cannot reach. The verifier drives SimClient directly (the wire + the
# physics); the Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing
# or the HUD, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL
# (convention 14) — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐⭐ AND THE SHARPEST TOOTH IN THE FILE IS ONE NO OTHER PROOF CAN REACH AT ALL: **A LIVE SLIDER
# DRAG.** The verifier sends a `reset` between arms, the UI test elsewhere presses the Reset BUTTON,
# and a windowed shot is one static frame — so a drag reaches NONE of the four gate-3 proofs unless
# this file goes and gets it. Slice 49 discovered that after all four of its proofs were green;
# slice 50 has it for free and asserts it here, in the form its own gauge needs:
#
#   THE GAUGE IS A LATCHED **INSTANT**, NOT A DURATION, so it must DISARM on a drag rather than
#   restart. 49's gauge was a duration — a run that restarts mid-flight is still an honest run, and
#   its range window said where. This one's entire meaning is *when the FROM-LAUNCH flight lost the
#   picture*. A shape dialled in at t = 5 s loses it somewhere its from-launch flight never would,
#   so a re-armed latch would be A DIFFERENT QUANTITY WEARING THE SAME LABEL — the exact defect
#   slice 49 caught, one instrument later. ⭐ A latched DURATION may restart mid-flight; a latched
#   INSTANT may not.
#
# ⚠⚠ AND THE OTHER TOOTH THAT IS SPECIFIC TO THIS SLICE: **THE NULL AND THE FAILURE MODE ARE THE
# SAME NUMBER.** The lesson's null reads 0.000° (F ≤ 7 never loses the lock) and a missing
# `seeker_tgo_s` read through `.get(k, 0.0)` also reads 0.000°. No value assertion anywhere can
# separate them, so the client tracks key PRESENCE independently and the HUD says which of the two
# zeros it is holding — asserted here in both directions.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-50 handshake routes to the 3-D airframe view and records the marker AND THE PAIR
#   2. ⭐⭐ THE HUD IS TAKEN AND THE BUTTON IS **NOT** — slice 46's toggle is still this slice's A/B
#   3. ⭐⭐ THE MIRROR: strip the marker and slice 46's HORIZON block takes the wire
#   4. ⭐⭐⭐ SLICE 49's MARKER MUST NOT FIRE HERE — it names a radar this wire does not have
#   5. ⭐⭐⭐ THE LATCH: it fires on the 1 → 0 EDGE, takes the FIRST edge only, and frame 1 is never one
#   6. ⭐⭐⭐ THE DRAG DISARMS IT — cleared, no number, and NOT re-armed for the rest of the flight
#   7. ⭐⭐ …AND THE LIVE LINES SURVIVE THE DRAG, because that is what keeps the drag a teaching tool
#   8. ⭐ Reset clears all seven AND re-arms — the only thing that does
#   9. ⭐⭐ THE TWO ZEROS: a measured null and a missing key must print DIFFERENT sentences
#  10. ⚠ WIDTHS: the family's 430 px (this is the 3-D view — slice 49's 390 was the spatial view's)
#  11. ONE slider → set_param on the TARGET's `rcs_fineness`
#  12. ⭐ THE MIRROR THE OTHER WAY: a slice-48 wire raises no slice-50 marker and keeps its own HUD
#
# Run:  godot --headless --path clients/godot --script res://net/slice50_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const MID := "m1"
const TID := "tgt1"

# ⚠ THE BUDGET IS THE FAMILY'S 430 px, AND THAT IS A PROPERTY OF THE VIEW RATHER THAN OF THE SLICE.
# Slice 49 tightened to 390 because the SPATIAL view puts its altitude tick labels up the right edge
# at `vp.x − 34`. This block draws into the 3-D airframe view, whose right edge is empty — exactly
# as slices 34–48 do. ⚠⚠ ASSERTED IN **PIXELS**, NOT CHARACTERS: slice 46 shipped a 100/96-CHARACTER
# tooth that passed green while every line clipped at 1152 px AND at 1920 px.
const HUD_ROOM := 430.0
const HEADLINE_ROOM := 430.0

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb_prior

# The fixture reproduces the wire's own shape: the slice-50 keys ride the target's SHAPE and the
# seeker's BUDGET, so on this wire they ship on EVERY frame — including while the lock is held.
func _tel(det: bool, om: float, tgo: float, r: float, racq: float, deg: float,
		  drop_tgo := false) -> Dictionary:
	var d := {
		MID + ".seeker_detect": 1.0 if det else 0.0,
		MID + ".los_rate": om,
		MID + ".los_range": r,
		MID + ".seeker_r_acq_m": racq,
		MID + ".seeker_range_margin_m": racq - r,
		MID + ".target_aspect_deg": deg,
		MID + ".rcs_eff_m2": 0.0013,
		MID + ".seeker_tgo_s": tgo,
		MID + ".closing_speed": 711.7,
	}
	# ⚠ THE FAILURE MODE THIS SLICE CANNOT DETECT BY VALUE: the key simply stops emitting.
	if drop_tgo:
		d.erase(MID + ".seeker_tgo_s")
	return d

func _handshake(marker: bool) -> Dictionary:
	var h := {
		"name": "slice50_defensive",
		"knobs": [
			{"target": TID, "key": "rcs_fineness", "min": 1.0, "max": 10.0, "value": 8.0,
			 "label": "TARGET FINENESS L/r (1 = sphere) — watch the LOCK BE TAKEN BACK, not the miss"},
		],
		"fidelity": {"airframe": "six_dof", "autopilot": "alpha", "guidance": "pn",
					 "seeker": "filtered", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
		# ⚠ THE 3-D AIRFRAME VIEW's OWN MARKERS — this wire IS slice 48's missile minus the search
		# and the midcourse, so it raises 46's `seeker_detect_view` and the airframe pair.
		"airframe_view": true, "airframe_6dof": true, "airframe_target": MID,
		"seeker_detect_view": true, "gimbal_view": true, "gimbal_rate_view": true,
	}
	if marker:
		h["seeker_aspect_view"] = true
		h["seeker_aspect_target"] = TID
		h["seeker_aspect_observer"] = MID
	return h

func _st(t: float) -> Dictionary:
	# ⚠ `entities` is an ARRAY OF RECORDS (the wire's own shape), not a dict keyed by id.
	return {"t": t, "entities": [
		{"id": MID, "kind": "missile", "pos": [700.0 * t, 0.0, 3000.0 + 140.0 * t]},
		{"id": TID, "kind": "target", "pos": [6000.0, -300.0 * t, 4200.0]},
	]}

func _feed(sb, t: float, det: bool, r: float, racq: float, om := 0.0078, tgo := 5.36,
		   deg := 76.0, drop_tgo := false) -> void:
	# One frame through the REAL client path, so the latch is exercised where it actually lives.
	sb._telemetry = _tel(det, om, tgo, r, racq, deg, drop_tgo)
	sb._airframe3d_on_state(_st(t))

func _initialize() -> void:
	print("S50UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_handshake(true))

	# ══ TOOTH 1 — ROUTE, AND THE PAIR ════════════════════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-50 handshake must route to the 3-D AIRFRAME view, got '%s' — this is slice 48's 6-DOF missile with the search and the midcourse removed, and the HUD's 430 px budget is a property of that view" % sb._mode)
	if not sb._s50_view:
		return _fail("the client must record the `seeker_aspect_view` handshake marker")
	if sb._s50_target != TID or sb._s50_observer != MID:
		return _fail("⚠ an aspect belongs to a target–observer PAIR and the marker carries both: got target '%s' / observer '%s'. The telemetry is keyed on the OBSERVER (the missile) while the prose names the TARGET, and the missile's aspect on this target is a DIFFERENT number from a ground radar's at the same instant" % [sb._s50_target, sb._s50_observer])
	if sb._s50_key("seeker_tgo_s") != MID + ".seeker_tgo_s":
		return _fail("⭐ the HUD must form its keys off the OBSERVER (got '%s')" % sb._s50_key("seeker_tgo_s"))
	print("S50UI_ROUTE  airframe3d view, seeker_aspect_view + the %s→%s pair recorded" % [sb._s50_target, sb._s50_observer])

	# ══ TOOTH 2 — ⭐⭐ THE HUD IS TAKEN, THE BUTTON IS **NOT** ════════════════════════════════════
	# 47/48's shape, and NOT 49's: slice 46's `seeker_detect` toggle is still this slice's own A/B.
	# Press it and the horizon goes away, the lock is never taken back, and the target's shape stops
	# mattering at all — the sharpest comparison this wire has. A marker that stole the button would
	# delete it.
	if sb._fid_kind == "aspect":
		return _fail("⭐⭐ the slice-50 marker must NOT claim the shared button — slice 46's seeker_detect toggle is this wire's own A/B (press it: the horizon goes away and the lock is never lost), and taking the button would delete the comparison")
	if not sb._seeker_detect_view:
		return _fail("the wire must keep slice 46's `seeker_detect_view` — the button is inherited, only the HUD is new")
	print("S50UI_BUTTON the HUD is taken and the seeker_detect BUTTON is left alone (47/48's shape, not 49's)")

	# ══ TOOTH 3 — ⭐⭐ THE MIRROR: without the marker slice 46's HORIZON block takes the wire ══════
	# ⚠⚠ AND THE HOLE IS NOT A VIEW OR A BUTTON — it is the HUD, and the failure is the subtle kind
	# this family keeps rediscovering: every line slice 46's block draws on this wire is TRUE. The
	# horizon is real, the margin is real, the authority is real. What none of them can say is that
	# the horizon is MOVING, that the TARGET is what moved it, or that a lock the missile already had
	# was taken back. Every number right and the slice invisible.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_handshake(false))
	if _sb_nomarker._s50_view:
		return _fail("the no-marker mirror must NOT record seeker_aspect_view")
	if _sb_nomarker._mode != "airframe3d":
		return _fail("⚠ the two must share the VIEW — the marker changes the HUD, not the view. Got %s vs %s" % [_sb_nomarker._mode, sb._mode])
	if not _sb_nomarker._seeker_detect_view:
		return _fail("⭐⭐ THE HOLE: without the marker this wire must fall to slice 46's HORIZON block — that fallback is exactly the failure being prevented (five TRUE numbers about a stationary horizon on a scenario whose horizon RETREATS), and it must be reproduced here or the mirror proves nothing")
	print("S50UI_MIRROR without the marker the wire keeps the view and falls to slice 46's horizon block — every number true, and the slice invisible")

	# ══ TOOTH 4 — ⭐⭐⭐ SLICE 49's MARKER MUST NOT FIRE ON THIS WIRE ═════════════════════════════
	# `_aspect_view_info` raises on ANY shaped target, so this wire tripped it — and slice 49's HUD
	# keys EVERY line off a RADAR observer, which here does not exist. The block would have rendered
	# against an empty-string observer: "HOLDING IT: 90° broadside / echo 0 m² — 0.0 dB below
	# broadside / range 0.0 km  Pd 0.00  SEEN" over a target turning nose-on at 3 g and seconds from
	# being lost. Six defaulted numbers, no failing test, and the two loudest asserting the exact
	# OPPOSITE of the lesson. The core now REQUIRES the observer — half a pair is not a marker — and
	# this tooth is what stops that ever being loosened again.
	if sb._aspect_view or sb._aspect_observer != "":
		return _fail("⭐⭐⭐ a slice-50 wire must NOT raise slice 49's `aspect_view` (view=%s, observer='%s') — it names a RADAR this wire does not have, and its HUD keys every line off that observer. With an empty one it renders SIX DEFAULTED NUMBERS, the loudest of them '90° broadside' and 'SEEN', over a target about to vanish" % [sb._aspect_view, sb._aspect_observer])
	print("S50UI_S49    slice 49's radar-keyed block is correctly silent on a wire with no radar")

	# ══ TOOTH 5 — ⭐⭐⭐ THE LATCH: THE EDGE, THE FIRST EDGE ONLY, AND FRAME 1 IS NEVER ONE ════════
	var g = _build_sandbox()
	g._on_scenario(_handshake(true))
	# ⚠ FRAME 1 OPENS **BLIND** ON PURPOSE. `_s50_prev_det` starts at −1 so this cannot be an edge; a
	# 0.0 seed would latch here and sample the start of the RECORDING as an instant of loss.
	_feed(g, 0.016, false, 6100.0, 8079.0)
	if g._s50_latched:
		return _fail("⭐⭐⭐ frame 1 must NEVER be an edge — `_s50_prev_det` starts at −1 for exactly this reason, and a 0.0 seed would make a wire that opens blind latch on frame one, sampling the start of the RECORDING as though it were an instant of loss")
	_feed(g, 0.032, true, 6000.0, 8079.0)      # …the lock is there
	if g._s50_latched:
		return _fail("a 0 → 1 edge must not latch — the gauge is the moment the lock is TAKEN BACK")
	if not g._s50_keys:
		return _fail("the client must record that `seeker_tgo_s` is PRESENT — on this gauge that is the only thing separating a measured null from a dead instrument")
	# ⭐ THE EDGE. ω = 0.007782 rad/s, t_go = 5.357 s ⇒ 0.041690 rad ⇒ 2.389° (§7.1's authored row).
	_feed(g, 3.280, false, 3809.9, 3809.0, 0.007782, 5.357, 76.39)
	if not g._s50_latched:
		return _fail("⭐⭐⭐ the 1 → 0 edge must LATCH — that is the moment the lock is taken back, and it is the whole slice")
	if absf(g._s50_deg - 2.3888) > 0.01:
		return _fail("⭐⭐⭐ the gauge must be ω_LOS · t_go in DEGREES (got %.4f, want 2.389) — 'the heading error the missile went blind holding'. Under PN the loop drives ω toward zero while it can see; whatever is left at the last look is a heading error, and t_go is how much flying was left to hold it through" % g._s50_deg)
	if absf(g._s50_r_loss - 3809.9) > 0.01 or absf(g._s50_t_loss - 3.280) > 1.0e-9:
		return _fail("⚠ the RANGE and the TIME are part of the SAME latch (got %.1f m / %.4f s) — they are r and t SAMPLED AT THE LOSS INSTANT, not live readouts that happen to sit beside it, so they go stale with it" % [g._s50_r_loss, g._s50_t_loss])
	# ⚠ THE **FIRST** EDGE ONLY. A later one would be sampled downstream of a blind coast, and
	# everything downstream of a blind coast is a divergence being sampled: the same quantity read at
	# RE-ACQUISITION moves 3.1× at half `dt`, and the CPA on that row moves 20×.
	_feed(g, 5.373, true, 2281.0, 2400.0)      # the lock is GIVEN BACK
	if not g._s50_regained:
		return _fail("a 0 → 1 edge after the latch must record that the lock was GIVEN BACK — that is what separates the teachable domain from the region above the ceiling, where it never is")
	_feed(g, 6.000, false, 1900.0, 1800.0, 0.9, 1.0)    # a SECOND loss, with a huge would-be gauge
	if absf(g._s50_deg - 2.3888) > 0.01:
		return _fail("⭐⭐⭐ the latch must take the FIRST edge ONLY (gauge moved to %.4f) — a second edge is sampled downstream of a blind COAST, which is an open-loop integration of a frozen estimate: the same quantity read at re-acquisition moves 3.1x at half dt and the CPA on that row moves 20x" % g._s50_deg)
	print("S50UI_LATCH  edge-latched at 2.389 deg / 3809.9 m / 3.280 s, lock given back, and a second loss does NOT move it")

	# ══ TOOTH 6 — ⭐⭐⭐ THE DRAG DISARMS IT ══════════════════════════════════════════════════════
	# The tooth NO OTHER PROOF CAN REACH (see the header). Both halves asserted, because they are two
	# different decisions: the number is CLEARED (it belongs to the shape that produced it) and the
	# latch is DISARMED FOR THE REST OF THE FLIGHT (the instant's meaning is the whole from-launch
	# history, and a live knob rewrites that history).
	g._on_knob_dragged("rcs_fineness")
	if g._s50_latched or g._s50_deg != 0.0 or g._s50_r_loss != 0.0 or g._s50_t_loss != 0.0 or g._s50_regained:
		return _fail("⭐⭐⭐ a live drag must CLEAR the latch (latched=%s, %.4f deg, %.1f m, %.4f s) — the measurement was made on a DIFFERENT BODY, and displaying it under the new shape is the needle's number under the wrong label" % [g._s50_latched, g._s50_deg, g._s50_r_loss, g._s50_t_loss])
	if g._s50_armed:
		return _fail("⭐⭐⭐ …and it must DISARM, not merely clear. This gauge is a latched INSTANT whose entire meaning is *when the FROM-LAUNCH flight lost the picture*: a shape dialled in mid-flight loses it somewhere its from-launch flight never would, so a re-armed latch is A DIFFERENT QUANTITY WEARING THE SAME LABEL. A latched DURATION may restart mid-flight; a latched INSTANT may not")
	# …and it stays disarmed through further frames, INCLUDING a fresh 1 → 0 edge.
	_feed(g, 7.000, true, 1500.0, 4000.0)
	_feed(g, 7.500, false, 1300.0, 1200.0, 0.5, 2.0)
	if g._s50_latched or g._s50_deg != 0.0:
		return _fail("⭐⭐⭐ a fresh edge AFTER the drag must NOT re-latch (%.4f deg) — that number would be measured from a launch this shape never flew" % g._s50_deg)
	# ⚠ AND THE HUD MUST SAY SO IN WORDS, WITH **NO NUMBER IN IT**. A verdict word beside the value
	# would be a display patch over a semantic collision — the number itself would still be
	# mislabelled. This is asserted on the STRINGS because that is where the decision lives.
	var dis_head: String = g._s50_verdict_label(g._s50_armed, g._s50_keys, g._s50_latched, false, false, g._s50_deg)
	var dis_gauge: String = g._s50_gauge_text(g._s50_armed, g._s50_keys, g._s50_latched, g._s50_deg, g._s50_r_loss, g._s50_t_loss)
	if not (dis_head.to_lower().contains("reset") and dis_gauge.to_lower().contains("clear")):
		return _fail("⭐⭐ the disarmed state must SAY it needs a Reset and that the gauge is cleared — got '%s' / '%s'" % [dis_head, dis_gauge])
	for s in [dis_head, dis_gauge]:
		if s.contains("2.38") or s.contains("3809") or s.contains("3.28"):
			return _fail("⭐⭐⭐ the disarmed state must print NO NUMBER at all — got '%s'. A verdict word beside the value would be a display patch over a semantic collision, and the number would still be mislabelled" % s)
	print("S50UI_DRAG   ⭐⭐⭐ a drag CLEARS the latch AND DISARMS it for the rest of the flight, and says so with no number: '%s'" % dis_head)

	# ══ TOOTH 7 — ⭐⭐ …AND THE LIVE LINES SURVIVE THE DRAG ══════════════════════════════════════
	# The split is the non-obvious part and it is deliberate: the LATCH belongs to the shape, the
	# LIVE lines belong to the tick. They are recomputed every frame from the NEW shape and are never
	# latched, which is what keeps the drag a TEACHING INSTRUMENT — dial the fineness up and watch
	# the horizon collapse through the range in real time, with the gauge honestly saying it can no
	# longer measure THIS flight.
	if absf(g._s50_aspect_deg() - 76.0) > 1.0e-9:
		return _fail("⚠ the LIVE aspect must survive the drag (%.3f) — it is recomputed every frame from the new shape" % g._s50_aspect_deg())
	var live: String = g._s50_horizon_text(float(g._telemetry.get(MID + ".seeker_r_acq_m", 0.0)),
										   float(g._telemetry.get(MID + ".los_range", 0.0)))
	if not (live.contains("1.2") and live.contains("1.3")):
		return _fail("⚠ the LIVE horizon-vs-range line must still read the wire after a drag — got '%s'" % live)
	print("S50UI_LIVE   the drag leaves the live lines alone: '%s'" % live)

	# ══ TOOTH 8 — ⭐ RESET CLEARS ALL SEVEN **AND RE-ARMS** ══════════════════════════════════════
	# The only thing that does, and the reason is the difference between the two gestures: a drag
	# changes the shape underneath a flight already in progress; a reset restarts the FLIGHT, which
	# is the very history the instant is measured against.
	g._on_reset_pressed()
	if not g._s50_armed:
		return _fail("⭐ Reset must RE-ARM the latch — it restarts the flight, which is the history the instant is measured against, so a from-launch measurement becomes possible again")
	if g._s50_latched or g._s50_regained or g._s50_deg != 0.0 or g._s50_r_loss != 0.0 \
			or g._s50_t_loss != 0.0 or g._s50_t != 0.0:
		return _fail("⭐ Reset must clear the latch, the sentence selectors and the clock — a stale set opens a fresh launch at the slider's FLOOR displaying the previous arm's 5.77 deg as though the ROUND body had owed it, which is this HUD's single most misleading state")
	if g._s50_prev_det != -1.0:
		return _fail("⚠ Reset must return the edge detector to −1 and NOT to 0 (got %.1f) — a stale 1.0 against a first frame that reads blind would latch on frame one" % g._s50_prev_det)
	print("S50UI_RESET  all seven cleared AND the latch RE-ARMED — the one gesture that does")

	# ══ TOOTH 9 — ⭐⭐ THE TWO ZEROS MUST PRINT DIFFERENT SENTENCES ══════════════════════════════
	# The lesson's NULL is 0.000° and a missing `seeker_tgo_s` through `.get(k, 0.0)` is 0.000° too —
	# **the legitimate value and the failure mode are the same number**, which no other slice in this
	# family has had to face. No value assertion can separate them; only key PRESENCE can.
	var z = _build_sandbox()
	z._on_scenario(_handshake(true))
	_feed(z, 0.016, true, 6100.0, 8079.0)
	_feed(z, 1.000, true, 5400.0, 8000.0)
	if not z._s50_keys or z._s50_latched:
		return _fail("the measured-null fixture must carry its keys and never latch")
	var null_head: String = z._s50_verdict_label(z._s50_armed, z._s50_keys, z._s50_latched, true, false, z._s50_deg)
	var null_gauge: String = z._s50_gauge_text(z._s50_armed, z._s50_keys, z._s50_latched, z._s50_deg, 0.0, 0.0)
	# …now the SAME zero, arrived at by the key going missing.
	_feed(z, 2.000, true, 5000.0, 7800.0, 0.0078, 5.36, 76.0, true)
	if z._s50_keys:
		return _fail("⚠ the client must NOTICE that `seeker_tgo_s` stopped emitting — presence is tracked separately from value precisely because the value is identical in both cases")
	var dead_head: String = z._s50_verdict_label(z._s50_armed, z._s50_keys, z._s50_latched, true, false, z._s50_deg)
	var dead_gauge: String = z._s50_gauge_text(z._s50_armed, z._s50_keys, z._s50_latched, z._s50_deg, 0.0, 0.0)
	if null_head == dead_head or null_gauge == dead_gauge:
		return _fail("⭐⭐ a MEASURED null and a DEAD instrument both read 0.000 deg and must print DIFFERENT sentences — got '%s' vs '%s'. This is the defaulted-zero class in the one form no value assertion can catch" % [null_head, dead_head])
	if not (null_gauge.to_lower().contains("round") or null_gauge.to_lower().contains("no heading")):
		return _fail("⭐ the NULL's own sentence must say the shape is round, not print a bare zero — got '%s'. 'owed 0.0 deg' reads as an instrument nothing has fed rather than as the result it is" % null_gauge)
	if not dead_gauge.to_lower().contains("unavailable"):
		return _fail("⭐ …and the DEAD instrument must say it is unavailable — got '%s'" % dead_gauge)
	print("S50UI_ZEROS  measured null: '%s' | dead instrument: '%s' — the same 0.000 deg, two sentences" % [null_gauge, dead_gauge])

	# ══ TOOTH 9b — ⭐⭐⭐ THE ASPECT WORD MUST **RESOLVE OVER THIS WIRE'S OWN DOMAIN** ═════════════
	# ⚠⚠ NO OTHER PROOF HAS THIS TOOTH, AND THE WINDOWED SHOT IS WHAT EXPOSED THE NEED FOR IT.
	# Slice 49's `_asp_word` bands on the ABSOLUTE aspect (70–110° → "broadside"), which is right for
	# a radar watching a target swing through 0–180° over ninety seconds. **This wire never leaves
	# that one band**: launch is 90° and every loss on every arm is between 71.9° and 81.5°. Inherit
	# those bands and the word is CONSTANT across the entire teachable domain — the same objection
	# that disqualified `min R_acq/r` as a gauge (resolution over no slider steps at all).
	# ⚠⚠⚠ AND IT IS WRONG, NOT MERELY USELESS: at 71° with a fineness of 8 the echo is ~18 dB below
	# broadside and the line beside it says the horizon has collapsed inside the range. "broadside"
	# is the word for BRIGHTEST. Printing it on a blind frame is `_aspect_view_info`'s own defect
	# committed in the client, with a COMPUTED value in place of a defaulted one.
	var w_launch: String = sb._s50_word(90.0)
	var w_loss75: String = sb._s50_word(71.86)     # F = 7.5, the marginal arm
	var w_loss8: String = sb._s50_word(76.37)      # F = 8, the AUTHORED wire
	var w_loss10: String = sb._s50_word(81.47)     # F = 10, the ceiling
	if w_launch == w_loss8:
		return _fail("⭐⭐⭐ the aspect word must CHANGE between the launch (90°) and the authored arm's loss (76.4°) — both read '%s'. Slice 49's absolute bands put this wire's whole domain in one word, which is a vocabulary with no resolution over the slider it is meant to describe" % w_launch)
	if w_loss10 == w_loss75:
		return _fail("⭐⭐ …and it must resolve ACROSS the slider too: F=10 loses at 81.5° and F=7.5 at 71.9°, and both read '%s'" % w_loss10)
	# ⚠⚠ AND NO WORD REACHABLE AT A LOSS MAY CLAIM THE TARGET IS AT ITS BRIGHTEST. That is the
	# specific lie: the loss frames are 8–18° off broadside, tens of times dimmer, and blind.
	for pair in [[w_loss75, 71.86], [w_loss8, 76.37], [w_loss10, 81.47]]:
		var low: String = str(pair[0]).to_lower()
		if low.contains("brightest") or low == "broadside":
			return _fail("⭐⭐⭐ at %.1f° the target is tens of times dimmer than broadside and the seeker is BLIND — the word must not read '%s'. 'broadside' is the word for BRIGHTEST" % [float(pair[1]), str(pair[0])])
	# ⚠ …and the brightest word must still be REACHABLE, at the launch aspect where it is true.
	if not w_launch.to_lower().contains("brightest"):
		return _fail("⚠ at 90° the target IS at its brightest (`rcs_aspect(σ, F, π/2) = σ` for every fineness) and the word must say so — got '%s'" % w_launch)
	# ⚠ FORE/AFT SYMMETRY (`rcs_aspect`'s named approximation): 156° returns the same σ as 24°, so no
	# band may name the NOSE or the TAIL — the model cannot tell them apart and the word must not
	# pretend otherwise. Asserted as an IDENTITY across the reflection, not as a wording check.
	for d in [10.0, 24.0, 45.0, 71.86, 89.0]:
		if sb._s50_word(d) != sb._s50_word(180.0 - d):
			return _fail("⚠ the word must be fore/aft SYMMETRIC like the model it describes: %.1f° reads '%s' but %.1f° reads '%s', and `rcs_aspect` returns the SAME σ for both" % [d, sb._s50_word(d), 180.0 - d, sb._s50_word(180.0 - d)])
	print("S50UI_WORD   90°='%s' → 81.5°='%s' → 76.4°='%s' → 71.9°='%s' — it resolves over the domain, and never says 'brightest' on a blind frame" % [w_launch, w_loss10, w_loss8, w_loss75])

	# ══ TOOTH 10 — ⚠ WIDTHS, IN PIXELS ═════════════════════════════════════════════════════════
	var bodies := [
		sb._s50_aspect_text(TID, MID, 76.0),
		sb._s50_aspect_text(TID, MID, 9.0),
		sb._s50_horizon_text(3809.0, 3809.9),
		sb._s50_horizon_text(8079.0, 6118.0),
		sb._s50_gauge_text(true, true, true, 5.702, 4521.7, 2.272),
		sb._s50_gauge_text(true, true, false, 0.0, 0.0, 0.0),
		sb._s50_gauge_text(false, true, false, 0.0, 0.0, 0.0),
		sb._s50_gauge_text(true, false, false, 0.0, 0.0, 0.0),
		sb._s50_cure_text(true, true), sb._s50_cure_text(false, true), sb._s50_cure_text(false, false),
		"closing at 712 m/s — the MISS says nothing here",
	]
	var heads := [
		sb._s50_verdict_label(true, true, true, false, false, 5.702),
		sb._s50_verdict_label(true, true, true, true, true, 5.702),
		sb._s50_verdict_label(true, true, false, true, false, 0.0),
		sb._s50_verdict_label(true, true, false, false, false, 0.0),
		sb._s50_verdict_label(false, true, false, true, false, 0.0),
		sb._s50_verdict_label(true, false, false, true, false, 0.0),
	]
	var wb: float = _maxpx(sb._font, bodies, 15)
	var wh: float = _maxpx(sb._font, heads, 20)
	if wb > HUD_ROOM:
		return _fail("⚠ a HUD body line is %.1f px, over the %.0f px column: '%s'. The origin is right-anchored, so NO window size rescues it — and slice 46 shipped a CHARACTER-count tooth that passed green while every line clipped at 1152 px AND 1920 px" % [wb, HUD_ROOM, _widest(sb._font, bodies, 15)])
	if wh > HEADLINE_ROOM:
		return _fail("⚠ a HEADLINE is %.1f px, over the %.0f px column: '%s' (they are drawn at 20 px)" % [wh, HEADLINE_ROOM, _widest(sb._font, heads, 20)])
	# ⭐ AND EVERY VERDICT STATE MUST BE DISTINCT, or the HUD has states it cannot tell apart.
	for i in range(heads.size()):
		for j in range(i + 1, heads.size()):
			if str(heads[i]) == str(heads[j]):
				return _fail("⭐ two verdict states render identically ('%s') — the HUD would have a state it cannot show" % str(heads[i]))
	# ⚠⚠ AND NO HEADLINE MAY NAME A **MISS**. This arc has banned that gauge three times and slice 50
	# re-earned the ban: above the slider's ceiling the CPA reverses FOUR times, because a blind coast
	# is an open-loop integration whose closest approach is chaotic in the initial condition.
	for s in heads:
		var low := str(s).to_lower()
		if low.contains("miss") or low.contains("cpa"):
			return _fail("⚠⚠ no headline may name the MISS or CPA — got '%s'. It is banned on this arc three times over, and above this slider's own ceiling it reverses four times" % s)
	# ⚠⚠ THE MARGIN IS PRINTED ON A **PASSING** RUN, ALONG WITH THE WIDEST LINE, AND THAT IS SLICE
	# 49's own hard-won addition rather than decoration: its first cure line came to exactly 390.0 px
	# against 390 px of room — a pass sitting ON the limit, one glyph from clipping and
	# indistinguishable from a comfortable pass unless the number and the line are both named.
	print("S50UI_WIDTH  bodies %.0f px (margin %.0f) / headlines %.0f px (margin %.0f), room %.0f — all %d verdict states distinct, none naming the miss. Widest: '%s'" %
		  [wb, HUD_ROOM - wb, wh, HEADLINE_ROOM - wh, HUD_ROOM, heads.size(), _widest(sb._font, bodies, 15)])

	# ══ TOOTH 11 — ONE SLIDER → set_param ON THE **TARGET** ════════════════════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("⚠ exactly ONE live knob (convention 9), got %d — `a_lat_mps2` is TWO-SIDED (it moves the intercept triangle as well as the aspect, which is the confound the sphere control exists to close) and `rcs_m2` would move the horizon UNDER the lesson" % sliders.size())
	mock.sent.clear()
	# ⚠ THE SIGNAL IS EMITTED EXPLICITLY. A slider built by a mock lives outside the SceneTree, so
	# assigning `.value` does not fire `value_changed` and the whole tooth would pass vacuously on an
	# empty `sent` list — slice 49's technique, and it is the difference between testing the WIRING
	# and testing the assignment.
	sliders[0].value = 10.0
	sliders[0].value_changed.emit(10.0)
	var sent_ok := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "rcs_fineness" \
				and str(d.get("target", "")) == TID and absf(float(d.get("value", 0.0)) - 10.0) < 1.0e-9:
			sent_ok = true
	if not sent_ok:
		return _fail("the slider must send set_param on the TARGET's `rcs_fineness` — the shape is the target's, not the missile's. Got %s" % str(mock.sent))
	# ⭐ AND THE CEILING IS **10, NOT SLICE 49's 12**, on a measurement: at F ≥ 11 the missile never
	# re-acquires, flies blind through CPA, and both its miss and its re-acquisition go non-monotone.
	if absf(sliders[0].max_value - 10.0) > 1.0e-9 or absf(sliders[0].min_value - 1.0) > 1.0e-9:
		return _fail("⭐ the slider must span 1–10 (got %.1f–%.1f). The ceiling is 10 and NOT slice 49's 12 because 11+ is a DIFFERENT MECHANISM — the lock is never given back and the outcome is a divergence being sampled" % [sliders[0].min_value, sliders[0].max_value])
	# …and the drag path must have disarmed this sandbox's latch too, which is the real wiring proof:
	# `_on_knob_dragged` has to be reached FROM the slider, not merely callable.
	if sb._s50_armed:
		return _fail("⭐⭐⭐ moving the actual SLIDER must reach `_on_knob_dragged` and disarm the latch — asserting the function in isolation would leave the wiring unproven, and the wiring is the half slice 49 found missing")
	print("S50UI_KNOB   one slider, 1–10, set_param on %s.rcs_fineness — and moving it DISARMS the latch through the real signal path" % TID)

	# ══ TOOTH 12 — ⭐ THE MIRROR THE OTHER WAY: a slice-48 wire keeps its own HUD ════════════════
	_sb_prior = _build_sandbox()
	_sb_prior._on_scenario({
		"name": "slice48_search",
		"knobs": [{"target": MID, "key": "seeker_search_rate_dps", "min": 0.0, "max": 240.0,
				   "value": 45.0, "label": "SEEKER SWEEP RATE (deg/s)"}],
		"fidelity": {"airframe": "six_dof", "autopilot": "alpha", "guidance": "pn",
					 "seeker": "filtered", "seeker_axes": "az_el", "seeker_detect": "snr"},
		"dt_physics": 1.0e-3,
		"airframe_view": true, "airframe_6dof": true, "airframe_target": MID,
		"seeker_detect_view": true, "midcourse_view": true, "search_view": true,
	})
	if _sb_prior._s50_view or _sb_prior._s50_target != "" or _sb_prior._s50_observer != "":
		return _fail("a slice-48 wire must raise no slice-50 marker and name no pair — its target authors no shape")
	if not _sb_prior._search_view:
		return _fail("⭐ …and it must KEEP its own search HUD — the slice-50 branch is checked FIRST in the HUD chain, so a bug there would steal slice 48's own lesson")
	# ⭐ AND ITS LATCH MUST BE UNTOUCHED AT ITS RESET VALUES — the marker gate is what makes every
	# scenario 1–49 "a chain of nothing" (slice 33's independent-`if` finding).
	_sb_prior._telemetry = _tel(false, 0.9, 4.0, 3000.0, 2000.0, 20.0)
	_sb_prior._airframe3d_on_state(_st(1.0))
	if _sb_prior._s50_latched or _sb_prior._s50_deg != 0.0 or not _sb_prior._s50_armed:
		return _fail("⭐ a slice-48 wire must leave all seven slice-50 instruments at their reset values even while its own telemetry sails past the edge condition (latched=%s, %.4f deg) — the marker gate is what makes every prior scenario a chain of nothing" % [_sb_prior._s50_latched, _sb_prior._s50_deg])
	print("S50UI_PRIOR  a slice-48 wire raises no slice-50 marker, keeps its search HUD, and its latch never fires")

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
	print("S50UI OK: the target's SHAPE decides WHEN it can be seen, so a defensive turn can take " +
		"back a lock the missile already had — and the price is paid in THE HEADING ERROR THE " +
		"MISSILE GOES BLIND HOLDING, not in the miss. ⭐⭐⭐ THE TOOTH NO OTHER PROOF REACHES IS THE " +
		"LIVE DRAG: this gauge is a latched INSTANT whose meaning is *when the from-launch flight " +
		"lost the picture*, so a drag must DISARM it rather than restart it — a latched DURATION " +
		"may restart mid-flight, a latched INSTANT may not. ⚠⚠ AND THE NULL AND THE FAILURE MODE " +
		"ARE THE SAME NUMBER here (0.000 deg either way), so key PRESENCE, not value, is what tells " +
		"a measured null from a dead instrument.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S50UI FAIL: " + msg)
	print("S50UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb_prior]:
		if sb != null and is_instance_valid(sb):
			sb.free()
