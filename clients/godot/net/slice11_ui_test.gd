extends SceneTree
# Headless UI test for the slice-11 SEEKER PATH — the piece slice11_verify.gd can't reach. The verifier
# drives SimClient directly (the set_fidelity/set_param wire + the raw/filtered physics); the Sandbox.tscn
# smoke-load proves the scene loads + handshakes against a seeker server. Neither PRESSES the seeker cycler
# or drags the σ_seek/α/β slider, so `_on_seeker_pressed` (the raw↔filtered ring), the _fid_kind=seeker
# button/badge re-render, the reset resync, and the sigma_seek slider → set_param path ship unverified.
# This drives them directly (no server, no viewport): it builds only the nodes the path touches, injects a
# recording mock client, feeds a fake slice-11 `seeker` handshake (seeker:filtered + guidance:pn +
# autopilot:ideal, no range/pri axis, no estimator/raim/integrator → the SPATIAL view + the SEEKER cycler),
# then asserts. CRITICAL: the handshake carries ALL THREE keys; the button must cycle SEEKER (checked
# BEFORE guidance AND autopilot in the discriminator — convention 9, one lesson per button). Mirrors
# slice10_ui_test.gd, one lesson deeper.
#
# Run:  godot --headless --path clients/godot --script res://net/slice11_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S11UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the SEEKER cycler in a slice-11 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-11 seeker scenario: seeker:filtered + guidance:pn +
	# autopilot:ideal (ALL THREE keys — the one lesson is seeker; guidance/autopilot are held) + the
	# σ_seek/α/β/N/a_max knobs + NO range_axis_m/pri_axis_us/estimator/raim/integrator (so the client
	# STAYS spatial and wires the SEEKER cycler, checked BEFORE guidance/autopilot).
	sb._on_scenario({
		"name": "seeker_ui",
		"knobs": [
			{"target": "m1", "key": "sigma_seek", "min": 0.0, "max": 0.02, "value": 3.0e-3, "label": "σ_seek (LOS noise, rad)"},
			{"target": "m1", "key": "alpha",      "min": 0.05, "max": 0.95, "value": 0.30, "label": "α (α-β angle gain)"},
			{"target": "m1", "key": "beta",       "min": 0.005, "max": 0.30, "value": 0.05, "label": "β (α-β rate gain)"},
			{"target": "m1", "key": "n_pn",       "min": 2.0, "max": 6.0, "value": 4.0, "label": "N (nav constant)"},
			{"target": "m1", "key": "a_max",      "min": 100.0, "max": 5000.0, "value": 3000.0, "label": "a_max (g-limit, m/s²)"},
		],
		"fidelity": {"seeker": "filtered", "guidance": "pn", "autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but SEEKER button-kind (checked BEFORE guidance/autopilot)
	if sb._mode != "spatial":
		return _fail("a slice-11 (seeker ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "seeker":
		return _fail("a `seeker` fidelity must make the shared button the SEEKER cycler, NOT guidance/autopilot (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S11UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows ALL THREE keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("seeker" in badge0 and "filtered" in badge0 and "guidance" in badge0 and "pn" in badge0 and "autopilot" in badge0 and "ideal" in badge0):
		return _fail("badge did not render seeker:filtered + guidance:pn + autopilot:ideal on handshake: '%s'" % badge0)
	if btn0 != "seeker: filtered":
		return _fail("button did not render 'seeker: filtered' (the toggled lesson, not guidance/autopilot): '%s'" % btn0)

	# Cycle the seeker ring filtered→raw→filtered (2 presses wrap). Each press sends set_fidelity{key:
	# seeker} + re-renders badge + button. It must NEVER send a set_fidelity for guidance or autopilot (held).
	var seq: Array = []
	var touched_held := false
	for step in 2:
		sb._on_seeker_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "seeker":
			seq.append(str(d.get("value", "")))
		if str(d.get("type", "")) == "set_fidelity" and (str(d.get("key", "")) == "guidance" or str(d.get("key", "")) == "autopilot"):
			touched_held = true
	print("S11UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["raw", "filtered"]:
		return _fail("seeker cycle sent wrong set_fidelity sequence: %s" % str(seq))
	if touched_held:
		return _fail("the seeker button must NOT touch guidance/autopilot (the held-fixed outer/inner loops)")
	if sb._prop_btn.text != "seeker: filtered":
		return _fail("button did not wrap back to 'seeker: filtered' after a full cycle: '%s'" % sb._prop_btn.text)

	# σ_seek slider → set_param: dragging it must write the comp via the §5 channel.
	var slider = _find_slider_for(sb._knob_box, "σ_seek")
	if slider == null:
		return _fail("no σ_seek slider was built from the handshake knobs")
	slider.value = 0.01
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var sg_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "sigma_seek":
			sg_set = d
	print("S11UI_SLIDER last sigma_seek set_param = %s" % str(sg_set))
	if sg_set == null:
		return _fail("σ_seek slider sent no set_param frame")
	if str(sg_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(sg_set))
	if absf(float(sg_set.get("value", 0.0)) - 0.01) > 1.0e-4:
		return _fail("σ_seek slider did not carry the dragged value (~0.01): %s" % str(sg_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_seeker_pressed()                 # filtered → raw
	if sb._prop_btn.text != "seeker: raw":
		return _fail("pre-reset button should be 'seeker: raw', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S11UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "seeker: filtered":
		return _fail("reset did not resync the seeker rung to 'filtered': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S11UI OK: slice-11 handshake STAYS spatial + wires the SEEKER cycler (NOT guidance/autopilot); " +
		"ring walks raw→filtered and wraps; guidance/autopilot untouched; badge/button track; σ_seek slider " +
		"sends set_param; reset resyncs to filtered")
	_teardown()
	quit(0)

func _find_slider_for(box: Node, label_substr: String):
	# Walk the knob box; a slider follows its label (name_lbl then the row with the HSlider). Match the
	# label text so we grab the σ_seek slider specifically (the first slider, but be explicit).
	var want_next := false
	for c in box.get_children():
		if c is Label and (label_substr in c.text):
			want_next = true
			continue
		if want_next:
			var s = _first_slider(c)
			if s != null:
				return s
	return _first_slider(box)   # fallback: first slider anywhere

func _first_slider(node: Node):
	if node is HSlider:
		return node
	for c in node.get_children():
		var nested = _first_slider(c)
		if nested != null:
			return nested
	return null

func _fail(msg: String) -> void:
	push_error("S11UI FAIL: " + msg)
	print("S11UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
