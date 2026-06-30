extends SceneTree
# Headless UI test for the slice-5 estimator cycler / σθ-slider PATH — the piece slice5_verify.gd
# can't reach. The verifier drives SimClient directly, proving the set_fidelity/set_param wire + the
# GDOP/ellipse/estimator physics; the Sandbox.tscn smoke-load proves the scene loads + handshakes
# against a slice-5 server. Neither PRESSES the estimator cycler or drags a σθ slider, so
# `_on_est_pressed` (the 2-rung ring), the est badge/button re-render, the reset resync, and the σθ
# slider → set_param path ship unverified. This drives them directly (no server, no viewport): it
# builds only the nodes the path touches, injects a recording mock client, feeds a fake slice-5
# `scenario` handshake (estimator present, NO range_axis_m → the PLAN/geoloc mode + the estimator
# cycler), then asserts the cycle + slider + reset behave.
# Mirrors net/slice4_ui_test.gd (the ep analog) and net/slice3_ui_test.gd (the cfar analog).
#
# Run:  godot --headless --path clients/godot --script res://net/slice5_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb

func _initialize() -> void:
	print("S5UI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()           # NOT added to the tree → _ready (UI build + socket) never fires
	_sb = sb
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()            # repurposed as the estimator cycler in a slice-5 scene
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake for a slice-5 DF scenario: estimator:pseudolinear default +
	# three σθ knobs, and NO range_axis_m (so the client enters the PLAN view + wires the estimator
	# cycler, not the prop toggle / cfar cycler).
	sb._on_scenario({
		"name": "geoloc_ui",
		"knobs": [
			{"target": "dfs1", "key": "sigma_theta_deg", "min": 0.1, "max": 5.0, "label": "dfs1 σθ (deg)"},
			{"target": "dfs2", "key": "sigma_theta_deg", "min": 0.1, "max": 5.0, "label": "dfs2 σθ (deg)"},
			{"target": "dfs3", "key": "sigma_theta_deg", "min": 0.1, "max": 5.0, "label": "dfs3 σθ (deg)"},
		],
		"fidelity": {"estimator": "pseudolinear"},
	})

	# handshake → geoloc mode, estimator button-kind, badge + button show the default rung
	if sb._mode != "geoloc":
		return _fail("a slice-5 (estimator, no range_axis_m) handshake must enter geoloc/plan mode (got %s)" % sb._mode)
	if sb._fid_kind != "geoloc":
		return _fail("an `estimator` fidelity must make the button the estimator cycler (_fid_kind=%s)" % sb._fid_kind)
	var badge0: String = sb._badge.text
	var btn0: String = sb._prop_btn.text
	print("S5UI_HANDSHAKE badge='%s' btn='%s'" % [badge0, btn0])
	if not ("estimator" in badge0 and "pseudolinear" in badge0):
		return _fail("badge did not render estimator:pseudolinear on handshake: '%s'" % badge0)
	if btn0 != "est: pseudolinear":
		return _fail("button did not render 'est: pseudolinear' on handshake: '%s'" % btn0)

	# Cycle the estimator ring twice from pseudolinear: pseudolinear→ml→pseudolinear (wrap). Each
	# press must send a set_fidelity{key:estimator} and re-render badge + button.
	var sf_seq: Array = []
	for step in 2:
		sb._on_est_pressed()
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "estimator":
			sf_seq.append(str(d.get("value", "")))
	print("S5UI_CYCLE set_fidelity seq = %s  final badge='%s' btn='%s'" % [str(sf_seq), sb._badge.text, sb._prop_btn.text])
	if sf_seq != ["ml", "pseudolinear"]:
		return _fail("estimator cycle sent wrong set_fidelity sequence: %s" % str(sf_seq))
	if sb._prop_btn.text != "est: pseudolinear":
		return _fail("button did not wrap back to 'est: pseudolinear' after a full cycle: '%s'" % sb._prop_btn.text)
	if not ("estimator" in sb._badge.text and "pseudolinear" in sb._badge.text):
		return _fail("badge did not track the rung back to pseudolinear: '%s'" % sb._badge.text)

	# σθ slider → set_param: dragging a sensor's sigma_theta_deg must write the comp via the §5 channel.
	var slider = _find_slider(sb._knob_box)
	if slider == null:
		return _fail("no σθ slider was built from the handshake knobs")
	slider.value = 3.5
	slider.emit_signal("value_changed", slider.value)   # programmatic set outside the tree won't auto-emit
	var sig_set: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "sigma_theta_deg":
			sig_set = d
	print("S5UI_SLIDER last sigma_theta_deg set_param = %s" % str(sig_set))
	if sig_set == null:
		return _fail("σθ slider sent no set_param frame")
	if not str(sig_set.get("target", "")).begins_with("dfs"):
		return _fail("set_param target should be a df sensor: %s" % str(sig_set))
	if float(sig_set.get("value", 0.0)) < 2.0:
		return _fail("σθ slider did not carry the dragged value (~3.5): %s" % str(sig_set))

	# Reset must resync the badge/button to the scenario default (server reloads YAML →
	# estimator:pseudolinear, no new handshake — the client owns the displayed state) and send reset.
	# First move the rung OFF the default so the resync is observable.
	sb._on_est_pressed()                     # pseudolinear → ml
	if sb._prop_btn.text != "est: ml":
		return _fail("pre-reset button should be 'est: ml', got '%s'" % sb._prop_btn.text)
	sb._on_reset_pressed()
	print("S5UI_RESET badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	if sb._prop_btn.text != "est: pseudolinear" or not ("pseudolinear" in sb._badge.text):
		return _fail("reset did not resync to estimator:pseudolinear: badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	var saw_reset := false
	for d in mock.sent:
		if str(d.get("type", "")) == "reset":
			saw_reset = true
	if not saw_reset:
		return _fail("reset button sent no reset frame")

	print("S5UI OK: slice-5 handshake enters the plan view + wires the estimator cycler; ring walks " +
		"pseudolinear→ml and wraps; σθ slider sends set_param; reset resyncs to pseudolinear")
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
	push_error("S5UI FAIL: " + msg)
	print("S5UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()
		_sb = null
