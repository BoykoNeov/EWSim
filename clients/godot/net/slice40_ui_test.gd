extends SceneTree
# Headless UI test for the slice-40 SERVO-ORDER view routing + HUD — the piece slice40_verify.gd
# can't reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT routing or the verdict this slice
# adds, and ⚠ ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL (convention
# 14) — which is why every line of this slice's HUD is a pure helper this file calls directly.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A MARKER THAT DOES **BOTH** JOBS, and it is only the second of this
# family to un-drop the shared button (slice 37's was the first):
#   THE BUTTON — a slice-40 wire raises `radome_view`, `gimbal_view` AND `gimbal_rate_view`, every
#     one of which HIDES the button. On this wire the press IS the lesson: a ringing missile goes
#     quiet when the servo goes back to the shipped first-order LAG, because a lag's index gain is
#     bounded by 1 and its phase by −90° at EVERY frequency and it cannot ring here at all.
#   THE HUD — without the branch, `gimbal_rate_view` takes the wire and slice 35's block draws a
#     DEMAND-vs-CAP pair against a rate limit AUTHORED WIDE HERE PRECISELY SO IT NEVER BINDS
#     (`sat_band` 0.00 % in every cell of the slider's domain). Every number TRUE, the verdict
#     "servo FREE", and the INERTIA ringing the missile never mentioned — slice 35's own
#     invisible-slice failure mode, pointed back at slice 35's own HUD.
#
# ⭐⭐ AND THERE IS A STATE ONLY THIS BRANCH CAN NAME: **ON THE FIRST-ORDER RUNG THIS SLICE'S SLIDER IS
# INERT.** A first-order head has no natural frequency and no damping ratio, so every value of
# `gimbal_zeta` flies the same missile there — bit-identically (`max|Δpos| == 0.0` over 800 frames,
# measured by the verifier). Slice 38's finding in a new key: a LIVE CONTROL THAT DOES NOTHING is the
# stale-readout class in a NEW form, not a stale number but a DEAD KNOB.
#
# ⚠ AND THE BUTTON IS A DIFFERENT FIDELITY FROM THE ONE BESIDE IT. Slices 37/38 cycle `seeker_head`
# (the servo's FRAME); this cycles `head_servo` (its ORDER). The slice-40 scenarios deliberately do
# NOT author `seeker_head`, so its marker stays down and this branch owns the button unambiguously
# (convention 9: one button, one lesson) — pinned below in both directions.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-40 handshake routes to _mode=airframe3d with the button VISIBLE at BOTH sites, on the
#      `head_servo` kind
#   2. ⭐⭐ THE MIRROR: strip the marker and the button VANISHES and the HUD becomes slice 35's — this
#      marker's two halves are BOTH load-bearing, unlike slice 38's
#   3. ⭐⭐ THE INERT STATE IS NAMED — the mechanism line changes across the button, and says INERT
#   4. ⭐ the VERDICT in all four states, and its third state is the one the slice is about
#   5. ⭐⭐ the GAIN line carries its two reference values and NO verdict (the other wire refuses it)
#   6. ⚠ WIDTHS: two budgets, ~55 for body lines and ~30 for headlines (slice 38's shots paid for it)
#   7. every key `_draw_head_servo_hud_lines` reads is present and scalar
#   8. ONE slider → set_param AND a button → set_fidelity, on the RIGHT key
#   9. ⭐ THE MIRROR THE OTHER WAY: a slice-38 wire must NOT raise the new marker and keeps its own
#  10. the value-guard, and the prior wires still route where they did
#
# Run:  godot --headless --path clients/godot --script res://net/slice40_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb38
var _sb37
var _sb35

# The slice-40 wire's telemetry at the numbers the verifier measures on its `open` arm. ⚠ NOTE WHAT
# IS HERE: the whole `radome_*` family (this wire HAS glass) AND the head/servo family — which is
# exactly why three earlier route markers fire on it and why the new one is checked ahead of them.
func _servo_tel(valid: bool, ring: float, wn: float, z: float, gain: float) -> Dictionary:
	return {
		"m1.los_range": 1800.0,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 25.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": 21.35,
		"m1.gimbal_rate_dps": 120.0,
		"m1.head_off_deg": 3.647,
		"m1.head_rate_dps": 9.4,
		"m1.head_rate_sat": 0.0,
		"m1.head_angle_deg": 22.876,
		"m1.look_angle": 22.876,
		"m1.look_body_deg": 17.31,
		"m1.lead_angle_deg": 14.64,
		# ⭐ THE SLICE'S OWN KEYS.
		"m1.gimbal_omega_hz": wn,
		"m1.gimbal_zeta": z,
		"m1.head_index_gain": gain,
		# THE GLASS — present, live and plausible, which is what makes the mis-branch dangerous here
		# rather than merely silent (slice 34's "nothing in it is stale" form).
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.18,
		"m1.radome_slope_worst": -0.33,
		"m1.radome_slope_az": -0.23,
		"m1.radome_residual": 0.15,
		"m1.radome_eps": -0.0004,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.04, "m1.omega_r": ring,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _servo_handshake(marker: bool, rung: String = "second_order") -> Dictionary:
	var h := {
		"name": "slice40_resonance",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠ THREE ROUTE MARKERS ARE RAISED ON THIS WIRE — that is the hazard, not an oversight, and
		# every one of them DROPS the button the lesson needs.
		"radome_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "gimbal_zeta", "min": 0.05, "max": 1.0, "value": 0.10,
			 "label": "GIMBAL DAMPING ζ — inertia is not the enemy, UNDAMPED inertia is"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "head_servo": rung},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["gimbal_servo_view"] = true
	return h

func _initialize() -> void:
	print("S40UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_servo_handshake(true))

	# ══ TOOTH 1 — ROUTE, and the button COMES BACK ═══════════════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-40 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_servo_view:
		return _fail("the client must record the `gimbal_servo_view` handshake marker")
	if not (sb._radome_view and sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠ a slice-40 wire is a slice-35 wire PLUS a rung, so it must STILL raise all THREE of those markers — each of which drops the button. That is the hazard the new marker exists for. Got rad=%s gim=%s rate=%s" % [sb._radome_view, sb._gimbal_view, sb._gimbal_rate_view])
	if sb._gimbal_frame_view:
		return _fail("⚠ a slice-40 wire must NOT raise `gimbal_frame_view` — the scenarios deliberately do not author `seeker_head`, because raising slice 37's marker would point the shared button at the servo's FRAME instead of its ORDER (convention 9: one button, one lesson)")
	if not sb._prop_btn.visible:
		return _fail("⭐⭐ a slice-40 handshake must RESTORE the shared button — three earlier markers drop it, and on this wire the PRESS IS THE LESSON (a lag cannot ring here at all)")
	if sb._fid_kind != "head_servo":
		return _fail("⭐ …and it must take the NEW `_fid_kind` (got %s) — `seeker_head` is a DIFFERENT fidelity (the servo's FRAME); this button cycles its ORDER" % sb._fid_kind)
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("routing must NOT skip _build_airframe3d_scene — slice 40 reuses the slice-23 3-D view wholesale")
	sb._update_fid_btn()
	if not (sb._prop_btn.visible and sb._prop_btn.text.contains("second_order")):
		return _fail("_update_fid_btn must keep the button visible and label it with the LIVE rung, got visible=%s '%s'" % [sb._prop_btn.visible, sb._prop_btn.text])
	print("S40UI_ROUTE  airframe3d + gimbal_servo_view recorded, all THREE earlier markers also raised, button RESTORED at both sites labelled '%s'" % sb._prop_btn.text)

	# ══ TOOTH 2 — ⭐⭐ THE MIRROR: strip the marker and BOTH halves fail ═══════════════════════════
	# ⚠⚠ UNLIKE SLICE 38's, THIS MARKER'S TWO HALVES ARE **BOTH** LOAD-BEARING, and the mirror is how
	# that is proven rather than asserted: without it the button VANISHES (three earlier markers drop
	# it) AND the HUD falls through to slice 35's servo block. Slice 38's "a branch selector, not a
	# hole plug" sentence does NOT transfer here — this one is both.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_servo_handshake(false))
	if _sb_nomarker._gimbal_servo_view:
		return _fail("the no-marker mirror must NOT record gimbal_servo_view")
	if _sb_nomarker._prop_btn.visible:
		return _fail("⭐⭐ THE HOLE: without `gimbal_servo_view` the button must be HIDDEN — `radome_view`/`gimbal_view`/`gimbal_rate_view` each drop it, and the press that IS this slice's lesson would be unavailable. If it stays visible, something else is showing it and this marker's button half is not load-bearing")
	if _sb_nomarker._mode != sb._mode:
		return _fail("⚠ the two must still share the VIEW — what the marker changes is the button and the HUD branch. Got %s/%s" % [_sb_nomarker._mode, sb._mode])
	print("S40UI_MIRROR without the marker the BUTTON VANISHES and the HUD falls through to slice 35's servo block — BOTH halves load-bearing, unlike slice 38's")

	# ══ TOOTH 3 — ⭐⭐ THE INERT STATE IS NAMED ════════════════════════════════════════════════════
	# On the first-order rung there is NO natural frequency and NO damping ratio, so this slice's
	# slider flies the same missile at every value — measured bit-identically by the verifier
	# (`max|Δpos| == 0.0` over 800 frames). A live control that does nothing has to be LABELLED, or
	# the student drags it and watches an unlabelled nothing (slice 38's finding, in a new key).
	var mech_2nd: String = sb._head_servo_mech_text(true, 2.0, 0.10)
	var mech_1st: String = sb._head_servo_mech_text(false, 2.0, 0.10)
	if mech_2nd == mech_1st:
		return _fail("⭐⭐ the mechanism line must CHANGE across the button — it is the only place the client can say that the slider is inert on one rung")
	# ⚠ THE PHRASE, NOT THE SUBSTRING — "INERTIA" CONTAINS "INERT", and the first draft of this tooth
	# failed on exactly that: the second-order line names the inertia and would have read as claiming
	# its own slider was dead. A substring check on a word that is a prefix of another word in the
	# same family is a false positive waiting for the one line that contains both.
	if not mech_1st.contains("slider INERT"):
		return _fail("⭐⭐ THE INERT STATE MUST BE NAMED on the first-order rung, got '%s'. The slider is bit-identically dead there (a lag has no ω_n and no ζ), and an unlabelled dead knob is the stale-readout class in a new form" % mech_1st)
	if mech_2nd.contains("slider INERT"):
		return _fail("…and NOT named on the second-order rung, where the slider is the whole lesson. Got '%s'" % mech_2nd)
	# ⚠ AND THE LAG LINE CARRIES NO τ — `gimbal_tau_s` is not a telemetry key, so a τ printed there
	# would be a CLIENT-SIDE CONSTANT dressed as data. It is also the weaker sentence: the bound holds
	# for EVERY τ, which is exactly why that rung cannot ring here.
	if not (mech_1st.contains("ANY τ") and mech_2nd.contains("ω_n")):
		return _fail("⭐ the lag line must state the bound holds at ANY τ (never a printed τ, which would be a client-side constant dressed as data) and the inertia line must name ω_n. Got '%s' / '%s'" % [mech_1st, mech_2nd])
	print("S40UI_INERT  '%s'  vs  '%s'" % [mech_2nd, mech_1st])

	# ══ TOOTH 4 — ⭐ THE VERDICT, and its THIRD state is the one the slice is about ════════════════
	var v_ring: String = sb._head_servo_verdict_label(false, true, true)
	var v_quiet: String = sb._head_servo_verdict_label(false, false, true)
	var v_lag: String = sb._head_servo_verdict_label(false, true, false)
	var v_lost: String = sb._head_servo_verdict_label(true, true, true)
	if v_ring == v_quiet or v_ring == v_lag or v_quiet == v_lag or v_lost == v_ring:
		return _fail("the four verdict states must be distinct, got '%s' / '%s' / '%s' / '%s'" % [v_ring, v_quiet, v_lag, v_lost])
	# ⭐⭐ THE THIRD STATE: the two rungs are NOT "bad" and "good". A first-order lag CANNOT ring on
	# this design at all (measured across an 800× τ sweep), so its label says WHY rather than
	# reporting a quiet it could not have failed to have.
	if not v_lag.contains("bounded"):
		return _fail("⭐⭐ the LAG verdict must name the BOUND rather than report a quiet — the lag is not merely quiet here, it is incapable of ringing (gain ≤ 1, phase ≥ −90°, at every frequency for every τ). Got '%s'" % v_lag)
	if not (v_ring.contains("RINGING") and v_quiet.contains("QUIET")):
		return _fail("the two second-order states must name the ring, got '%s' / '%s'" % [v_ring, v_quiet])
	print("S40UI_VERDICT '%s' | '%s' | '%s' | '%s'" % [v_ring, v_quiet, v_lag, v_lost])

	# ══ TOOTH 5 — ⭐⭐ THE GAIN LINE IS A LABEL, NOT A VERDICT ══════════════════════════════════════
	# The shipped `head_index_gain` is how much of the missile's own body motion reaches the part of
	# the dome the ray goes through. On THIS wire the ringing servo reads 3.07, above a strapdown
	# seeker's 1.00 — the intuitive story. ⚠⚠ AND THE OTHER WIRE REFUSES IT: `slice40_heavy` rings
	# just as hard at 0.095, a TENTH of the shipped lag's. So the line must carry its REFERENCE
	# VALUES and never a verdict, or the HUD would be asserting the thing the pair of wires disproves.
	var gtxt: String = sb._head_servo_gain_text(3.073)
	if not (gtxt.contains("1.00") and gtxt.contains("0.88")):
		return _fail("⭐⭐ the gain line must carry BOTH reference values — the shipped lag's 0.88 (the number slice 37 measured its whole margin out of) and a STRAPDOWN seeker's 1.00 — or the live number invites a comparison against nothing. Got '%s'" % gtxt)
	for w in ["RING", "QUIET", "STABLE", "UNSTABLE"]:
		if gtxt.contains(w):
			return _fail("⭐⭐ the gain line must NOT render a verdict (found '%s' in '%s') — two arms of this slice ring with this number 32× apart, which is the payload" % [w, gtxt])

	# ══ TOOTH 6 — ⚠ WIDTHS, TWO BUDGETS ══════════════════════════════════════════════════════════
	# Slice 38's shots proved ONE budget is not enough: its body-line tooth PASSED at ~55 characters
	# while BOTH new headlines ran off the right edge, because a headline is drawn LARGER and from a
	# different origin and its budget is ~30. The right-edge overrun's 5th occurrence was in a
	# headline; this pins both.
	# ⚠⚠ THE CURE LINE IS STATE-AWARE AND THE SHOT IS WHY: its first version advised "damp it (ζ→1)"
	# on an arm ALREADY at ζ = 1.00 and already quiet, under a verdict correctly reading "DAMPED
	# GIMBAL — loop QUIET". Every number true, the instruction stale. Pinned in all three states.
	var cure_ring: String = sb._head_servo_cure_text(true, true)
	var cure_damped: String = sb._head_servo_cure_text(true, false)
	var cure_lag: String = sb._head_servo_cure_text(false, true)
	if cure_ring == cure_damped:
		return _fail("⭐ the cure line must FOLLOW THE STATE — on a quiet damped arm it must not advise damping, which is the cure the student has already applied. Got '%s' twice" % cure_ring)
	if not cure_ring.contains("damp it"):
		return _fail("the RINGING second-order state must advise damping, got '%s'" % cure_ring)
	if cure_damped.contains("damp it"):
		return _fail("…and the QUIET damped state must NOT, got '%s'" % cure_damped)
	if sb._head_servo_cure_text(false, false) != cure_lag:
		return _fail("the lag rung's cure line must not depend on the ring — it cannot ring at all")
	var body_lines := [mech_2nd, mech_1st, gtxt, cure_ring, cure_damped, cure_lag]
	for s in body_lines:
		if s.length() > 55:
			return _fail("⚠ HUD body line is %d chars, over the measured ~55-character budget at 15 px from `vp.x − 430`: '%s'" % [s.length(), s])
	for s in [v_ring, v_quiet, v_lag, v_lost]:
		if s.length() > 30:
			return _fail("⚠ HEADLINE is %d chars, over the ~30-character budget (a headline is drawn LARGER and from a different origin — slice 38's shots paid for this number): '%s'" % [s.length(), s])
	print("S40UI_WIDTH  body lines ≤ %d chars (budget ~55), headlines ≤ %d (budget ~30)" %
		  [_maxlen(body_lines), _maxlen([v_ring, v_quiet, v_lag, v_lost])])

	# ══ TOOTH 7 — every key the HUD reads is present and scalar ═══════════════════════════════════
	sb._telemetry = _servo_tel(true, 0.517, 2.0, 0.10, 3.073)
	sb._af3d_missile = "m1"
	for k in ["m1.gimbal_omega_hz", "m1.gimbal_zeta", "m1.head_index_gain", "m1.head_off_deg",
			  "m1.gimbal_fov_margin_deg", "m1.omega_r"]:
		if not sb._telemetry.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		if typeof(sb._telemetry[k]) == TYPE_ARRAY or typeof(sb._telemetry[k]) == TYPE_DICTIONARY:
			return _fail("%s must be a SCALAR — `_update_readout` skips Array telemetry (the float() crash watch-item)" % k)

	# ══ TOOTH 8 — ONE slider → set_param, and the button → set_fidelity ON THE RIGHT KEY ══════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9), got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 0.45
	sliders[0].value_changed.emit(0.45)
	if mock.sent.size() != 1 or str(mock.sent[0].get("type", "")) != "set_param" \
			or str(mock.sent[0].get("key", "")) != "gimbal_zeta":
		return _fail("the slider must send set_param gimbal_zeta, got %s" % str(mock.sent))
	mock.sent.clear()
	sb._on_head_servo_pressed()
	if mock.sent.size() != 1 or str(mock.sent[0].get("type", "")) != "set_fidelity" \
			or str(mock.sent[0].get("key", "")) != "head_servo":
		return _fail("⭐ the button must send set_fidelity on `head_servo` — NOT `seeker_head`, which is a different slice's rung (the servo's FRAME). Got %s" % str(mock.sent))
	if str(mock.sent[0].get("value", "")) != "first_order":
		return _fail("…and it must advance second_order → first_order, got %s" % str(mock.sent[0].get("value", "")))
	sb._update_fid_btn()
	if not sb._prop_btn.text.contains("first_order"):
		return _fail("…and the label must follow the press, got '%s'" % sb._prop_btn.text)
	# …and it WRAPS (the cycler contract).
	mock.sent.clear()
	sb._on_head_servo_pressed()
	if str(mock.sent[0].get("value", "")) != "second_order":
		return _fail("the cycler must WRAP back to second_order, got %s" % str(mock.sent[0].get("value", "")))
	print("S40UI_CTRL   one slider → set_param gimbal_zeta; button → set_fidelity head_servo, and it wraps")

	# ══ TOOTH 9 — ⭐ THE MIRROR THE OTHER WAY: a slice-38 wire keeps its own ══════════════════════
	# If a slice-38 wire raised the new marker, the branch selector would select BOTH and slice 38's
	# HUD would be the one that disappears — the exact failure this file exists to prevent, inverted.
	_sb38 = _build_sandbox()
	_sb38._on_scenario({
		"name": "slice38_head_gyro", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"gimbal_rate_view": true, "gimbal_frame_view": true, "gimbal_gyro_view": true,
		"knobs": [], "dt_physics": 1.0e-3,
		"fidelity": {"airframe": "six_dof", "seeker_head": "space_stabilized"},
	})
	if _sb38._gimbal_servo_view:
		return _fail("⭐ THE MIRROR: a slice-38 wire must NOT raise `gimbal_servo_view`")
	if _sb38._fid_kind != "seeker_head" or not _sb38._prop_btn.visible:
		return _fail("…and it must keep slice 38's own routing (kind=%s visible=%s)" % [_sb38._fid_kind, _sb38._prop_btn.visible])

	# ══ TOOTH 10 — the value-guard: the prior wires still route where they did ════════════════════
	_sb37 = _build_sandbox()
	_sb37._on_scenario({
		"name": "slice37_frame", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"gimbal_rate_view": true, "gimbal_frame_view": true, "knobs": [], "dt_physics": 1.0e-3,
		"fidelity": {"airframe": "six_dof", "seeker_head": "body_referenced"},
	})
	if _sb37._gimbal_servo_view or _sb37._fid_kind != "seeker_head" or not _sb37._prop_btn.visible:
		return _fail("a slice-37 wire must keep its own routing (servo_view=%s kind=%s visible=%s)" % [_sb37._gimbal_servo_view, _sb37._fid_kind, _sb37._prop_btn.visible])
	_sb35 = _build_sandbox()
	_sb35._on_scenario({
		"name": "slice35_rate", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"gimbal_rate_view": true, "knobs": [], "dt_physics": 1.0e-3,
		"fidelity": {"airframe": "six_dof"},
	})
	if _sb35._gimbal_servo_view or _sb35._prop_btn.visible:
		return _fail("a slice-35 wire must raise no new marker and keep its button DROPPED (servo_view=%s visible=%s)" % [_sb35._gimbal_servo_view, _sb35._prop_btn.visible])
	print("S40UI_GUARD  slices 35 / 37 / 38 all route where they did, and none raises the new marker")

	return _pass()

func _maxlen(a: Array) -> int:
	var m := 0
	for s in a:
		m = maxi(m, str(s).length())
	return m

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
	print("S40UI OK: slices 34–39's head is a FIRST-ORDER LAG, and a lag is BOUNDED in both " +
		"currencies — its index gain can never exceed 1 and its phase can never pass −90°, at every " +
		"frequency for every τ — so it could only ever make the radome's index QUIETER, which is " +
		"exactly how slice 37's margin was bought. Give the gimbal an INERTIA and both bounds are " +
		"gone. ⭐⭐ THE CLIENT HALF IS A MARKER THAT DOES **BOTH** JOBS, only the second of this " +
		"family to un-drop the shared button: three earlier markers hide it and on this wire the " +
		"PRESS IS THE LESSON, while without the HUD branch slice 35's block would draw a " +
		"DEMAND-vs-CAP pair against a rate limit authored WIDE here precisely so it never binds — " +
		"every number true, the verdict 'servo FREE', and the inertia ringing the missile never " +
		"mentioned. ⭐⭐ AND THE STATE ONLY THIS BRANCH CAN NAME IS A DEAD KNOB: on the first-order " +
		"rung the ζ slider is BIT-IDENTICALLY INERT (a lag has no ω_n and no ζ), so the mechanism " +
		"line says INERT there. ⭐⭐ THE GAIN LINE IS A LABEL AND NEVER A VERDICT, because the other " +
		"wire refuses that reading: `slice40_heavy` rings just as hard at a TENTH of the lag's index " +
		"gain. ⚠ The button cycles `head_servo` (the servo's ORDER) and NOT `seeker_head` (its " +
		"FRAME) — a different fidelity, and no shipped wire authors both. ⚠ Two width budgets pinned " +
		"(~55 body, ~30 headline), and slices 35/37/38 all route exactly where they did.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S40UI FAIL: " + msg)
	print("S40UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb38, _sb37, _sb35]:
		if sb != null and is_instance_valid(sb):
			sb.free()
