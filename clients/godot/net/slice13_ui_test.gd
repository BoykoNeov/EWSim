extends SceneTree
# Headless UI test for the slice-13 DISCRIMINATION PATH — the piece slice13_verify.gd can't reach. The
# verifier drives SimClient directly (the set_fidelity/set_param wire + the seduction/discrimination
# physics); the Sandbox.tscn smoke-load proves the scene loads + handshakes against a slice-13 server.
# Neither PRESSES the discrimination cycler or drags the intensity/gate sliders, so
# `_on_discrimination_pressed` (the none↔gated ring), the _fid_kind=discrimination button/badge
# re-render, the reset resync, and the intensity/gate_halfwidth slider → set_param path ship unverified.
# This drives them directly (no server, no viewport): it builds only the nodes the path touches, injects
# a recording mock client, feeds a fake slice-13 `discrimination` handshake (discrimination:none +
# seeker:scan + guidance:pn + autopilot:ideal, no range/pri axis → the SPATIAL view + the DISCRIMINATION
# cycler), then asserts. CRITICAL: the handshake carries ALL FOUR keys; the button must cycle
# DISCRIMINATION (checked FIRST in the discriminator — convention 9, one lesson per button; NOT the held
# seeker/guidance/autopilot). Mirrors slice12_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice13_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S13UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the DISCRIMINATION cycler in a slice-13 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-13 countermeasures scenario: discrimination:none +
	# seeker:scan + guidance:pn + autopilot:ideal (ALL FOUR keys — the one lesson is discrimination; the
	# other three are held) + the intensity/gate_halfwidth knobs (intensity is on the DECOY dcy1) + NO
	# range_axis_m/pri_axis_us (so the client STAYS spatial and wires the DISCRIMINATION cycler).
	sb._on_scenario({
		"name": "decoy_ui",
		"knobs": [
			{"target": "dcy1", "key": "intensity",      "min": 0.0,  "max": 200.0, "value": 80.0,  "label": "decoy intensity (lobe amp)"},
			{"target": "m1",   "key": "gate_halfwidth", "min": 0.01, "max": 0.16,  "value": 0.045, "label": "gate half-width (rad)"},
			{"target": "m1",   "key": "n_pn",           "min": 2.0,  "max": 6.0,   "value": 4.0,   "label": "N (nav constant)"},
			{"target": "m1",   "key": "a_max",          "min": 100.0, "max": 5000.0, "value": 3000.0, "label": "a_max (g-limit, m/s²)"},
		],
		"fidelity": {"discrimination": "none", "seeker": "scan", "guidance": "pn", "autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but DISCRIMINATION button-kind (checked BEFORE seeker/
	# guidance/autopilot — a slice-13 scene ships all four; the button must toggle the ONE lesson).
	if sb._mode != "spatial":
		return _fail("a slice-13 (discrimination ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "discrimination":
		return _fail("a `discrimination` fidelity must make the shared button the DISCRIMINATION cycler, NOT seeker/guidance/autopilot (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S13UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows ALL FOUR keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("discrimination" in badge0 and "none" in badge0 and "seeker" in badge0 and "scan" in badge0
			and "guidance" in badge0 and "autopilot" in badge0):
		return _fail("badge did not render the full four-key fidelity map on handshake: '%s'" % badge0)
	if btn0 != "disc: none":
		return _fail("button did not render 'disc: none' (the toggled lesson, not seeker/guidance): '%s'" % btn0)

	# Cycle the discrimination ring none→gated→none (2 presses wrap). Each press sends set_fidelity{key:
	# discrimination} + re-renders badge + button. It must NEVER send a set_fidelity for the held keys.
	var seq: Array = []
	var touched_held := ""
	for step in 2:
		sb._on_discrimination_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity":
			var k := str(d.get("key", ""))
			if k == "discrimination":
				seq.append(str(d.get("value", "")))
			elif k in ["seeker", "guidance", "autopilot"]:
				touched_held = k
	print("S13UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["gated", "none"]:
		return _fail("discrimination cycle sent wrong set_fidelity sequence: %s (want gated→none)" % str(seq))
	if touched_held != "":
		return _fail("the discrimination button must NOT touch the held key '%s'" % touched_held)
	if sb._prop_btn.text != "disc: none":
		return _fail("button did not wrap back to 'disc: none' after a full 2-ring cycle: '%s'" % sb._prop_btn.text)

	# intensity slider → set_param: dragging the DECOY's lobe amplitude must write the comp via the §5
	# channel to the decoy entity (the seduction-strength lever).
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no intensity/gate/N/a_max slider was built from the handshake knobs")
	slider.value = 120.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var it_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "intensity":
			it_set = d
	print("S13UI_SLIDER last intensity set_param = %s" % str(it_set))
	if it_set == null:
		return _fail("intensity slider sent no set_param frame")
	if str(it_set.get("target", "")) != "dcy1":
		return _fail("set_param target should be the decoy dcy1: %s" % str(it_set))
	if absf(float(it_set.get("value", 0.0)) - 120.0) > 0.1:
		return _fail("intensity slider did not carry the dragged value (~120.0): %s" % str(it_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_discrimination_pressed()         # none → gated
	if sb._prop_btn.text != "disc: gated":
		return _fail("pre-reset button should be 'disc: gated', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S13UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "disc: none":
		return _fail("reset did not resync the discrimination rung to 'none': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S13UI OK: slice-13 handshake STAYS spatial + wires the DISCRIMINATION cycler (NOT the held " +
		"seeker/guidance/autopilot); the ring walks none→gated and wraps; the held keys untouched; " +
		"badge/button track; the intensity slider sends set_param to the decoy dcy1; reset resyncs to none")
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
	push_error("S13UI FAIL: " + msg)
	print("S13UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
