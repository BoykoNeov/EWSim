extends SceneTree
# Headless UI test for the slice-21 ATMOSPHERE VIEW PATH — the piece slice21_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity/set_param wire + the coupled physics); the
# Sandbox.tscn smoke-load proves the scene loads against a slice-21 server. Neither exercises the CLIENT
# view-routing, and slice 21 is the first slice in this arc where that routing had to CHANGE.
#
# ⭐ WHAT THIS TEST IS REALLY FOR. Slice 20 shipped ZERO client code because its lesson was a SLIDER and
# it was happy to let `:airframe` keep the button. Slice 21's lesson IS a button — and its scenario ALSO
# ships `:airframe: pitch_coupled` (AUTHORED FIXED: ρ(z) is inert without the coupling, so the missile
# must stay coupled for a lift ceiling to exist at all). Two view-claiming fidelity keys in one handshake,
# for the first time in the arc. `_setup_spatial_fid_btn` checks `:atmosphere` FIRST so the ONE button
# toggles the LESSON's key and not the HELD one — the slice-13/14 rule ("a scenario ships several keys,
# all but one held; the button must be the unheld one" — convention 9), third occurrence.
#
# THE VALUE-GUARD IS FIVE-WAY NOW. The SAME `_setup_spatial_fid_btn` must keep every routing intact:
#   • slice 16 (airframe_view, NO fidelity)               → _fid_kind=airframe, button DROPPED
#   • slice 17/19/20 (airframe_view + :airframe)          → _fid_kind=airframe, button SHOWN (that cycler)
#   • slice 18 (terrain_grid)                             → the 3-D terrain branch, untouched
#   • slice 21 (airframe_view + :airframe + :atmosphere)  → _fid_kind=ATMOSPHERE, button = the atm cycler
# The 4th line is the one with teeth: slice 21 must win the button DESPITE `_fidelity.has("airframe")`
# being true. Get the ordering wrong and slice 21 silently ships slice 17's button — a scenario whose
# lesson is a rung, with the wrong rung on the button, and nothing else would catch it.
#
# ⭐ AND THE CONVERSE, WHICH IS THE REAL REGRESSION RISK: slices 17/19/20 have NO `:atmosphere` key, so
# they must be UNDISTURBED by the new first-checked branch. Asserted here for all three shapes, because
# "I only added a branch above it" is exactly the kind of claim that is false by one `elif`.
#
# Run:  godot --headless --path clients/godot --script res://net/slice21_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16
var _sb19
var _sb18

func _initialize() -> void:
	print("S21UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The §5 handshake for slice21_atmosphere: airframe_view=true + FOUR fidelity keys (atmosphere is the
	# ONE toggled button; airframe/guidance/autopilot are HELD) + exactly ONE knob + NO axis / NO
	# terrain_grid (stays spatial).
	sb._on_scenario({
		"name": "atmosphere_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0,
			 "label": "H scale height (m)"},
		],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled",
					 "guidance": "pn", "autopilot": "alpha"},
	})

	# ⭐ THE ORDERING TOOTH: atmosphere WINS the button over the co-shipped :airframe key.
	if sb._mode != "spatial":
		return _fail("a slice-21 handshake must STAY spatial (got %s)" % sb._mode)
	if sb._fid_kind != "atmosphere":
		return _fail("⭐ a slice-21 handshake must route to _fid_kind=atmosphere, got '%s' — the co-shipped :airframe key must NOT capture the button (it is AUTHORED FIXED here: the missile must stay coupled for a lift ceiling to exist at all, so it is the reference arm, not the lesson)" % sb._fid_kind)
	if not sb._airframe_view:
		return _fail("_airframe_view must latch true from the handshake marker — the aero/α strips and the nose-vs-velocity vectors are gated on it, and slice 21 REUSES all of them")
	if not sb._prop_btn.visible:
		return _fail("the shared fidelity button must be SHOWN in a slice-21 view — the rung IS the lesson (the live side-by-side is the punchline)")
	if not ("atm" in sb._prop_btn.text and "exponential" in sb._prop_btn.text):
		return _fail("the button must read 'atm: exponential' on handshake, got '%s'" % sb._prop_btn.text)
	if not ("exponential" in sb._badge.text and "pitch_coupled" in sb._badge.text):
		return _fail("the §12 badge must name every live fidelity incl. the held pitch_coupled, got '%s'" % sb._badge.text)
	print("S21UI_HANDSHAKE mode='%s' fid_kind='%s' btn='%s' badge='%s'" %
		[sb._mode, sb._fid_kind, sb._prop_btn.text, sb._badge.text])

	# THE CYCLER — exponential → constant → wrap, each press a set_fidelity on `atmosphere` (NOT airframe:
	# pressing this button must never disturb the held key, or the twin would stop being a twin).
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("atmosphere", "")) != "constant":
		return _fail("cycling must advance :atmosphere to constant, got %s" % str(sb._fidelity.get("atmosphere", "")))
	if not ("atm" in sb._prop_btn.text and "constant" in sb._prop_btn.text):
		return _fail("the button must re-render to 'atm: constant', got '%s'" % sb._prop_btn.text)
	if str(sb._fidelity.get("airframe", "")) != "pitch_coupled":
		return _fail("cycling the ATMOSPHERE must leave the HELD :airframe at pitch_coupled, got %s — the twin must differ in the AIR and nothing else" % str(sb._fidelity.get("airframe", "")))
	sb._prop_btn.emit_signal("pressed")
	if str(sb._fidelity.get("atmosphere", "")) != "exponential":
		return _fail("the cycler must WRAP back to exponential, got %s" % str(sb._fidelity.get("atmosphere", "")))
	var fid_sent := []
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity":
			fid_sent.append("%s=%s" % [str(d.get("key", "")), str(d.get("value", ""))])
	if fid_sent != ["atmosphere=constant", "atmosphere=exponential"]:
		return _fail("each press must send exactly one set_fidelity on `atmosphere`, got %s" % str(fid_sent))
	print("S21UI_CYCLE wrapped exponential→constant→exponential; wire=%s; held :airframe untouched" % str(fid_sent))

	# THE ONE KNOB. Exactly one slider — af_scale_height → set_param on m1. ρ₀ and α_max are DISQUALIFIED
	# (ρ₀ scales the WHOLE profile and cannot produce a GRADIENT, which is the precise difference this
	# slice exists to show; α_max is the very clamp whose LEAK bounds the H range), and K would confound
	# the isolation. Their ABSENCE is a design property, asserted — not an oversight.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("slice 21 must build EXACTLY ONE slider (af_scale_height), got %d" % sliders.size())
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
	if not keys_set.has("af_scale_height"):
		return _fail("the af_scale_height slider must send set_param, got keys %s" % str(keys_set.keys()))
	if keys_set["af_scale_height"] != "m1":
		return _fail("the lesson-lever set_param must target m1, got %s" % str(keys_set))
	if keys_set.has("rho") or keys_set.has("af_alpha_max") or keys_set.has("af_k_induced"):
		return _fail("slice 21 must NOT build ρ/α_max/K sliders — ρ₀ cannot produce a gradient, α_max's leak BOUNDS the H range, and K would confound the pure-altitude isolation, got %s" % str(keys_set.keys()))
	if keys_set.has("speed"):
		return _fail("slice 21 must NOT build a 'speed' slider — comp[:speed] is load-only, so it would be a DEAD knob (slice-19 gate-3 finding)")
	print("S21UI_KNOB exactly 1 slider; set_param keys=%s" % str(keys_set))

	# THE LESSON DRAWS ITSELF ON SLICE-19's STRIP — the reuse claim, proven rather than asserted. The aero
	# strip already plots the CORE's a_max_aero (cyan) vs a_demand (orange); under :exponential the ceiling
	# simply starts FALLING as the missile climbs. Feed two frames — low/thick then high/thin — and assert
	# the history carries the CORE's own scalars VERBATIM (convention 13: nothing recomputed in GDScript).
	sb._missile_id = "m1"
	sb._telemetry = {
		"m1.a_max_aero": 239.5, "m1.a_demand": 60.0, "m1.aero_sat": 0.0, "m1.alpha": 0.03,
		"m1.rho_air": 1.089, "m1.q_dyn": 266805.0, "m1.speed": 700.0, "m1.pos_z": 1000.0,
		"m1.alpha_cmd": 0.02, "m1.delta_cmd": 0.01, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state({"entities": []})
	sb._telemetry = {
		"m1.a_max_aero": 27.1, "m1.a_demand": 210.0, "m1.aero_sat": 1.0, "m1.alpha": 0.199,
		"m1.rho_air": 0.249, "m1.q_dyn": 30257.0, "m1.speed": 493.0, "m1.pos_z": 13570.0,
		"m1.alpha_cmd": 0.2, "m1.delta_cmd": 0.18, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state({"entities": []})
	if sb._ceil_hist.size() != 2 or sb._demand_hist.size() != 2:
		return _fail("the aero strip must sample a_max_aero/a_demand each frame (got %d/%d)" %
			[sb._ceil_hist.size(), sb._demand_hist.size()])
	if not is_equal_approx(float(sb._ceil_hist[0]), 239.5) or not is_equal_approx(float(sb._ceil_hist[1]), 27.1):
		return _fail("the ceiling history must carry the CORE's a_max_aero VERBATIM, got %s" % str(sb._ceil_hist))
	if not (float(sb._ceil_hist[1]) < float(sb._ceil_hist[0])):
		return _fail("the atmosphere lesson must show the ceiling FALLING as the missile climbs, got %s" % str(sb._ceil_hist))
	if not sb._aero_sat_now:
		return _fail("aero_sat=1.0 in the high/thin frame must light the client's binding tell (the client reads the CORE's flag — it never hand-rolls the compare)")
	print("S21UI_STRIP ceiling %s → the demand crosses it as the air thins; aero_sat lit=%s" %
		[str(sb._ceil_hist), str(sb._aero_sat_now)])

	# THE KEY-GATED READOUT: `rho_air` is a plain scalar, so _update_readout renders it automatically (it
	# iterates the telemetry — no whitelist). Assert the new key reaches the text.
	sb._update_readout()
	if not ("rho_air" in sb._readout.text or "rho_air" in sb._readout2.text or "rho_air" in sb._readout3.text):
		return _fail("the rho_air readout must render (it is a scalar — the auto-rendered path)")
	print("S21UI_READOUT rho_air reaches the readout text")

	# ⭐ THE VALUE-GUARD, ALL FOUR OTHER WAYS. The new first-checked branch must disturb NOTHING.
	# (a) slice 16 — airframe_view, NO fidelity at all → still DROPS the button (the Cmα slider is its lesson)
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._fid_kind != "airframe":
		return _fail("a slice-16 handshake must still route to _fid_kind=airframe, got %s" % _sb16._fid_kind)
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake (NO fidelity) must STILL drop the button — the atmosphere branch must not have stolen it")

	# (b) slice 17/19/20 — airframe_view + :airframe but NO :atmosphere → still the AIRFRAME cycler.
	# THE REAL REGRESSION RISK: "I only added a branch above it" is false by one `elif`.
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_alpha_max", "min": 0.05, "max": 0.4, "value": 0.2, "label": "α_max"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._fid_kind != "airframe":
		return _fail("a slice-17/19/20 handshake (NO :atmosphere) must STILL route to _fid_kind=airframe, got %s — the atmosphere branch must be value-guarded" % _sb19._fid_kind)
	if not _sb19._prop_btn.visible:
		return _fail("a slice-17/19/20 handshake must still SHOW the :airframe cycler")
	if not ("airframe" in _sb19._prop_btn.text):
		return _fail("a slice-17/19/20 button must still read 'airframe: …', got '%s'" % _sb19._prop_btn.text)

	# (c) slice 18 — terrain_grid wins the mode discriminator OUTRIGHT (it is decided before
	# _setup_spatial_fid_btn is ever called), so the 3-D view must be untouched by any of this.
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1",
		"terrain_grid": [[0.0, 0.0], [0.0, 0.0]], "terrain_n": 2,
		"terrain_extent": [0.0, 1000.0, 0.0, 1000.0],
		"knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._fid_kind == "atmosphere":
		return _fail("VALUE-GUARD: the terrain view must NOT be routed to _fid_kind=atmosphere")
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must still enter the 3-D terrain mode, got %s" % _sb18._mode)
	print("S21UI_GUARD five-way OK — 16 drops the button / 17-19-20 keep the airframe cycler / 18 stays 3-D / 21 takes the atm cycler")

	# Reset resyncs to the scenario default, keeps the button shown, and CLEARS the strip histories (a
	# stale falling ceiling would misread the new run — here, as an atmosphere that was never switched on).
	sb._on_reset_pressed()
	if not sb._prop_btn.visible:
		return _fail("reset must keep the :atmosphere cycler SHOWN")
	if str(sb._fidelity.get("atmosphere", "")) != "exponential":
		return _fail("reset must resync :atmosphere to the scenario default exponential, got %s" % str(sb._fidelity.get("atmosphere", "")))
	if sb._ceil_hist.size() != 0 or sb._demand_hist.size() != 0:
		return _fail("reset must CLEAR the aero strip histories (got %d/%d) — a stale falling trace would read as a collapse that did not happen" %
			[sb._ceil_hist.size(), sb._demand_hist.size()])
	print("S21UI_RESET button shown, :atmosphere resynced to exponential, strip histories cleared")
	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19/20_ui_test contract) ---------------------------------------------

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
	print("S21UI OK: a slice-21 handshake STAYS spatial and takes _fid_kind=ATMOSPHERE — the first time in " +
		"this arc that two view-claiming fidelity keys ship together, and the ONE button must be the LESSON's. " +
		"`:atmosphere` is checked FIRST in _setup_spatial_fid_btn so the co-shipped `:airframe: pitch_coupled` " +
		"(AUTHORED FIXED — ρ(z) is INERT without the coupling, so the missile must stay coupled for a lift " +
		"ceiling to exist at all) cannot capture it: the slice-13/14 rule, third occurrence. The cycler wraps " +
		"exponential→constant→exponential, sends exactly one set_fidelity per press, and never disturbs the " +
		"held key — the twin must differ in the AIR and nothing else. EXACTLY ONE slider (af_scale_height → " +
		"set_param m1); ρ/α_max/K are ABSENT deliberately (ρ₀ scales the whole profile and cannot make a " +
		"GRADIENT; α_max's leak BOUNDS the H range; K would confound the pure-altitude isolation). Everything " +
		"else is REUSE, proven not asserted: slice 19's aero strip carries the lesson (the ceiling simply " +
		"starts FALLING and the crossing draws itself), the α strip and nose-vs-velocity vectors ride on " +
		"_airframe_view, and `rho_air` renders through the no-whitelist scalar path. The value-guard holds " +
		"FIVE ways — 16 drops the button, 17/19/20 keep the airframe cycler (the real regression risk: 'I only " +
		"added a branch above it' is false by one elif), 18 stays 3-D, 21 takes the atm cycler. Reset resyncs " +
		"the rung and clears the strip histories.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S21UI FAIL: " + msg)
	print("S21UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for n in [_sb, _sb16, _sb19, _sb18]:
		if n != null:
			n.free()
	_sb = null
	_sb16 = null
	_sb19 = null
	_sb18 = null
