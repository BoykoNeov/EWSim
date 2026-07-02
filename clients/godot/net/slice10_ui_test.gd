extends SceneTree
# Headless UI test for the slice-10 PN PATH — the piece slice10_verify.gd can't reach. The verifier
# drives SimClient directly (the set_fidelity/set_param wire + the PN/pursuit physics); the Sandbox.tscn
# smoke-load proves the scene loads + handshakes against a PN server. Neither PRESSES the guidance cycler
# or drags the N/a_max slider, so `_on_guidance_pressed` (the pursuit↔pn ring), the _fid_kind=guidance
# button/badge re-render, the reset resync, and the n_pn slider → set_param path ship unverified. This
# drives them directly (no server, no viewport): it builds only the nodes the path touches, injects a
# recording mock client, feeds a fake slice-10 `guidance` handshake (guidance:pn + autopilot:ideal, no
# range/pri axis, no estimator/raim/integrator → the SPATIAL view + the GUIDANCE cycler), then asserts.
# CRITICAL: the handshake carries BOTH guidance AND autopilot; the button must cycle GUIDANCE (checked
# before autopilot in the discriminator — convention 9, one lesson per button). Mirrors slice9_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice10_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S10UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the GUIDANCE cycler in a slice-10 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-10 PN scenario: guidance:pn + autopilot:ideal (BOTH
	# keys — the one lesson is guidance; autopilot is held) + the N/a_max/r_stop knobs + NO range_axis_m/
	# pri_axis_us/estimator/raim/integrator (so the client STAYS spatial and wires the GUIDANCE cycler).
	sb._on_scenario({
		"name": "pn_ui",
		"knobs": [
			{"target": "m1", "key": "n_pn",   "min": 2.0, "max": 6.0,     "value": 4.0,    "label": "N (nav constant)"},
			{"target": "m1", "key": "a_max",  "min": 100.0, "max": 5000.0, "value": 3000.0, "label": "a_max (g-limit, m/s²)"},
			{"target": "m1", "key": "r_stop", "min": 0.0, "max": 100.0,    "value": 30.0,   "label": "r_stop (endgame, m)"},
		],
		"fidelity": {"guidance": "pn", "autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but GUIDANCE button-kind (checked BEFORE autopilot)
	if sb._mode != "spatial":
		return _fail("a slice-10 (guidance ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "guidance":
		return _fail("a `guidance` fidelity must make the shared button the GUIDANCE cycler, NOT autopilot (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S10UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows BOTH keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("guidance" in badge0 and "pn" in badge0 and "autopilot" in badge0 and "ideal" in badge0):
		return _fail("badge did not render guidance:pn + autopilot:ideal on handshake: '%s'" % badge0)
	if btn0 != "guidance: pn":
		return _fail("button did not render 'guidance: pn' (the toggled lesson, not autopilot): '%s'" % btn0)

	# Cycle the guidance ring pn→pursuit→pn (2 presses wrap). Each press sends set_fidelity{key:
	# guidance} + re-renders badge + button. It must NEVER send a set_fidelity for autopilot (held fixed).
	var seq: Array = []
	var touched_autopilot := false
	for step in 2:
		sb._on_guidance_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "guidance":
			seq.append(str(d.get("value", "")))
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "autopilot":
			touched_autopilot = true
	print("S10UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["pursuit", "pn"]:
		return _fail("guidance cycle sent wrong set_fidelity sequence: %s" % str(seq))
	if touched_autopilot:
		return _fail("the guidance button must NOT touch autopilot (the held-fixed inner loop)")
	if sb._prop_btn.text != "guidance: pn":
		return _fail("button did not wrap back to 'guidance: pn' after a full cycle: '%s'" % sb._prop_btn.text)

	# n_pn slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no N/a_max slider was built from the handshake knobs")
	slider.value = 6.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var np_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "n_pn":
			np_set = d
	print("S10UI_SLIDER last n_pn set_param = %s" % str(np_set))
	if np_set == null:
		return _fail("n_pn slider sent no set_param frame")
	if str(np_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(np_set))
	if absf(float(np_set.get("value", 0.0)) - 6.0) > 0.1:
		return _fail("n_pn slider did not carry the dragged value (~6.0): %s" % str(np_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_guidance_pressed()               # pn → pursuit
	if sb._prop_btn.text != "guidance: pursuit":
		return _fail("pre-reset button should be 'guidance: pursuit', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S10UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "guidance: pn":
		return _fail("reset did not resync the guidance rung to 'pn': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S10UI OK: slice-10 handshake STAYS spatial + wires the GUIDANCE cycler (NOT autopilot); ring " +
		"walks pursuit→pn and wraps; autopilot untouched; badge/button track; n_pn slider sends set_param; " +
		"reset resyncs to pn")
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
	push_error("S10UI FAIL: " + msg)
	print("S10UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
