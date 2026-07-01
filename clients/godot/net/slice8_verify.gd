extends SceneTree
# Headless slice-8 gate-3 verifier (the slice2..7_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-8's ballistic
# "done" criterion as machine checks. Start it against the slice8_ballistic server (it serves one
# client then exits). ALL assertions on the SCALAR telemetry (de_frac / alt / speed / impacted) + the
# :impact EVENT; never on the display-only trail.
#
#   1. handshake carries `fidelity.integrator == rk4` (→ the missile-view discriminator; the view
#      stays SPATIAL) + the cd_area_m2 slider, and NO range_axis_m / pri_axis_us / estimator / raim /
#      cfar / ep / propagation (a missile scene is single-domain — one lesson per scenario);
#   2. PARABOLA — under the default rk4 + drag off, RK4 integrates the constant-g parabola EXACTLY, so
#      at a MID-FLIGHT sample (t=8 s) the energy-conservation error `de_frac` (ΔE/E₀) ≈ 0 (probed
#      −5.5e-14, machine eps) — the clean conserved arc;
#   3. EULER (the integrator fidelity is LIVE) — reset (→ rk4, drag off) then `set_fidelity integrator
#      euler`, replay to the SAME t: euler does NOT conserve — |de_frac| jumps to ~1e-5 (probed
#      +1.2e-5), ORDERS above rk4 (asserted by MAGNITUDE, not sign — euler's energy drift is phase-
#      dependent, the slice's own "don't over-pin sign" discipline), at a bit-identical t. The
#      not-a-dead-knob: dialing the integrator CHANGES the physics (unlike the slice-5/6/7 draw-free
#      toggles);
#   4. DRAG — reset then `set_param cd_area_m2 = 0.02` (the ONE live in-flight lever, well-defined
#      mid-flight): quadratic drag BLEEDS energy monotonically, so at t=8 s `de_frac` goes clearly
#      negative (probed −0.79) and the missile is lower/shorter — the energy-dissipation lesson;
#   5. IMPACT — reset then step PAST the ground crossing (t=37 s > T≈36.05 s): the missile emits
#      exactly ONE `:impact` event (accumulated across the drained burst — it is one-shot, cleared
#      after its frame — the slice-6/7 event-drain pattern) and latches `impacted == true`, `speed==0`.
#
# Determinism (slice 8 has NO RNG — the trajectory is a closed-form ODE solve): the trace at a given t
# is bit-identical for a fixed config, and `step n` lands the clock at exactly n·dt, so each leg
# samples an identical t. `reset` reloads the YAML → the defaults (rk4, drag off), so it MUST precede
# each set_fidelity/set_param (else it clobbers the toggle/slider). `:integrator` is introduce-safe.
#
# Run (server must be listening on slice8_ballistic.yaml first):
#   godot --headless --path clients/godot --script res://net/slice8_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 180.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit of a burst lands exactly on the target
# t (the slice-2/6/7 drain contract — an off-multiple count leaves the last frame short and the drain
# times out). 8000 = 500·16 → t=8.0 s (mid-flight for rk4/euler/drag: drag cd=0.02 impacts at T≈20 s).
# 37008 = 2313·16 → t=37.008 s, past the drag-off impact T≈36.05 s.
const STEPS_MID := 8000
const STEPS_IMPACT := 37008
const DE_RK4_MAX := 1.0e-6       # rk4 drag-off |de_frac| below this at t=8 s (probed 5.5e-14)
const DE_EULER_MIN := 1.0e-6     # euler |de_frac| above this (probed 1.2e-5) — not-a-dead-knob
const DE_DRAG_MAX := -0.1        # drag-on de_frac below this at t=8 s (probed −0.79) — energy bled

enum P { HANDSHAKE, PARABOLA, EULER, DRAG, IMPACT }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""                   # missile entity id (discovered from the state stream)
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

var _de_rk4 := 0.0
var _t_rk4 := 0.0
var _alt_rk4 := 0.0
var _impact_events := 0          # accumulated across the IMPACT drain burst (one-shot events)

func _initialize() -> void:
	print("S8V_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt_frame: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		return _fail("TIMEOUT in phase %s" % P.keys()[_phase], 2)
	_client.poll()

	match _phase:
		P.HANDSHAKE:
			var f := _take("scenario")
			if f.is_empty():
				return false
			var verr := _check_handshake(f)
			if verr != "":
				return _fail(verr)
			_dt = float(f.get("dt_physics", 1.0e-3))
			_begin_step(STEPS_MID, P.PARABOLA)

		P.PARABOLA:
			if not _drain_to_T():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream (telemetry prefix unknown)")
			_de_rk4 = _tel(_mid + ".de_frac")
			_alt_rk4 = _tel(_mid + ".alt")
			_t_rk4 = float(_last_state.get("t", -1.0))
			print("S8V_PARABOLA mid=%s de_frac=%s alt=%.1f t=%.4f (rk4, drag off)" %
				[_mid, str(_de_rk4), _alt_rk4, _t_rk4])
			if not (_alt_rk4 > 0.0):
				return _fail("mid-flight altitude must be > 0 (got %.2f) — sampled off the arc" % _alt_rk4)
			if absf(_de_rk4) > DE_RK4_MAX:
				return _fail("rk4 drag-off must conserve energy (|de_frac| < %s), got %s" % [str(DE_RK4_MAX), str(_de_rk4)])
			# EULER: reset (→ rk4, drag off) then integrator euler, replay to the SAME t.
			_reset_then_step([_set_fidelity_cmd("integrator", "euler")], STEPS_MID, P.EULER)

		P.EULER:
			if not _drain_to_T():
				return false
			var de := _tel(_mid + ".de_frac")
			var t_eu := float(_last_state.get("t", -1.0))
			print("S8V_EULER de_frac=%s (rk4 %s) |ratio|=%s t=%.4f (rk4 t=%.4f)" %
				[str(de), str(_de_rk4), str(absf(de) / maxf(absf(_de_rk4), 1.0e-300)), t_eu, _t_rk4])
			if absf(t_eu - _t_rk4) > 0.5 * _dt:
				return _fail("euler sample t must be bit-identical to rk4 (%.4f vs %.4f)" % [t_eu, _t_rk4])
			# magnitude, not sign (euler's energy drift is phase-dependent — slice-8 discipline)
			if absf(de) < DE_EULER_MIN:
				return _fail("euler must NOT conserve — |de_frac| ≥ %s expected, got %s" % [str(DE_EULER_MIN), str(de)])
			if absf(de) < 100.0 * absf(_de_rk4):
				return _fail("euler |de_frac| (%s) must be orders above rk4 (%s) — the not-a-dead-knob" % [str(de), str(_de_rk4)])
			# DRAG: reset then set cd_area, replay to the SAME t.
			_reset_then_step([_set_param_cmd(_mid, "cd_area_m2", 0.02)], STEPS_MID, P.DRAG)

		P.DRAG:
			if not _drain_to_T():
				return false
			var de := _tel(_mid + ".de_frac")
			var alt := _tel(_mid + ".alt")
			print("S8V_DRAG cd=0.02 de_frac=%.4f alt=%.1f (drag-off alt %.1f) t=%.4f" %
				[de, alt, _alt_rk4, float(_last_state.get("t", -1.0))])
			if not (de < DE_DRAG_MAX):
				return _fail("drag must bleed energy (de_frac < %s), got %.4f" % [str(DE_DRAG_MAX), de])
			if not (alt < _alt_rk4):
				return _fail("drag must shorten the arc (alt %.1f < drag-off %.1f)" % [alt, _alt_rk4])
			# IMPACT: reset (→ default rk4, drag off) then step PAST the ground crossing.
			_impact_events = 0
			_reset_then_step([], STEPS_IMPACT, P.IMPACT)

		P.IMPACT:
			# accumulate :impact events across the whole drained burst (one-shot, cleared per frame)
			if not _drain_to_T_events():
				return false
			var impacted := bool(_last_state.get("telemetry", {}).get(_mid + ".impacted", false))
			var speed := _tel(_mid + ".speed")
			print("S8V_IMPACT events=%d impacted=%s speed=%.4f t=%.4f" %
				[_impact_events, str(impacted), speed, float(_last_state.get("t", -1.0))])
			if _impact_events != 1:
				return _fail("the missile must emit EXACTLY one :impact event, got %d" % _impact_events)
			if not impacted:
				return _fail("the missile must latch impacted=true after the ground crossing")
			if absf(speed) > 1.0e-9:
				return _fail("an impacted missile must freeze (speed 0), got %s" % str(speed))
			return _pass()
	return false

# --- stepping / draining (the slice-4/5/6/7 contract) -------------------------------------

func _begin_step(n: int, next: P) -> void:
	var base := _now_t()
	_inbox.clear()
	_last_state = {}
	_t_target = base + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_then_step(cmds: Array, n: int, next: P) -> void:
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt          # reset zeroes the clock
	_client.send({"type": "step", "n": n})
	_phase = next

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

func _drain_to_T() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# Impact variant: also accumulate any :impact events that this missile fired on each drained frame
# (they are one-shot — the server clears them after the frame they ship on, so keeping only the last
# frame would miss the impact, which fires ~mid-burst — the slice-6/7 event-accumulation pattern).
func _drain_to_T_events() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		for ev in f.get("events", []):
			if str(ev.get("kind", "")) == "impact" and str(ev.get("of", "")) == _mid:
				_impact_events += 1
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

# --- helpers ------------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _find_missile(state: Dictionary) -> String:
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "missile":
			return str(e.get("id", ""))
	return ""

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (missile-view discriminator / §12 badge blind)"
	if not fid.has("integrator"):
		return "a missile scenario handshake must carry `integrator` (the missile-view discriminator)"
	if str(fid.get("integrator", "")) != "rk4":
		return "slice8_ballistic default integrator should be 'rk4' (the clean conserved parabola), got '%s'" % str(fid.get("integrator", ""))
	# one lesson per scenario: no other-slice fidelity keys, no cfar/esm/geoloc/gps view axes
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim"]:
		if fid.has(other):
			return "a missile scenario should carry ONLY `integrator` (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a missile scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the cd_area_m2 slider must be exposed (the one live lever)
	var has_cd := false
	for k in f.get("knobs", []):
		if str(k.get("key", "")) == "cd_area_m2":
			has_cd = true
	if not has_cd:
		return "slice8_ballistic handshake must expose the cd_area_m2 (drag) slider"
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _tel(key: String) -> float:
	var tel: Dictionary = _last_state.get("telemetry", {})
	return float(tel.get(key, -1.0e30)) if tel.has(key) else -1.0e30

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S8V OK: rk4 conserves the constant-g parabola to machine eps; euler drifts ΔE (orders " +
		"above rk4, the not-a-dead-knob physics-changing fidelity); the cd_area slider bleeds energy " +
		"(de_frac negative, arc shortens); the missile emits one :impact event and freezes at z=0")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S8V FAIL: " + msg)
	print("S8V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
