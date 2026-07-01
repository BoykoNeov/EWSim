extends SceneTree
# Headless UI test for the slice-7 GPS-view PATH — the piece slice7_verify.gd can't reach. The
# verifier drives SimClient directly (the set_fidelity/set_param wire + the DOP/RAIM physics); the
# Sandbox.tscn smoke-load proves the scene loads + handshakes against a GPS server. Neither PRESSES
# the raim cycler / the five error toggles / drags the fault slider, so `_on_raim_pressed` (the
# 3-rung ring), `_on_gps_toggle_pressed` (the NEW five-button row + its `.bind(term)` wiring), the
# badge/button re-render, the reset resync, and the fault slider → set_param path ship unverified.
# This drives them directly (no server, no viewport): it builds only the nodes the path touches,
# injects a recording mock client, feeds a fake slice-7 `gps` handshake (raim present, no range/pri
# axis, no estimator → the GPS view + the raim cycler + the error-toggle row), then asserts them.
# Mirrors net/slice6_ui_test.gd (the deinterleaver analog).
#
# Run:  godot --headless --path clients/godot --script res://net/slice7_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S7UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the raim cycler in a slice-7 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-7 GPS scenario: raim:off default (so the cycler
	# starts at off) + the five error-term keys + the fault_bias_m knob + NO range_axis_m/pri_axis_us/
	# estimator (so the client enters the GPS view + wires the raim cycler + the error-toggle row).
	sb._on_scenario({
		"name": "gps_ui",
		"knobs": [
			{"target": "sv3", "key": "fault_bias_m", "min": 0.0, "max": 200.0, "value": 100.0, "label": "fault bias (m)"},
		],
		"fidelity": {"iono": "on", "tropo": "off", "clock": "off", "multipath": "off", "noise": "on", "raim": "off"},
	})

	# handshake → gps mode, raim button-kind, the error-toggle row built
	if sb._mode != "gps":
		return _fail("a slice-7 (raim ∈ fidelity) handshake must enter the GPS view (got %s)" % sb._mode)
	if sb._fid_kind != "gps":
		return _fail("a `raim` fidelity must make the shared button the raim cycler (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S7UI_HANDSHAKE badge='%s' btn='%s'" % [badge0, btn0])
	if not ("raim" in badge0 and "off" in badge0):
		return _fail("badge did not render raim:off on handshake: '%s'" % badge0)
	if btn0 != "raim: off":
		return _fail("button did not render 'raim: off' on handshake: '%s'" % btn0)
	# the NEW five-error-toggle row: all five present, labels reflect the handshake fidelity
	for term in ["iono", "tropo", "clock", "multipath", "noise"]:
		if not sb._gps_toggle_btns.has(term):
			return _fail("error-toggle row is missing the '%s' button" % term)
	if sb._gps_toggle_btns["iono"].text != "iono:on":
		return _fail("iono toggle should show 'iono:on' from the handshake, got '%s'" % sb._gps_toggle_btns["iono"].text)
	if sb._gps_toggle_btns["clock"].text != "clock:off":
		return _fail("clock toggle should show 'clock:off' from the handshake, got '%s'" % sb._gps_toggle_btns["clock"].text)

	# Cycle the raim ring off→detect→exclude→off (3 presses wrap). Each press must send a
	# set_fidelity{key:raim} and re-render badge + button.
	var raim_seq: Array = []
	for step in 3:
		sb._on_raim_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "raim":
			raim_seq.append(str(d.get("value", "")))
	print("S7UI_RAIM_CYCLE seq=%s  final btn='%s'" % [str(raim_seq), sb._prop_btn.text])
	if raim_seq != ["detect", "exclude", "off"]:
		return _fail("raim cycle sent wrong set_fidelity sequence: %s" % str(raim_seq))
	if sb._prop_btn.text != "raim: off":
		return _fail("button did not wrap back to 'raim: off' after a full cycle: '%s'" % sb._prop_btn.text)

	# Press two error toggles VIA THE BUTTON SIGNAL (exercises the `.bind(term)` wiring): clock off→on,
	# noise on→off. Each must send set_fidelity{key:term} + flip its button label.
	sb._gps_toggle_btns["clock"].emit_signal("pressed")
	sb._gps_toggle_btns["noise"].emit_signal("pressed")
	var clk_val := ""
	var noise_val := ""
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "clock":
			clk_val = str(d.get("value", ""))
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "noise":
			noise_val = str(d.get("value", ""))
	print("S7UI_TOGGLES clock→%s noise→%s | clock btn='%s' noise btn='%s'" %
		[clk_val, noise_val, sb._gps_toggle_btns["clock"].text, sb._gps_toggle_btns["noise"].text])
	if clk_val != "on":
		return _fail("clock toggle should send set_fidelity clock=on, got '%s'" % clk_val)
	if noise_val != "off":
		return _fail("noise toggle should send set_fidelity noise=off, got '%s'" % noise_val)
	if sb._gps_toggle_btns["clock"].text != "clock:on" or sb._gps_toggle_btns["noise"].text != "noise:off":
		return _fail("error-toggle labels did not flip: clock='%s' noise='%s'" %
			[sb._gps_toggle_btns["clock"].text, sb._gps_toggle_btns["noise"].text])

	# fault_bias_m slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no fault slider was built from the handshake knobs")
	slider.value = 140.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var fault_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "fault_bias_m":
			fault_set = d
	print("S7UI_SLIDER last fault_bias_m set_param = %s" % str(fault_set))
	if fault_set == null:
		return _fail("fault_bias_m slider sent no set_param frame")
	if str(fault_set.get("target", "")) != "sv3":
		return _fail("set_param target should be the spoofed satellite sv3: %s" % str(fault_set))
	if float(fault_set.get("value", 0.0)) < 130.0:
		return _fail("fault_bias_m slider did not carry the dragged value (~140): %s" % str(fault_set))

	# Reset must resync the badge/button AND the five error toggles to the scenario default (server
	# reloads YAML → the defaults, no new handshake — the client owns the displayed state) + send
	# reset. First move the rung + a toggle OFF the default so the resync is observable.
	sb._on_raim_pressed()                    # off → detect
	sb._gps_toggle_btns["iono"].emit_signal("pressed")   # iono on → off
	if sb._prop_btn.text != "raim: detect":
		return _fail("pre-reset button should be 'raim: detect', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S7UI_RESET btn='%s' iono='%s' badge='%s'" % [sb._prop_btn.text, sb._gps_toggle_btns["iono"].text, sb._badge.text])
	if sb._prop_btn.text != "raim: off":
		return _fail("reset did not resync the raim rung to 'off': '%s'" % sb._prop_btn.text)
	if sb._gps_toggle_btns["iono"].text != "iono:on":
		return _fail("reset did not resync the iono toggle to 'on': '%s'" % sb._gps_toggle_btns["iono"].text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S7UI OK: slice-7 handshake enters the GPS view + wires the raim cycler + the five-error-toggle " +
		"row; ring walks off→detect→exclude and wraps; toggles send set_fidelity + flip; fault slider " +
		"sends set_param; reset resyncs the rung + toggles to defaults")
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
	push_error("S7UI FAIL: " + msg)
	print("S7UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
