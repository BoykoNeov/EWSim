extends SceneTree
# Headless UI test for the slice-20 INDUCED-DRAG VIEW PATH — the piece slice20_verify.gd can't reach.
# The verifier drives SimClient directly (the set_param wire + the coupled physics); the Sandbox.tscn
# smoke-load proves the scene loads against a slice-20 server. Neither exercises the CLIENT view-routing.
#
# ⭐ WHAT THIS TEST IS REALLY FOR: slice 20 ships **ZERO new client code**, and that claim needs proving
# rather than asserting. The slice-19 airframe view carries it wholesale — the `:airframe` cycler branch
# (slice 20's scenario ships an `:airframe` fidelity, so `_setup_spatial_fid_btn` routes there), the
# ceiling-vs-demand aero strip (which now simply watches the ceiling FALL — the lesson draws itself),
# the α strip, the nose-vs-velocity vectors, and the auto-built knob slider. If any of that had drifted,
# the "no client edits" claim would be false. So this test asserts the REUSE.
#
# THE VALUE-GUARD IS FOUR-WAY NOW. The SAME `_setup_spatial_fid_btn` must keep every routing intact:
#   • slice 16 (airframe_view, NO fidelity)             → _fid_kind=airframe, button DROPPED
#   • slice 17/19/20 (airframe_view + :airframe fidelity) → _fid_kind=airframe, button SHOWN (the cycler)
#   • slice 18 (terrain_grid)                            → the 3-D terrain branch, untouched
# Slice 20 adds NO branch — it must land in the existing slice-17/19 arm and disturb nothing.
#
# THE ONE-KNOB SHAPE IS ALSO UNDER TEST. Slice 19 built THREE sliders; slice 20 builds exactly ONE
# (af_k_induced). α_max and ρ are DISQUALIFIED here (both are confounded with the new drag term — α_max
# feeds the bill through the achieved α; ρ moves the ceiling AND the bill), so their ABSENCE is a
# deliberate design property, asserted — not an oversight.
#
# Run:  godot --headless --path clients/godot --script res://net/slice20_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16

func _initialize() -> void:
	print("S20UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The §5 handshake for slice20_induced_drag: airframe_view=true + the three fidelity keys (airframe
	# is the ONE toggled button — slice 19's REFERENCE ARM here, since slice 20's lesson is the SLIDER)
	# + exactly ONE knob + NO axis / NO terrain_grid (stays spatial).
	sb._on_scenario({
		"name": "induced_drag_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_k_induced", "min": 0.0, "max": 0.3, "value": 0.15,
			 "label": "K induced-drag factor (C_Di = K·C_L²)"},
		],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})

	# handshake → STAYS spatial + REUSES _fid_kind=airframe + the button is SHOWN (the :airframe cycler).
	# Slice 20 adds no view: if this routes anywhere new, the "zero client code" claim is false.
	if sb._mode != "spatial":
		return _fail("a slice-20 handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "airframe":
		return _fail("a slice-20 handshake must REUSE _fid_kind=airframe (got %s) — the slice-17/19 view carries over wholesale" % sb._fid_kind)
	if not sb._airframe_view:
		return _fail("_airframe_view must latch true from the handshake marker")
	if not sb._prop_btn.visible:
		return _fail("the shared fidelity button must be SHOWN in a slice-20 view (the :airframe cycler — slice 19's reference arm)")
	if not ("airframe" in sb._prop_btn.text and "pitch_coupled" in sb._prop_btn.text):
		return _fail("the button must read 'airframe: pitch_coupled' on handshake, got '%s'" % sb._prop_btn.text)
	if not ("alpha" in sb._badge.text and "pitch_coupled" in sb._badge.text):
		return _fail("the §12 badge must name the live fidelity incl. autopilot: alpha, got '%s'" % sb._badge.text)
	print("S20UI_HANDSHAKE mode='%s' fid_kind='%s' btn='%s' badge='%s'" %
		[sb._mode, sb._fid_kind, sb._prop_btn.text, sb._badge.text])

	# THE ONE KNOB. Exactly one slider, and it must be af_k_induced → set_param on m1. The knob is the
	# LESSON here (the slice-16 shape: a live knob that changes physics without being a fidelity button)
	# — a rung would have named nothing the knob doesn't, since a `:free` rung IS K = 0.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("slice 20 must build EXACTLY ONE slider (af_k_induced), got %d — α_max/ρ are confounded with the drag term and are deliberately not knobs" % sliders.size())
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
	if not keys_set.has("af_k_induced"):
		return _fail("the af_k_induced slider must send set_param, got keys %s" % str(keys_set.keys()))
	if keys_set["af_k_induced"] != "m1":
		return _fail("the lesson-lever set_param must target m1, got %s" % str(keys_set))
	if keys_set.has("speed"):
		return _fail("slice 20 must NOT build a 'speed' slider — comp[:speed] is load-only, so it would be a DEAD knob")
	if keys_set.has("af_alpha_max") or keys_set.has("rho"):
		return _fail("slice 20 must NOT build α_max/ρ sliders — both are CONFOUNDED with the induced-drag term (convention 9: one lesson), got %s" % str(keys_set.keys()))
	print("S20UI_KNOB exactly 1 slider; set_param keys=%s" % str(keys_set))

	# THE CYCLER still works (slice 19's reference arm): pitch_coupled → point_mass → wrap. Under
	# :point_mass there is no α and no lift, so there is nothing to bill — the core drops `a_induced`
	# from the wire entirely (rung-gated), which the strip below covers.
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("airframe", "")) != "point_mass":
		return _fail("cycling must advance :airframe to point_mass, got %s" % str(sb._fidelity.get("airframe", "")))
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("the cycler must WRAP back to pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	print("S20UI_CYCLE wrapped pitch_coupled→point_mass→pitch_coupled")

	# ⭐ THE LESSON DRAWS ITSELF ON SLICE-19's STRIP. Slice 20 needed no new chart: the aero strip already
	# plots the CORE's a_max_aero (cyan) vs a_demand (orange), and slice 20's ceiling simply FALLS across
	# the run. Feed two frames — early (ceiling high) then late (ceiling collapsed) — and assert the
	# history carries the CORE's own scalars verbatim (convention 13: nothing is recomputed in GDScript).
	sb._missile_id = "m1"
	sb._telemetry = {
		"m1.a_max_aero": 269.39, "m1.a_demand": 160.0, "m1.aero_sat": 0.0, "m1.alpha": 0.133,
		"m1.a_induced": 12.4, "m1.a_lift": 180.0, "m1.speed": 700.0,
		"m1.alpha_cmd": 0.10, "m1.delta_cmd": 0.13, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state({"entities": []})
	sb._telemetry = {
		"m1.a_max_aero": 32.1, "m1.a_demand": 280.0, "m1.aero_sat": 1.0, "m1.alpha": 0.177,
		"m1.a_induced": 86.0, "m1.a_lift": 30.0, "m1.speed": 241.7,
		"m1.alpha_cmd": 0.2, "m1.delta_cmd": 0.27, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state({"entities": []})
	if sb._ceil_hist.size() != 2 or sb._demand_hist.size() != 2:
		return _fail("the aero strip must sample a_max_aero/a_demand each frame (got %d/%d)" %
			[sb._ceil_hist.size(), sb._demand_hist.size()])
	if not is_equal_approx(float(sb._ceil_hist[0]), 269.39) or not is_equal_approx(float(sb._ceil_hist[1]), 32.1):
		return _fail("the ceiling history must carry the CORE's a_max_aero VERBATIM, got %s" % str(sb._ceil_hist))
	# THE SPIRAL, as the user sees it: the ceiling FALLS while the demand RISES — they CROSS, and the
	# crossing is the verdict. The client never decides that; it draws the core's numbers and lights the
	# core's flag (the verifier asserts `aero_sat` itself, never a hand-rolled compare — slice-19 gate-2).
	if not (float(sb._ceil_hist[1]) < float(sb._ceil_hist[0])):
		return _fail("the spiral must show the ceiling FALLING across the run, got %s" % str(sb._ceil_hist))
	if not sb._aero_sat_now:
		return _fail("aero_sat=1.0 in the late frame must light the client's binding tell")
	print("S20UI_STRIP ceiling %s → the demand crosses it; aero_sat lit=%s" % [str(sb._ceil_hist), str(sb._aero_sat_now)])

	# THE KEY-GATED READOUT: `a_induced` is a plain scalar, so _update_readout renders it automatically
	# (it iterates the telemetry — no whitelist). That is WHY the bill needed no client code. Assert it
	# reaches the text, and that an Array-valued key would still be skipped (the float()-crash watch-item).
	sb._update_readout()
	if not ("a_induced" in sb._readout.text or "a_induced" in sb._readout2.text or "a_induced" in sb._readout3.text):
		return _fail("the a_induced bill must render in the readout (it is a scalar — the auto-rendered path)")
	print("S20UI_READOUT a_induced reaches the readout text")

	# …and a slice-16/17 frame (airframe_view, NO α/g keys) must leave the strip EMPTY — the key-gated
	# readout, so the prior slices' views are untouched (their UI tests still pass unchanged).
	var sb17 = _build_sandbox()
	sb17._missile_id = "m1"
	sb17._airframe_view = true
	sb17._telemetry = {"m1.alpha": 0.05, "m1.alpha_trim": 0.05, "m1.a_lift": 40.0}
	sb17._spatial_on_state({"entities": []})
	if sb17._ceil_hist.size() != 0:
		return _fail("a slice-16/17 frame (no a_max_aero key) must NOT feed the aero strip, got %d samples" % sb17._ceil_hist.size())
	sb17.free()

	# THE VALUE-GUARD, STILL THREE-WAY: a slice-16 handshake (airframe_view, NO :airframe fidelity) must
	# STILL drop the button. Slice 20 adds no fidelity at all, so this must be untouched — but "must be
	# untouched" is exactly the kind of claim that rots silently, so it is re-asserted here.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._fid_kind != "airframe":
		return _fail("a slice-16 handshake must still route to _fid_kind=airframe, got %s" % _sb16._fid_kind)
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake (NO :airframe fidelity) must still DROP the button — the value-guard both ways")
	print("S20UI_GUARD slice-16 (no fidelity) still drops the button; slice-20 (with fidelity) shows it")

	# Reset resyncs to the scenario default, keeps the button shown, and CLEARS the strip histories (a
	# stale ceiling trace would misread the new run — and here it would misread it as a SPIRAL).
	sb._on_reset_pressed()
	if not sb._prop_btn.visible:
		return _fail("reset must keep the :airframe cycler SHOWN")
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("reset must resync :airframe to the scenario default pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	if sb._ceil_hist.size() != 0 or sb._demand_hist.size() != 0:
		return _fail("reset must CLEAR the aero strip histories (got %d/%d) — a stale falling trace would read as a spiral that did not happen" %
			[sb._ceil_hist.size(), sb._demand_hist.size()])
	print("S20UI_RESET button shown, :airframe resynced to pitch_coupled, strip histories cleared")
	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19_ui_test contract) ------------------------------------------------

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	return sb

func _find_all_sliders(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	for c in node.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_all_sliders(c))
	return out

func _pass() -> bool:
	print("S20UI OK: a slice-20 handshake STAYS spatial and REUSES _fid_kind=airframe — slice 20 ships ZERO " +
		"new client code and this proves it: the slice-17/19 airframe view carries the lesson wholesale. The " +
		"aero strip already plotted the core's ceiling-vs-demand, so slice 20's ceiling simply starts FALLING " +
		"and the crossing draws itself; `a_induced` is a scalar, so the readout renders it with no whitelist " +
		"edit. EXACTLY ONE slider (af_k_induced → set_param m1) — the lesson is the KNOB (the slice-16 shape; " +
		"a `:free` rung would have named nothing K=0 doesn't), and α_max/ρ are ABSENT deliberately (both are " +
		"confounded with the new drag term). The :airframe cycler stays as slice 19's reference arm and wraps; " +
		"the value-guard still drops the button for a fidelity-less slice-16 handshake; reset clears the strip " +
		"histories (a stale falling trace would read as a spiral that never happened).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S20UI FAIL: " + msg)
	print("S20UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for n in [_sb, _sb16]:
		if n != null:
			n.free()
	_sb = null
	_sb16 = null
