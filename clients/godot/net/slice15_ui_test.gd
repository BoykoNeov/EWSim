extends SceneTree
# Headless UI test for the slice-15 FIN-SERVO PATH — the piece slice15_verify.gd can't reach. The verifier
# drives SimClient directly (the set_fidelity/set_param wire + the fin physics); the Sandbox.tscn smoke-load
# proves the scene loads + handshakes against a fin server. Neither PRESSES the autopilot cycler (now a
# 3-RING) or drags the δ̇_max slider, so `_on_autopilot_pressed` (the ideal→pid→fin ring), the
# _fid_kind=autopilot button/badge re-render, the reset resync, and the delta_rate_max slider → set_param
# path ship unverified. This drives them directly (no server, no viewport): it builds only the nodes the
# path touches, injects a recording mock client, feeds a fake slice-15 `autopilot:fin` handshake (autopilot:
# fin + guidance:pn, no range/pri axis → the SPATIAL view + the AUTOPILOT cycler), then asserts.
# CRITICAL: the handshake carries BOTH autopilot AND guidance; the button must cycle AUTOPILOT (routed on
# autopilot==:fin BEFORE the guidance branch — convention 9, one lesson per button) as a 3-RING. Mirrors
# slice12_ui_test.gd (which cycles guidance); slice-15 cycles autopilot with the third `fin` rung.
#
# Run:  godot --headless --path clients/godot --script res://net/slice15_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S15UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the AUTOPILOT cycler in a slice-15 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-15 fin scenario: autopilot:fin default + guidance:pn
	# (BOTH keys — the one lesson is the fin plant; guidance is held) + the δ̇_max/a_lat/a_max knobs (δ̇_max
	# is on the MISSILE m1) + NO range_axis_m/pri_axis_us (so the client STAYS spatial and, because
	# autopilot==fin, wires the AUTOPILOT cycler — NOT the guidance cycler).
	sb._on_scenario({
		"name": "fin_ui",
		"knobs": [
			{"target": "m1",   "key": "delta_rate_max", "min": 0.05, "max": 2.0,    "value": 0.4,   "label": "δ̇_max (fin rate limit, rad/s)"},
			{"target": "tgt1", "key": "a_lat_mps2",     "min": 0.0,  "max": 300.0,  "value": 160.0, "label": "a_lat (target g, m/s²)"},
			{"target": "m1",   "key": "a_max",          "min": 2600.0, "max": 4000.0, "value": 2600.0, "label": "a_max (magnitude g-limit, m/s²)"},
		],
		"fidelity": {"autopilot": "fin", "guidance": "pn"},
	})

	# handshake → spatial view (NOT a new mode) but AUTOPILOT button-kind (routed on autopilot==fin, checked
	# BEFORE guidance)
	if sb._mode != "spatial":
		return _fail("a slice-15 (autopilot:fin, no axis) handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "autopilot":
		return _fail("an autopilot:fin fidelity must make the shared button the AUTOPILOT cycler, NOT guidance (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S15UI_HANDSHAKE mode='%s' badge='%s' btn='%s'" % [sb._mode, badge0, btn0])
	# the badge shows BOTH keys (the §12 badge is the full fidelity map); the button shows the toggled one
	if not ("autopilot" in badge0 and "fin" in badge0 and "guidance" in badge0 and "pn" in badge0):
		return _fail("badge did not render autopilot:fin + guidance:pn on handshake: '%s'" % badge0)
	if btn0 != "autopilot: fin":
		return _fail("button did not render 'autopilot: fin' (the toggled lesson, not guidance): '%s'" % btn0)

	# Cycle the autopilot 3-RING fin→ideal→pid→fin (3 presses wrap). Each press sends set_fidelity{key:
	# autopilot} + re-renders badge + button. It must NEVER send a set_fidelity for guidance (held fixed).
	var seq: Array = []
	var touched_guidance := false
	for step in 3:
		sb._on_autopilot_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "autopilot":
			seq.append(str(d.get("value", "")))
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "guidance":
			touched_guidance = true
	print("S15UI_CYCLE seq=%s  final btn='%s'" % [str(seq), sb._prop_btn.text])
	if seq != ["ideal", "pid", "fin"]:
		return _fail("autopilot 3-ring cycle sent wrong set_fidelity sequence: %s (want ideal→pid→fin)" % str(seq))
	if touched_guidance:
		return _fail("the autopilot button must NOT touch guidance (the held-fixed outer law)")
	if sb._prop_btn.text != "autopilot: fin":
		return _fail("button did not wrap back to 'autopilot: fin' after a full 3-ring cycle: '%s'" % sb._prop_btn.text)

	# δ̇_max slider → set_param: dragging the MISSILE's fin rate limit must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no δ̇_max/a_lat/a_max slider was built from the handshake knobs")
	slider.value = 2.0
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var dr_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "delta_rate_max":
			dr_set = d
	print("S15UI_SLIDER last delta_rate_max set_param = %s" % str(dr_set))
	if dr_set == null:
		return _fail("delta_rate_max slider sent no set_param frame")
	if str(dr_set.get("target", "")) != "m1":
		return _fail("set_param target should be the missile m1: %s" % str(dr_set))
	if absf(float(dr_set.get("value", 0.0)) - 2.0) > 0.01:
		return _fail("δ̇_max slider did not carry the dragged value (~2.0): %s" % str(dr_set))

	# Reset must resync the button/badge to the scenario default (server reloads YAML → the defaults, no
	# new handshake — the client owns the displayed state) + send reset. First move the rung OFF the
	# default so the resync is observable, AND confirm the 3-ring SURVIVES reset (reset leaves _fid_kind /
	# _autopilot_rungs — the per-scenario 3-ring, not the const).
	sb._on_autopilot_pressed()              # fin → ideal
	if sb._prop_btn.text != "autopilot: ideal":
		return _fail("pre-reset button should be 'autopilot: ideal', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S15UI_RESET btn='%s' badge='%s'" % [sb._prop_btn.text, sb._badge.text])
	if sb._prop_btn.text != "autopilot: fin":
		return _fail("reset did not resync the autopilot rung to 'fin': '%s'" % sb._prop_btn.text)
	# the 3-ring must survive reset: one press from fin should land on ideal (not wrap wrongly on a 2-ring)
	sb._on_autopilot_pressed()              # fin → ideal (proves the ring is still 3-wide post-reset)
	sb._on_autopilot_pressed()              # ideal → pid
	if sb._prop_btn.text != "autopilot: pid":
		return _fail("the 3-ring did not SURVIVE reset (fin→ideal→pid expected): '%s'" % sb._prop_btn.text)
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S15UI OK: slice-15 handshake STAYS spatial + wires the AUTOPILOT cycler (NOT guidance); the " +
		"3-ring walks ideal→pid→fin and wraps; guidance untouched; badge/button track; δ̇_max slider sends " +
		"set_param to m1; reset resyncs to fin AND preserves the 3-ring")
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
	push_error("S15UI FAIL: " + msg)
	print("S15UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
