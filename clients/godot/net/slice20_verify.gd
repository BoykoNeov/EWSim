extends SceneTree
# Headless slice-20 gate-3 verifier (the slice8..19_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-20's induced-drag
# "done" criteria as machine checks on the SCALAR telemetry (los_range / a_max_aero / aero_sat /
# defl_sat / a_induced / speed / pos_*).
#
# THE LESSON: **the missile lowers its own ceiling by maneuvering.** Slices 17/19 shipped an explicit §1
# approximation — "lift is drag-free / speed-preserving (⟂ v)". Slice 20 cashes it: lift ⟂ v turns the
# path, induced drag ∥ −v̂ sends the invoice, and the invoice is paid in the very currency that buys the
# turn (V sets Q sets `a_max_aero = Q·S·C_Lα·α_max/m`). The project's first DEGENERATIVE SPIRAL.
# Slice 19 moved this ceiling with the ρ knob — a flight condition the ENGINEER dialled. Here the
# MISSILE moves it, by turning.
#
# ⚠ "DEGENERATIVE", NOT "POSITIVE FEEDBACK" (gate-3 FINDING 12): the SPEED bleed is SELF-LIMITING
# (bill ∝ V²α² ⇒ dV/dt peaks at −88.8 then DECAYS to −35.8; V asymptotes at ≈213, the ceiling at ≈25 —
# neither reaches 0). The positive sign is on the TRACKING ERROR, and only once the demand crosses the
# falling ceiling. airframe.jl carries the full statement.
#
# THE HEADLINE ASSERTION IS `_collapse()` — THE CEILING'S OWN FALL WITHIN ONE RUN — not `aero_sat`.
# The collapse ratio is PURE CEILING and monotone-safe by construction (more bill → more bleed → lower
# ceiling; it cannot reverse), which is what evidences "the missile lowers its own CEILING". aero_sat
# moves on the ceiling AND the demand, so it is asserted as the CONSEQUENCE (advisor). Both ship.
# FIVE phases:
#   • PAID        — the default K = 0.15: the ceiling FALLS ACROSS THE APPROACH (269 → 130, a 0.48×
#                   collapse WITHIN one run) and the miss opens to ≈103 m. The baseline trace.
#   • PAID_REPLAY — reset + replay the SAME config → the pos trace is BIT-IDENTICAL (class-4c RNG-FREE
#                   determinism — truth-fed PN, no seeker, no w.rng draw).
#   • FREE        — set_param af_k_induced → 0.0 (lift is drag-free again — slices 17/19's approximation,
#                   authored): the missile HITS, and ⭐ THE HEADLINE: `aero_sat == 0` — the aero ceiling
#                   NEVER BINDS ONCE. It is not a factor in this engagement at all. The ceiling is FLAT
#                   across the run (0.92×, and that residual is GRAVITY, not the turn).
#   • KMAX        — set_param af_k_induced → 0.3 (the knob's max): the ceiling COLLAPSES 8.4× WITHIN the
#                   run, aero_sat climbs 0% → 55%, and the miss opens to ≈714 m. Nothing that SETS the
#                   ceiling moved — ρ, S, C_Lα, α_max, mass are all held. Only K changed.
#
# ⚠ THE CLAIM IS BOUNDED — this verifier does NOT prove "induced drag" (gate-0 FINDING 5). Matched on
# ΔV, a parasitic `cd_area` reproduces this miss AND this ceiling almost exactly (45.02 m / 173.2 vs
# 44.17 m / 176.3): "bleed → Q → ceiling → miss" is what ANY speed loss does. What is distinctive is the
# SOURCE of the bill (∝ α² — a straight fly-out is billed 0.06 m/s vs parasitic's 75–136), and THAT is
# pinned in the CORE suite (test_missile.jl "THE DISCRIMINATOR"), where the straight-vs-turning
# comparison can be run controlled. This file asserts the SPIRAL; that file asserts it is INDUCED.
#
# AND NOT THIS (gate-0 FINDING 7, REFUTED by its own probe): "a harder engagement costs more" is FALSE
# (the attributable bill FALLS 194 → 117 m/s as the target's maneuver hardens — time-of-flight shortens
# and the α clamp caps α anyway). The target here does NOT maneuver: the missile pays for ITS OWN TURN
# onto the collision course. Never write "dogfighting costs speed".
#
# ⭐ ENDGAME_RANGE = 1000, **NOT slice-19's 300** — and this is load-bearing, not a tweak (gate-3
# finding). Slice 19's `r > 300` gate excludes ITS terminal λ̇ spike only because slice 19 misses by
# 295 m — i.e. its CPA falls BELOW the gate, by luck of the geometry. Slice 20's KMAX arm misses by
# 714 m, so its CPA sits ABOVE a 300 m gate: at CPA the LOS rotates fastest ⇒ a_cmd spikes ⇒ α_cmd pegs
# ⇒ δ punches δ_max, and a 300 m gate COUNTS it (measured: defl_sat = 1 frame at t = 8.016, r = 714.1,
# δ = −0.4). The gate must sit above the LARGEST CPA in the sweep so the terminal artifact is excluded
# from EVERY arm consistently. 1000 m clears the 714 m worst case by 286 m and costs only ~10% of the
# window (450 frames still sampled). Copying slice 19's constant would have shipped a FALSE isolation.
#
# THE ISOLATION: `defl_sat == 0` in EVERY arm (the FOURTH cap, δ_max, provably not standing in for the
# lesson) — RE-ESTABLISHED under this slice's own gate, never copied. `cd_area_m2 = 0` in the scenario,
# so every m/s lost is provably bought with α.
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). All bounds below are pinned
# against the FRAME-SAMPLED live wire (wire.jl / gate_pick.jl), never the per-tick truth: the FREE arm's
# true 1.27 m CPA frame-samples to 8.59 m, so a sub-metre bound would FAIL on a hit. The MISS side
# samples faithfully (true 714.10 → frame 714.12).
#
# Everything is RNG-FREE (truth-fed PN, no seeker) so "draw-count invariance" is VACUOUS (class 4c) — do
# NOT copy slice-11/13 draw language. CPA is measured from the core's own `los_range` on the FIRST
# DESCENDING BAND only (the target outruns the missile at |v| ≈ 825 > 700, so the first CPA is the
# honest one — but the latch is explicit, not a hope).
#
# Run (server must be listening on slice20_induced_drag.yaml first):
#   godot --headless --path clients/godot --script res://net/slice20_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 9600 = 600·16 = 9.6 s — the LATEST CPA is 8.03 s (KMAX, the bled-out arm flies longer), so the
# first-descending band is closed and latched well before the drain ends on every arm.
const STEPS := 9600

const K_DEFAULT := 0.15           # the scenario's authored k_induced (the mid-range opening position)
const K_FREE := 0.0               # lift is DRAG-FREE — slices 17/19's approximation, authored
const K_MAX := 0.3                # the knob's max (gate-0 FINDING 11: monotone to 0.6, contaminates at 0.8)
const ENDGAME_RANGE := 1000.0     # ← NOT slice-19's 300. See the header — load-bearing.

# Bounds — ALL pinned against the FRAME-SAMPLED live wire at ENDGAME_RANGE = 1000, conservative:
const FREE_HIT_MAX := 30.0        # FREE frame CPA (measured 8.59; true 1.27 — sub-metre unreachable)
const FREE_FLAT_MIN := 0.85       # FREE ceiling collapse ratio (measured 0.916 — FLAT; that 8% is gravity)
const PAID_MISS_MIN := 50.0       # default-K frame CPA (measured 103.14)
const KMAX_MISS_MIN := 400.0      # KMAX frame CPA (measured 714.12)
const KMAX_COLLAPSE_MAX := 0.25   # ⭐ KMAX ceiling collapse WITHIN the run (measured 0.119 — 8.4×)
const KMAX_SAT_MIN := 0.35        # ⭐ KMAX aero_sat share (measured 0.551) — vs FREE's EXACT 0
const KMAX_AIND_MIN := 40.0       # KMAX peak a_induced (measured 86.0) — the bill is REAL
const RATIO_MIN := 20.0           # KMAX/FREE frame ratio (measured 83.1× — 4× margin)

enum P { HANDSHAKE, PAID, PAID_REPLAY, FREE, KMAX }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
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
var _sampled_n := 0
var _ceil_first := -1.0           # the ceiling at the START of the approach (the collapse numerator)
var _ceil_min := 1.0e30           # …and its MINIMUM on the approach — the SPIRAL, within ONE run
var _aind_max := 0.0              # peak a_induced — the bill
var _v_last := 0.0
var _drag_key := false            # the key-gated slice-20 telemetry ships
var _pos_trace: Array = []
# recorded across phases
var _paid_pos: Array = []
var _paid_miss := 0.0
var _free_miss := 0.0

func _initialize() -> void:
	print("S20V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.PAID)

		# --- the default K = 0.15 — the spiral is already running --------------------------------
		P.PAID:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_paid_pos = _pos_trace.duplicate(true)
			_paid_miss = _min_los
			print("S20V_PAID K=%.2f  miss(frame)=%.3f  ceiling %.1f→%.1f (%.3fx)  aero_sat=%d/%d (%.1f%%)  a_ind_max=%.1f  V_end=%.1f  defl_sat=%d  keys=%s" %
				[K_DEFAULT, _min_los, _ceil_first, _ceil_min, _collapse(), _aero_sat_n, _sampled_n,
				 100.0 * _sat_frac(), _aind_max, _v_last, _defl_sat_n, str(_drag_key)])
			if not _drag_key:
				return _fail("an authored k_induced must ship the `a_induced` telemetry (the bill readout)")
			if not (_min_los > PAID_MISS_MIN):
				return _fail("the default K must already open the miss (frame CPA > %.0f m), got %.2f" % [PAID_MISS_MIN, _min_los])
			if _defl_sat_n != 0:
				return _fail("the FOURTH cap (δ_max) must NOT bind — defl_sat must stay 0, got %d frames (it would contaminate the lesson)" % _defl_sat_n)
			_reset_then_scan([], STEPS, P.PAID_REPLAY)

		P.PAID_REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_paid_pos, _pos_trace)
			print("S20V_REPLAY posdiff_vs_paid=%s m  miss=%.3f (must be 0.0 / identical — class-4c RNG-free)" % [rdiff, _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % rdiff)
			if not (_min_los == _paid_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _paid_miss])
			_reset_then_scan([_set_param_cmd("m1", "af_k_induced", K_FREE)], STEPS, P.FREE)

		# --- K → 0 — lift is DRAG-FREE again: ⭐ THE CEILING NEVER BINDS ONCE ---------------------
		P.FREE:
			if not _drain_scan():
				return false
			_free_miss = _min_los
			print("S20V_FREE K=%.2f  miss(frame)=%.3f  ceiling %.1f→%.1f (%.3fx — FLAT)  aero_sat=%d/%d (%.1f%%)  a_ind_max=%.1f  V_end=%.1f  defl_sat=%d" %
				[K_FREE, _min_los, _ceil_first, _ceil_min, _collapse(), _aero_sat_n, _sampled_n,
				 100.0 * _sat_frac(), _aind_max, _v_last, _defl_sat_n])
			if not (_min_los < FREE_HIT_MAX):
				return _fail("with lift drag-free the missile must HIT (frame CPA < %.0f m — sub-metre is UNREACHABLE on the wire), got %.2f" % [FREE_HIT_MAX, _min_los])
			# ⭐ THE HEADLINE. At K = 0 the aero ceiling is NOT A FACTOR IN THIS ENGAGEMENT — it never
			# binds on a single sampled frame. Everything slice 20 shows is therefore something the
			# MISSILE did to itself; nothing lowered the ceiling from outside (contrast slice 19,
			# where the ENGINEER lowers it with the ρ knob). An EXACT 0 — not a fraction.
			if _aero_sat_n != 0:
				return _fail("⭐ THE HEADLINE REQUIRES aero_sat == 0 with lift drag-free — the ceiling must never bind ONCE, got %d/%d frames. If it binds here, the miss is not the missile's own doing." % [_aero_sat_n, _sampled_n])
			# …and the ceiling is FLAT across the approach: the ~8% residual is GRAVITY on a climbing
			# missile (drag is OFF), not the turn. This is the reference the KMAX collapse is read against.
			if not (_collapse() > FREE_FLAT_MIN):
				return _fail("with no bill the ceiling must stay ~FLAT across the approach (> %.2fx), got %.3fx" % [FREE_FLAT_MIN, _collapse()])
			if not (_aind_max == 0.0):
				return _fail("K = 0 must bill EXACTLY nothing (a_induced == 0), got %.6f" % _aind_max)
			if _defl_sat_n != 0:
				return _fail("the FREE arm must keep the 4th cap clear (defl_sat == 0), got %d" % _defl_sat_n)
			_reset_then_scan([_set_param_cmd("m1", "af_k_induced", K_MAX)], STEPS, P.KMAX)

		# --- K → 0.3 — ⭐ THE SPIRAL: the missile eats its own ceiling ----------------------------
		P.KMAX:
			if not _drain_scan():
				return false
			var ratio := _min_los / maxf(_free_miss, 1.0e-9)
			print("S20V_KMAX K=%.2f  miss(frame)=%.3f (vs FREE %.3f = %.1fx)  ceiling %.1f→%.1f (%.3fx COLLAPSE)  aero_sat=%d/%d (%.1f%%)  a_ind_max=%.1f  V_end=%.1f  defl_sat=%d" %
				[K_MAX, _min_los, _free_miss, ratio, _ceil_first, _ceil_min, _collapse(),
				 _aero_sat_n, _sampled_n, 100.0 * _sat_frac(), _aind_max, _v_last, _defl_sat_n])
			# THE TRIPWIRE THE DEAD `speed` KNOB SLIPPED THROUGH (slice-19 gate 3): a knob must MOVE
			# THE PHYSICS, not merely fail to crash. K is fetched every tick by the stage closure.
			if not (_aind_max > KMAX_AIND_MIN):
				return _fail("the K knob must MOVE the physics: peak a_induced > %.0f m/s², got %.2f — a knob that changes nothing is a DEAD knob" % [KMAX_AIND_MIN, _aind_max])
			# ⭐ THE SPIRAL, within ONE run and needing no cross-run compare: the ceiling COLLAPSES.
			# Nothing that SETS it moved — ρ, S, C_Lα, α_max and mass are all held across every arm.
			if not (_collapse() < KMAX_COLLAPSE_MAX):
				return _fail("⭐ THE SPIRAL requires the ceiling to COLLAPSE across the approach (< %.2fx, measured 0.119), got %.3fx — the missile must eat its own ceiling by turning" % [KMAX_COLLAPSE_MAX, _collapse()])
			# …and the collapsed ceiling CATCHES the demand: 0% → 55%. The engagement acquires a
			# constraint it did not have, self-inflicted.
			if not (_sat_frac() > KMAX_SAT_MIN):
				return _fail("the collapsed ceiling must CATCH the demand (aero_sat > %.0f%%, measured 55%%), got %.1f%%" % [100.0 * KMAX_SAT_MIN, 100.0 * _sat_frac()])
			if not (_min_los > KMAX_MISS_MIN):
				return _fail("the spiral must reach the OUTCOME (frame CPA > %.0f m), got %.2f" % [KMAX_MISS_MIN, _min_los])
			if not (ratio > RATIO_MIN):
				return _fail("the K knob must be NON-DEAD end to end: KMAX/FREE frame ratio > %.0fx, got %.1fx" % [RATIO_MIN, ratio])
			# THE ISOLATION, under THIS slice's gate — not copied from slice 19 (whose 300 m constant
			# would COUNT this arm's CPA λ̇ spike, since its CPA is at 714 m > 300 m).
			if _defl_sat_n != 0:
				return _fail("the FOURTH cap (δ_max) must stay clear at K_MAX too (defl_sat == 0), got %d — the lesson would be δ_max in an induced-drag costume" % _defl_sat_n)
			if not (_sampled_n > 300):
				return _fail("the sampled window must be real, got %d frames" % _sampled_n)
			return _pass()
	return false

# --- stepping / scanning (the slice-10..19 contract) --------------------------------------

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
	_ceil_first = -1.0
	_ceil_min = 1.0e30
	_aind_max = 0.0
	_v_last = 0.0
	_drag_key = false
	_pos_trace = []

func _sat_frac() -> float:
	return float(_aero_sat_n) / maxf(float(_sampled_n), 1.0)

# The SPIRAL signature, within ONE run: the ceiling's minimum on the approach over its value at the
# START. FLAT (≈0.92, gravity only) with no bill; COLLAPSED (≈0.12) once the turn is billed. This is
# monotone-safe BY CONSTRUCTION (more bill → more bleed → lower ceiling; it cannot reverse) — unlike
# the miss, which IS non-monotone in K in general (gate-0 FINDING 6, occurrence #4 of that pattern).
func _collapse() -> float:
	if _ceil_first <= 0.0 or _ceil_min > 1.0e29:
		return -1.0
	return _ceil_min / _ceil_first

func _now_t() -> float:
	return float(_last_state.get("t", 0.0)) if not _last_state.is_empty() else 0.0

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
					_drag_key = tel.has(_mid + ".a_induced")
					_sampled_n += 1
					var c := float(tel[_mid + ".a_max_aero"])
					if _ceil_first < 0.0:
						_ceil_first = c        # the ceiling at the START of the approach
					_ceil_min = minf(_ceil_min, c)
					_aind_max = maxf(_aind_max, float(tel.get(_mid + ".a_induced", 0.0)))
					_v_last = float(tel.get(_mid + ".speed", 0.0))
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
	# Slice 20 reuses slice-17/19's `airframe_view` marker AND ships the `:airframe` fidelity, so the
	# client takes the slice-19 airframe-cycler branch and the aero strip / α strip / nose-vs-velocity
	# drawing ALL carry over — the view needed NO new client code (the ceiling the strip already plots
	# simply starts falling). The `:airframe` button is slice 19's REFERENCE ARM here, not this
	# slice's lesson: slice 20's lesson is the af_k_induced SLIDER (the slice-16 shape).
	if not bool(f.get("airframe_view", false)):
		return "a slice-20 handshake must ship airframe_view=true (the airframe view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-20 scenario must default :airframe to pitch_coupled (there is no lift to bill for under point_mass), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-20 scenario must AUTHOR the autopilot at :alpha (the inner α/g loop), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-20 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-20 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-20 scenario must NOT ship terrain_grid (that flips the client to the slice-18 3-D view)"
	# THE lesson lever must be exposed — and the CONFOUNDED ones must NOT be. `af_alpha_max` is slice
	# 19's causation knob and is DISQUALIFIED here (advisor): it now ALSO feeds the induced drag
	# through the achieved α, so it is no longer isolated and can never be this slice's counterfactual.
	# `rho` moves the ceiling AND the bill together. K enters ONLY the drag term — it is the one clean
	# lever, which is exactly why it is the only knob.
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("af_k_induced"):
		return "slice-20 handshake must expose the 'af_k_induced' slider — THE lesson lever (K enters only the drag term)"
	if keys.has("speed"):
		return "slice-20 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load and read by NOTHING per-tick, so the slider would be DEAD (slice-19 gate-3 finding)"
	if keys.has("af_alpha_max") or keys.has("rho"):
		return "slice-20 must NOT expose 'af_alpha_max' / 'rho' — both are CONFOUNDED with the new drag term (α_max feeds the bill through the achieved α; ρ moves the ceiling AND the bill), so neither can be this slice's lever (convention 9 — one lesson)"
	# The knob range is MEASURED, not cosmetic (gate-0 FINDINGS 6 + 11): the miss is NON-MONOTONE in K
	# in general (it peaks then REVERSES — a bled-out missile flies ~ballistically into a close pass),
	# and THIS config contaminates at K ≥ 0.8 (defl_sat 0 → 1289, α_pk overshoots α_max = the slice-19
	# ceiling LEAK). Clean and monotone to 0.6; the max sits at 0.3 — a 2× margin.
	for k in f.get("knobs", []):
		if str(k.get("key", "")) == "af_k_induced":
			if float(k.get("min", -1.0)) != 0.0:
				return "af_k_induced must floor at 0 (a negative K is a drag that ACCELERATES), got %s" % str(k.get("min"))
			if float(k.get("max", 99.0)) > 0.6:
				return "af_k_induced must cap at or below the proven-monotone bound (0.6; shipped 0.3), got %s — past it the miss REVERSES and defl_sat explodes (gate-0 FINDINGS 6/11)" % str(k.get("max"))
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S20V OK: INDUCED DRAG — the missile LOWERS ITS OWN CEILING by maneuvering. Lift ⟂ v turns the " +
		"path; induced drag ∥ −v̂ bills it (C_Di = K·C_L²), and the bill is paid in the very currency that " +
		"buys the turn: V sets Q sets a_max_aero. With lift DRAG-FREE (K=0 — slices 17/19's approximation) " +
		"the ceiling NEVER BINDS ONCE (aero_sat 0/366) and stays FLAT (0.92x, that residual being gravity), " +
		"and the missile HITS (8.59 m frame-sampled; true 1.27). Turn the bill on at K=0.3 and the ceiling " +
		"COLLAPSES 8.4x WITHIN one run (269 → 32), catches the demand (aero_sat 0% → 55%), and the missile " +
		"MISSES by 714 m (83x). Nothing that SETS the ceiling moved — ρ, S, C_Lα, α_max and mass are held " +
		"across every arm. The engagement acquired a constraint it did not have, self-inflicted: the " +
		"project's first DEGENERATIVE SPIRAL — NOT a 'positive-feedback loop' (the speed bleed is " +
		"SELF-LIMITING, ∝V²α²: dV/dt peaks at −88.8 then decays to −35.8 and V asymptotes at ≈213; the " +
		"positive sign is on the TRACKING ERROR, and only once the demand crosses the falling ceiling). " +
		"The isolation is re-established under THIS slice's gate " +
		"(defl_sat == 0 at ENDGAME_RANGE = 1000, NOT slice-19's 300 — which would COUNT this arm's CPA λ̇ " +
		"spike at r = 714 > 300 and ship a false claim). NOTE the claim is BOUNDED: bleed → ceiling → miss " +
		"is what ANY speed loss does (a matched parasitic cd_area reproduces it); that this bill is written " +
		"BY THE TURN (∝ α², a straight fly-out billed 0.06 m/s vs parasitic's 75–136) is pinned in the CORE " +
		"suite. Physics-changing, RNG-free, live-settable (class 4c).")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S20V FAIL: " + msg)
	print("S20V FAIL: ", msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	# `close()` + `free()` — the slice8..19_verify contract. (SimClient has no `stop()`; a first draft
	# called one and threw AFTER quit(0), so the run still exited 0 with a broken teardown and 7 leaked
	# ObjectDB instances. An error that lands past the exit code is exactly the kind that survives.)
	if _client != null:
		_client.close()
		_client.free()
		_client = null
