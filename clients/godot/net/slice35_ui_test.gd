extends SceneTree
# Headless UI test for the slice-35 RATE-LIMITED SERVO view routing + HUD — the piece
# slice35_verify.gd can't reach. The verifier drives SimClient directly (the set_param wire + the
# physics); the Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing,
# the new instrument, or the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS AN **INVISIBLE SLICE**, NOT A HOLE — AND THE DIFFERENCE IS THE WHOLE
# POINT OF THIS FILE. Slice 34's marker plugged a REAL HOLE: its wire raised neither FOV marker (the
# loader refuses `seeker_fov_deg` beside a head) and fell through into slice 26/27/28's RADOME
# cascade, which then talked confidently about the GLASS on a wire whose subject was the HEAD. The
# re-check the plan demanded for THIS slice came back **NEGATIVE**: a slice-35 wire is a slice-34 wire
# PLUS one key, `gimbal_view` is raised, and the branch it selects is still about the HEAD. Nothing is
# re-routed and nothing is stale.
#
# ⚠⚠ WHAT GOES WRONG INSTEAD IS SUBTLER AND WORTH A TOOTH OF ITS OWN: slice 34's verdict pairs the
# head's TRACKING ERROR against the DETECTOR WINDOW, which on this wire is AUTHORED WIDE (25 deg
# against a worst measured requirement of 19.279 deg over 184 domain cells) and NEVER BINDS. So it
# would report a comfortable budget, name the INDEX, and never mention the SERVO. Every number it drew
# would be TRUE. ⭐⭐ AND ON ONE STATE IT IS WORSE THAN SILENT: when a slow servo has bought the ring
# down, slice 34's helper reads "SELF-INDEXED — the loop is quiet" — crediting the INDEX for a quiet
# the BANDWIDTH paid for, which is the exact inversion of this slice's lesson. That state is pinned
# below as the sharpest tooth in the file.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-35 handshake routes to _mode=airframe3d, button HIDDEN at BOTH sites, no edit
#   2. ⭐⭐ THE INVISIBLE SLICE: strip `gimbal_rate_view` and the SAME wire keeps slice 34's HUD —
#      identical routing, identical button, and a verdict that is TRUE and says nothing
#   3. ⭐⭐ THE INVERSION: on the bought-quiet state slice 34's helper credits the wrong thing
#   4. ⭐ the VERDICT pinned in all FIVE states, with the latch proven to outrank both booleans
#   5. ⭐ THE NEW INSTRUMENT: an EMA duty, live beside the ring peak-hold and the head latch, and
#      cleared by reset — plus the two-run inversion (a broken arm's servo reads FREE)
#   6. every key `_draw_gimbal_rate_hud_lines` reads is present and scalar
#   7. TWO sliders at the interceptor driving set_param; NOTHING sends set_fidelity
#   8. the disqualified knobs are absent — INCLUDING `gimbal_fov_deg`, which was slice 34's own live
#      slider and is dropped here on a NUMBER
#   9. ⭐ THE MIRROR: a slice-34 handshake keeps slice 34's branch and its own verdict, unchanged
#  10. the value-guard, EIGHTEEN-WAY
#
# Run:  godot --headless --path clients/godot --script res://net/slice35_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb34
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

# The slice-35 wire's telemetry: the shipped default (R̂ = −0.03, servo 40 deg/s, a 25 deg AUTHORED
# detector window, a 30 deg stop) mid-approach, at the numbers the verifier measured on this wire.
# ⚠ NOTE WHAT IS HERE. The three NEW keys (`head_rate_dps`, `head_rate_sat`, `gimbal_rate_dps`) sit
# BESIDE every slice-34 head key, because a slice-35 wire is a slice-34 wire plus one — which is
# exactly why slice 34's branch would happily draw it and say nothing wrong.
func _rate_tel(valid: bool, los: float, dem: float, sat: bool, off: float, margin: float,
			   omr: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 25.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": margin,
		"m1.gimbal_rate_dps": 40.0,          # …the CAP
		"m1.head_rate_dps": dem,             # …and the PRE-LIMIT demand, which must exceed it
		"m1.head_rate_sat": 1.0 if sat else 0.0,
		"m1.head_angle_deg": 23.61,
		"m1.head_off_deg": off,
		"m1.look_angle": 23.61,             # …the HEAD's index: the angle the glass ACTUALLY used
		"m1.look_body_deg": 24.02,          # …and the NOSE's, which a strapdown seeker would use
		"m1.lead_angle_deg": 18.13,
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.03,
		"m1.radome_slope_worst": -0.32999999999999996,
		"m1.radome_residual": 0.0,
		"m1.radome_residual_az": -0.10,
		"m1.radome_slope_az": -0.23,
		"m1.radome_eps": 0.0005,
		"m1.radome_ripple": -0.15,
		"m1.aero_sat": 1.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.10, "m1.omega_r": omr,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _rate_handshake(rate_marker: bool) -> Dictionary:
	var h := {
		"name": "slice35_rate",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"radome_view": true,
		"gimbal_view": true,
		"knobs": [
			{"target": "m1", "key": "gimbal_rate_dps", "min": 8.0, "max": 60.0, "value": 40.0,
			 "label": "SERVO: max head slew (deg/s) — slow it and the ring falls while the lag grows"},
			{"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03,
			 "label": "DESIGN: believed slope R̂ — at R₀+2A the servo is free at every rate"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	}
	if rate_marker:
		h["gimbal_rate_view"] = true
	return h

func _initialize() -> void:
	print("S35UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_rate_handshake(true))
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]

	# ══ TOOTH 1 — ROUTE: slice 23's 3-D view, and the button DROPPED for the ELEVENTH time ════════
	if sb._mode != "airframe3d":
		return _fail("a slice-35 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_rate_view:
		return _fail("the client must record the `gimbal_rate_view` handshake marker — without it the HUD is slice 34's and the servo is never mentioned")
	if not (sb._gimbal_view and sb._radome_view):
		return _fail("a slice-35 wire is a slice-34 wire PLUS one key — it still carries a HEAD and still carries GLASS, so both older markers must be recorded. That superset relation is precisely why the marker-hole re-check came back NEGATIVE")
	if sb._seeker_fov_view:
		return _fail("⚠ a slice-35 wire must NOT carry `seeker_fov_view` — the loader REFUSES `seeker_fov_deg` beside a head")
	if sb._prop_btn.visible:
		return _fail("a slice-35 handshake must DROP the shared button — slice 35 adds NO rung (a rate limit is a deterministic bound on an existing servo, and `gimbal_rate_dps` is a KNOB: an absent key is bit-identical to no limit). Slice-16's Option-P′, ELEVENTH use")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 35 reuses the slice-23 3-D view wholesale")
	# ⚠ AND THE DROP NEEDS NO SLICE-35 EDIT AT EITHER SITE — slice 33's finding, THIRD occurrence.
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button hidden — the scenario carries an `:airframe` fidelity (HELD at six_dof), so the generic arm would re-show what _enter_airframe3d_mode dropped. `radome_view` already hides it at both sites, and this is the assert that says so")
	print("S35UI_ROUTE  airframe3d + gimbal_rate_view recorded ALONGSIDE gimbal_view and radome_view (the superset relation that made the hole re-check negative) + button HIDDEN at BOTH sites with NO slice-35 edit at either")

	# ══ TOOTH 2 — ⭐⭐ THE INVISIBLE SLICE: strip the marker and slice 34's HUD takes it ═══════════
	# ⚠⚠ AND THE ASSERT IS DELIBERATELY THE OPPOSITE SHAPE TO SLICE 34's. Slice 34's mirror had to
	# show the wire landing in a branch that was WRONG ABOUT THE SUBJECT. Here it lands in a branch
	# that is RIGHT about the subject (it is still the head) and simply cannot see the servo — so what
	# is asserted is not a wrong number but the ABSENCE of the slice from the screen.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_rate_handshake(false))
	if _sb_nomarker._gimbal_rate_view:
		return _fail("the no-marker mirror must NOT record gimbal_rate_view")
	if not (_sb_nomarker._gimbal_view and _sb_nomarker._radome_view):
		return _fail("⭐⭐ THE INVISIBLE SLICE: without `gimbal_rate_view` the wire still raises `gimbal_view`, so slice 34's HEAD branch takes it — nothing is re-routed and nothing is stale, which is exactly why the failure has no wrong number to catch it. Got gim=%s rad=%s" % [_sb_nomarker._gimbal_view, _sb_nomarker._radome_view])
	if _sb_nomarker._mode != sb._mode or _sb_nomarker._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ and the two must be indistinguishable by ROUTING (same view, same dropped button) — which is why the failure would be silent. Got modes %s/%s" % [_sb_nomarker._mode, sb._mode])
	# ⚠ EVERY KEY SLICE 34's BRANCH READS IS LIVE HERE (it is a superset wire), so it would draw five
	# fluent, true lines about the head's travel and its detector budget — and none about the servo.
	sb._telemetry = _rate_tel(true, 4500.0, 110.19, true, 7.50, 17.50, 1.31)
	for k in ["m1.head_angle_deg", "m1.look_body_deg", "m1.gimbal_stop_deg", "m1.head_off_deg",
			  "m1.gimbal_fov_deg", "m1.gimbal_fov_margin_deg", "m1.gimbal_valid"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ slice 34's branch reads %s — it must be LIVE on this wire, which is what makes the mis-branch FLUENT rather than visibly broken" % k)
	print("S35UI_INVIS  the no-marker mirror routes IDENTICALLY, keeps slice 34's HEAD branch (the right subject), and every key that branch reads is live — so it would draw five TRUE lines and never mention the demand, the cap or the saturation")

	# ══ TOOTH 3 — ⭐⭐ THE INVERSION: slice 34's verdict CREDITS THE WRONG THING ═══════════════════
	# The sharpest state in the file, and the one only this slice can produce: a slow servo has bought
	# the ring DOWN (quiet) while saturating almost every tick (pegged). Slice 34's helper sees a
	# comfortable detector budget and a quiet ring and reports the INDEX as the reason — which is the
	# exact inversion of the lesson, since what bought the quiet was BANDWIDTH, and it was not free.
	var s34_bought: String = sb._gimbal_verdict_label(false, 5.72, 4500.0, false)
	var s35_bought: String = sb._servo_verdict_label(false, false, 0.97)
	if s34_bought != "SELF-INDEXED — the loop is quiet":
		return _fail("the setup for the inversion must hold: on a quiet arm with a positive budget slice 34's helper reads the index verdict. Got '%s'" % s34_bought)
	if s35_bought != "QUIET, BOUGHT WITH BANDWIDTH":
		return _fail("⭐⭐ THE INVERSION: the SAME arm must read as bought-with-bandwidth here — slice 34's helper credits the INDEX for a quiet the SERVO paid for, and this state is the one no two-way label can express. Got '%s'" % s35_bought)
	# …and on the shipped default the two also differ, in the milder way: 34's is TRUE and silent.
	var s34_open: String = sb._gimbal_verdict_label(false, 17.50, 4500.0, true)
	var s35_open: String = sb._servo_verdict_label(false, true, 0.65)
	if s34_open == s35_open:
		return _fail("⭐⭐ THE TWO HELPERS MUST DISAGREE ON THIS WIRE'S OWN NUMBERS — that disagreement is why the branch exists. Both returned '%s'" % s35_open)
	if not s34_open.contains("index"):
		return _fail("slice 34's verdict must still name the INDEX (it is a head wire and that reading is TRUE) — got '%s'" % s34_open)
	if not s35_open.contains("SERVO"):
		return _fail("…and slice 35's must name the SERVO, which is the half slice 34's cannot reach at all. Got '%s'" % s35_open)
	# ⚠ AND SLICE 34's HELPER IS LEFT VERBATIM AND IS STILL RIGHT ON SLICE 34's OWN WIRE, so the defect
	# is the BRANCH and not the helper (slice 34 made the same assert about slice 33's).
	if sb._gimbal_verdict_label(false, -1.2, 3000.0, false) != "ERROR PAST THE WINDOW — breaking":
		return _fail("slice 34's helper must be UNCHANGED — a negative detector budget at r = 3000 m on ITS own wire must still read as breaking")
	print("S35UI_INVERT slice 34's helper says '%s' where slice 35's says '%s' — it credits the INDEX for a quiet the BANDWIDTH bought; and on the shipped default 34's is TRUE and silent ('%s' vs '%s')" % [s34_bought, s35_bought, s34_open, s35_open])

	# ══ TOOTH 4 — ⭐ THE VERDICT, PINNED IN ALL FIVE STATES ═══════════════════════════════════════
	# ⚠⚠ FOUR OF THEM ARE A 2x2 ON TWO BOOLEANS, AND THAT SHAPE IS THE SLICE: a rate limit buys the
	# ring DOWN and sells the tracking error UP, so the interesting states are the two MIXED ones. A
	# verdict built on either boolean alone would collapse exactly the pair a student is dragging.
	if sb._servo_verdict_label(false, true, 0.97) != "SERVO PEGGED — and still RINGING":
		return _fail("⭐ the WORST state: the servo is saturated AND the loop is still ringing. Got '%s'" % sb._servo_verdict_label(false, true, 0.97))
	if sb._servo_verdict_label(false, true, 0.08) != "RINGING — the servo has room yet":
		return _fail("⭐ the slider's CEILING: the loop rings at full amplitude and the servo is barely touched (8.2 %% of the band, measured). Got '%s'" % sb._servo_verdict_label(false, true, 0.08))
	if sb._servo_verdict_label(false, false, 0.0) != "FREE — the servo costs nothing":
		return _fail("⭐ THE CURE, and slice 30's rule paying a THIRD time: at the aim point the requirement is FLAT across the whole rate domain and the limit binds on 0.00 %% of the band. Got '%s'" % sb._servo_verdict_label(false, false, 0.0))
	# ⚠⚠ THE LATCH WINS OUTRIGHT, over BOTH booleans and in BOTH of their positions — inherited from
	# slice 34 with its reason and re-earned by a SECOND inversion this slice adds: a broken window
	# freezes the index (quiet at every R̂) AND the held head demands nothing, so `head_rate_sat` reads
	# 0 too. Both instruments read "healthy" on a missile that has lost its target.
	for ring in [true, false]:
		for duty in [0.0, 0.97]:
			if sb._servo_verdict_label(true, ring, duty) != "TRACK LOST — the head let go":
				return _fail("⚠⚠ THE LATCH MUST WIN OUTRIGHT in all four corners (ring=%s duty=%.2f gave '%s'). On a broken arm the ring meter reads calm (a frozen index makes a CONSTANT bend) AND the servo meter reads free (a held head demands nothing) — the two-run discipline's FOURTH quantity, and both would be good news" % [ring, duty, sb._servo_verdict_label(true, ring, duty)])
	# ⚠ AND THE DUTY THRESHOLD IS AN ARGUMENT, NOT A GLOBAL — driven at the boundary from both sides.
	if sb._servo_verdict_label(false, false, 0.49) != "FREE — the servo costs nothing":
		return _fail("the duty threshold must be 0.5 — 0.49 is below it. Got '%s'" % sb._servo_verdict_label(false, false, 0.49))
	if sb._servo_verdict_label(false, false, 0.50) != "QUIET, BOUGHT WITH BANDWIDTH":
		return _fail("…and 0.50 must be at or above it. Got '%s'" % sb._servo_verdict_label(false, false, 0.50))
	print("S35UI_VERDICT all five states pinned — the 2x2 on ring x pegged (both MIXED states named), the latch outranking all four corners, and the duty threshold driven from both sides")

	# ══ TOOTH 5 — ⭐ THREE INSTRUMENTS LIVE ON ONE WIRE, AND THE NEW ONE IS A THIRD SHAPE ═════════
	# `_radome_qpeak` (a decaying PEAK-HOLD, slice 27), `_gimbal_lost` (a LATCH, slice 34) and
	# `_servo_duty` (an EMA DUTY, NEW) are three INDEPENDENT `if` blocks in `_airframe3d_on_state`.
	# ⚠ Slice 33's finding matters MORE here than it did there: on slice 34's wire the two blocks could
	# not co-occur (the loader refused the combination), whereas here all three keys ship on EVERY
	# frame — so a chained dispatch would freeze one of them outright rather than merely being fragile.
	# ⚠ AND THE NEW SHAPE IS EARNED: a rate limit binds on a FRACTION of ticks (8.2 / 65.2 / 97.0 % at
	# the slider's ceiling, default and floor), so an instantaneous read would flicker with the ~2 Hz
	# ring and a latch would go true on every arm and stay. The question is the DUTY.
	if sb._gimbal_lost or sb._fov_lost or sb._radome_qpeak != 0.0 or sb._servo_duty != 0.0:
		return _fail("all four instruments must start clear")
	sb._telemetry = _rate_tel(true, 4500.0, 110.19, true, 7.50, 17.50, 1.31)
	for _i in 40:
		sb._airframe3d_on_state({"entities": ents})
	if not (sb._servo_duty >= 0.5):
		return _fail("⭐ THE NEW INSTRUMENT MUST RISE: 40 saturated frames must carry the EMA past the 0.5 verdict threshold (got %.4f). Its ~0.5 s time constant is the peak-hold's, chosen for the same reason — comfortably longer than the ring's half-period, so the verdict is steady across a whole cycle" % sb._servo_duty)
	if not (sb._radome_qpeak > 0.5):
		return _fail("⭐ …and the RING instrument must still be live beside it (fed |omega_r| = 1.31, got peak %.4f) — three independent `if` blocks, not a chain" % sb._radome_qpeak)
	if sb._gimbal_lost or sb._fov_lost:
		return _fail("…and a VALID frame must latch neither window instrument")
	if sb._ring_channel_key() != ".omega_r":
		return _fail("a RIPPLE wire (ships `radome_slope_az`) must select the YAW channel — slice 28's switch, shared by every HUD site. Got %s" % sb._ring_channel_key())
	# ⚠⚠ THE TWO-RUN INVERSION, DRIVEN: a broken arm's servo meter FALLS, for the same reason its ring
	# meter does. The head HOLDS when it has no error signal, so it demands nothing and never
	# saturates — a FREE-LOOKING servo on a lost track, which is why the latch outranks it above.
	sb._telemetry = _rate_tel(false, 5216.9, 0.0, false, 73.60, -48.60, 1.20)
	for _i in 40:
		sb._airframe3d_on_state({"entities": ents})
	if not sb._gimbal_lost:
		return _fail("⭐ the HEAD's latch must fire on a `gimbal_valid` 0 frame at r = 5217 m")
	if not (sb._servo_duty < 0.5):
		return _fail("⚠⚠ THE TWO-RUN INVERSION MUST BE VISIBLE IN THE INSTRUMENT: on a broken arm the head HOLDS, demands nothing and never saturates, so the duty DECAYS toward free (got %.4f). That is why `lost` outranks it in the verdict — a servo meter reading 'free' on a missile that has lost its target is good news about nothing" % sb._servo_duty)
	# …and `reset` clears all three live instruments (slice 32's post-review finding, fourth use)
	sb._on_reset_pressed()
	if sb._gimbal_lost or sb._radome_qpeak != 0.0 or sb._servo_duty != 0.0:
		return _fail("`reset` must clear the head latch, the peak-hold AND the servo duty (latch %s, peak %.4f, duty %.4f). The duty is the sharper case: its ~0.5 s time constant would carry a PEGGED verdict straight into a re-launch that opens on the LAUNCH TURN — itself the largest slew demand in the engagement — where a stale reading is indistinguishable from a real one" % [sb._gimbal_lost, sb._radome_qpeak, sb._servo_duty])
	print("S35UI_INSTR  three independent instruments on ONE wire (all three keys ship every frame here, unlike slice 34's mutually-exclusive pair): the EMA duty rises past 0.5, the peak-hold rides YAW, the latch fires — and on a BROKEN arm the duty DECAYS back toward free, which is the two-run inversion made visible; `reset` clears all three")

	# ══ TOOTH 6 — every key `_draw_gimbal_rate_hud_lines` reads is PRESENT and scalar ═════════════
	# ⚠ The stale-readout class in its MIRROR form: a missing key silently becoming 0.000 through
	# `get(..., 0.0)`. ⭐ AND THE PAIRS ARE WHAT MATTER — `head_rate_dps` vs `gimbal_rate_dps` (the
	# DEMAND against the CAP, with `head_rate_sat` as the core's own verdict on that comparison) and
	# the ring beside `head_off_deg` (the TRADE). The client compares nothing: it never re-derives
	# `demand > cap`, because a flag built from a re-derived predicate can DISAGREE with the branch it
	# claims to report at exactly the boundary tick where the disagreement is least visible.
	sb._telemetry = _rate_tel(true, 4500.0, 110.19, true, 7.50, 17.50, 1.31)
	sb._airframe3d_on_state({"entities": ents})
	sb._update_readout()
	for k in ["m1.omega_r", "m1.head_rate_dps", "m1.gimbal_rate_dps", "m1.head_rate_sat",
			  "m1.head_off_deg", "m1.gimbal_fov_margin_deg", "m1.radome_slope_est",
			  "m1.radome_slope_worst", "m1.los_range"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ `_draw_gimbal_rate_hud_lines` reads %s — a missing key would `get(..., 0.0)` and print a confident 0.000, the stale-readout class this arc has caught nine times" % k)
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	# ⭐⭐ AND THE HEADLINE PAIR MUST BE TWO NUMBERS THAT DISAGREE — the mechanism made visible. The
	# shipped demand is PRE-LIMIT, which is the entire reason `head_slew_full` exists: a post-hoc
	# difference of the head's own angles would read the CLIPPED motion and report the CAP as the
	# demand, i.e. the answer as the question (measured at the slider's floor: 214.958 against 8.000).
	if not (float(sb._telemetry["m1.head_rate_dps"]) > float(sb._telemetry["m1.gimbal_rate_dps"])):
		return _fail("⭐⭐ the DEMAND must exceed the CAP on a saturated frame — if the two agreed, the client would be drawing the clipped motion twice and the slice would have nothing to show")
	if not (float(sb._telemetry["m1.head_rate_sat"]) >= 0.5):
		return _fail("…and the core's own FLAG must agree with them, since the client is forbidden to re-derive it")
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S35UI_HUD    all nine servo keys present and scalar, and the headline PAIR disagrees as it must (demand 110.19 deg/s against a 40 deg/s cap, with the core's own flag LIT)")

	# ══ TOOTH 7+8 — TWO sliders, BOTH at the interceptor, and the disqualifications ══════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 2:
		return _fail("the slice-35 wire must build EXACTLY TWO sliders (gimbal_rate_dps + radome_slope_est), got %d" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-35 wire must NEVER send set_fidelity — there is no rung; a rate limit is a deterministic bound on an existing servo and `gimbal_rate_dps` is a KNOB (an absent key is bit-identical to no limit)")
	if not keys_set.has("gimbal_rate_dps") or keys_set["gimbal_rate_dps"] != "m1":
		return _fail("the 'gimbal_rate_dps' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	if not keys_set.has("radome_slope_est") or keys_set["radome_slope_est"] != "m1":
		return _fail("the 'radome_slope_est' slider must send set_param at the interceptor m1 — the belief is the missile's. Got %s" % str(keys_set))
	# ⭐⭐ AND THE DISQUALIFICATION THAT IS NEW IS SLICE 34's OWN LIVE SLIDER, dropped here ON A NUMBER.
	if keys_set.has("gimbal_fov_deg"):
		return _fail("⭐⭐ slice 35 must NOT build a 'gimbal_fov_deg' slider, and this is the slice's OWN convention-9 finding rather than an inherited rule — it was slice 34's one live axis. Under a rate limit the binding requirement is the ACQUISITION TURN's, out at LAUNCH RANGE (gate 2 measured `off_band` 1.956 → 2.022 while `off_max` went 1.956 → 8.051 at r ≈ 5700 m, and the same happens on a wire with NO GLASS AT ALL), so a LIVE window would make this wire's break an ACQUISITION break — slice 34's lesson re-run as a third mechanism, and a statement about the HANDOVER BASKET, which is slice 34's FIRST named deferral and a different slice. It is AUTHORED at 25 deg against a worst measured requirement of 19.279 deg over 184 domain cells")
	for bad in ["gimbal_tau_s", "gimbal_stop_deg", "seeker_fov_deg", "cross_speed_mps",
				"radome_slope", "radome_ripple", "radome_ripple_k", "gyro_scale_err", "gyro_bias_z",
				"n_pn", "rho", "sigma_seek", "elevation_deg", "af_alpha_max", "alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 35 must NOT build a '%s' slider. `gimbal_tau_s` is a CONFOUNDED lever (slice 34's gate 2 measured the amplitude sagging with τ and, at the line, that sag crossing the verdict); `gimbal_stop_deg` is a RESTATEMENT of slice 33's excursion and binding it COUPLES the two budgets; `seeker_fov_deg` is refused by the loader outright; `cross_speed_mps` is slice 32's axis and moves the LEAD, hence the demand. The rest move the guidance loop, degrade the lesson beside it, or are DEAD. Got %s" % [bad, str(keys_set.keys())])
	print("S35UI_KNOB   exactly 2 sliders — gimbal_rate_dps and radome_slope_est, BOTH → m1; NOTHING sends set_fidelity; and `gimbal_fov_deg`, slice 34's own live slider, is asserted ABSENT")

	# ══ TOOTH 9 — ⭐ THE MIRROR: a slice-34 wire keeps slice 34's branch, unchanged ═══════════════
	# The new branch is inserted AHEAD of slice 34's, so the mirror is what proves it is a SWITCH and
	# not an `or` — slice 33's tooth and slice 34's, one slice on.
	_sb34 = _build_sandbox()
	_sb34._on_scenario({
		"name": "slice34_gimbal", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_fov_deg", "min": 1.0, "max": 8.0, "value": 4.0,
				   "label": "SEEKER: detector window (deg)"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03,
				   "value": -0.18, "label": "DESIGN: believed slope R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb34._gimbal_rate_view:
		return _fail("⭐ THE MIRROR: a slice-34 wire must NOT raise `gimbal_rate_view` — if it did, the branch selector would select BOTH wires and slice 34's HUD would be the one that disappears")
	if not _sb34._gimbal_view:
		return _fail("…and it must still raise `gimbal_view`, or the mirror is not slice 34's wire at all")
	if _sb34._mode != sb._mode or _sb34._prop_btn.visible != sb._prop_btn.visible:
		return _fail("⚠ the two wires must be indistinguishable by ROUTING — the same 3-D view and the same dropped button. What separates them is the HUD BRANCH alone. Got modes %s/%s" % [_sb34._mode, sb._mode])
	# ⚠ AND SLICE 34's OWN INSTRUMENTS MUST STILL WORK — the new `if` block is gated on the slice-35
	# telemetry key, so a slice-34 wire's servo duty must stay structurally DEAD rather than defaulting.
	_sb34._telemetry = {"m1.los_range": 4500.0, "m1.gimbal_valid": 1.0, "m1.gimbal_fov_deg": 4.0,
						"m1.gimbal_stop_deg": 30.0, "m1.gimbal_fov_margin_deg": 2.05,
						"m1.head_angle_deg": 20.62, "m1.head_off_deg": 5.24,
						"m1.look_angle": 20.62, "m1.look_body_deg": 17.83,
						"m1.radome_slope": -0.03, "m1.radome_slope_est": -0.18,
						"m1.radome_slope_worst": -0.32999999999999996, "m1.radome_residual": 0.15,
						"m1.radome_residual_az": -0.05, "m1.radome_slope_az": -0.23,
						"m1.radome_eps": 0.0005, "m1.aero_sat": 0.0, "m1.alpha": 0.12,
						"m1.omega_q": 0.10, "m1.omega_r": 1.31,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	for _i in 40:
		_sb34._airframe3d_on_state({"entities": ents})
	if _sb34._servo_duty != 0.0:
		return _fail("⚠ a slice-34 wire ships NO `head_rate_sat`, so the servo duty must stay EXACTLY 0 by its PRESENCE gate and not by a value that happens to be false. Got %.4f" % _sb34._servo_duty)
	if not (_sb34._radome_qpeak > 0.5):
		return _fail("⭐ …and slice 34's own ring instrument must be undisturbed by the new block (fed |omega_r| = 1.31, got %.4f)" % _sb34._radome_qpeak)
	print("S35UI_MIRROR a slice-34 wire keeps `gimbal_view` WITHOUT `gimbal_rate_view`, routes identically, keeps its own instruments, and its servo duty stays EXACTLY 0 by presence gate")

	# ══ TOOTH 10 — THE VALUE-GUARD, EIGHTEEN-WAY ═════════════════════════════════════════════════
	# (a) ⭐ slice 33 — BOTH of the older markers, no head: still its own composition branch
	_sb33 = _build_sandbox()
	_sb33._on_scenario({
		"name": "s33_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"radome_view": true, "seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 19.0, "max": 40.0, "value": 21.0, "label": "FOV"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb33._gimbal_rate_view or _sb33._gimbal_view or not (_sb33._radome_view and _sb33._seeker_fov_view):
		return _fail("a slice-33 wire must carry BOTH older markers and NEITHER head marker")
	# (b) slice 32 — FOV only
	_sb32 = _build_sandbox()
	_sb32._on_scenario({
		"name": "s32_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 18.5, "max": 40.0, "value": 25.0, "label": "FOV"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb32._gimbal_rate_view or _sb32._gimbal_view or _sb32._radome_view or not _sb32._seeker_fov_view:
		return _fail("a slice-32 wire must carry seeker_fov_view ALONE")
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
	if _sb31._gimbal_rate_view or _sb31._gimbal_view or _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view ALONE")
	# ⭐ AND ITS PEAK-HOLD MUST STILL LATCH ON PITCH — the new branch is inserted AHEAD of two others
	# and must not have disturbed the oldest (the mirror of tooth 5).
	_sb31._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.omega_r": 0.02,
						"m1.radome_slope": -0.10, "m1.radome_eps": -0.0004, "m1.look_angle": 13.6,
						"m1.radome_residual": 0.0, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb31._airframe3d_on_state({"entities": ents})
	if not (_sb31._radome_qpeak > 0.5):
		return _fail("⭐ the radome-only MIRROR must still latch its PITCH peak-hold (fed |omega_q| = 1.31, no `radome_slope_az`) — got %.4f" % _sb31._radome_qpeak)
	if _sb31._servo_duty != 0.0 or _sb31._gimbal_lost or _sb31._fov_lost:
		return _fail("the radome-only MIRROR must latch no window instrument and must keep the servo duty at EXACTLY 0")
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
		return _fail("slices 16 and 35 both drop the button but must NOT share a mode (16 = 2-D spatial, 35 = 3-D airframe3d)")
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
	print("S35UI_GUARD  eighteen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 31 radome-only / 32 FOV-only / 33 BOTH-older / 34 gimbal-no-rate / 35 gimbal+rate — plus the no-marker mirror")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..34_ui_test contract) --------------------------------------------

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
	print("S35UI OK: slice 34's head was INFINITELY FAST; a real gimbal has a servo with a maximum " +
		"slew rate, and the moment it does the head's motion stops being free — it becomes a RESOURCE " +
		"spent against a demand the PARASITIC LOOP sets. ⚠⚠ THE CLIENT HALF OF THIS SLICE IS A MARKER " +
		"WHOSE JUSTIFICATION IS WEAKER THAN SLICE 34's, AND SAYING SO IS THE POINT. The marker-hole " +
		"re-check the plan demanded came back NEGATIVE: a slice-35 wire is a slice-34 wire PLUS one " +
		"key, so `gimbal_view` is raised, the head branch takes it, and the SUBJECT is right. Slice " +
		"34's marker plugged a REAL HOLE (a loader refusal re-routing its wire into the radome " +
		"cascade); this one is a BRANCH SELECTOR, and the two must not be taught as one rule. " +
		"⭐⭐ WHAT GOES WRONG WITHOUT IT IS AN INVISIBLE SLICE, NOT A WRONG NUMBER: slice 34's verdict " +
		"pairs the tracking error against the DETECTOR WINDOW, which is AUTHORED WIDE here (25 deg " +
		"against a worst measured requirement of 19.279 deg over 184 domain cells) and NEVER BINDS, " +
		"so it reports a comfortable budget, names the INDEX, and never mentions the servo — every " +
		"number TRUE. ⭐⭐ AND ON ONE STATE IT IS WORSE THAN SILENT, which is the sharpest tooth here: " +
		"when a slow servo has BOUGHT the ring down, slice 34's helper reads 'SELF-INDEXED — the loop " +
		"is quiet', crediting the INDEX for a quiet the BANDWIDTH paid for. The two helpers are called " +
		"on the SAME numbers and asserted to disagree, and slice 34's is left VERBATIM and still " +
		"correct on its own wire. ⭐ THE VERDICT IS A PURE HELPER (the only reason it is testable at " +
		"all, since `_draw` never runs headless — convention 14; slice 31's aim-point comparison " +
		"shipped WRONG and only a windowed shot caught it) and it is a 2x2 ON TWO BOOLEANS rather than " +
		"a cascade on one, because THE WHOLE SLICE IS THAT THE TWO MOVE IN OPPOSITE DIRECTIONS: both " +
		"MIXED states are named, all five are pinned, the duty threshold is driven from both sides, " +
		"and the LATCH is proven to outrank all FOUR corners — a broken window freezes the index " +
		"(quiet at every R̂) AND a held head demands nothing (a free-looking servo), so both " +
		"instruments read as good news on a missile that has lost its target. ⭐ THE NEW INSTRUMENT IS " +
		"A THIRD SHAPE beside slice 27's decaying peak-hold and slice 32's latch — an EMA DUTY — and " +
		"the shape is EARNED: a rate limit binds on a FRACTION of ticks (8.2 / 65.2 / 97.0 % at the " +
		"slider's ceiling, default and floor), so an instantaneous read would flicker with the ~2 Hz " +
		"ring and a latch would go true on every arm and stay. All THREE instruments are live on ONE " +
		"wire as INDEPENDENT `if` blocks — and slice 33's finding matters MORE here than it did there, " +
		"because unlike slice 34's mutually-exclusive pair all three keys ship on EVERY frame, so a " +
		"chained dispatch would freeze one outright. The two-run inversion is DRIVEN, not described: " +
		"on a broken arm the duty DECAYS back toward free. `reset` clears all three, and the duty is " +
		"the sharper case (its ~0.5 s constant would carry a PEGGED verdict into a re-launch that " +
		"opens on the LAUNCH TURN, itself the largest slew demand in the engagement). ⭐⭐ THE HEADLINE " +
		"PAIR IS DEMAND BESIDE CAP and the two must DISAGREE on a saturated frame: the shipped demand " +
		"is PRE-LIMIT, which is the entire reason `head_slew_full` exists, and the client never " +
		"re-derives the comparison because a flag built from a re-derived predicate can disagree with " +
		"the branch it claims to report. TWO sliders are built, BOTH at the interceptor, and NOTHING " +
		"sends set_fidelity; `gimbal_fov_deg` — slice 34's OWN live axis — is asserted ABSENT, dropped " +
		"here on a NUMBER rather than an argument. ⭐ AND THE SLICE-34 MIRROR PROVES THE NEW BRANCH IS " +
		"A SWITCH AND NOT AN `or`: it keeps `gimbal_view` without `gimbal_rate_view`, routes " +
		"identically, keeps its own instruments, and its servo duty stays EXACTLY 0 by PRESENCE gate. " +
		"The value-guard holds EIGHTEEN ways.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S35UI FAIL: " + msg)
	print("S35UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb34, _sb33, _sb32, _sb31, _sb25, _sb24, _sb23, _sb19,
			   _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
