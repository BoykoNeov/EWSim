extends SceneTree
# Headless UI test for the slice-34 GIMBAL view routing + HUD — the piece slice34_verify.gd can't
# reach. The verifier drives SimClient directly (the set_param wire + the physics on BOTH shipped
# wires); the Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing,
# the button drop, the new latch, or the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A HOLE, NOT A CONJUNCTION, AND THAT IS NEW FOR THIS ARC. Slices 26–31
# were indistinguishable BY ROUTING and separated only by their HUD; slice 32's tooth was the MIRROR
# WITHOUT its marker; slice 33's was that a branch keyed on BOTH markers sits ahead of both. Here the
# marker exists because the LOADER'S REFUSAL LEAVES A HOLE. `scenario.jl` refuses `seeker_fov_deg`
# beside a head — a gimballed seeker has NO body-fixed window, its body-fixed limit is the mechanical
# STOP — so a gimbal wire raises `radome_view` (it HAS glass) and NOT `seeker_fov_view`: BOTH of the
# client's FOV branches fail their conjunction and slice 26/27/28's RADOME CASCADE takes it.
#
# ⚠⚠ AND THAT FAILURE IS THE STALE-READOUT CLASS'S WORST FORM, BECAUSE NOTHING IN IT IS STALE. A
# gimbal wire carries `radome_slope`, `radome_residual*`, `radome_slope_worst` and `omega_q`/`omega_r`,
# so every number the cascade reads is LIVE and PLAUSIBLE. It would print a confident ring/quiet
# verdict about the GLASS on a wire whose whole subject is the HEAD — the wrong subject, from real
# telemetry, and not one test would fail. The mirror below asserts exactly that: strip the marker and
# the SAME handshake lands in the radome arm with `_radome_view` still true.
#
# ⚠ THE BUTTON NEEDS NO EDIT AT EITHER SITE (slice 33's finding, second occurrence — the OPPOSITE of
# slice 26's "the drop needs BOTH"), and that is asserted rather than assumed: `radome_view` is raised
# here too and already hides it. What the new marker selects is the HUD BRANCH ALONE.
#
# ⭐ AND THE HUD COMPARES TWO PAIRS, NOT ONE — the plan's gate-3 warning, made structural. A gimbal has
# TWO limits read against TWO DIFFERENT ANGLES: the head's TRAVEL against the mechanical STOP (which
# is the ENGAGEMENT's lead, i.e. slice 33's excursion RESTATED) and the head's TRACKING ERROR against
# the DETECTOR window (new, and where the margin the self-referential index buys is paid for). A HUD
# that kept slice 33's single comparison would report a budget that is not the one being spent.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-34 gimbal handshake routes to _mode=airframe3d, button HIDDEN at BOTH sites, no edit
#   2. ⭐⭐ THE HOLE: strip `gimbal_view` and the SAME wire falls into the radome cascade
#   3. ⭐⭐ THE DISAGREEMENT: slice 33's verdict and slice 34's, on this wire's own numbers, differ
#   4. ⭐ the VERDICT pinned in all FOUR states, including the endgame the range gate suppresses
#   5. ⭐ BOTH instruments live — the ring peak-hold AND the NEW head latch, independently; and
#      `_fov_lost` must stay CLEAR (a gimbal wire ships no `seeker_valid` at all)
#   6. every key `_draw_gimbal_hud_lines` reads is present and scalar
#   7. TWO sliders at the interceptor driving set_param; NOTHING sends set_fidelity
#   8. the disqualified knobs are absent — including `gimbal_tau_s`, whose exclusion is MEASURED
#   9. ⭐ THE TWIN: a strapdown handshake keeps the radome cascade and never latches the head
#  10. the value-guard, SEVENTEEN-WAY
#
# Run:  godot --headless --path clients/godot --script res://net/slice34_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb_twin
var _sb33
var _sb32
var _sb31
var _sb25
var _sb24
var _sb23
var _sb19
var _sb16
var _sb18
var _sb21

# The slice-34 gimbal wire's telemetry: the shipped default (R̂ = −0.18, a 4 deg detector window, a
# 30 deg stop) mid-approach.
# ⚠ NOTE WHAT IS HERE AND WHAT IS NOT. The head keys are present; NOT ONE slice-32/33 window key is
# (`seeker_fov_deg`, `seeker_fov_margin_deg`, `seeker_valid`) — the loader refuses the combination and
# the seam's `!_gim` conjunct makes that refusal STRUCTURAL. And `look_angle` carries the HEAD's own
# angle, equal to `head_angle_deg` by construction, while `look_body_deg` is the NOSE's — the triple
# that IS this slice.
func _gim_tel(valid: bool, los: float, head: float, off: float, margin: float, omr: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 4.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": margin,
		"m1.head_angle_deg": head,
		"m1.head_off_deg": off,
		"m1.look_angle": head,              # …the HEAD's index: the angle the glass ACTUALLY used
		"m1.look_body_deg": 17.83,          # …and the NOSE's, which a strapdown seeker would use
		"m1.lead_angle_deg": 18.13,
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.18,
		"m1.radome_slope_worst": -0.32999999999999996,
		"m1.radome_residual": 0.15,
		"m1.radome_residual_az": -0.05,
		"m1.radome_slope_az": -0.23,
		"m1.radome_eps": 0.0005,
		"m1.radome_ripple": -0.15,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.10, "m1.omega_r": omr,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _gim_handshake(gim_marker: bool) -> Dictionary:
	var h := {
		"name": "slice34_gimbal",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"radome_view": true,
		"knobs": [
			{"target": "m1", "key": "gimbal_fov_deg", "min": 1.0, "max": 8.0, "value": 4.0,
			 "label": "SEEKER: detector window (deg) — what the head's tracking error is spent from"},
			{"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.18,
			 "label": "DESIGN: believed slope R̂ — it moves the ring AND the tracking error"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	}
	if gim_marker:
		h["gimbal_view"] = true
	return h

func _initialize() -> void:
	print("S34UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_gim_handshake(true))

	# ══ TOOTH 1 — ROUTE: slice 23's 3-D view, and the button DROPPED for the TENTH time ═══════════
	if sb._mode != "airframe3d":
		return _fail("a slice-34 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_view:
		return _fail("the client must record the `gimbal_view` handshake marker — without it the dispatch falls past both FOV branches into the RADOME cascade")
	if not sb._radome_view:
		return _fail("a gimbal wire carries GLASS, so `radome_view` must be recorded too — the two markers co-occur here and the ORDER between them is what matters")
	if sb._seeker_fov_view:
		return _fail("⚠ a gimbal wire must NOT carry `seeker_fov_view` — the loader REFUSES `seeker_fov_deg` beside a head, because a gimballed seeker has no body-fixed window. That absence is exactly why `gimbal_view` had to exist")
	if sb._prop_btn.visible:
		return _fail("a slice-34 handshake must DROP the shared button — slice 34 adds NO rung at all (the head is a deterministic servo, and `gimbal_fov_deg` is a KNOB: a wide window is bit-identical to the key being absent). Slice-16's Option-P′, TENTH use.")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 34 reuses the slice-23 3-D view wholesale")
	# ⚠ AND THE DROP NEEDS NO SLICE-34 EDIT AT EITHER SITE, which is slice 33's finding recurring and
	# the OPPOSITE of slice 26's: `radome_view` is raised here too and both existing branches already
	# hide the button. Asserted rather than assumed.
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button hidden on a gimbal wire — the scenario carries an `:airframe` fidelity (HELD at six_dof), so the generic arm would re-show what _enter_airframe3d_mode dropped. Slice 34 needs no edit at either site (the `radome_view` branch already hides it), and this is the assert that says so")
	print("S34UI_ROUTE airframe3d + gimbal_view recorded (and seeker_fov_view correctly ABSENT) + button HIDDEN at BOTH sites with NO slice-34 edit at either + the 3-D scene still built")

	# ══ TOOTH 2 — ⭐⭐ THE HOLE: strip the marker and the SAME wire lands in the RADOME CASCADE ═════
	# This is the defect the marker exists to prevent, asserted structurally: the routing is
	# IDENTICAL (so nothing about the view or the button gives it away) while the only surviving
	# marker is `radome_view` — which is the branch that would then draw a verdict about the GLASS.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_gim_handshake(false))
	if _sb_nomarker._gimbal_view:
		return _fail("the no-marker mirror must NOT record gimbal_view")
	if not _sb_nomarker._radome_view or _sb_nomarker._seeker_fov_view:
		return _fail("⭐⭐ THE HOLE: without `gimbal_view` the ONLY surviving marker is `radome_view` — both FOV branches fail their conjunction (`seeker_fov_view` is absent by the loader's refusal) and slice 26/27/28's cascade takes the wire. Got rad=%s fov=%s" % [_sb_nomarker._radome_view, _sb_nomarker._seeker_fov_view])
	if _sb_nomarker._mode != sb._mode or _sb_nomarker._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ and the two must be indistinguishable by ROUTING (same view, same dropped button) — which is precisely why the failure would be silent. Got modes %s/%s" % [_sb_nomarker._mode, sb._mode])
	# ⚠ AND EVERY KEY THAT CASCADE READS IS LIVE ON THIS WIRE — the reason the failure is confidently
	# wrong rather than visibly broken. If any of these were absent it would print a 0.000 and someone
	# would notice; they are all present, so it would print fluent nonsense about the glass.
	sb._telemetry = _gim_tel(true, 4500.0, 17.19, 1.95, 2.05, 0.02)
	for k in ["m1.radome_slope", "m1.radome_eps", "m1.look_angle", "m1.radome_residual",
			  "m1.radome_slope_az", "m1.radome_slope_worst", "m1.omega_r"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ the radome cascade reads %s — it must be LIVE on this wire, which is what makes the mis-branch CONFIDENT rather than visibly broken" % k)
	print("S34UI_HOLE   the no-marker mirror routes IDENTICALLY and keeps only `radome_view` — and every key that cascade reads is live here, so the mis-branch would be fluent about the GLASS on a wire whose subject is the HEAD")

	# ══ TOOTH 3 — ⭐⭐ THE DISAGREEMENT: slice 33's verdict is WRONG on this wire ═══════════════════
	# The pairs differ. Slice 33's helper reads `seeker_fov_margin_deg` (a BODY window budget) which a
	# gimbal wire does not ship at all, so through a defaulted `get(..., 0.0)` it would see a margin of
	# 0.0 and a belief nowhere near the aim point, and report the ring spending a budget that is not
	# the one being spent. Slice 34's rides the DETECTOR budget the core actually ships.
	var s33_says: String = sb._budget_verdict_label(false, 0.0, 4500.0, -0.18, -0.32999999999999996)
	var s34_says: String = sb._gimbal_verdict_label(false, 2.05, 4500.0, false)
	if s33_says == s34_says:
		return _fail("⭐⭐ THE TWO HELPERS MUST DISAGREE ON THIS WIRE — that disagreement is why the branch exists. Slice 33's compares a BODY-window budget this wire does not ship (defaulted to 0.0) against a belief that is not at the aim point; slice 34's rides the DETECTOR budget (+2.05 deg) the core does ship. Both returned '%s'" % s34_says)
	if s34_says != "SELF-INDEXED — the loop is quiet":
		return _fail("⭐ slice 34's verdict must name the MECHANISM on a healthy arm — the index is the head's own last measurement and the loop is quiet. Got '%s'" % s34_says)
	# ⚠ AND SLICE 33's HELPER IS LEFT VERBATIM AND IS STILL RIGHT ON SLICE 33's OWN WIRE, so the defect
	# is the BRANCH and not the helper (slice 33 made the same assert about slice 32's).
	if sb._budget_verdict_label(false, -1.5, 3000.0, -0.03, -0.33) != "RING PAST THE WINDOW — breaking":
		return _fail("slice 33's helper must be UNCHANGED — a negative body budget at r = 3000 m on ITS own wire must still read as breaking")
	print("S34UI_DISAGREE slice 33's helper says '%s' on this wire while slice 34's says '%s' — the branch is proven necessary, and 33's helper is verbatim and still correct on 33's wire" % [s33_says, s34_says])

	# ══ TOOTH 4 — ⭐ THE VERDICT, PINNED IN ALL FOUR STATES ════════════════════════════════════════
	# ⚠⚠ THE ORDER IS LOAD-BEARING, NOT TIDY, AND THIS IS WHERE IT IS PROVEN. The latch wins outright
	# because of the metric inversion gate 2 measured: a broken window FREEZES the index (no error
	# signal, no slew — the head HOLDS), a frozen index makes a CONSTANT bend, and a constant bend is
	# QUIET at every R̂. So on a broken arm the ring meter reads calm, and a ring-first ordering would
	# print "the loop is quiet" on a missile that has lost its target.
	if sb._gimbal_verdict_label(true, 2.05, 4500.0, false) != "TRACK LOST — the head let go":
		return _fail("⭐ THE LATCH MUST WIN OUTRIGHT: once the head has lost its error signal it HOLDS, and neither a recovered budget nor a quiet ring changes that. Got '%s'" % sb._gimbal_verdict_label(true, 2.05, 4500.0, false))
	if sb._gimbal_verdict_label(true, 2.05, 4500.0, true) != "TRACK LOST — the head let go":
		return _fail("⚠⚠ …AND IT MUST WIN OVER THE RING TOO. A broken window freezes the index and a frozen index makes a CONSTANT bend, which is quiet at every R̂ — so on a broken arm the ring meter is meaningless in BOTH directions and the latch must outrank it either way. Got '%s'" % sb._gimbal_verdict_label(true, 2.05, 4500.0, true))
	if sb._gimbal_verdict_label(false, -1.2, 3000.0, false) != "ERROR PAST THE WINDOW — breaking":
		return _fail("⭐ THE BREAKING STATE: a NEGATIVE detector budget out at r = 3000 m is the tracking error overrunning the window. Got '%s'" % sb._gimbal_verdict_label(false, -1.2, 3000.0, false))
	if sb._gimbal_verdict_label(false, 2.76, 4500.0, true) != "RINGING — the index is not enough":
		return _fail("⭐ THE THIRD STATE IS THE ONE A TWO-WAY LABEL WOULD HIDE: the head is still holding its track and the budget is positive, but the loop is ringing anyway — the self-referential index bought two rungs of margin, not immunity. Got '%s'" % sb._gimbal_verdict_label(false, 2.76, 4500.0, true))
	# ⚠⚠ AND THE ENDGAME MUST NOT READ AS BREAKING — the reason the range gate is an ARGUMENT of the
	# helper rather than a caller's concern. EVERY held arm leaves its detector window in the last
	# metres because the LOS unit vector swings through a huge angle as r → 0 (slice 33 paid five
	# failing asserts for this and this slice's verifier re-measured it). Ungated, this state would
	# fire at the instant of a CLEAN INTERCEPT.
	if sb._gimbal_verdict_label(false, -86.0, 1.9, false) != "SELF-INDEXED — the loop is quiet":
		return _fail("⚠⚠ THE ENDGAME MUST NOT READ AS BREAKING: a budget of −86 deg at r = 1.9 m is the LOS unit vector swinging through a huge angle in the last millisecond before impact — GEOMETRY, not the window's verdict. Got '%s'" % sb._gimbal_verdict_label(false, -86.0, 1.9, false))
	if sb._gimbal_verdict_label(false, -86.0, 900.0, false) != "ERROR PAST THE WINDOW — breaking":
		return _fail("…and the SAME budget at r = 900 m MUST read as breaking, or the gate above is suppressing the state everywhere rather than in the endgame. Got '%s'" % sb._gimbal_verdict_label(false, -86.0, 900.0, false))
	print("S34UI_VERDICT all four states pinned — the latch outranking BOTH the budget and the ring (the metric inversion), and the endgame the range gate suppresses with its mirror outside the gate")

	# ══ TOOTH 5 — ⭐ BOTH INSTRUMENTS LIVE, AND THE THIRD ONE CORRECTLY DEAD ═══════════════════════
	# `_radome_qpeak` (the ring, slice 27) and `_gimbal_lost` (the head's track break, NEW) are two
	# INDEPENDENT `if` blocks in `_airframe3d_on_state`, not a chain — slice 33's own finding, one
	# slice later. ⚠ And `_fov_lost` must stay CLEAR: a gimbal wire ships no `seeker_valid` at all, so
	# a latch that defaulted to "lost" would paint every gimbal arm broken.
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]
	if sb._gimbal_lost or sb._fov_lost or sb._radome_qpeak != 0.0:
		return _fail("all three instruments must start clear")
	sb._telemetry = _gim_tel(true, 4500.0, 20.62, 5.24, 2.76, 1.31)     # ringing, still holding
	sb._airframe3d_on_state({"entities": ents})
	if not (sb._radome_qpeak > 0.5):
		return _fail("⭐ THE RING INSTRUMENT MUST BE LIVE ON A GIMBAL WIRE (fed |omega_r| = 1.31, got peak %.4f). A gimbal wire ships `radome_residual`, so the peak-hold's own gate is satisfied — if a dispatch ever chains these, the HUD reports a stable loop on a missile shaking itself out of its own detector window" % sb._radome_qpeak)
	if sb._gimbal_lost:
		return _fail("…and a VALID frame must not latch a head loss")
	if sb._fov_lost:
		return _fail("⚠ `_fov_lost` must stay CLEAR on a gimbal wire — it is gated on `seeker_valid`, which the loader's refusal guarantees is absent here. A latch that defaulted to lost would paint every gimbal arm broken")
	# ⚠ THE CHANNEL IS YAW: this wire's lead is in AZIMUTH, so the yaw channel sits on the steep part
	# of the slope curve while pitch sits near the boresight slope (slice 28's finding). `omega_q` is
	# 0.10 in this fixture — a peak-hold left on pitch would meter the QUIET channel.
	if sb._radome_qpeak < 1.0:
		return _fail("⚠ the peak-hold must be riding the YAW channel (|omega_r| = 1.31), not pitch (|omega_q| = 0.10) — this wire ships `radome_slope_az`. Got %.4f" % sb._radome_qpeak)
	if sb._ring_channel_key() != ".omega_r":
		return _fail("a RIPPLE wire (ships `radome_slope_az`) must select the YAW channel — slice 28's switch, shared by both HUD sites. Got %s" % sb._ring_channel_key())
	sb._telemetry = _gim_tel(false, 5216.9, 17.19, 73.60, -69.60, 1.20)   # the break, at long range
	sb._airframe3d_on_state({"entities": ents})
	if not sb._gimbal_lost:
		return _fail("⭐ AND THE HEAD's LATCH MUST BE LIVE — a frame with `gimbal_valid` 0 at r = 5217 m must latch it. It is a SEPARATE variable from `_fov_lost` because the two read DIFFERENT core booleans about DIFFERENT windows")
	if not (sb._radome_qpeak > 0.5):
		return _fail("…and latching the break must not disturb the ring instrument")
	if sb._fov_lost:
		return _fail("…and it must still not touch slice 32's latch")
	# …and `reset` clears the new latch with the others (slice 32's post-review finding, third use)
	sb._on_reset_pressed()
	if sb._gimbal_lost or sb._radome_qpeak != 0.0:
		return _fail("`reset` must clear the head latch AND the peak-hold (latch %s, peak %.4f) — otherwise a re-launched missile inherits the previous run's verdict" % [sb._gimbal_lost, sb._radome_qpeak])
	print("S34UI_INSTRUMENTS the ring peak-hold rides YAW to 1.310 and the NEW head latch fires at r = 5217 m, independently; `_fov_lost` stays correctly dead (no `seeker_valid` on this wire); `reset` clears both live ones")

	# ══ TOOTH 6 — every key `_draw_gimbal_hud_lines` reads is PRESENT and scalar ══════════════════
	# ⚠ The stale-readout class in its MIRROR form: a missing key silently becoming 0.000 through
	# `get(..., 0.0)`. ⭐ AND THE PAIRS ARE WHAT MATTER — `head_angle_deg` vs `gimbal_stop_deg` (the
	# TRAVEL against the STOP) and `head_off_deg` vs `gimbal_fov_deg` with `gimbal_fov_margin_deg` as
	# the signed verdict (the TRACKING ERROR against the DETECTOR window). All eight are core scalars;
	# the client evaluates no geometry and never reconstructs the margin (convention 13, and gate 2
	# measured that the window and the error do NOT reconstruct it on a negative slider).
	sb._telemetry = _gim_tel(true, 4500.0, 17.19, 1.95, 2.05, 0.02)
	# ⚠ ONE MORE STATE FRAME, AND IT IS NOT BOOKKEEPING: tooth 5 ended by driving
	# `_on_reset_pressed()`, which clears the 3-D trail along with the instruments. Re-feeding here
	# checks the state path still works AFTER a reset — which is the path a student actually takes.
	sb._airframe3d_on_state({"entities": ents})
	sb._update_readout()
	for k in ["m1.omega_r", "m1.head_angle_deg", "m1.head_off_deg", "m1.gimbal_stop_deg",
			  "m1.gimbal_fov_deg", "m1.gimbal_fov_margin_deg", "m1.look_body_deg",
			  "m1.gimbal_valid", "m1.los_range"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ `_draw_gimbal_hud_lines` reads %s — a missing key would `get(..., 0.0)` and print a confident 0.000, the stale-readout class this arc has caught nine times" % k)
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	# ⭐⭐ AND THE INDEX PAIR MUST BE TWO DIFFERENT NUMBERS ON THE SCREEN — the mechanism made visible.
	# `look_angle` IS the head's own angle (the seam sets `look_az, look_el = head_az, head_el` before
	# the bend is taken) while `look_body_deg` is the NOSE's. If a HUD drew only one of them there
	# would be nothing to see: the whole slice is WHERE the glass is indexed.
	if float(sb._telemetry["m1.look_angle"]) != float(sb._telemetry["m1.head_angle_deg"]):
		return _fail("`look_angle` must carry the HEAD's own angle on a gimbal wire — that is what the glass was evaluated at, and it is asserted core-side as a per-tick bit-identity")
	if float(sb._telemetry["m1.look_body_deg"]) == float(sb._telemetry["m1.head_angle_deg"]):
		return _fail("⭐⭐ …and `look_body_deg` must be a DIFFERENT number — the NOSE's angle, what a strapdown seeker would have indexed. Two numbers on the screen IS the mechanism; one number is no lesson")
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S34UI_HUD all nine gimbal keys present and scalar, and the index PAIR is two different numbers (head 17.19 deg vs nose 17.83 deg)")

	# ══ TOOTH 7+8 — TWO sliders, BOTH at the interceptor, and the disqualifications ═══════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("the slice-34 gimbal wire must build EXACTLY TWO sliders (gimbal_fov_deg + radome_slope_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-34 wire must NEVER send set_fidelity — there is no rung; the head is a deterministic servo and the window is a KNOB (a wide one is bit-identical to the key being absent)")
	if not keys_set.has("gimbal_fov_deg") or keys_set["gimbal_fov_deg"] != "m1":
		return _fail("the 'gimbal_fov_deg' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	if not keys_set.has("radome_slope_est") or keys_set["radome_slope_est"] != "m1":
		return _fail("the 'radome_slope_est' slider must send set_param at the interceptor m1 — the belief is the missile's. Got %s" % str(keys_set))
	for bad in ["gimbal_tau_s", "gimbal_stop_deg", "seeker_fov_deg", "cross_speed_mps",
				"radome_slope", "radome_ripple", "radome_ripple_k", "gyro_scale_err", "gyro_bias_z",
				"n_pn", "rho", "sigma_seek", "elevation_deg", "af_alpha_max", "alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 34 must NOT build a '%s' slider. `gimbal_tau_s` heads this list and its exclusion is MEASURED, not argued: the amplitude sags monotonically with τ on EVERY arm and AT THE LINE that sag crosses the verdict (the bracket walks from (−0.18, −0.17] at τ ≤ 0.02 to (−0.16, −0.12] at 0.20) — a CONFOUNDED lever moves the verdict without moving the mechanism. `gimbal_stop_deg` is a RESTATEMENT of slice 33's excursion and binding it COUPLES the two budgets. `seeker_fov_deg` is refused by the loader outright. The rest move the guidance loop, degrade the lesson beside it, or are DEAD. Got %s" % [bad, str(keys_set.keys())])
	print("S34UI_KNOB exactly 2 sliders — gimbal_fov_deg and radome_slope_est, BOTH → m1; NOTHING sends set_fidelity")

	# ══ TOOTH 9 — ⭐ THE TWIN: the strapdown wire keeps the radome cascade and never latches ═══════
	# The FOIL half of this two-scenario slice. It has no head, so it must NOT raise `gimbal_view`,
	# must keep exactly ONE slider, and its head latch must be structurally unreachable.
	_sb_twin = _build_sandbox()
	_sb_twin._on_scenario({
		"name": "slice34_strapdown", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true,
		"knobs": [{"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03,
				   "value": -0.18, "label": "DESIGN: believed slope R̂ — the STRAPDOWN twin"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb_twin._gimbal_view or _sb_twin._seeker_fov_view or not _sb_twin._radome_view:
		return _fail("the STRAPDOWN twin must raise radome_view ALONE — no head, no body window. Got gim=%s fov=%s rad=%s" % [_sb_twin._gimbal_view, _sb_twin._seeker_fov_view, _sb_twin._radome_view])
	if _sb_twin._mode != sb._mode or _sb_twin._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ the two shipped wires must be indistinguishable by ROUTING — the same 3-D view and the same dropped button. What separates them is the HUD BRANCH, which is the whole reason for the marker. Got modes %s/%s" % [_sb_twin._mode, sb._mode])
	if _find_all_sliders(_sb_twin._knob_box).size() != 1:
		return _fail("the twin must build EXACTLY ONE slider — it has no detector window to drag, and convention 9 is satisfied outright there rather than by the gimbal wire's diagonal argument")
	# ⚠ AND ITS HEAD LATCH MUST BE STRUCTURALLY UNREACHABLE — the twin ships no `gimbal_valid`, so the
	# latch's own presence gate is what keeps it dead rather than a value that happens to be 1.
	_sb_twin._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": 0.10, "m1.omega_r": -1.31,
						   "m1.radome_slope": -0.03, "m1.radome_eps": -0.0004,
						   "m1.look_angle": 22.11, "m1.radome_residual": 0.15,
						   "m1.radome_residual_az": -0.05, "m1.radome_slope_az": -0.23,
						   "m1.radome_slope_worst": -0.32999999999999996,
						   "m1.radome_slope_est": -0.18, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						   "m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb_twin._airframe3d_on_state({"entities": ents})
	if _sb_twin._gimbal_lost or _sb_twin._fov_lost:
		return _fail("the twin must latch NEITHER window instrument — it ships neither `gimbal_valid` nor `seeker_valid`, so both latches must be gated on the key's PRESENCE and not default to 'lost'")
	if not (_sb_twin._radome_qpeak > 0.5):
		return _fail("⭐ but its RING instrument must be live and riding YAW (fed |omega_r| = 1.31) — the twin is the arm that actually rings, and its whole job is to show it. Got %.4f" % _sb_twin._radome_qpeak)
	print("S34UI_TWIN   the strapdown wire routes identically, keeps ONE slider, latches NEITHER window instrument, and its ring peak-hold reaches %.3f" % _sb_twin._radome_qpeak)

	# ══ TOOTH 10 — THE VALUE-GUARD, SEVENTEEN-WAY ═════════════════════════════════════════════════
	# (a) ⭐ slice 33 — BOTH of the older markers, no gimbal one: still its own composition branch
	_sb33 = _build_sandbox()
	_sb33._on_scenario({
		"name": "s33_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"radome_view": true, "seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 19.0, "max": 40.0, "value": 21.0, "label": "FOV"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb33._gimbal_view or not (_sb33._radome_view and _sb33._seeker_fov_view):
		return _fail("a slice-33 wire must carry BOTH older markers and NOT gimbal_view — the composition branch must stay reachable underneath the new one")
	# (b) slice 32 — FOV only
	_sb32 = _build_sandbox()
	_sb32._on_scenario({
		"name": "s32_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 18.5, "max": 40.0, "value": 25.0, "label": "FOV"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb32._gimbal_view or _sb32._radome_view or not _sb32._seeker_fov_view:
		return _fail("a slice-32 wire must carry seeker_fov_view ALONE (its radome keys are absent by convention 9 — slice 32's own gate-3 testset asserts that AS A FEATURE)")
	# (c) ⭐ slice 31 — the deepest radome wire, radome_view only, still its own cascade
	_sb31 = _build_sandbox()
	_sb31._on_scenario({
		"name": "s31_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05, "label": "s"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb31._gimbal_view or _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view ALONE")
	# ⭐ AND ITS PEAK-HOLD MUST STILL LATCH ON PITCH — the new branch is inserted AHEAD of the radome
	# cascade and must not have disturbed it (the mirror of tooth 5).
	_sb31._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.omega_r": 0.02,
						"m1.radome_slope": -0.10, "m1.radome_eps": -0.0004, "m1.look_angle": 13.6,
						"m1.radome_residual": 0.0, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb31._airframe3d_on_state({"entities": ents})
	if not (_sb31._radome_qpeak > 0.5):
		return _fail("⭐ the radome-only MIRROR must still latch its PITCH peak-hold (fed |omega_q| = 1.31, no `radome_slope_az`) — got %.4f" % _sb31._radome_qpeak)
	if _sb31._gimbal_lost or _sb31._fov_lost:
		return _fail("the radome-only MIRROR must latch neither window instrument")
	# (d) slice 25 — seeker_axes with no marker keeps its cycler
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4, "label": "σ"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 wire (no marker) must keep the seeker_axes cycler VISIBLE, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# (e) slice 24 — steering cycler
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._fid_kind != "steering" or not _sb24._prop_btn.visible:
		return _fail("a slice-24 wire must take the steering cycler, got kind=%s vis=%s" % [_sb24._fid_kind, _sb24._prop_btn.visible])
	# (f) slice 23 — the 3-ring airframe cycler
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": 0.0, "max": 30.0, "value": 20.0, "label": "Cyβ"}],
		"fidelity": {"airframe": "six_dof", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._fid_kind != "airframe" or not _sb23._prop_btn.visible or _sb23._airframe_rungs.size() != 3:
		return _fail("a slice-23 wire must take the 3-ring airframe cycler, got kind=%s vis=%s rungs=%d" % [_sb23._fid_kind, _sb23._prop_btn.visible, _sb23._airframe_rungs.size()])
	# (g) slice 19 — the 2-D airframe view, 2-ring cycler
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.0, "label": "ρ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or not _sb19._prop_btn.visible:
		return _fail("a slice-19 wire must stay 2-D spatial with a VISIBLE airframe cycler, got mode=%s kind=%s vis=%s" % [_sb19._mode, _sb19._fid_kind, _sb19._prop_btn.visible])
	# (h) slice 16 — drops the button, but in the 2-D view
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {"guidance": "pn", "autopilot": "alpha"},
	})
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 wire must DROP the button (no fidelity to cycle)")
	if _sb16._mode == sb._mode:
		return _fail("slices 16 and 34 both drop the button but must NOT share a mode (16 = 2-D spatial, 34 = 3-D airframe3d)")
	# (i) slice 18 — terrain_grid wins the MODE discriminator
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (j) slice 21 — :atmosphere still wins the button over a co-shipped :airframe
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S34UI_GUARD seventeen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 31 radome-only / 32 FOV-only / 33 BOTH-older / 34 gimbal — plus the no-marker mirror and the strapdown twin")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..33_ui_test contract) --------------------------------------------

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
	print("S34UI OK: slice 34 ships TWO wires, and the CLIENT half of it is a marker that exists " +
		"because THE LOADER'S REFUSAL LEAVES A HOLE. `scenario.jl` refuses `seeker_fov_deg` beside a " +
		"head — a gimballed seeker has NO body-fixed window, its body-fixed limit is the mechanical " +
		"STOP — so a gimbal wire raises `radome_view` and NOT `seeker_fov_view`, both of the client's " +
		"FOV branches fail their conjunction, and slice 26/27/28's RADOME CASCADE takes it. ⚠⚠ THAT " +
		"IS THE STALE-READOUT CLASS'S WORST FORM, BECAUSE NOTHING IN IT IS STALE: every key that " +
		"cascade reads is LIVE on this wire (asserted above), so it would print a fluent ring/quiet " +
		"verdict about the GLASS on a wire whose whole subject is the HEAD, and not one test would " +
		"have failed. The no-marker mirror proves it structurally — identical routing, identical " +
		"dropped button, only `radome_view` surviving. ⚠ THE BUTTON NEEDS NO EDIT AT EITHER SITE " +
		"(slice 33's finding, second occurrence, and the OPPOSITE of slice 26's 'the drop needs " +
		"BOTH'), which is asserted rather than assumed; what the marker selects is the HUD BRANCH " +
		"ALONE. ⭐ AND THAT BRANCH DRAWS TWO PAIRS, NOT ONE: a gimbal has TWO limits read against TWO " +
		"DIFFERENT ANGLES — the head's TRAVEL against the STOP (slice 33's excursion, RESTATED) and " +
		"the head's TRACKING ERROR against the DETECTOR window, with `gimbal_fov_margin_deg` as the " +
		"SIGNED verdict (slice 18's `terrain_clearance_m` shape). A HUD keeping slice 33's single " +
		"comparison would report a budget that is not the one being spent, and the two helpers are " +
		"called on the SAME wire's numbers and asserted to DISAGREE. ⭐⭐ THE INDEX PAIR IS ON SCREEN " +
		"AS TWO DIFFERENT NUMBERS — `look_angle` carries the HEAD's own angle (what the glass was " +
		"evaluated at) and `look_body_deg` the NOSE's (what a strapdown seeker would have used); one " +
		"number would be no lesson. ⭐ THE VERDICT IS A PURE HELPER, the only reason it is testable at " +
		"all since `_draw` never runs headless (convention 14; slice 31's aim-point comparison " +
		"shipped WRONG and only a windowed shot caught it). All FOUR states are pinned, and the ORDER " +
		"is proven: the LATCH outranks BOTH the budget and the ring, because a broken window FREEZES " +
		"the index and a frozen index makes a CONSTANT bend, which is QUIET at every R̂ — a " +
		"ring-first ordering would print 'the loop is quiet' on a missile that has lost its target. " +
		"The ENDGAME state the range gate suppresses is pinned with its mirror OUTSIDE the gate, so " +
		"the gate is proven a RANGE gate and not a blanket. ⭐ BOTH INSTRUMENTS ARE LIVE ON ONE WIRE " +
		"— `_radome_qpeak` and the NEW `_gimbal_lost` are two INDEPENDENT `if` blocks, not a chain — " +
		"and `_fov_lost` is asserted to stay DEAD, since a gimbal wire ships no `seeker_valid` at all " +
		"and a latch defaulting to 'lost' would paint every gimbal arm broken. `reset` clears the " +
		"live ones. TWO sliders are built, BOTH at the interceptor, and NOTHING sends set_fidelity; " +
		"every other lever is asserted ABSENT — `gimbal_tau_s` heads that list and its exclusion is " +
		"MEASURED, not argued (the amplitude sags monotonically with τ and AT THE LINE that sag " +
		"crosses the verdict, so it is a CONFOUNDED lever). ⭐ AND THE STRAPDOWN TWIN IS CHECKED TOO: " +
		"it routes IDENTICALLY, keeps ONE slider, latches NEITHER window instrument, and rings. The " +
		"value-guard holds SEVENTEEN ways.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S34UI FAIL: " + msg)
	print("S34UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb_twin, _sb33, _sb32, _sb31, _sb25, _sb24, _sb23, _sb19,
			   _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
