extends SceneTree
# Headless UI test for the slice-12 APN PATH — the piece slice12_verify.gd can't reach. The verifier
# drives SimClient directly (the set_fidelity/set_param wire + the APN/PN physics); the Sandbox.tscn
# smoke-load proves the scene loads + handshakes against an APN server. Neither PRESSES the guidance
# cycler (now a 3-RING) or drags the a_lat slider, so `_on_guidance_pressed` (the pursuit→pn→apn ring),
# the _fid_kind=guidance button/badge re-render, the reset resync, and the a_lat_mps2 slider → set_param
# path ship unverified. This drives them directly (no server, no viewport): it builds only the nodes the
# path touches, injects a recording mock client, feeds a fake slice-12 `guidance` handshake (guidance:apn
# + autopilot:ideal, no range/pri axis → the SPATIAL view + the GUIDANCE cycler), then asserts.
# CRITICAL: the handshake carries BOTH guidance AND autopilot; the button must cycle GUIDANCE (checked
# before autopilot in the discriminator — convention 9, one lesson per button). Mirrors slice10_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice12_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S12UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the GUIDANCE cycler in a slice-12 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-12 APN scenario: guidance:apn + autopilot:ideal (BOTH
	# keys — the one lesson is guidance; autopilot is held) + the a_lat/N/a_max knobs (a_lat is on the
	# TARGET tgt1) + NO range_axis_m/pri_axis_us (so the client STAYS spatial and wires the GUIDANCE cycler).
	sb._on_scenario({
		"name": "apn_ui",
		"knobs": [
			{"target": "tgt1", "key": "a_lat_mps2", "min": 0.0, "max": 400.0,   "value": 200.0,  "label": "a_lat (target g, m/s²)"},
			{"target": "m1",   "key": "n_pn",       "min": 2.0, "max": 6.0,     "value": 4.0,    "label": "N (nav constant)"},
			{"target": "m1",   "key": "a_max",      "min": 100.0, "max": 600.0, "value": 200.0,  "label": "a_max (g-limit, m/s²)"},
		],
		"fidelity": {"guidance": "apn", "autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but GUIDANCE button-kind (checked BEFORE autopilot)
	if sb._mode != "spatial":
		return _fail("a slice-12 (guidance ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "guidance":
		return _fail("a `guidance` fidelity must make the shared button the GUIDANCE cycler, NOT autopilot (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S12UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows BOTH keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("guidance" in badge0 and "apn" in badge0 and "autopilot" in badge0 and "ideal" in badge0):
		return _fail("badge did not render guidance:apn + autopilot:ideal on handshake: '%s'" % badge0)
	if btn0 != "guidance: apn":
		return _fail("button did not render 'guidance: apn' (the toggled lesson, not autopilot): '%s'" % btn0)

	# Cycle the guidance 3-RING apn→pursuit→pn→apn (3 presses wrap). Each press sends set_fidelity{key:
	# guidance} + re-renders badge + button. It must NEVER send a set_fidelity for autopilot (held fixed).
	var seq: Array = []
	var touched_autopilot := false
	for step in 3:
		sb._on_guidance_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "guidance":
			seq.append(str(d.get("value", "")))
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "autopilot":
			touched_autopilot = true
	print("S12UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["pursuit", "pn", "apn"]:
		return _fail("guidance 3-ring cycle sent wrong set_fidelity sequence: %s (want pursuit→pn→apn)" % str(seq))
	if touched_autopilot:
		return _fail("the guidance button must NOT touch autopilot (the held-fixed inner loop)")
	if sb._prop_btn.text != "guidance: apn":
		return _fail("button did not wrap back to 'guidance: apn' after a full 3-ring cycle: '%s'" % sb._prop_btn.text)

	# a_lat slider → set_param: dragging the TARGET's maneuver g must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no a_lat/N/a_max slider was built from the handshake knobs")
	slider.value = 350.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var al_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "a_lat_mps2":
			al_set = d
	print("S12UI_SLIDER last a_lat_mps2 set_param = %s" % str(al_set))
	if al_set == null:
		return _fail("a_lat_mps2 slider sent no set_param frame")
	if str(al_set.get("target", "")) != "tgt1":
		return _fail("set_param target should be the maneuvering target tgt1: %s" % str(al_set))
	if absf(float(al_set.get("value", 0.0)) - 350.0) > 0.1:
		return _fail("a_lat slider did not carry the dragged value (~350.0): %s" % str(al_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_guidance_pressed()               # apn → pursuit
	if sb._prop_btn.text != "guidance: pursuit":
		return _fail("pre-reset button should be 'guidance: pursuit', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S12UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "guidance: apn":
		return _fail("reset did not resync the guidance rung to 'apn': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S12UI OK: slice-12 handshake STAYS spatial + wires the GUIDANCE cycler (NOT autopilot); the " +
		"3-ring walks pursuit→pn→apn and wraps; autopilot untouched; badge/button track; a_lat slider sends " +
		"set_param to tgt1; reset resyncs to apn")
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
	push_error("S12UI FAIL: " + msg)
	print("S12UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
