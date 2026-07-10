extends SceneTree
# Headless UI test for the slice-14 COOPERATION PATH — the piece slice14_verify.gd can't reach. The
# verifier drives SimClient directly (the set_fidelity/set_param wire + the salvo/spread physics); the
# Sandbox.tscn smoke-load proves the scene loads + handshakes against a slice-14 server. Neither PRESSES
# the cooperation cycler or drags the k_it slider, so `_on_cooperation_pressed` (the solo↔salvo ring),
# the _fid_kind=cooperation button/badge re-render, the reset resync, and the k_it slider → set_param
# path ship unverified. This drives them directly (no server, no viewport): it builds only the nodes the
# path touches, injects a recording mock client, feeds a fake slice-14 `cooperation` handshake
# (cooperation:solo + guidance:pn + autopilot:ideal, no seeker/discrimination, no range/pri axis → the
# SPATIAL view + the COOPERATION cycler), then asserts. CRITICAL: the handshake carries THREE keys; the
# button must cycle COOPERATION (checked FIRST in the discriminator — convention 9, one lesson per
# button; NOT the held guidance/autopilot). Mirrors slice13_ui_test.gd.
#
# Run:  godot --headless --path clients/godot --script res://net/slice14_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S14UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the COOPERATION cycler in a slice-14 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-14 salvo scenario: cooperation:solo + guidance:pn +
	# autopilot:ideal (THREE keys — the one lesson is cooperation; the other two are held) + the k_it/
	# n_pn/a_max knobs (all on the near missile mA) + NO range_axis_m/pri_axis_us (so the client STAYS
	# spatial and wires the COOPERATION cycler).
	sb._on_scenario({
		"name": "salvo_ui",
		"knobs": [
			{"target": "mA", "key": "k_it",  "min": 0.1,   "max": 0.7,    "value": 0.45,   "label": "K_it (impact-time gain, 1/s²)"},
			{"target": "mA", "key": "n_pn",  "min": 2.0,   "max": 6.0,    "value": 4.0,    "label": "N (nav constant)"},
			{"target": "mA", "key": "a_max", "min": 100.0, "max": 5000.0, "value": 3000.0, "label": "a_max (g-limit, m/s²)"},
		],
		"fidelity": {"cooperation": "solo", "guidance": "pn", "autopilot": "ideal"},
	})

	# handshake → spatial view (NOT a new mode) but COOPERATION button-kind (checked BEFORE guidance/
	# autopilot — a slice-14 scene ships all three; the button must toggle the ONE lesson).
	if sb._mode != "spatial":
		return _fail("a slice-14 (cooperation ∈ fidelity, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "cooperation":
		return _fail("a `cooperation` fidelity must make the shared button the COOPERATION cycler, NOT guidance/autopilot (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S14UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows ALL THREE keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("cooperation" in badge0 and "solo" in badge0 and "guidance" in badge0 and "autopilot" in badge0):
		return _fail("badge did not render the full three-key fidelity map on handshake: '%s'" % badge0)
	if btn0 != "coop: solo":
		return _fail("button did not render 'coop: solo' (the toggled lesson, not guidance/autopilot): '%s'" % btn0)

	# Cycle the cooperation ring solo→salvo→solo (2 presses wrap). Each press sends set_fidelity{key:
	# cooperation} + re-renders badge + button. It must NEVER send a set_fidelity for the held keys.
	var seq: Array = []
	var touched_held := ""
	for step in 2:
		sb._on_cooperation_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity":
			var k := str(d.get("key", ""))
			if k == "cooperation":
				seq.append(str(d.get("value", "")))
			elif k in ["guidance", "autopilot", "seeker", "discrimination"]:
				touched_held = k
	print("S14UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["salvo", "solo"]:
		return _fail("cooperation cycle sent wrong set_fidelity sequence: %s (want salvo→solo)" % str(seq))
	if touched_held != "":
		return _fail("the cooperation button must NOT touch the held key '%s'" % touched_held)
	if sb._prop_btn.text != "coop: solo":
		return _fail("button did not wrap back to 'coop: solo' after a full 2-ring cycle: '%s'" % sb._prop_btn.text)

	# k_it slider → set_param: dragging the impact-time-control gain must write the comp via the §5
	# channel to the near missile mA (the salvo tuning lever).
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no k_it/N/a_max slider was built from the handshake knobs")
	slider.value = 0.55
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var kit_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "k_it":
			kit_set = d
	print("S14UI_SLIDER last k_it set_param = %s" % str(kit_set))
	if kit_set == null:
		return _fail("k_it slider sent no set_param frame")
	if str(kit_set.get("target", "")) != "mA":
		return _fail("set_param target should be the near missile mA: %s" % str(kit_set))
	if absf(float(kit_set.get("value", 0.0)) - 0.55) > 0.01:
		return _fail("k_it slider did not carry the dragged value (~0.55): %s" % str(kit_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable.
	sb._on_cooperation_pressed()            # solo → salvo
	if sb._prop_btn.text != "coop: salvo":
		return _fail("pre-reset button should be 'coop: salvo', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S14UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "coop: solo":
		return _fail("reset did not resync the cooperation rung to 'solo': '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S14UI OK: slice-14 handshake STAYS spatial + wires the COOPERATION cycler (NOT the held " +
		"guidance/autopilot); the ring walks solo→salvo and wraps; the held keys untouched; badge/button " +
		"track; the k_it slider sends set_param to the near missile mA; reset resyncs to solo")
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
	push_error("S14UI FAIL: " + msg)
	print("S14UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
