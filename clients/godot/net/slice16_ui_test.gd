extends SceneTree
# Headless UI test for the slice-16 AIRFRAME VIEW PATH — the piece slice16_verify.gd can't reach. The
# verifier drives SimClient directly (the set_param wire + the rotational physics); the Sandbox.tscn
# smoke-load proves the scene loads + handshakes against an airframe server. Neither exercises the CLIENT
# view-routing: that a handshake carrying `airframe_view` (and NO fidelity) STAYS spatial, sets
# _fid_kind=airframe, DROPS the shared fidelity button (nothing to cycle — the Cmα slider is the lesson),
# renders the airframe badge, and that the af_cma slider → set_param path + the reset resync work. This
# drives them directly (no server, no viewport): it builds only the nodes the path touches, injects a
# recording mock client, feeds a fake slice-16 airframe handshake, then asserts.
# CRITICAL (the advisor Option-P′ design): slice 16 carries NO fidelity — the button must be HIDDEN (not
# fall through to the propagation cycler), and the lesson lever is the auto-built af_cma KNOB slider.
#
# Run:  godot --headless --path clients/godot --script res://net/slice16_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S16UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # must be HIDDEN in a slice-16 scene (no fidelity to cycle)
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-16 airframe scenario: airframe_view=true + target m1 +
	# EMPTY fidelity (the params-presence gate) + the af_cma knob (the Cmα lesson lever) + NO
	# range_axis_m/pri_axis_us (so the client STAYS spatial and lands in the airframe branch).
	sb._on_scenario({
		"name": "airframe_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_cma", "min": -0.5, "max": 0.5, "value": -0.3, "label": "Cmα (static stability ∂Cm/∂α, 1/rad)"},
		],
		"fidelity": {},
	})

	# handshake → spatial view (NOT a new mode) + airframe button-kind (routed on airframe_view, checked
	# FIRST since there is no fidelity to compete)
	if sb._mode != "spatial":
		return _fail("a slice-16 (airframe_view, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "airframe":
		return _fail("an airframe_view handshake must set _fid_kind=airframe (dropping the fidelity button), got %s" % sb._fid_kind)
	if not sb._airframe_view:
		return _fail("_airframe_view must latch true from the handshake marker")
	# THE Option-P′ CRUX: the shared fidelity button is HIDDEN (no fidelity to cycle — NOT a propagation
	# fallthrough). A slice-16 scenario's only lever is the Cmα slider.
	if sb._prop_btn.visible:
		return _fail("the shared fidelity button must be HIDDEN in a slice-16 airframe view (nothing to cycle), it is visible")
	var badge0: String = sb._badge.text
	print("S16UI_HANDSHAKE mode='%s' fid_kind='%s' btn_visible=%s badge='%s'" %
		[sb._mode, sb._fid_kind, str(sb._prop_btn.visible), badge0])
	# the badge names the airframe approximation explicitly (empty fidelity → not "unspecified")
	if not ("airframe" in badge0 and "pitch-plane" in badge0):
		return _fail("badge did not name the airframe approximation on handshake: '%s'" % badge0)

	# af_cma slider → set_param: dragging the Cmα knob must write the missile comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no af_cma slider was built from the handshake knobs")
	slider.value = 0.3
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var cma_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "af_cma":
			cma_set = d
	print("S16UI_SLIDER last af_cma set_param = %s" % str(cma_set))
	if cma_set == null:
		return _fail("af_cma slider sent no set_param frame")
	if str(cma_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(cma_set))
	if absf(float(cma_set.get("value", 0.0)) - 0.3) > 0.01:
		return _fail("Cmα slider did not carry the dragged value (~0.3): %s" % str(cma_set))

	# Reset must send a reset frame + keep the button hidden (the airframe view has no fidelity to resync).
	sb._on_reset_pressed()
	print("S16UI_RESET btn_visible=%s badge='%s'" % [str(sb._prop_btn.visible), sb._badge.text])
	if sb._prop_btn.visible:
		return _fail("reset must NOT re-show the fidelity button in a slice-16 airframe view")
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S16UI OK: slice-16 handshake STAYS spatial + recognizes the airframe view + DROPS the fidelity " +
		"button (Option-P′: no false-fidelity toggle); the badge names the pitch-plane approximation; the " +
		"af_cma slider sends set_param to m1; reset keeps the button hidden and sends reset")
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
	push_error("S16UI FAIL: " + msg)
	print("S16UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
