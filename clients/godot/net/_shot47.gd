extends SceneTree
# Throwaway WINDOWED shot harness for slice 47 (convention 14's 4th proof — Godot skips `_draw`
# headless). Instantiates the REAL Sandbox against a live slice-47 server and captures the 3-D
# airframe view with the MIDCOURSE HUD. MODE comes from the S47_SHOT_MODE env var:
#   blind — the shipped default (38 m/s of picture error) captured WHILE STILL BLIND: the head is
#           cued off a belief, the magenta belief line is separated from the orange LOS, and the
#           headline reads the predicted handover angle against the window.
#   lost  — DRAG THE SLIDER to 39 m/s (the real UI path) and capture after the receiver has opened:
#           the cue error was 10.05° into a 10° window, the seeker never acquires, and the headline
#           says MISSED THE WINDOW.
#   ok    — DRAG THE SLIDER to 0 (a perfect picture) and capture after the handover: HANDED OVER at
#           0.0°, cruising, the belief line collapsed onto the LOS.
# ⚠ The picture-error slider is the ONLY knob, so `_find_sliders()[0]` is it; the value is read back.
# ⚠ THE BUTTON MUST BE VISIBLE AND SAY `detect:` IN ALL THREE — slice 47's marker takes the HUD and
# deliberately NOT the button, and a shot where it had been stolen is the failure that proves it.
# Run WINDOWED (no --headless) so `_draw` + the 3-D SubViewport get a real render context.
const SandboxScene := preload("res://scenes/Sandbox.tscn")

var _sb
var _state := "WAIT"
var _t := 0.0
var _mode := OS.get_environment("S47_SHOT_MODE")
var _cap_path := ""

func _initialize() -> void:
	if _mode == "":
		_mode = "blind"
	_cap_path = "M:/claud_projects/temp/slice47/slice47_shot_%s.png" % _mode
	_sb = SandboxScene.instantiate()
	get_root().add_child(_sb)
	get_root().size = Vector2i(1280, 800)

func _tel(k: String, d := 0.0) -> float:
	return float(_sb._telemetry.get("m1." + k, d)) if _sb != null else d

func _los() -> float:
	return _tel("los_range", 1.0e30)

func _find_sliders(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_sliders(c))
	return out

func _process(dt: float) -> bool:
	_t += dt
	match _state:
		"WAIT":
			if _sb != null and _sb._mode == "airframe3d" and _sb._entities.has("m1"):
				_sb._on_reset_pressed()          # relaunch from t=0
				_t = 0.0
				_state = "RESET"
		"RESET":
			if _t > 0.8:
				if _mode != "blind":
					var ss := _find_sliders(_sb._knob_box)
					if ss.size() != 1:
						print("SHOT expected exactly ONE slider, got ", ss.size())
						quit(3)
						return true
					ss[0].value = (39.0 if _mode == "lost" else 0.0)
					print("SHOT drove slider[0] to ", ss[0].value)
				print("SHOT mode=", _mode, "  midcourse_view=", _sb._midcourse_view,
					  "  button_visible=", _sb._prop_btn.visible, "  btn='", _sb._prop_btn.text,
					  "'  (must be visible AND say detect: — slice 47 does NOT take the button)")
				_t = 0.0
				_state = "FLY"
		"FLY":
			# ⚠ EACH MODE HAS ITS OWN READY CONDITION, because the three pictures are of three
			# different moments: BLIND must be caught while the head is still CUED, and the other two
			# after the receiver has opened — one that acquired and one that did not.
			var cued := _tel("head_cued", 0.0) >= 0.5
			var ready := false
			if _mode == "blind":
				ready = cued and _los() < 1650.0
			else:
				ready = (not cued) and _sb._mid_was_cued and _los() < 1200.0
			if ready or _t > 40.0:
				print("SHOT los=", _los(), "  cued=", cued, "  cue@handover=",
					  _tel("head_cue_err_handover_deg"), "  fov=", _tel("gimbal_fov_deg"),
					  "  acquired=", _sb._mid_acquired, "  auth_peak=", _sb._mid_auth_peak,
					  "  pip_err=", _tel("midcourse_pip_err_m"), "  t=", _t)
				_t = 0.0
				_state = "SETTLE"
		"SETTLE":
			if _t > 0.20:                        # let the 3-D SubViewport render a few frames
				var img := get_root().get_texture().get_image()
				img.save_png(_cap_path)
				print("SHOT saved ", _cap_path, " (", img.get_width(), "x", img.get_height(), ")",
					  "  cue=", _tel("head_cue_err_handover_deg"), "  acquired=", _sb._mid_acquired,
					  "  button_visible=", _sb._prop_btn.visible)
				quit(0)
				return true
	if _t > 120.0:
		print("SHOT TIMEOUT in state ", _state)
		quit(2)
		return true
	return false
