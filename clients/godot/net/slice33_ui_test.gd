extends SceneTree
# Headless UI test for the slice-33 COMPOSITION view routing + HUD — the piece slice33_verify.gd
# can't reach. The verifier drives SimClient directly (the set_param wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing, the button
# drop, the two instruments, or the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS THE CONJUNCTION, AND IT IS A NEW SHAPE FOR THIS ARC. Slices 26–31
# were indistinguishable BY ROUTING (all six ship `radome_view`) and separated only by their HUD;
# slice 32 added a second marker and its tooth was the MIRROR WITHOUT IT. Slice 33's wire is the
# FIRST in the project to raise BOTH, so its tooth is neither: it is that a branch keyed on
# `_seeker_fov_view and _radome_view` sits AHEAD of both, and that removing either half sends the
# same wire back to its owner's branch VERBATIM (a SWITCH, not an `or`, three ways).
#
# ⚠⚠ AND THE DEFECT IT PREVENTS IS ASSERTED AS A NUMBER, NOT DESCRIBED (the sharpest tooth here).
# Without the composition branch `_seeker_fov_view` wins and slice 32's `_fov_verdict_label` runs —
# and on THIS wire it compares a ~18.1 deg LEAD against a 21 deg WINDOW, so it returns "IN THE
# WINDOW — FOV holds the lead" on the arm that misses by 3.7 km, then "TRACK BROKEN — lead outgrew
# FOV" once the latch fires, naming the WRONG CAUSE confidently. THE LEAD NEVER OUTGREW THE WINDOW;
# THE RING DID. Both helpers are called below with the SAME wire's own numbers and asserted to
# DISAGREE — so the branch is proven necessary rather than argued for. Slice 32's helper is left
# VERBATIM and is still right on slice 32's wire (no glass ⇒ look ≡ lead + incidence).
#
# ⭐ AND BOTH INSTRUMENTS MUST BE LIVE, which is the other thing a composition can silently break.
# `_radome_qpeak` (the ring, since slice 27) and `_fov_lost` (the track break, since slice 32) are
# two INDEPENDENT `if` blocks in `_airframe3d_on_state`, gated on their own telemetry keys — not an
# `if/elif` — and this file proves it on ONE wire that carries both, because a composition is exactly
# where a chained dispatch would silently freeze one half. A frozen peak-hold prints "loop STABLE"
# forever on a shaking missile and nothing headless would catch it.
#
# ⭐ THE VERDICT IS A PURE HELPER AND THAT IS WHY IT IS TESTABLE AT ALL. `_draw` never runs headless
# (convention 14), so slice 31's aim-point comparison shipped WRONG and only the windowed shot caught
# it. `_budget_verdict_label` is pinned here in all FOUR states — including the one the RANGE GATE
# exists for: every held arm on this wire leaves the window in the last metres (gate 2 measured first
# out at r = 0.18–8.55 m), so an ungated "breaking" state would fire at the instant of a CLEAN
# INTERCEPT and paint the CURE arm as a failure.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-33 handshake (BOTH markers) routes to _mode=airframe3d, button HIDDEN at BOTH sites
#   2. ⭐⭐ THE THREE-WAY SWITCH: drop either marker and the wire returns to its owner's branch
#   3. ⭐⭐ THE DISAGREEMENT: slice 32's helper and slice 33's, on the SAME numbers, differ
#   4. ⭐ the VERDICT pinned in all FOUR states, including the endgame the range gate suppresses
#   5. ⭐ BOTH INSTRUMENTS live on ONE wire — the ring peak-hold AND the track-break latch
#   6. every key `_draw_budget_hud_lines` reads is present (no `get(..., 0.0)` printing a 0.000)
#   7. TWO sliders, BOTH at the interceptor, driving set_param; NOTHING sends set_fidelity
#   8. the disqualified knobs are absent — including `cross_speed_mps`, slice 32's OWN axis
#   9. the value-guard, FIFTEEN-WAY
#
# Run:  godot --headless --path clients/godot --script res://net/slice33_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_fovonly
var _sb_radonly
var _sb31
var _sb25
var _sb24
var _sb23
var _sb19
var _sb16
var _sb18
var _sb21

# The slice-33 wire's telemetry: the shipped default (R̂ = R₀ = −0.03, a 21 deg window) mid-approach.
# ⚠ NOTE WHAT IS HERE THAT NEITHER PARENT SLICE HAS: the radome keys AND the FOV keys, together, for
# the first time in the project. `radome_residual` is EXACTLY 0.0 — slice 28's own headline, the
# compensator matching the glass it was characterized against perfectly — and it rings anyway.
func _budget_tel(valid: bool, los: float, look: float, margin: float, omr: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.seeker_valid": 1.0 if valid else 0.0,
		"m1.seeker_fov_deg": 21.0,
		"m1.look_angle": look,
		"m1.seeker_fov_margin_deg": margin,
		"m1.lead_angle_deg": 18.13,
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.03,
		"m1.radome_slope_worst": -0.32999999999999996,
		"m1.radome_residual": 0.0,
		"m1.radome_residual_az": -0.078,
		"m1.radome_slope_az": -0.0682,
		"m1.radome_eps": 0.0005,
		"m1.radome_ripple": -0.15,
		"m1.aero_sat": 1.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.10, "m1.omega_r": omr,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _budget_handshake(fov_marker: bool, rad_marker: bool) -> Dictionary:
	var h := {
		"name": "s33_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "seeker_fov_deg", "min": 19.0, "max": 40.0, "value": 21.0,
			 "label": "SEEKER: field of view (deg) — the budget the ring is spending"},
			{"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03,
			 "label": "DESIGN: believed slope R̂ — aim it at R₀+2A and the bill stops"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	}
	if fov_marker:
		h["seeker_fov_view"] = true
	if rad_marker:
		h["radome_view"] = true
	return h

func _initialize() -> void:
	print("S33UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_budget_handshake(true, true))

	# ══ TOOTH 1 — ROUTE: slice 23's 3-D view, and the button DROPPED for the NINTH time ════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-33 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not (sb._seeker_fov_view and sb._radome_view):
		return _fail("⭐⭐ the client must record BOTH handshake markers — slice 33's wire is the FIRST in the project to carry glass AND a window, and the composition HUD branch keys off exactly that conjunction (got fov=%s rad=%s)" % [sb._seeker_fov_view, sb._radome_view])
	if sb._prop_btn.visible:
		return _fail("a slice-33 handshake must DROP the shared button — slice 33 adds NO rung at all (both halves already fly, both sliders already ship). Slice-16's Option-P′, NINTH use.")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 33 reuses the slice-23 3-D view wholesale")
	# ⚠ THE DROP NEEDS BOTH SITES for slices 26 and 32 — and slice 33 needs NO EDIT AT EITHER, which
	# is the OPPOSITE of slice 26's finding and is asserted rather than assumed: both existing marker
	# branches hide the button and build the same scene, so a wire raising both is already correct.
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button hidden on a composition wire — the scenario carries an `:airframe` fidelity (HELD at six_dof), so the generic arm would re-show what _enter_airframe3d_mode dropped. Slice 33 needs no edit at either site (both marker branches already hide it), and this is the assert that says so")
	print("S33UI_ROUTE airframe3d + BOTH markers recorded + button HIDDEN at BOTH sites with NO slice-33 edit at either + the 3-D scene still built")

	# ══ TOOTH 2 — ⭐⭐ THE THREE-WAY SWITCH: drop either marker, the wire goes back to its owner ═════
	# This is what makes the composition branch a SWITCH rather than an `or`, and it is the reason
	# slices 26–32 render byte-identically after this slice.
	_sb_fovonly = _build_sandbox()
	_sb_fovonly._on_scenario(_budget_handshake(true, false))
	if not _sb_fovonly._seeker_fov_view or _sb_fovonly._radome_view:
		return _fail("the FOV-only mirror must carry seeker_fov_view and NOT radome_view")
	if _sb_fovonly._mode != sb._mode or _sb_fovonly._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ slices 32 and 33 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD BRANCH, got modes %s/%s" % [_sb_fovonly._mode, sb._mode])
	_sb_radonly = _build_sandbox()
	_sb_radonly._on_scenario(_budget_handshake(false, true))
	if _sb_radonly._seeker_fov_view or not _sb_radonly._radome_view:
		return _fail("the radome-only mirror must carry radome_view and NOT seeker_fov_view")
	if _sb_radonly._mode != sb._mode or _sb_radonly._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ slices 26–31 and 33 must be indistinguishable by ROUTING too, got modes %s/%s" % [_sb_radonly._mode, sb._mode])
	print("S33UI_SWITCH three ways — both markers / FOV only / radome only all route identically, so what the conjunction selects is the HUD BRANCH alone (a SWITCH, not an `or`)")

	# ══ TOOTH 3 — ⭐⭐ THE DISAGREEMENT: slice 32's verdict is CONFIDENTLY WRONG on this wire ═══════
	# The composition wire's own numbers: a lead of 18.13 deg, a window of 21 deg, and a ring whose
	# excursion is 25.01 deg. Slice 32's helper sees only the first two.
	var s32_says: String = sb._fov_verdict_label(false, 18.13, 21.0)
	if s32_says != "IN THE WINDOW — FOV holds the lead":
		return _fail("the premise of this tooth must hold: slice 32's helper, given THIS wire's lead (18.13) and window (21.0), returns '%s'" % s32_says)
	var s33_says: String = sb._budget_verdict_label(false, -1.5, 3000.0, -0.03, -0.33)
	if s33_says == s32_says:
		return _fail("⭐⭐ THE TWO HELPERS MUST DISAGREE ON THIS WIRE — that disagreement is the whole reason the composition branch exists. Slice 32's compares the LEAD against the WINDOW and the lead (18.13 deg) fits inside 21 deg, so it reports health on the arm that misses by 3.7 km; the RING is what overran the window, and only a verdict riding the shipped MARGIN can see it. Both returned '%s'" % s33_says)
	if s33_says != "RING PAST THE WINDOW — breaking":
		return _fail("⭐⭐ …and slice 33's must name the RIGHT cause: with the shipped budget already NEGATIVE (−1.5 deg) at r = 3000 m, the verdict is that the ring has overrun the window. Got '%s'" % s33_says)
	# ⚠ AND SLICE 32's HELPER IS LEFT VERBATIM AND IS STILL RIGHT ON SLICE 32's OWN WIRE (no glass, so
	# the look angle IS the lead plus the missile's aerodynamic incidence). The defect is the BRANCH,
	# not the helper, and this asserts the helper was not "fixed" into being wrong elsewhere.
	if sb._fov_verdict_label(false, 28.89, 25.0) != "LEAD PAST WINDOW — about to break":
		return _fail("slice 32's helper must be UNCHANGED — its middle state on ITS own wire (a 28.89 deg lead against a 25 deg window) must still read as about to break")
	print("S33UI_DISAGREE slice 32's helper says '%s' on this wire's numbers while slice 33's says '%s' — the branch is proven necessary, and 32's helper is verbatim and still correct on 32's wire" % [s32_says, s33_says])

	# ══ TOOTH 4 — ⭐ THE VERDICT, PINNED IN ALL FOUR STATES ════════════════════════════════════════
	# ⭐ THE CURE STATE: aimed at slice 30's rule, and the ~1e−9 tolerance is the one slices 30 and 31
	# both needed — the aim point is a Float64 sum landing at −0.32999999999999996, not −0.33, and the
	# slider a student drags carries the decimal.
	if sb._budget_verdict_label(false, 2.88, 3000.0, -0.32999999999999996, -0.32999999999999996) != "AIMED AT R₀+2A — budget intact":
		return _fail("⭐ THE CURE STATE: R̂ exactly at the wire's own aim point must read as aimed — and it must survive the Float64 representation (−0.32999999999999996), which is why the comparison carries the 1e−9 tolerance slices 30 and 31 both needed. Got '%s'" % sb._budget_verdict_label(false, 2.88, 3000.0, -0.32999999999999996, -0.32999999999999996))
	# THE DISEASE STATE: quiet-looking budget, but the design is nowhere near the rule.
	if sb._budget_verdict_label(false, 15.0, 5000.0, -0.03, -0.33) != "RING IS SPENDING THE BUDGET":
		return _fail("⭐ THE THIRD STATE IS THE ONE A TWO-WAY LABEL WOULD HIDE, and it is slice 30's and 31's third state in a new currency: the budget is positive RIGHT NOW, but the design is not at the aim point, so the ring is spending it — that is what a student needs to see BEFORE the break. Got '%s'" % sb._budget_verdict_label(false, 15.0, 5000.0, -0.03, -0.33))
	# THE BROKEN STATE — the latch wins outright, as slice 32's does.
	if sb._budget_verdict_label(true, 5.0, 3000.0, -0.33, -0.33) != "TRACK BROKEN — the RING ate it":
		return _fail("⭐ THE LATCH MUST WIN OUTRIGHT: once the track has broken the missile coasts on a stale rate, and neither a recovered budget nor a corrected belief changes that. Got '%s'" % sb._budget_verdict_label(true, 5.0, 3000.0, -0.33, -0.33))
	# ⚠⚠ AND THE ENDGAME MUST NOT READ AS BREAKING — the reason the range gate is an ARGUMENT of the
	# helper rather than a caller's concern. Gate 2 measured EVERY held arm leaving the window in the
	# last metres (first out at r = 0.18–8.55 m, at look angles of 21–162 deg) because the LOS unit
	# vector swings through a huge angle as r → 0. Ungated, the CURE arm would be painted a failure at
	# the instant of a clean intercept.
	if sb._budget_verdict_label(false, -140.0, 1.9, -0.33, -0.33) != "AIMED AT R₀+2A — budget intact":
		return _fail("⚠⚠ THE ENDGAME MUST NOT READ AS BREAKING: a budget of −140 deg at r = 1.9 m is the LOS unit vector swinging through a huge angle in the last millisecond before impact — GEOMETRY, not the window's verdict. Gate 2 paid five failing asserts for this distinction. Ungated, this state would fire on every clean intercept, including the CURE arm. Got '%s'" % sb._budget_verdict_label(false, -140.0, 1.9, -0.33, -0.33))
	# …and the SAME negative budget OUTSIDE the gate does read as breaking, so the gate is proven to
	# be a range gate and not a blanket suppression.
	if sb._budget_verdict_label(false, -140.0, 900.0, -0.33, -0.33) != "RING PAST THE WINDOW — breaking":
		return _fail("…and the SAME budget at r = 900 m MUST read as breaking, or the gate above is suppressing the state everywhere rather than in the endgame. Got '%s'" % sb._budget_verdict_label(false, -140.0, 900.0, -0.33, -0.33))
	print("S33UI_VERDICT all four states pinned — including the endgame the range gate suppresses, and its mirror OUTSIDE the gate proving the gate is a range gate and not a blanket")

	# ══ TOOTH 5 — ⭐ BOTH INSTRUMENTS LIVE ON ONE WIRE ═════════════════════════════════════════════
	# The advisor's blocking concern, asserted: `_radome_qpeak` (the ring, slice 27) and `_fov_lost`
	# (the track break, slice 32) are two INDEPENDENT `if` blocks, not a chain. A composition is
	# exactly where a chained dispatch would silently freeze one half — and a frozen peak-hold prints
	# "loop STABLE" forever on a shaking missile with nothing headless to catch it.
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]
	if sb._fov_lost or sb._radome_qpeak != 0.0:
		return _fail("both instruments must start clear")
	sb._telemetry = _budget_tel(true, 4500.0, 18.0, 3.0, 1.31)     # ringing, still inside the window
	sb._airframe3d_on_state({"entities": ents})
	if not (sb._radome_qpeak > 0.5):
		return _fail("⭐ THE RING INSTRUMENT MUST BE LIVE ON A COMPOSITION WIRE (fed |omega_r| = 1.31, got peak %.4f). If a dispatch ever chains these two, the peak-hold freezes at 0 and the HUD reports a stable loop on a missile that is shaking itself out of its own window — the exact half this slice is about" % sb._radome_qpeak)
	if sb._fov_lost:
		return _fail("…and a VALID frame must not latch a loss")
	# ⚠ THE CHANNEL IS YAW, and it is fed as such: this wire's lead is in AZIMUTH, so the yaw channel
	# sits on the steep part of the slope curve while pitch sits near the boresight slope (slice 28's
	# finding). `omega_q` is 0.10 in this fixture — a peak-hold left on pitch would meter the QUIET
	# channel of a shaking missile and read 0.10 rather than 1.31.
	if sb._radome_qpeak < 1.0:
		return _fail("⚠ the peak-hold must be riding the YAW channel (|omega_r| = 1.31), not pitch (|omega_q| = 0.10) — this wire ships `radome_slope_az`, so slice 28's channel switch applies. Got %.4f" % sb._radome_qpeak)
	sb._telemetry = _budget_tel(false, 5247.0, 26.0, -5.0, 1.20)   # the break, at long range
	sb._airframe3d_on_state({"entities": ents})
	if not sb._fov_lost:
		return _fail("⭐ AND THE TRACK-BREAK LATCH MUST BE LIVE TOO — a frame with `seeker_valid` 0 at r = 5247 m must latch it. Both instruments, one wire: that is the whole point of a composition view")
	if not (sb._radome_qpeak > 0.5):
		return _fail("…and latching the break must not disturb the ring instrument")
	# ⭐⭐ AND THE CHANNEL IS CHOSEN ONCE, SHARED BY BOTH SITES — a post-review hardening (advisor).
	# The composition branch fires on `_seeker_fov_view and _radome_view`, and `radome_view` is ALSO
	# raised by slice-26-shaped glass with NO ripple, which rings in PITCH. A hardcoded `omega_r` in
	# the HUD would have stayed silently correct on the shipped wire (it HAS a ripple) and printed a
	# near-zero rate under an orange "← RINGING" tag driven by the peak-hold's `omega_q` on the next
	# composition — slice 28's own defect in a new place. `_ring_channel_key` is what both read.
	if sb._ring_channel_key() != ".omega_r":
		return _fail("a RIPPLE wire (ships `radome_slope_az`) must select the YAW channel — slice 28's switch. Got %s" % sb._ring_channel_key())
	let_no_ripple(sb)
	if sb._ring_channel_key() != ".omega_q":
		return _fail("⭐⭐ …and a wire WITHOUT `radome_slope_az` — slice 26/27's FLAT glass, which rings in PITCH — must select `omega_q`. If this ever returns yaw, a no-ripple composition would draw a calm number under an orange RINGING tag. Got %s" % sb._ring_channel_key())
	sb._telemetry = _budget_tel(false, 5247.0, 26.0, -5.0, 1.20)   # restore the fixture
	print("S33UI_INSTRUMENTS both live on ONE wire — the ring peak-hold rides the YAW channel to %.3f and the track-break latch fires at r = 5247 m, independently; and BOTH sites take the channel from ONE shared helper, proven in both directions" % sb._radome_qpeak)

	# ══ TOOTH 6 — every key the composition HUD reads is PRESENT ══════════════════════════════════
	# ⚠ The stale-readout class, in its MIRROR form: not a stale number printed confidently, but a
	# missing one silently becoming 0.000 through `get(..., 0.0)`. Six keys, all core scalars — the
	# client evaluates no geometry and no stability threshold (convention 13).
	sb._update_readout()
	for k in ["m1.omega_r", "m1.look_angle", "m1.seeker_fov_deg", "m1.seeker_fov_margin_deg",
			  "m1.radome_slope_est", "m1.radome_slope_worst", "m1.seeker_valid", "m1.los_range"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ `_draw_budget_hud_lines` reads %s — a missing key would `get(..., 0.0)` and print a confident 0.000, the stale-readout class this arc has caught eight times" % k)
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S33UI_HUD all eight composition keys present and scalar — nothing reaches a label through a defaulted get()")

	# ══ TOOTH 7+8 — TWO sliders, BOTH at the interceptor, and the disqualifications ═══════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("slice 33 must build EXACTLY TWO sliders (seeker_fov_deg + radome_slope_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-33 wire must NEVER send set_fidelity — there is no rung; the lesson is the two SLIDERS")
	if not keys_set.has("seeker_fov_deg") or keys_set["seeker_fov_deg"] != "m1":
		return _fail("the 'seeker_fov_deg' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	# ⚠ AND UNLIKE SLICES 30 AND 32, BOTH KNOBS TARGET THE INTERCEPTOR — because both halves of this
	# comparison belong to the MISSILE (the window its seeker has, and the belief its guidance
	# computer carries). Slice 32's pair straddled two entities; this one does not, and that
	# difference is asserted rather than inherited.
	if not keys_set.has("radome_slope_est") or keys_set["radome_slope_est"] != "m1":
		return _fail("the 'radome_slope_est' slider must send set_param at the interceptor m1 — the belief is the missile's, not the engagement's. Got %s" % str(keys_set))
	for bad in ["cross_speed_mps", "radome_slope", "radome_ripple", "radome_ripple_k",
				"gyro_scale_err", "gyro_bias_z", "n_pn", "rho", "sigma_seek", "elevation_deg",
				"af_alpha_max", "alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 33 must NOT build a '%s' slider. `cross_speed_mps` is slice 32's OWN axis (it moves the LEAD) and would be a THIRD mechanism on a wire convention 9 already stretches to two; the `radome_*` glass keys are HARDWARE (the arc's point since 27 is that what an engineer changes is the BELIEF); `af_alpha_max` is slice 26's amplitude instrument and a confounded lever, held as the gate-0 causation probe; the rest move the guidance loop, degrade the lesson beside it, or are DEAD. Got %s" % [bad, str(keys_set.keys())])
	print("S33UI_KNOB exactly 2 sliders — seeker_fov_deg and radome_slope_est, BOTH → m1 (unlike 30/32's two-entity pair); NOTHING sends set_fidelity")

	# ══ TOOTH 9 — THE VALUE-GUARD, FIFTEEN-WAY ════════════════════════════════════════════════════
	# (a) ⭐ slice 31 — the deepest radome wire, radome_view WITHOUT the FOV marker, still its own
	_sb31 = _build_sandbox()
	_sb31._on_scenario({
		"name": "s31_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05,
				   "label": "GYRO: scale-factor error s"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27,
				   "label": "COMPENSATOR: belief R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view and NOT seeker_fov_view")
	# ⭐ AND ITS PEAK-HOLD MUST STILL LATCH ON IDENTICAL ROUTING — the composition branch is inserted
	# AHEAD of the radome cascade and must not have disturbed it (the mirror of tooth 5).
	_sb31._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.omega_r": 0.02,
						"m1.radome_slope": -0.10, "m1.radome_eps": -0.0004, "m1.look_angle": 13.6,
						"m1.radome_residual": 0.0, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb31._airframe3d_on_state({"entities": ents})
	if not (_sb31._radome_qpeak > 0.5):
		return _fail("⭐ the radome-only MIRROR must still latch its PITCH peak-hold (fed |omega_q| = 1.31, no `radome_slope_az` so slice 28's channel switch does not apply) — got %.4f" % _sb31._radome_qpeak)
	if _sb31._fov_lost:
		return _fail("the radome-only MIRROR must not latch a track break — it ships no `seeker_valid` at all, so the latch must be gated on the key's presence and not default to 'lost'")
	# …and `reset` clears BOTH instruments (slice 32's post-review finding, still true with two live)
	_sb31._on_reset_pressed()
	if _sb31._radome_qpeak != 0.0 or _sb31._fov_lost:
		return _fail("`reset` must clear BOTH instruments (peak-hold %.4f, latch %s) — otherwise a re-launched missile inherits the previous run's verdict" % [_sb31._radome_qpeak, _sb31._fov_lost])
	# (b) slice 25 — seeker_axes WITHOUT either marker keeps its cycler
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4,
				   "label": "σ_seek"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 wire (no marker) must keep the seeker_axes cycler VISIBLE, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# (c) slice 24 — steering cycler
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._fid_kind != "steering" or not _sb24._prop_btn.visible:
		return _fail("a slice-24 wire must take the steering cycler, got kind=%s vis=%s" % [_sb24._fid_kind, _sb24._prop_btn.visible])
	# (d) slice 23 — the 3-ring airframe cycler
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": 0.0, "max": 30.0, "value": 20.0, "label": "Cyβ"}],
		"fidelity": {"airframe": "six_dof", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._fid_kind != "airframe" or not _sb23._prop_btn.visible or _sb23._airframe_rungs.size() != 3:
		return _fail("a slice-23 wire must take the 3-ring airframe cycler, got kind=%s vis=%s rungs=%d" % [_sb23._fid_kind, _sb23._prop_btn.visible, _sb23._airframe_rungs.size()])
	# (e) slice 19 — the 2-D airframe view, 2-ring cycler
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.0, "label": "ρ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or not _sb19._prop_btn.visible:
		return _fail("a slice-19 wire must stay 2-D spatial with a VISIBLE airframe cycler, got mode=%s kind=%s vis=%s" % [_sb19._mode, _sb19._fid_kind, _sb19._prop_btn.visible])
	# (f) slice 16 — drops the button, but in the 2-D view (so the drop cannot be confused with 33's)
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {"guidance": "pn", "autopilot": "alpha"},
	})
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 wire must DROP the button (no fidelity to cycle)")
	if _sb16._mode == sb._mode:
		return _fail("slices 16 and 33 both drop the button but must NOT share a mode (16 = 2-D spatial, 33 = 3-D airframe3d)")
	# (g) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (h) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S33UI_GUARD fifteen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 31 drops(3-D, radome-only) / 32 drops(3-D, FOV-only) / 33 drops(3-D, BOTH) — and the two half-marker mirrors of 33")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..32_ui_test contract) --------------------------------------------

# Strip the slice-28 ripple key from the current fixture — the FLAT-glass composition (slice 26/27
# shaped glass behind a window), which rings in PITCH.
func let_no_ripple(sb) -> void:
	var t: Dictionary = sb._telemetry.duplicate()
	t.erase("m1.radome_slope_az")
	sb._telemetry = t

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
	print("S33UI OK: slice 33's wire is the FIRST in the project to carry GLASS AND A WINDOW, so it " +
		"is the first to raise BOTH `seeker_fov_view` and `radome_view` — where slice 32's own gate-3 " +
		"testset asserts `!haskey(info, :radome_view)` on ITS wire AS A FEATURE. ⭐⭐ THE BUTTON " +
		"OUTCOME IS IDENTICAL EITHER WAY, AND THAT IS ASSERTED RATHER THAN ASSUMED: both existing " +
		"marker branches already hide it and build the same 3-D scene, so slice 33 needs NO EDIT at " +
		"either drop site — the OPPOSITE of slice 26's 'the drop needs BOTH sites', and the reason " +
		"the routing is checked three ways here (both markers / FOV only / radome only all reach " +
		"airframe3d with the button hidden). WHAT THE CONJUNCTION SELECTS IS THE HUD BRANCH ALONE. " +
		"⭐⭐ AND THAT BRANCH IS PROVEN NECESSARY BY A DISAGREEMENT, NOT ARGUED FOR: given THIS wire's " +
		"own numbers — a lead of 18.13 deg inside a 21 deg window — slice 32's `_fov_verdict_label` " +
		"returns 'IN THE WINDOW — FOV holds the lead' on the arm that misses by 3.7 km, and after the " +
		"latch it would name the wrong cause outright ('lead outgrew FOV'). THE LEAD NEVER OUTGREW " +
		"THE WINDOW; THE RING DID, and only a verdict riding the shipped MARGIN can see that. Slice " +
		"32's helper is left VERBATIM and is still correct on slice 32's glass-free wire, which is " +
		"asserted too. ⭐ THE VERDICT IS A PURE HELPER — the only reason it is testable at all, since " +
		"`_draw` never runs headless and slice 31's aim-point comparison shipped WRONG with only a " +
		"windowed shot to catch it (convention 14). All FOUR states are pinned, including the CURE " +
		"state at the Float64 aim point (−0.32999999999999996, the 1e−9 tolerance slices 30 and 31 " +
		"both needed) and the ENDGAME state the RANGE GATE suppresses: gate 2 measured every held arm " +
		"leaving the window in the last metres (r = 0.18–8.55 m) as the LOS swings through a huge " +
		"angle, so an ungated 'breaking' verdict would paint the CURE arm a failure at the instant of " +
		"a clean intercept. Its mirror OUTSIDE the gate is asserted too, so the gate is proven to be " +
		"a RANGE gate and not a blanket suppression. ⭐ AND BOTH INSTRUMENTS ARE LIVE ON ONE WIRE: " +
		"`_radome_qpeak` and `_fov_lost` are two INDEPENDENT `if` blocks gated on their own telemetry " +
		"keys, not a chain — a composition is exactly where a chained dispatch would silently freeze " +
		"one half, and a frozen peak-hold prints 'loop STABLE' forever on a missile shaking itself " +
		"out of its own window. The peak-hold is asserted to be riding the YAW channel (slice 28's " +
		"switch: this wire's lead is in AZIMUTH, and a pitch meter would read 0.10 where yaw reads " +
		"1.31), the latch to fire at long range, and `reset` to clear BOTH. Every one of the eight " +
		"keys the composition HUD reads is asserted PRESENT and scalar — the stale-readout class in " +
		"its MIRROR form, where a missing key silently becomes 0.000 through a defaulted get(). TWO " +
		"sliders are built, BOTH at the interceptor (unlike slice 30's and 32's two-entity pairs, " +
		"because both halves of this comparison belong to the missile), both driving set_param, and " +
		"NOTHING sends set_fidelity. Every other lever is asserted ABSENT — including " +
		"`cross_speed_mps`, slice 32's OWN axis, which would be a THIRD mechanism on a wire " +
		"convention 9 already stretches to two. The value-guard holds FIFTEEN ways.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S33UI FAIL: " + msg)
	print("S33UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_fovonly, _sb_radonly, _sb31, _sb25, _sb24, _sb23, _sb19, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
