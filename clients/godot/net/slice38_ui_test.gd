extends SceneTree
# Headless UI test for the slice-38 HEAD-GYRO view routing + HUD — the piece slice38_verify.gd can't
# reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn smoke-load
# proves the scene loads. Neither exercises the CLIENT routing or the verdict this slice adds, and
# ⚠ ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention 14) — which
# is why every line of this slice's HUD is a pure helper this file calls directly.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS **A MARKER WHOSE ONLY JOB IS THE HUD**, and it is the second of this
# family to be so (slice 35's shape). A slice-38 wire is a slice-37 wire PLUS one comp key, so it
# raises `gimbal_frame_view` too and THE BUTTON IS ALREADY CORRECT — correct for a REASON rather than
# by luck, because `:seeker_head`'s two rungs are the two ENDS of this slice's own slider axis. What is
# NOT correct is the HUD: slice 37's block would take the wire, and EVERY KEY IT READS IS LIVE HERE, so
# it would print a fluent and entirely TRUE frame-comparison verdict — with a cure line naming
# `radome_slope_est` against `radome_slope_worst` — above a lesson about the SENSOR, on a wire where
# neither of those numbers is the control. The stale-readout class's WORST form (slice 34's), where
# nothing is stale.
#
# ⭐⭐ AND THERE IS A STATE ONLY THIS BRANCH CAN NAME: **ON THE BODY-REFERENCED RUNG THIS SLICE'S SLIDER
# IS INERT.** A body-referenced head has no stabilization gyro to corrupt, so every value of
# `head_gyro_scale_err` flies the same missile there — bit-identically (`max|Δpos| == 0.0` and the ring
# metric equal to nine digits, both measured by the verifier). A LIVE CONTROL THAT DOES NOTHING is the
# stale-readout class in a NEW form: not a stale number but a DEAD KNOB. A student who presses the
# button and then drags the slider would otherwise be watching an unlabelled nothing.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-38 handshake routes to _mode=airframe3d with the button VISIBLE at BOTH sites
#   2. ⭐⭐ THE MIRROR: strip the marker and slice 37's FRAME HUD takes the wire (a SWITCH, not an `or`)
#   3. ⭐⭐ THE INERT STATE IS NAMED — the mechanism line changes across the button, and says so
#   4. ⭐ the VERDICT in all four states, and it names the SENSOR rather than the frame
#   5. the sensor-spec line carries the leak, and the leak is NOT the index gain
#   6. ⚠ WIDTHS: every new line inside the measured ~55-character budget (the overrun's 5th guard)
#   7. every key `_draw_head_gyro_hud_lines` reads is present and scalar
#   8. ONE slider → set_param AND a button → set_fidelity
#   9. ⭐ THE MIRROR THE OTHER WAY: a slice-37 wire must NOT raise the new marker, and must keep its own
#  10. the value-guard, and the prior wires still route where they did
#
# Run:  godot --headless --path clients/godot --script res://net/slice38_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb37
var _sb36
var _sb35
var _sb34

# The slice-38 wire's telemetry, at the numbers the verifier measures. ⚠ NOTE WHAT IS HERE: the whole
# `radome_*` family (this wire HAS glass) AND the head/servo family — which is exactly why FOUR route
# markers fire on it and why the new one has to be checked ahead of all of them.
func _gyro_tel(valid: bool, los: float, off: float, margin: float, ring: float,
			   s: float, leak: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 25.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": margin,
		"m1.gimbal_rate_dps": 40.0,
		"m1.head_off_deg": off,
		"m1.head_rate_dps": 14.2,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 17.24,
		"m1.look_angle": 17.24,
		"m1.look_body_deg": 17.31,
		"m1.lead_angle_deg": 14.64,
		# ⭐ THE SLICE'S OWN KEYS.
		"m1.head_gyro_scale_err": s,
		"m1.head_gyro_bias_z": 0.0,
		"m1.head_gyro_leak": leak,
		# THE GLASS — present, live and plausible, which is what makes the mis-branch dangerous here
		# rather than merely silent (slice 34's "nothing in it is stale" form).
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.20,
		"m1.radome_slope_worst": -0.33,
		"m1.radome_slope_az": -0.23,
		"m1.radome_residual": 0.17,
		"m1.radome_eps": -0.0004,
		"m1.aero_sat": 1.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.04, "m1.omega_r": ring,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _gyro_handshake(marker: bool, rung: String = "space_stabilized") -> Dictionary:
	var h := {
		"name": "slice38_head_gyro",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠ FOUR ROUTE MARKERS ARE RAISED ON THIS WIRE — that is the hazard, not an oversight, and it
		# is one MORE than slice 37 had to contend with.
		"radome_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"gimbal_frame_view": true,
		"knobs": [
			{"target": "m1", "key": "head_gyro_scale_err", "min": -0.20, "max": 0.10, "value": 0.0,
			 "label": "HEAD GYRO scale error s — a WORSE gyro is a MORE STABLE missile"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_head": rung},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["gimbal_gyro_view"] = true
	return h

func _initialize() -> void:
	print("S38UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_gyro_handshake(true))

	# ══ TOOTH 1 — ROUTE, and the button STAYS (it is slice 37's, and it is right here) ════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-38 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_gyro_view:
		return _fail("the client must record the `gimbal_gyro_view` handshake marker")
	if not (sb._radome_view and sb._gimbal_view and sb._gimbal_rate_view and sb._gimbal_frame_view):
		return _fail("⚠ a slice-38 wire is a slice-37 wire PLUS one comp key, so it must STILL raise all FOUR of those markers — one more than slice 37 had. That is the hazard the new marker exists for. Got rad=%s gim=%s rate=%s frame=%s" % [sb._radome_view, sb._gimbal_view, sb._gimbal_rate_view, sb._gimbal_frame_view])
	if not sb._prop_btn.visible:
		return _fail("⭐ a slice-38 handshake must KEEP the shared button — it is slice 37's cycler and it is correct here for a REASON: `:seeker_head`'s two rungs are the two ENDS of this slice's slider axis, so pressing it is meaningful in a way it is not on slices 32–36")
	if sb._fid_kind != "seeker_head":
		return _fail("⭐ …and it must take slice 37's `_fid_kind` (got %s) — this slice adds no new kind, because the button it shows is the same button" % sb._fid_kind)
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — slice 38 reuses the slice-23 3-D view wholesale")
	sb._update_fid_btn()
	if not (sb._prop_btn.visible and sb._prop_btn.text.contains("space_stabilized")):
		return _fail("_update_fid_btn must keep the button visible and label it with the LIVE rung, got visible=%s '%s'" % [sb._prop_btn.visible, sb._prop_btn.text])
	print("S38UI_ROUTE  airframe3d + gimbal_gyro_view recorded, all FOUR earlier markers also raised, button VISIBLE at both sites labelled '%s'" % sb._prop_btn.text)

	# ══ TOOTH 2 — ⭐⭐ THE MIRROR: strip the marker and SLICE 37's HUD TAKES THE WIRE ═══════════════
	# ⚠⚠ THIS IS A **SWITCH, NOT AN `or`**, and the mirror is the only way to prove it: with the marker
	# stripped the button must be UNCHANGED (slice 37's branch keeps it) while the HUD must FALL
	# THROUGH to the frame block. If the button moved too, the two halves would be entangled and the
	# claim "this marker's job is the HUD alone" would be false.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_gyro_handshake(false))
	if _sb_nomarker._gimbal_gyro_view:
		return _fail("the no-marker mirror must NOT record gimbal_gyro_view")
	if not _sb_nomarker._prop_btn.visible:
		return _fail("⭐⭐ THE MIRROR: without `gimbal_gyro_view` the BUTTON must be UNCHANGED — slice 37's `gimbal_frame_view` branch keeps it, and this marker's job is the HUD alone. If the button vanished, the two halves are entangled")
	if _sb_nomarker._fid_kind != "seeker_head":
		return _fail("⭐⭐ …and the kind with it (got %s)" % _sb_nomarker._fid_kind)
	if _sb_nomarker._mode != sb._mode:
		return _fail("⚠ the two must still share the VIEW — what the marker changes is the HUD branch only. Got %s/%s" % [_sb_nomarker._mode, sb._mode])
	print("S38UI_MIRROR without the marker the BUTTON IS UNCHANGED (kind=%s, visible) and only the HUD branch falls through to slice 37's — a SWITCH, not an `or`" % _sb_nomarker._fid_kind)

	# ══ TOOTH 3 — ⭐⭐ THE INERT STATE IS NAMED ════════════════════════════════════════════════════
	# On the body-referenced rung there is NO stabilization gyro to corrupt, so this slice's slider
	# flies the same missile at every value — measured bit-identically by the verifier
	# (`max|Δpos| == 0.0`, `rms r` equal to nine digits). A live control that does nothing has to be
	# LABELLED, or the student drags it and watches an unlabelled nothing.
	var mech_stab: String = sb._head_gyro_mech_text(true)
	var mech_body: String = sb._head_gyro_mech_text(false)
	if mech_stab == mech_body:
		return _fail("⭐⭐ the mechanism line must CHANGE across the button — it is the only place the client can say that the slider is inert on one rung")
	if not mech_body.contains("INERT"):
		return _fail("⭐⭐ THE INERT STATE MUST BE NAMED on the body-referenced rung, got '%s'. The slider is bit-identically dead there (a body head has no stabilization gyro), and an unlabelled dead knob is the stale-readout class in a new form" % mech_body)
	if mech_stab.contains("INERT"):
		return _fail("…and NOT named on the stabilized rung, where the slider is the whole lesson. Got '%s'" % mech_stab)
	# …and the SPEC line changes with it, so the sensor's own number is not presented as live when it
	# is not being read by anything.
	var spec_live: String = sb._head_gyro_spec_text(-0.05, 0.05, false)
	var spec_inert: String = sb._head_gyro_spec_text(-0.05, 0.05, true)
	if spec_live == spec_inert:
		return _fail("⭐ the sensor-spec line must also change on the inert rung — the number is TRUE there and is being read by nothing, which is exactly the pairing that misleads")
	print("S38UI_INERT  the mechanism line names the dead knob: stabilized '%s' / body '%s'" % [mech_stab, mech_body])

	# ══ TOOTH 4 — ⭐ THE VERDICT NAMES THE SENSOR, NOT THE FRAME ══════════════════════════════════
	# ⚠ Slice 37's label would be TRUE on this wire and still wrong to show: its subject is which frame
	# the servo closes in, and here that is AUTHORED while the GYRO is what the student is dragging.
	var v_ring: String = sb._head_gyro_verdict_label(false, true, true)
	var v_quiet: String = sb._head_gyro_verdict_label(false, false, true)
	var v_body: String = sb._head_gyro_verdict_label(false, true, false)
	var v_lost: String = sb._head_gyro_verdict_label(true, true, true)
	if v_ring == v_quiet:
		return _fail("the verdict must distinguish RINGING from quiet")
	if not v_body.contains("no gyro"):
		return _fail("⭐⭐ on the body rung the verdict must say there is no gyro in this loop (got '%s') — reporting a ring the student cannot influence from there is the same defect as an unlabelled dead knob" % v_body)
	if v_body == v_ring:
		return _fail("…and it must not repeat the stabilized ringing verdict on a rung that has no gyro")
	if not v_lost.contains("TRACK LOST"):
		return _fail("the track-lost state must still win over everything (got '%s')" % v_lost)
	var v37: String = sb._frame_verdict_label(false, true, true)
	if v_ring == v37:
		return _fail("⭐ the slice-38 verdict must not be slice 37's — that one names the FRAME, which is AUTHORED here (got '%s' for both)" % v_ring)
	print("S38UI_VERDICT ring='%s' quiet='%s' body='%s'" % [v_ring, v_quiet, v_body])

	# ══ TOOTH 5 — THE LEAK IS ON THE LINE, AND IT IS NOT THE INDEX GAIN ═══════════════════════════
	# ⚠ Gate 0's FIRST REFUTATION: the index gain is what the glass sees AFTER the servo has also
	# acted, so it runs 1.000 → 0.886 rather than 1 → 0 (a head carried by the body is STILL SLEWED by
	# its servo, which is precisely slice 37's other rung). The line says "of body motion" and must not
	# claim an index gain the wire does not ship.
	if not spec_live.contains("20%") and not sb._head_gyro_spec_text(-0.20, 0.20, false).contains("20%"):
		return _fail("the sensor line must print the LEAK as a percentage of body motion, got '%s'" % sb._head_gyro_spec_text(-0.20, 0.20, false))
	if sb._head_gyro_spec_text(-0.20, 0.20, false).contains("index"):
		return _fail("⚠ the sensor line must NOT name an INDEX gain — the leak (|s|, 0 → 1) and the index gain (1.000 → 0.886) are different quantities, and gate 0's first refutation was exactly that confusion")
	var walk: String = sb._head_gyro_walk_text()
	if not (walk.contains("SPACE") and walk.contains("BODY")):
		return _fail("⭐ the payload line must name BOTH of slice 37's brackets — the slider walks between them (got '%s')" % walk)

	# ══ TOOTH 6 — ⚠ WIDTHS, MEASURED (the right-edge overrun's 5th guard after 26/28/36/37) ═══════
	# Knob labels are drawn FULL-WIDTH in the UI CanvasLayer, which paints OVER the Node2D `_draw` HUD
	# whose column starts at `vp.x − 430`; ~55 characters fit at 15 px. Slice 37's cure line shipped at
	# 59 and was caught only by a windowed capture, which is why this is pinned here instead.
	# ⚠⚠ TWO BUDGETS, NOT ONE, AND THAT SEPARATION IS WHAT THE FIRST PAIR OF SHOTS BOUGHT. This tooth
	# originally pinned ONE number — the ~55 characters the BODY lines are drawn against at 15 px from
	# `vp.x − 430` — and it PASSED while both new HEADLINES ran off the right edge in the capture
	# ("PERFECT-ish GYRO — RINGING: the index sees the body", 50 chars, and "GYRO LEAK — the ring is
	# bought by a WORSE sensor", 47). The headline is drawn LARGER and from a different origin, so its
	# budget is ~30: slice 37's longest is "SPACE-STABILIZED — loop STABLE" at exactly 30, and every
	# label in this family has quietly obeyed that without anyone writing it down until now.
	# ⇒ the right-edge overrun's 5th occurrence after 26/28/36/37, and THE FIRST IN A HEADLINE.
	for pair in [["mech(stab)", mech_stab], ["mech(body)", mech_body], ["spec(live)", spec_live],
				 ["spec(inert)", spec_inert], ["walk", walk],
				 ["spec(floor)", sb._head_gyro_spec_text(-0.20, 0.20, false)]]:
		if str(pair[1]).length() > 55:
			return _fail("⚠ HUD BODY line '%s' is %d characters, over the measured ~55 budget at 15 px from `vp.x − 430` — the part that gets cut is always the part that carries the meaning: '%s'" % [str(pair[0]), str(pair[1]).length(), str(pair[1])])
	for pair in [["verdict(ring)", v_ring], ["verdict(body)", v_body], ["verdict(quiet)", v_quiet],
				 ["verdict(lost)", v_lost]]:
		if str(pair[1]).length() > 30:
			return _fail("⚠⚠ HUD HEADLINE '%s' is %d characters, over the ~30 the headline is drawn against — a SEPARATE and much tighter budget than the body lines', because it is drawn larger and from a different origin. The first pair of slice-38 shots ran two headlines off the right edge while this very tooth passed at the body-line budget: '%s'" % [str(pair[0]), str(pair[1]).length(), str(pair[1])])
	print("S38UI_WIDTH  six body lines inside ~55 and four headlines inside ~30 — TWO budgets, which is what the first pair of shots cost")

	# ══ TOOTH 7 — EVERY KEY THE HUD READS IS PRESENT AND SCALAR ══════════════════════════════════
	sb._telemetry = _gyro_tel(true, 1800.0, 3.07, 21.9, 0.63, 0.0, 0.0)
	for k in ["m1.head_gyro_scale_err", "m1.head_gyro_leak", "m1.head_off_deg",
			  "m1.gimbal_fov_margin_deg", "m1.omega_r"]:
		if not sb._telemetry.has(k):
			return _fail("the slice-38 HUD reads '%s' and the wire must ship it" % k)
		if typeof(sb._telemetry[k]) == TYPE_ARRAY:
			return _fail("'%s' must be a SCALAR — `_update_readout` skips Arrays (the float() crash watch-item)" % k)

	# ══ TOOTH 8 — ONE SLIDER → set_param, AND THE BUTTON → set_fidelity ══════════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("the slice-38 wire must build EXACTLY ONE slider (got %d) — convention 9, and on this wire the second control is the BUTTON, which is the SAME AXIS expressed discretely" % sliders.size())
	mock.sent.clear()
	sliders[0].value = -0.05
	sliders[0].value_changed.emit(-0.05)
	var saw_param := false
	for m in mock.sent:
		if str(m.get("type", "")) == "set_param" and str(m.get("key", "")) == "head_gyro_scale_err":
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send `set_param head_gyro_scale_err` — the SENSOR axis, and the only live control besides the button")
	mock.sent.clear()
	sb._prop_btn.emit_signal("pressed")
	var saw_fid := false
	for m in mock.sent:
		if str(m.get("type", "")) == "set_fidelity" and str(m.get("key", "")) == "seeker_head":
			saw_fid = true
	if not saw_fid:
		return _fail("⭐ pressing the button must send `set_fidelity seeker_head` — the rung, never a set_param. The client owns the DISPLAYED rung, so the label must move with the press (slice 19's lying-picture lesson, paid for twice)")
	if not sb._prop_btn.text.contains("body_referenced"):
		return _fail("…and the LABEL must move with it, got '%s'" % sb._prop_btn.text)
	print("S38UI_WIRE   slider → set_param head_gyro_scale_err, button → set_fidelity seeker_head, label '%s'" % sb._prop_btn.text)

	# ══ TOOTH 9 — ⭐ THE MIRROR THE OTHER WAY: a slice-37 wire keeps its own HUD ══════════════════
	# ⚠ A slice-37 wire authors NO `head_gyro_*` key, so the core cannot raise this marker there — and
	# if it somehow did, slice 37's frame HUD would be replaced by a gyro block on a wire with no gyro
	# to speak of. The pairing is asserted in both directions because a marker that fires too widely is
	# the same defect as one that fires too narrowly.
	_sb37 = _build_sandbox()
	var h37 := _gyro_handshake(false, "body_referenced")
	h37["name"] = "slice37_frame"
	h37["knobs"] = [{"target": "m1", "key": "radome_slope_est", "min": -0.33, "max": -0.14,
					 "value": -0.18, "label": "DESIGN: believed slope R̂"}]
	_sb37._on_scenario(h37)
	if _sb37._gimbal_gyro_view:
		return _fail("⭐ a slice-37 wire must NOT raise gimbal_gyro_view — it authors no head_gyro_* key at all")
	if not _sb37._prop_btn.visible or _sb37._fid_kind != "seeker_head":
		return _fail("…and it must keep its own button and kind (visible=%s kind=%s)" % [_sb37._prop_btn.visible, _sb37._fid_kind])
	print("S38UI_37     a slice-37 wire keeps its own HUD and button, and does not raise the new marker")

	# ══ TOOTH 10 — THE VALUE-GUARD: the earlier wires still route where they did ══════════════════
	_sb36 = _build_sandbox()
	_sb36._on_scenario({"name": "slice36_handover", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "gimbal_view": true, "gimbal_rate_view": true,
		"gimbal_handover_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_rate_dps", "min": 6.0, "max": 60.0, "value": 8.0,
				   "label": "servo"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"}, "dt_physics": 1.0e-3})
	if _sb36._gimbal_gyro_view:
		return _fail("a slice-36 wire must not raise gimbal_gyro_view")
	if _sb36._prop_btn.visible:
		return _fail("a slice-36 wire must still DROP the button (gimbal_handover_view does both jobs there)")
	_sb35 = _build_sandbox()
	_sb35._on_scenario({"name": "slice35_rate", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true, "gimbal_rate_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_rate_dps", "min": 8.0, "max": 60.0, "value": 40.0,
				   "label": "servo"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"}, "dt_physics": 1.0e-3})
	if _sb35._gimbal_gyro_view or _sb35._prop_btn.visible:
		return _fail("a slice-35 wire must not raise gimbal_gyro_view and must still drop the button")
	_sb34 = _build_sandbox()
	_sb34._on_scenario({"name": "slice34_gimbal", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"knobs": [{"target": "m1", "key": "radome_slope_est", "min": -0.33, "max": -0.03,
				   "value": -0.18, "label": "belief"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"}, "dt_physics": 1.0e-3})
	if _sb34._gimbal_gyro_view or _sb34._prop_btn.visible:
		return _fail("a slice-34 wire must not raise gimbal_gyro_view and must still drop the button")
	print("S38UI_GUARD  slices 34 / 35 / 36 / 37 all route where they did, and none raises the new marker")

	return _pass()

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
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
	print("S38UI OK: slice 37 showed that stabilizing the seeker head in space REMOVES stability " +
		"margin, and that whole result rests on a PERFECT gyro — the §1 approximation it named FIRST " +
		"among its own deferrals. Slice 38 corrupts that sensor, and slice 37's stability boundary " +
		"WALKS with gyro quality: the two architectures it shipped as a BUTTON are the two ENDS of ONE " +
		"HARDWARE SPEC, and A WORSE GYRO IS A MORE STABLE MISSILE. ⭐⭐ THE CLIENT HALF IS A MARKER " +
		"WHOSE ONLY JOB IS THE HUD — the second of this family to be so (slice 35's shape) — because a " +
		"slice-38 wire is a slice-37 wire PLUS one comp key: it raises FOUR earlier route markers, the " +
		"BUTTON is already correct (the two rungs are the two ends of this slider's own axis), and " +
		"what is wrong without the marker is the HUD, where slice 37's block would print a fluent and " +
		"entirely TRUE verdict about the SERVO'S FRAME — plus a cure line naming a slider this wire " +
		"does not have — above a lesson about the SENSOR. The stale-readout class's WORST form, where " +
		"nothing is stale. ⭐⭐ AND THE STATE ONLY THIS BRANCH CAN NAME IS A DEAD KNOB: on the " +
		"body-referenced rung the slider is BIT-IDENTICALLY INERT (a body head has no stabilization " +
		"gyro to corrupt), so the mechanism line says INERT there rather than leaving a student to " +
		"drag a live control and watch nothing happen — the stale-readout class in a NEW form, not a " +
		"stale number but a dead one. ⚠ The mirror proves the branch is a SWITCH and not an `or`: " +
		"strip the marker and the BUTTON is unchanged while only the HUD falls through. ⚠⚠ AND THE " +
		"WIDTH TOOTH PINS **TWO** BUDGETS BECAUSE THE FIRST PAIR OF SHOTS PROVED ONE WAS NOT ENOUGH: " +
		"six body lines inside ~55 characters and four HEADLINES inside ~30, which is a separate and " +
		"much tighter budget (the headline is drawn larger and from a different origin). Both new " +
		"headlines ran off the right edge in the capture WHILE THIS TOOTH PASSED at the body-line " +
		"number — the right-edge overrun's 5th occurrence after 26/28/36/37 and the FIRST in a " +
		"headline. ⚠ The leak is never presented as an index gain (gate 0's first refutation), and " +
		"slices 34/35/36/37 all route exactly where they did.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S38UI FAIL: " + msg)
	print("S38UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb37, _sb36, _sb35, _sb34]:
		if sb != null and is_instance_valid(sb):
			sb.free()
