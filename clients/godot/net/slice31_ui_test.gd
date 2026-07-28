extends SceneTree
# Headless UI test for the slice-31 IMPERFECT-GYRO view routing + HUD — the piece slice31_verify.gd
# can't reach. The verifier drives SimClient directly (the set_param wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing or the four
# HUD lines this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A **SIX-WAY** MIRROR, one deeper than slice 30's five-way. Slices 26,
# 27, 28, 29, 30 and 31 ALL ship slice 26's `radome_view` marker unchanged — same view, same dropped
# button — so all six are INDISTINGUISHABLE BY ROUTING. What separates them is the HUD, which must be
# a SWITCH on each slice's own telemetry key, checked most-specific first:
#   • radome_view + `gyro_scale_err`      → slice 31: R̂ ×(1+s) → the belief THE LOOP SEES, the
#                                             re-aimed point R_worst/(1+s), the effective residual,
#                                             and the bias injection
#   • radome_view + `cross_speed_mps`, NO gyro    → slice 30: R₀/R̂/the aim point + the engagement
#   • radome_view + `radome_sched_slope`, NEITHER → slice 29: Â/k̂, the bench error, the loop residual
#   • radome_view + `radome_slope_az`, NONE OF 3  → slice 28: the two per-axis channel gains
#   • radome_view + `radome_residual`, NONE OF 4  → slice 27: R, R̂, RESIDUAL — verbatim
#   • radome_view, NONE                           → slice 26: its own slope line — verbatim
#
# ⚠⚠ AND THE DISCRIMINATOR CHOICE IS A TOOTH AGAIN, for the same reason it was in slice 30: the
# NATURAL key to switch on would be `radome_slope_est_eff` or `radome_aim_gyro` — the numbers this
# HUD exists to show — but both are shipped from the same gate as `gyro_scale_err`, so they are
# equivalent HERE and would silently stop being so if a later slice ever ships an effective belief
# without a scale factor. The gyro key is the one that names the SENSOR, which is what this slice is
# about. The slice-30 mirror below deliberately carries `radome_slope_worst` AND `cross_speed_mps`,
# so a branch that switched on the aim point would render slice 31's lines on an envelope wire.
#
# ⚠ AND THE BUTTON MUST STILL BE DROPPED. Slice 31 adds no rung — both gyro terms are in-domain
# slider values whose off-state (0.0) is BIT-IDENTICAL to the key being absent (measured in
# `test_missile.jl`) — so atmosphere.jl's knob-vs-rung discriminator returns KNOB and slice-16's
# Option-P′ applies for the SEVENTH time (16, 26, 27, 28, 29, 30, 31). Nothing here may send
# set_fidelity.
#
# ⭐ THE TOOTH THIS SLICE ADDS THAT NO EARLIER ONE COULD: the HUD must show TWO BELIEFS — the one the
# student set and the one the LOOP SEES — and they must DISAGREE on the fixture. A HUD that showed
# only `radome_slope_est` would let a student drag a slider to the aim point, read the number they
# typed, and watch it ring anyway with nothing on screen to explain it. The fixture therefore carries
# `radome_slope_est` = −0.27 with an effective belief of −0.2565, and asserts the gap.
#
# ⚠ AND SLICE 28's KEY IS NOT REDEFINED (advisor): `radome_residual_az` keeps its meaning and the
# gyro-effective residual ships ALONGSIDE it. The fixture carries BOTH and asserts they DISAGREE —
# two numbers from the same frames that disagree is this arc's own shape (28's hardware-vs-engagement
# pair, 29's bench-vs-loop pair), and a client that read the wrong one would label a ringing missile
# safe.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-31 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. ⭐⭐ the SIX-WAY HUD MIRROR (31 / 30 / 29 / 28 / 27 / 26), with the 30 mirror CARRYING the
#      aim-point key so the wrong discriminator would be caught
#   3. ⭐ TWO BELIEFS on screen and they DISAGREE; ⚠ and BOTH residuals ship, also disagreeing
#   4. ⭐ the CHANNEL: the peak-hold still rides |r| on a slice-31 wire and |q| on a slice-27 one,
#      proven with IDENTICAL telemetry so nothing else can account for it
#   5. THREE sliders are built, ALL drive set_param, ALL target the interceptor
#   6. the disqualified knobs are absent — including slice 30's ENGAGEMENT axis (convention 9) and
#      `gyro_bias_y` (the ELEVATION channel, ~10x smaller on a crossing wire)
#   7. the off-tree state path carries the gyro telemetry as CORE-COMPUTED SCALARS (the client never
#      multiplies R̂ by (1+s) — convention 13)
#   8. the value-guard, THIRTEEN-WAY (16 / 18 / 19 / 21 / 23 / 24 / 25 / 26 / 27 / 28 / 29 / 30 / 31)
#
# Run:  godot --headless --path clients/godot --script res://net/slice31_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb30
var _sb29
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

# The SAME telemetry payload is fed to the slice-31 wire and to the 30/29/28/27 mirrors, apart from
# each slice's own keys — so any behavioural difference is attributable to the switch and to nothing
# else. A RINGING YAW channel with a QUIET pitch channel is the arc's signature from slice 28 on.
# ⚠ `radome_slope_worst` lands at level 28 (a property of the GLASS — gate 2 of slice 30 measured it
# ADDITIVE on every ripple-carrying wire) and `cross_speed_mps` at level 30, so neither can be slice
# 31's discriminator.
func _ring_tel(level: int) -> Dictionary:
	var t := {
		"m1.los_range": 1500.0, "m1.omega_q": 0.02, "m1.omega_r": 1.21,
		"m1.radome_eps": -0.0004, "m1.radome_eps_az": 0.0021, "m1.look_angle": 13.6,
		"m1.omega_ratio": 4.6, "m1.radome_slope": -0.03, "m1.radome_slope_est": -0.27,
		"m1.radome_residual": 0.24, "m1.radome_ff_el": 0.0029, "m1.aero_sat": 1.0,
		"m1.alpha": 0.121,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}
	if level >= 28:
		t["m1.radome_ripple"] = -0.15
		t["m1.radome_slope_az"] = -0.322
		t["m1.radome_slope_el"] = -0.030
		t["m1.radome_residual_az"] = -0.052       # R(look_az) − R̂, slice 28's key, MEANING UNCHANGED
		t["m1.radome_slope_worst"] = -0.330       # min(R₀, R₀+2A) — on 28/29/30/31 wires TOO
	if level == 29:
		t["m1.radome_ripple_est"] = -0.15
		t["m1.radome_ripple_k_est"] = 10.0
		t["m1.radome_sched_slope"] = -0.686
		t["m1.radome_model_err_az"] = -0.014
		t["m1.look_angle_est"] = 12.7
	if level == 30:
		t["m1.cross_speed_mps"] = 200.0           # the key unique to a slice-30 wire
	if level >= 31:
		t["m1.gyro_scale_err"] = -0.05            # ⭐ THE DISCRIMINATOR: the SENSOR's own key
		t["m1.gyro_bias_z"] = 0.02
		t["m1.radome_slope_est_eff"] = -0.2565    # ⭐ R̂(1+s) — the belief THE LOOP SEES
		t["m1.radome_aim_gyro"] = -0.3474         # R_worst/(1+s) — the rule, re-aimed for the sensor
		t["m1.radome_residual_az_eff"] = -0.0655  # …and the residual read against it
		t["m1.gyro_inject_az"] = -0.0054          # R̂·b — the OTHER currency
	return t

func _initialize() -> void:
	print("S31UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice31_gyro: slice 26's markers UNCHANGED (airframe_view + airframe_6dof +
	# radome_view), every fidelity HELD, and THREE knobs — the SENSOR's two error terms and the
	# BELIEF they multiply.
	sb._on_scenario({
		"name": "s31_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"radome_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05,
			 "label": "GYRO: scale-factor error s — CURE A"},
			{"target": "m1", "key": "gyro_bias_z", "min": -0.08, "max": 0.08, "value": 0.0,
			 "label": "GYRO: yaw-rate bias b (rad/s) — the OTHER currency"},
			{"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27,
			 "label": "COMPENSATOR: belief R̂ — CURE B"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: slice 26's view and its dropped button, INHERITED a SIXTH time ═════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-31 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._prop_btn.visible:
		return _fail("a slice-31 handshake must DROP the shared button — slice 31 adds NO rung (both gyro terms are in-domain slider values whose off-state 0.0 is BIT-IDENTICAL to the key being absent, measured). Slice-16's Option-P′, SEVENTH use.")
	if not sb._radome_view:
		return _fail("the client must record the radome_view handshake marker (inherited from slice 26, unchanged)")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 31 reuses the slice-23/26/27/28/29/30 3-D view wholesale")
	print("S31UI_ROUTE airframe3d + button HIDDEN + the 3-D scene still built (slice 26's routing, inherited a sixth time)")

	# ══ TOOTH 3+4+7 — the slice-31 wire: TWO beliefs, TWO residuals, the yaw channel ════════════════
	sb._telemetry = _ring_tel(31)
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	sb._update_readout()
	# ⚠ convention 13 — EVERY quantity the lesson turns on arrives from the CORE as one scalar. The
	# client must never form R̂*(1+s) or R_worst/(1+s) itself: that is physics in GDScript, AND it is
	# the version that silently drifts the instant either slider moves.
	for k in ["m1.gyro_scale_err", "m1.gyro_bias_z", "m1.radome_slope_est_eff",
			  "m1.radome_aim_gyro", "m1.radome_residual_az_eff", "m1.gyro_inject_az",
			  "m1.radome_slope_est", "m1.radome_residual_az"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side physics)" % k)
	# ⭐ TWO BELIEFS, AND THEY MUST DISAGREE — the whole reason this slice is not zero client code.
	var rhat: float = float(sb._telemetry["m1.radome_slope_est"])
	var eff: float = float(sb._telemetry["m1.radome_slope_est_eff"])
	if not (absf(eff - rhat) > 1.0e-6 and eff > rhat):
		return _fail("the fixture must carry an EFFECTIVE belief (%.4f) that DISAGREES with the authored one (%.4f) and sits on the RINGING side (less negative) — a HUD showing only the slider would let a student read back the number they typed while the loop flies a different one" % [eff, rhat])
	# ⚠ AND SLICE 28's RESIDUAL KEEPS ITS MEANING: both ship, and they disagree by the belief rescale.
	if not (absf(float(sb._telemetry["m1.radome_residual_az_eff"]) - float(sb._telemetry["m1.radome_residual_az"])) > 1.0e-6):
		return _fail("both residuals must ship and DISAGREE — slice 28's `radome_residual_az` keeps its meaning (its own headline is that the hardware residual reads 0.000 while the missile rings) and the gyro-effective one ships ALONGSIDE it")
	# ⭐ THE RE-AIMED POINT MUST BE BELOW THE PLAIN ONE: the gyro spec pushes the design deeper.
	if not (float(sb._telemetry["m1.radome_aim_gyro"]) < float(sb._telemetry["m1.radome_slope_worst"])):
		return _fail("with an UNDER-reading gyro the re-aimed point R_worst/(1+s) (%.4f) must sit BELOW slice 30's R_worst (%.4f) — that deepening IS the gyro budget being spent" % [float(sb._telemetry["m1.radome_aim_gyro"]), float(sb._telemetry["m1.radome_slope_worst"])])
	# ⭐ THE CHANNEL, INHERITED FROM SLICE 28: a gyro wire carries a ripple glass, so the ring is still
	# in YAW and the peak-hold must have latched |omega_r|. Asserted here because the slice-31 HUD
	# branch is inserted AHEAD of slice 28's, and the channel switch lives in the branch it skips.
	if not (sb._radome_qpeak > 0.5):
		return _fail("on a gyro wire the peak-hold must still ride the YAW channel |omega_r| (fed 1.21 rad/s with pitch at 0.02) — a peak-hold left on |q| meters the QUIET channel and labels a shaking missile STABLE. Got %.4f" % sb._radome_qpeak)
	print("S31UI_GYRO the loop's belief %.4f (against the authored %.4f), the re-aimed point %.4f (below R_worst %.4f) and the injection %.5f all reach the HUD as core scalars; the peak-hold latched the YAW channel (%.3f)" % [eff, rhat, float(sb._telemetry["m1.radome_aim_gyro"]), float(sb._telemetry["m1.radome_slope_worst"]), float(sb._telemetry["m1.gyro_inject_az"]), sb._radome_qpeak])

	# ══ TOOTH 2 — ⭐⭐ THE SIX-WAY MIRROR, and the mirror that would catch the WRONG switch ═══════════
	# ⚠ the slice-30 mirror CARRIES `radome_slope_worst` (and the engagement key) deliberately: if the
	# slice-31 branch switched on the aim point instead of on the gyro key, this wire would take it.
	_sb30 = _build_sandbox()
	_sb30._on_scenario({
		"name": "s30_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "tgt1", "key": "cross_speed_mps", "min": 0.0, "max": 400.0, "value": 200.0,
				   "label": "ENGAGEMENT: target crossing speed"},
				  {"target": "m1", "key": "radome_ripple", "min": -0.2, "max": 0.0, "value": -0.15,
				   "label": "RADOME: slope ripple A"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.03,
				   "label": "COMPENSATOR: scalar belief R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	_sb30._telemetry = _ring_tel(30)             # IDENTICAL numbers, minus the slice-31 keys
	_sb30._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb30._update_readout()
	if _sb30._telemetry.has("m1.gyro_scale_err"):
		return _fail("the slice-30 MIRROR must carry NO gyro key — otherwise this tooth proves nothing")
	if not (_sb30._telemetry.has("m1.radome_slope_worst") and _sb30._telemetry.has("m1.cross_speed_mps")):
		return _fail("⚠ the slice-30 MIRROR must STILL carry radome_slope_worst AND cross_speed_mps — this fixture exists to prove the slice-31 branch does NOT switch on the aim point")
	if _sb30._mode != sb._mode or _sb30._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 30 and 31 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD switch, got modes %s/%s" % [_sb30._mode, sb._mode])
	# …the slice-29 wire: the schedule, but no engagement and no gyro.
	_sb29 = _build_sandbox()
	_sb29._on_scenario({
		"name": "s29_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "radome_ripple_k_est", "min": 6.0, "max": 22.0, "value": 10.0,
				   "label": "SCHEDULE: believed ripple frequency k̂"},
				  {"target": "m1", "key": "radome_ripple_est", "min": -0.3, "max": 0.0, "value": -0.15,
				   "label": "SCHEDULE: believed ripple amplitude Â"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	_sb29._telemetry = _ring_tel(29)
	_sb29._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb29._update_readout()
	if _sb29._telemetry.has("m1.gyro_scale_err") or _sb29._telemetry.has("m1.cross_speed_mps"):
		return _fail("the slice-29 MIRROR must carry neither the gyro keys nor the engagement key")
	if not _sb29._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-29 MIRROR must carry radome_sched_slope — it is what selects slice 29's own HUD block")
	# …the slice-28 wire: the curve and the aim point, none of the three later keys.
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
	_sb28._telemetry = _ring_tel(28)
	_sb28._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb28._update_readout()
	if _sb28._telemetry.has("m1.gyro_scale_err") or _sb28._telemetry.has("m1.cross_speed_mps") \
			or _sb28._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-28 MIRROR must carry none of the gyro / engagement / schedule keys")
	if not (_sb28._radome_qpeak > 0.5):
		return _fail("the slice-28 MIRROR must still ride the YAW channel — got %.4f" % _sb28._radome_qpeak)
	# …the slice-27 wire: no curve at all, and the PITCH channel.
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
	if _sb27._telemetry.has("m1.radome_slope_az") or _sb27._telemetry.has("m1.gyro_scale_err"):
		return _fail("the slice-27 MIRROR must carry no curve key and no gyro key")
	if not _sb27._telemetry.has("m1.radome_residual"):
		return _fail("the slice-27 MIRROR must still carry radome_residual — it is what selects slice 27's own HUD block")
	# ⭐ THE SAME FEED, THE OTHER CHANNEL: with |q| = 0.02 the slice-27 peak-hold must stay LOW even
	# though |r| = 1.21 is in the same dictionary — the assert that fails if the channel is hard-wired.
	if _sb27._radome_qpeak > 0.5:
		return _fail("a slice-27 wire must keep metering the PITCH channel |omega_q| (fed 0.02 with yaw at 1.21) — its ring is in pitch, and switching 26/27 to yaw would silently rewrite their lesson. Got %.4f" % _sb27._radome_qpeak)
	# …and the slice-26 wire, one step further still: NONE of the five keys.
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
			or _sb26._telemetry.has("m1.radome_sched_slope") or _sb26._telemetry.has("m1.cross_speed_mps") \
			or _sb26._telemetry.has("m1.gyro_scale_err"):
		return _fail("the slice-26 MIRROR must carry NONE of the compensator / curve / schedule / engagement / gyro keys — otherwise the six-way switch is not being tested")
	if _sb26._mode != sb._mode or _sb26._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 26 and 31 must be indistinguishable by ROUTING, got modes %s/%s" % [_sb26._mode, sb._mode])
	print("S31UI_MIRROR 26 / 27 / 28 / 29 / 30 / 31 share the routing exactly; the HUD is a SIX-WAY SWITCH on their own telemetry keys — and the 30 mirror carries BOTH the aim point and the engagement key, so switching on either would have been caught here")

	# ══ TOOTH 5+6 — THREE sliders, all driving set_param, all at the interceptor ════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 3:
		return _fail("slice 31 must build EXACTLY THREE sliders (gyro_scale_err + gyro_bias_z + radome_slope_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-31 wire must NEVER send set_fidelity — there is no rung; the lesson is the SLIDERS")
	for need in ["gyro_scale_err", "gyro_bias_z", "radome_slope_est"]:
		if not keys_set.has(need):
			return _fail("the '%s' slider must send set_param, got keys %s" % [need, str(keys_set.keys())])
		if keys_set[need] != "m1":
			return _fail("the '%s' set_param must target the interceptor m1, got %s" % [need, str(keys_set)])
	# ⚠ THREE knobs is convention-9-legal ONLY because they are three terms of ONE quantity — and here
	# they literally are: the three terms of the product the compensator subtracts, R̂*((1+s)*ω + b).
	# The DISQUALIFICATIONS are a design property, asserted rather than described. ⚠ `cross_speed_mps`
	# is barred for a reason no earlier slice had: slice 30's ENGAGEMENT axis is a SECOND lesson, and
	# stacking it here would break convention 9 outright.
	for bad in ["cross_speed_mps", "radome_ripple", "gyro_bias_y", "radome_ripple_est",
				"radome_ripple_k_est", "n_pn", "rho", "radome_slope", "radome_ripple_k",
				"af_alpha_max", "alpha_max", "sigma_seek", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 31 must NOT build a '%s' slider — it stacks slice 30's ENGAGEMENT axis (convention 9), moves the glass under the comparison, drives the ELEVATION channel, puts slice 29's SCHEDULE on a scalar wire, moves the loop gain, or sets the cycle amplitude. Got %s" % [bad, str(keys_set.keys())])
	print("S31UI_KNOB exactly 3 sliders — gyro_scale_err + gyro_bias_z + radome_slope_est, ALL → m1; NOTHING sends set_fidelity")

	# ══ TOOTH 7 — the off-tree state path survives the gyro telemetry ═══════════════════════════════
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S31UI_STATE trail + markers + the gyro readouts handled off-tree (no crash)")

	# ══ TOOTH 8 — THE VALUE-GUARD, THIRTEEN-WAY ════════════════════════════════════════════════════
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
	# (e) slice 16 — the OTHER button-dropping branch. ⚠ SEVEN branches now drop the button (16, 26,
	#     27, 28, 29, 30, 31) and they must NOT collapse: 16 is the 2-D SPATIAL view, 26–31 the 3-D one.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slices 16 and 31 both drop the button but must NOT share a mode (16 = 2-D spatial, 31 = 3-D airframe3d)")
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
	print("S31UI_GUARD thirteen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D, bare) / 27 drops(3-D, residual) / 28 drops(3-D, curve) / 29 drops(3-D, schedule) / 30 drops(3-D, envelope) / 31 drops(3-D, gyro)")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..30_ui_test contract) --------------------------------------------

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
	print("S31UI OK: a slice-31 handshake reuses slice 26's `radome_view` marker UNCHANGED — the same 3-D " +
		"airframe view, the same DROPPED button — because slice 31 adds no fidelity rung either (both gyro " +
		"error terms are in-domain slider values whose off-state 0.0 is BIT-IDENTICAL to the key being " +
		"absent, MEASURED in test_missile.jl). Slice-16's Option-P′, SEVENTH use. ⭐⭐ THE SHARP TOOTH IS " +
		"THAT 26, 27, 28, 29, 30 AND 31 ARE ALL INDISTINGUISHABLE BY ROUTING, so the HUD must be a SIX-WAY " +
		"SWITCH on each slice's own telemetry key, most specific first — and ⚠⚠ THE OBVIOUS DISCRIMINATORS " +
		"ARE THE WRONG ONES AGAIN: `radome_slope_worst` is ADDITIVE on every ripple-carrying wire and " +
		"`cross_speed_mps` belongs to slice 30, so the 30 mirror here deliberately carries BOTH — a branch " +
		"switched on either would render an EFFECTIVE-BELIEF line on a wire that has no gyro. ⭐ THE LINE " +
		"THIS SLICE EXISTS FOR IS THE SECOND BELIEF: the HUD shows the R̂ the student set AND the R̂(1+s) " +
		"THE LOOP SEES, and the fixture asserts they DISAGREE and that the effective one sits on the " +
		"RINGING side — without it a student drags a slider to the aim point, reads back the number they " +
		"typed, and watches it ring with nothing on screen to explain it. ⚠ AND SLICE 28's " +
		"`radome_residual_az` IS NOT REDEFINED: the gyro-effective residual ships ALONGSIDE it and the two " +
		"DISAGREE on the fixture — two numbers from the same frames that disagree is this arc's own shape. " +
		"⭐ The re-aimed point R_worst/(1+s) sits BELOW slice 30's R_worst, which is the gyro budget being " +
		"spent, and every one of these numbers arrives as a CORE-COMPUTED SCALAR — the client never " +
		"multiplies R̂ by (1+s) (convention 13, and the version that cannot drift when either slider moves). " +
		"⭐ THE CHANNEL is slice 28's, inherited and re-asserted because the slice-31 branch is inserted " +
		"AHEAD of the branch that owns the switch: a gyro wire carries a ripple glass, so the ring is in " +
		"YAW and the peak-hold follows |omega_r|, while 26/27 keep following |omega_q| — proven by feeding " +
		"the wires IDENTICAL rates (yaw 1.21, pitch 0.02). THREE sliders are built, ALL drive set_param at " +
		"the interceptor, and NOTHING sends set_fidelity. Three knobs is convention-9-legal only because " +
		"they are literally the three terms of the product the compensator subtracts, R̂*((1+s)*ω + b); the " +
		"disqualified levers are asserted ABSENT, including slice 30's ENGAGEMENT axis (a second lesson) " +
		"and `gyro_bias_y` (the ELEVATION channel, ~10x smaller on a crossing wire). The value-guard holds " +
		"THIRTEEN ways, with 16-vs-31 asserted on BOTH mode and visibility so the seven button-dropping " +
		"branches cannot collapse. The DRAWING is proven by the windowed shot harness (convention 14's 4th " +
		"proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S31UI FAIL: " + msg)
	print("S31UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb30, _sb29, _sb28, _sb27, _sb26, _sb25, _sb24, _sb23, _sb19, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
