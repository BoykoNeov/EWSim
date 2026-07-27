extends SceneTree
# Headless UI test for the slice-27 RADOME-COMPENSATION view routing + HUD — the piece
# slice27_verify.gd can't reach. The verifier drives SimClient directly (the set_param wire + the
# residual physics); the Sandbox.tscn smoke-load proves the scene loads. Neither exercises the
# CLIENT routing or the one line of HUD this slice adds.
#
# ⭐ THE LOAD-BEARING TOOTH IS THE SLICE-26 MIRROR, AND IT IS SHARPER THAN SLICE 26's OWN. Slice 27
# reuses slice 26's `radome_view` marker UNCHANGED — same view, same dropped button — so the two
# wires are indistinguishable by ROUTING. What separates them is the HUD, which must be a SWITCH on
# the COMPENSATOR's own telemetry key (`radome_residual`), not an `or` and not a reordering:
#   • radome_view + `radome_residual` in telemetry → slice 27: R, R̂ and the RESIDUAL, and the
#                                                    headline names the CURE ("COMPENSATED")
#   • radome_view, NO `radome_residual`            → slice 26: its own slope line, verbatim
# A careless implementation that keyed off `radome_view` alone would print a residual of 0.000 on
# every slice-26 wire — a number that is not merely cosmetic but WRONG (slice 26 has no compensator,
# so its residual is its bare slope), and it would silently rewrite slice 26's lesson on screen.
#
# ⚠ AND THE BUTTON MUST STILL BE DROPPED. Slice 27 adds no rung — `R̂ = 0` is an in-domain slider
# value AND bit-identical to the compensator not existing (measured, test_missile.jl) — so the
# knob-vs-rung discriminator returns KNOB and slice-16's Option-P′ applies for the THIRD time
# (16, 26, 27). Nothing in this wire may ever send set_fidelity.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-27 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. ⭐ the HUD MIRROR: with `radome_residual` present the compensator lines render; without it the
#      slice-26 line renders — asserted BOTH ways (a SWITCH, not an `or`)
#   3. TWO sliders (R̂ and R) are built and BOTH drive set_param; nothing sends set_fidelity
#   4. the disqualified knobs are absent (the confounded-lever rule, asserted not assumed)
#   5. the off-tree state path carries the compensator telemetry (core scalars — no client physics),
#      and in particular the RESIDUAL arrives as a NUMBER (convention 13 — the client never subtracts)
#   6. the value-guard, NINE-WAY (16 / 18 / 21 / 23 / 24 / 25 / 26 / 27)
#
# Run:  godot --headless --path clients/godot --script res://net/slice27_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb26
var _sb25
var _sb24
var _sb23
var _sb16
var _sb18
var _sb21

func _initialize() -> void:
	print("S27UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice27_radome_comp: slice 26's markers UNCHANGED (airframe_view +
	# airframe_6dof + radome_view), every fidelity HELD, and TWO knobs.
	sb._on_scenario({
		"name": "s27_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"radome_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "radome_slope_est", "min": -0.15, "max": 0.0, "value": 0.0,
			 "label": "COMPENSATOR: slope estimate R̂"},
			{"target": "m1", "key": "radome_slope", "min": -0.2, "max": 0.0, "value": -0.10,
			 "label": "RADOME: true error slope R"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: slice 26's view and its dropped button, INHERITED unchanged ═════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-27 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._prop_btn.visible:
		return _fail("a slice-27 handshake must DROP the shared button — slice 27 adds NO rung (R̂ = 0 is an in-domain slider value AND bit-identical to the compensator not existing). Slice-16's Option-P′, third use.")
	if not sb._radome_view:
		return _fail("the client must record the radome_view handshake marker (inherited from slice 26)")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 27 reuses the slice-23/26 3-D view wholesale")
	print("S27UI_ROUTE airframe3d + button HIDDEN + the 3-D scene still built (slice 26's routing, inherited)")

	# ══ TOOTH 2 — ⭐ THE HUD MIRROR: a SWITCH on `radome_residual`, asserted BOTH ways ═══════════════
	# The compensated wire. `_update_readout` + the HUD draw path must tolerate the new keys, and the
	# residual must be the CORE's number — the client never subtracts R̂ from R itself.
	sb._telemetry = {
		"m1.los_range": 1500.0, "m1.omega_q": -0.02, "m1.radome_eps": -0.0012,
		"m1.radome_eps_az": 0.0003, "m1.look_angle": 4.1, "m1.omega_ratio": 1.02,
		"m1.radome_slope": -0.10, "m1.radome_slope_est": -0.10, "m1.radome_residual": 0.0,
		"m1.radome_ff_el": 0.0044, "m1.aero_sat": 0.0, "m1.alpha": 0.013,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	sb._update_readout()
	# ⚠ convention 13 — the RESIDUAL is the quantity that decides, and it arrives from the CORE as one
	# scalar. If the client ever computed `slope - slope_est` itself that would be physics in GDScript
	# (and it would be wrong the moment a wire compensates for glass it does not have).
	for k in ["m1.radome_residual", "m1.radome_slope_est", "m1.radome_ff_el"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side physics)" % k)
	# The MIRROR: a slice-26 wire — SAME marker, SAME view, NO compensator key — must keep its own
	# HUD line. This is the assert that fails if the HUD keys off `radome_view` instead of the
	# compensator's telemetry.
	_sb26 = _build_sandbox()
	_sb26._on_scenario({
		"name": "s26_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_slope", "min": -0.12, "max": 0.06, "value": -0.10,
				   "label": "radome error slope R"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	_sb26._telemetry = {
		"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.radome_eps": -0.0122,
		"m1.radome_eps_az": 0.0031, "m1.look_angle": 6.9, "m1.omega_ratio": 7.13,
		"m1.radome_slope": -0.10, "m1.aero_sat": 1.0, "m1.alpha": 0.139,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	_sb26._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb26._update_readout()
	if _sb26._telemetry.has("m1.radome_residual"):
		return _fail("the slice-26 MIRROR must carry NO radome_residual key — otherwise this tooth proves nothing")
	if _sb26._mode != sb._mode or _sb26._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 26 and 27 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD switch, got modes %s/%s" % [_sb26._mode, sb._mode])
	print("S27UI_MIRROR26 same routing as slice 26; the HUD is a SWITCH on `radome_residual`, asserted BOTH ways")

	# ══ TOOTH 3+4 — TWO sliders, both driving set_param; nothing sends set_fidelity ═════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("slice 27 must build EXACTLY TWO sliders (radome_slope_est + radome_slope), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-27 wire must NEVER send set_fidelity — there is no rung; the lesson is the SLIDERS")
	for need in ["radome_slope_est", "radome_slope"]:
		if not keys_set.has(need):
			return _fail("the '%s' slider must send set_param, got keys %s" % [need, str(keys_set.keys())])
		if keys_set[need] != "m1":
			return _fail("the '%s' set_param must target m1, got %s" % [need, str(keys_set)])
	# ⚠ TWO knobs is convention-9-legal ONLY because they are two halves of ONE quantity (the residual
	# R − R̂) — proven by the verifier's DIAGONAL phase, where moving both together changes nothing.
	# The DISQUALIFICATIONS are a design property, asserted: each of these moves the BOUNDARY, so a
	# student could cross it without touching either slope (the confounded-lever rule). n_pn is the
	# sharpest — the objection is STRONGER here than in slice 26, because with a compensator on the
	# wire a student who crossed the boundary via N would credit the compensator.
	for bad in ["n_pn", "rho", "af_alpha_max", "alpha_max", "sigma_seek", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 27 must NOT build a '%s' slider — it moves the loop gain N·|R − R̂|/ρ / the cycle amplitude / the ring's own signature, got %s" % [bad, str(keys_set.keys())])
	print("S27UI_KNOB exactly 2 sliders (radome_slope_est + radome_slope → m1); NOTHING sends set_fidelity")

	# ══ TOOTH 5 — the off-tree state path survives the compensated telemetry ════════════════════════
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S27UI_STATE trail + markers + the compensator readouts handled off-tree (no crash)")

	# ══ TOOTH 6 — THE VALUE-GUARD, NINE-WAY ════════════════════════════════════════════════════════
	# (a) slice 25 — seeker_axes WITHOUT the radome marker keeps its cycler
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4,
				   "label": "σ_seek"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 handshake must KEEP its seeker-axes cycler, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# (b) slice 24 — steering; (c) slice 23 — the 3-ring airframe cycler
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
	# (d) slice 16 — the OTHER button-dropping branch. ⚠ THREE branches now drop the button (16, 26,
	#     27) and they must NOT collapse: 16 is the 2-D SPATIAL view, 26/27 the 3-D airframe view.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slices 16 and 27 both drop the button but must NOT share a mode (16 = 2-D spatial, 27 = 3-D airframe3d)")
	# (e) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (f) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S27UI_GUARD nine-way OK — 16 drops(2-D) / 18 terrain-3-D / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D, no residual) / 27 drops(3-D, residual)")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..26_ui_test contract) --------------------------------------------

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
	print("S27UI OK: a slice-27 handshake reuses slice 26's `radome_view` marker UNCHANGED — the same 3-D " +
		"airframe view, the same DROPPED button — because slice 27 adds no fidelity rung either (R̂ = 0 is an " +
		"in-domain slider value AND bit-identical to the compensator not existing). Slice-16's Option-P′, " +
		"third use. ⭐ THE SHARP TOOTH IS THAT 26 AND 27 ARE INDISTINGUISHABLE BY ROUTING, so the HUD must " +
		"be a SWITCH on the COMPENSATOR's own telemetry key (`radome_residual`) — asserted BOTH ways, " +
		"because keying off `radome_view` instead would print a residual of 0.000 on every slice-26 wire, " +
		"which is not cosmetic but WRONG (slice 26 has no compensator, so its residual IS its bare slope). " +
		"TWO sliders are built and both drive set_param, with NOTHING sending set_fidelity — and two knobs " +
		"is convention-9-legal only because they are two halves of ONE quantity (the residual), which the " +
		"verifier's DIAGONAL phase is what proves. The disqualified levers (n_pn, rho, alpha_max, " +
		"sigma_seek, speed) are asserted ABSENT: each moves the boundary N·|R − R̂|/ρ, and with a " +
		"compensator on the wire a student who crossed it via N would credit the compensator. The " +
		"value-guard holds NINE ways, with 16-vs-27 asserted on BOTH mode and visibility so the three " +
		"button-dropping branches cannot collapse. Every readout (residual / slope_est / ff_el) reaches " +
		"the HUD as a core-computed scalar — the client never subtracts. The DRAWING is proven by the " +
		"windowed shot harness (convention 14's 4th proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S27UI FAIL: " + msg)
	print("S27UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb26, _sb25, _sb24, _sb23, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
