extends SceneTree
# Headless UI test for the slice-9 guided-missile PATH — the piece slice9_verify.gd can't reach. The
# verifier drives SimClient directly (the set_fidelity/set_param wire + the pursuit/PID physics); the
# Sandbox.tscn smoke-load proves the scene loads + handshakes against a guided-missile server. Neither
# PRESSES the autopilot cycler or drags a gain slider, so `_on_autopilot_pressed` (the ideal↔pid ring),
# the _fid_kind=autopilot button/badge re-render, the reset resync, and the kp slider → set_param path
# ship unverified. This drives them directly (no server, no viewport): it builds only the nodes the path
# touches, injects a recording mock client, feeds a fake slice-9 `autopilot` handshake (no range/pri
# axis, no estimator/raim/integrator → the SPATIAL view + the autopilot cycler), then asserts them.
# Mirrors net/slice8_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice9_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S9UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the autopilot cycler in a slice-9 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-9 guided-missile scenario: autopilot:ideal default +
	# the PID-gain knobs + NO range_axis_m/pri_axis_us/estimator/raim/integrator (so the client STAYS
	# spatial and wires the autopilot cycler).
	sb._on_scenario({
		"name": "pursuit_ui",
		"knobs": [
			{"target": "m1", "key": "kp",     "min": 0.0, "max": 10.0, "value": 2.0, "label": "Kp (accel P-gain)"},
			{"target": "m1", "key": "ki",     "min": 0.0, "max": 60.0, "value": 0.0, "label": "Ki (accel I-gain)"},
			{"target": "m1", "key": "k_guid", "min": 1.0, "max": 6.0,  "value": 3.0, "label": "K_guid (turn-rate)"},
		],
		"fidelity": {"autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but autopilot button-kind
	if sb._mode != "spatial":
		return _fail("a slice-9 (autopilot ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "autopilot":
		return _fail("an `autopilot` fidelity must make the shared button the autopilot cycler (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S9UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	if not ("autopilot" in badge0 and "ideal" in badge0):
		return _fail("badge did not render autopilot:ideal on handshake: '%s'" % badge0)
	if btn0 != "autopilot: ideal":
		return _fail("button did not render 'autopilot: ideal' on handshake: '%s'" % btn0)

	# Cycle the autopilot ring ideal→pid→ideal (2 presses wrap). Each press sends set_fidelity{key:
	# autopilot} + re-renders badge + button.
	var seq: Array = []
	for step in 2:
		sb._on_autopilot_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "autopilot":
			seq.append(str(d.get("value", "")))
	print("S9UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["pid", "ideal"]:
		return _fail("autopilot cycle sent wrong set_fidelity sequence: %s" % str(seq))
	if sb._prop_btn.text != "autopilot: ideal":
		return _fail("button did not wrap back to 'autopilot: ideal' after a full cycle: '%s'" % sb._prop_btn.text)

	# kp slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no gain slider was built from the handshake knobs")
	slider.value = 8.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var kp_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "kp":
			kp_set = d
	print("S9UI_SLIDER last kp set_param = %s" % str(kp_set))
	if kp_set == null:
		return _fail("kp slider sent no set_param frame")
	if str(kp_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(kp_set))
	if absf(float(kp_set.get("value", 0.0)) - 8.0) > 0.1:
		return _fail("kp slider did not carry the dragged value (~8.0): %s" % str(kp_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_autopilot_pressed()               # ideal → pid
	if sb._prop_btn.text != "autopilot: pid":
		return _fail("pre-reset button should be 'autopilot: pid', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S9UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "autopilot: ideal":
		return _fail("reset did not resync the autopilot rung to 'ideal': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S9UI OK: slice-9 handshake STAYS spatial + wires the autopilot cycler; ring walks " +
		"ideal→pid and wraps; badge/button track; kp slider sends set_param; reset resyncs to ideal")
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
	push_error("S9UI FAIL: " + msg)
	print("S9UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
