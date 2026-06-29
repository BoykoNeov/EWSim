extends SceneTree
# Headless UI test for the slice-4 EP cycler / jammer-slider PATH — the piece slice4_verify.gd
# can't reach. The verifier drives SimClient directly, proving the set_fidelity wire + the
# burn-through/EP physics; the Sandbox.tscn smoke-load proves the scene loads + handshakes
# against a slice-4 server. Neither PRESSES the ep cycler or drags the jammer-power slider, so
# `_on_ep_pressed` (the 3-rung ring), the ep badge/button re-render, the reset resync, and the
# jammer pt_w slider → set_param path ship unverified. This drives them directly (no server, no
# viewport): it builds only the nodes the path touches, injects a recording mock client, feeds a
# fake slice-4 `scenario` handshake (ep present, NO range_axis_m → stays SPATIAL mode but the
# button becomes the ep cycler), then asserts the cycle + slider + reset behave.
# Mirrors net/slice3_ui_test.gd (the cfar analog) and net/sandbox_ui_test.gd (the prop analog).
#
# Run:  godot --headless --path clients/godot --script res://net/slice4_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S4UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the ep cycler in a slice-4 spatial scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-4 self-screen scenario: ep:none default + a
	# jammer-power knob, and NO range_axis_m (so the client stays in SPATIAL mode but the shared
	# button is wired as the ep cycler, not the prop toggle).
	sb._on_scenario({
		"name": "selfscreen_ui",
		"knobs": [{"target": "jam1", "key": "pt_w", "min": 1, "max": 200, "label": "Jammer power (W)", "log": true}],
		"fidelity": {"ep": "none"},
	})

	# handshake → spatial mode, ep button-kind, badge + button show the default rung
	if sb._mode != "spatial":
		return _fail("a slice-4 (no range_axis_m) handshake must stay spatial mode (got %s)" % sb._mode)
	if sb._fid_kind != "ep":
		return _fail("an `ep` fidelity must make the button the ep cycler (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S4UI_HANDSHAKE badge='%s' btn='%s'" % [badge0, btn0])
	if not ("ep" in badge0 and "none" in badge0):
		return _fail("badge did not render ep:none on handshake: '%s'" % badge0)
	if btn0 != "ep: none":
		return _fail("button did not render 'ep: none' on handshake: '%s'" % btn0)

	# Cycle the ep ring 3 times from none: none→freq_agility→sidelobe_blanking→none (wrap). Each
	# press must send a set_fidelity{key:ep} and re-render badge + button.
	var sf_seq: Array = []
	for step in 3:
		sb._on_ep_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "ep":
			sf_seq.append(str(d.get("value", "")))
	print("S4UI_CYCLE set_fidelity seq = %s  final badge='%s' btn='%s'" % [str(sf_seq), sb._badge.text, sb._prop_btn.text])
	if sf_seq != ["freq_agility", "sidelobe_blanking", "none"]:
		return _fail("ep cycle sent wrong set_fidelity sequence: %s" % str(sf_seq))
	if sb._prop_btn.text != "ep: none":
		return _fail("button did not wrap back to 'ep: none' after a full cycle: '%s'" % sb._prop_btn.text)
	if not ("ep" in sb._badge.text and "none" in sb._badge.text):
		return _fail("badge did not track the rung back to none: '%s'" % sb._badge.text)

	# Jammer-power slider → set_param: dragging jam1.pt_w must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no jammer-power slider was built from the handshake knobs")
	slider.value = 50.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var pj_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "pt_w":
			pj_set = d
	print("S4UI_SLIDER last pt_w set_param = %s" % str(pj_set))
	if pj_set == null:
		return _fail("jammer-power slider sent no set_param frame")
	if str(pj_set.get("target", "")) != "jam1":
		return _fail("set_param target should be jam1: %s" % str(pj_set))
	if float(pj_set.get("value", 0.0)) < 30.0:
		return _fail("jammer-power slider did not carry the dragged value (~50): %s" % str(pj_set))

	# Reset must resync the badge/button to the scenario default (server reloads YAML → ep:none,
	# no new handshake — the client owns the displayed state) and send a reset.
	# First move the rung OFF the default so the resync is observable.
	sb._on_ep_pressed()                     # none → freq_agility
	if sb._prop_btn.text != "ep: freq_agility":
		return _fail("pre-reset button should be 'ep: freq_agility', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S4UI_RESET badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	if sb._prop_btn.text != "ep: none" or not ("none" in sb._badge.text):
		return _fail("reset did not resync to ep:none: badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S4UI OK: slice-4 handshake stays spatial + wires the ep cycler; ring walks " +
		"none→freq_agility→sidelobe_blanking and wraps; jammer slider sends set_param; reset resyncs to none")
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
	push_error("S4UI FAIL: " + msg)
	print("S4UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
