extends SceneTree
# Headless UI test for the slice-26 RADOME view routing — the piece slice26_verify.gd can't reach.
# The verifier drives SimClient directly (the set_param wire + the parasitic-loop physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT view routing.
#
# ⭐ THE LOAD-BEARING TOOTH IS THAT SLICE 26 *DROPS* THE BUTTON, AND THAT IT IS THE ONLY ONE OF THE
# FOUR airframe3d WIRES THAT DOES. Slices 23, 24, 25 and 26 ALL enter the 3-D airframe view
# (_mode=airframe3d, airframe_6dof=true). What splits them is what the shared button does — and the
# radome marker is checked FIRST ("check the NEW key first", 5th occurrence):
#   • airframe_6dof + `radome_view`  → slice 26: the button is HIDDEN (there is NO rung to cycle —
#                                      the lesson is the radome_slope SLIDER, slice-16's Option-P′)
#   • airframe_6dof + `seeker_axes`  → slice 25: the SEEKER-AXES cycler (2-ring)
#   • airframe_6dof + `steering`     → slice 24: the STEERING cycler (2-ring)
#   • airframe_6dof + none of them   → slice 23: the AIRFRAME cycler (3-ring)
#
# ⚠ AND THE SLICE-25 MIRROR IS THE SHARPEST CASE. A slice-26 wire ALSO carries `seeker_axes` in its
# fidelity (HELD at az_el), so a careless `elif` ordering — or an `or` instead of a SWITCH — routes it
# to the seeker-axes cycler and hands the student a button whose other position (`:pitch_plane`)
# leaves the radome LIVE AND REFRACTING beside slice 25's unrelated 2000 m blind miss. Two mechanisms
# compounding in one view is exactly what convention 9 exists to prevent, so BOTH directions are
# asserted: slice 26 (with seeker_axes) drops the button, slice 25 (without radome_view) keeps it.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-26 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. MIRROR (the sharp one): the SAME fidelity WITHOUT radome_view keeps the seeker-axes cycler
#   3. MIRROR: slice-24 (steering) and slice-23 (neither) are untouched
#   4. the radome_slope SLIDER is built from the handshake knob and drives set_param
#   5. the off-tree state path carries the radome telemetry keys (core scalars — no client physics)
#   6. the value-guard, EIGHT-WAY (16 / 18 / 21 / 23 / 24 / 25 / 26)
#
# Run:  godot --headless --path clients/godot --script res://net/slice26_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb25
var _sb24
var _sb23
var _sb16
var _sb18
var _sb21

func _initialize() -> void:
	print("S26UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice26_radome: airframe_view + airframe_6dof + radome_view, a fidelity with
	# EVERY key HELD (including `seeker_axes` at az_el — the mirror hazard above), and ONE knob.
	sb._on_scenario({
		"name": "s26_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"radome_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "radome_slope", "min": -0.12, "max": 0.06, "value": -0.10,
			 "label": "radome error slope R"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: the 3-D view, and the button is DROPPED ═════════════════════════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-26 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._prop_btn.visible:
		return _fail("a slice-26 handshake must DROP the shared button — there is NO fidelity rung to cycle (R = 0 is an in-domain slider value AND bit-identical to the radome not existing). Slice-16's Option-P′.")
	if not sb._radome_view:
		return _fail("the client must record the radome_view handshake marker")
	# the 3-D scene must STILL have been built — dropping the button must not drop the view
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 26 reuses the slice-23 3-D view wholesale")
	print("S26UI_ROUTE airframe3d + button HIDDEN + the 3-D scene still built")

	# ══ TOOTH 2 — THE MIRROR THAT MATTERS: the SAME fidelity WITHOUT radome_view keeps slice 25's ════
	# cycler. This is what proves an if/elif SWITCH keyed on the MARKER, not an `or` or a reordering.
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4,
				   "label": "σ_seek"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._mode != "airframe3d" or _sb25._fid_kind != "seeker_axes":
		return _fail("a slice-25 handshake (seeker_axes, NO radome_view) must KEEP _fid_kind=seeker_axes, got kind=%s" % _sb25._fid_kind)
	if not _sb25._prop_btn.visible:
		return _fail("a slice-25 handshake must still SHOW its cycler — only the radome marker drops the button")
	print("S26UI_MIRROR25 the same fidelity WITHOUT radome_view keeps the seeker-axes cycler (a SWITCH on the MARKER)")

	# ══ TOOTH 3 — the other two mirrors: slice 24 (steering) and slice 23 (neither) are untouched ════
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._fid_kind != "steering" or not _sb24._prop_btn.visible:
		return _fail("a slice-24 handshake must keep _fid_kind=steering with the button shown, got kind=%s vis=%s" % [_sb24._fid_kind, _sb24._prop_btn.visible])
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Yβ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._fid_kind != "airframe" or _sb23._airframe_rungs.size() != 3:
		return _fail("a slice-23 handshake must keep the 3-RING airframe cycler, got kind=%s rungs=%s" % [_sb23._fid_kind, str(_sb23._airframe_rungs)])
	print("S26UI_MIRROR2324 slice-24 keeps steering / slice-23 keeps the 3-ring airframe")

	# ══ TOOTH 4 — the SLIDER is the lesson: it is built, and it drives set_param ═════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("slice 26 must build EXACTLY ONE slider (radome_slope), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-26 wire must NEVER send set_fidelity — there is no rung; the lesson is the slider")
	if not keys_set.has("radome_slope"):
		return _fail("the radome_slope slider must send set_param, got keys %s" % str(keys_set.keys()))
	if keys_set["radome_slope"] != "m1":
		return _fail("the lesson-lever set_param must target m1, got %s" % str(keys_set))
	# The DISQUALIFICATIONS are a design property, asserted — not an oversight. Each of these MOVES the
	# lesson: n_pn and rho move the LOOP GAIN N·|R|/ρ the lesson is ABOUT (so a student could cross the
	# threshold without touching the radome), alpha_max sets the cycle's AMPLITUDE (the thing the
	# isolation holds fixed), and sigma_seek — slice 25's own knob — compresses the ring's signature
	# from 106× to 14× at its top.
	for bad in ["n_pn", "rho", "af_alpha_max", "alpha_max", "sigma_seek", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 26 must NOT build a '%s' slider — it moves the loop gain / the cycle amplitude / the ring's own signature, got %s" % [bad, str(keys_set.keys())])
	print("S26UI_KNOB exactly 1 slider (radome_slope → m1); NOTHING sends set_fidelity")

	# ══ TOOTH 5 — the off-tree state path carries the radome telemetry (core scalars only) ══════════
	sb._telemetry = {
		"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.radome_eps": -0.0122,
		"m1.radome_eps_az": 0.0031, "m1.look_angle": 6.9, "m1.omega_ratio": 7.13,
		"m1.radome_slope": -0.10, "m1.aero_sat": 1.0, "m1.alpha": 0.139,
		# a NORMALIZED quaternion (0.5² × 4 = 1) — Godot's Quaternion.xform asserts unit norm
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	# convention 13 — every radome readout arrives as a plain core-computed scalar. The client never
	# derives ε from an attitude, never recomputes a look angle, and never forms omega_ratio itself.
	for k in ["m1.radome_eps", "m1.look_angle", "m1.omega_ratio", "m1.omega_q"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side physics)" % k)
	sb._update_readout()
	print("S26UI_STATE trail + markers + the radome readouts handled off-tree (no crash)")

	# ══ TOOTH 6 — THE VALUE-GUARD, EIGHT-WAY ════════════════════════════════════════════════════════
	# (a) slice 16 — airframe_view, NO fidelity → 2-D airframe, button DROPPED. ⚠ Slice 26 also drops
	#     the button, and they must NOT collapse into one branch: 16 is the 2-D SPATIAL view, 26 is
	#     the 3-D airframe view. Same button decision, different mode — assert BOTH fields.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slice 16 and slice 26 both drop the button but must NOT share a mode (16 = 2-D spatial, 26 = 3-D airframe3d)")
	# (b) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (c) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S26UI_GUARD eight-way OK — 16 drops(2-D) / 18 terrain-3-D / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D)")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..25_ui_test contract) --------------------------------------------

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
	print("S26UI OK: a slice-26 handshake (airframe_6dof + `radome_view`) enters the 3-D airframe view and " +
		"DROPS the shared button — the only one of the four airframe3d wires that does, because slice 26 has " +
		"no fidelity rung at all (R = 0 is an in-domain slider value AND bit-identical to the radome not " +
		"existing). Slice-16's Option-P′, second use. THE SHARP MIRROR HOLDS: the SAME fidelity WITHOUT the " +
		"marker keeps slice 25's seeker-axes cycler — so this is an if/elif SWITCH on the MARKER, not an " +
		"`or` or a lucky ordering, and a radome wire can never hand the student a button whose other " +
		"position leaves the radome refracting beside slice 25's unrelated 2000 m blind miss. Slices 24 " +
		"and 23 keep theirs. The lesson is the SLIDER: exactly one knob, driving set_param radome_slope, " +
		"with NOTHING sending set_fidelity. The value-guard holds EIGHT ways, and 16-vs-26 is asserted on " +
		"BOTH mode and visibility so the two button-dropping branches cannot collapse. Every radome readout " +
		"(eps / look_angle / omega_ratio / omega_q) reaches the HUD as a core-computed scalar — no " +
		"client-side physics. The DRAWING is proven by the windowed shot harness (convention 14's 4th proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S26UI FAIL: " + msg)
	print("S26UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb25, _sb24, _sb23, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
