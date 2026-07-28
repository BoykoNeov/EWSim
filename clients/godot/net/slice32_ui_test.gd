extends SceneTree
# Headless UI test for the slice-32 SEEKER-FOV view routing + HUD — the piece slice32_verify.gd
# can't reach. The verifier drives SimClient directly (the set_param wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing, the
# button drop, the track-break latch, or the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS THE MARKER-VS-NO-MARKER MIRROR, and it is a different shape from
# 26-31's. Those six were indistinguishable BY ROUTING (all six ship `radome_view`) and separated
# only by their HUD. Slice 32 ships a NEW marker, `seeker_fov_view`, and the tooth is what happens
# WITHOUT it: a FOV wire holds `seeker_axes` at az_el (the window lives in the two-angle seeker, and
# the LOADER refuses `seeker_fov_deg` without `two_angle: true`), so the dispatch would fall through
# to slice 25's `seeker_axes` CYCLER — whose other position, `:pitch_plane`, leaves the WINDOW LIVE
# on a missile that ALSO misses by 2000 m for a wholly unrelated reason. Two mechanisms compounding
# in one view is exactly what convention 9 exists to prevent, and it is the "identical signature,
# different mechanism" trap slice 25 spent a section on. The mirror below is the SAME handshake with
# the marker REMOVED, and it must take the cycler — so the marker is proven to be what drops the
# button, rather than assumed.
#
# ⚠ AND THE HUD MUST BE ITS OWN BRANCH, NEVER A RUNG OF THE RADOME CASCADE. That cascade reads
# `radome_slope` / `radome_residual` / `radome_slope_worst` / …, and a FOV wire has NONE of them, so
# every line would `get(..., 0.0)` and print a confident 0.000 — the stale-readout class this arc has
# caught seven times, and precisely what gate 2's blocking advisor catch was about one layer up.
#
# ⭐ THE VERDICT IS A PURE HELPER AND THAT IS WHY IT IS TESTABLE AT ALL. `_draw` never runs headless
# (convention 14), so slice 31's aim-point comparison shipped WRONG and only the windowed shot caught
# it. `_fov_verdict_label` is pinned here in all THREE states — and the middle one is the state a
# two-way label would hide: the lead has passed the window but the tracker has not dropped yet.
#
# ⭐ AND THE LATCH IS A TOOTH, NOT A DETAIL. `_fov_lost` is a LATCH where slice 27's `_radome_qpeak`
# is a decaying peak-hold, because the two answer different questions: a limit cycle crosses zero
# twice per cycle so its verdict must FORGET, while a track break is a THING THAT HAPPENED — the
# missile coasts on a stale rate from then on. An instantaneous `seeker_valid` would blink back to 1
# the moment the runaway geometry swings the LOS back through the window and label a lost missile
# "tracking". ⚠ It is RANGE-GATED at r > 200 m for the same reason every look-angle number in this
# slice is: a healthy intercept leaves the window for one or two ticks at r = 0.1-0.6 m as the LOS
# swings through a large angle in the last millisecond, and latching on that would paint every hit as
# a lost track. Both directions are asserted.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-32 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. ⭐⭐ THE MARKER MIRROR: the same handshake WITHOUT `seeker_fov_view` takes slice 25's cycler
#      with the button VISIBLE — so the marker is what drops it
#   3. ⭐ the VERDICT helper pinned in all THREE states, including the middle one
#   4. ⭐ the LATCH: it latches at long range, SURVIVES a return to valid, and does NOT latch on the
#      endgame excursion inside 200 m
#   5. the HUD branch is its own: no radome key on the wire, and the radome peak-hold never engages
#   6. TWO sliders, driving set_param at DIFFERENT entities (the window at the missile, the
#      engagement at the TARGET — a first for this arc's sliders); NOTHING sends set_fidelity
#   7. the disqualified knobs are absent — including every radome key (a SECOND mechanism)
#   8. the value-guard, FOURTEEN-WAY (16 / 18 / 19 / 21 / 23 / 24 / 25 / 26 / 30 / 31 / 32)
#
# Run:  godot --headless --path clients/godot --script res://net/slice32_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomark
var _sb26
var _sb31
var _sb25
var _sb24
var _sb23
var _sb19
var _sb16
var _sb18
var _sb21

# The slice-32 wire's telemetry: a BROKEN arm mid-approach. ⚠ NOTE WHAT IS *NOT* HERE — no
# `radome_*` key of any kind. The showcase wire carries no glass by design (convention 9: a ringing
# arm's look angle swings BECAUSE it rings, so the angle measured on one belongs to the LOOP and not
# to the ENGAGEMENT), and that absence is exactly what tooth 5 checks.
func _fov_tel(valid: bool, los: float, look: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.seeker_valid": 1.0 if valid else 0.0,
		"m1.seeker_fov_deg": 25.0,
		"m1.look_angle": look,
		"m1.lead_angle_deg": 28.89,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.11,
		"m1.omega_q": 0.02, "m1.omega_r": 0.03,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _fov_handshake(with_marker: bool) -> Dictionary:
	var h := {
		"name": "s32_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "seeker_fov_deg", "min": 20.0, "max": 40.0, "value": 25.0,
			 "label": "SEEKER: field of view (deg)"},
			{"target": "tgt1", "key": "cross_speed_mps", "min": 0.0, "max": 400.0, "value": 400.0,
			 "label": "ENGAGEMENT: target crossing speed (m/s)"},
		],
		# ⚠ `seeker_axes` HELD at az_el — the window lives in the two-angle seeker, which is also why
		# the loader REFUSES `seeker_fov_deg` without `two_angle: true`. It is precisely this key that
		# makes the marker load-bearing.
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	}
	if with_marker:
		h["seeker_fov_view"] = true
	return h

func _initialize() -> void:
	print("S32UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_fov_handshake(true))

	# ══ TOOTH 1 — ROUTE: slice 23's 3-D view, and the button DROPPED for the EIGHTH time ═══════════
	if sb._mode != "airframe3d":
		return _fail("a slice-32 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._seeker_fov_view:
		return _fail("the client must record the `seeker_fov_view` handshake marker")
	if sb._prop_btn.visible:
		return _fail("a slice-32 handshake must DROP the shared button — slice 32 adds NO rung (`seeker_fov_deg` = 180 flies the key-absent trajectory on this wire, so atmosphere.jl's knob-vs-rung discriminator returns KNOB). Slice-16's Option-P′, EIGHTH use.")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 32 reuses the slice-23 3-D view wholesale")
	# ⚠ THE DROP NEEDS BOTH SITES, exactly as slice 26 found for its second use: `_update_fid_btn` is
	# called on every badge refresh and its "airframe" arm would RE-SHOW the button, because this
	# scenario really does carry an `:airframe` fidelity (HELD at six_dof).
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button hidden on a FOV wire — the scenario carries an `:airframe` fidelity (HELD at six_dof), so the generic arm would re-show the button that _enter_airframe3d_mode dropped, and cycling a HELD key is the convention-9 trap")
	print("S32UI_ROUTE airframe3d + button HIDDEN at BOTH sites + the 3-D scene still built")

	# ══ TOOTH 2 — ⭐⭐ THE MARKER MIRROR: without it, slice 25's cycler takes the wire ════════════════
	_sb_nomark = _build_sandbox()
	_sb_nomark._on_scenario(_fov_handshake(false))
	if _sb_nomark._mode != "airframe3d":
		return _fail("the no-marker mirror must still reach airframe3d (it is the same 6-DOF wire), got %s" % _sb_nomark._mode)
	if _sb_nomark._fid_kind != "seeker_axes" or not _sb_nomark._prop_btn.visible:
		return _fail("⭐⭐ THE MARKER MUST BE WHAT DROPS THE BUTTON, and this mirror is the proof: the SAME handshake WITHOUT `seeker_fov_view` must fall through to slice 25's seeker_axes CYCLER with the button VISIBLE (got kind=%s vis=%s). If it does not, this test is asserting nothing — and the shipped wire would offer a student a cycler whose other position (:pitch_plane) leaves the WINDOW LIVE on a missile that ALSO misses by 2000 m for an unrelated reason" % [_sb_nomark._fid_kind, _sb_nomark._prop_btn.visible])
	print("S32UI_MARKER without `seeker_fov_view` the SAME wire takes slice 25's cycler (button VISIBLE) — the marker is what drops it, proven rather than assumed")

	# ══ TOOTH 3 — ⭐ THE VERDICT, PINNED IN ALL THREE STATES ════════════════════════════════════════
	# The comparison is the whole lesson in one line: the ENGAGEMENT's demand (`lead_angle_deg`, the
	# collision triangle's own lead) against the HARDWARE's limit (`seeker_fov_deg`), in the same
	# degrees, both from the CORE. ⚠ The MIDDLE state is the one a two-way label would hide.
	if sb._fov_verdict_label(false, 28.89, 30.0) != "IN THE WINDOW — FOV holds the lead":
		return _fail("a lead of 28.89 deg inside a 30 deg window must read as HELD — got '%s'" % sb._fov_verdict_label(false, 28.89, 30.0))
	if sb._fov_verdict_label(false, 28.89, 25.0) != "LEAD PAST WINDOW — about to break":
		return _fail("⭐ THE MIDDLE STATE: a lead of 28.89 deg against a 25 deg window, with the tracker not yet dropped, must say so — that is where a student watching the crossing-speed slider is ABOUT to lose the engagement, and a two-way label would show it as healthy. Got '%s'" % sb._fov_verdict_label(false, 28.89, 25.0))
	if sb._fov_verdict_label(true, 28.89, 30.0) != "TRACK BROKEN — lead outgrew FOV":
		return _fail("⭐ THE LATCH MUST WIN OUTRIGHT: once the track has broken the missile is coasting on a stale rate, and no amount of current geometry changes that — even a lead that now fits. Got '%s'" % sb._fov_verdict_label(true, 28.89, 30.0))
	# …and the boundary is the comparison itself, with NO client-side margin on the physics.
	if sb._fov_verdict_label(false, 25.0, 25.0) != "IN THE WINDOW — FOV holds the lead":
		return _fail("the comparison must be `lead <= fov` with no invented margin — a lead exactly equal to the window is inside it, matching `seeker_in_fov`'s own `<=` (pinned without a tolerance in test_frames.jl)")
	print("S32UI_VERDICT all three states pinned, including the middle one a two-way label would hide")

	# ══ TOOTH 4 — ⭐ THE LATCH: it remembers, and it does NOT fire on the endgame ═══════════════════
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]
	if sb._fov_lost:
		return _fail("the latch must start clear")
	sb._telemetry = _fov_tel(true, 4500.0, 24.1)
	sb._airframe3d_on_state({"entities": ents})
	if sb._fov_lost:
		return _fail("a VALID frame must not latch a loss")
	sb._telemetry = _fov_tel(false, 4120.0, 25.4)          # the break, at long range
	sb._airframe3d_on_state({"entities": ents})
	if not sb._fov_lost:
		return _fail("a frame with `seeker_valid` 0 at r = 4120 m must latch the track break — that is the whole mechanism")
	sb._telemetry = _fov_tel(true, 2000.0, 12.0)           # the runaway swings the LOS back through
	sb._airframe3d_on_state({"entities": ents})
	if not sb._fov_lost:
		return _fail("⭐ THE LATCH MUST SURVIVE A RETURN TO VALID: a runaway geometry swings the LOS back through the window, and an instantaneous flag would label a missile that lost its target seconds ago 'tracking'. This is the one behavioural difference from slice 27's DECAYING peak-hold, and it is deliberate")
	# …and the ENDGAME must NOT latch: a healthy intercept leaves the window for a tick or two inside
	# 200 m as the LOS swings through a large angle in the last millisecond before impact.
	var sb2 = _build_sandbox()
	sb2._on_scenario(_fov_handshake(true))
	sb2._telemetry = _fov_tel(false, 0.4, 96.0)
	sb2._airframe3d_on_state({"entities": ents})
	if sb2._fov_lost:
		return _fail("⚠ THE ENDGAME MUST NOT LATCH: an out-of-window frame at r = 0.4 m is the LOS unit vector swinging through a large angle in the last millisecond before impact — GEOMETRY, not the window's verdict (gate 2 measured it; `%.1f` had hidden it as '0.0 %'). Latching there would paint every healthy intercept as a lost track")
	sb2.free()
	print("S32UI_LATCH latches at long range, SURVIVES a return to valid, and ignores the endgame excursion inside 200 m")

	# ══ TOOTH 5 — the HUD is its OWN branch: no radome key, and the radome peak-hold never engages ══
	sb._update_readout()
	for bad in ["m1.radome_slope", "m1.radome_residual", "m1.radome_residual_az", "m1.radome_eps",
				"m1.radome_slope_worst", "m1.radome_slope_est", "m1.gyro_scale_err",
				"m1.cross_speed_mps", "m1.radome_sched_slope"]:
		if sb._telemetry.has(bad):
			return _fail("⚠ a slice-32 wire must carry NO radome/gyro key (found %s) — the showcase has no glass BY DESIGN (convention 9), and a HUD branch that read one would print a confident 0.000 into a label: the stale-readout class this arc has caught seven times" % bad)
	if sb._radome_qpeak != 0.0:
		return _fail("the radome peak-hold must never engage on a FOV wire (it is gated on `radome_residual`, which this wire does not ship) — got %.4f" % sb._radome_qpeak)
	# …and every quantity the lesson turns on arrives from the CORE as a scalar (convention 13: the
	# client compares two shipped degrees and reports a shipped boolean; it evaluates no triangle).
	for k in ["m1.seeker_fov_deg", "m1.lead_angle_deg", "m1.look_angle", "m1.seeker_valid"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S32UI_HUD its own branch — no radome key on the wire, the radome peak-hold stays 0, and the four FOV quantities arrive as core scalars")

	# ══ TOOTH 6+7 — TWO sliders, at TWO DIFFERENT entities, and the disqualifications ══════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("slice 32 must build EXACTLY TWO sliders (seeker_fov_deg + cross_speed_mps), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-32 wire must NEVER send set_fidelity — there is no rung; the lesson is the two SLIDERS")
	if not keys_set.has("seeker_fov_deg") or keys_set["seeker_fov_deg"] != "m1":
		return _fail("the 'seeker_fov_deg' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	# ⭐ AND THIS IS A FIRST FOR THE ARC's SLIDERS: the two knobs target DIFFERENT ENTITIES, because
	# they are the two sides of the comparison — the WINDOW belongs to the missile and the LEAD to the
	# engagement. A client that routed both to the interceptor would silently fail at the server,
	# which validates that a knob names a real entity + comp key.
	if not keys_set.has("cross_speed_mps") or keys_set["cross_speed_mps"] != "tgt1":
		return _fail("the 'cross_speed_mps' slider must send set_param at the TARGET tgt1 — it is the ENGAGEMENT's axis, not the missile's. Got %s" % str(keys_set))
	# ⚠ TWO knobs is convention-9-legal because they are the two terms of ONE comparison, `fov` vs
	# `lead(vy)`, and the verifier measures the verdict flipping exactly where the difference crosses
	# zero, from BOTH directions. The DISQUALIFICATIONS are a design property, asserted not described.
	for bad in ["radome_slope", "radome_slope_est", "radome_ripple", "radome_ripple_k",
				"gyro_scale_err", "gyro_bias_z", "n_pn", "rho", "sigma_seek", "elevation_deg",
				"af_alpha_max", "alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 32 must NOT build a '%s' slider — it is a SECOND MECHANISM (any radome/gyro key), moves the guidance loop the lesson is not about, degrades the lesson beside it, measures the LAUNCHER rather than the seeker (elevation_deg — and it is DEAD anyway, consumed once at load), or moves the aero ceiling this slice holds at 0. Got %s" % [bad, str(keys_set.keys())])
	print("S32UI_KNOB exactly 2 sliders — seeker_fov_deg → m1 and cross_speed_mps → tgt1 (the arc's first two-ENTITY pair); NOTHING sends set_fidelity")

	# ══ TOOTH 8 — THE VALUE-GUARD, FOURTEEN-WAY ════════════════════════════════════════════════════
	# (a) ⭐ slice 26 — a RADOME wire (no FOV key) must keep the RADOME branch and its peak-hold. This
	#     is the mirror of tooth 5: neither view may capture the other's telemetry.
	_sb26 = _build_sandbox()
	_sb26._on_scenario({
		"name": "s26_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_slope", "min": -0.12, "max": 0.06, "value": -0.10,
				   "label": "radome error slope R"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb26._seeker_fov_view:
		return _fail("a slice-26 wire must NOT be marked as a FOV view")
	if _sb26._mode != sb._mode or _sb26._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 26 and 32 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD branch, got modes %s/%s" % [_sb26._mode, sb._mode])
	_sb26._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.omega_r": 0.02,
						"m1.radome_slope": -0.10, "m1.radome_eps": -0.0004, "m1.look_angle": 13.6,
						"m1.radome_residual": 0.0, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb26._airframe3d_on_state({"entities": ents})
	if not (_sb26._radome_qpeak > 0.5):
		return _fail("⭐ the slice-26 MIRROR must still latch its PITCH peak-hold (fed |omega_q| = 1.31) — the FOV branch is inserted AHEAD of the radome cascade and must not have disturbed it. Got %.4f" % _sb26._radome_qpeak)
	if _sb26._fov_lost:
		return _fail("the slice-26 MIRROR must not latch a track break — it ships no `seeker_valid` at all, so the latch must be gated on the key's presence and not default to 'lost'")
	# (b) slice 31 — the deepest radome wire, still routed by `radome_view` and NOT by the FOV marker
	_sb31 = _build_sandbox()
	_sb31._on_scenario({
		"name": "s31_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05,
				   "label": "GYRO: scale-factor error s"},
				  {"target": "m1", "key": "gyro_bias_z", "min": -0.08, "max": 0.08, "value": 0.0,
				   "label": "GYRO: yaw-rate bias b"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27,
				   "label": "COMPENSATOR: belief R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view and NOT seeker_fov_view")
	# (c) slice 25 — seeker_axes WITHOUT either marker keeps its cycler
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4,
				   "label": "σ_seek"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 handshake must KEEP its seeker-axes cycler, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# (d) slice 24 — steering; (e) slice 23 — the 3-ring airframe cycler
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._fid_kind != "steering" or not _sb24._prop_btn.visible:
		return _fail("a slice-24 handshake must keep _fid_kind=steering with the button shown, got kind=%s vis=%s" % [_sb24._fid_kind, _sb24._prop_btn.visible])
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Yβ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._fid_kind != "airframe" or _sb23._airframe_rungs.size() != 3:
		return _fail("a slice-23 handshake must keep the 3-RING airframe cycler, got kind=%s rungs=%s" % [_sb23._fid_kind, str(_sb23._airframe_rungs)])
	# (f) slice 19 — the 2-D SPATIAL airframe cycler with only TWO rungs
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.0, "label": "ρ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or _sb19._airframe_rungs.size() != 2:
		return _fail("a slice-19 handshake must stay 2-D spatial with a TWO-ring airframe cycler, got mode=%s kind=%s rungs=%s" % [_sb19._mode, _sb19._fid_kind, str(_sb19._airframe_rungs)])
	# (g) slice 16 — the OTHER button-dropping branch. ⚠ EIGHT branches now drop the button (16, 26,
	#     27, 28, 29, 30, 31, 32) and they must NOT collapse: 16 is the 2-D SPATIAL view, 26-32 the 3-D.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slices 16 and 32 both drop the button but must NOT share a mode (16 = 2-D spatial, 32 = 3-D airframe3d)")
	# (h) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (i) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S32UI_GUARD fourteen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D, radome) / 31 drops(3-D, gyro) / 32 drops(3-D, FOV) / and the NO-MARKER mirror of 32 falling through to 25's cycler")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..31_ui_test contract) --------------------------------------------

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
	print("S32UI OK: a slice-32 handshake ships a NEW button-dropping marker, `seeker_fov_view`, and " +
		"reuses slice 23's 3-D airframe view wholesale. ⭐⭐ THE LOAD-BEARING TOOTH IS THE MIRROR " +
		"WITHOUT IT: a FOV wire HOLDS `seeker_axes` at az_el (the window lives in the two-angle " +
		"seeker, which is why the LOADER refuses `seeker_fov_deg` without `two_angle: true`), so the " +
		"same handshake minus the marker falls straight through to slice 25's CYCLER with the button " +
		"VISIBLE — and that cycler's other position, `:pitch_plane`, would leave the WINDOW LIVE on a " +
		"missile that ALSO misses by 2000 m for a wholly unrelated reason. Two mechanisms compounding " +
		"in one view is exactly what convention 9 exists to prevent, and it is the 'identical " +
		"signature, different mechanism' trap slice 25 spent a section on. Slice-16's Option-P′, " +
		"EIGHTH use, and the drop is asserted at BOTH sites (the mode entry AND `_update_fid_btn`, " +
		"whose generic arm would re-show it because the scenario really does carry an `:airframe` " +
		"fidelity, HELD at six_dof). ⚠ IT IS A SEPARATE MARKER FROM `radome_view` RATHER THAN A " +
		"REUSE, because the two select different HUD BRANCHES: the radome cascade reads " +
		"`radome_slope` / `radome_residual` / `radome_slope_worst`, and a FOV wire has NONE of them — " +
		"reading one would print a confident 0.000 into a label, the stale-readout class this arc " +
		"has caught seven times. Both directions are asserted here: the FOV wire ships no radome key " +
		"and never engages the radome peak-hold, while the slice-26 mirror still latches its PITCH " +
		"peak-hold on identical routing. ⭐ THE VERDICT IS A PURE HELPER, WHICH IS THE ONLY REASON IT " +
		"CAN BE TESTED AT ALL — `_draw` never runs headless, and slice 31's aim-point comparison " +
		"shipped WRONG with only a windowed shot to catch it (convention 14). It is pinned in ALL " +
		"THREE states, including the middle one a two-way label would hide: the lead has passed the " +
		"window but the tracker has not dropped yet, which is precisely where a student dragging the " +
		"crossing-speed slider is ABOUT to lose the engagement. ⭐ AND THE TRACK-BREAK LATCH IS A " +
		"TOOTH, NOT A DETAIL: it is a LATCH where slice 27's peak-hold DECAYS, because a limit cycle " +
		"crosses zero twice per cycle (its verdict must forget) while a track break is a THING THAT " +
		"HAPPENED — the missile coasts on a stale rate from then on, and an instantaneous flag would " +
		"blink green the moment the runaway geometry swung the LOS back through the window. It " +
		"latches at long range, SURVIVES a return to valid, and is RANGE-GATED so the endgame " +
		"excursion inside 200 m — the LOS swinging through a large angle in the last millisecond " +
		"before impact — cannot paint a healthy intercept as a lost track. TWO sliders are built, at " +
		"TWO DIFFERENT ENTITIES (a first for this arc: the WINDOW belongs to the missile and the LEAD " +
		"to the engagement), both driving set_param, and NOTHING sends set_fidelity. Two knobs is " +
		"convention-9-legal because they are the two terms of ONE comparison, `fov` vs `lead(vy)`, " +
		"and the verifier measures the verdict flipping exactly where the difference crosses zero " +
		"from BOTH directions; every other lever is asserted ABSENT, including every radome and gyro " +
		"key (a SECOND mechanism, kept off the wire by convention 9) and `elevation_deg` (which would " +
		"measure the LAUNCHER rather than the seeker, and is a DEAD knob besides). The value-guard " +
		"holds FOURTEEN ways, with 16-vs-32 asserted on BOTH mode and visibility so the eight " +
		"button-dropping branches cannot collapse. The DRAWING is proven by the windowed shot " +
		"harness (convention 14's 4th proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S32UI FAIL: " + msg)
	print("S32UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomark, _sb26, _sb31, _sb25, _sb24, _sb23, _sb19, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
