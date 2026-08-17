extends SceneTree
# Headless UI test for the slice-37 SERVO REFERENCE FRAME view routing + HUD — the piece
# slice37_verify.gd can't reach. The verifier drives SimClient directly (the wire + the physics); the
# Sandbox.tscn smoke-load proves the scene loads. Neither exercises the CLIENT routing, the BUTTON, or
# the verdict this slice adds.
#
# ⭐⭐ THE LOAD-BEARING TOOTH IS A **BUTTON THAT MUST NOT GO AWAY**, AND IT IS THE EXACT INVERSE OF
# SLICE 36's. Slice 36's mirror asserted that stripping its marker made a button COME BACK that had to
# be dropped. Here the marker exists so a button STAYS, and stripping it must make the button VANISH —
# because this wire raises `radome_view`, `gimbal_view` AND `gimbal_rate_view`, every one of which
# hides it. Slices 26–36 each had no rung to cycle (the lesson was a slider every time); `:seeker_head`
# IS a rung — the first on this button since slice 25 — so here THE BUTTON IS THE LESSON, and the one
# slice in twelve that has something to cycle would otherwise ship with no control at all.
# ⚠ THE RULE THIS FAMILY TEACHES IS THEREFORE NOT "a gimbal marker drops the button". It is *the button
# shows what there is to cycle, and these wires mostly have nothing.*
#
# ⭐⭐ AND THE HUD HALF IS AN **INVITED SUBTRACTION**, WHICH IS SLICE 36's OWN GATE-3 DEFECT IN A NEW
# QUANTITY. `gimbal_rate_view` is raised here, so without the new branch slice 35's servo block takes
# the wire — and it pairs `head_rate_dps` against the rate cap WITHOUT NAMING ITS FRAME. That key means
# BODY-frame demand on one rung (including tracking out the missile's own rotation) and INERTIAL-frame
# demand on the other. At the slider's ceiling the press makes it FALL 3.15x while the ring RISES
# 1.70x, so a student presses the button, watches the demand drop, and concludes *"the stabilized head
# is the cheaper build"* — three live, TRUE numbers whose invited arithmetic is exactly the inference
# the core's own seam comment forbids (cheaper in SERVO BANDWIDTH, dearer in STABILITY MARGIN).
#
# THE TEETH, in order of what would actually break:
#   1. a slice-37 handshake routes to _mode=airframe3d with the button VISIBLE at BOTH sites
#   2. ⭐⭐ THE INVERSE MIRROR: strip the marker and the button VANISHES (three markers drop it)
#   3. ⭐⭐ THE BUTTON CYCLES and sends `set_fidelity seeker_head` — the rung, not a set_param
#   4. ⭐⭐ THE INVITED SUBTRACTION: the demand line NAMES ITS FRAME, and slice 35's does not
#   5. ⭐ the VERDICT in all five states, naming the rung, and asserted to MOVE across the press
#   6. ⭐ the MECHANISM line, one per rung, and it names no threshold
#   7. every key `_draw_frame_hud_lines` reads is present and scalar
#   8. ONE slider → set_param AND a button → set_fidelity (this wire is the first to send BOTH)
#   9. the inherited instruments still run (the ring peak-hold on the YAW channel, the track latch)
#  10. ⭐ THE MIRROR: a slice-35/36 wire must NOT raise the new marker and must keep its own HUD+button
#  11. the value-guard, TWENTY-WAY
#
# Run:  godot --headless --path clients/godot --script res://net/slice37_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_nomarker
var _sb36
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

# The slice-37 wire's telemetry, at the numbers the verifier measures. ⚠ NOTE WHAT **IS** HERE that a
# slice-36 wire lacks: the whole `radome_*` family, because this wire HAS GLASS — which is precisely
# why all three drop markers fire on it and why the new one has to be checked ahead of them.
func _frame_tel(valid: bool, los: float, off: float, margin: float, ring: float,
				dem: float, sat: bool) -> Dictionary:
	return {
		"m1.los_range": los,
		"m1.gimbal_valid": 1.0 if valid else 0.0,
		"m1.gimbal_fov_deg": 25.0,
		"m1.gimbal_stop_deg": 30.0,
		"m1.gimbal_fov_margin_deg": margin,
		"m1.gimbal_rate_dps": 40.0,
		"m1.head_off_deg": off,
		"m1.head_rate_dps": dem,
		"m1.head_rate_sat": 1.0 if sat else 0.0,
		"m1.head_angle_deg": 18.28,
		"m1.look_angle": 18.28,
		"m1.look_body_deg": 18.31,
		"m1.lead_angle_deg": 18.13,
		# THE GLASS — present, live, and plausible, which is what makes the mis-branch dangerous here
		# rather than merely silent (slice 34's "nothing in it is stale" form).
		"m1.radome_slope": -0.03,
		"m1.radome_slope_est": -0.18,
		"m1.radome_slope_worst": -0.33,
		"m1.radome_slope_az": -0.23,
		"m1.radome_residual": 0.15,
		"m1.radome_eps": -0.0004,
		"m1.aero_sat": 1.0,
		"m1.alpha": 0.12,
		"m1.omega_q": 0.04, "m1.omega_r": ring,
		"m1.att_qw": 0.5, "m1.att_qx": 0.5, "m1.att_qy": -0.5, "m1.att_qz": 0.5,
	}

func _frame_handshake(marker: bool, rung: String = "body_referenced") -> Dictionary:
	var h := {
		"name": "slice37_frame",
		"airframe_view": true,
		"airframe_6dof": true,
		"airframe_target": "m1",
		# ⚠ ALL THREE DROP MARKERS ARE RAISED ON THIS WIRE — that is the hazard, not an oversight.
		"radome_view": true,
		"gimbal_view": true,
		"gimbal_rate_view": true,
		"knobs": [
			{"target": "m1", "key": "radome_slope_est", "min": -0.33, "max": -0.14, "value": -0.18,
			 "label": "DESIGN: believed slope R̂ — the onset is found TWICE, once per servo frame"},
		],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha", "seeker_head": rung},
		"dt_physics": 1.0e-3,
	}
	if marker:
		h["gimbal_frame_view"] = true
	return h

func _initialize() -> void:
	print("S37UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_frame_handshake(true))
	var ents := [{"id": "m1", "kind": "missile", "pos": [3000.0, 900.0, 3600.0]},
				 {"id": "tgt1", "kind": "target", "pos": [6000.0, 2000.0, 4200.0]}]

	# ══ TOOTH 1 — ROUTE, and the button is BACK for the first time since slice 25 ═════════════════
	if sb._mode != "airframe3d":
		return _fail("a slice-37 handshake (airframe_6dof) must enter _mode=airframe3d, got %s" % sb._mode)
	if not sb._gimbal_frame_view:
		return _fail("the client must record the `gimbal_frame_view` handshake marker")
	if not (sb._radome_view and sb._gimbal_view and sb._gimbal_rate_view):
		return _fail("⚠ a slice-37 wire is slice 35's wire with one number changed and one fidelity authored, so it must STILL raise all three of those markers — every one of which DROPS the button. That is the hazard the new marker exists for. Got rad=%s gim=%s rate=%s" % [sb._radome_view, sb._gimbal_view, sb._gimbal_rate_view])
	if not sb._prop_btn.visible:
		return _fail("⭐⭐ a slice-37 handshake must KEEP the shared button — `:seeker_head` is a genuine two-rung fidelity, the FIRST on this button since slice 25, and the press IS the lesson. Three separate markers on this same wire hide it, so this branch must be checked FIRST or it is unreachable")
	if sb._fid_kind != "seeker_head":
		return _fail("⭐⭐ …and it must take its OWN `_fid_kind` (got %s). A new kind is free here — the 3-D view keys off `_mode`, not `_fid_kind`, and neither slice 24's `steering` nor slice 25's `seeker_axes` appears in any drawing gate (slice 21's 'only `_draw_missile`'s gate needed this kind added' re-checked, and the answer is that none did)" % sb._fid_kind)
	if sb._t3d_layer == null or not is_instance_valid(sb._t3d_layer):
		return _fail("keeping the button must NOT skip _build_airframe3d_scene — slice 37 reuses the slice-23 3-D view wholesale")
	# ⚠⚠ AND THE SECOND SITE IS LOAD-BEARING IN THE OPPOSITE DIRECTION FROM SLICE 36's. There, the
	# `"airframe"` arm had to KEEP the button hidden. Here `_fid_kind` is a NEW value, so the button's
	# label lives in its own match arm — and if that arm were missing the `_:` default would take it
	# and re-label it as the PROPAGATION button on a wire that has no propagation rung at all.
	sb._update_fid_btn()
	if not sb._prop_btn.visible:
		return _fail("_update_fid_btn must KEEP the button visible — its `\"seeker_head\"` arm sets that EXPLICITLY rather than inheriting it, because falling through to the `\"airframe\"` arm would cycle the HELD `:airframe` key (the convention-9 'toggle a held key' trap those defences exist for)")
	if not sb._prop_btn.text.contains("body_referenced"):
		return _fail("…and must LABEL it with the live rung, got '%s'. Without its own match arm the `_:` default would print 'prop: ?' on a wire with no propagation rung" % sb._prop_btn.text)
	print("S37UI_ROUTE  airframe3d + gimbal_frame_view recorded, all three DROP markers also raised, and the button is VISIBLE at BOTH sites labelled '%s' — the first rung on this button since slice 25" % sb._prop_btn.text)

	# ══ TOOTH 2 — ⭐⭐ THE INVERSE MIRROR: strip the marker and the button VANISHES ════════════════
	# ⚠⚠ THE EXACT OPPOSITE OF SLICE 36's MIRROR, and stating that is the point: there, stripping the
	# marker made a button APPEAR that had to be dropped; here it makes the button DISAPPEAR on the one
	# wire in twelve slices that has a rung to cycle. Same mechanism, opposite sign — and a later slice
	# reading only slices 26–36 would learn the wrong rule.
	_sb_nomarker = _build_sandbox()
	_sb_nomarker._on_scenario(_frame_handshake(false))
	if _sb_nomarker._gimbal_frame_view:
		return _fail("the no-marker mirror must NOT record gimbal_frame_view")
	if _sb_nomarker._prop_btn.visible:
		return _fail("⭐⭐ THE HOLE: without `gimbal_frame_view` the button must VANISH — `radome_view` (and `gimbal_view`, and `gimbal_rate_view`) each drop it, and the dispatch reaches them first. If it stays visible, something else is showing it and this marker's button half is not the load-bearing thing this file claims")
	if _sb_nomarker._fid_kind == "seeker_head":
		return _fail("⭐⭐ …and the kind must fall back too (got %s) — otherwise the drop is happening for a reason unrelated to the branch" % _sb_nomarker._fid_kind)
	if _sb_nomarker._mode != sb._mode:
		return _fail("⚠ the two must still share the VIEW (the 3-D airframe scene) — what the marker changes is the button and the HUD branch, not the mode. Got %s/%s" % [_sb_nomarker._mode, sb._mode])
	print("S37UI_HOLE   without the marker the button VANISHES (kind=%s, hidden) — the exact inverse of slice 36's mirror, where stripping the marker made one appear" % _sb_nomarker._fid_kind)

	# ══ TOOTH 3 — ⭐⭐ THE BUTTON CYCLES, AND IT SENDS A RUNG ══════════════════════════════════════
	# ⚠ `set_fidelity`, never `set_param` — and the server accepts it with NO draw-topology guard
	# (class 4a: there is no topology to flip, unlike `:cfar` and `:scan`). The client owns the
	# DISPLAYED rung, which is why the label must move with the press: slice 19's lesson, that a raw
	# wire command moves the physics while the label keeps the old number — a lying picture on a green
	# run — and slice 35's shot paid for it a second time.
	mock.sent.clear()
	sb._prop_btn.emit_signal("pressed")
	var fid_cmds: Array = []
	for d in mock.sent:
		if str(d.get("type", "")) == "set_fidelity":
			fid_cmds.append(d)
		if str(d.get("type", "")) == "set_param":
			return _fail("⚠ the BUTTON must send `set_fidelity`, never `set_param` — the reference frame is a RUNG, and gate 0 answered the reparameterization gate with a BOUND (a 25x faster servo at a 50x smaller tau stops at 4.796 deg of index gain and cannot reach the stabilized head's 3.861). Got %s" % str(d))
	if fid_cmds.size() != 1:
		return _fail("one press must send exactly one set_fidelity, got %d" % fid_cmds.size())
	if str(fid_cmds[0].get("key", "")) != "seeker_head":
		return _fail("the press must cycle `seeker_head`, got key='%s'" % str(fid_cmds[0].get("key", "")))
	if str(fid_cmds[0].get("value", "")) != "space_stabilized":
		return _fail("⭐⭐ the FIRST press must move to `space_stabilized` — the wire OPENS on the GOOD design (body-referenced, quiet, and it hits) so that the first press is the one that BREAKS it. Got '%s'" % str(fid_cmds[0].get("value", "")))
	if not sb._prop_btn.text.contains("space_stabilized"):
		return _fail("…and the LABEL must move with it (got '%s'). Slice 19's press-the-button lesson: a raw wire command changes the physics while the label keeps the old number — a lying picture on a green run" % sb._prop_btn.text)
	# …and the ring WRAPS back, so the demonstration is repeatable without a reset.
	mock.sent.clear()
	sb._prop_btn.emit_signal("pressed")
	if str(mock.sent[0].get("value", "")) != "body_referenced":
		return _fail("the ring must WRAP back to body_referenced, got '%s'" % str(mock.sent[0].get("value", "")))
	print("S37UI_BTN    one press sends set_fidelity seeker_head=space_stabilized and the LABEL moves with it; the ring wraps back — never set_param, because the frame is a RUNG and gate 0 proved no tau reaches it")

	# ══ TOOTH 4 — ⭐⭐ THE INVITED SUBTRACTION: the demand line must NAME ITS FRAME ════════════════
	# ⚠⚠ THE ONE NON-NEGOTIABLE THING IN THIS SLICE's HUD. `head_rate_dps` keeps its slice-35 name
	# across this button and MEANS A DIFFERENT THING ON EACH SIDE OF IT. At the slider's ceiling the
	# press makes it FALL 3.15x (55.7 -> 17.7 deg/s) while the ring RISES 1.70x — so an unlabelled line
	# invites *"the stabilized head is the cheaper build"*, which is exactly the conclusion the core's
	# seam forbids. Slice 36's INVITED ARITHMETIC defect, in a new quantity: three true numbers under a
	# correct verdict, whose subtraction is wrong.
	var d_body: String = sb._frame_demand_text(55.68, 40.0, true, false)
	var d_space: String = sb._frame_demand_text(17.65, 40.0, false, true)
	if not d_body.contains("BODY"):
		return _fail("⭐⭐ the demand line must NAME the body frame on the body rung. Got '%s'" % d_body)
	if not d_space.contains("INERTIAL"):
		return _fail("⭐⭐ …and the inertial frame on the stabilized rung. Got '%s'" % d_space)
	# ⭐ THE SAME NUMBER MUST READ DIFFERENTLY ON THE TWO RUNGS — asserted directly, because that is the
	# whole claim. If the two strings agree on identical inputs, the frame is not on screen.
	if sb._frame_demand_text(17.65, 40.0, false, false) == sb._frame_demand_text(17.65, 40.0, false, true):
		return _fail("⭐⭐ THE SAME DEMAND ON THE TWO RUNGS MUST NOT RENDER IDENTICALLY — the frame is what distinguishes them, and a student comparing two frames' demands under one label is doing the subtraction the core's seam comment forbids")
	# ⚠ AND SLICE 35's OWN LINE IS LEFT VERBATIM AND IS STILL RIGHT ON ITS OWN WIRE — the defect this
	# branch fixes is the BRANCH, not the helper. Slice 35's servo verdict cannot name a frame at all.
	var s35: String = sb._servo_verdict_label(false, true, 0.9)
	if s35.contains("BODY") or s35.contains("INERTIAL"):
		return _fail("slice 35's helper must be UNCHANGED and must NOT name a frame (it has no way to know one) — got '%s'" % s35)
	if not s35.contains("SERVO PEGGED"):
		return _fail("slice 35's helper must still return its own verdict on its own numbers, got '%s'" % s35)
	# ⚠ THE PEGGED TAG STILL WORKS, because the saturation split IS this slice's price column (0.00 %
	# space against 17.5 % body at the slider's ceiling) — the frame naming must not have cost it.
	if not d_body.contains("PEGGED"):
		return _fail("the demand line must still flag saturation (the core's own branch predicate, never a re-derived compare). Got '%s'" % d_body)
	if d_space.contains("PEGGED"):
		return _fail("…and must not flag it when the flag is clear. Got '%s'" % d_space)
	for s in [d_body, d_space]:
		if s.length() > 55:
			return _fail("⚠⚠ the HUD line must fit ~55 characters at 15 px from `vp.x − 430` (got %d): '%s'. The 3rd occurrence of that overrun after slices 26 and 28 cost slice 36 a retake, and the part that gets cut is always the part that carries the meaning" % [s.length(), s])
	print("S37UI_FRAME  the demand line names its frame on both rungs ('%s' / '%s') and the SAME number renders differently — slice 35's helper is unchanged and cannot name a frame at all" % [d_body, d_space])

	# ══ TOOTH 5 — ⭐ THE VERDICT, FIVE STATES, AND IT MUST MOVE ACROSS THE PRESS ══════════════════
	# A HUD only ever sees ONE arm, so what has to be legible is THE PRESS: the student holds one design
	# still, changes the architecture, and reads the verdict change. Naming the rung is what turns two
	# consecutive frames into a comparison.
	if sb._frame_verdict_label(false, false, false) != "BODY-REFERENCED — loop STABLE":
		return _fail("⭐ the wire's OPENING state — slice 34's shipped design, quiet and hitting. Got '%s'" % sb._frame_verdict_label(false, false, false))
	if sb._frame_verdict_label(false, true, true) != "SPACE-STABILIZED — RINGING":
		return _fail("⭐⭐ the state ONE PRESS away — the SAME design, the other frame, shaking. Got '%s'" % sb._frame_verdict_label(false, true, true))
	if sb._frame_verdict_label(false, true, false) != "BODY-REFERENCED — RINGING":
		return _fail("⭐ the slider's CEILING on the body rung, where BOTH rungs ring. Got '%s'" % sb._frame_verdict_label(false, true, false))
	if sb._frame_verdict_label(false, false, true) != "SPACE-STABILIZED — loop STABLE":
		return _fail("⭐ the slider's FLOOR on the stabilized rung — slice 30's aim point, where the button goes dead. Got '%s'" % sb._frame_verdict_label(false, false, true))
	if sb._frame_verdict_label(true, false, true) != "TRACK LOST — the head let go":
		return _fail("the LOST state, inherited from 34/35 (unreachable on this wire — the window never bites — but the branch must exist). Got '%s'" % sb._frame_verdict_label(true, false, true))
	# ⭐⭐ THE PRESS MUST MOVE THE VERDICT AT THE SHIPPED DEFAULT — asserted as a DISAGREEMENT, which is
	# the only form that proves the button is legible at all.
	if sb._frame_verdict_label(false, false, false) == sb._frame_verdict_label(false, true, true):
		return _fail("⭐⭐ the two sides of the shipped press must produce DIFFERENT verdicts — that difference IS the slice")
	# ⚠ AND THE TWO RINGING STRINGS MUST DIFFER FROM EACH OTHER TOO, or the student cannot tell which
	# architecture is shaking. ⚠ Neither may hint at the other rung: near the ceiling BOTH ring, and a
	# "RINGING TOO" would assert a fact about an arm this frame has no access to.
	if sb._frame_verdict_label(false, true, false) == sb._frame_verdict_label(false, true, true):
		return _fail("⭐ the two RINGING states must name their own architecture")
	for s in ["BODY-REFERENCED — loop STABLE", "SPACE-STABILIZED — RINGING"]:
		if s.length() > 34:
			return _fail("⚠ the headline must fit ~34 characters at 20 px from `vp.x − 430` (got %d): '%s'" % [s.length(), s])
	print("S37UI_VERDICT five states pinned, the press MOVES the verdict ('%s' -> '%s'), and neither ringing string hints at the other rung" % [sb._frame_verdict_label(false, false, false), sb._frame_verdict_label(false, true, true)])

	# ══ TOOTH 6 — ⭐ THE MECHANISM LINE, one per rung, naming no threshold ════════════════════════
	# The line that makes the ring and the demand readable TOGETHER: the position servo's LAG is not
	# merely slowness, it LOW-PASSES body motion out of the radome's INDEX, and slice 26's limit cycle
	# lives at 1.7-2.1 Hz where a tau = 0.05 s filter is worth 12-16 % of gain and ~30 deg of phase.
	var m_body: String = sb._frame_mech_text(false)
	var m_space: String = sb._frame_mech_text(true)
	if not (m_body.contains("LAG") and m_body.contains("index")):
		return _fail("⭐ the body rung's mechanism line must name the LAG and the INDEX — without it the ring and the demand are two numbers with no stated relationship. Got '%s'" % m_body)
	if not m_space.contains("no lag"):
		return _fail("⭐ the stabilized rung's must say the filter is GONE. Got '%s'" % m_space)
	if m_body == m_space:
		return _fail("the mechanism line must differ by rung — it is the half of the HUD that explains the press")
	# ⚠ NO CLIENT-SIDE STABILITY TEST ANYWHERE ON THIS WIRE: |R_crit| moves with N and rho (the boundary
	# is N·|R − R̂|/rho), so a "residual < x ⇒ unstable" line would be physics in GDScript AND wrong the
	# moment a scenario changes N. Convention 13, slice 26's rule, still in force.
	for s in [m_body, m_space]:
		if s.contains("0.3") or s.contains("critical") or s.contains("R_crit"):
			return _fail("⚠ the mechanism line must NAME the mechanism and never a THRESHOLD (convention 13). Got '%s'" % s)
		if s.length() > 55:
			return _fail("⚠⚠ the mechanism line must fit ~55 characters (got %d): '%s'" % [s.length(), s])
	print("S37UI_MECH   the mechanism line differs by rung ('%s' / '%s') and names no threshold" % [m_body, m_space])

	# ══ TOOTH 7 — every key `_draw_frame_hud_lines` reads is PRESENT and scalar ═══════════════════
	# ⚠ The stale-readout class in its MIRROR form: a missing key silently becoming 0.000 through
	# `get(..., 0.0)`. ⚠⚠ AND ON THIS WIRE THEY ARE ALL LIVE — which is what makes a mis-branch
	# DANGEROUS rather than merely silent. Slice 34's form of the defect: nothing is stale, and the
	# subject is simply wrong.
	sb._telemetry = _frame_tel(true, 1500.0, 3.37, 21.63, 1.05, 16.59, false)
	sb._airframe3d_on_state({"entities": ents})
	sb._update_readout()
	for k in ["m1.omega_r", "m1.head_rate_dps", "m1.gimbal_rate_dps", "m1.head_rate_sat",
			  "m1.head_off_deg", "m1.gimbal_fov_margin_deg", "m1.radome_slope_est",
			  "m1.radome_slope_worst", "m1.los_range"]:
		if not sb._telemetry.has(k):
			return _fail("⚠ `_draw_frame_hud_lines` reads %s — a missing key would `get(..., 0.0)` and print a confident 0.000, the stale-readout class this arc has caught nine times" % k)
		if typeof(sb._telemetry.get(k)) != TYPE_FLOAT:
			return _fail("%s must reach the client as a scalar float (no client-side geometry)" % k)
	# ⭐ THE CURE LINE's TWO NUMBERS ARE BOTH REAL HERE — unlike on slice 36's glass-free wire, where
	# reading them was the defect. Slice 30's rule pays a FOURTH time and the slider's FLOOR is the
	# aim point exactly, so a student can drag to it and watch the button go dead.
	if not (float(sb._telemetry["m1.radome_slope_worst"]) < -0.3):
		return _fail("⭐ the aim point must be live and negative on this wire (R₀+2A = −0.33) — it is the slider's FLOOR and the place the architecture stops mattering")
	# ⚠⚠ AND THE CURE LINE's WIDTH IS PINNED HERE **BECAUSE THE FIRST SHOT CAUGHT IT**. Inside `_draw`
	# it had no headless proof at all (convention 14), and it shipped at 59 characters against the
	# measured ~55-character budget at 15 px from `vp.x − 430` — clearing the right edge by ~10 px at
	# 1600 px and cut at any narrower window. The 4th occurrence of that overrun after slices 26, 28
	# and 36, and the part that gets cut is always the part that carries the meaning. Extracting it to
	# a pure helper is what makes this assertable at all.
	# ⭐⭐ THE RING LINE MUST SEPARATE THE TWO ARMS **AS A NUMBER**, AND THIS TOOTH EXISTS BECAUSE THE
	# FIRST PAIR OF SHOTS CAUGHT IT NOT DOING SO. The captures read `ring r −0.019 rad/s` on the QUIET
	# arm against `ring r +0.021 rad/s` on the one ringing 84× harder — a limit cycle crosses zero twice
	# per cycle, so one frame catches it wherever it happens to be. Two live, TRUE numbers whose
	# comparison says the architecture did not matter, which is the exact inverse of the claim: slice
	# 36's INVITED ARITHMETIC, in this slice's own headline quantity. The DECAYING PEAK is what
	# separates them, so it is drawn as a number and not only as an orange tag.
	var ring_quiet: String = sb._frame_ring_text(-0.019, 0.021, 1.91, true)
	var ring_loud: String = sb._frame_ring_text(0.021, 1.31, 1.50, true)
	if not ring_loud.contains("1.31"):
		return _fail("⭐⭐ the ring line must print the PEAK's value, not only its tag — the live rate alone reads 0.021 on a ringing arm and 0.019 on a quiet one. Got '%s'" % ring_loud)
	if not ring_quiet.contains("0.02"):
		return _fail("⭐⭐ …and the quiet arm's peak must be visibly small on the SAME line, or the pair still cannot be compared. Got '%s'" % ring_quiet)
	if ring_quiet.contains("RINGING") or not ring_loud.contains("RINGING"):
		return _fail("⚠ the tag must still ride the peak-hold and not the live rate (slice 27: a limit cycle crosses zero twice per cycle, so an instantaneous verdict mislabels half the frames). Got '%s' / '%s'" % [ring_quiet, ring_loud])
	if not (ring_quiet.contains("-0.019") and ring_loud.contains("+0.021")):
		return _fail("⚠ …and the LIVE value must stay on the line beside the instrument, so nothing is hidden behind it. Got '%s' / '%s'" % [ring_quiet, ring_loud])
	for s in [ring_quiet, ring_loud]:
		if s.length() > 55:
			return _fail("⚠⚠ the ring line must fit ~55 characters at 15 px (got %d): '%s'" % [s.length(), s])
	var cure: String = sb._frame_cure_text(-0.180, -0.330)
	if cure.length() > 55:
		return _fail("⚠⚠ the cure line must fit ~55 characters at 15 px (got %d): '%s'" % [cure.length(), cure])
	if not (cure.contains("R₀+2A") and cure.contains("-0.330")):
		return _fail("⭐ the cure line must pair the BELIEF with the AIM POINT, both READ OFF THE WIRE — never a client-side stability test, because |R_crit| moves with N and ρ (convention 13). Got '%s'" % cure)
	if cure.contains("0.30") or cure.contains("critical"):
		return _fail("⚠ …and it must name no THRESHOLD. Got '%s'" % cure)
	if sb._t3d_trail_pts.size() < 1:
		return _fail("the state path must append a trail breadcrumb")
	print("S37UI_HUD    all nine frame keys present and scalar, and the cure line's aim point is LIVE (%.3f) — the opposite of slice 36's wire, where reading it was the defect" % float(sb._telemetry["m1.radome_slope_worst"]))

	# ══ TOOTH 8 — ONE slider AND a button: the first wire of this family to send BOTH ═════════════
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("the slice-37 wire must build EXACTLY ONE slider (radome_slope_est), got %d — convention 9, and on this wire the SECOND control is the BUTTON" % sliders.size())
	mock.sent.clear()
	for s in sliders:
		s.emit_signal("value_changed", s.value)   # a programmatic set outside the tree won't auto-emit
	var keys_set := {}
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param":
			keys_set[str(d.get("key", ""))] = str(d.get("target", ""))
	if not keys_set.has("radome_slope_est") or keys_set["radome_slope_est"] != "m1":
		return _fail("the 'radome_slope_est' slider must send set_param at the interceptor m1, got %s" % str(keys_set))
	# ⚠ THE SERVO IS AUTHORED HERE, and the disqualification is a MEASUREMENT: putting slice 35's
	# TWO-SIDED knob live beside this button would be a third mechanism on a wire whose subject is the
	# reference frame. Its own finding — the demand inversion at the ceiling — ships as a TOOTH.
	for bad in ["gimbal_rate_dps", "gimbal_tau_s", "gimbal_fov_deg", "gimbal_stop_deg",
				"gimbal_handover_err_deg", "radome_slope", "radome_ripple", "radome_ripple_k",
				"seeker_fov_deg", "cross_speed_mps", "n_pn", "rho", "sigma_seek", "elevation_deg",
				"af_alpha_max", "alpha_max", "speed"]:
		if keys_set.has(bad):
			return _fail("slice 37 must NOT build a '%s' slider. `gimbal_rate_dps` is slice 35's TWO-SIDED knob (a third mechanism here); `gimbal_tau_s` moves the SIZE of this slice's own mechanism (at tau <= 0.005 the two rungs' brackets COINCIDE); `gimbal_fov_deg` must never bite or every rms r here stops being a stability read; the GLASS is hardware. Got %s" % [bad, str(keys_set.keys())])
	print("S37UI_KNOB   exactly 1 slider — radome_slope_est → m1 — beside a button that sends set_fidelity: the first wire of this family to drive BOTH, because it is the first with a rung AND a design axis")

	# ══ TOOTH 9 — the inherited instruments still run, on the RIGHT channel ═══════════════════════
	# ⚠ The ring peak-hold must follow the YAW channel: this wire has a slope RIPPLE, so the lead is in
	# AZIMUTH and the yaw channel sits on the steep part of the glass while pitch sits near the
	# boresight slope. A peak-hold left on |q| would meter the QUIET channel of a shaking missile
	# (slice 28's finding, measured here as omega_q 0.04 against omega_r 1.05).
	var sb2 = _build_sandbox()
	sb2._on_scenario(_frame_handshake(true))
	sb2._telemetry = _frame_tel(true, 1500.0, 3.37, 21.63, 1.05, 16.59, false)
	for _i in 40:
		sb2._airframe3d_on_state({"entities": ents})
	if not (sb2._radome_qpeak > 0.5):
		return _fail("⭐ the ring peak-hold must latch on the YAW channel (fed omega_r = 1.05 against omega_q = 0.04), got %.4f — a peak-hold on pitch would read 0.04 and label a shaking missile STABLE" % sb2._radome_qpeak)
	if sb2._ring_channel_key() != ".omega_r":
		return _fail("…and the shared channel helper must select yaw on a ripple-carrying wire, got %s" % sb2._ring_channel_key())
	# …and the TRACK LATCH is range-gated and still works, though this wire never trips it.
	if sb2._gimbal_lost:
		return _fail("⚠ the track latch must stay CLEAR on this wire — the detector window is authored at 25 deg against a worst measured requirement of 5.391, and every `rms r` here being a stability read DEPENDS on that")
	sb2._telemetry = _frame_tel(false, 1500.0, 26.0, -1.0, 1.05, 0.0, false)
	sb2._airframe3d_on_state({"entities": ents})
	if not sb2._gimbal_lost:
		return _fail("…but it must still latch when the core says the window broke (the client only REMEMBERS the verdict — convention 13)")
	sb2._on_reset_pressed()
	if sb2._gimbal_lost or sb2._radome_qpeak != 0.0:
		return _fail("`reset` must clear the latch and the peak-hold (got lost=%s peak=%.4f)" % [sb2._gimbal_lost, sb2._radome_qpeak])
	sb2.free()
	print("S37UI_INSTR  the ring peak-hold latches on the YAW channel (omega_r 1.05 vs omega_q 0.04), the track latch stays clear on this wire but still fires on the core's verdict, and reset clears both")

	# ══ TOOTH 10 — ⭐ THE MIRROR: slices 35 and 36 keep THEIR branches, buttons and instruments ════
	# The new branch is inserted AHEAD of both, so the mirror is what proves it is a SWITCH and not an
	# `or` — slice 33's tooth, 34's, 35's and 36's, one slice on. ⚠ AND IT IS SHARPEST AGAINST SLICE
	# 35, whose wire is nearly identical: same markers, same view, same head. The ONLY difference is
	# the authored fidelity, which is exactly why the core gates the marker on the FIDELITY.
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
	if _sb35._gimbal_frame_view:
		return _fail("⭐ THE MIRROR: a slice-35 wire must NOT raise `gimbal_frame_view` — if it did, the branch selector would select BOTH wires and slice 35's own SERVO HUD would be the one that disappears")
	if _sb35._prop_btn.visible:
		return _fail("⚠ slice 35's wire must keep its button DROPPED (by `radome_view`) — got visible. The two wires differ ONLY by the authored fidelity, which is why the marker is gated on it")
	if _sb35._mode != sb._mode:
		return _fail("…while still sharing the VIEW. Got %s/%s" % [_sb35._mode, sb._mode])
	# (and slice 36's, which raises its own marker and drops the button by IT rather than by radome_view)
	_sb36 = _build_sandbox()
	_sb36._on_scenario({
		"name": "slice36_biased", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"gimbal_view": true, "gimbal_rate_view": true, "gimbal_handover_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_rate_dps", "min": 8.0, "max": 60.0, "value": 8.0,
				   "label": "SERVO"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb36._gimbal_frame_view or not _sb36._gimbal_handover_view:
		return _fail("a slice-36 wire must raise its OWN marker and not this one")
	if _sb36._prop_btn.visible:
		return _fail("⚠ slice 36's wire must keep its button dropped BY ITS OWN MARKER (it has no glass, so `radome_view` cannot do it) — got visible")
	if _sb36._radome_view:
		return _fail("…and it must still have NO glass, or it is not slice 36's wire at all")
	print("S37UI_MIRROR slice 35 keeps its markers WITHOUT the new one and its button dropped by `radome_view`; slice 36 keeps its own marker and its own drop — the new branch is a SWITCH ahead of both, not an `or`")

	# ══ TOOTH 11 — THE VALUE-GUARD, TWENTY-WAY ═══════════════════════════════════════════════════
	# (a) slice 34 — a head, no rate limit
	_sb34 = _build_sandbox()
	_sb34._on_scenario({
		"name": "slice34_gimbal", "airframe_view": true, "airframe_6dof": true,
		"airframe_target": "m1", "radome_view": true, "gimbal_view": true,
		"knobs": [{"target": "m1", "key": "gimbal_fov_deg", "min": 1.0, "max": 8.0, "value": 4.0, "label": "WIN"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.18, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb34._gimbal_frame_view or _sb34._gimbal_rate_view or not _sb34._gimbal_view:
		return _fail("a slice-34 wire must raise `gimbal_view` ALONE of the four head markers")
	if _sb34._prop_btn.visible:
		return _fail("a slice-34 wire must keep its button dropped (by `radome_view`)")
	# (b) slice 33 — BOTH older markers, no head
	_sb33 = _build_sandbox()
	_sb33._on_scenario({
		"name": "s33_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"radome_view": true, "seeker_fov_view": true,
		"knobs": [{"target": "m1", "key": "seeker_fov_deg", "min": 19.0, "max": 40.0, "value": 21.0, "label": "FOV"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.36, "max": -0.03, "value": -0.03, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb33._gimbal_frame_view or _sb33._gimbal_view or not (_sb33._radome_view and _sb33._seeker_fov_view):
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
	if _sb32._gimbal_frame_view or _sb32._gimbal_view or _sb32._radome_view or not _sb32._seeker_fov_view:
		return _fail("a slice-32 wire must carry seeker_fov_view ALONE")
	# (d) slice 31 — radome only, still its own cascade
	_sb31 = _build_sandbox()
	_sb31._on_scenario({
		"name": "s31_mirror", "airframe_view": true, "airframe_6dof": true, "radome_view": true,
		"airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "gyro_scale_err", "min": -0.4, "max": 0.4, "value": -0.05, "label": "s"},
				  {"target": "m1", "key": "radome_slope_est", "min": -0.55, "max": 0.0, "value": -0.27, "label": "R̂"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "az_el", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb31._gimbal_frame_view or _sb31._gimbal_view or _sb31._seeker_fov_view or not _sb31._radome_view:
		return _fail("a slice-31 wire must carry radome_view ALONE")
	# (e) ⚠⚠ slice 25 — seeker_axes with no marker keeps its cycler. AND THIS IS THE BRANCH THE
	# NO-MARKER MIRROR WOULD *NOT* REACH on a slice-37 wire, which is the difference from slice 36:
	# there, stripping the marker fell through to HERE; here it is caught by `radome_view` first.
	_sb25 = _build_sandbox()
	_sb25._on_scenario({
		"name": "s25_mirror", "airframe_view": true, "airframe_6dof": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "sigma_seek", "min": 5.0e-5, "max": 3.0e-4, "value": 3.0e-4, "label": "σ"}],
		"fidelity": {"airframe": "six_dof", "seeker_axes": "pitch_plane", "seeker": "filtered",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb25._fid_kind != "seeker_axes" or not _sb25._prop_btn.visible:
		return _fail("a slice-25 wire (no marker) must keep the seeker_axes cycler VISIBLE, got kind=%s vis=%s" % [_sb25._fid_kind, _sb25._prop_btn.visible])
	# ⭐ AND ITS CYCLER MUST STILL SEND ITS OWN KEY — the new `"seeker_head"` arm must not have
	# shadowed the `"seeker_axes"` one (they are adjacent match arms with similar names).
	var m25: MockClient = _sb25._client
	m25.sent.clear()
	_sb25._prop_btn.emit_signal("pressed")
	if str(m25.sent[0].get("key", "")) != "seeker_axes":
		return _fail("⭐ slice 25's cycler must still send `seeker_axes`, got '%s' — the two match arms are adjacent and similarly named" % str(m25.sent[0].get("key", "")))
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
	# (i) slice 16 — drops the button, in the 2-D view
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_mirror", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {"guidance": "pn", "autopilot": "alpha"},
	})
	if _sb16._prop_btn.visible:
		return _fail("a slice-16 wire must DROP the button (no fidelity to cycle)")
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
	print("S37UI_GUARD  twenty-way OK — 16 drops(2-D) / 18 terrain-3-D / 19 airframe-2-ring(2-D) / 21 atmosphere / 23 airframe-3-ring / 24 steering / 25 seeker_axes(+its own key) / 31 radome-only / 32 FOV-only / 33 BOTH-older / 34 gimbal / 35 gimbal+rate / 36 handover / 37 frame — plus the no-marker mirror, which here VANISHES rather than appearing")

	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19..36_ui_test contract) --------------------------------------------

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
	print("S37UI OK: slice 34 gave the seeker a head, slice 35 gave that head a real servo, and this " +
		"slice asks what FRAME the servo closes in. ⚠⚠ THE DEFERRAL THAT NAMED IT WAS WRONG — 'a " +
		"rate-stabilized head measures inertial LOS rate directly' is ALREADY TRUE of this model, so " +
		"what is body-referenced is the SERVO. ⭐⭐ AND STABILIZING IT REMOVES MARGIN: the position " +
		"servo's LAG was doing stability work nobody asked it for, low-passing the missile's own body " +
		"motion out of the radome's INDEX at exactly the 1.7-2.1 Hz where slice 26's limit cycle " +
		"lives. THE CLASSICAL REASON GIMBALS EXIST INVERTS ON THIS WIRE. " +
		"⭐⭐ THE CLIENT HALF IS THE FIRST MARKER IN THIS FAMILY WHOSE BUTTON JOB IS THE **OPPOSITE** " +
		"OF EVERY MARKER BEFORE IT, and saying so is the point: slices 26–36 each had no rung to " +
		"cycle, so `radome_view` / `seeker_fov_view` / `gimbal_handover_view` all HIDE the shared " +
		"button and 32/33/34/35 rode one of them for free. `:seeker_head` IS a rung — the first on " +
		"this button since slice 25 — and this wire raises THREE of those drop markers, so without a " +
		"marker of its own the one slice in twelve that has something to cycle would ship with no " +
		"control at all. Proven BY MIRROR, and the mirror is the EXACT INVERSE of slice 36's: there, " +
		"stripping the marker made a button APPEAR that had to be dropped; here it makes the button " +
		"VANISH. ⚠ The rule this family teaches is NOT 'a gimbal marker drops the button' — it is that " +
		"the button shows what there is to cycle, and these wires mostly have nothing. " +
		"⭐⭐ THE HUD HALF IS AN INVITED SUBTRACTION, WHICH IS SLICE 36's OWN GATE-3 DEFECT IN A NEW " +
		"QUANTITY. `gimbal_rate_view` IS raised here, so without the new branch slice 35's servo block " +
		"takes the wire — and it pairs `head_rate_dps` against the rate cap WITHOUT NAMING ITS FRAME. " +
		"That key means BODY-frame demand on one rung (including tracking out the missile's own " +
		"rotation) and INERTIAL-frame demand on the other, and at the slider's ceiling the press makes " +
		"it FALL 3.15x while the ring RISES 1.70x. Every number would be TRUE and the invited " +
		"arithmetic — *press it, watch the demand drop, conclude the stabilized head is the cheaper " +
		"build* — is exactly the inference the core's seam comment forbids: cheaper in SERVO " +
		"BANDWIDTH, dearer in STABILITY MARGIN. ⇒ THE FRAME IS PRINTED INSIDE THE SAME STRING AS THE " +
		"NUMBER, and the same demand on the two rungs is asserted to render DIFFERENTLY. " +
		"⭐ THE VERDICT IS A PURE HELPER (the only reason it is testable at all — `_draw` never runs " +
		"headless, convention 14) and it names the RUNG in every state, because a HUD sees one arm at " +
		"a time and what must be legible is THE PRESS: the student holds one design still, changes " +
		"the architecture, and reads the verdict change. Five states pinned, the press asserted to " +
		"MOVE it, and neither ringing string hints at the other rung — near the slider's ceiling BOTH " +
		"ring, and a 'RINGING TOO' would assert a fact this frame has no access to. " +
		"⭐ THE MECHANISM LINE names the LAG and the INDEX and never a THRESHOLD (convention 13: " +
		"|R_crit| moves with N and rho, so a client-side stability test would be physics in GDScript " +
		"AND wrong the moment a scenario changes N). ONE slider is built, at the interceptor, BESIDE a " +
		"button that sends `set_fidelity` — the first wire of this family to drive BOTH — and the " +
		"press moves the LABEL with the physics (slice 19's lying-picture lesson, which slice 35's " +
		"shot paid for a second time). The inherited instruments still run on the RIGHT channel (the " +
		"ring peak-hold on YAW, where a ripple wire's lead is). The value-guard holds TWENTY ways.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S37UI FAIL: " + msg)
	print("S37UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_nomarker, _sb36, _sb35, _sb34, _sb33, _sb32, _sb31, _sb25, _sb24, _sb23,
			   _sb19, _sb16, _sb18, _sb21]:
		if sb != null and is_instance_valid(sb):
			sb.free()
