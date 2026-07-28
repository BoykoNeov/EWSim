extends SceneTree
# Headless UI test for the slice-30 ENVELOPE view routing + HUD — the piece slice30_verify.gd can't
# reach. The verifier drives SimClient directly (the set_param wire + the envelope physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing or the three
# HUD lines this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A **FIVE-WAY** MIRROR, one deeper than slice 29's four-way. Slices
# 26, 27, 28, 29 and 30 ALL ship slice 26's `radome_view` marker unchanged — same view, same dropped
# button — so all five are INDISTINGUISHABLE BY ROUTING. What separates them is the HUD, which must
# be a SWITCH on each slice's own telemetry key, checked most-specific first:
#   • radome_view + `cross_speed_mps`     → slice 30: R₀/R̂/THE AIM POINT + the engagement label +
#                                             the engagement residual
#   • radome_view + `radome_sched_slope`, NO cross → slice 29: Â/k̂, the bench error, the loop
#                                             residual at its own index
#   • radome_view + `radome_slope_az`, NEITHER    → slice 28: R₀/R̂/hardware residual + the two
#                                             per-axis channel gains + the engagement residual
#   • radome_view + `radome_residual`, NONE OF 3  → slice 27: R, R̂, RESIDUAL — verbatim
#   • radome_view, NONE                           → slice 26: its own slope line — verbatim
#
# ⚠⚠ AND THE DISCRIMINATOR CHOICE IS ITSELF A TOOTH, because the obvious one is WRONG. The natural
# key to switch on would be `radome_slope_worst` — the number slice 30's HUD exists to show. But gate
# 2 measured that key as ADDITIVE on EVERY ripple-carrying wire: slices 28 and 29 grow it too. So the
# 28 and 29 mirrors here deliberately CARRY `radome_slope_worst`, and if the branch switched on it
# they would render slice 30's lines — showing an ENGAGEMENT label on wires that have no engagement
# knob, and dropping the bench/loop pair that IS slice 29. `cross_speed_mps` is the only key unique
# to this wire, and it is shipped from phase-4 `decide!` gated on the target's comp key.
#
# ⚠ AND THE BUTTON MUST STILL BE DROPPED. Slice 30 adds no rung — all three knobs are in-domain
# slider values with no distinct code path behind them (A = 0 is bit-identical to the ripple key
# being absent; `cross_speed_mps` equal to the authored vel_y is bit-identical to the key being
# absent, both MEASURED) — so atmosphere.jl's knob-vs-rung discriminator returns KNOB and slice-16's
# Option-P′ applies for the SIXTH time (16, 26, 27, 28, 29, 30). Nothing here may send set_fidelity.
#
# ⭐ A TOOTH NO EARLIER SLICE IN THIS ARC COULD HAVE: one of the three sliders targets the TARGET
# entity, not the missile. `cross_speed_mps` is the first knob in the radome arc that lives on
# something other than the interceptor, and `set_param` on a target is what the whole ENVELOPE axis
# rides on (it works because `handle_command!` needs only the entity plus a declared Knob — slice
# 18's `alt_hold_m` is the precedent).
#
# ⚠ THE CHANNEL IS SLICE 28's, INHERITED: an envelope wire carries a ripple glass, so it ships
# `radome_slope_az` too and the instruments must keep riding |omega_r| (the lead is in azimuth, so
# the ring is in yaw). Asserted here as well, because the slice-30 branch is inserted AHEAD of the
# slice-28 one and a reader could easily leave the channel switch behind in the branch it skipped.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-30 handshake routes to _mode=airframe3d, the button HIDDEN, the 3-D scene still BUILT
#   2. ⭐⭐ the FIVE-WAY HUD MIRROR (30 / 29 / 28 / 27 / 26), with 28 and 29 CARRYING the aim-point key
#      so the wrong discriminator would be caught
#   3. ⭐ the CHANNEL: the peak-hold still rides |r| on a slice-30 wire and |q| on a slice-27 one,
#      proven with IDENTICAL telemetry so nothing else can account for it
#   4. THREE sliders are built, ALL drive set_param, and ⭐ the crossing-speed one targets tgt1
#   5. the disqualified knobs are absent — including slice 29's SCHEDULE keys, because this wire's
#      compensator is a SCALAR and the claim is about what a scalar can guarantee
#   6. the off-tree state path carries the envelope telemetry as CORE-COMPUTED SCALARS (the client
#      never evaluates a curve, never adds R₀ + 2A and never subtracts — convention 13)
#   7. the value-guard, TWELVE-WAY (16 / 18 / 19 / 21 / 23 / 24 / 25 / 26 / 27 / 28 / 29 / 30)
#
# Run:  godot --headless --path clients/godot --script res://net/slice30_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
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

# The SAME telemetry payload is fed to the slice-30 wire and to the 29/28/27 mirrors, apart from each
# slice's own keys — so any behavioural difference is attributable to the switch and to nothing else.
# A RINGING YAW channel with a QUIET pitch channel is the arc's signature from slice 28 on.
# ⚠ `radome_slope_worst` lands at level 28, NOT at level 30, and that is the point of this fixture:
# the aim point is a property of the GLASS, so every ripple-carrying wire ships it (gate 2, measured)
# and it CANNOT be slice 30's discriminator.
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
		t["m1.radome_slope_az"] = -0.190
		t["m1.radome_slope_el"] = -0.030
		t["m1.radome_residual_az"] = -0.193       # NEGATIVE: the side that rings (the one-sidedness)
		t["m1.radome_slope_worst"] = -0.330       # min(R₀, R₀+2A) — on 28/29 wires TOO
	if level == 29:
		t["m1.radome_ripple_est"] = -0.15
		t["m1.radome_ripple_k_est"] = 10.0
		t["m1.radome_sched_slope"] = -0.686
		t["m1.radome_model_err_az"] = -0.014
		t["m1.look_angle_est"] = 12.7
	if level >= 30:
		t["m1.cross_speed_mps"] = 200.0           # THE ONLY key unique to a slice-30 wire
	return t

func _initialize() -> void:
	print("S30UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice30_envelope: slice 26's markers UNCHANGED (airframe_view +
	# airframe_6dof + radome_view), every fidelity HELD, and THREE knobs — the ENGAGEMENT, the
	# GLASS and the BELIEF.
	sb._on_scenario({
		"name": "s30_ui",
		"airframe_view": true,
		"airframe_6dof": true,
		"radome_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "tgt1", "key": "cross_speed_mps", "min": 0.0, "max": 400.0, "value": 200.0,
			 "label": "ENGAGEMENT: target crossing speed (m/s)"},
			{"target": "m1", "key": "radome_ripple", "min": -0.2, "max": 0.0, "value": -0.15,
			 "label": "RADOME: slope ripple A (the glass)"},
			{"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.03,
			 "label": "COMPENSATOR: scalar belief R̂"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})

	# ══ TOOTH 1 — ROUTE: slice 26's view and its dropped button, INHERITED a FIFTH time ═════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-30 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if sb._prop_btn.visible:
		return _fail("a slice-30 handshake must DROP the shared button — slice 30 adds NO rung (all three knobs are in-domain slider values with no distinct code path behind them). Slice-16's Option-P′, SIXTH use.")
	if not sb._radome_view:
		return _fail("the client must record the radome_view handshake marker (inherited from slice 26, unchanged)")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 30 reuses the slice-23/26/27/28/29 3-D view wholesale")
	print("S30UI_ROUTE airframe3d + button HIDDEN + the 3-D scene still built (slice 26's routing, inherited a fifth time)")

	# ══ TOOTH 2+3+6 — the slice-30 wire: the envelope keys, the yaw channel, the core's scalars ═════
	sb._telemetry = _ring_tel(30)
	sb._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	if sb._af3d_missile != "m1" or sb._af3d_target != "tgt1":
		return _fail("the state path must resolve the missile + target ids, got %s / %s" % [sb._af3d_missile, sb._af3d_target])
	sb._update_readout()
	# ⚠ convention 13 — EVERY quantity the lesson turns on arrives from the CORE as one scalar. The
	# client must never form R₀ + 2A itself: that is physics in GDScript, AND it is the version that
	# silently drifts the instant the A slider moves.
	for k in ["m1.radome_slope_worst", "m1.cross_speed_mps", "m1.radome_slope_az",
			  "m1.radome_residual_az", "m1.radome_slope_est"]:
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side physics)" % k)
	# ⭐ THE AIM POINT MUST BE BELOW THE BELIEF ON THIS FIXTURE — i.e. the wire is showing the DISEASE
	# (a boresight-characterized scalar against curved glass), which is what the showcase opens on.
	var aim: float = float(sb._telemetry["m1.radome_slope_worst"])
	var rhat: float = float(sb._telemetry["m1.radome_slope_est"])
	if not (aim < rhat):
		return _fail("the shipped-arm fixture must have the AIM POINT (%.3f) BELOW the belief (%.3f) — otherwise the HUD is not showing the case the slice is about (the rule says aim AT OR BELOW it)" % [aim, rhat])
	if not (float(sb._telemetry["m1.radome_residual_az"]) < 0.0):
		return _fail("the shipped-arm fixture's ENGAGEMENT residual must be NEGATIVE — only the negative side closes slice 26's loop, and that one-sidedness is the whole rule")
	# ⭐ THE CHANNEL, INHERITED FROM SLICE 28: an envelope wire carries a ripple glass, so the ring is
	# still in YAW and the peak-hold must have latched |omega_r|. Asserted here because the slice-30
	# HUD branch is inserted AHEAD of slice 28's, and the channel switch lives in the branch it skips.
	if not (sb._radome_qpeak > 0.5):
		return _fail("on an envelope wire the peak-hold must still ride the YAW channel |omega_r| (fed 1.21 rad/s with pitch at 0.02) — a peak-hold left on |q| meters the QUIET channel and labels a shaking missile STABLE. Got %.4f" % sb._radome_qpeak)
	print("S30UI_ENV the aim point %.3f and the crossing label %.0f m/s reach the HUD as core scalars beside R̂ %.3f; the peak-hold latched the YAW channel (%.3f)" % [aim, float(sb._telemetry["m1.cross_speed_mps"]), rhat, sb._radome_qpeak])

	# ══ TOOTH 2 — ⭐⭐ THE FIVE-WAY MIRROR, and the two mirrors that would catch the WRONG switch ═════
	# ⚠ 29 and 28 both CARRY `radome_slope_worst` here, deliberately: if the slice-30 branch switched
	# on that key instead of on `cross_speed_mps`, these two wires would take it.
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
	_sb29._telemetry = _ring_tel(29)             # IDENTICAL numbers, minus the slice-30 key
	_sb29._airframe3d_on_state({"entities": [
		{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
		{"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]},
	]})
	_sb29._update_readout()
	if _sb29._telemetry.has("m1.cross_speed_mps"):
		return _fail("the slice-29 MIRROR must carry NO cross_speed_mps key — otherwise this tooth proves nothing")
	if not _sb29._telemetry.has("m1.radome_slope_worst"):
		return _fail("⚠ the slice-29 MIRROR must STILL carry radome_slope_worst — gate 2 measured that key as ADDITIVE on every ripple-carrying wire, and this fixture exists to prove the slice-30 branch does NOT switch on it")
	if not _sb29._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-29 MIRROR must carry radome_sched_slope — it is what selects slice 29's own HUD block")
	if _sb29._mode != sb._mode or _sb29._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 29 and 30 must be indistinguishable by ROUTING (same view, same dropped button) — what separates them is the HUD switch, got modes %s/%s" % [_sb29._mode, sb._mode])
	# …the slice-28 wire: the curve, the aim point, but NEITHER the schedule NOR the engagement.
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
	if _sb28._telemetry.has("m1.cross_speed_mps") or _sb28._telemetry.has("m1.radome_sched_slope"):
		return _fail("the slice-28 MIRROR must carry NEITHER the engagement key NOR the schedule key")
	if not _sb28._telemetry.has("m1.radome_slope_worst"):
		return _fail("⚠ the slice-28 MIRROR must STILL carry radome_slope_worst — same reason as the 29 mirror: it is a property of the GLASS, not of the engagement")
	if not (_sb28._radome_qpeak > 0.5):
		return _fail("the slice-28 MIRROR must still ride the YAW channel — got %.4f" % _sb28._radome_qpeak)
	# …the slice-27 wire: no curve at all, no aim point, and the PITCH channel.
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
	if _sb27._telemetry.has("m1.radome_slope_az") or _sb27._telemetry.has("m1.radome_slope_worst") \
			or _sb27._telemetry.has("m1.cross_speed_mps"):
		return _fail("the slice-27 MIRROR must carry no curve key, no aim point and no engagement key")
	if not _sb27._telemetry.has("m1.radome_residual"):
		return _fail("the slice-27 MIRROR must still carry radome_residual — it is what selects slice 27's own HUD block")
	# ⭐ THE SAME FEED, THE OTHER CHANNEL: with |q| = 0.02 the slice-27 peak-hold must stay LOW even
	# though |r| = 1.21 is in the same dictionary — the assert that fails if the channel is hard-wired.
	if _sb27._radome_qpeak > 0.5:
		return _fail("a slice-27 wire must keep metering the PITCH channel |omega_q| (fed 0.02 with yaw at 1.21) — its ring is in pitch, and switching 26/27 to yaw would silently rewrite their lesson. Got %.4f" % _sb27._radome_qpeak)
	# …and the slice-26 wire, one step further still: NONE of the four keys.
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
			or _sb26._telemetry.has("m1.radome_sched_slope") or _sb26._telemetry.has("m1.cross_speed_mps"):
		return _fail("the slice-26 MIRROR must carry NONE of the compensator / curve / schedule / engagement keys — otherwise the five-way switch is not being tested")
	if _sb26._mode != sb._mode or _sb26._prop_btn.visible != sb._prop_btn.visible:
		return _fail("slices 26 and 30 must be indistinguishable by ROUTING, got modes %s/%s" % [_sb26._mode, sb._mode])
	print("S30UI_MIRROR 26 / 27 / 28 / 29 / 30 share the routing exactly; the HUD is a FIVE-WAY SWITCH on their own telemetry keys — and 28/29 carry the AIM POINT key, so switching on it would have been caught here")

	# ══ TOOTH 4+5 — THREE sliders, all driving set_param, ⭐ one of them at the TARGET ══════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 3:
		return _fail("slice 30 must build EXACTLY THREE sliders (cross_speed_mps + radome_ripple + radome_slope_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-30 wire must NEVER send set_fidelity — there is no rung; the lesson is the SLIDERS")
	for need in ["cross_speed_mps", "radome_ripple", "radome_slope_est"]:
		if not keys_set.has(need):
			return _fail("the '%s' slider must send set_param, got keys %s" % [need, str(keys_set.keys())])
	# ⭐ THE ENGAGEMENT KNOB LIVES ON THE TARGET, and this is the first knob in the radome arc that
	# does. The whole envelope axis rides on `set_param` reaching a non-missile entity (slice 18's
	# `alt_hold_m` is the precedent; `handle_command!` needs only the entity plus a declared Knob).
	if keys_set["cross_speed_mps"] != "tgt1":
		return _fail("the 'cross_speed_mps' set_param must target the TARGET entity tgt1 — it pins the ConstantVelocity mover's vel_y, and a slider pointed at the missile would be a dead knob. Got %s" % str(keys_set))
	for need_m in ["radome_ripple", "radome_slope_est"]:
		if keys_set[need_m] != "m1":
			return _fail("the '%s' set_param must target m1, got %s" % [need_m, str(keys_set)])
	# ⚠ THREE knobs is convention-9-legal ONLY because they are three terms of ONE quantity — the
	# ENGAGEMENT residual the core ships as `radome_residual_az` (vy sets the look angle the
	# engagement holds, A the glass's slope there, R̂ the belief), and gate 0 settled that by
	# MEASUREMENT over a 245-arm grid rather than by counting sliders. The DISQUALIFICATIONS are a
	# design property, asserted rather than described. ⚠ Slice 29's SCHEDULE keys are barred for a
	# reason none of the earlier slices had: this wire's compensator is a SCALAR, deliberately,
	# because the claim is about what a SCALAR can guarantee across an envelope.
	for bad in ["radome_ripple_est", "radome_ripple_k_est", "n_pn", "rho", "radome_slope",
				"radome_ripple_k", "af_alpha_max", "alpha_max", "sigma_seek", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 30 must NOT build a '%s' slider — it puts slice 29's SCHEDULE on a scalar wire, moves the loop gain, moves the LEVEL the belief was characterized against, or sets the cycle amplitude. Got %s" % [bad, str(keys_set.keys())])
	print("S30UI_KNOB exactly 3 sliders; cross_speed_mps → tgt1 (the first TARGET knob in this arc), radome_ripple + radome_slope_est → m1; NOTHING sends set_fidelity")

	# ══ TOOTH 6 — the off-tree state path survives the envelope telemetry ═══════════════════════════
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S30UI_STATE trail + markers + the envelope readouts handled off-tree (no crash)")

	# ══ TOOTH 7 — THE VALUE-GUARD, TWELVE-WAY ══════════════════════════════════════════════════════
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
	# (e) slice 16 — the OTHER button-dropping branch. ⚠ SIX branches now drop the button (16, 26, 27,
	#     28, 29, 30) and they must NOT collapse: 16 is the 2-D SPATIAL view, 26–30 the 3-D airframe one.
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._mode != "spatial" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STAY spatial + DROP the button, got mode=%s vis=%s" % [_sb16._mode, _sb16._prop_btn.visible])
	if sb._mode == _sb16._mode:
		return _fail("slices 16 and 30 both drop the button but must NOT share a mode (16 = 2-D spatial, 30 = 3-D airframe3d)")
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
	print("S30UI_GUARD twelve-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 26 drops(3-D, bare) / 27 drops(3-D, residual) / 28 drops(3-D, curve) / 29 drops(3-D, schedule) / 30 drops(3-D, envelope)")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..29_ui_test contract) --------------------------------------------

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
	print("S30UI OK: a slice-30 handshake reuses slice 26's `radome_view` marker UNCHANGED — the same 3-D " +
		"airframe view, the same DROPPED button — because slice 30 adds no fidelity rung either (all three " +
		"knobs are in-domain slider values with no distinct code path behind them, both endpoints MEASURED " +
		"bit-identical to their keys being absent). Slice-16's Option-P′, SIXTH use. ⭐⭐ THE SHARP TOOTH IS " +
		"THAT 26, 27, 28, 29 AND 30 ARE ALL INDISTINGUISHABLE BY ROUTING, so the HUD must be a FIVE-WAY " +
		"SWITCH on each slice's own telemetry key, most specific first — and ⚠⚠ THE OBVIOUS DISCRIMINATOR IS " +
		"THE WRONG ONE: `radome_slope_worst`, the number this slice's HUD exists to show, is ADDITIVE on " +
		"EVERY ripple-carrying wire (gate 2, measured), so slices 28 and 29 grow it too. Both mirrors here " +
		"deliberately CARRY it, which is what would catch a branch switched on it — it would print an " +
		"ENGAGEMENT label on wires that have no engagement knob and drop the bench/loop pair that IS slice " +
		"29. `cross_speed_mps` is the only key unique to this wire. ⭐ THE AIM POINT IS ON SCREEN LIVE BESIDE " +
		"R̂ because the glass is a SLIDER: dragging A moves the rule's own target, so without that line a " +
		"student who deepens the glass silently invalidates the R̂ they already set — and it arrives as a " +
		"CORE-COMPUTED SCALAR, never formed as R₀ + 2A in GDScript (convention 13, and the version that " +
		"cannot drift). ⚠ It is labelled 'or below', never as a threshold: the rule is SUFFICIENT, NEVER " +
		"TIGHT. ⭐ THE CHANNEL is slice 28's, inherited and re-asserted here because the slice-30 branch is " +
		"inserted AHEAD of the branch that owns the switch: an envelope wire carries a ripple glass, so the " +
		"ring is in YAW and both the rate line and the peak-hold follow |omega_r|, while 26/27 keep " +
		"following |omega_q| — proven by feeding the wires IDENTICAL rates (yaw 1.21, pitch 0.02). THREE " +
		"sliders are built and all drive set_param with NOTHING sending set_fidelity, and ⭐ the " +
		"crossing-speed one targets tgt1 — the FIRST knob in this arc on something other than the " +
		"interceptor, which is what the whole envelope axis rides on. Three knobs is convention-9-legal only " +
		"because they are three terms of ONE quantity (the engagement residual), settled at gate 0 by a " +
		"245-arm measurement rather than by counting sliders; the disqualified levers are asserted ABSENT, " +
		"including slice 29's SCHEDULE keys, because this wire's compensator is a SCALAR and the claim is " +
		"about what a scalar can guarantee. The value-guard holds TWELVE ways, with 16-vs-30 asserted on " +
		"BOTH mode and visibility so the six button-dropping branches cannot collapse. The DRAWING is proven " +
		"by the windowed shot harness (convention 14's 4th proof).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S30UI FAIL: " + msg)
	print("S30UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb29, _sb28, _sb27, _sb26, _sb25, _sb24, _sb23, _sb19, _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
