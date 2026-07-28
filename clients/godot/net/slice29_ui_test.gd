extends SceneTree
# Headless UI test for the slice-29 SCHEDULED-COMPENSATOR view routing + HUD — the piece
# slice29_verify.gd can't reach. The verifier drives SimClient directly (the set_param wire + the
# schedule physics); the Sandbox.tscn smoke-load proves the scene loads. Neither exercises the
# CLIENT routing or the three HUD lines this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A **FOUR-WAY** MIRROR, one deeper than slice 28's three-way. Slices
# 26, 27, 28 and 29 ALL ship slice 26's `radome_view` marker unchanged — same view, same dropped
# button — so all four are INDISTINGUISHABLE BY ROUTING. What separates them is the HUD, which must
# be a SWITCH on each slice's own telemetry key, checked most-specific first:
#   • radome_view + `radome_sched_slope`  → slice 29: Â/k̂, the BENCH error, and the LOOP residual
#                                             with the INDEX PAIR beside it
#   • radome_view + `radome_slope_az`, NO sched_slope → slice 28: R₀/R̂/hardware residual + the two
#                                             per-axis channel gains + the engagement residual
#   • radome_view + `radome_residual`, NEITHER        → slice 27: R, R̂, RESIDUAL — verbatim
#   • radome_view, NONE                               → slice 26: its own slope line — verbatim
# A careless `or`, or a reordering, would print slice 28's lines on a slice-29 wire — which would
# show the ENGAGEMENT residual WITHOUT the bench number beside it, and the whole slice is that those
# two numbers DISAGREE and the loop follows the second. A student shown only one of them cannot see
# the crossover at all; shown only the residual, the k̂ = 17 arm reads as a contradiction.
#
# ⚠ AND THE BUTTON MUST STILL BE DROPPED. Slice 29 adds no rung — `Â = 0` is an in-domain slider
# value AND bit-identical to the schedule key not existing (measured, test_missile.jl) — so the
# knob-vs-rung discriminator returns KNOB and slice-16's Option-P′ applies for the FIFTH time
# (16, 26, 27, 28, 29). Nothing in this wire may ever send set_fidelity.
#
# ⚠ THE CHANNEL IS SLICE 28's, INHERITED: a schedule wire carries a ripple glass, so it ships
# `radome_slope_az` too and the instruments must keep riding |omega_r| (the lead is in azimuth, so
# the ring is in yaw). Asserted here as well, because the slice-29 branch is inserted AHEAD of the
# slice-28 one and a reader could easily leave the channel switch behind in the branch it skipped.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-29 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. ⭐⭐ the FOUR-WAY HUD MIRROR (29 / 28 / 27 / 26), asserted on all four wires
#   3. ⭐ the CHANNEL: the peak-hold still rides |r| on a slice-29 wire (inherited from 28) and |q|
#      on a slice-27 one, proven with IDENTICAL telemetry so nothing else can account for it
#   4. TWO sliders (k̂ and Â) are built and BOTH drive set_param; nothing sends set_fidelity
#   5. the disqualified knobs are absent — including EVERY GLASS key (the thing the belief is being
#      compared against) and slice 28's own `radome_slope_est`, which would quiet this wire without
#      ever touching the schedule
#   6. the off-tree state path carries the schedule telemetry as CORE-COMPUTED SCALARS (the client
#      never evaluates R̂(look), never differentiates it and never subtracts — convention 13)
#   7. the value-guard, ELEVEN-WAY (16 / 18 / 19 / 21 / 23 / 24 / 25 / 26 / 27 / 28 / 29)
#
# Run:  godot --headless --path clients/godot --script res://net/slice29_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb28
var _sb27
var _sb26
var _sb25
var _sb24
var _sb23
var _sb19
var _sb16
var _sb18
var _sb21

# The SAME telemetry payload is fed to the slice-29 wire and to the 28/27 mirrors, apart from each
# slice's own keys — so any behavioural difference is attributable to the switch and to nothing
# else. A RINGING YAW channel with a QUIET pitch channel is the arc's signature from slice 28 on.
# The two error numbers are the SHIPPED arm's: the BENCH error is the SMALLER one and it rings.
func _ring_tel(level: int) -> Dictionary:
	var t := {
		"m1.los_range": 1500.0, "m1.omega_q": 0.02, "m1.omega_r": 1.21,
		"m1.radome_eps": -0.0004, "m1.radome_eps_az": 0.0021, "m1.look_angle": 15.5,
		"m1.omega_ratio": 4.6, "m1.radome_slope": -0.03, "m1.radome_slope_est": -0.03,
		"m1.radome_residual": 0.0, "m1.radome_ff_el": 0.0029, "m1.aero_sat": 1.0,
		"m1.alpha": 0.121,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	if level >= 28:
		t["m1.radome_ripple"] = -0.15
		t["m1.radome_slope_az"] = -0.320
		t["m1.radome_slope_el"] = -0.030
		t["m1.radome_residual_az"] = -0.052
	if level >= 29:
		t["m1.radome_ripple_est"] = -0.15
		t["m1.radome_ripple_k_est"] = 10.0
		t["m1.radome_sched_slope"] = -0.686
		t["m1.radome_model_err_az"] = -0.014      # the BENCH number — the SMALLER of the two
		t["m1.look_angle_est"] = 12.7             # …and the index that makes the loop one bigger
	return t

func _initialize() -> void:
	print("S29UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice29_radome_schedule: slice 26's markers UNCHANGED (airframe_view +
	# airframe_6dof + radome_view), every fidelity HELD, and TWO knobs — k̂ and Â.
	sb._on_scenario({
		"name": "s29_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"radome_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "radome_ripple_k_est", "min": 6.0, "max": 22.0, "value": 10.0,
			 "label": "SCHEDULE: believed ripple frequency k̂"},
			{"target": "m1", "key": "radome_ripple_est", "min": -0.3, "max": 0.0, "value": -0.15,
			 "label": "SCHEDULE: believed ripple amplitude Â"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: slice 26's view and its dropped button, INHERITED a FOURTH time ════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-29 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._prop_btn.visible:
		return _fail("a slice-29 handshake must DROP the shared button — slice 29 adds NO rung (Â = 0 is an in-domain slider value AND bit-identical to the schedule key not existing). Slice-16's Option-P′, FIFTH use.")
	if not sb._radome_view:
		return _fail("the client must record the radome_view handshake marker (inherited from slice 26, unchanged)")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 29 reuses the slice-23/26/27/28 3-D view wholesale")
	print("S29UI_ROUTE airframe3d + button HIDDEN + the 3-D scene still built (slice 26's routing, inherited a fourth time)")

	# ══ TOOTH 2+3+6 — the slice-29 wire: the schedule keys, the yaw channel, the core's scalars ═════
	sb._telemetry = _ring_tel(29)
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	sb._update_readout()
	# ⚠ convention 13 — EVERY quantity the lesson turns on arrives from the CORE as one scalar. If
	# the client evaluated R̂₀ + Â·(1−cos(k̂·look)) itself, or differentiated it, or subtracted it from
	# the glass, that would be physics in GDScript — and here it would be the WRONG physics, because
	# the two error numbers differ ONLY in which look angle each side is evaluated at.
	for k in ["m1.radome_sched_slope", "m1.radome_model_err_az", "m1.radome_residual_az",
			  "m1.radome_ripple_est", "m1.radome_ripple_k_est", "m1.look_angle_est"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side physics)" % k)
	# ⭐ THE TWO NUMBERS MUST BOTH BE PRESENT AND MUST DISAGREE — that IS the slice. A wire carrying
	# only one of them cannot show the crossover, and the HUD block is what puts them side by side.
	var bench: float = float(sb._telemetry["m1.radome_model_err_az"])
	var loopr: float = float(sb._telemetry["m1.radome_residual_az"])
	if absf(loopr) <= absf(bench):
		return _fail("the shipped-arm fixture must have the LOOP residual LARGER than the BENCH error (got %.4f vs %.4f) — otherwise this test is not exercising the case the slice is about" % [loopr, bench])
	if float(sb._telemetry["m1.look_angle"]) <= float(sb._telemetry["m1.look_angle_est"]):
		return _fail("the fixture's compensator index must run BELOW the truth look angle (the bend), got %.1f vs %.1f" % [float(sb._telemetry["m1.look_angle_est"]), float(sb._telemetry["m1.look_angle"])])
	# ⭐ THE CHANNEL, INHERITED FROM SLICE 28: a schedule wire carries a ripple glass, so the ring is
	# still in YAW and the peak-hold must have latched |omega_r|. Asserted here because the slice-29
	# HUD branch is inserted AHEAD of slice 28's, and the channel switch lives in the branch it skips.
	if not (sb._radome_qpeak > 0.5):
		return _fail("on a scheduled wire the peak-hold must still ride the YAW channel |omega_r| (fed 1.21 rad/s with pitch at 0.02) — a peak-hold left on |q| meters the QUIET channel and labels a shaking missile STABLE. Got %.4f" % sb._radome_qpeak)
	print("S29UI_SCHED the schedule keys reach the HUD as core scalars; bench %.3f vs loop %.3f; the peak-hold latched the YAW channel (%.3f)" % [bench, loopr, sb._radome_qpeak])

	# ══ TOOTH 2 — ⭐⭐ THE FOUR-WAY MIRROR: 28 keeps ITS lines, 27 ITS lines AND ITS channel, 26 ITS ══
	_sb28 = _build_sandbox()
	_sb28._on_scenario({
		"name": "s28_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_ripple", "min": -0.1, "max": 0.0, "value": -0.05,
				   "label": "RADOME: slope ripple A"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.15, "max": 0.0, "value": -0.03,
				   "label": "COMPENSATOR: slope estimate R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	_sb28._telemetry = _ring_tel(28)             # IDENTICAL numbers, minus the slice-29 keys
	_sb28._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb28._update_readout()
	if _sb28._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-28 MIRROR must carry NO radome_sched_slope key — otherwise this tooth proves nothing")
	if not _sb28._telemetry.has("m1.radome_slope_az"):
		return _fail("the slice-28 MIRROR must still carry radome_slope_az — it is what selects slice 28's own HUD block")
	if _sb28._telemetry.has("m1.radome_model_err_az"):
		return _fail("the slice-28 MIRROR must carry NO radome_model_err_az — a 26/27/28 wire has a CONSTANT belief, for which the bench and loop numbers are the same number and the key would be meaningless")
	if not (_sb28._radome_qpeak > 0.5):
		return _fail("the slice-28 MIRROR must still ride the YAW channel — got %.4f" % _sb28._radome_qpeak)
	if _sb28._mode != sb._mode or _sb28._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 28 and 29 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD switch, got modes %s/%s" % [_sb28._mode, sb._mode])
	# …the slice-27 wire, one step further out: NO curve key either, and the PITCH channel.
	_sb27 = _build_sandbox()
	_sb27._on_scenario({
		"name": "s27_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_slope_est", "min": -0.15, "max": 0.0, "value": 0.0,
				   "label": "COMPENSATOR: slope estimate R̂"},
				  {"target": "m1", "key": "radome_slope", "min": -0.2, "max": 0.0, "value": -0.10,
				   "label": "RADOME: true error slope R"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	_sb27._telemetry = _ring_tel(27)
	_sb27._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb27._update_readout()
	if _sb27._telemetry.has("m1.radome_slope_az") or _sb27._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-27 MIRROR must carry NEITHER the curve key NOR the schedule key")
	if not _sb27._telemetry.has("m1.radome_residual"):
		return _fail("the slice-27 MIRROR must still carry radome_residual — it is what selects slice 27's own HUD block")
	# ⭐ THE SAME FEED, THE OTHER CHANNEL: with |q| = 0.02 the slice-27 peak-hold must stay LOW even
	# though |r| = 1.21 is in the same dictionary — the assert that fails if the channel is hard-wired.
	if _sb27._radome_qpeak > 0.5:
		return _fail("a slice-27 wire must keep metering the PITCH channel |omega_q| (fed 0.02 with yaw at 1.21) — its ring is in pitch, and switching 26/27 to yaw would silently rewrite their lesson. Got %.4f" % _sb27._radome_qpeak)
	# …and the slice-26 wire, one step further still: NONE of the three keys.
	_sb26 = _build_sandbox()
	_sb26._on_scenario({
		"name": "s26_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_slope", "min": -0.12, "max": 0.06, "value": -0.10,
				   "label": "radome error slope R"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	var t26 := _ring_tel(27)
	t26.erase("m1.radome_residual")
	t26.erase("m1.radome_slope_est")
	t26.erase("m1.radome_ff_el")
	t26["m1.omega_q"] = -1.31
	_sb26._telemetry = t26
	_sb26._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb26._update_readout()
	if _sb26._telemetry.has("m1.radome_residual") or _sb26._telemetry.has("m1.radome_slope_az") \
			or _sb26._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-26 MIRROR must carry NONE of the compensator / curve / schedule keys — otherwise the four-way switch is not being tested")
	if _sb26._mode != sb._mode or _sb26._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 26 and 29 must be indistinguishable by ROUTING, got modes %s/%s" % [_sb26._mode, sb._mode])
	print("S29UI_MIRROR 26 / 27 / 28 / 29 share the routing exactly; the HUD is a FOUR-WAY SWITCH on their own telemetry keys, asserted on all four")

	# ══ TOOTH 4+5 — TWO sliders, both driving set_param; nothing sends set_fidelity ═════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("slice 29 must build EXACTLY TWO sliders (radome_ripple_k_est + radome_ripple_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-29 wire must NEVER send set_fidelity — there is no rung; the lesson is the SLIDERS")
	for need in ["radome_ripple_k_est", "radome_ripple_est"]:
		if not keys_set.has(need):
			return _fail("the '%s' slider must send set_param, got keys %s" % [need, str(keys_set.keys())])
		if keys_set[need] != "m1":
			return _fail("the '%s' set_param must target m1, got %s" % [need, str(keys_set)])
	# ⚠ TWO knobs is convention-9-legal ONLY because they are the two halves of ONE object — the
	# compensator's BELIEF about the curve, its LEVEL and its SHAPE. The DISQUALIFICATIONS are a
	# design property, asserted rather than described. ⚠ THE GLASS KEYS are disqualified for a reason
	# none of the earlier slices had: they are the thing the belief is being COMPARED AGAINST, and a
	# student who can move both has no comparison left. ⚠ And `radome_slope_est` is slice 28's knob —
	# it would quiet this wire without ever touching the schedule, which is the whole subject.
	for bad in ["n_pn", "rho", "radome_slope", "radome_ripple", "radome_ripple_k",
				"radome_slope_est", "af_alpha_max", "alpha_max", "sigma_seek", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 29 must NOT build a '%s' slider — it moves the loop gain, the cycle amplitude, the GLASS the belief is compared against, or (for radome_slope_est) it cures the wire without touching the SCHEDULE. Got %s" % [bad, str(keys_set.keys())])
	print("S29UI_KNOB exactly 2 sliders (radome_ripple_k_est + radome_ripple_est → m1); NOTHING sends set_fidelity")

	# ══ TOOTH 6 — the off-tree state path survives the schedule telemetry ═══════════════════════════
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S29UI_STATE trail + markers + the schedule readouts handled off-tree (no crash)")

	# ══ TOOTH 7 — THE VALUE-GUARD, ELEVEN-WAY ══════════════════════════════════════════════════════
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
	# (d) slice 19 — the 2-D SPATIAL airframe cycler with only TWO rungs
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.0, "label": "ρ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or _sb19._airframe_rungs.size() != 2:
		return _fail("a slice-19 handshake must stay 2-D spatial with a TWO-ring airframe cycler, got mode=%s kind=%s rungs=%s" % [_sb19._mode, _sb19._fid_kind, str(_sb19._airframe_rungs)])
	# (e) slice 16 — the OTHER button-dropping branch. ⚠ FIVE branches now drop the button (16, 26,
	#     27, 28, 29) and they must NOT collapse: 16 is the 2-D SPATIAL view, 26–29 the 3-D airframe one.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slices 16 and 29 both drop the button but must NOT share a mode (16 = 2-D spatial, 29 = 3-D airframe3d)")
	# (f) slice 18 — terrain_grid wins the MODE discriminator (a DIFFERENT 3-D view)
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (g) slice 21 — :atmosphere still wins the button over a co-shipped :airframe (spatial, 2-D)
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S29UI_GUARD eleven-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D, bare) / 27 drops(3-D, residual) / 28 drops(3-D, curve) / 29 drops(3-D, schedule)")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..28_ui_test contract) --------------------------------------------

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
	print("S29UI OK: a slice-29 handshake reuses slice 26's `radome_view` marker UNCHANGED — the same 3-D " +
		"airframe view, the same DROPPED button — because slice 29 adds no fidelity rung either (Â = 0 is " +
		"an in-domain slider value AND bit-identical to the schedule key not existing). Slice-16's " +
		"Option-P′, FIFTH use. ⭐⭐ THE SHARP TOOTH IS THAT 26, 27, 28 AND 29 ARE ALL INDISTINGUISHABLE BY " +
		"ROUTING, so the HUD must be a FOUR-WAY SWITCH on each slice's own telemetry key, most specific " +
		"first — asserted on all four wires, because a careless `or` would print slice 28's lines on a " +
		"slice-29 wire and show the LOOP residual with NO BENCH NUMBER BESIDE IT. That is not cosmetic: the " +
		"whole slice is that those two numbers DISAGREE and the ring follows the second, so a student shown " +
		"only one of them reads the quiet-but-worse-model arm as a contradiction rather than a mechanism. " +
		"The INDEX PAIR (truth look angle vs the compensator's own) is on screen for the same reason — it " +
		"is what makes the disagreement a mechanism. ⭐ THE CHANNEL is slice 28's, inherited and re-asserted " +
		"here because the slice-29 branch is inserted AHEAD of the branch that owns the switch: a scheduled " +
		"wire carries a ripple glass, so the ring is still in YAW and both the rate line and the peak-hold " +
		"follow |omega_r|, while 26/27 keep following |omega_q| — proven by feeding the wires the IDENTICAL " +
		"rates (yaw 1.21, pitch 0.02). TWO sliders are built and both drive set_param, with NOTHING sending " +
		"set_fidelity — and two knobs is convention-9-legal only because they are the two halves of ONE " +
		"object, the compensator's BELIEF about the curve (its LEVEL and its SHAPE). The disqualified levers " +
		"are asserted ABSENT, and this slice adds a class the earlier ones did not have: EVERY GLASS KEY " +
		"(radome_slope / radome_ripple / radome_ripple_k) is barred because it is the thing the belief is " +
		"COMPARED AGAINST, and slice 28's radome_slope_est is barred because it would quiet this wire " +
		"without ever touching the schedule. The value-guard holds ELEVEN ways, with 16-vs-29 asserted on " +
		"BOTH mode and visibility so the five button-dropping branches cannot collapse. Every readout " +
		"(both error numbers, the sensitivity, the two knob values, both look angles) reaches the HUD as a " +
		"core-computed scalar — the client never evaluates the schedule, never differentiates it and never " +
		"subtracts. The DRAWING is proven by the windowed shot harness (convention 14's 4th proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S29UI FAIL: " + msg)
	print("S29UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb28, _sb27, _sb26, _sb25, _sb24, _sb23, _sb19, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
