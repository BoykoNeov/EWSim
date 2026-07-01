extends SceneTree
# Headless UI test for the slice-6 deinterleaver cycler / jitter+intercept-slider PATH — the piece
# slice6_verify.gd can't reach. The verifier drives SimClient directly, proving the set_fidelity/
# set_param wire + the histogram/PRI physics; the Sandbox.tscn smoke-load proves the scene loads +
# handshakes against a slice-6 server. Neither PRESSES the deinterleaver cycler or drags a slider, so
# `_on_deint_pressed` (the 2-rung ring), the deint badge/button re-render, the reset resync, and the
# slider → set_param path ship unverified. This drives them directly (no server, no viewport): it
# builds only the nodes the path touches, injects a recording mock client, feeds a fake slice-6
# `scenario` handshake (deinterleaver present + pri_axis_us → the ESM view + the deinterleaver
# cycler), then asserts the cycle + slider + reset behave.
# Mirrors net/slice5_ui_test.gd (the estimator analog) and net/slice3_ui_test.gd (the cfar analog).
#
# Run:  godot --headless --path clients/godot --script res://net/slice6_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S6UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the deinterleaver cycler in a slice-6 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-6 EW scenario: deinterleaver:cdif default + the
	# jitter/intercept knobs + the STATIC pri_axis_us/dwell_us (so the client enters the ESM view +
	# wires the deinterleaver cycler, not the prop toggle / cfar / geoloc paths).
	sb._on_scenario({
		"name": "esm_ui",
		"knobs": [
			{"target": "esm1", "key": "jitter_us",   "min": 0.0, "max": 60.0, "label": "TOA jitter σ (µs)"},
			{"target": "esm1", "key": "p_intercept", "min": 0.3, "max": 1.0,  "label": "P(intercept)"},
		],
		"fidelity": {"deinterleaver": "cdif"},
		"esm": "esm1",
		"dwell_us": 80000.0,
		"pri_axis_us": [10.0, 30.0, 50.0],   # a stub axis — presence is the ESM-view discriminator
	})

	# handshake → esm mode, deinterleaver button-kind, badge + button show the default rung
	if sb._mode != "esm":
		return _fail("a slice-6 (pri_axis_us) handshake must enter the ESM view (got %s)" % sb._mode)
	if sb._fid_kind != "esm":
		return _fail("a `deinterleaver` fidelity must make the button the deinterleaver cycler (_fid_kind=%s)" % sb._fid_kind)
	if sb._esm_id != "esm1":
		return _fail("ESM id not adopted from the handshake (got '%s')" % sb._esm_id)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S6UI_HANDSHAKE badge='%s' btn='%s'" % [badge0, btn0])
	if not ("deinterleaver" in badge0 and "cdif" in badge0):
		return _fail("badge did not render deinterleaver:cdif on handshake: '%s'" % badge0)
	if btn0 != "deint: cdif":
		return _fail("button did not render 'deint: cdif' on handshake: '%s'" % btn0)

	# Cycle the deinterleaver ring twice from cdif: cdif→sdif→cdif (wrap). Each press must send a
	# set_fidelity{key:deinterleaver} and re-render badge + button.
	var sf_seq: Array = []
	for step in 2:
		sb._on_deint_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "deinterleaver":
			sf_seq.append(str(d.get("value", "")))
	print("S6UI_CYCLE set_fidelity seq = %s  final badge='%s' btn='%s'" % [str(sf_seq), sb._badge.text, sb._prop_btn.text])
	if sf_seq != ["sdif", "cdif"]:
		return _fail("deinterleaver cycle sent wrong set_fidelity sequence: %s" % str(sf_seq))
	if sb._prop_btn.text != "deint: cdif":
		return _fail("button did not wrap back to 'deint: cdif' after a full cycle: '%s'" % sb._prop_btn.text)
	if not ("deinterleaver" in sb._badge.text and "cdif" in sb._badge.text):
		return _fail("badge did not track the rung back to cdif: '%s'" % sb._badge.text)

	# jitter_us slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no slider was built from the handshake knobs")
	slider.value = 42.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var jit_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "jitter_us":
			jit_set = d
	print("S6UI_SLIDER last jitter_us set_param = %s" % str(jit_set))
	if jit_set == null:
		return _fail("jitter_us slider sent no set_param frame")
	if str(jit_set.get("target", "")) != "esm1":
		return _fail("set_param target should be the ESM: %s" % str(jit_set))
	if float(jit_set.get("value", 0.0)) < 40.0:
		return _fail("jitter_us slider did not carry the dragged value (~42): %s" % str(jit_set))

	# Reset must resync the badge/button to the scenario default (server reloads YAML →
	# deinterleaver:cdif, no new handshake — the client owns the displayed state) and send reset.
	# First move the rung OFF the default so the resync is observable.
	sb._on_deint_pressed()                   # cdif → sdif
	if sb._prop_btn.text != "deint: sdif":
		return _fail("pre-reset button should be 'deint: sdif', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S6UI_RESET badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	if sb._prop_btn.text != "deint: cdif" or not ("cdif" in sb._badge.text):
		return _fail("reset did not resync to deinterleaver:cdif: badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S6UI OK: slice-6 handshake enters the ESM view + wires the deinterleaver cycler; ring walks " +
		"cdif→sdif and wraps; jitter_us slider sends set_param; reset resyncs to cdif")
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
	push_error("S6UI FAIL: " + msg)
	print("S6UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
