extends SceneTree
# Headless UI test for the slice-17 AIRFRAME COUPLING VIEW PATH — the piece slice17_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity/set_param wire + the coupled physics); the
# Sandbox.tscn smoke-load proves the scene loads against a slice-17 server. Neither exercises the CLIENT
# view-routing: that a handshake carrying `airframe_view` AND an `:airframe` fidelity STAYS spatial, sets
# _fid_kind=airframe, SHOWS the shared button as the point_mass↔pitch_coupled cycler (the button comes
# BACK — the difference from slice 16, which drops it), cycling it sends set_fidelity, the af_delta/af_cla
# sliders → set_param, and reset resyncs. PLUS the VALUE-GUARD BOTH WAYS: a slice-16-style handshake
# (airframe_view, NO fidelity) still DROPS the button. Drives them directly (no server, no viewport).
#
# Run:  godot --headless --path clients/godot --script res://net/slice17_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16

func _initialize() -> void:
	print("S17UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# Fake the §5 handshake for a slice-17 coupling scenario: airframe_view=true + the :airframe fidelity
	# (pitch_coupled — the REAL toggle) + the af_delta/af_cla turn levers + NO axis (stays spatial).
	sb._on_scenario({
		"name": "coupling_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_delta", "min": -0.3, "max": 0.3, "value": 0.15, "label": "δ fin trim (rad)"},
			{"target": "m1", "key": "af_cla", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Lα lift-curve slope (1/rad)"},
		],
		"fidelity": {"airframe": "pitch_coupled"},
	})

	# handshake → STAYS spatial + _fid_kind=airframe + the button is SHOWN (the cycler is back — the
	# difference from slice 16). Value-guarded on the :airframe fidelity being PRESENT.
	if sb._mode != "spatial":
		return _fail("a slice-17 (airframe_view + :airframe fidelity) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "airframe":
		return _fail("a slice-17 handshake must set _fid_kind=airframe (got %s)" % sb._fid_kind)
	if not sb._airframe_view:
		return _fail("_airframe_view must latch true from the handshake marker")
	if not sb._prop_btn.visible:
		return _fail("the shared fidelity button must be SHOWN in a slice-17 view (the :airframe cycler is back), it is hidden")
	if not ("airframe" in sb._prop_btn.text and "pitch_coupled" in sb._prop_btn.text):
		return _fail("the button must read 'airframe: pitch_coupled' on handshake, got '%s'" % sb._prop_btn.text)
	print("S17UI_HANDSHAKE mode='%s' fid_kind='%s' btn_visible=%s btn='%s'" %
		[sb._mode, sb._fid_kind, str(sb._prop_btn.visible), sb._prop_btn.text])

	# CYCLE: pressing the button toggles pitch_coupled → point_mass, sends set_fidelity, updates the label;
	# pressing again wraps back to pitch_coupled (the 2-ring). Emit the wired `pressed` signal (tests the
	# connection made in _setup_spatial_fid_btn, not just the handler).
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("airframe", "")) != "point_mass":
		return _fail("cycling the button must advance :airframe to point_mass, got %s" % str(sb._fidelity.get("airframe", "")))
	if not ("point_mass" in sb._prop_btn.text):
		return _fail("the button label must follow to 'airframe: point_mass', got '%s'" % sb._prop_btn.text)
	var last_fid: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "airframe":
			last_fid = d
	if last_fid == null or str(last_fid.get("value", "")) != "point_mass":
		return _fail("cycling must send set_fidelity airframe=point_mass, got %s" % str(last_fid))
	sb._prop_btn.emit_signal("pressed")           # wrap back
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("the cycler must WRAP back to pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	print("S17UI_CYCLE wrapped pitch_coupled→point_mass→pitch_coupled; last set_fidelity=%s" % str(last_fid))

	# af_delta / af_cla sliders → set_param (both turn levers write the missile comp via the §5 channel).
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() < 2:
		return _fail("expected the af_delta + af_cla sliders (got %d)" % sliders.size())
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
	if not (keys_set.has("af_delta") and keys_set.has("af_cla")):
		return _fail("both af_delta and af_cla sliders must send set_param, got keys %s" % str(keys_set.keys()))
	if keys_set["af_delta"] != "m1" or keys_set["af_cla"] != "m1":
		return _fail("the slider set_param frames must target m1, got %s" % str(keys_set))
	print("S17UI_SLIDERS set_param keys=%s" % str(keys_set))

	# Reset resyncs the fidelity to the scenario default (pitch_coupled) and keeps the button SHOWN.
	sb._on_reset_pressed()
	if not sb._prop_btn.visible:
		return _fail("reset must keep the :airframe cycler SHOWN in a slice-17 view")
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("reset must resync :airframe to the scenario default pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")
	print("S17UI_RESET btn_visible=%s airframe=%s" % [str(sb._prop_btn.visible), str(sb._fidelity.get("airframe", ""))])

	# THE VALUE-GUARD BOTH WAYS: a slice-16-style handshake (airframe_view, NO fidelity) still DROPS the
	# button (the slice-16 lesson is the af_cma slider, not a fidelity cycler). This is the memory-flagged
	# both-ways check — the same _setup_spatial_fid_btn code must keep slice 16 dropping.
	var sb16 = _build_sandbox()
	_sb16 = sb16
	sb16._on_scenario({
		"name": "airframe16_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -0.5, "max": 0.5, "value": -0.3, "label": "Cmα"}],
		"fidelity": {},
	})
	if sb16._fid_kind != "airframe":
		return _fail("a slice-16 handshake must still set _fid_kind=airframe, got %s" % sb16._fid_kind)
	if sb16._prop_btn.visible:
		return _fail("VALUE-GUARD: a slice-16 handshake (no :airframe fidelity) must STILL DROP the button, it is visible")
	print("S17UI_GUARD slice-16 handshake still drops the button (btn_visible=%s)" % str(sb16._prop_btn.visible))

	print("S17UI OK: slice-17 handshake STAYS spatial + SHOWS the :airframe cycler (point_mass↔pitch_coupled, " +
		"wraps, sends set_fidelity); the af_delta/af_cla sliders send set_param to m1; reset resyncs to " +
		"pitch_coupled and keeps the button shown; AND a slice-16 handshake (no :airframe fidelity) STILL " +
		"drops the button (the value-guard both ways).")
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
	push_error("S17UI FAIL: " + msg)
	print("S17UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
	if _sb16 != null:
		_sb16.free()
		_sb16 = null
