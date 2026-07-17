extends SceneTree
# Headless slice-19 gate-3 verifier (the slice8..18_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-19's inner α/g
# autopilot "done" criteria as machine checks on the SCALAR telemetry (los_range / a_max_aero / aero_sat
# / defl_sat / q_dyn / pos_*). The lesson: with the guidance command inverted through the aero
# (a_cmd → α_cmd → δ), the achievable maneuver accel IS the FLIGHT-CONDITION lift ceiling
# `a_max_aero = Q·S·C_Lα·α_max/m` — so the SAME PN law that HITS on the slice-10 point-mass plant
# MISSES on the coupled airframe, because the air will not give it the g it is asking for. SIX phases:
#   • COUPLED        — the default :pitch_coupled MISSES (frame CPA ≈ 295 m); the aero ceiling BINDS
#                      (aero_sat lit on most of the approach); the ISOLATION holds (defl_sat == 0 and
#                      the STRUCTURAL max(a_max_aero) < a_max). The baseline trace.
#   • COUPLED_REPLAY — reset + replay the SAME config → the pos trace is BIT-IDENTICAL (class-4c
#                      RNG-FREE determinism — truth-fed PN, no seeker, no w.rng draw).
#   • POINT_MASS     — reset + set_fidelity airframe → point_mass (the LIVE toggle, the ONE button):
#                      the SAME PN law HITS. The separation is asserted as a RATIO (see the sampling
#                      note) — the non-dead toggle, the INVERSE of slice-16's posdiff = 0.0.
#   • RHO_LEVER      — reset + set_param rho → 0.6 (THE DEMO LEVER): thinner air ⇒ the ceiling FALLS
#                      LIVE (≈ 269 → 132, a 2× drop) and aero_sat CLIMBS. Asserts the CEILING MOVES —
#                      NOT a hit (ρ is confounded: ω_sp ∝ √ρ moves the ceiling AND the response speed
#                      together, so it can never be the causation proof; it is the physical story).
#   • ALPHA_CAUSE    — reset + set_param af_alpha_max → 1.5 (THE CAUSATION LEVER, ρ/speed/geometry ALL
#                      HELD): α_max enters ONLY the α_cmd clamp — it is ABSENT from pitch_moment,
#                      lift_accel and short_period_freq — so it moves the ceiling ALONE. The miss
#                      COLLAPSES ⇒ the ceiling CAUSED it. BINDING ≠ CAUSING; this phase is the only
#                      thing that licenses the causal claim.
#
# THE ISOLATION IS STRUCTURAL — do NOT copy slice-15's `saturated == 0` (it FAILS here, by design).
# a_max = 3000 clamps ~560× in the guided window and is INERT (proven bit-for-bit at a_max = 1e7):
# it clamps a_cmd UPSTREAM of the α inversion, and since a_max_aero < a_max the clamped demand STILL
# pegs α_cmd at ±α_max — the tighter clamp wins downstream. So we assert max(a_max_aero) < a_max
# (269 < 3000) and defl_sat == 0 (the FOURTH cap, δ_max, stays clear).
#
# THE "BINDS" ASSERTION KEYS OFF `aero_sat`, NEVER A HAND-ROLLED `a_demand > a_max_aero` (gate-2
# finding): `aero_sat` fires on |a_perp| (the ⟂-v PROJECTION of the command) while `a_demand` is the
# FULL-magnitude pre-clamp demand, and |a_perp| ≤ |a_cmd| ≤ |a_dem| ⇒ the sets NEST. A hand-rolled
# compare would read "breached" earlier and more often than the flag (the along-v̂ component reaches
# 0.55·|a_cmd| and is unproducible by an airframe — which is exactly why the flag reads 59%, not more).
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). The verifier sees state frames
# every emit_every (16) ticks; closing speed at CPA ≈ 1373 m/s ⇒ frames land ≈ 22 m apart near CPA.
# Measured on the live wire (wire.jl): a TRUE 0.276 m point-mass CPA frame-samples to 3.84 m, and the
# relaxed-α_max twin's TRUE 13.12 m samples to 16.82 m. So:
#   • SUB-METRE IS UNREACHABLE — an absolute `pm < 1 m` bound would FAIL on a hit.
#   • The COUPLED side samples faithfully (true 295.168 → frame 295.186) — only the HIT side is coarse.
#   • The causation arm is asserted as a RELATIVE drop, not a tight absolute floor: a `< 20 m` bound
#     would sit only 3.2 m above the measured 16.82 and shift with where CPA falls between frames.
# All bounds below are pinned against the FRAME-SAMPLED live-wire numbers, never the true CPA.
#
# Everything is RNG-FREE (truth-fed PN, no seeker) so "draw-count invariance" is VACUOUS (class 4c) —
# do NOT copy slice-11/13 draw language. CPA is measured from the core's own `los_range` telemetry on
# the FIRST DESCENDING BAND only (the target outruns the missile at |v| ≈ 825 > 700, so the first CPA
# is the honest one — but the latch is explicit, not a hope).
#
# Run (server must be listening on slice19_alpha_limit.yaml first):
#   godot --headless --path clients/godot --script res://net/slice19_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 5120 = 320·16 = 5.12 s — the CPA lands at ≈ 4.13 s on every arm, so the first-descending band is
# closed and latched well before the drain ends.
const STEPS := 5120

const A_MAX := 3000.0             # the scenario's authored g-limit — INERT (the structural isolation)
const RHO_THIN := 0.6             # the demo lever's floor (≈ 7 km ISA; the monotone-region bound)
const ALPHA_MAX_RELAXED := 1.5    # the causation lever (measured: true 13.12 → frame 16.82)

# Bounds — ALL pinned against the FRAME-SAMPLED live wire (wire.jl), conservative:
const COUPLED_MISS_MIN := 250.0   # coupled frame CPA (measured 295.19) — the aero ceiling opens the miss
const PM_HIT_MAX := 30.0          # point_mass frame CPA (measured 3.84; true 0.276 — sub-metre unreachable)
const RATIO_MIN := 8.0            # coupled/point_mass frame ratio (measured 76.8× — 9.6× margin)
const AERO_SAT_FRAC_MIN := 0.40   # aero_sat share of the sampled approach (measured ≈ 0.59)
const CEIL_FALL_MAX := 0.60       # ρ→0.6 must drop the ceiling to < 0.60× the default (measured 0.49×)
const CAUSE_MISS_MAX := 30.0      # relaxed-α_max frame CPA (measured 16.82) — absolute sanity
const CAUSE_RATIO_MAX := 0.20     # …AND < 0.20× the coupled miss (measured 0.057× — the real tooth)
const ENDGAME_RANGE := 300.0      # sample the ceiling/flags only while los_range > this (the r→0 spike)

enum P { HANDSHAKE, COUPLED, COUPLED_REPLAY, POINT_MASS, RHO_LEVER, ALPHA_CAUSE }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _name := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0

# scan accumulators (reset per burst)
var _min_los := 1.0e30            # CPA on the FIRST DESCENDING BAND only
var _prev_los := 1.0e30
var _closing := true              # latched false at the first ascent (no post-CPA re-crossing)
var _past_endgame := false
var _aero_sat_n := 0              # frames with the AERO ceiling binding (the LESSON flag)
var _defl_sat_n := 0              # frames with δ_max binding (the ISOLATION — must stay 0)
var _sampled_n := 0               # frames sampled on the approach (the fraction's denominator)
var _ceil_max := 0.0              # max a_max_aero on the approach (the STRUCTURAL isolation)
var _ceil_min := 1.0e30
var _qdyn_max := 0.0
var _alpha_keys := false          # the rung-gated slice-19 telemetry ships
var _pos_trace: Array = []        # per-frame [pos_x, pos_z] — the replay comparison
# recorded across phases
var _coupled_pos: Array = []
var _coupled_miss := 0.0
var _coupled_ceil := 0.0
var _coupled_sat_frac := 0.0
var _pm_miss := 0.0

func _initialize() -> void:
	print("S19V_INIT godot=", Engine.get_version_info().string)
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
			_name = str(f.get("name", ""))
			_begin_scan(STEPS, P.COUPLED)

		# --- :pitch_coupled — the airframe cannot make the g PN asks for → it MISSES ---------------
		P.COUPLED:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_coupled_pos = _pos_trace.duplicate(true)
			_coupled_miss = _min_los
			_coupled_ceil = _ceil_max
			_coupled_sat_frac = _sat_frac()
			print("S19V_COUPLED miss(frame)=%.3f  a_max_aero=[%.2f, %.2f]  q_dyn_max=%.0f  aero_sat=%d/%d (%.1f%%)  defl_sat=%d  keys=%s" %
				[_min_los, _ceil_min, _ceil_max, _qdyn_max, _aero_sat_n, _sampled_n, 100.0 * _coupled_sat_frac, _defl_sat_n, str(_alpha_keys)])
			if not _alpha_keys:
				return _fail("the :alpha rung must ship the α/g telemetry (a_max_aero / aero_sat / alpha_cmd / delta_cmd)")
			if not (_min_los > COUPLED_MISS_MIN):
				return _fail(":pitch_coupled must MISS — the aero ceiling caps the achievable g (frame CPA > %.0f m), got %.2f" % [COUPLED_MISS_MIN, _min_los])
			# THE LESSON FLAG — keyed off `aero_sat`, NEVER a hand-rolled a_demand > a_max_aero.
			if not (_coupled_sat_frac > AERO_SAT_FRAC_MIN):
				return _fail("the AERO ceiling must BIND on the approach (aero_sat > %.0f%% of sampled frames), got %.1f%%" % [100.0 * AERO_SAT_FRAC_MIN, 100.0 * _coupled_sat_frac])
			# THE ISOLATION — STRUCTURAL, not `saturated == 0` (which FAILS: a_max clamps ~560× INERTLY).
			if not (_ceil_max < A_MAX):
				return _fail("the ISOLATION requires max(a_max_aero) < a_max (%.1f < %.0f) — else this is slice-10's magnitude clamp in an airframe costume" % [_ceil_max, A_MAX])
			if _defl_sat_n != 0:
				return _fail("the FOURTH cap (δ_max) must NOT bind — defl_sat must stay 0, got %d frames (it would contaminate the lesson)" % _defl_sat_n)
			_reset_then_scan([], STEPS, P.COUPLED_REPLAY)

		P.COUPLED_REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_coupled_pos, _pos_trace)
			print("S19V_REPLAY posdiff_vs_coupled=%s m  miss=%.3f (must be 0.0 / identical — class-4c RNG-free)" % [rdiff, _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % rdiff)
			if not (_min_los == _coupled_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _coupled_miss])
			_reset_then_scan([_set_fidelity_cmd("airframe", "point_mass")], STEPS, P.POINT_MASS)

		# --- :point_mass — the slice-10 plant: a_ctrl by fiat → the SAME PN law HITS ---------------
		P.POINT_MASS:
			if not _drain_scan():
				return false
			_pm_miss = _min_los
			var ratio := _coupled_miss / maxf(_pm_miss, 1.0e-9)
			print("S19V_POINT_MASS miss(frame)=%.3f  ratio=%.1fx  aero_sat=%d/%d  a_max_aero=%.2f (shipped under BOTH arms)" %
				[_pm_miss, ratio, _aero_sat_n, _sampled_n, _ceil_max])
			if not (_pm_miss < PM_HIT_MAX):
				return _fail(":point_mass must HIT (frame CPA < %.0f m — sub-metre is UNREACHABLE on the wire), got %.2f" % [PM_HIT_MAX, _pm_miss])
			if not (ratio > RATIO_MIN):
				return _fail("the :airframe toggle must be NON-DEAD: coupled/point_mass frame ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			# The ceiling is a FLIGHT-CONDITION property — shipped under BOTH arms (the deliberate
			# contrast to slice-17's coupled-only lift keys). Under :point_mass the demand crosses it
			# and the missile HITS ANYWAY — the plant simply ignores it. That IS the contrast.
			if not (_ceil_max > 0.0):
				return _fail(":point_mass must STILL ship a_max_aero (a flight-condition property, not a produced force)")
			_reset_then_scan([_set_param_cmd("m1", "rho", RHO_THIN)], STEPS, P.RHO_LEVER)

		# --- ρ → 0.6 — THE DEMO LEVER: the ceiling is a FLIGHT CONDITION, and it MOVES -------------
		P.RHO_LEVER:
			if not _drain_scan():
				return false
			var fall := _ceil_max / maxf(_coupled_ceil, 1.0e-9)
			print("S19V_RHO_LEVER rho=%.2f  a_max_aero=%.2f (was %.2f) = %.2fx  q_dyn_max=%.0f  aero_sat=%.1f%% (was %.1f%%)  miss=%.2f" %
				[RHO_THIN, _ceil_max, _coupled_ceil, fall, _qdyn_max, 100.0 * _sat_frac(), 100.0 * _coupled_sat_frac, _min_los])
			# THE TRIPWIRE THE DEAD `speed` KNOB SLIPPED THROUGH: a knob must MOVE THE PHYSICS, not
			# merely fail to crash. (`speed` was the plan's demo lever until gate 3 found it is
			# consumed ONCE at load and read by NOTHING per-tick — a live set_param wrote a key no
			# consumer reads. `rho` is fetched every tick by both integrate! and decide!.)
			if not (fall < CEIL_FALL_MAX):
				return _fail("the ρ demo lever must MOVE the ceiling: thinning the air to %.1f must drop a_max_aero below %.2fx, got %.2fx — a knob that changes nothing is a DEAD knob" % [RHO_THIN, CEIL_FALL_MAX, fall])
			if not (_sat_frac() > _coupled_sat_frac):
				return _fail("thinner air must make the ceiling bind MORE (aero_sat %.1f%% must exceed the default's %.1f%%)" % [100.0 * _sat_frac(), 100.0 * _coupled_sat_frac])
			if _defl_sat_n != 0:
				return _fail("the ρ lever must keep the 4th cap clear (defl_sat == 0), got %d" % _defl_sat_n)
			_reset_then_scan([_set_param_cmd("m1", "af_alpha_max", ALPHA_MAX_RELAXED)], STEPS, P.ALPHA_CAUSE)

		# --- α_max → 1.5 — THE CAUSATION PROOF: BINDING ≠ CAUSING ----------------------------------
		P.ALPHA_CAUSE:
			if not _drain_scan():
				return false
			var drop := _min_los / maxf(_coupled_miss, 1.0e-9)
			print("S19V_ALPHA_CAUSE alpha_max=%.2f (rho/speed HELD)  miss(frame)=%.3f (was %.3f) = %.3fx  aero_sat=%.1f%%  defl_sat=%d  recovered=%.1f m (%.1f%%)" %
				[ALPHA_MAX_RELAXED, _min_los, _coupled_miss, drop, 100.0 * _sat_frac(), _defl_sat_n, _coupled_miss - _min_los, 100.0 * (1.0 - drop)])
			# Relative AND absolute — the relative bound is the real tooth (the absolute one sits only
			# ~13 m above the measured 16.82 and would shift with where CPA falls between frames).
			if not (_min_los < CAUSE_MISS_MAX):
				return _fail("relaxing α_max ALONE must CLOSE the miss (frame CPA < %.0f m), got %.2f" % [CAUSE_MISS_MAX, _min_los])
			if not (drop < CAUSE_RATIO_MAX):
				return _fail("relaxing α_max ALONE must recover the miss to < %.2fx the coupled default, got %.3fx — without this the ceiling is only shown to BIND, not to CAUSE" % [CAUSE_RATIO_MAX, drop])
			# The 4th cap must stay clear THROUGHOUT the counterfactual — gate 0's first causation twin
			# was contaminated by δ_max silently capping α at ≈(Cmd/|Cma|)·δ_max while α_max was relaxed.
			if _defl_sat_n != 0:
				return _fail("the causation twin must keep δ_max NON-binding (defl_sat == 0), got %d — relaxing one cap while another binds is the false-claim trap one level down" % _defl_sat_n)
			# …and the residual must NOT collapse to the point-mass hit: the ~13 m floor is the
			# airframe+autopilot DYNAMIC TRACKING COST (a §1 named approximation of the :pitch_coupled
			# plant) — NOT "short-period lag" (unearned) and NOT a projection effect (refuted at
			# −0.081 m). The lesson survives it intact at 95.6% of the miss.
			if not (_min_los > _pm_miss):
				return _fail("the relaxed twin must NOT reach the point-mass CPA (%.2f vs %.2f) — the dynamic tracking cost is real and must not be papered over" % [_min_los, _pm_miss])
			return _pass()
	return false

# --- stepping / scanning (the slice-10..18 contract) --------------------------------------

func _begin_scan(n: int, next: P) -> void:
	_reset_scan_accum()
	_inbox.clear()
	_last_state = {}
	_t_target = _now_t() + n * _dt
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_then_scan(cmds: Array, n: int, next: P) -> void:
	_reset_scan_accum()
	_inbox.clear()
	_last_state = {}
	_client.send({"type": "reset"})
	for c in cmds:
		_client.send(c)
	_t_target = n * _dt              # reset zeroes the clock
	_client.send({"type": "step", "n": n})
	_phase = next

func _reset_scan_accum() -> void:
	_min_los = 1.0e30
	_prev_los = 1.0e30
	_closing = true
	_past_endgame = false
	_aero_sat_n = 0
	_defl_sat_n = 0
	_sampled_n = 0
	_ceil_max = 0.0
	_ceil_min = 1.0e30
	_qdyn_max = 0.0
	_alpha_keys = false
	_pos_trace = []

func _sat_frac() -> float:
	return float(_aero_sat_n) / maxf(float(_sampled_n), 1.0)

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

# Scan: CPA on the FIRST DESCENDING BAND (the target outruns the missile so the first CPA is the honest
# one — but latch it explicitly rather than trusting the geometry: [[ewsim-missile-verifier-sampling]]),
# plus the ceiling / flag accumulators sampled ONLY while los_range > ENDGAME_RANGE on that approach
# (the r→0 endgame spikes the demand, and a post-CPA re-crossing would re-light the flags).
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mid == "":
			_mid = _find_missile(f)
		var tel: Dictionary = f.get("telemetry", {})
		if _mid != "" and tel.has(_mid + ".pos_x"):
			_pos_trace.append([float(tel.get(_mid + ".pos_x", 0.0)), float(tel.get(_mid + ".pos_z", 0.0))])
		if _mid != "" and tel.has(_mid + ".los_range"):
			var r := float(tel[_mid + ".los_range"])
			if r > _prev_los:
				_closing = false          # CPA passed — stop accumulating (no re-crossing)
			if _closing:
				_min_los = minf(_min_los, r)
			_prev_los = r
			if r <= ENDGAME_RANGE:
				_past_endgame = true
			if _closing and not _past_endgame and r > ENDGAME_RANGE:
				if tel.has(_mid + ".a_max_aero"):
					_alpha_keys = tel.has(_mid + ".aero_sat") and tel.has(_mid + ".alpha_cmd") and tel.has(_mid + ".delta_cmd")
					_sampled_n += 1
					_ceil_max = maxf(_ceil_max, float(tel[_mid + ".a_max_aero"]))
					_ceil_min = minf(_ceil_min, float(tel[_mid + ".a_max_aero"]))
					_qdyn_max = maxf(_qdyn_max, float(tel.get(_mid + ".q_dyn", 0.0)))
					if float(tel.get(_mid + ".aero_sat", 0.0)) > 0.5:
						_aero_sat_n += 1
					if float(tel.get(_mid + ".defl_sat", 0.0)) > 0.5:
						_defl_sat_n += 1
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

func _pos_max_diff(a: Array, b: Array) -> float:
	var n := mini(a.size(), b.size())
	if n == 0:
		return 1.0e30                       # no overlap ⇒ treat as a failure
	var m := 0.0
	for i in n:
		m = maxf(m, absf(a[i][0] - b[i][0]))
		m = maxf(m, absf(a[i][1] - b[i][1]))
	return m

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
	# Slice 19 reuses slice-17's `airframe_view` marker (the view carries over wholesale) AND ships the
	# `:airframe` fidelity (the ONE toggled button) with the autopilot AUTHORED at :alpha — the
	# cross-fidelity dependency (:alpha commands a_ctrl under :point_mass, δ under :pitch_coupled).
	if not bool(f.get("airframe_view", false)):
		return "a slice-19 handshake must ship airframe_view=true (the airframe view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-19 scenario must default :airframe to pitch_coupled (the showcase opens on the miss), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-19 scenario must AUTHOR the autopilot at :alpha (the inner α/g loop), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-19 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	# one lesson per scenario: no view axes (that would flip the client to cfar/esm/geoloc/gps), and no
	# terrain grid (that would flip it to the slice-18 3-D branch).
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-19 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-19 scenario must NOT ship terrain_grid (that flips the client to the slice-18 3-D view)"
	# the two lesson levers must be exposed — and `speed` must NOT be (it is consumed once at load and
	# read by nothing per-tick: a slider would be DEAD. ρ is the live Q lever — gate-3 finding).
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not (keys.has("rho") and keys.has("af_alpha_max")):
		return "slice-19 handshake must expose the 'rho' (demo) and 'af_alpha_max' (causation) sliders — the two lesson levers"
	if keys.has("speed"):
		return "slice-19 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load (scenario.jl) and read by NOTHING per-tick, so the slider would be DEAD (gate-3 finding); rho is the live Q lever"
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S19V OK: the guidance command inverted through the aero (a_cmd → α_cmd → δ) means the achievable " +
		"maneuver accel IS the FLIGHT-CONDITION lift ceiling a_max_aero = Q·S·C_Lα·α_max/m — so the SAME PN law " +
		"that HITS on the point-mass plant MISSES on the coupled airframe (≈295 m vs ≈4 m frame-sampled, the " +
		"ceiling binding ~59% of the approach). The isolation is STRUCTURAL (max a_max_aero ≪ a_max, defl_sat 0 — " +
		"NOT `saturated == 0`, which fails by design: a_max clamps ~560× INERTLY). The ρ demo lever MOVES the " +
		"ceiling live (2× drop in thinner air — the tripwire a DEAD knob fails); and relaxing α_max ALONE, with " +
		"ρ/speed/geometry held, COLLAPSES the miss — so the ceiling did not merely BIND, it CAUSED. The residual " +
		"is the airframe+autopilot dynamic tracking cost (a §1 named approximation), not a defect. " +
		"Physics-changing, RNG-free, live-settable (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S19V FAIL: " + msg)
	print("S19V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
