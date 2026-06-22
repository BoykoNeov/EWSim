extends SceneTree
# Headless UI test for the slice-3 CFAR toggle/slider PATH — the piece slice3_verify.gd can't
# reach. The verifier drives SimClient directly, proving the set_fidelity wire + physics; the
# Sandbox.tscn smoke-load proves the scene loads + handshakes against a CFAR server. Neither
# presses the rung cycler or drags a window slider, so `_on_cfar_pressed` (the 5-rung ring),
# the cfar badge/button re-render, the reset resync, and the N_train slider → set_param path
# ship unverified. This drives them directly (no server, no viewport): it builds only the
# nodes the path touches, injects a recording mock client, feeds a fake CFAR `scenario`
# handshake (range_axis_m present → cfar mode), then asserts the cycle + slider behave.
# (The range-power _draw still needs a windowed look; the arrays it renders are wire-verified
# by slice3_verify.gd.) Mirrors net/sandbox_ui_test.gd (the slice-2 prop-toggle analog).
#
# Run:  godot --headless --path clients/godot --script res://net/slice3_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

# A stand-in for SimClient that records sent frames instead of opening a socket.
class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb                                # held so _fail can free the subtree on the error path

func _initialize() -> void:
	print("S3UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()          # NOT added to the tree → _ready (UI build + real
	                                       # socket) never fires; we wire the minimal pieces.
	_sb = sb
	# Only the nodes the cfar path reads/writes. Parent them to sb so sb.free() cascades.
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()           # repurposed as the cfar rung cycler in cfar mode
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a CFAR scenario: ca default + a range axis (which
	# flips the client into cfar mode) + one window knob (so _build_knobs runs too).
	var axis := [0.0, 150.0, 300.0, 450.0, 600.0, 750.0, 900.0, 1050.0]
	sb._on_scenario({
		"name": "cfar_ui",
		"knobs": [{"target": "radar1", "key": "n_train", "min": 4, "max": 48, "label": "N_train"}],
		"fidelity": {"cfar": "ca", "detection": "analytic"},
		"range_axis_m": axis,
		"n_cells": axis.size(),
		"dr_m": 149.9,
		"radar": "radar1",
	})

	# handshake → cfar mode, badge + button show the default rung
	if sb._mode != "cfar":
		return _fail("range_axis_m handshake did not enter cfar mode (mode=%s)" % sb._mode)
	if sb._cfar_radar != "radar1" or sb._n_cells != axis.size():
		return _fail("cfar axis not adopted: radar='%s' n_cells=%d" % [sb._cfar_radar, sb._n_cells])
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S3UI_HANDSHAKE badge='%s' btn='%s'" % [badge0, btn0])
	if not ("cfar" in badge0 and "ca" in badge0):
		return _fail("badge did not render cfar:ca on handshake: '%s'" % badge0)
	if btn0 != "cfar: ca":
		return _fail("button did not render 'cfar: ca' on handshake: '%s'" % btn0)

	# Cycle the rung ring 5 times from ca: ca→go→so→os→fixed→ca (wrap). Each press must send a
	# set_fidelity{key:cfar} and re-render badge + button.
	var sf_seq: Array = []
	for step in 5:
		sb._on_cfar_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "cfar":
			sf_seq.append(str(d.get("value", "")))
	print("S3UI_CYCLE set_fidelity seq = %s  final badge='%s' btn='%s'" % [str(sf_seq), sb._badge.text, sb._prop_btn.text])
	if sf_seq != ["go", "so", "os", "fixed", "ca"]:
		return _fail("rung cycle sent wrong set_fidelity sequence: %s" % str(sf_seq))
	if sb._prop_btn.text != "cfar: ca":
		return _fail("button did not wrap back to 'cfar: ca' after a full cycle: '%s'" % sb._prop_btn.text)
	if not ("cfar" in sb._badge.text and "ca" in sb._badge.text):
		return _fail("badge did not track the rung back to ca: '%s'" % sb._badge.text)

	# Window slider → set_param: dragging N_train must write the radar comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no N_train slider was built from the handshake knobs")
	slider.value = 30.0                    # snaps to the nearest step (~29.96)
	# A programmatic .value set outside the scene tree doesn't auto-emit; a real user DRAG
	# does. Fire value_changed ourselves to faithfully simulate the drag → the connected
	# set_param lambda (the path under test).
	slider.emit_signal("value_changed", slider.value)
	var np_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "n_train":
			np_set = d                     # keep the LAST one (after our explicit drag)
	print("S3UI_SLIDER last n_train set_param = %s" % str(np_set))
	if np_set == null:
		return _fail("N_train slider sent no set_param frame")
	if str(np_set.get("target", "")) != "radar1":
		return _fail("set_param target should be radar1: %s" % str(np_set))
	if float(np_set.get("value", 0.0)) < 20.0:
		return _fail("N_train slider did not carry the dragged value (~30): %s" % str(np_set))

	# Reset must resync the badge/button to the scenario default (server reloads YAML → cfar:ca,
	# no new handshake — the client owns the displayed state) and send a reset.
	sb._on_reset_pressed()
	print("S3UI_RESET badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	if sb._prop_btn.text != "cfar: ca" or not ("ca" in sb._badge.text):
		return _fail("reset did not resync to cfar:ca: badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S3UI OK: handshake enters cfar mode; rung cycler walks fixed→ca→go→so→os and wraps; " +
		"N_train slider sends set_param; reset resyncs to ca")
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
	push_error("S3UI FAIL: " + msg)
	print("S3UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()        # frees the subtree (parented Controls + _build_knobs sliders)
		_sb = null
