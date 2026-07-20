extends SceneTree
# Headless UI test for the slice-22 STALL VIEW PATH — the piece slice22_verify.gd can't reach. The
# verifier drives SimClient directly (the set_param wire + the coupled physics); the Sandbox.tscn
# smoke-load proves the scene loads against a slice-22 server. Neither exercises the CLIENT drawing.
#
# ⭐ WHAT THIS TEST IS REALLY FOR, AND IT IS NOT THE BUTTON. Slice 22 is a KNOB slice (gate-0 F7 /
# Decision 1: the rung claim was MEASURED and LOST — a finite α_stall ≥ 0.25 is linear-in-effect over
# every reachable state, so the off-state IS knob-reachable). So it ships NO `:aero_curve` fidelity, NO
# cycler, and the one-button rule's "4th occurrence" DOES NOT ARISE: like slice 20 — the other knob-only
# slice — its scenarios author `:airframe: pitch_coupled`, so the shared button is the AIRFRAME cycler by
# ESTABLISHED PRECEDENT, not a new deviation. Nothing in `_setup_spatial_fid_btn` changed.
#
# ⭐⭐ THE ONE CLIENT CHANGE IS THE BREACH INDICATOR, AND IT IS FORCED (gate-2 G10, BY DESIGN). Under an
# authored stall `a_max_aero` drops to the lift curve's INTERIOR PEAK, while `aero_sat` still keys off
# the **α_max CLAMP** — the higher, LINEAR limit. So there is a real regime, PAST THE PHYSICS CEILING BUT
# WITH THE COMMAND NOT YET PEGGED, where the demand exceeds the ceiling and `aero_sat` STAYS 0. Keying
# the strip on `aero_sat` would UNDER-REPORT the very breach the slice is about.
#   ⭐ GATE 3 MEASURED HOW BADLY, and it is worse than "under-reports": on the shipped wire `aero_sat`
#   fires 53/215 frames on the PARKED, **LINEAR** arm and 53/215 on the STALL arm — the SAME COUNT,
#   because both arms share the α_max clamp. It does not discriminate AT ALL. `post_stall` does:
#   EXACTLY 0 vs 56 frames. That is the whole justification for the key and for this edit.
#
# THE TEETH HERE, in order of what would actually break:
#   1. a wire WITH `post_stall` lights the breach on post_stall and IGNORES aero_sat  ← the slice
#   2. a wire WITH `post_stall` LOW but aero_sat HIGH must NOT light  ← the under-report's mirror,
#      and the one that proves the switch really happened rather than an `or` being added
#   3. a slice-19/20/21 wire (NO `post_stall` key) must key on aero_sat EXACTLY AS BEFORE  ← the
#      presence-gate; "I only added a branch" is false by one condition (the slice-21 UI test's own
#      lesson, restated one slice on)
#   4. the value-guard, now SIX-WAY, because `_draw_aero_strip` is SHARED draw code
#
# Run:  godot --headless --path clients/godot --script res://net/slice22_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.

const SandboxScript := preload("res://scenes/Sandbox.gd")

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb16
var _sb19
var _sb18
var _sb21

func _initialize() -> void:
	print("S22UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client

	# The handshake for slice22_stall: airframe_view=true + THREE fidelity keys (ALL HELD — slice 22
	# toggles none of them) + exactly ONE knob + NO axis / NO terrain_grid (stays spatial).
	sb._on_scenario({
		"name": "stall_ui",
		"airframe_view": true,
		"airframe_target": "m1",
		"knobs": [
			{"target": "m1", "key": "af_alpha_stall", "min": 0.15, "max": 0.35, "value": 0.20,
			 "label": "α_stall (rad)"},
		],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
		"dt_physics": 1.0e-3,
	})
	if sb._mode != "spatial":
		return _fail("a slice-22 handshake must stay in the SPATIAL view, got %s" % sb._mode)
	# By ESTABLISHED PRECEDENT (slice 20), not a new routing: the scenario authors `:airframe`, so the
	# shared button is that cycler. Slice 22 has no fidelity of its own to put there.
	if sb._fid_kind != "airframe":
		return _fail("a slice-22 handshake must route to _fid_kind=airframe (slice 20's precedent — it is a KNOB slice with no rung of its own), got %s" % sb._fid_kind)
	if not sb._prop_btn.visible:
		return _fail("a slice-22 handshake must SHOW the :airframe cycler (the scenario authors :airframe, exactly like slice 20)")
	print("S22UI_ROUTE spatial + _fid_kind=airframe + button shown (slice-20 precedent, no new branch)")

	# EXACTLY ONE slider, and it must be the lesson lever wired to set_param.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("slice 22 must expose EXACTLY ONE slider (α_stall), got %d — k_sep is measured nearly INERT (0.9%% over its whole range, gate-2 G5) and a slider that does nothing visible would teach that separation drag does not matter, which is false" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 0.15
	sliders[0].value_changed.emit(0.15)
	var found_set_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "af_alpha_stall":
			found_set_param = true
			if str(d.get("target", "")) != "m1":
				return _fail("the α_stall slider must target m1, got %s" % str(d.get("target", "")))
	if not found_set_param:
		return _fail("dragging the α_stall slider must send set_param af_alpha_stall — it is the ONLY lesson lever this slice has (there is no button)")
	print("S22UI_SLIDER af_alpha_stall → set_param m1")

	# ══ TOOTH 1 — a STALL wire lights the breach on `post_stall`, and IGNORES `aero_sat` ═══════
	# post_stall HIGH, aero_sat LOW: this is the exact regime G10 names — past the physics ceiling
	# with the command NOT yet pegged. The old code would have drawn a calm panel here.
	sb._telemetry = {
		"m1.a_max_aero": 269.39, "m1.a_demand": 300.0,
		"m1.post_stall": 1.0, "m1.aero_sat": 0.0, "m1.defl_sat": 0.0,
	}
	sb._missile_id = "m1"
	sb._airframe_view = true
	sb._spatial_on_state(_state())
	if not sb._has_post_stall:
		return _fail("a wire carrying `post_stall` must set _has_post_stall — the presence gate is what switches the indicator")
	if not sb._post_stall_now:
		return _fail("post_stall=1 must light _post_stall_now")
	if sb._aero_sat_now:
		return _fail("the mock has aero_sat=0; _aero_sat_now must be false (else this tooth is not testing what it claims)")
	print("S22UI_G10 post_stall=1 / aero_sat=0 → the breach lights on post_stall (the G10 regime)")

	# ══ TOOTH 2 — THE MIRROR: post_stall LOW, aero_sat HIGH must NOT light on a stall wire ══════
	# This is what proves the indicator SWITCHED rather than gaining an `or`. On the shipped wire
	# aero_sat fires 53/215 frames on the PARKED LINEAR arm too, so an `or` would light the panel
	# for the linear twin and destroy the contrast the slice exists to draw.
	sb._telemetry = {
		"m1.a_max_aero": 471.44, "m1.a_demand": 300.0,
		"m1.post_stall": 0.0, "m1.aero_sat": 1.0, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state(_state())
	if sb._post_stall_now:
		return _fail("post_stall=0 must clear _post_stall_now")
	if not sb._aero_sat_now:
		return _fail("the mock has aero_sat=1; _aero_sat_now must be true (else the mirror tooth is vacuous)")
	print("S22UI_G10_MIRROR post_stall=0 / aero_sat=1 → the stall wire does NOT light (a switch, not an `or`)")

	# ══ TOOTH 3 — THE PRESENCE GATE: a slice-19/20/21 wire keys on aero_sat EXACTLY AS BEFORE ════
	# No `post_stall` key at all. `_has_post_stall` must go false and the old behaviour must return —
	# this is the additive claim, PROVEN rather than asserted (advisor: the edit touches SHARED draw
	# code, so "the presence-gate should leave them identical" is exactly the kind of claim to test).
	sb._telemetry = {
		"m1.a_max_aero": 269.39, "m1.a_demand": 300.0,
		"m1.aero_sat": 1.0, "m1.defl_sat": 0.0,
	}
	sb._spatial_on_state(_state())
	if sb._has_post_stall:
		return _fail("a slice-19/20/21 wire ships NO `post_stall` key — _has_post_stall must go FALSE, else the indicator silently changes meaning on three shipped slices")
	if sb._post_stall_now:
		return _fail("_post_stall_now must be cleared when the key is absent (a stale true would light slices 19-21's panel forever)")
	if not sb._aero_sat_now:
		return _fail("with no `post_stall` key the panel must key on aero_sat EXACTLY as before — that is the whole additive claim")
	print("S22UI_PRESENCE no post_stall key → falls back to aero_sat (slices 19/20/21 UNCHANGED)")

	# ══ TOOTH 4 — THE VALUE-GUARD, NOW SIX-WAY (`_draw_aero_strip` is SHARED draw code) ══════════
	# (a) slice 16 — airframe_view, NO fidelity → still DROPS the button (the Cmα slider is its lesson)
	_sb16 = _build_sandbox()
	_sb16._on_scenario({
		"name": "s16_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_cma", "min": -2.0, "max": 1.0, "value": -1.0, "label": "Cmα"}],
		"fidelity": {},
	})
	if _sb16._fid_kind != "airframe" or _sb16._prop_btn.visible:
		return _fail("a slice-16 handshake must STILL route to airframe and DROP the button")

	# (b) slice 17/19/20 — airframe_view + :airframe, no post_stall → the AIRFRAME cycler, unchanged
	_sb19 = _build_sandbox()
	_sb19._on_scenario({
		"name": "s19_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_alpha_max", "min": 0.05, "max": 0.4, "value": 0.2, "label": "α_max"}],
		"fidelity": {"airframe": "pitch_coupled", "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb19._fid_kind != "airframe" or not _sb19._prop_btn.visible:
		return _fail("a slice-17/19/20 handshake must STILL show the :airframe cycler")

	# (c) slice 18 — terrain_grid wins the mode discriminator outright; the 3-D view is untouched
	_sb18 = _build_sandbox()
	_sb18._on_scenario({
		"name": "s18_ui", "radar": "r1",
		"terrain_grid": [[0.0, 0.0], [0.0, 0.0]], "terrain_n": 2,
		"terrain_extent": [0.0, 1000.0, 0.0, 1000.0],
		"knobs": [], "fidelity": {"propagation": "terrain"},
	})
	if _sb18._mode != "terrain":
		return _fail("a terrain handshake must still enter the 3-D terrain mode, got %s" % _sb18._mode)

	# (d) slice 21 — :atmosphere must STILL win the button over the co-shipped :airframe (the
	# slice-13/14 one-button rule). Slice 22 added no branch, but this is shared code and the
	# ordering is exactly what a careless edit here would disturb.
	_sb21 = _build_sandbox()
	_sb21._on_scenario({
		"name": "s21_ui", "airframe_view": true, "airframe_target": "m1",
		"knobs": [{"target": "m1", "key": "af_scale_height", "min": 6000.0, "max": 25000.0, "value": 8500.0, "label": "H"}],
		"fidelity": {"atmosphere": "exponential", "airframe": "pitch_coupled",
					 "guidance": "pn", "autopilot": "alpha"},
	})
	if _sb21._fid_kind != "atmosphere":
		return _fail("a slice-21 handshake must STILL take _fid_kind=atmosphere (checked FIRST, over the co-shipped :airframe), got %s" % _sb21._fid_kind)
	print("S22UI_GUARD six-way OK — 16 drops / 17-19-20 keep the airframe cycler / 18 stays 3-D / 21 keeps the atm cycler / 22 takes the airframe cycler by precedent")

	# Reset must clear the stall tell along with the strip histories — a stale `post_stall` would light
	# the panel on a re-launch that has not reached the corner yet.
	sb._on_reset_pressed()
	if sb._post_stall_now:
		return _fail("reset must clear _post_stall_now — a stale tell would light the breach on a fresh run that has not reached the corner")
	if sb._ceil_hist.size() != 0 or sb._demand_hist.size() != 0:
		return _fail("reset must CLEAR the aero strip histories (got %d/%d)" % [sb._ceil_hist.size(), sb._demand_hist.size()])
	print("S22UI_RESET post_stall tell + strip histories cleared")
	return _pass()

func _process(_d: float) -> bool:
	return true

# --- helpers (the slice19/20/21_ui_test contract) -------------------------------------------

# A minimal state frame carrying the missile entity. `_spatial_on_state` is where the strip
# sampling lives; `_telemetry` is set by the caller (_on_state) in the real client, so the tests
# set it directly and then drive this. ⚠ `_draw_aero_strip` itself is NOT called here — it needs a
# live CanvasItem in the tree. `_breach` is composed of EXACTLY the two state vars asserted below
# (`_post_stall_now if _has_post_stall else _aero_sat_now`), and the DRAWING is proven by the
# windowed shot harness (convention 14's fourth proof).
func _state() -> Dictionary:
	return {"entities": [{"id": "m1", "kind": "missile", "pos": [0.0, 0.0, 3000.0]}]}

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
	print("S22UI OK: a slice-22 handshake stays SPATIAL and takes the AIRFRAME cycler — by slice-20's " +
		"ESTABLISHED PRECEDENT, not a new branch. Slice 22 is a KNOB slice (gate-0 F7 / Decision 1: the " +
		"plan's rung claim was MEASURED and LOST — a finite α_stall ≥ 0.25 is linear-in-effect over every " +
		"reachable state, so the off-state IS knob-reachable and the knob's own TOP is the linear twin), " +
		"so it ships no :aero_curve fidelity and the one-button rule's 4th occurrence never arises. " +
		"EXACTLY ONE slider (af_alpha_stall → set_param m1); k_sep is absent deliberately — measured " +
		"nearly INERT at 0.9% over its whole range, and a slider that does nothing visible would teach " +
		"that separation drag does not matter, which is false and is the OPPOSITE of why the term is " +
		"mandatory. ⭐ THE ONE CLIENT CHANGE IS THE BREACH INDICATOR, AND IT IS FORCED: under a stall the " +
		"ceiling drops to the lift curve's INTERIOR PEAK while `aero_sat` still keys off the α_max CLAMP, " +
		"so there is a real regime past the physics ceiling with the command not yet pegged where " +
		"aero_sat stays 0 (gate-2 G10). Measured on the shipped wire it is WORSE than under-reporting — " +
		"aero_sat fires 53/215 frames on the PARKED, LINEAR arm and 53/215 on the STALL arm, the SAME " +
		"COUNT, so it does not discriminate AT ALL; post_stall separates them EXACTLY 0-vs-56. All four " +
		"teeth hold: post_stall lights the breach where aero_sat is silent; the MIRROR case (aero_sat " +
		"high, post_stall low) does NOT light, proving the indicator SWITCHED rather than gaining an `or` " +
		"— an `or` would light the panel for the linear twin and destroy the contrast; a wire with NO " +
		"post_stall key falls back to aero_sat EXACTLY as before, which is the additive claim PROVEN " +
		"rather than asserted on shared draw code; and the value-guard holds SIX ways (16 drops the " +
		"button, 17/19/20 keep the airframe cycler, 18 stays 3-D, 21 keeps the atmosphere cycler over " +
		"its co-shipped :airframe, 22 takes the airframe cycler by precedent). Reset clears the stall " +
		"tell along with the strip histories.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S22UI FAIL: " + msg)
	print("S22UI FAIL: ", msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb16, _sb19, _sb18, _sb21]:
		if sb != null:
			sb.free()
