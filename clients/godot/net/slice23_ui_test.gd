extends SceneTree
# Headless UI test for the slice-23 3-D AIRFRAME VIEW PATH — the piece slice23_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity wire + the 6-DOF physics); the Sandbox.tscn
# smoke-load proves the scene loads against a slice-23 server. Neither exercises the CLIENT view routing
# or the 3-ring cycler.
#
# ⭐ THE LOAD-BEARING TOOTH IS THE MULTI-VIEW DISCRIMINATOR. The client now has THREE view families that
# can all be reached from an airframe-ish handshake, and the routing must keep them apart:
#   • airframe_view + airframe_6dof   → the slice-23 3-D AIRFRAME view (_mode=airframe3d, 3-ring cycler)
#   • airframe_view, NO fidelity      → the slice-16 2-D airframe overlay (spatial, button DROPPED)
#   • airframe_view + :airframe       → the slice-17/19 2-D airframe cycler (spatial, 2-ring)
#   • terrain_grid                    → the slice-18 terrain 3-D view (_mode=terrain) — a DIFFERENT 3-D
#   • :atmosphere + :airframe         → the slice-21 atmosphere cycler (spatial, checked FIRST)
# A careless edit to the mode dispatch or _setup_spatial_fid_btn would collapse two of these together.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-23 handshake routes to _mode=airframe3d + _fid_kind=airframe + the button SHOWN
#   2. the cycler is the 3-RING point_mass → pitch_coupled → six_dof, each press → set_fidelity airframe
#   3. a slice-17/19 handshake (NO airframe_6dof) stays SPATIAL and its cycler is the 2-RING (six_dof
#      is a DEAD rung there — no 6-DOF params — so it must NOT be reachable)
#   4. the off-tree state path (_airframe3d_on_state) builds the trail + reads att_q without crashing
#   5. the value-guard, FIVE-way (16 / 17-19 / 18 / 21 / 23) — the multi-view discriminator
#
# Run:  godot --headless --path clients/godot --script res://net/slice23_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16
var _sb19
var _sb18
var _sb21

func _initialize() -> void:
	print("S23UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice23_out_of_plane: airframe_view + airframe_6dof + THREE fidelity keys (the
	# :airframe cycler + guidance/autopilot HELD) + the af_cy_beta knob + NO axis / NO terrain_grid.
	sb._on_scenario({
		"name": "s23_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_cy_beta", "min": -5.0, "max": 40.0, "value": 20.0,
			 "label": "C_Yβ yaw authority"},
		],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: the 6-DOF discriminator enters the 3-D airframe view ════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-23 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._fid_kind != "airframe":
		return _fail("a slice-23 handshake must route to _fid_kind=airframe (the cycler kind reused), got %s" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("a slice-23 handshake must SHOW the :airframe cycler")
	if not sb._airframe_6dof:
		return _fail("_airframe_6dof must be set from the handshake marker")
	print("S23UI_ROUTE airframe3d + _fid_kind=airframe + button shown")

	# ══ TOOTH 2 — the 3-RING cycler point_mass → pitch_coupled → six_dof, each press → set_fidelity ══
	if sb._airframe_rungs.size() != 3 or not sb._airframe_rungs.has("six_dof"):
		return _fail("a slice-23 scenario must use the 3-RING airframe cycler (point_mass/pitch_coupled/six_dof), got %s" % str(sb._airframe_rungs))
	# start at pitch_coupled (the scenario default) → press → six_dof → press → point_mass → press → pitch_coupled
	var seq := ["six_dof", "point_mass", "pitch_coupled"]
	for want in seq:
		mock.sent.clear()
		sb._on_airframe_pressed()
		if str(sb._fidelity.get("airframe", "")) != want:
			return _fail("the 3-ring cycler must advance to %s, got %s" % [want, str(sb._fidelity.get("airframe", ""))])
		var sent_fid := false
		for d in mock.sent:
			if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "airframe" and str(d.get("value", "")) == want:
				sent_fid = true
		if not sent_fid:
			return _fail("cycling to %s must send set_fidelity airframe=%s" % [want, want])
	print("S23UI_CYCLE 3-ring point_mass → pitch_coupled → six_dof (each press → set_fidelity airframe)")

	# ══ TOOTH 4 — the off-tree state path: build the trail + read att_q without crashing ══════════
	# Feed a six_dof state frame (missile off the x–z plane, att_q present). _airframe3d_on_state runs
	# the marker/trail/LOS/nose meshes off-tree (the camera guard handles is_inside_tree); assert the
	# trail grows and the y-excursion is carried (the discard-dies drawing, in data form).
	sb._fidelity["airframe"] = "six_dof"
	sb._telemetry = {
		"m1.los_range": 1500.0, "m1.beta": 0.20,
		"m1.att_qw": 0.98, "m1.att_qx": -0.02, "m1.att_qy": -0.10, "m1.att_qz": 0.19,
	}
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 800.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb (the interceptor's 3-D position)")
	print("S23UI_STATE trail + markers + att_q nose built off-tree (no crash)")

	# ══ TOOTH 5 — THE VALUE-GUARD, FIVE-WAY (the multi-view discriminator) ═══════════════════════
	# (a) slice 16 — airframe_view, NO fidelity, NO airframe_6dof → 2-D airframe, button DROPPED
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._fid_kind != "airframe" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake (no airframe_6dof) must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])

	# (b) slice 17/19 — airframe_view + :airframe, NO airframe_6dof → 2-D airframe cycler, 2-RING
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_alpha_max", "min": 0.05, "max": 0.4, "value": 0.2, "label": "α_max"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or not _sb19._prop_btn.visible:
		return _fail("a slice-17/19 handshake (no airframe_6dof) must stay SPATIAL with the airframe cycler shown, got mode=%s" % _sb19._mode)
	# THE DEAD-RUNG GUARD: six_dof must NOT be reachable on a 2-ring scenario (no 6-DOF params → it
	# would fall to the point-mass path, a silent no-op the user could not tell from a bug).
	if _sb19._airframe_rungs.size() != 2 or _sb19._airframe_rungs.has("six_dof"):
		return _fail("a slice-17/19 scenario must keep the 2-RING cycler (six_dof is a DEAD rung there), got %s" % str(_sb19._airframe_rungs))

	# (c) slice 18 — terrain_grid wins the mode discriminator outright (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1",
		"terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0],
		"knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode (NOT airframe3d), got %s" % _sb18._mode)

	# (d) slice 21 — :atmosphere must STILL win the button over the co-shipped :airframe (spatial)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake (no airframe_6dof) must STILL take _fid_kind=atmosphere in the spatial view, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S23UI_GUARD five-way OK — 16 drops / 17-19 keep the 2-ring airframe cycler / 18 terrain-3-D / 21 atmosphere / 23 airframe3d-3-ring")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..22_ui_test contract) --------------------------------------------

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	return sb

func _pass() -> bool:
	print("S23UI OK: a slice-23 handshake (airframe_view + airframe_6dof) enters the 3-D AIRFRAME view " +
		"(_mode=airframe3d, the slice-18 terrain SubViewport machinery reused minus the heightfield) with " +
		"the shared button as the 3-RING airframe cycler (point_mass → pitch_coupled → six_dof, each press " +
		"→ set_fidelity airframe). The multi-view discriminator holds FIVE ways: slice 16 (no fidelity) " +
		"stays 2-D and drops the button, slice 17/19 (:airframe, no airframe_6dof) stays 2-D with the " +
		"2-RING cycler (six_dof is a DEAD rung there — no 6-DOF params — and must NOT be reachable), slice " +
		"18 (terrain_grid) enters the DIFFERENT terrain 3-D view, slice 21 (:atmosphere) keeps the " +
		"atmosphere cycler over its co-shipped :airframe, and slice 23 (airframe_6dof) enters airframe3d. " +
		"The off-tree state path builds the curving trail + reads att_q for the nose vector without " +
		"crashing (the discard dies, in data form). The DRAWING is proven by the windowed shot harness " +
		"(convention 14's fourth proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S23UI FAIL: " + msg)
	print("S23UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb16, _sb19, _sb18, _sb21]:
		if sb != null:
			sb.free()
