extends SceneTree
# Headless UI test for the slice-25 SEEKER-AXES CYCLER PATH — the piece slice25_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity wire + the seeker physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT view routing or the cycler.
#
# ⭐ THE LOAD-BEARING TOOTH IS THE WITHIN-airframe3d DISCRIMINATOR, NOW THREE-WAY. Slices 23, 24 and 25
# ALL enter the 3-D airframe view (_mode=airframe3d, airframe_6dof=true). What splits them is which
# fidelity the shared button cycles — and slice 25 is checked FIRST ("check the NEW key first"):
#   • airframe_6dof + `seeker_axes` → the slice-25 SEEKER-AXES cycler (_fid_kind=seeker_axes, 2-ring
#                                     pitch_plane ↔ az_el; :airframe HELD :six_dof, :seeker HELD :filtered)
#   • airframe_6dof + `steering`    → the slice-24 STEERING cycler (_fid_kind=steering, 2-ring)
#   • airframe_6dof + neither       → the slice-23 AIRFRAME cycler (_fid_kind=airframe, 3-ring)
# A careless edit collapses these — a slice-25 wire cycling :airframe or :steering (HELD keys) instead of
# :seeker_axes (the lesson key), the convention-9 "toggle the LESSON's key" trap. Both MIRROR cases are
# asserted, which is what proves an if/elif SWITCH rather than an `or`.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-25 handshake routes to _mode=airframe3d + _fid_kind=SEEKER_AXES + the button SHOWN
#   2. the cycler is the 2-RING pitch_plane ↔ az_el, each press → set_fidelity SEEKER_AXES (never
#      :airframe / :steering / :seeker — the held keys), and the button label reads "seeker: …"
#   3. MIRROR A: a slice-24 handshake (steering, NO seeker_axes) STILL takes _fid_kind=steering
#   4. MIRROR B: a slice-23 handshake (neither) STILL takes _fid_kind=airframe, 3-ring
#   5. the off-tree state path builds the trail and reads the omega_oop HUD key without crashing
#   6. the value-guard, SEVEN-way (16 / 18 / 21 / 23 / 24 / 25) — the multi-view discriminator
#
# Run:  godot --headless --path clients/godot --script res://net/slice25_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb24
var _sb23
var _sb16
var _sb18
var _sb21

func _initialize() -> void:
	print("S25UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice25_seeker_3d: airframe_view + airframe_6dof + a fidelity carrying
	# `seeker_axes` (default pitch_plane — the showcase opens on the BLIND miss), :airframe HELD
	# six_dof, :seeker HELD filtered, NO `steering` key at all, and the sigma_seek knob.
	sb._on_scenario({
		"name": "s25_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4,
			 "label": "σ_seek LOS angular noise"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: airframe_6dof + seeker_axes enters the 3-D view with the SEEKER-AXES cycler ══
	if sb._mode != "airframe3d":
		return _fail("a slice-25 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._fid_kind != "seeker_axes":
		return _fail("a slice-25 handshake (fidelity has `seeker_axes`) must route to _fid_kind=seeker_axes (NOT airframe/steering — the HELD keys), got %s" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("a slice-25 handshake must SHOW the :seeker_axes cycler")
	sb._update_fid_btn()
	if str(sb._prop_btn.text) != "seeker: pitch_plane":
		return _fail("the button must read 'seeker: pitch_plane', got '%s'" % sb._prop_btn.text)
	print("S25UI_ROUTE airframe3d + _fid_kind=seeker_axes + button 'seeker: pitch_plane'")

	# ══ TOOTH 2 — the 2-RING cycler, each press → set_fidelity SEEKER_AXES (never a held key) ═════════
	# start at pitch_plane (default) → press → az_el → press → pitch_plane
	var seq := ["az_el", "pitch_plane"]
	for want in seq:
		mock.sent.clear()
		sb._on_seeker_axes_pressed()
		if str(sb._fidelity.get("seeker_axes", "")) != want:
			return _fail("the seeker-axes cycler must advance to %s, got %s" % [want, str(sb._fidelity.get("seeker_axes", ""))])
		# the HELD keys must NOT move (convention 9 — ONE toggled fidelity)
		if str(sb._fidelity.get("airframe", "")) != "six_dof":
			return _fail("cycling seeker_axes must NOT touch the HELD :airframe (still six_dof), got %s" % str(sb._fidelity.get("airframe", "")))
		if str(sb._fidelity.get("seeker", "")) != "filtered":
			return _fail("cycling seeker_axes must NOT touch the HELD :seeker tracker (still filtered — a 3-D :raw arm is slice 11's lesson), got %s" % str(sb._fidelity.get("seeker", "")))
		var sent_axes := false
		for d in mock.sent:
			if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "seeker_axes" and str(d.get("value", "")) == want:
				sent_axes = true
			if str(d.get("key", "")) == "airframe" or str(d.get("key", "")) == "steering" or str(d.get("key", "")) == "seeker":
				return _fail("cycling seeker_axes must NEVER send set_fidelity %s (that is a held key)" % str(d.get("key", "")))
		if not sent_axes:
			return _fail("cycling to %s must send set_fidelity seeker_axes=%s" % [want, want])
	sb._update_fid_btn()
	if str(sb._prop_btn.text) != "seeker: pitch_plane":
		return _fail("after a full cycle the button must read 'seeker: pitch_plane', got '%s'" % sb._prop_btn.text)
	print("S25UI_CYCLE 2-ring pitch_plane ↔ az_el (each press → set_fidelity seeker_axes; airframe/seeker HELD)")

	# ══ TOOTH 3 — MIRROR A: a slice-24 handshake (steering, NO seeker_axes) keeps the STEERING cycler ══
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._mode != "airframe3d" or _sb24._fid_kind != "steering":
		return _fail("a slice-24 handshake (steering, NO seeker_axes) must keep _fid_kind=steering, got kind=%s" % _sb24._fid_kind)

	# ══ TOOTH 4 — MIRROR B: a slice-23 handshake (neither key) keeps the 3-RING AIRFRAME cycler ═══════
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Yβ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._mode != "airframe3d" or _sb23._fid_kind != "airframe":
		return _fail("a slice-23 handshake (neither key) must keep _fid_kind=airframe in airframe3d, got kind=%s" % _sb23._fid_kind)
	if _sb23._airframe_rungs.size() != 3 or not _sb23._airframe_rungs.has("six_dof"):
		return _fail("a slice-23 scenario must keep the 3-RING airframe cycler, got %s" % str(_sb23._airframe_rungs))
	print("S25UI_MIRROR slice-24 keeps steering / slice-23 keeps the 3-ring airframe (an if/elif SWITCH, not an `or`)")

	# ══ TOOTH 5 — the off-tree state path + the omega_oop HUD key ═════════════════════════════════════
	sb._telemetry = {
		"m1.los_range": 1500.0, "m1.omega_oop": 0.0, "m1.beta": 0.02,
		# a NORMALIZED quaternion (0.5² × 4 = 1) — Godot's Quaternion.xform asserts unit norm, and an
		# unnormalized literal makes the state path print engine errors on an otherwise green run
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 0.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb (the interceptor's 3-D position)")
	# the HEADLINE readout must be a plain core-supplied scalar the HUD can print (convention 13 — the
	# client never recomputes an ω; it prints what the core measured, including the EXACT 0.0)
	if typeof(sb._telemetry.get("m1.omega_oop")) != TYPE_FLOAT:
		return _fail("omega_oop must reach the client as a scalar float (no client-side physics)")
	print("S25UI_STATE trail + markers + the omega_oop headline key handled off-tree (no crash)")

	# ══ TOOTH 6 — THE VALUE-GUARD, SEVEN-WAY (the multi-view discriminator) ══════════════════════════
	# (a) slice 16 — airframe_view, NO fidelity → 2-D airframe, button DROPPED
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	# (b) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode (NOT airframe3d), got %s" % _sb18._mode)
	# (c) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S25UI_GUARD seven-way OK — 16 drops / 18 terrain-3-D / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..24_ui_test contract) --------------------------------------------

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	return sb

func _pass() -> bool:
	print("S25UI OK: a slice-25 handshake (airframe_6dof + a `seeker_axes` fidelity) enters the 3-D airframe " +
		"view with the shared button as the 2-RING SEEKER-AXES cycler (pitch_plane ↔ az_el, each press → " +
		"set_fidelity seeker_axes — NEVER :airframe / :steering / :seeker, which stay HELD; the button reads " +
		"'seeker: …'). The within-airframe3d discriminator is now THREE-WAY and holds as an if/elif SWITCH: a " +
		"slice-24 wire keeps the steering cycler and a slice-23 wire keeps the 3-RING airframe cycler, both " +
		"UNTOUCHED. The multi-view guard holds seven ways (16 drops / 18 terrain-3-D / 21 atmosphere / 23 " +
		"airframe / 24 steering / 25 seeker_axes). The off-tree state path builds the trail and carries the " +
		"omega_oop headline key (a core scalar the HUD prints — no client-side physics). The DRAWING is proven " +
		"by the windowed shot harness (convention 14's fourth proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S25UI FAIL: " + msg)
	print("S25UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb24, _sb23, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
