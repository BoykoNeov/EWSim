extends SceneTree
# Headless UI test for the slice-36 HANDOVER BASKET view routing + HUD — the piece slice36_verify.gd
# can't reach. The verifier drives SimClient directly (the set_param wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing, the two new
# instruments, or the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A **BUTTON THAT COMES BACK**, AND THAT IS NEW IN THIS FAMILY. Slice 33
# found — and 34 and 35 inherited — that the shared fidelity button needed no edit, because `radome_view`
# was already raised and already dropped it at both sites. ⚠⚠ THAT FREE RIDE ENDS HERE, AND THE REASON
# IS INTERNAL TO THIS SLICE: `radome_view` is keyed on authored GLASS, and slice 36's wires carry NONE
# (a handover error is EXACTLY inert on the trajectory without a window or an index, so the wire that
# isolates the basket is a radome-free wire). `seeker_fov_view` is absent too — the loader REFUSES
# `seeker_fov_deg` beside a head. So BOTH drop-branches in `_enter_airframe3d_mode` fail, its dispatch
# falls through to slice 25's `seeker_axes` cycler, and the button RETURNS — whose other position
# (`:pitch_plane`) leaves the handover error live beside slice 25's unrelated 2000 m blind miss. Slice
# 26's argument, and the drop needs BOTH sites (its 4th occurrence), because `_update_fid_btn`'s
# `"seeker_axes"` arm re-shows the button unconditionally and never reaches the `"airframe"` arm's
# defences.
#
# ⭐⭐ AND THE HOLE HAS A SECOND HALF: WITHOUT THE MARKER, SLICE 35's HUD PRINTS TWO ZEROS OF GLASS THAT
# DOES NOT EXIST. `gimbal_rate_view` IS raised here (the servo is this slice's one slider), so slice 35's
# block takes the wire — and its line 4, the one its own comment calls THE CURE, reads
# `radome_slope_est` and `radome_slope_worst`. Neither is shipped on a radome-free wire, so it renders
# `R̂ +0.000   aim point R₀+2A +0.000`. ⇒ not slice 35's INVISIBLE SLICE (every number true, the subject
# unmentioned) but an invisible slice PLUS two fabricated numbers: the stale-readout class's 9th
# occurrence, landing on another slice's payoff line.
#
# THE TEETH, in order of what would actually break:
#   1. a slice-36 handshake routes to _mode=airframe3d, button HIDDEN at BOTH sites
#   2. ⭐⭐ THE BUTTON COMES BACK: strip the marker and the seeker_axes cycler takes the wire
#   3. ⭐⭐ THE FABRICATED ZEROS: the keys slice 35's cure line reads are ABSENT on this wire
#   4. ⭐ the VERDICT pinned in all FOUR states, with the DIAGONAL (perfect+lost vs biased+held) named
#   5. ⭐⭐ THE DISPLAY FREEZE, driven with the 179.4998 deg endgame sample — the only headless proof
#   6. ⭐ the REQUIREMENT text: a requirement on a held arm, a POST-BREAK RUNAWAY on a broken one, and
#      never a subtracted margin (gate 2 measured that key and DROPPED it)
#   7. the two new instruments: the range-gated FREEZE and the one-shot BIRTH latch, cleared by reset
#   8. every key `_draw_handover_hud_lines` reads is present and scalar
#   9. ONE slider at the interceptor driving set_param; NOTHING sends set_fidelity; the AUTHORED key is
#      asserted absent as a slider (it is structurally dead and the loader refuses it BY NAME)
#  10. ⭐ THE MIRROR: a slice-35 wire must NOT raise the new marker, and must keep its own HUD + button
#  11. the value-guard, NINETEEN-WAY
#
# Run:  godot --headless --path clients/godot --script res://net/slice36_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb35
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

# The slice-36 wire's telemetry, at the numbers the verifier measures. ⚠⚠ NOTE WHAT IS **NOT** HERE:
# there is not one `radome_*` key, because this wire has NO GLASS. That absence is the whole reason the
# new marker exists — slice 35's inherited HUD would `get(..., 0.0)` two of them and print a cure.
func _hand_tel(valid: bool, los: float, off: float, margin: float, peak: float, az: float,
			   dem: float, sat: bool, err: float) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 10.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": margin,
		"m1.gimbal_rate_dps": 8.0,
		"m1.gimbal_handover_err_deg": err,       # …the basket's coordinate, SIGNED
		"m1.head_off_deg": off,
		"m1.head_off_peak_deg": peak,            # …the REQUIREMENT (a running max)
		"m1.head_rate_dps": dem,
		"m1.head_rate_sat": 1.0 if sat else 0.0,
		"m1.head_angle_deg": 18.12,
		"m1.look_angle": 18.12,
		"m1.look_body_deg": absf(az),            # the `hypot` — it cannot show the sign
		"m1.look_body_az_deg": az,               # …and the SIGNED azimuth, which is the mechanism
		"m1.lead_angle_deg": 18.13,
		"m1.aero_sat": 0.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.02, "m1.omega_r": 0.03,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _hand_handshake(marker: bool, err: float) -> Dictionary:
	var h := {
		"name": "slice36_handover" if absf(err) < 1.0e-9 else "slice36_biased",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "gimbal_rate_dps", "min": 8.0, "max": 60.0, "value": 8.0,
			 "label": "SERVO: max head slew (deg/s) — drag UP to buy back the track a perfect handover lost"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["gimbal_handover_view"] = true
	return h

func _initialize() -> void:
	print("S36UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_hand_handshake(true, 0.0))
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]

	# ══ TOOTH 1 — ROUTE: slice 23's 3-D view, and the button DROPPED for the TWELFTH time ═════════
	if sb._mode != "airframe3d":
		return _fail("a slice-36 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_handover_view:
		return _fail("the client must record the `gimbal_handover_view` handshake marker")
	if not (sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("a slice-36 wire is a slice-35 wire MINUS THE GLASS plus one key — it still carries a rate-limited HEAD, so both of those markers must be recorded. Got gim=%s rate=%s" % [sb._gimbal_view, sb._gimbal_rate_view])
	# ⭐⭐ THE TWO ABSENCES ARE THE FINDING, asserted as the POSITIVE facts they are.
	if sb._radome_view:
		return _fail("⭐⭐ a slice-36 wire must NOT carry `radome_view` — it has NO GLASS, and that absence is exactly why the button drop stopped being free (slices 26–35 all rode this marker for it)")
	if sb._seeker_fov_view:
		return _fail("⚠ a slice-36 wire must NOT carry `seeker_fov_view` — the loader REFUSES `seeker_fov_deg` beside a head")
	if sb._prop_btn.visible:
		return _fail("a slice-36 handshake must DROP the shared button — there is no rung to cycle (the lesson is an AUTHORED pair of wires plus ONE servo slider, and the authored key is structurally a dead knob). Slice-16's Option-P′, TWELFTH use — and the FIRST that needed an edit")
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("dropping the button must NOT skip _build_airframe3d_scene — slice 36 reuses the slice-23 3-D view wholesale")
	# ⚠⚠ AND THE DROP NEEDS AN EDIT AT **BOTH** SITES HERE, unlike 33/34/35 — slice 26's finding, 4th
	# occurrence. This is the second site, and without its arm the `_fidelity.has("airframe")` branch
	# re-shows the button that `_enter_airframe3d_mode` just dropped.
	sb._update_fid_btn()
	if sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button hidden — the scenario carries an `:airframe` fidelity (HELD at six_dof), so the generic arm would re-show what _enter_airframe3d_mode dropped. ⚠ On slices 33/34/35 `radome_view` did this for free; with no glass this arm is LOAD-BEARING")
	print("S36UI_ROUTE  airframe3d + gimbal_handover_view recorded, radome_view and seeker_fov_view BOTH correctly ABSENT, button HIDDEN at BOTH sites — and here BOTH edits are load-bearing for the first time since slice 26")

	# ══ TOOTH 2 — ⭐⭐ THE BUTTON COMES BACK: strip the marker and slice 25's cycler takes it ═══════
	# ⚠⚠ THE OPPOSITE SHAPE TO SLICE 35's MIRROR. There, stripping the marker changed nothing about the
	# routing and the failure was an INVISIBLE SLICE. Here the routing itself moves: with no glass there
	# is no `radome_view` to drop the button, so the dispatch reaches `_fidelity.has("seeker_axes")` and
	# a CYCLER appears on a wire whose other rung position (`:pitch_plane`) would leave the handover
	# error live beside slice 25's unrelated 2000 m blind miss — two mechanisms in one view.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_hand_handshake(false, 0.0))
	if _sb_nomarker._gimbal_handover_view:
		return _fail("the no-marker mirror must NOT record gimbal_handover_view")
	if not _sb_nomarker._prop_btn.visible:
		return _fail("⭐⭐ THE HOLE: without `gimbal_handover_view` the button must COME BACK (this is the first no-glass wire of the arc, so `radome_view` is absent and both drop-branches fail). If it stays hidden, something else is dropping it and this marker's button half is not the load-bearing thing this file claims")
	if _sb_nomarker._fid_kind != "seeker_axes":
		return _fail("⭐⭐ …and it must come back as SLICE 25's cycler specifically (got kind=%s) — that is what makes it dangerous rather than merely wrong: its other position leaves the handover live beside a 2000 m blind miss" % _sb_nomarker._fid_kind)
	if _sb_nomarker._mode != sb._mode:
		return _fail("⚠ the two must still share the VIEW (the 3-D airframe scene) — what the marker changes is the button and the HUD branch, not the mode. Got %s/%s" % [_sb_nomarker._mode, sb._mode])
	print("S36UI_HOLE   without the marker the button RETURNS as slice 25's seeker_axes cycler (kind=%s, visible) — the free ride slices 26–35 had on `radome_view` ends with the glass" % _sb_nomarker._fid_kind)

	# ══ TOOTH 3 — ⭐⭐ THE FABRICATED ZEROS: slice 35's cure line reads keys that DO NOT EXIST ══════
	# The HUD half of the hole, and it is a stale-readout defect rather than slice 35's invisible-slice
	# one. `gimbal_rate_view` is raised here, so without the new branch slice 35's block draws the wire —
	# and its line 4 reads these two keys through `get(..., 0.0)`.
	sb._telemetry = _hand_tel(true, 4500.0, 7.50, 2.50, 8.84, -12.12, 6.20, false, 0.0)
	for absent in ["m1.radome_slope_est", "m1.radome_slope_worst", "m1.radome_residual",
				   "m1.radome_slope", "m1.radome_eps"]:
		if sb._telemetry.has(absent):
			return _fail("⭐⭐ a slice-36 wire must ship NO `%s` — slice 35's HUD reads two of these on its CURE line, so their absence is what turns a mis-branch into `R̂ +0.000   aim point R₀+2A +0.000`: the stale-readout class's 9th occurrence, on another slice's payoff line" % absent)
	# ⚠ AND THE RING INSTRUMENT IS STRUCTURALLY DEAD HERE TOO, by its own presence gate — so slice 35's
	# trade line would show a calm number beside those two zeros and nothing would be lit.
	for _i in 40:
		sb._airframe3d_on_state({"entities": ents})
	if sb._radome_qpeak != 0.0:
		return _fail("⚠ `_radome_qpeak` is gated on `.radome_residual`, which this wire never ships, so it must stay EXACTLY 0.0 (got %.6f) — that is the other half of what makes slice 35's branch silent here" % sb._radome_qpeak)
	print("S36UI_ZEROS  every glass key slice 35's cure line reads is ABSENT, and `_radome_qpeak` stays exactly 0.0 by presence gate — so the mis-branch would print two fabricated zeros, not merely stay silent")

	# ══ TOOTH 4 — ⭐ THE VERDICT, PINNED IN ALL FOUR STATES, AND THE DIAGONAL IS THE HEADLINE ══════
	# ⚠⚠ THE PAIR A STUDENT READS OFF ONE LINE is PERFECT-AND-LOST (the foil wire at its default servo,
	# missing by 3290 m) beside BIASED-AND-HELD (the twin, 0.191 m at the SAME servo behind the SAME
	# window). A verdict built on `lost` alone would print the same string on both halves of the pair.
	if sb._handover_verdict_label(true, 0.0) != "PERFECT HANDOVER — TRACK LOST":
		return _fail("⭐⭐ the FOIL's state: handed over exactly right, and the track is gone. Got '%s'" % sb._handover_verdict_label(true, 0.0))
	if sb._handover_verdict_label(false, -6.0) != "BIASED HANDOVER — track HELD":
		return _fail("⭐⭐ the SHIP's state: 6 deg 'wrong' and it keeps the track. Got '%s'" % sb._handover_verdict_label(false, -6.0))
	if sb._handover_verdict_label(true, -12.0) != "TOO MUCH BIAS — TRACK LOST":
		return _fail("⭐ the OTHER side of the basket — too much bias breaks it too, which is what makes it a BASKET rather than a direction. Got '%s'" % sb._handover_verdict_label(true, -12.0))
	if sb._handover_verdict_label(false, 0.0) != "ON THE LOS — the servo kept up":
		return _fail("⭐ and the CURE: the same perfect handover with a fast enough servo. Got '%s'" % sb._handover_verdict_label(false, 0.0))
	# ⚠ THE DIAGONAL, ASSERTED AS A DISAGREEMENT: the two halves of the shipped pair must not read alike.
	if sb._handover_verdict_label(true, 0.0) == sb._handover_verdict_label(false, -6.0):
		return _fail("⚠ the two shipped wires must produce DIFFERENT verdicts at the same servo — that difference IS the slice")
	# ⚠ AND SLICE 34's AND 35's HELPERS ARE LEFT VERBATIM AND ARE STILL RIGHT ON THEIR OWN WIRES, so the
	# defect this branch fixes is the BRANCH and not the helpers (slice 34/35 each made this assert too).
	if sb._servo_verdict_label(false, false, 0.0) != "FREE — the servo costs nothing":
		return _fail("slice 35's helper must be UNCHANGED")
	if sb._gimbal_verdict_label(false, -1.2, 3000.0, false) != "ERROR PAST THE WINDOW — breaking":
		return _fail("slice 34's helper must be UNCHANGED")
	# ⭐⭐ AND ON THIS WIRE SLICE 35's HELPER IS NOT MERELY SILENT — IT BLAMES THE SERVO. At the foil's
	# default the servo is NOT pegged (the head holds once the track is lost, so it demands nothing —
	# slice 35's own two-run inversion), so its helper reads the LATCH and names the head letting go,
	# with no way to say that the HANDOVER is what put it there.
	var s35_foil: String = sb._servo_verdict_label(true, false, 0.0)
	if s35_foil == sb._handover_verdict_label(true, 0.0):
		return _fail("⭐⭐ THE TWO HELPERS MUST DISAGREE ON THE FOIL's OWN NUMBERS — that disagreement is why the branch exists. Both returned '%s'" % s35_foil)
	if s35_foil.contains("HANDOVER"):
		return _fail("…and slice 35's must NOT name the handover (it cannot see it), got '%s'" % s35_foil)
	print("S36UI_VERDICT all four states pinned, the DIAGONAL named (perfect+lost vs biased+held), and slice 35's helper says '%s' where this slice's says '%s' — it cannot name the handover at all" % [s35_foil, sb._handover_verdict_label(true, 0.0)])

	# ══ TOOTH 5 — ⭐⭐ THE DISPLAY FREEZE, AND THIS IS THE ONLY HEADLESS PROOF IT WILL EVER HAVE ════
	# `head_off_peak_deg` is a RUNNING MAXIMUM, so it reads the clean requirement unchanged from
	# r = 3000 m down to r = 200 m and then runs to ~179.4998 deg AT CPA ON EVERY ARM, HIT OR MISS,
	# because the target is behind the head by then. A PEAK CANNOT FORGET. A HUD printing the raw key
	# would therefore end every clean intercept displaying a 179 deg "requirement" — slice 19's lying
	# picture in a new widget — which is why the range is an ARGUMENT to a pure helper (convention 14:
	# `_draw` never runs headless, and slice 31's aim-point comparison shipped WRONG with only a
	# windowed shot to catch it).
	if sb._handover_peak_hold(8.84, 9.51, 3000.0) != 9.51:
		return _fail("the freeze must UPDATE while r > 200 m")
	if sb._handover_peak_hold(8.84, 9.51, 200.1) != 9.51:
		return _fail("…including just above the gate (r = 200.1 m)")
	if sb._handover_peak_hold(8.84, 179.4998, 200.0) != 8.84:
		return _fail("⭐⭐ THE ENDGAME: at r = 200 m and below the display must HOLD its last approach value (8.84) rather than take the %.4f deg CPA swing. Got %.4f" % [179.4998, sb._handover_peak_hold(8.84, 179.4998, 200.0)])
	if sb._handover_peak_hold(8.84, 179.4998, 0.19) != 8.84:
		return _fail("…and at the CPA itself (r = 0.19 m, a HITTING arm), which is where the raw key reads 179.4998 deg on EVERY arm")
	print("S36UI_FREEZE the requirement's display holds its last r > 200 m sample (8.84) against the 179.4998 deg CPA value the raw key takes on every arm, hit or miss — the range is an ARGUMENT, so this is provable headless")

	# ══ TOOTH 6 — ⭐ THE REQUIREMENT TEXT, AND WHAT IT DELIBERATELY DOES NOT PRINT ═════════════════
	# ⚠⚠ THE TWO-RUN DISCIPLINE's FIFTH QUANTITY, FAILING **LARGE**: on a broken arm the peak is the
	# POST-BREAK RUNAWAY (104.56 / 65.79 / 73.77 deg against real requirements of 12.346 / 10.000 /
	# 18.000), where slice 34's frozen `head_angle_deg` failed plausibly-but-TOO-SMALL. The text must say
	# which it is, or a reader over-designs by ~8x.
	var t_held: String = sb._handover_req_text(8.84, 10.0, false)
	var t_broke: String = sb._handover_req_text(104.56, 10.0, true)
	if not (t_held.contains("requirement") and t_held.contains("8.84") and t_held.contains("10.0")):
		return _fail("a HELD arm's line must pair the requirement WITH the window, both numbers on screen. Got '%s'" % t_held)
	if t_held.contains("OVER"):
		return _fail("…and must not flag a requirement that is inside the window. Got '%s'" % t_held)
	if not (t_broke.contains("POST-BREAK") and t_broke.contains("NOT a requirement")):
		return _fail("⚠⚠ a BROKEN arm's line must say outright that the number is NOT a requirement — it is the runaway, and it fails LARGE. Got '%s'" % t_broke)
	if t_broke.contains("requirement (peak)"):
		return _fail("…and must not present it as one anyway. Got '%s'" % t_broke)
	# ⭐ THE OVER-WINDOW MARKER, on the state where a requirement exceeds its window while still held
	# (reachable at the bracket's own cells): a MARKER, never a subtracted degree count.
	if not sb._handover_req_text(10.33, 10.0, false).contains("OVER"):
		return _fail("⭐ a requirement above the window must be MARKED. Got '%s'" % sb._handover_req_text(10.33, 10.0, false))
	# ⚠⚠ AND IT MUST NEVER PRINT THE DIFFERENCE. A signed peak MARGIN was drafted at gate 2, MEASURED and
	# DROPPED: it latches negative on the first breached tick and never recovers, which fires on 100 % of
	# arms INCLUDING every hit (the endgame breaches any window). Subtracting the two here would rebuild
	# exactly that dropped key in GDScript.
	if t_held.contains("1.16") or t_held.contains("LEFT"):
		return _fail("⚠⚠ the requirement line must show the PAIR and never their DIFFERENCE — a peak MARGIN was measured and DROPPED at gate 2 because a latch that fires on every arm is not a verdict. Got '%s'" % t_held)
	print("S36UI_REQ    the requirement line pairs %s; on a broken arm it reads '%s' — and it never subtracts the two, because that key was measured and dropped" % [t_held, t_broke])

	# ══ TOOTH 6b — ⭐⭐ THE MECHANISM LINE, AND THIS BRANCH WAS FOUND BY THE WINDOWED SHOT ════════════
	# ⚠⚠ THE SIXTH QUANTITY OF THE TWO-RUN DISCIPLINE. The verifier measures the body-frame LOS azimuth
	# spanning 33.182 deg on an arm that HELD and 110.473 deg (~3.3x) on the shipped BROKEN one — a
	# missile that has lost its track is in a runaway geometry. Shot A's FIRST capture printed
	# `handover +0.0°   body LOS az −39.18°  (first frame +18.00°)`: three LIVE, TRUE numbers that a
	# reader subtracts into a 57 deg "excursion" which is not the mechanism at all. That is slice 33's
	# defect in a new quantity — the verdict above it was already correct and the INVITED ARITHMETIC was
	# wrong — and it is exactly what a windowed shot exists to catch (headless never runs `_draw`).
	var l_held: String = sb._handover_los_text(-6.0, -12.12, 18.00, false)
	var l_lost: String = sb._handover_los_text(0.0, -39.18, 18.00, true)
	if not (l_held.contains("from") and l_held.contains("18.00")):
		return _fail("⭐ on a HELD arm the line must show the live azimuth BESIDE the birth angle — without the pair the 33.2 deg excursion that IS the mechanism never appears on screen. Got '%s'" % l_held)
	if not l_lost.contains("RUNNING AWAY"):
		return _fail("⭐⭐ on a BROKEN arm it must SAY the azimuth is running away. Got '%s'" % l_lost)
	if l_lost.contains("18.00"):
		return _fail("⚠⚠ …and it must NOT offer the birth angle there, because the subtraction a reader would do is the runaway and not the journey (110.473 deg against the mechanism's 33.182). Got '%s'" % l_lost)
	# ⚠⚠ AND BOTH FORMS MUST FIT THE MEASURED WIDTH — ~55 characters at 15 px from `vp.x − 430`. The
	# first retake of shot A ran 67 characters and the right edge ate "…RUNNING AWAY sin", which is the
	# 3rd occurrence of that overrun after slices 26 and 28. A clause that does not print is not a proof.
	for s in [l_held, l_lost]:
		if s.length() > 55:
			return _fail("⚠⚠ the HUD line must fit ~55 characters at 15 px (got %d): '%s'" % [s.length(), s])
	print("S36UI_MECH   the mechanism line pairs live-vs-birth on a HELD arm and withdraws the pair on a broken one ('%s') — the shot found this branch, which is what the shot is for" % l_lost)

	# ══ TOOTH 7 — the two new instruments: a range-gated FREEZE and a one-shot BIRTH latch ════════
	# ⚠ TWO INDEPENDENT `if` BLOCKS, not a chain and not an `elif` on slice 35's duty block — slice 33's
	# finding, and here all three keys ship on EVERY frame, so a chained dispatch would freeze one
	# outright rather than merely being fragile. ⭐ A FOURTH instrument shape beside slice 27's decaying
	# peak-hold, slice 32's latch and slice 35's EMA duty: a RANGE-GATED FREEZE.
	var sb2 = _build_sandbox()
	sb2._on_scenario(_hand_handshake(true, 0.0))
	if sb2._handover_peak != 0.0 or not is_nan(sb2._handover_los0):
		return _fail("both instruments must start clear — the peak at 0.0 and the birth latch at NAN")
	sb2._telemetry = _hand_tel(true, 4500.0, 7.50, 2.50, 8.84, 18.11, 6.20, false, 0.0)
	sb2._airframe3d_on_state({"entities": ents})
	if not (absf(sb2._handover_peak - 8.84) < 1.0e-9):
		return _fail("the freeze must take the shipped peak while r > 200 m (got %.4f)" % sb2._handover_peak)
	if not (absf(sb2._handover_los0 - 18.11) < 1.0e-9):
		return _fail("⭐ the BIRTH latch must take the FIRST frame's signed azimuth (got %.4f) — without it the live azimuth has nothing to be measured against and the 33.2 deg excursion never appears on screen" % sb2._handover_los0)
	# …and the latch is ONE-SHOT: later frames move the live value and must NOT move the birth angle.
	sb2._telemetry = _hand_tel(true, 1500.0, 8.84, 1.16, 8.84, -12.12, 4.10, false, 0.0)
	sb2._airframe3d_on_state({"entities": ents})
	if not (absf(sb2._handover_los0 - 18.11) < 1.0e-9):
		return _fail("the birth latch must be ONE-SHOT (got %.4f after a frame at %.2f deg) — a latch that tracked would pair the live azimuth against itself and the excursion would read zero" % [sb2._handover_los0, -12.12])
	# ⭐⭐ THE ENDGAME, DRIVEN THROUGH THE STATE PATH rather than only through the helper: a CPA frame
	# ships the 179.4998 deg running max and the displayed requirement must not move.
	sb2._telemetry = _hand_tel(true, 0.19, 179.4998, -169.5, 179.4998, -15.15, 0.0, false, 0.0)
	sb2._airframe3d_on_state({"entities": ents})
	if not (absf(sb2._handover_peak - 8.84) < 1.0e-9):
		return _fail("⭐⭐ a CPA frame must NOT move the displayed requirement (got %.4f, expected the frozen 8.84) — the raw key reads 179.4998 deg there on every arm and a peak cannot forget" % sb2._handover_peak)
	# …and `reset` clears BOTH (slice 32's post-review finding, fifth use). ⚠ The birth latch must return
	# to NAN and not to 0.0: an azimuth of exactly 0.000000 deg is a REAL birth angle (it is what
	# err = −18.105 produces, the declared domain's own lower endpoint), so a zero sentinel would be
	# indistinguishable from the arm the domain is bounded by.
	sb2._on_reset_pressed()
	if sb2._handover_peak != 0.0 or not is_nan(sb2._handover_los0):
		return _fail("`reset` must clear the frozen requirement AND the birth latch (got peak %.4f, los0 %.4f). A stale peak would carry the previous run's ~105 deg post-break runaway through a whole re-launch, and a stale birth angle would silently misreport the excursion" % [sb2._handover_peak, sb2._handover_los0])
	sb2.free()
	print("S36UI_INSTR  the FREEZE takes the peak while r > 200 m and holds it through a 179.4998 deg CPA frame; the BIRTH latch is ONE-SHOT and returns to NAN (not 0.0 — a 0.000000 deg birth angle is real) on reset")

	# ══ TOOTH 8 — every key `_draw_handover_hud_lines` reads is PRESENT and scalar ════════════════
	# ⚠ The stale-readout class in its MIRROR form: a missing key silently becoming 0.000 through
	# `get(..., 0.0)` — which is exactly what the ABSENT glass keys of tooth 3 would do in slice 35's
	# block. ⭐ AND THE PAIRS ARE WHAT MATTER: the authored error beside the live signed azimuth (WHERE
	# THE HEAD WAS PUT against WHERE THE LOS WENT — the mechanism), and the requirement beside the
	# window (slice 32's predicate, in the basket's own currency).
	sb._telemetry = _hand_tel(true, 4500.0, 7.50, 2.50, 8.84, -12.12, 6.20, false, 0.0)
	sb._airframe3d_on_state({"entities": ents})
	sb._update_readout()
	for k in ["m1.gimbal_handover_err_deg", "m1.look_body_az_deg", "m1.head_off_peak_deg",
			  "m1.gimbal_fov_deg", "m1.head_off_deg", "m1.gimbal_fov_margin_deg",
			  "m1.head_rate_dps", "m1.gimbal_rate_dps", "m1.head_rate_sat", "m1.los_range"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ `_draw_handover_hud_lines` reads %s — a missing key would `get(..., 0.0)` and print a confident 0.000, the stale-readout class this arc has caught nine times" % k)
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	# ⭐ AND THE SIGNED KEY MUST BE ABLE TO BE NEGATIVE WHERE THE `hypot` BESIDE IT CANNOT — the sign
	# trap pinned in the client too (gate 0's first mechanism story was inferred from that hypot and was
	# WRONG: the #1 SIGN TRAP's 10th occurrence).
	if not (float(sb._telemetry["m1.look_body_az_deg"]) < 0.0):
		return _fail("⭐ the mechanism's number must be SIGNED and reach the client negative mid-approach")
	if not (float(sb._telemetry["m1.look_body_deg"]) > 0.0):
		return _fail("…while the `hypot` beside it stays positive on the same frame — which is why an unsigned lens reads the 33.2 deg journey as a gentle settle")
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S36UI_HUD    all ten handover keys present and scalar, and the signed azimuth reads %.2f deg where the hypot beside it reads %.2f — the sign trap pinned client-side too" % [float(sb._telemetry["m1.look_body_az_deg"]), float(sb._telemetry["m1.look_body_deg"])])

	# ══ TOOTH 9 — ONE slider, at the interceptor, and the disqualifications ═══════════════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("the slice-36 wire must build EXACTLY ONE slider (gimbal_rate_dps), got %d — convention 9 is satisfied by a MEASUREMENT here rather than by counting: the servo MOVES THE ARGMIN of the basket, so the authored error and the servo are ONE AXIS" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
		if str(d.get("type", "")) == "set_fidelity":
			return _fail("a slice-36 wire must NEVER send set_fidelity — there is no rung: the contrast is TWO SCENARIOS, because the authored key is consumed once at tick 1 and cannot be a knob at all")
	if not keys_set.has("gimbal_rate_dps") or keys_set["gimbal_rate_dps"] != "m1":
		return _fail("the 'gimbal_rate_dps' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	# ⚠⚠ AND THE AUTHORED KEY MUST NEVER BE A SLIDER. It is consumed exactly once, at tick 1, and never
	# read again — slice 19's `speed` and slice 21's launch altitude, the 5th occurrence in this arc and
	# the FIRST caught before the key was written. `_parse_knobs` refuses it BY NAME (the first by-name
	# refusal in the project), because the EXISTING guard would not have caught it: that guard rejects
	# knobs whose comp key does not exist, and this one's does.
	if keys_set.has("gimbal_handover_err_deg"):
		return _fail("⚠⚠ slice 36 must NOT build a 'gimbal_handover_err_deg' slider — it is STRUCTURALLY DEAD, slice 19's NOT-A-DEAD-KNOB tripwire would FAIL on it, and the loader refuses it BY NAME")
	for bad in ["radome_slope_est", "radome_slope", "radome_ripple", "radome_ripple_k",
				"gimbal_fov_deg", "gimbal_tau_s", "gimbal_stop_deg", "seeker_fov_deg",
				"cross_speed_mps", "n_pn", "rho", "sigma_seek", "elevation_deg", "af_alpha_max",
				"alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 36 must NOT build a '%s' slider. The whole `radome_*` family is DEAD on a glass-free wire (slice 35's own R̂ slider goes with the glass); `gimbal_fov_deg` is what the requirement is READ AGAINST; `gimbal_stop_deg` reaches the SAME rescue by a DIFFERENT mechanism (it CAGES the head — `head_max === stop`, and the birth angle SATURATES) and ships as a tooth instead; `cross_speed_mps` is slice 32's axis AND this slice's own control. Got %s" % [bad, str(keys_set.keys())])
	print("S36UI_KNOB   exactly 1 slider — gimbal_rate_dps → m1; NOTHING sends set_fidelity; and the AUTHORED handover error is asserted ABSENT as a slider, as is the whole radome family that went with the glass")

	# ══ TOOTH 10 — ⭐ THE MIRROR: a slice-35 wire keeps ITS branch, its button and its instruments ══
	# The new branch is inserted AHEAD of slice 35's, so the mirror is what proves it is a SWITCH and not
	# an `or` — slice 33's tooth, slice 34's and slice 35's, one slice on. ⚠ AND IT IS SHARPER HERE
	# BECAUSE THE BUTTON MOVES TOO: slice 35's wire must still get its drop from `radome_view`.
	_sb35 = _build_sandbox()
	_sb35._on_scenario({
		"name": "slice35_rate", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"radome_view": true, "gimbal_view": true, "gimbal_rate_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_rate_dps", "min": 8.0, "max": 60.0, "value": 40.0,
				   "label": "SERVO"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03,
				   "value": -0.03, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb35._gimbal_handover_view:
		return _fail("⭐ THE MIRROR: a slice-35 wire must NOT raise `gimbal_handover_view` — if it did, the branch selector would select BOTH wires and slice 35's own HUD would be the one that disappears")
	if not (_sb35._gimbal_rate_view and _sb35._radome_view):
		return _fail("…and it must still raise both of its own markers, or the mirror is not slice 35's wire at all")
	if _sb35._mode != sb._mode or _sb35._prop_btn.visible:
		return _fail("⚠ slice 35's wire must share the VIEW and keep its button DROPPED — but by `radome_view`, not by this slice's marker. Got mode=%s vis=%s" % [_sb35._mode, _sb35._prop_btn.visible])
	# ⚠ AND SLICE 35's OWN INSTRUMENT MUST STILL RUN — the new blocks are gated on the slice-36
	# telemetry keys, so a slice-35 wire's handover instruments must stay structurally dead.
	_sb35._telemetry = {"m1.los_range": 4500.0, "m1.gimbal_valid": 1.0, "m1.gimbal_fov_deg": 25.0,
						"m1.gimbal_stop_deg": 30.0, "m1.gimbal_fov_margin_deg": 17.50,
						"m1.gimbal_rate_dps": 40.0, "m1.head_rate_dps": 110.19,
						"m1.head_rate_sat": 1.0, "m1.head_angle_deg": 23.61,
						"m1.head_off_deg": 7.50, "m1.look_angle": 23.61,
						"m1.look_body_deg": 24.02, "m1.radome_slope": -0.03,
						"m1.radome_slope_est": -0.03, "m1.radome_slope_worst": -0.33,
						"m1.radome_residual": 0.0, "m1.radome_slope_az": -0.23,
						"m1.radome_eps": 0.0005, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.omega_q": 0.10, "m1.omega_r": 1.31,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	for _i in 40:
		_sb35._airframe3d_on_state({"entities": ents})
	if not (_sb35._servo_duty >= 0.5):
		return _fail("⭐ slice 35's EMA duty must still rise on its own wire (got %.4f) — the new blocks must not have disturbed it" % _sb35._servo_duty)
	if _sb35._handover_peak != 0.0 or not is_nan(_sb35._handover_los0):
		return _fail("⚠ a slice-35 wire ships neither `head_off_peak_deg` nor `look_body_az_deg`, so BOTH new instruments must stay at their initial values by PRESENCE gate, not by a value that happens to be inert. Got peak %.4f, los0 %.4f" % [_sb35._handover_peak, _sb35._handover_los0])
	if not (_sb35._radome_qpeak > 0.5):
		return _fail("⭐ …and slice 27's ring peak-hold must still latch on slice 35's wire (fed |omega_r| = 1.31, got %.4f)" % _sb35._radome_qpeak)
	print("S36UI_MIRROR a slice-35 wire keeps its own markers WITHOUT the new one, keeps its button dropped by `radome_view`, keeps its EMA duty and ring peak-hold — and both slice-36 instruments stay dead by presence gate")

	# ══ TOOTH 11 — THE VALUE-GUARD, NINETEEN-WAY ═════════════════════════════════════════════════
	# (a) slice 34 — a head, no rate limit: keeps its own branch and its `radome_view` drop
	_sb34 = _build_sandbox()
	_sb34._on_scenario({
		"name": "slice34_gimbal", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_fov_deg", "min": 1.0, "max": 8.0, "value": 4.0, "label": "WIN"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.18, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb34._gimbal_handover_view or _sb34._gimbal_rate_view or not _sb34._gimbal_view:
		return _fail("a slice-34 wire must raise `gimbal_view` ALONE of the three head markers")
	if _sb34._prop_btn.visible:
		return _fail("a slice-34 wire must keep its button dropped (by `radome_view`)")
	# (b) ⭐ slice 33 — BOTH older markers, no head: still its own composition branch
	_sb33 = _build_sandbox()
	_sb33._on_scenario({
		"name": "s33_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"radome_view": true, "seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 19.0, "max": 40.0, "value": 21.0, "label": "FOV"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb33._gimbal_handover_view or _sb33._gimbal_view or not (_sb33._radome_view and _sb33._seeker_fov_view):
		return _fail("a slice-33 wire must carry BOTH older markers and NO head marker")
	# (c) slice 32 — FOV only
	_sb32 = _build_sandbox()
	_sb32._on_scenario({
		"name": "s32_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 18.5, "max": 40.0, "value": 25.0, "label": "FOV"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb32._gimbal_handover_view or _sb32._gimbal_view or _sb32._radome_view or not _sb32._seeker_fov_view:
		return _fail("a slice-32 wire must carry seeker_fov_view ALONE")
	# (d) ⭐ slice 31 — the deepest radome wire, radome_view only, still its own cascade
	_sb31 = _build_sandbox()
	_sb31._on_scenario({
		"name": "s31_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05, "label": "s"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb31._gimbal_handover_view or _sb31._gimbal_view or _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view ALONE")
	_sb31._telemetry = {"m1.los_range": 1500.0, "m1.omega_q": -1.31, "m1.omega_r": 0.02,
						"m1.radome_slope": -0.10, "m1.radome_eps": -0.0004, "m1.look_angle": 13.6,
						"m1.radome_residual": 0.0, "m1.aero_sat": 1.0, "m1.alpha": 0.12,
						"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5}
	_sb31._airframe3d_on_state({"entities": ents})
	if not (_sb31._radome_qpeak > 0.5):
		return _fail("⭐ the radome-only MIRROR must still latch its PITCH peak-hold (fed |omega_q| = 1.31) — got %.4f" % _sb31._radome_qpeak)
	if _sb31._handover_peak != 0.0 or not is_nan(_sb31._handover_los0):
		return _fail("…and both slice-36 instruments must stay dead on it, by presence gate")
	# (e) slice 25 — seeker_axes with no marker keeps its cycler. ⚠⚠ AND THIS IS THE MIRROR OF TOOTH 2:
	# it is the SAME branch a slice-36 wire would fall into, which is why the new marker had to exist.
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4, "label": "σ"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 wire (no marker) must keep the seeker_axes cycler VISIBLE, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# (f) slice 24 — steering cycler
	_sb24 = _build_sandbox()
	_sb24._on_scenario({
		"name": "s24_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_tau_roll", "min": 0.1, "max": 2.0, "value": 1.0, "label": "τ_roll"}],
		"fidelity": {"airframe": "six_dof", "steering": "bank_to_turn", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb24._fid_kind != "steering" or not _sb24._prop_btn.visible:
		return _fail("a slice-24 wire must take the steering cycler, got kind=%s vis=%s" % [_sb24._fid_kind, _sb24._prop_btn.visible])
	# (g) slice 23 — the 3-ring airframe cycler
	_sb23 = _build_sandbox()
	_sb23._on_scenario({
		"name": "s23_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cy_beta", "min": 0.0, "max": 30.0, "value": 20.0, "label": "Cyβ"}],
		"fidelity": {"airframe": "six_dof", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb23._fid_kind != "airframe" or not _sb23._prop_btn.visible or _sb23._airframe_rungs.size() != 3:
		return _fail("a slice-23 wire must take the 3-ring airframe cycler, got kind=%s vis=%s rungs=%d" % [_sb23._fid_kind, _sb23._prop_btn.visible, _sb23._airframe_rungs.size()])
	# (h) slice 19 — the 2-D airframe view, 2-ring cycler
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "rho", "min": 0.6, "max": 1.3, "value": 1.0, "label": "ρ"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._mode != "spatial" or _sb19._fid_kind != "airframe" or not _sb19._prop_btn.visible:
		return _fail("a slice-19 wire must stay 2-D spatial with a VISIBLE airframe cycler, got mode=%s kind=%s vis=%s" % [_sb19._mode, _sb19._fid_kind, _sb19._prop_btn.visible])
	# (i) slice 16 — drops the button, but in the 2-D view
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {"guidance": "pn", "autopilot": "alpha"},
	})
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 wire must DROP the button (no fidelity to cycle)")
	if _sb16._mode == sb._mode:
		return _fail("slices 16 and 36 both drop the button but must NOT share a mode (16 = 2-D spatial, 36 = 3-D airframe3d)")
	# (j) slice 18 — terrain_grid wins the MODE discriminator
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1", "terrain_grid": [0.0, 0.0, 0.0, 0.0], "terrain_n": 2,
		"terrain_extent_m": [0.0, 1000.0, 0.0, 1000.0], "knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must enter the slice-18 terrain 3-D mode, got %s" % _sb18._mode)
	# (k) slice 21 — :atmosphere still wins the button over a co-shipped :airframe
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._mode != "spatial" or _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere, got mode=%s kind=%s" % [_sb21._mode, _sb21._fid_kind])
	print("S36UI_GUARD  nineteen-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes / 31 radome-only / 32 FOV-only / 33 BOTH-older / 34 gimbal / 35 gimbal+rate / 36 handover — plus the no-marker mirror, which lands in slice 25's cycler")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..35_ui_test contract) --------------------------------------------

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
	print("S36UI OK: since slice 34 the head has been handed its target PERFECTLY — a §1 condition slice " +
		"35 had to gate away with a band and a wide window, because the ACQUISITION TURN is the largest " +
		"slew demand in the whole engagement. Slice 36 makes the handover an AUTHORED quantity, and the " +
		"question that was gated away has an answer nobody in the arc predicted: THE WINDOW A SEEKER " +
		"NEEDS IS NOT |err|, because the body-frame LOS travels +18.11 → −15.15 deg over the approach " +
		"and a head handed over part-way along that journey starts with a head start. " +
		"⭐⭐ THE CLIENT HALF OF THIS SLICE IS THE FIRST MARKER IN THE FAMILY TO DO **BOTH** JOBS, AND " +
		"SAYING SO IS THE POINT. Slice 34's plugged a HOLE (a loader refusal re-routed its wire into the " +
		"radome cascade); slice 35's was a BRANCH SELECTOR and explicitly not a hole plug. This one is " +
		"both — and the button half is new, because slices 26–35 all dropped the shared button by riding " +
		"`radome_view`, which is keyed on authored GLASS. ⚠⚠ THIS IS THE FIRST NO-GLASS WIRE OF THE ARC " +
		"(the drop is MEASURED: a handover error is EXACTLY inert on the trajectory without a window or " +
		"an index), so `radome_view` is absent, `seeker_fov_view` is refused by the loader beside a head, " +
		"BOTH drop-branches fail, and the button COMES BACK as slice 25's `seeker_axes` cycler — whose " +
		"other position leaves the handover live beside slice 25's unrelated 2000 m blind miss. Proven BY " +
		"MIRROR in both directions, and the drop needs BOTH sites for the first time since slice 26. " +
		"⭐⭐ THE HUD HALF IS A STALE-READOUT DEFECT RATHER THAN AN INVISIBLE SLICE: `gimbal_rate_view` IS " +
		"raised here, so without the new branch slice 35's block takes the wire and its own CURE line " +
		"reads `radome_slope_est` / `radome_slope_worst` — asserted ABSENT here — and would print " +
		"`R̂ +0.000   aim point R₀+2A +0.000`, with `_radome_qpeak` frozen at 0.0 beside it by its own " +
		"presence gate. The 9th occurrence of that class, landing on another slice's payoff line. " +
		"⭐ THE VERDICT IS A PURE HELPER (the only reason it is testable at all — `_draw` never runs " +
		"headless, convention 14; slice 31's aim-point comparison shipped WRONG and only a windowed shot " +
		"caught it) and it is a 2x2 whose DIAGONAL is the headline: PERFECT-AND-LOST beside " +
		"BIASED-AND-HELD, the two shipped wires at the SAME servo, asserted to disagree. Slice 35's " +
		"helper on the foil's own numbers names the head letting go and CANNOT name the handover. " +
		"⭐⭐ THE DISPLAY FREEZE IS THIS FILE's SHARPEST TOOTH BECAUSE NOTHING ELSE CAN PROVE IT: " +
		"`head_off_peak_deg` is a RUNNING MAX, so it runs to 179.4998 deg at CPA on EVERY arm, hit or " +
		"miss, and a peak CANNOT FORGET — a HUD printing the raw key would end every clean intercept " +
		"displaying a 179 deg 'requirement', slice 19's lying picture in a new widget. The range is an " +
		"ARGUMENT, so the freeze is driven headless from both sides of r = 200 m and through a real CPA " +
		"frame. ⭐ THE REQUIREMENT LINE SAYS WHICH KIND OF NUMBER IT IS SHOWING: on a broken arm the peak " +
		"is the POST-BREAK RUNAWAY (~105 deg against a real 12.346), the two-run discipline's FIFTH " +
		"quantity failing LARGE where slice 34's froze plausibly-but-small — and it prints the PAIR and " +
		"NEVER the difference, because a signed peak MARGIN was drafted at gate 2, measured, and DROPPED " +
		"(it latches on 100 % of arms including every hit). TWO new instruments, a FOURTH shape in this " +
		"family — a RANGE-GATED FREEZE and a ONE-SHOT BIRTH LATCH whose sentinel is NAN and not 0.0, " +
		"because a 0.000000 deg birth angle is a REAL state (it is what the domain's lower endpoint " +
		"produces). Both cleared by `reset`, both dead by PRESENCE gate on slice 35's wire. ONE slider is " +
		"built, at the interceptor, NOTHING sends set_fidelity, and the AUTHORED key is asserted absent " +
		"as a slider — it is structurally dead and the loader refuses it BY NAME. The value-guard holds " +
		"NINETEEN ways.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S36UI FAIL: " + msg)
	print("S36UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb35, _sb34, _sb33, _sb32, _sb31, _sb25, _sb24, _sb23, _sb19,
			   _sb16, _sb18, _sb21]:
		if sb != null:
			sb.free()
