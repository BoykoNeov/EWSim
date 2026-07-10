extends SceneTree
# Headless slice-14 gate-3 verifier (THE CAPSTONE — the slice8..13_verify analog). Drives the REAL
# Julia server through SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts
# slice-14's cooperative-salvo "done" criteria as machine checks on the SCALAR telemetry (per-missile
# `los_range` + `t_go`). The lesson: TWO interceptors launched from ASYMMETRIC ranges against a common
# moving target. Under :solo (uncoordinated PN) they arrive SPREAD OUT in time (Δτ ≈ 2.35 s — a
# defender picks them off one at a time); under :salvo (impact-time-control cooperation, sharing t_go
# over the ideal datalink) the near missile STRETCHES to the shared T_d so both arrive TOGETHER
# (Δτ collapses to ≲ 0.53 s, a ~4.5× compression) while EACH still hits — HANDOFF §10 item 13, the
# committed roadmap's capstone. FOUR phases:
#   • SOLO        — the default :solo spreads the two arrivals (Δτ large) with both missiles hitting.
#   • SOLO_REPLAY — reset + replay the SAME :solo config → the per-missile CPA times AND a per-missile
#                   pos-sequence checksum are BIT-IDENTICAL (class-4c RNG-FREE determinism, the
#                   slice-12 shape — NOT slice-13's RNG-affected pos; there is no seeker draw here).
#   • SALVO       — set_fidelity cooperation salvo (ACCEPTED LIVE — the class-4c contrast to slice-13
#                   :scan's introduce-reject): Δτ COLLAPSES (both converge) with both still hitting.
#   • Δτ ratio    — Δτ(:solo) ≫ Δτ(:salvo) (the pinned one-sided bounds → a ≥2× compression).
#
# THE ARRIVAL METRIC is each missile's FIRST-CPA time: the wire ships per-missile `los_range` every
# emit_every (16) ticks; the verifier tracks the running-min per missile and the `t` at that min,
# breaking the band only once the range has climbed well past the min (the descending-band first-CPA —
# excludes the post-CPA coast re-growth; [[ewsim-missile-verifier-sampling]]). Δτ = |CPA_A − CPA_B|.
# MISS is the frame-sampled min los_range per missile (COARSER than the true CPA — the CPA falls
# BETWEEN 16-tick frames, so the true <1 m intercept reads up to ~9 m here; the bounds are set against
# the emit-grid re-probe, NOT the per-tick FINDINGS). guidance=:pn, autopilot=:ideal, no seeker → the
# lesson isolates the COOPERATION, RNG-free (the slice-12 discipline). MISS/CPA is ALWAYS vs the true
# :target (each missile's _nearest_target; the :datalink node is skipped by kind — the truth-path
# invariant, asserted implicitly by both missiles closing on the common target).
#
# Run (server must be listening on slice14_salvo.yaml first):
#   godot --headless --path clients/godot --script res://net/slice14_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 240.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 8000 = 500·16 covers both missiles' CPAs (:solo mB ~7392 ticks, :salvo mA ~6864) plus the post-CPA
# climb the descending-band first-CPA needs (the emit-grid re-probe reported past=true for all).
const STEPS := 8000
const CPA_MARGIN := 50.0          # break the descending band once los climbs this far past the min (m)
const DTAU_SOLO_MIN := 2.0        # :solo arrival spread (emit-grid re-probe: Δτ = 2.352 s)
const DTAU_SALVO_MAX := 1.0       # :salvo COLLAPSED spread (re-probe: Δτ = 0.528 s)
const MISS_MAX := 15.0            # both hit — frame-sampled floor (re-probe max miss 8.67 m; true <1 m)

enum P { HANDSHAKE, SOLO, SOLO_REPLAY, SALVO }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mids: Array = []              # the interceptor ids discovered in the state stream (sorted)
var _last_state: Dictionary = {}
var _t0 := 0.0
var _t_target := 0.0

# per-missile scan accumulators (reset per burst): id -> {min, t_cpa, past, sig}
var _scan := {}
# recorded across phases
var _solo_cpa := {}                # id -> CPA time from the first :solo run (the replay anchor)
var _solo_sig := {}                # id -> pos-sequence checksum from the first :solo run
var _solo_dtau := 0.0

func _initialize() -> void:
	print("S14V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.SOLO)

		# --- :solo (default): the two arrivals spread out in time -------------------------
		P.SOLO:
			if not _drain_scan():
				return false
			if _mids.size() < 2:
				return _fail("expected ≥ 2 :missile interceptors in the state stream, got %d" % _mids.size())
			var dtau := _dtau()
			var mm := _max_miss()
			print("S14V_SOLO %s  Δτ=%.4f s  max_miss=%.2f m  (:solo — should SPREAD, both hit)" % [_cpa_str(), dtau, mm])
			if not (dtau > DTAU_SOLO_MIN):
				return _fail(":solo must SPREAD the arrivals (Δτ > %s s), got %.4f" % [str(DTAU_SOLO_MIN), dtau])
			if not (mm < MISS_MAX):
				return _fail(":solo — both interceptors must still HIT the true target (max miss < %s m), got %.2f" % [str(MISS_MAX), mm])
			# record the :solo CPA times + pos checksums for the replay bit-identity check
			for mid in _mids:
				_solo_cpa[mid] = _scan[mid].t_cpa
				_solo_sig[mid] = _scan[mid].sig
			_solo_dtau = dtau
			_reset_then_scan([], STEPS, P.SOLO_REPLAY)

		# --- reset + replay the SAME :solo config → bit-identical (RNG-free determinism) ----
		P.SOLO_REPLAY:
			if not _drain_scan():
				return false
			print("S14V_REPLAY %s  (must EQUAL the first :solo run — class-4c RNG-free determinism)" % _cpa_str())
			for mid in _mids:
				if _scan[mid].t_cpa != _solo_cpa[mid]:
					return _fail("held-config replay CPA time for %s must be BIT-IDENTICAL (%.6f != %.6f) — RNG-free determinism" % [mid, _scan[mid].t_cpa, _solo_cpa[mid]])
				if _scan[mid].sig != _solo_sig[mid]:
					return _fail("held-config replay pos-sequence for %s must be BIT-IDENTICAL (%.9f != %.9f) — RNG-free determinism" % [mid, _scan[mid].sig, _solo_sig[mid]])
			# SALVO: reset (→ solo default) then set_fidelity cooperation salvo (LIVE — no reject), replay.
			_reset_then_scan([_set_fidelity_cmd("cooperation", "salvo")], STEPS, P.SALVO)

		# --- :salvo: the arrival spread COLLAPSES (both converge) --------------------------
		P.SALVO:
			if not _drain_scan():
				return false
			var dtau2 := _dtau()
			var mm2 := _max_miss()
			print("S14V_SALVO %s  Δτ=%.4f s  max_miss=%.2f m  (:salvo — should COLLAPSE, both hit)" % [_cpa_str(), dtau2, mm2])
			if not (dtau2 < DTAU_SALVO_MAX):
				return _fail(":salvo must COLLAPSE the arrival spread (Δτ < %s s), got %.4f — set_fidelity cooperation salvo must be accepted LIVE (class 4c, no introduce-reject)" % [str(DTAU_SALVO_MAX), dtau2])
			if not (mm2 < MISS_MAX):
				return _fail(":salvo — both interceptors must STILL HIT (max miss < %s m), got %.2f — cooperation reshapes TIMING, not accuracy" % [str(MISS_MAX), mm2])
			if not (dtau2 < _solo_dtau):
				return _fail(":salvo Δτ (%.4f) must be < :solo Δτ (%.4f) — the cooperation collapses the spread" % [dtau2, _solo_dtau])
			print("S14V_RATIO Δτ(:solo)/Δτ(:salvo) = %.2f×" % (_solo_dtau / maxf(dtau2, 1e-9)))
			return _pass()
	return false

# --- stepping / scanning (the slice-9/10/12 contract, adapted for N missiles) --------------

func _begin_scan(n: int, next: P) -> void:
	_reset_scan_accum()
	_inbox.clear()
	_last_state = {}
	_t_target = n * _dt
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
	_scan = {}
	for mid in _mids:
		_scan[mid] = {"min": 1.0e30, "t_cpa": 0.0, "past": false, "sig": 0.0}

# Scan: for EACH missile accumulate the running-min los_range + the `t` at that min (the first-CPA),
# plus a pos-sequence checksum (the RNG-free determinism anchor). The descending-band `past` latch
# stops updating a missile's CPA once its range has climbed CPA_MARGIN past the min (excludes the
# post-CPA coast re-growth). The checksum sums each missile's world pos every frame (RNG-independent).
func _drain_scan() -> bool:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		if _mids.is_empty():
			_discover_missiles(f)
		var t := float(f.get("t", 0.0))
		var tel: Dictionary = f.get("telemetry", {})
		# pos-sequence checksum (from the entity world pos — RNG-independent, the class-4c anchor)
		for e in f.get("entities", []):
			var eid := str(e.get("id", ""))
			if _scan.has(eid):
				var p: Array = e.get("pos", [0, 0, 0])
				_scan[eid].sig += float(p[0]) + 1000.0 * float(p[2])
		# per-missile first-CPA from los_range
		for mid in _mids:
			var key: String = mid + ".los_range"
			if not tel.has(key):
				continue
			var r := float(tel[key])
			var s: Dictionary = _scan[mid]
			if not s.past:
				if r < s.min:
					s.min = r
					s.t_cpa = t
				elif r > s.min + CPA_MARGIN:
					s.past = true
		_last_state = f
	if _last_state.is_empty():
		return false
	return float(_last_state.get("t", -1.0)) >= _t_target - 0.5 * _dt

func _discover_missiles(state: Dictionary) -> void:
	var ids := PackedStringArray()
	for e in state.get("entities", []):
		if str(e.get("kind", "")) == "missile":
			ids.append(str(e.get("id", "")))
	ids.sort()
	_mids = Array(ids)
	for mid in _mids:
		if not _scan.has(mid):
			_scan[mid] = {"min": 1.0e30, "t_cpa": 0.0, "past": false, "sig": 0.0}

# --- metrics ------------------------------------------------------------------------------

func _dtau() -> float:
	# arrival spread = max CPA time − min CPA time over the interceptors (N=2 → |CPA_A − CPA_B|)
	var lo := 1.0e30
	var hi := -1.0e30
	for mid in _mids:
		var t: float = _scan[mid].t_cpa
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return hi - lo

func _max_miss() -> float:
	var mm := 0.0
	for mid in _mids:
		mm = maxf(mm, _scan[mid].min)
	return mm

func _cpa_str() -> String:
	var parts := PackedStringArray()
	for mid in _mids:
		parts.append("%s:CPA=%.3fs/miss=%.2fm" % [mid, _scan[mid].t_cpa, _scan[mid].min])
	return " ".join(parts)

# --- helpers ------------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if fid.is_empty():
		return "handshake carries no fidelity map (cooperation discriminator / the salvo badge blind)"
	if not fid.has("cooperation"):
		return "a slice-14 scenario handshake must carry `cooperation` (the salvo-view discriminator / the cycled lesson)"
	if str(fid.get("cooperation", "")) != "solo":
		return "slice-14 default cooperation should be 'solo' (so the button reveals the fix), got '%s'" % str(fid.get("cooperation", ""))
	# guidance/autopilot are HELD (guidance=:pn truth-fed PN; autopilot=:ideal) so Δτ isolates cooperation
	if str(fid.get("guidance", "")) != "pn":
		return "slice-14 must hold guidance at 'pn' (truth-fed PN base), got '%s'" % str(fid.get("guidance", ""))
	if str(fid.get("autopilot", "")) != "ideal":
		return "slice-14 must hold autopilot at 'ideal' (isolates the cooperation lesson), got '%s'" % str(fid.get("autopilot", ""))
	# one lesson per scenario: no OTHER-slice fidelity keys, no cfar/esm/geoloc/gps view axes, no seeker.
	for other in ["propagation", "cfar", "ep", "estimator", "deinterleaver", "raim", "integrator", "seeker", "discrimination"]:
		if fid.has(other):
			return "a slice-14 scenario should carry ONLY cooperation+guidance+autopilot (found '%s')" % other
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-14 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	# the K_it slider must be exposed (the impact-time-control gain — the salvo tuning lever)
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("k_it"):
		return "slice-14 handshake must expose the 'k_it' slider (the impact-time-control gain — the salvo lever)"
	return ""

func _set_fidelity_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	print("S14V OK: two interceptors launched from asymmetric ranges arrive SPREAD OUT under :solo " +
		"(Δτ ≈ 2.35 s) and TOGETHER under :salvo (Δτ collapses ~4.5× while both still hit) — the near " +
		"missile shares t_go over the ideal datalink and stretches to the team T_d — all on the wire, " +
		"physics-changing, RNG-free, cooperation live-settable (HANDOFF §10.13 — THE CAPSTONE)")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S14V FAIL: " + msg)
	print("S14V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()
		_client = null
