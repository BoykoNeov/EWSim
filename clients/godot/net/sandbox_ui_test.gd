extends SceneTree
# Headless UI test for the slice-2 fidelity toggle PATH — the piece slice2_verify.gd can't
# reach. The verifier drives SimClient directly, proving the set_fidelity wire + physics; the
# Sandbox.tscn smoke-load proves the scene loads + handshakes. Neither presses the toggle, so
# `_on_prop_pressed` and the toggle-triggered badge/button re-render + the reset resync ship
# unverified. This drives them directly (no server, no viewport): it builds only the nodes the
# toggle path touches, injects a recording mock client, feeds a fake `scenario` handshake, then
# asserts the button → badge → set_fidelity → reset loop behaves. (`_draw`'s below-horizon
# pixel branch still needs a windowed look; the `visible` flag it keys off is wire-verified by
# slice2_verify.gd.)
#
# Run:  godot --headless --path clients/godot --script res://net/sandbox_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

# A stand-in for SimClient that records sent frames instead of opening a socket.
class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb                                # held so _fail can free the subtree on the error path

func _initialize() -> void:
	print("SUI_INIT godot=", Engine.get_version_info().string)
	var sb = SandboxScript.new()          # NOT added to the tree → _ready (UI build + real
	                                       # socket) never fires; we wire the minimal pieces.
	_sb = sb
	# Only the nodes the toggle path reads/writes — avoids _build_ui()'s viewport-dependent
	# _layout_badge() and the real client entirely. Parent them to sb so sb.free() cascades
	# (otherwise orphan Controls leak text-server RIDs at exit).
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	var mock := MockClient.new()
	sb._client = mock

	# Fake the §5 `scenario` handshake: two_ray default + one knob (so _build_knobs runs too).
	sb._on_scenario({
		"name": "ui_test",
		"knobs": [{"target": "radar1", "key": "pt_w", "min": 1000, "max": 200000, "label": "Tx"}],
		"fidelity": {"propagation": "two_ray", "detection": "analytic"},
	})
	var badge_two: String = sb._badge.text
	var btn_two: String = sb._prop_btn.text

	# Press the toggle → should flip to free_space, re-render badge + button, send set_fidelity.
	sb._on_prop_pressed()
	var badge_free: String = sb._badge.text
	var btn_free: String = sb._prop_btn.text

	var sf: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity":
			sf = d
	print("SUI_TOGGLE badge_two='%s' badge_free='%s' btn_two='%s' btn_free='%s'" %
		[badge_two, badge_free, btn_two, btn_free])

	if not ("two_ray" in badge_two and "propagation" in badge_two):
		return _fail("badge did not render propagation:two_ray on handshake: '%s'" % badge_two)
	if badge_two == badge_free:
		return _fail("badge did not re-render on toggle (still '%s')" % badge_two)
	if not ("free_space" in badge_free):
		return _fail("badge did not flip to free_space on toggle: '%s'" % badge_free)
	if not ("two_ray" in btn_two) or not ("free_space" in btn_free):
		return _fail("button label did not track the toggle: '%s' -> '%s'" % [btn_two, btn_free])
	if sf == null:
		return _fail("toggle sent no set_fidelity frame (sent: %s)" % str(mock.sent))
	if str(sf.get("key", "")) != "propagation" or str(sf.get("value", "")) != "free_space":
		return _fail("wrong set_fidelity payload: %s" % str(sf))

	# Reset must resync the badge/button to the scenario default (server reloads YAML →
	# two_ray, with no new handshake — the client owns the displayed state).
	sb._on_reset_pressed()
	print("SUI_RESET badge='%s' btn='%s'" % [sb._badge.text, sb._prop_btn.text])
	if not ("two_ray" in sb._badge.text) or not ("two_ray" in sb._prop_btn.text):
		return _fail("reset did not resync to two_ray: badge='%s' btn='%s'" %
			[sb._badge.text, sb._prop_btn.text])

	print("SUI OK: toggle re-renders badge+button, sends set_fidelity, reset resyncs to default")
	_teardown()
	quit(0)

func _fail(msg: String) -> void:
	push_error("SUI FAIL: " + msg)
	print("SUI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	if _sb != null:
		_sb.free()        # frees the subtree (parented Controls + _build_knobs sliders)
		_sb = null
