extends SceneTree
# Headless UI test for the slice-18 TERRAIN VIEW PATH — the piece slice18_verify.gd can't reach.
# The verifier drives SimClient directly (the wire + the masking physics); the Sandbox.tscn smoke-load
# proves the scene loads against a slice-18 server. Neither exercises the CLIENT view-routing: that a
# handshake carrying `terrain_grid` flips the client into the 3-D "terrain" mode, adopts the grid/extents,
# upgrades the shared button to the FULL 3-RING propagation cycler (free_space → two_ray → terrain, wraps),
# cycling sends set_fidelity, the alt_hold_m slider → set_param, and reset resyncs to the scenario default.
# PLUS the ring guard the other way: a plain spatial handshake keeps the HISTORICAL 2-ring toggle
# (free_space ↔ two_ray — no phantom `terrain` rung on a slice-1/2 scenario). Drives them directly
# (no server, no viewport — the 3-D scene builds off-tree, which is exactly what this harness proves safe).
#
# Run:  godot --headless --path clients/godot --script res://net/slice18_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb2

func _initialize() -> void:
	print("S18UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# Fake the §5 handshake for a slice-18 terrain scenario: the static grid + extents + ids +
	# the :terrain propagation default + the altitude knob. Grid: a tiny asymmetric 3×3.
	sb._on_scenario({
		"name": "terrain_ui",
		"terrain": "ter1",
		"terrain_n": 3,
		"terrain_extent_m": [-1000.0, 15000.0, -4000.0, 4000.0],
		"terrain_grid": [0.0, 10.0, 0.0, 5.0, 250.0, 5.0, 0.0, 10.0, 0.0],
		"radar": "radar1",
		"target": "tgt1",
		"knobs": [
			{"target": "tgt1", "key": "alt_hold_m", "min": 50.0, "max": 1500.0, "value": 120.0, "label": "Target altitude (m)"},
		],
		"fidelity": {"propagation": "terrain"},
	})

	# handshake → the 3-D terrain mode + the FULL 3-ring + the adopted grid
	if sb._mode != "terrain":
		return _fail("a terrain_grid handshake must select the 'terrain' mode (got %s)" % sb._mode)
	if sb._fid_kind != "propagation":
		return _fail("the terrain view's shared button must drive 'propagation' (got %s)" % sb._fid_kind)
	if sb._prop_rungs != ["free_space", "two_ray", "terrain"]:
		return _fail("a terrain scenario must upgrade the button to the FULL 3-ring, got %s" % str(sb._prop_rungs))
	if sb._terrain_n != 3 or sb._terrain_grid_h.size() != 9:
		return _fail("the client must adopt the handshake grid (n=%d, len=%d)" % [sb._terrain_n, sb._terrain_grid_h.size()])
	if sb._terrain_radar != "radar1" or sb._terrain_target != "tgt1":
		return _fail("the client must adopt the radar/target ids (got %s / %s)" % [sb._terrain_radar, sb._terrain_target])
	if sb._t3d_layer == null:
		return _fail("the 3-D layer must be built from the handshake grid (it is null)")
	if not ("terrain" in sb._prop_btn.text):
		return _fail("the button must read 'prop: terrain' on handshake, got '%s'" % sb._prop_btn.text)
	print("S18UI_HANDSHAKE mode='%s' rungs=%s n=%d btn='%s' t3d=%s" %
		[sb._mode, str(sb._prop_rungs), sb._terrain_n, sb._prop_btn.text, str(sb._t3d_layer != null)])

	# CYCLE: terrain → free_space → two_ray → terrain (wraps the 3-ring), each press sends set_fidelity.
	var expect := ["free_space", "two_ray", "terrain"]
	for want in expect:
		sb._prop_btn.emit_signal("pressed")
		if str(sb._fidelity.get("propagation", "")) != want:
			return _fail("cycling must advance propagation to %s, got %s" % [want, str(sb._fidelity.get("propagation", ""))])
		if not (want in sb._prop_btn.text):
			return _fail("the button label must follow to '%s', got '%s'" % [want, sb._prop_btn.text])
	var fid_sent: Array = []
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "propagation":
			fid_sent.append(str(d.get("value", "")))
	if fid_sent != expect:
		return _fail("the presses must send set_fidelity %s, got %s" % [str(expect), str(fid_sent)])
	print("S18UI_CYCLE 3-ring wrapped terrain→free_space→two_ray→terrain; sent=%s" % str(fid_sent))

	# alt_hold_m slider → set_param (the §5 knob channel — the altitude lesson lever).
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() < 1:
		return _fail("expected the alt_hold_m slider (got %d sliders)" % sliders.size())
	sliders[0].emit_signal("value_changed", 1000.0)
	var alt_cmd: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "alt_hold_m":
			alt_cmd = d
	if alt_cmd == null or str(alt_cmd.get("target", "")) != "tgt1" or float(alt_cmd.get("value", 0.0)) != 1000.0:
		return _fail("the altitude slider must send set_param tgt1.alt_hold_m=1000, got %s" % str(alt_cmd))
	print("S18UI_SLIDER set_param %s" % str(alt_cmd))

	# a state frame routes through _terrain_on_state (markers + LOS rebuild) without error, and the
	# masked verdict is adopted from telemetry (the LOS color source; color itself is display-only).
	sb._on_state({
		"type": "state", "t": 0.016,
		"entities": [
			{"id": "radar1", "kind": "radar", "pos": [0.0, 0.0, 30.0]},
			{"id": "tgt1", "kind": "target", "pos": [14000.0, 0.0, 120.0]},
		],
		"telemetry": {"radar1.visible": false, "radar1.detected": false,
			"radar1.snr_db": -120.0, "radar1.terrain_clearance_m": -208.6},
	})
	if sb._t3d_target == null or sb._t3d_target.position == Vector3.ZERO:
		return _fail("a state frame must move the 3-D target marker (still at the origin)")
	print("S18UI_STATE target3d=%s trail=%d" % [str(sb._t3d_target.position), sb._t3d_trail_pts.size()])

	# Reset resyncs the fidelity to the scenario default (terrain) and clears the 3-D trail.
	sb._on_reset_pressed()
	if str(sb._fidelity.get("propagation", "")) != "terrain":
		return _fail("reset must resync propagation to the scenario default :terrain, got %s" % str(sb._fidelity.get("propagation", "")))
	if sb._t3d_trail_pts.size() != 0:
		return _fail("reset must clear the 3-D trail (got %d points)" % sb._t3d_trail_pts.size())
	print("S18UI_RESET propagation=%s trail=%d" % [str(sb._fidelity.get("propagation", "")), sb._t3d_trail_pts.size()])

	# THE RING GUARD THE OTHER WAY: a plain spatial (slice-1/2-style) handshake keeps the HISTORICAL
	# 2-ring toggle — no phantom `terrain` rung where no heightfield exists.
	var sb2 = _build_sandbox()
	_sb2 = sb2
	sb2._on_scenario({
		"name": "plain_ui",
		"knobs": [],
		"fidelity": {"propagation": "two_ray"},
	})
	if sb2._mode != "spatial":
		return _fail("a plain handshake must stay spatial, got %s" % sb2._mode)
	if sb2._prop_rungs != ["free_space", "two_ray"]:
		return _fail("a plain scenario must keep the 2-ring toggle, got %s" % str(sb2._prop_rungs))
	# NB: the plain spatial path wires the button in _build_ui (never run off-tree), so drive
	# the HANDLER directly here (the terrain branch above tested the wired signal instead).
	sb2._on_prop_pressed()
	if str(sb2._fidelity.get("propagation", "")) != "free_space":
		return _fail("the 2-ring must flip two_ray→free_space, got %s" % str(sb2._fidelity.get("propagation", "")))
	sb2._on_prop_pressed()
	if str(sb2._fidelity.get("propagation", "")) != "two_ray":
		return _fail("the 2-ring must flip back free_space→two_ray, got %s" % str(sb2._fidelity.get("propagation", "")))
	print("S18UI_GUARD plain handshake keeps the 2-ring (%s)" % str(sb2._prop_rungs))

	print("S18UI OK: a terrain_grid handshake selects the 3-D terrain mode, adopts the grid/extents/ids, " +
		"builds the 3-D layer, upgrades the shared button to the wrapping 3-ring propagation cycler " +
		"(each press → set_fidelity), the alt_hold_m slider sends set_param, a state frame drives the " +
		"markers/LOS, reset resyncs + clears the trail; AND a plain handshake keeps the historical " +
		"2-ring toggle (no phantom terrain rung).")
	_teardown()
	quit(0)

func _build_sandbox():
	var sb = SandboxScript.new()               # NOT added to the tree → _ready (UI build + socket) never fires
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	sb._client = MockClient.new()
	return sb

func _find_all_sliders(box: Node) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_all_sliders(c))
	return out

func _fail(msg: String) -> void:
	push_error("S18UI FAIL: " + msg)
	print("S18UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
	if _sb2 != null:
		_sb2.free()
		_sb2 = null
