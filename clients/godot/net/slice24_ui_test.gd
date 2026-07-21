extends SceneTree
# Headless UI test for the slice-24 STEERING CYCLER PATH — the piece slice24_verify.gd can't reach.
# The verifier drives SimClient directly (the set_fidelity wire + the BTT physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT view routing or the steering cycler.
#
# ⭐ THE LOAD-BEARING TOOTH IS THE WITHIN-airframe3d DISCRIMINATOR. Both slice 23 and slice 24 enter the
# 3-D airframe view (_mode=airframe3d, airframe_6dof=true). The NEW split is which fidelity the shared
# button cycles:
#   • airframe_6dof, fidelity HAS `steering`  → the slice-24 STEERING cycler (_fid_kind=steering, 2-ring
#                                               skid_to_turn ↔ bank_to_turn; :airframe HELD :six_dof)
#   • airframe_6dof, NO `steering`            → the slice-23 AIRFRAME cycler (_fid_kind=airframe, 3-ring)
# A careless edit to _enter_airframe3d_mode would collapse these — a slice-24 wire cycling :airframe (the
# HELD key) instead of :steering (the lesson key), the convention-9 "toggle the LESSON's key" trap.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-24 handshake routes to _mode=airframe3d + _fid_kind=STEERING + the button SHOWN
#   2. the cycler is the 2-RING skid_to_turn ↔ bank_to_turn, each press → set_fidelity STEERING
#      (NOT airframe — the held key), and the button label reads "steering: …"
#   3. a slice-23 handshake (airframe_6dof, NO steering) STILL routes to _fid_kind=airframe, 3-ring
#      (the within-airframe3d discriminator — the mirror case, proving a SWITCH not an `or`)
#   4. the off-tree state path builds the trail + reads att_q/bank_deg without crashing
#   5. the value-guard, SIX-way (16 / 17-19 / 18 / 21 / 23 / 24) — the multi-view discriminator
#
# Run:  godot --headless --path clients/godot --script res://net/slice24_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb23
var _sb16
var _sb18
var _sb21

func _initialize() -> void:
	print("S24UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice24_bank_to_turn: airframe_view + airframe_6dof + fidelity carrying `steering`
	# (default bank_to_turn) + :airframe HELD six_dof + guidance/autopilot + the af_tau_roll knob.
	sb._on_scenario({
		"name": "s24_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0,
			 "label": "τ_roll roll time constant"},
		],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: airframe_6dof + steering enters the 3-D view with the STEERING cycler ════════
	if sb._mode != "airframe3d":
		return _fail("a slice-24 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._fid_kind != "steering":
		return _fail("a slice-24 handshake (fidelity has `steering`) must route to _fid_kind=steering (NOT airframe — the HELD key), got %s" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("a slice-24 handshake must SHOW the :steering cycler")
	sb._update_fid_btn()
	if str(sb._prop_btn.text) != "steering: bank_to_turn":
		return _fail("the button must read 'steering: bank_to_turn', got '%s'" % sb._prop_btn.text)
	print("S24UI_ROUTE airframe3d + _fid_kind=steering + button 'steering: bank_to_turn'")

	# ══ TOOTH 2 — the 2-RING steering cycler, each press → set_fidelity STEERING (not airframe) ════════
	# start at bank_to_turn (default) → press → skid_to_turn → press → bank_to_turn
	var seq := ["skid_to_turn", "bank_to_turn"]
	for want in seq:
		mock.sent.clear()
		sb._on_steering_pressed()
		if str(sb._fidelity.get("steering", "")) != want:
			return _fail("the steering cycler must advance to %s, got %s" % [want, str(sb._fidelity.get("steering", ""))])
		# :airframe must NOT move (it is the HELD key — convention 9)
		if str(sb._fidelity.get("airframe", "")) != "six_dof":
			return _fail("cycling steering must NOT touch the HELD :airframe (still six_dof), got %s" % str(sb._fidelity.get("airframe", "")))
		var sent_steering := false
		for d in mock.sent:
			if str(d.get("type", "")) == "set_fidelity" and str(d.get("key", "")) == "steering" and str(d.get("value", "")) == want:
				sent_steering = true
			if str(d.get("key", "")) == "airframe":
				return _fail("cycling steering must NEVER send set_fidelity airframe (that is the held key)")
		if not sent_steering:
			return _fail("cycling to %s must send set_fidelity steering=%s" % [want, want])
	print("S24UI_CYCLE 2-ring skid_to_turn ↔ bank_to_turn (each press → set_fidelity steering; airframe HELD)")

	# ══ TOOTH 3 — MIRROR: a slice-23 handshake (airframe_6dof, NO steering) keeps the AIRFRAME cycler ══
	# This proves _enter_airframe3d_mode is a SWITCH on the `steering` key, not an `or` — the slice-23
	# path must be UNTOUCHED (3-ring airframe cycler, _fid_kind=airframe).
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_ui", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": -5.0, "max": 40.0, "value": 20.0, "label": "C_Yβ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._mode != "airframe3d" or _sb23._fid_kind != "airframe":
		return _fail("a slice-23 handshake (NO steering) must keep _fid_kind=airframe in airframe3d, got kind=%s" % _sb23._fid_kind)
	if _sb23._airframe_rungs.size() != 3 or not _sb23._airframe_rungs.has("six_dof"):
		return _fail("a slice-23 scenario must keep the 3-RING airframe cycler, got %s" % str(_sb23._airframe_rungs))
	print("S24UI_MIRROR slice-23 (no steering) keeps the 3-ring airframe cycler (a SWITCH, not an `or`)")

	# ══ TOOTH 4 — the off-tree state path: build the trail + read att_q/bank_deg without crashing ══════
	sb._telemetry = {
		"m1.los_range": 1500.0, "m1.bank_deg": 62.0, "m1.beta": 0.05,
		"m1.att_qw": 0.90, "m1.att_qx": 0.30, "m1.att_qy": -0.10, "m1.att_qz": 0.28,
	}
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 800.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb (the interceptor's 3-D position)")
	print("S24UI_STATE trail + markers + att_q nose/lift + bank_deg built off-tree (no crash)")

	# ══ TOOTH 5 — THE VALUE-GUARD, SIX-WAY (the multi-view discriminator) ═════════════════════════════
	# (a) slice 16 — airframe_view, NO fidelity → 2-D airframe, button DROPPED
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	# (b) slice 18 — terrain_grid wins the mode discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode (NOT airframe3d), got %s" % _sb18._mode)
	# (c) slice 21 — :atmosphere wins the button over co-shipped :airframe (spatial)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S24UI_GUARD six-way OK — 16 drops / 18 terrain-3-D / 21 atmosphere / 23 airframe3d-3-ring / 24 airframe3d-steering-2-ring")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..23_ui_test contract) --------------------------------------------

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	return sb

func _pass() -> bool:
	print("S24UI OK: a slice-24 handshake (airframe_6dof + a `steering` fidelity) enters the 3-D airframe " +
		"view with the shared button as the 2-RING STEERING cycler (skid_to_turn ↔ bank_to_turn, each press " +
		"→ set_fidelity steering — NOT :airframe, which stays HELD :six_dof; the button reads 'steering: …'). " +
		"The within-airframe3d discriminator holds as a SWITCH: a slice-23 handshake (NO steering) keeps the " +
		"3-RING airframe cycler UNTOUCHED. The multi-view guard holds six ways (16 drops / 18 terrain-3-D / " +
		"21 atmosphere / 23 airframe / 24 steering). The off-tree state path builds the curving trail + reads " +
		"att_q (nose + lift-axis) + bank_deg without crashing. The DRAWING is proven by the windowed shot " +
		"harness (convention 14's fourth proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S24UI FAIL: " + msg)
	print("S24UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb23, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
