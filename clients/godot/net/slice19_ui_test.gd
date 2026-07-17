extends SceneTree
# Headless UI test for the slice-19 α/g AUTOPILOT VIEW PATH — the piece slice19_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity/set_param wire + the coupled physics); the
# Sandbox.tscn smoke-load proves the scene loads against a slice-19 server. Neither exercises the CLIENT
# view-routing: that a slice-19 handshake (airframe_view + an `:airframe` fidelity) STAYS spatial, REUSES
# _fid_kind=airframe (so slice-17's curved trail + nose/velocity/α drawing all carry over unchanged),
# SHOWS the point_mass↔pitch_coupled cycler, that the rho/af_alpha_max/af_cla sliders → set_param, and
# that the NEW slice-19 g-ceiling-vs-demand headline strip samples the core's telemetry.
#
# THE VALUE-GUARD IS NOW THREE-WAY (the memory-flagged both-ways check, one deeper). The SAME
# `_setup_spatial_fid_btn` code must keep all three routings intact — it checks the airframe branch FIRST:
#   • slice 16 (airframe_view, NO fidelity)          → _fid_kind=airframe, button DROPPED (nothing to cycle)
#   • slice 17/19 (airframe_view + :airframe fidelity) → _fid_kind=airframe, button SHOWN (the cycler)
#   • slice 18 (terrain_grid)                         → the 3-D terrain branch, untouched by any of this
#
# Run:  godot --headless --path clients/godot --script res://net/slice19_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16
var _sb18

func _initialize() -> void:
	print("S19UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# Fake the §5 handshake for the slice-19 α-limit scenario: airframe_view=true + the THREE fidelity
	# keys (airframe is the ONE toggled button; guidance/autopilot are authored-and-fixed — convention 9)
	# + the two lesson levers + af_cla + NO axis / NO terrain_grid (stays spatial).
	sb._on_scenario({
		"name": "alpha_limit_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.225, "label": "ρ air density (kg/m³)"},
			{"target": "m1", "key": "af_alpha_max", "min": 0.05, "max": 1.5, "value": 0.2, "label": "α_max stall limit (rad)"},
			{"target": "m1", "key": "af_cla", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Lα lift-curve slope (1/rad)"},
		],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})

	# handshake → STAYS spatial + REUSES _fid_kind=airframe + the button is SHOWN (the :airframe cycler).
	if sb._mode != "spatial":
		return _fail("a slice-19 handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "airframe":
		return _fail("a slice-19 handshake must REUSE _fid_kind=airframe (got %s) — the slice-17 view carries over" % sb._fid_kind)
	if not sb._airframe_view:
		return _fail("_airframe_view must latch true from the handshake marker")
	if not sb._prop_btn.visible:
		return _fail("the shared fidelity button must be SHOWN in a slice-19 view (the :airframe cycler)")
	if not ("airframe" in sb._prop_btn.text and "pitch_coupled" in sb._prop_btn.text):
		return _fail("the button must read 'airframe: pitch_coupled' on handshake, got '%s'" % sb._prop_btn.text)
	# The badge must name the approximation from the LIVE fidelity map (§12) — including the :alpha rung,
	# so the cross-fidelity dependency is visible to the user, not just in the code.
	if not ("alpha" in sb._badge.text and "pitch_coupled" in sb._badge.text):
		return _fail("the §12 badge must name the live fidelity incl. autopilot: alpha, got '%s'" % sb._badge.text)
	print("S19UI_HANDSHAKE mode='%s' fid_kind='%s' btn='%s' badge='%s'" %
		[sb._mode, sb._fid_kind, sb._prop_btn.text, sb._badge.text])

	# CYCLE: the 2-ring pitch_coupled → point_mass → pitch_coupled, each sending set_fidelity. This is THE
	# showcase button — the plant swap that turns the miss into a hit (the :alpha autopilot follows it:
	# it commands δ under :pitch_coupled and a_ctrl under :point_mass — the cross-fidelity dependency).
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("airframe", "")) != "point_mass":
		return _fail("cycling must advance :airframe to point_mass, got %s" % str(sb._fidelity.get("airframe", "")))
	var last_fid: Variant = null
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "airframe":
			last_fid = d
	if last_fid == null or str(last_fid.get("value", "")) != "point_mass":
		return _fail("cycling must send set_fidelity airframe=point_mass, got %s" % str(last_fid))
	sb._prop_btn.emit_signal("pressed")           # wrap back
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("the cycler must WRAP back to pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	print("S19UI_CYCLE wrapped pitch_coupled→point_mass→pitch_coupled; last set_fidelity=%s" % str(last_fid))

	# The three sliders → set_param. `rho` is THE DEMO LEVER and its liveness is the whole gate-3 finding:
	# the plan named `speed` here, but comp[:speed] is consumed ONCE at load and read by NOTHING per-tick,
	# so that slider would have been DEAD. ρ is fetched every tick by integrate! AND decide!.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() < 3:
		return _fail("expected the rho + af_alpha_max + af_cla sliders (got %d)" % sliders.size())
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
	if not (keys_set.has("rho") and keys_set.has("af_alpha_max") and keys_set.has("af_cla")):
		return _fail("the rho/af_alpha_max/af_cla sliders must all send set_param, got keys %s" % str(keys_set.keys()))
	if keys_set["rho"] != "m1" or keys_set["af_alpha_max"] != "m1":
		return _fail("the lesson-lever set_param frames must target m1, got %s" % str(keys_set))
	if keys_set.has("speed"):
		return _fail("slice 19 must NOT build a 'speed' slider — comp[:speed] is load-only, so it would be a DEAD knob")
	print("S19UI_SLIDERS set_param keys=%s" % str(keys_set))

	# THE HEADLINE STRIP: a state frame carrying the rung-gated α/g telemetry must feed the display-only
	# ceiling/demand histories (drawn as the crossing — the verdict). Sampled in _spatial_on_state; nothing
	# is recomputed client-side (convention 13 — the core owns the physics).
	sb._missile_id = "m1"
	sb._telemetry = {
		"m1.a_max_aero": 269.39, "m1.a_demand": 441.0, "m1.aero_sat": 1.0, "m1.alpha": 0.1369,
		"m1.q_dyn": 300097.0, "m1.alpha_cmd": 0.2, "m1.delta_cmd": 0.2667, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state({"entities": []})
	if sb._ceil_hist.size() != 1 or sb._demand_hist.size() != 1:
		return _fail("the slice-19 headline must sample a_max_aero/a_demand into the display histories (got %d/%d)" %
			[sb._ceil_hist.size(), sb._demand_hist.size()])
	if not is_equal_approx(float(sb._ceil_hist[0]), 269.39):
		return _fail("the ceiling history must carry the CORE's a_max_aero verbatim, got %s" % str(sb._ceil_hist[0]))
	if not sb._aero_sat_now:
		return _fail("aero_sat=1.0 in telemetry must light the client's binding tell")
	# …and a slice-16/17 frame (airframe_view, NO α/g keys) must leave the strip EMPTY — the key-gated
	# readout, so the prior slices' views are untouched (their UI tests still pass unchanged).
	var sb17 = _build_sandbox()
	sb17._missile_id = "m1"
	sb17._airframe_view = true
	sb17._telemetry = {"m1.alpha": 0.05, "m1.alpha_trim": 0.05, "m1.a_lift": 40.0}
	sb17._spatial_on_state({"entities": []})
	if sb17._ceil_hist.size() != 0:
		return _fail("a slice-16/17 frame (no a_max_aero key) must NOT feed the slice-19 strip, got %d samples" % sb17._ceil_hist.size())
	sb17.free()
	print("S19UI_HEADLINE ceil=%s demand=%s aero_sat=%s; a slice-17 frame leaves it empty" %
		[str(sb._ceil_hist), str(sb._demand_hist), str(sb._aero_sat_now)])

	# Reset resyncs to the scenario default, keeps the button shown, and CLEARS the headline histories
	# (they restart with the re-launch — a stale ceiling trace would misread the new run).
	sb._on_reset_pressed()
	if not sb._prop_btn.visible:
		return _fail("reset must keep the :airframe cycler SHOWN")
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("reset must resync :airframe to the default pitch_coupled, got %s" % str(sb._fidelity.get("airframe", "")))
	if sb._ceil_hist.size() != 0 or sb._demand_hist.size() != 0 or sb._aero_sat_now:
		return _fail("reset must CLEAR the slice-19 headline histories (got %d/%d, sat=%s)" %
			[sb._ceil_hist.size(), sb._demand_hist.size(), str(sb._aero_sat_now)])
	print("S19UI_RESET btn_visible=%s airframe=%s hist_cleared=yes" %
		[str(sb._prop_btn.visible), str(sb._fidelity.get("airframe", ""))])

	# --- THE VALUE-GUARD, ALL THREE WAYS ------------------------------------------------------------
	# (1) slice 16: airframe_view + NO :airframe fidelity → still DROPS the button (its lesson is the
	# af_cma slider, not a cycler). `_setup_spatial_fid_btn` checks the airframe branch FIRST, so a
	# careless slice-19 edit here is exactly what would hide the button slice 17/19 want — or show one
	# slice 16 has nothing to fill.
	var sb16 = _build_sandbox()
	_sb16 = sb16
	sb16._on_scenario({
		"name": "airframe16_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -0.5, "max": 0.5, "value": -0.3, "label": "Cmα"}],
		"fidelity": {},
	})
	if sb16._fid_kind != "airframe":
		return _fail("a slice-16 handshake must still set _fid_kind=airframe, got %s" % sb16._fid_kind)
	if sb16._prop_btn.visible:
		return _fail("VALUE-GUARD: a slice-16 handshake (no :airframe fidelity) must STILL DROP the button")
	print("S19UI_GUARD16 slice-16 handshake still drops the button (btn_visible=%s)" % str(sb16._prop_btn.visible))

	# (2) slice 18: a terrain_grid handshake still takes the 3-D branch — the airframe routing must not
	# have poached it (the discriminator order: terrain_grid is checked in _on_scenario, before the
	# spatial branch ever runs).
	var sb18 = _build_sandbox()
	_sb18 = sb18
	sb18._on_scenario({
		"name": "terrain18_ui",
		"terrain": "ter1",
		"terrain_n": 3,
		"terrain_extent_m": [-1000.0, 15000.0, -4000.0, 4000.0],
		"terrain_grid": [0.0, 10.0, 0.0, 5.0, 250.0, 5.0, 0.0, 10.0, 0.0],
		"radar": "radar1",
		"target": "tgt1",
		"knobs": [{"target": "tgt1", "key": "alt_hold_m", "min": 50.0, "max": 1500.0, "value": 120.0, "label": "alt"}],
		"fidelity": {"propagation": "terrain"},
	})
	if sb18._mode != "terrain":
		return _fail("VALUE-GUARD: a slice-18 terrain_grid handshake must STILL select the 3-D terrain mode, got %s" % sb18._mode)
	if sb18._fid_kind == "airframe":
		return _fail("VALUE-GUARD: the terrain view must NOT be routed to _fid_kind=airframe")
	print("S19UI_GUARD18 slice-18 terrain handshake still takes the 3-D branch (mode='%s')" % sb18._mode)

	print("S19UI OK: a slice-19 handshake STAYS spatial + REUSES _fid_kind=airframe + SHOWS the " +
		":airframe cycler (point_mass↔pitch_coupled, wraps, sends set_fidelity); the badge names the live " +
		"fidelity incl. autopilot:alpha; the rho (DEMO — live, unlike the planned DEAD `speed`) / " +
		"af_alpha_max (CAUSATION) / af_cla sliders send set_param to m1; the g-ceiling-vs-demand headline " +
		"samples the CORE's telemetry and clears on reset, while a slice-17 frame leaves it empty; AND the " +
		"value-guard holds ALL THREE WAYS (16 drops the button / 19 shows it / 18 stays 3-D).")
	_teardown()
	quit(0)

func _build_sandbox():
	var sb = SandboxScript.new()               # NOT added to the tree → _ready (UI build + socket) never fires
	sb._status   = Label.new()
	sb._knob_box = VBoxContainer.new()
	sb._badge    = Label.new()
	sb._prop_btn = Button.new()
	sb._play_btn = Button.new()
	sb._readout  = Label.new()
	for n in [sb._status, sb._knob_box, sb._badge, sb._prop_btn, sb._play_btn, sb._readout]:
		sb.add_child(n)
	sb._client = MockClient.new()
	return sb

func _find_all_sliders(box: Node) -> Array:
	var out: Array = []
	for c in box.get_children():
		if c is HSlider:
			out.append(c)
		out.append_array(_find_all_sliders(c))
	return out

func _fail(msg: String) -> void:
	push_error("S19UI FAIL: " + msg)
	print("S19UI FAIL: " + msg)
	_teardown()
	quit(1)

func _teardown() -> void:
	for sb in [_sb, _sb16, _sb18]:
		if sb != null:
			sb.free()
	_sb = null
	_sb16 = null
	_sb18 = null
