extends SceneTree
# Headless slice-3 step-4 verifier (the analog of net/slice2_verify.gd). It drives the REAL
# Julia server (tools/server.jl scenarios/slice3_cfar.yaml) through SimClient.gd — the same
# protocol code Sandbox.tscn renders off — and asserts slice-3's "done" criterion as machine
# checks, because the range-power picture you judge by eye but the wire + the live `cfar`
# toggle can be *silently* wrong:
#
#   1. the handshake ships the STATIC range axis (range_axis_m of length n_cells, dr_m,
#      n_cells) and `fidelity.cfar == ca` (the scenario default) — the client labels its
#      x-axis from core output, no physics recomputed downstream;
#   2. every state frame carries the per-cell arrays profile_db / threshold_db / detections
#      (length n_cells, finite) — the threshold curve is CORE output;
#   3. THE deliverable — the cfar rung selects the THRESHOLDING RULE, not the draw. The draw
#      is rung-invariant, so resetting (held seed 3) before each rung replays an IDENTICAL
#      noise sequence; the only thing that changes is the rule. Measured over 80 looks per
#      rung from that identical sequence:
#        • CLUTTER EDGE — under `fixed` (flat −ln(pfa)) the 10–16 km clutter band lights up
#          with false alarms; `ca`/`go` track the elevated floor and hold Pfa → far fewer.
#        • MASKING — the strong interferer (tgtB) leaks into the victim's (tgtA) CA training
#          window → tgtA is masked under `ca`; `so` (smallest-of) / `os` (ordered-statistic)
#          reject the interferer side → tgtA resolves. tgtB is never masked.
#      All five rungs reach the SAME final t (bit-identical replay), proving the rung only
#      swapped the rule.
#
# Numbers below are from tools/slice3_probe.jl on this scenario (seed 3): tgtA cell 168
# (25.0 km, SNR 18.2 dB), tgtB cell 173 (25.75 km, 31.6 dB), clutter cells ~68–108. Over
# 200 shared-noise looks: fixed in-clutter 7464, ca 60, go 20; tgtA detections ca 13/200,
# so 162/200, os 161/200; tgtB ≥190 everywhere. The thresholds here are deliberately loose
# (a clean lesson has a >10× margin), the way slice2_verify documents its "~7 dB".
#
# reset MUST precede set_fidelity each rung: reset reloads the YAML (cfar→ca, seed re-applied,
# t=0) and would clobber the toggle; set_fidelity then overrides for this rung's replay.
#
# Run (server must be listening on slice3_cfar.yaml first; it serves one client, then exits):
#   godot --headless --path clients/godot --script res://net/slice3_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 120.0
const SimClientScript := preload("res://net/SimClient.gd")

const RUNGS := ["fixed", "ca", "go", "so", "os"]
const N_STEPS := 4000             # 80 looks (revisit 50 ticks); multiple of emit_every (16)
const CLUT_NEAR := 10000.0        # clutter band [near, far] (m) — matches slice3_cfar.yaml
const CLUT_FAR := 16000.0
# loose thresholds (a clean lesson clears them by >10×; see header for the measured values)
const CLUT_FLOOR := 200           # fixed must light the band: ≥ this many clutter FA events
const CLUT_RATIO := 10            # fixed clutter FA must exceed ca/go by ≥ this factor
const TGT_FLOOR := 15             # so/os must resolve tgtA: ≥ this many tgtA detections
const TGTB_FLOOR := 30            # interferer never masked: ≥ this many tgtB detections under ca

enum P { HANDSHAKE, RUNG_DRAIN, DONE }

var _client                       # SimClient (preloaded — never depend on class_name registration)
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _t_target := 4.0
var _radar := ""
var _n_cells := 0

var _ri := 0                      # index of the rung currently being measured

# per-rung accumulators (reset on rung entry)
var _acc_tgtA := 0
var _acc_tgtB := 0
var _acc_clut := 0
var _last_det: Array = []
var _last_prof: Array = []
var _last_thr: Array = []
var _last_t := -1.0

# results, keyed by rung
var _r_tgtA := {}
var _r_tgtB := {}
var _r_clut := {}
var _r_t := {}
var _r_ok := {}                   # arrays well-formed for this rung?

var _t0 := 0.0

func _initialize() -> void:
	print("S3V_INIT godot=", Engine.get_version_info().string)
	_t0 = _now()
	_client = SimClientScript.new()
	_client.frame_received.connect(func(obj: Dictionary) -> void: _inbox.append(obj))
	_client.start(HOST, PORT)

func _process(_dt_frame: float) -> bool:
	if _now() - _t0 > MAX_SECONDS:
		return _fail("TIMEOUT in phase %s (rung %s)" % [P.keys()[_phase], _cur_rung()], 2)
	_client.poll()                # node not in the tree → drive its IO ourselves

	match _phase:
		P.HANDSHAKE:
			var f := _take("scenario")
			if f.is_empty():
				return false
			var verr := _check_handshake(f)
			if verr != "":
				return _fail(verr)
			_dt = float(f.get("dt_physics", 1.0e-3))
			_t_target = N_STEPS * _dt
			_start_rung(0)
			_phase = P.RUNG_DRAIN

		P.RUNG_DRAIN:
			_drain_accumulate()
			# the last emit of a `step n` burst lands at exactly n·dt; tolerate <½ tick of slack
			if _last_t < _t_target - 0.5 * _dt:
				return false
			_finalize_rung()
			if _ri + 1 < RUNGS.size():
				_ri += 1
				_start_rung(_ri)
			else:
				return _finish()
	return false

# --- per-rung replay ----------------------------------------------------------------------

func _start_rung(i: int) -> void:
	# Clear stale frames from the prior rung, zero the accumulators, then reset (→ YAML ca,
	# seed 3, t=0) BEFORE set_fidelity (order matters — reset would clobber the toggle), then
	# step the fixed budget. Because the draw is rung-invariant and the seed is re-applied,
	# every rung replays the IDENTICAL noise sequence — a clean controlled experiment.
	_inbox.clear()
	_acc_tgtA = 0; _acc_tgtB = 0; _acc_clut = 0
	_last_det = []; _last_prof = []; _last_thr = []; _last_t = -1.0
	_client.send({"type": "reset"})
	_client.send({"type": "set_fidelity", "key": "cfar", "value": RUNGS[i]})
	_client.send({"type": "step", "n": N_STEPS})

func _drain_accumulate() -> void:
	# Accumulate detection EVENTS across ALL frames of the burst (one-shot per look; NOT the
	# per-frame detections array, which is republished between looks and would multi-count).
	# A target hit carries `of`; a false alarm carries only `cell`/`range`.
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) != "state":
			continue
		_last_t = float(f.get("t", -1.0))
		var tel: Dictionary = f.get("telemetry", {})
		_last_prof = tel.get(_radar + ".profile_db", [])
		_last_thr = tel.get(_radar + ".threshold_db", [])
		_last_det = tel.get(_radar + ".detections", [])
		for ev in f.get("events", []):
			if str(ev.get("kind", "")) != "detection":
				continue
			var of := str(ev.get("of", ""))
			if of == "tgtA":
				_acc_tgtA += 1
			elif of == "tgtB":
				_acc_tgtB += 1
			elif of == "":                       # a clutter/noise false alarm (no target)
				var rng := float(ev.get("range", -1.0))
				if rng >= CLUT_NEAR and rng <= CLUT_FAR:
					_acc_clut += 1

func _finalize_rung() -> void:
	var rung: String = RUNGS[_ri]
	_r_tgtA[rung] = _acc_tgtA
	_r_tgtB[rung] = _acc_tgtB
	_r_clut[rung] = _acc_clut
	_r_t[rung] = _last_t
	_r_ok[rung] = _arrays_well_formed()
	print("S3V_RUNG %-6s t=%.4f  tgtA=%-3d tgtB=%-3d clutterFA=%-5d arrays_ok=%s" %
		[rung, _last_t, _acc_tgtA, _acc_tgtB, _acc_clut, _r_ok[rung]])

# arrays present, right length, finite (the wire never ships -Inf/NaN — the slice-2/3 floor).
func _arrays_well_formed() -> bool:
	if _last_det.size() != _n_cells or _last_prof.size() != _n_cells or _last_thr.size() != _n_cells:
		return false
	for v in _last_prof:
		if not is_finite(float(v)):
			return false
	for v in _last_thr:
		if not is_finite(float(v)):
			return false
	return true

# --- assertions ---------------------------------------------------------------------------

func _finish() -> bool:
	# 1. arrays well-formed under every rung
	for rung in RUNGS:
		if not bool(_r_ok[rung]):
			return _fail("rung %s: profile/threshold/detections arrays malformed (len/finite)" % rung)

	# 2. bit-identical replay: all rungs reached the same final t (== N_STEPS·dt)
	var t0: float = _r_t[RUNGS[0]]
	for rung in RUNGS:
		if abs(float(_r_t[rung]) - t0) > 1.0e-9:
			return _fail("final t differs across rungs (%s=%.9f vs %s=%.9f) — replay not aligned" %
				[RUNGS[0], t0, rung, float(_r_t[rung])])
	if abs(t0 - _t_target) > 1.0e-6:
		return _fail("final t %.6f != target %.6f" % [t0, _t_target])

	# 3a. CLUTTER — `fixed` lights the band; `ca`/`go` track it (≥10× fewer false alarms)
	var cf: int = _r_clut["fixed"]
	var cca: int = _r_clut["ca"]
	var cgo: int = _r_clut["go"]
	if cf < CLUT_FLOOR:
		return _fail("fixed did NOT light the clutter band: %d FA events (< %d)" % [cf, CLUT_FLOOR])
	if cf < CLUT_RATIO * max(1, cca):
		return _fail("ca did not tame the clutter band: fixed=%d ca=%d (want ≥%d×)" % [cf, cca, CLUT_RATIO])
	if cf < CLUT_RATIO * max(1, cgo):
		return _fail("go did not tame the clutter band: fixed=%d go=%d (want ≥%d×)" % [cf, cgo, CLUT_RATIO])

	# 3b. MASKING — `ca` masks tgtA; `so`/`os` resolve it. tgtB (interferer) never masked.
	var aca: int = _r_tgtA["ca"]
	var aso: int = _r_tgtA["so"]
	var aos: int = _r_tgtA["os"]
	if aso < TGT_FLOOR or aos < TGT_FLOOR:
		return _fail("so/os did not resolve tgtA: so=%d os=%d (< %d)" % [aso, aos, TGT_FLOOR])
	if not (aca < aso and aca < aos):
		return _fail("tgtA not masked under ca: ca=%d so=%d os=%d (expected ca lowest)" % [aca, aso, aos])
	if aca * 2 > aso:
		return _fail("masking margin too thin: ca=%d, so=%d (want ca ≤ ½·so)" % [aca, aso])
	if int(_r_tgtB["ca"]) < TGTB_FLOOR:
		return _fail("interferer tgtB should never be masked: ca=%d (< %d)" % [int(_r_tgtB["ca"]), TGTB_FLOOR])

	print("S3V OK: handshake axis + arrays finite; rung swaps the rule only (same final t); " +
		"fixed lights clutter (%d) vs ca/go (%d/%d); tgtA masked under ca (%d) resolves under so/os (%d/%d)" %
		[cf, cca, cgo, aca, aso, aos])
	_teardown()
	quit(0)
	return true

# --- frame helpers ------------------------------------------------------------------------

func _take(type: String) -> Dictionary:
	while not _inbox.is_empty():
		var f: Dictionary = _inbox.pop_front()
		if str(f.get("type", "")) == type:
			return f
	return {}

func _check_handshake(f: Dictionary) -> String:
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("cfar", "")) != "ca":
		return "scenario default cfar should be 'ca', got '%s'" % str(fid.get("cfar", ""))
	if not f.has("range_axis_m"):
		return "handshake carries no range_axis_m (the client would have no x-axis to label)"
	var axis: Array = f.get("range_axis_m", [])
	_n_cells = int(f.get("n_cells", 0))
	if _n_cells <= 0 or axis.size() != _n_cells:
		return "range axis malformed: n_cells=%d, axis.size=%d" % [_n_cells, axis.size()]
	if float(f.get("dr_m", 0.0)) <= 0.0:
		return "dr_m must be positive, got %s" % str(f.get("dr_m", 0.0))
	_radar = str(f.get("radar", ""))
	if _radar == "":
		return "handshake carries no radar id for the CFAR axis"
	return ""

func _cur_rung() -> String:
	return RUNGS[_ri] if _ri < RUNGS.size() else "?"

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _fail(msg: String, code := 1) -> bool:
	push_error("S3V FAIL: " + msg)
	print("S3V FAIL: " + msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	if _client != null:
		_client.close()
		_client.free()        # never parented to the tree → free it ourselves
		_client = null
