extends SceneTree
# Headless UI test for the slice-8 missile-view PATH — the piece slice8_verify.gd can't reach. The
# verifier drives SimClient directly (the set_fidelity/set_param wire + the integrator/drag physics);
# the Sandbox.tscn smoke-load proves the scene loads + handshakes against a missile server. Neither
# PRESSES the integrator cycler or drags the drag slider, so `_on_integrator_pressed` (the rk4↔euler
# ring), the _fid_kind=missile button/badge re-render, the reset resync, and the cd_area_m2 slider →
# set_param path ship unverified. This drives them directly (no server, no viewport): it builds only
# the nodes the path touches, injects a recording mock client, feeds a fake slice-8 `integrator`
# handshake (no range/pri axis, no estimator/raim → the SPATIAL view + the integrator cycler), then
# asserts them. Mirrors net/slice7_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice8_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S8UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the integrator cycler in a slice-8 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-8 missile scenario: integrator:rk4 default + the
	# cd_area_m2 knob + NO range_axis_m/pri_axis_us/estimator/raim (so the client STAYS spatial and
	# wires the integrator cycler).
	sb._on_scenario({
		"name": "missile_ui",
		"knobs": [
			{"target": "m1", "key": "cd_area_m2", "min": 0.0, "max": 0.03, "value": 0.0, "label": "drag Cd·A (m²)"},
		],
		"fidelity": {"integrator": "rk4"},
	})

	# handshake → spatial view (NOT a new mode) but missile button-kind
	if sb._mode != "spatial":
		return _fail("a slice-8 (integrator ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "missile":
		return _fail("an `integrator` fidelity must make the shared button the integrator cycler (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S8UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	if not ("integrator" in badge0 and "rk4" in badge0):
		return _fail("badge did not render integrator:rk4 on handshake: '%s'" % badge0)
	if btn0 != "integrator: rk4":
		return _fail("button did not render 'integrator: rk4' on handshake: '%s'" % btn0)

	# Cycle the integrator ring rk4→euler→rk4 (2 presses wrap). Each press sends set_fidelity{key:
	# integrator} + re-renders badge + button.
	var seq: Array = []
	for step in 2:
		sb._on_integrator_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "integrator":
			seq.append(str(d.get("value", "")))
	print("S8UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["euler", "rk4"]:
		return _fail("integrator cycle sent wrong set_fidelity sequence: %s" % str(seq))
	if sb._prop_btn.text != "integrator: rk4":
		return _fail("button did not wrap back to 'integrator: rk4' after a full cycle: '%s'" % sb._prop_btn.text)

	# cd_area_m2 slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no cd_area slider was built from the handshake knobs")
	slider.value = 0.02
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var cd_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "cd_area_m2":
			cd_set = d
	print("S8UI_SLIDER last cd_area_m2 set_param = %s" % str(cd_set))
	if cd_set == null:
		return _fail("cd_area_m2 slider sent no set_param frame")
	if str(cd_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(cd_set))
	# the slider's `step` quantizes the value (max/200 ≈ 1.5e-4), so allow one step of slack
	if absf(float(cd_set.get("value", 0.0)) - 0.02) > 0.001:
		return _fail("cd_area_m2 slider did not carry the dragged value (~0.02): %s" % str(cd_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults,
	# no new handshake — the client owns the displayed state) + send reset. First move the rung OFF
	# the default so the resync is observable.
	sb._on_integrator_pressed()              # rk4 → euler
	if sb._prop_btn.text != "integrator: euler":
		return _fail("pre-reset button should be 'integrator: euler', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S8UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "integrator: rk4":
		return _fail("reset did not resync the integrator rung to 'rk4': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S8UI OK: slice-8 handshake STAYS spatial + wires the integrator cycler; ring walks " +
		"rk4→euler and wraps; badge/button track; cd_area slider sends set_param; reset resyncs to rk4")
	_teardown()
	quit(0)

func _find_slider(box: Node):
	for c in box.get_children():
		if c is HSlider:
			return c
		var nested = _find_slider(c)
		if nested != null:
			return nested
	return null

func _fail(msg: String) -> void:
	push_error("S8UI FAIL: " + msg)
	print("S8UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
