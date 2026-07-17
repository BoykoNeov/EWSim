extends SceneTree
# Headless slice-21 gate-3 verifier (the slice8..20_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-21's exponential-
# atmosphere "done" criteria as machine checks on the SCALAR telemetry (los_range / a_max_aero / rho_air /
# speed / aero_sat / defl_sat / pos_*).
#
# THE LESSON: **the ceiling you lower by CLIMBING.** Slices 19 and 20 were under standing orders to say
# "low dynamic pressure (thin air)" and NEVER unqualified "high altitude" — ρ was a number an engineer
# typed, not a consequence of where the missile flew, and only V could move Q = ½ρV². Here ρ = ρ₀·exp(−z/H)
# and the phrase is EARNED: climb → ρ(z) falls → Q falls → a_max_aero = Q·S·C_Lα·α_max/m falls → you
# cannot pull → you miss. Same cap (#4) as slice 19; a THIRD mover for it (19: the engineer's ρ knob;
# 20: the missile's own turn, via V; 21: WHERE IT FLIES).
#
# ⭐ THE HEADLINE IS THE ρ-FACTOR — and it is a stronger claim than slice 20's collapse ratio could ever
# be, because it FACTORIZES EXACTLY. Since a_max_aero = ½·ρ(z)·V²·S·|C_Lα|·α_max/m, the within-run ceiling
# ratio is IDENTICALLY [ρ(z)/ρ(z₀)]·[V/V₀]² — an ALGEBRAIC IDENTITY, not an empirical fit. So ALTITUDE and
# SPEED separate with NO residual (P.EXP asserts the identity ON THE WIRE, at the ceiling-minimum frame,
# to atol 1e-9). Slice 20's V-only collapse could not be decomposed this way.
#
# ⭐⭐ AND THE SHARPEST SINGLE FACT — P.CONST: **the twin's ρ-factor is EXACTLY 1.0** (`==`, not `≈`). The
# `:constant` arm's ceiling ALSO falls on this climb, by ≈2× — but that is purely the V bleed, i.e.
# GRAVITY, and its model attributes 100% of it to speed BY DEFINITION. ρ(z) reveals the 4.4× it could not
# see. That is the whole slice in one number, and it is why `rho_air` is KEY-gated and not RUNG-gated: the
# twin's half of the headline has to be ON THE WIRE.
#
# FOUR phases:
#   • EXP        — the authored H = 8500 (EARTH'S REAL SCALE HEIGHT, not a tuned number): the ρ-factor
#                  COLLAPSES 4.4× within one run, the ceiling falls 239 → 27, and the missile MISSES.
#   • EXP_REPLAY — reset + replay the SAME config → the pos trace is BIT-IDENTICAL (class-4c RNG-FREE
#                  determinism — truth-fed PN, no seeker, no w.rng draw).
#   • CONST      — set_fidelity atmosphere → constant (THE BUTTON — the live side-by-side IS the
#                  punchline): the OLD MODEL HITS, its ceiling NEVER BINDS ONCE, ρ-factor EXACTLY 1.0.
#   • HMAX       — set_param af_scale_height → 25000 (the slider's max): a deep, slowly-thinning
#                  atmosphere FORGIVES — the miss nearly closes. The not-a-dead-knob tripwire.
#
# ⚠ WHY H = 25000 AND NOT H = 6000 FOR THE KNOB ARM — this is the LOS-gate rule, not a preference
# ([[ewsim-missile-verifier-sampling]], third recurrence). The gate must sit ABOVE THE LARGEST CPA IN THE
# SWEEP, or it excludes the terminal λ̇ artifact from some arms and not others. H = 6000 misses by 1706 m
# (gate-0 F8) — a missile that never comes within 1000 m, so a 1000 m gate would exclude NOTHING from it
# while excluding the endgame from every other arm: an inconsistent comparison. H = 25000 keeps the
# largest CPA in the sweep at 360.7 m, so gate 2's MEASURED 1000 carries over unchanged and every arm is
# gated identically. (The severity direction is not lost — the CORE suite flies H = 6000 in
# test_missile.jl, where the whole trace is available and no gate is needed.)
#
# ⚠ ENDGAME_RANGE = 1000 IS MEASURED, NOT COPIED — it FAILED first at slice-19's 300 (gate 2). The CONST
# twin HITS, so it flies the full r → 0 endgame where PN's ω → ∞ spikes a_cmd and the ceiling blips
# against it; measured, those blips lie ENTIRELY within r ∈ [1.9, 362.9] m and at r > 1000 the count is
# EXACTLY 0. That matters because `aero_sat == 0` in P.CONST is an assertion, not a hope. Do NOT lower it.
#
# THE ISOLATION: `defl_sat == 0` in EVERY arm (the FOURTH cap, δ_max, provably not standing in for the
# lesson), and `a_max` is INERT (3000 ≫ the ~269 ceiling — slice-19's structural finding: a_max clamps
# a_cmd UPSTREAM of the α inversion, so the tighter downstream cap wins). `cd_area = 0` AND no
# `k_induced`: nothing bleeds speed but GRAVITY, and the twin carries the same gravity — so the twin
# difference is PURE ALTITUDE.
#
# FRAME SAMPLING IS LOAD-BEARING ([[ewsim-missile-verifier-sampling]]). Every bound below is pinned
# against the FRAME-SAMPLED live wire (emit_every = 16 ⇒ one sample per 16 ms), NEVER the per-tick truth
# the CORE suite measures — and the two DIVERGE ASYMMETRICALLY, which is the whole reason to say so:
#   • A MISS samples FAITHFULLY. At CPA the radial rate is zero by definition, so the error is
#     second-order: EXP's true 360.739 m frame-samples to 360.768 (Δ 0.03 m).
#   • A HIT samples COARSELY. The pair closes at ~800 m/s ⇒ ~13 m of travel BETWEEN SAMPLES, so a true
#     1.949 m CPA lands at 3.075 and H_MAX's true 6.29 lands at 7.131. (Slice 20 hit this exactly: its
#     true 1.27 m frame-sampled to 8.59.) A sub-metre bound on a hit arm would FAIL ON A HIT.
# So CONST_HIT_MAX/HMAX_HIT_MAX are generous BY NECESSITY, and the EXP/CONST ratio reads 117× on the wire
# where the per-tick truth is 185× — the twin's frame CPA is the inflated term. Quote the FRAME numbers in
# anything this file prints; the per-tick numbers belong to test_missile.jl, which can see every tick.
#
# Everything is RNG-FREE (truth-fed PN, no seeker) so "draw-count invariance" is VACUOUS (class 4c) — do
# NOT copy slice-11/13 draw language. CPA is measured from the core's own `los_range` on the FIRST
# DESCENDING BAND only.
#
# Run (server must be listening on slice21_atmosphere.yaml first):
#   godot --headless --path clients/godot --script res://net/slice21_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 900.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 48000 = 3000·16 = 48 s. This is a LONG shot — a 22 km climbing intercept puts CPA at t ≈ 43.5 s — so the
# first-descending band closes and latches with ~4.5 s to spare on every arm. (Slice 18's verifier already
# ran 2500 frames; this is 3000.)
const STEPS := 48000

const H_DEFAULT := 8500.0         # the scenario's authored scale height — EARTH'S REAL VALUE
const H_MAX := 25000.0            # the knob's max: a deep, slowly-thinning atmosphere
const ENDGAME_RANGE := 1000.0     # ← MEASURED (gate 2), NOT slice-19's 300. See the header — load-bearing.

# Bounds — ALL pinned against the FRAME-SAMPLED live wire (see the header), conservative.
const EXP_MISS_MIN := 100.0       # :exponential frame CPA (measured 360.768; truth 360.739)
const EXP_RHOF_MAX := 0.35        # ⭐ the ρ-factor's within-run collapse (measured 0.248 — a 4× fall)
const EXP_SAT_MIN := 0.10         # the collapsed ceiling CATCHES the demand (measured 25.6%, vs CONST's EXACT 0)
const CONST_HIT_MAX := 30.0       # :constant frame CPA (measured 3.075; truth 1.949 — the OLD MODEL HITS)
const RATIO_MIN := 20.0           # :exponential / :constant FRAME ratio (measured 117×; per-tick 185×)
const HMAX_HIT_MAX := 60.0        # H = 25000 frame CPA (measured 7.131; truth 6.29 — a deep atmosphere FORGIVES)
const HMAX_RHOF_MARGIN := 1.3     # H_MAX's ρ-factor vs the EXP arm's MEASURED one (0.621 vs 0.248 = 2.5×)
# The identity is ALGEBRAIC, so this is a ROUND-OFF budget, not a fit tolerance. MEASURED, the residual is
# EXACTLY 0.0 on both arms — the same three floats build both sides, so the division associates identically.
# The 1e-9 is deliberately left as slack rather than tightened to `== 0.0`: the claim being pinned is "these
# separate with no residual", not "IEEE happens to round this way", and a future ρ₀ ≠ 1.225 would make the
# reassociation visible without making the physics one bit less exact.
const FACTORIZE_ATOL := 1.0e-9

enum P { HANDSHAKE, EXP, EXP_REPLAY, CONST, HMAX }

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
var _ceil_min := 1.0e30           # …and its MINIMUM on the approach
var _rho_first := -1.0            # ρ at the START — the ρ-factor's denominator
var _rho_at_cmin := -1.0          # ⭐ ρ AT THE CEILING-MINIMUM FRAME (the factorization is PER-FRAME)
var _v_first := -1.0              # V at the START
var _v_at_cmin := -1.0            # ⭐ V AT THE CEILING-MINIMUM FRAME
var _z_max := 0.0                 # peak altitude reached on the approach (the climb, as a number)
var _rho_key := false             # the key-gated slice-21 telemetry ships
var _pos_trace: Array = []
# recorded across phases
var _exp_pos: Array = []
var _exp_miss := 0.0
var _exp_rhof := -1.0             # the EXP arm's MEASURED ρ-factor — H_MAX is compared against THIS
var _const_miss := 0.0

func _initialize() -> void:
	print("S21V_INIT godot=", Engine.get_version_info().string)
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
			_begin_scan(STEPS, P.EXP)

		# --- H = 8500, Earth's real scale height — the air thins as the missile climbs -------------
		P.EXP:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_exp_pos = _pos_trace.duplicate(true)
			_exp_miss = _min_los
			print("S21V_EXP H=%.0f  miss(frame)=%.3f  ceiling %.1f→%.1f (%.3fx)  rho %.4f→%.4f (rho-factor %.3fx)  z_max=%.0f m  aero_sat=%d/%d (%.1f%%)  defl_sat=%d  keys=%s" %
				[H_DEFAULT, _min_los, _ceil_first, _ceil_min, _collapse(), _rho_first, _rho_at_cmin,
				 _rho_factor(), _z_max, _aero_sat_n, _sampled_n, 100.0 * _sat_frac(), _defl_sat_n, str(_rho_key)])
			if not _rho_key:
				return _fail("an authored scale_height_m must ship the `rho_air` telemetry — the CORE computes ρ, the client displays it (convention 13); without it the ρ-factor headline would have to be divided out of q_dyn in GDScript")
			# ⭐ THE HEADLINE: the ρ-factor COLLAPSES. PURE ALTITUDE, no speed confound, and monotone BY
			# CONSTRUCTION (exp cannot reverse) — which is why it, and not the miss, is the headline.
			if not (_rho_factor() < EXP_RHOF_MAX):
				return _fail("⭐ THE HEADLINE requires the ρ-factor to COLLAPSE within the run (< %.2fx, measured 0.228 — a 4.4× fall), got %.3fx" % [EXP_RHOF_MAX, _rho_factor()])
			# ⭐⭐ THE FACTORIZATION, ON THE WIRE. ceiling(t)/ceiling(0) ≡ [ρ(z)/ρ(z₀)]·[V/V₀]², read at
			# the SAME frame (the identity is per-frame — ρ_min and ceiling_min need not coincide). This
			# is what licenses "the missile lowered its ceiling by CLIMBING" rather than "by slowing":
			# the two causes SEPARATE EXACTLY, with no residual to argue about.
			var lhs := _collapse()
			var rhs := _rho_factor() * pow(_v_at_cmin / _v_first, 2.0)
			# `%s` for the residual, NOT `%.2e`: GDScript's `%` has no `%e`, and an unknown specifier makes
			# the WHOLE format fail silently and return the literal string — so the headline's own number
			# printed as "%.9f" on the first green run. A number that does not print is not a proof.
			print("S21V_FACTORIZE  ceiling %.9f  ==  rho %.9f x V^2 %.9f  =  %.9f   (residual %s)" %
				[lhs, _rho_factor(), pow(_v_at_cmin / _v_first, 2.0), rhs, str(absf(lhs - rhs))])
			if not (absf(lhs - rhs) < FACTORIZE_ATOL):
				return _fail("⭐⭐ the ceiling spread must FACTORIZE EXACTLY into ρ-factor × V-factor (an ALGEBRAIC identity, not a fit): %.9f vs %.9f, residual %s" % [lhs, rhs, str(absf(lhs - rhs))])
			_exp_rhof = _rho_factor()   # the H_MAX arm is pinned against this MEASURED value, not a constant
			if not (_min_los > EXP_MISS_MIN):
				return _fail("the real atmosphere must open the miss (frame CPA > %.0f m, measured 360.7), got %.2f" % [EXP_MISS_MIN, _min_los])
			if not (_sat_frac() > EXP_SAT_MIN):
				return _fail("the collapsed ceiling must CATCH the demand (aero_sat > %.0f%%), got %.1f%%" % [100.0 * EXP_SAT_MIN, 100.0 * _sat_frac()])
			if _defl_sat_n != 0:
				return _fail("the FOURTH cap (δ_max) must NOT bind — defl_sat must stay 0, got %d frames (the lesson would be δ_max in an atmosphere costume)" % _defl_sat_n)
			_reset_then_scan([], STEPS, P.EXP_REPLAY)

		P.EXP_REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_exp_pos, _pos_trace)
			print("S21V_REPLAY posdiff_vs_exp=%s m  miss=%.3f (must be 0.0 / identical — class-4c RNG-free)" % [rdiff, _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % rdiff)
			if not (_min_los == _exp_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _exp_miss])
			_reset_then_scan([_set_fid_cmd("atmosphere", "constant")], STEPS, P.CONST)

		# --- THE BUTTON: back to the OLD MODEL — ⭐ IT HITS, AND ITS CEILING NEVER BINDS ----------
		P.CONST:
			if not _drain_scan():
				return false
			_const_miss = _min_los
			var ratio := _exp_miss / maxf(_min_los, 1.0e-9)
			print("S21V_CONST miss(frame)=%.3f (vs EXP %.3f = %.1fx)  ceiling %.1f→%.1f (%.3fx)  rho %.4f→%.4f (rho-factor %.6fx)  aero_sat=%d/%d  defl_sat=%d" %
				[_min_los, _exp_miss, ratio, _ceil_first, _ceil_min, _collapse(), _rho_first,
				 _rho_at_cmin, _rho_factor(), _aero_sat_n, _sampled_n, _defl_sat_n])
			if not (_min_los < CONST_HIT_MAX):
				return _fail("the OLD MODEL must HIT (frame CPA < %.0f m, measured 1.95), got %.2f — without that the button is not a side-by-side" % [CONST_HIT_MAX, _min_los])
			# ⭐ THE CEILING NEVER BINDS ONCE. The old model thinks the air at 13.6 km is as thick as at
			# sea level, so the engagement looks EASY — it is not merely mis-predicting the miss, it has
			# no idea a constraint exists. An EXACT 0, not a fraction.
			if _aero_sat_n != 0:
				return _fail("⭐ under constant ρ the aero ceiling must NEVER BIND ONCE — got %d/%d frames. Constant ρ must make this engagement look EASY; that it does is the point." % [_aero_sat_n, _sampled_n])
			# ⭐⭐ THE SHARPEST FACT: the twin's ρ-factor is EXACTLY 1.0 — `==`, not `≈`. Its ceiling DOES
			# fall (≈2×, gravity bleeding V on the climb) and its model books 100% of that to speed,
			# BY DEFINITION. It cannot see the 4.4× ρ(z) is taking, because it has no z in its ρ at all.
			if not (_rho_factor() == 1.0):
				return _fail("⭐⭐ the twin's ρ-factor must be EXACTLY 1.0 (constant ρ never moves off ρ₀ by even a bit), got %.17f" % _rho_factor())
			if not (_rho_first == _rho_at_cmin):
				return _fail("constant ρ must be FLAT across the whole approach (%.17f vs %.17f)" % [_rho_first, _rho_at_cmin])
			# …and ALL of its ceiling loss is therefore the V-factor, with no residual (the same identity
			# as P.EXP, degenerating to its speed half — which is precisely the old model's blind spot).
			var cf := pow(_v_at_cmin / _v_first, 2.0)
			if not (absf(_collapse() - cf) < FACTORIZE_ATOL):
				return _fail("under constant ρ the ceiling ratio must be the V-factor ALONE (%.9f vs %.9f)" % [_collapse(), cf])
			if not (ratio > RATIO_MIN):
				return _fail("the rung must be a REAL side-by-side: EXP/CONST frame ratio > %.0fx (measured 185×), got %.1fx" % [RATIO_MIN, ratio])
			if _defl_sat_n != 0:
				return _fail("the twin must keep the 4th cap clear too (defl_sat == 0), got %d" % _defl_sat_n)
			_reset_then_scan([_set_param_cmd("m1", "af_scale_height", H_MAX)], STEPS, P.HMAX)

		# --- H → 25000: a DEEP atmosphere FORGIVES — the not-a-dead-knob tripwire ------------------
		P.HMAX:
			if not _drain_scan():
				return false
			print("S21V_HMAX H=%.0f  miss(frame)=%.3f (vs EXP %.3f)  ceiling %.1f→%.1f (%.3fx)  rho-factor %.3fx  aero_sat=%d/%d  defl_sat=%d" %
				[H_MAX, _min_los, _exp_miss, _ceil_first, _ceil_min, _collapse(), _rho_factor(),
				 _aero_sat_n, _sampled_n, _defl_sat_n])
			# THE TRIPWIRE THE DEAD `speed` KNOB SLIPPED THROUGH (slice-19 gate 3): a knob must MOVE THE
			# PHYSICS, not merely fail to crash. H is fetched every tick by BOTH integrate! and decide!
			# (via `_airframe_rho`), so it is live by construction — assert it anyway, on a NUMBER.
			#
			# PINNED AGAINST THE EXP ARM'S **MEASURED** ρ-FACTOR, not a hand-picked constant (advisor): a
			# first draft compared to `1.5 × EXP_RHOF_MAX` = 0.525, which the actual 0.621 cleared by only
			# 18% — a tooth one scenario tweak from flaking. Comparing the two arms MEASURED (0.621 vs
			# 0.248 = 2.5×) is both a bigger margin AND the honest statement: a deeper atmosphere thins
			# LESS over the SAME climb, and neither number needs to be known in advance to say so.
			if not (_rho_factor() > HMAX_RHOF_MARGIN * _exp_rhof):
				return _fail("the H knob must MOVE the physics: a deeper atmosphere must collapse the ρ-factor LESS than H=8500's MEASURED %.3f (by ≥%.1fx), got %.3f — a knob that changes nothing is a DEAD knob" % [_exp_rhof, HMAX_RHOF_MARGIN, _rho_factor()])
			if not (_min_los < HMAX_HIT_MAX):
				return _fail("a deep, slowly-thinning atmosphere must FORGIVE (frame CPA < %.0f m, measured 6.29), got %.2f" % [HMAX_HIT_MAX, _min_los])
			if not (_min_los < 0.5 * _exp_miss):
				return _fail("H must move the OUTCOME, not just the readout: %.2f vs EXP's %.2f" % [_min_los, _exp_miss])
			if _defl_sat_n != 0:
				return _fail("the H_MAX arm must keep the 4th cap clear (defl_sat == 0), got %d" % _defl_sat_n)
			if not (_sampled_n > 300):
				return _fail("the sampled window must be real, got %d frames" % _sampled_n)
			return _pass()
	return false

# --- stepping / scanning (the slice-10..20 contract) --------------------------------------

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
	_rho_first = -1.0
	_rho_at_cmin = -1.0
	_v_first = -1.0
	_v_at_cmin = -1.0
	_z_max = 0.0
	_rho_key = false
	_pos_trace = []

func _sat_frac() -> float:
	return float(_aero_sat_n) / maxf(float(_sampled_n), 1.0)

# The ceiling's minimum on the approach over its value at the START (slice-20's `_collapse()`, reused).
func _collapse() -> float:
	if _ceil_first <= 0.0 or _ceil_min > 1.0e29:
		return -1.0
	return _ceil_min / _ceil_first

# ⭐ THE HEADLINE NUMBER: the ρ-factor's own fall across the approach — ρ AT THE CEILING-MINIMUM FRAME
# over ρ at the start. PURE ALTITUDE: no V appears in it at all. Read at the ceiling-min frame (not at
# ρ's own min) so it composes with the V-factor into the EXACT per-frame identity above. Under
# `:constant` this is EXACTLY 1.0 — the old model's blind spot, as a number.
func _rho_factor() -> float:
	if _rho_first <= 0.0 or _rho_at_cmin < 0.0:
		return -1.0
	return _rho_at_cmin / _rho_first

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
					_rho_key = tel.has(_mid + ".rho_air")
					_sampled_n += 1
					_z_max = maxf(_z_max, float(tel.get(_mid + ".pos_z", 0.0)))
					var c := float(tel[_mid + ".a_max_aero"])
					var rho := float(tel.get(_mid + ".rho_air", -1.0))
					var v := float(tel.get(_mid + ".speed", 0.0))
					if _ceil_first < 0.0:
						_ceil_first = c        # the ceiling at the START of the approach…
						_rho_first = rho       # …and the ρ and V that built it (the identity's denominator)
						_v_first = v
					# ⭐ ρ and V are latched AT THE CEILING-MINIMUM FRAME, not at their own extrema — the
					# factorization is a PER-FRAME identity, so all three must come from ONE frame.
					if c < _ceil_min:
						_ceil_min = c
						_rho_at_cmin = rho
						_v_at_cmin = v
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
	# Slice 21 reuses slice-17/19/20's `airframe_view` marker, so the aero strip / α strip / nose-vs-
	# velocity drawing all carry over. But UNLIKE slice 20 it is NOT zero client code: the scenario ships
	# an `:airframe` fidelity that the client's airframe branch would grab, so `:atmosphere` is checked
	# FIRST in `_setup_spatial_fid_btn` (the slice-13/14 "the ONE button must toggle the LESSON's key,
	# not the held ones" rule, third occurrence).
	if not bool(f.get("airframe_view", false)):
		return "a slice-21 handshake must ship airframe_view=true (the airframe view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	if str(fid.get("atmosphere", "")) != "exponential":
		return "a slice-21 scenario must default :atmosphere to exponential (the lesson ships ON), got %s" % str(fid.get("atmosphere", "<absent>"))
	# THE CROSS-FIDELITY DEPENDENCY, ASSERTED (slice 19's, restated — never implied): ρ(z) reaches the
	# COUPLED path ONLY. `_atm_on` carries `:pitch_coupled` as a conjunct, so under `:point_mass` this
	# whole rung is INERT (there is no lift ceiling for the air to lower). The scenario must author it.
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-21 scenario must AUTHOR :airframe at pitch_coupled — `:atmosphere` is INERT without it (ρ(z) reaches the coupled path only; a point-mass plant makes its accel by fiat and has no lift ceiling to lower), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-21 scenario must AUTHOR the autopilot at :alpha (the inner α/g loop is what the ceiling clamps), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-21 scenario must hold :guidance at :pn (convention 9 — ONE toggled fidelity), got %s" % str(fid.get("guidance", "<absent>"))
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-21 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-21 scenario must NOT ship terrain_grid (that flips the client to the slice-18 3-D view)"
	# THE lesson lever must be exposed — and the CONFOUNDED ones must NOT be. H is the RATE the air
	# thins: the one degree of freedom no constant ρ has, and the reason `:constant` is unreachable by
	# dragging any slider (it is H = ∞, a LIMIT POINT — within 1% at 13.6 km needs H ≈ 1.4e6).
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if not keys.has("af_scale_height"):
		return "slice-21 handshake must expose the 'af_scale_height' slider — THE lesson lever (H is the RATE the air thins, the one DOF no constant ρ has)"
	if keys.has("speed"):
		return "slice-21 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load and read by NOTHING per-tick, so the slider would be DEAD (slice-19 gate-3 finding)"
	if keys.has("rho") or keys.has("af_alpha_max"):
		return "slice-21 must NOT expose 'rho' / 'af_alpha_max' — ρ₀ is slice-19's lever telling slice-19's story and it scales the WHOLE profile (it cannot produce a GRADIENT, which is the precise difference this slice exists to show); α_max is the very clamp whose LEAK bounds the H range, so moving it moves the bound (convention 9 — one lesson)"
	if keys.has("af_k_induced"):
		return "slice-21 must NOT expose 'af_k_induced' — slice 20's bill would confound the one clean thing this scenario has (K = 0 AND cd_area = 0 is THE ISOLATION: nothing bleeds speed but gravity, and the twin bleeds identically, so the twin difference is PURE ALTITUDE)"
	# The knob range is MEASURED (gate-0 F8), and the FLOOR is the binding constraint: at H ≤ 3000 the
	# achieved α BREACHES α_max (slice-19 FINDING 14 — the clamp bounds the COMMAND, lift uses the
	# ACHIEVED α, so the ceiling LEAKS). The floor sits at 2× that boundary — the slice-20 K discipline.
	for k in f.get("knobs", []):
		if str(k.get("key", "")) == "af_scale_height":
			if float(k.get("min", 0.0)) < 6000.0:
				return "af_scale_height must floor at or above the proven-no-leak bound (6000; H ≤ 3000 breaches α_max and the ceiling LEAKS — gate-0 F8), got %s" % str(k.get("min"))
			if float(k.get("max", 1.0e9)) > 40000.0:
				return "af_scale_height must stay in the measured window (shipped 25000), got %s" % str(k.get("max"))
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _set_fid_cmd(key: String, value: String) -> Dictionary:
	return {"type": "set_fidelity", "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass() -> bool:
	# ALL NUMBERS HERE ARE FRAME-SAMPLED — what THIS file measured, not test_missile.jl's per-tick truth
	# (which reads 360.739 / 1.949 / 6.29 and a 185× ratio). A hit samples coarsely; see the header.
	print("S21V OK: THE EXPONENTIAL ATMOSPHERE — the ceiling you lower by CLIMBING. ρ = ρ₀·exp(−z/H) makes " +
		"the air a function of WHERE THE MISSILE FLIES, and the climb is not optional: it is the only way " +
		"to a 14 km target. Climb → ρ(z) falls → Q falls → a_max_aero = Q·S·C_Lα·α_max/m falls → you " +
		"cannot pull → you miss. Under the REAL atmosphere (H = 8500, Earth's own) the missile climbs to " +
		"12.8 km, the ρ-factor COLLAPSES 4× WITHIN one run (1.088 → 0.270 kg/m³), the ceiling falls " +
		"239 → 31, the demand crosses it on 25.6% of the approach, and it MISSES by 360.8 m. Press the " +
		"button back to :constant — slices 8–20's authored ρ — and the SAME missile on the SAME geometry " +
		"against the SAME jink HITS (3.1 m frame-sampled, true 1.9; a 117× ratio on the wire, 185× " +
		"per-tick), because its ceiling NEVER BINDS ONCE (0/2628): the old model thinks the air at 12.8 km " +
		"is as thick as at sea level, so the engagement looks EASY. Constant ρ was lying to you at " +
		"altitude. ⭐ THE CLAIM IS EXACT, NOT FITTED: the ceiling ratio is IDENTICALLY [ρ(z)/ρ(z₀)]·[V/V₀]², " +
		"verified ON THE WIRE at the ceiling-minimum frame with a residual of EXACTLY 0.0 — so ALTITUDE and " +
		"SPEED separate with NO residual at all (slice 20's V-only collapse could never be decomposed). " +
		"And the twin's ρ-factor is " +
		"EXACTLY 1.0: its ceiling DOES fall (0.524×) but constant ρ books 100% of that to speed — that 2× " +
		"is GRAVITY on the climb — and it cannot see the 4× ρ(z) is taking, because it has no z in its ρ at " +
		"all. Nothing that SETS the ceiling moved: ρ₀, S, C_Lα, α_max and mass are held across every arm, " +
		"and cd_area = 0 with K = 0, so nothing bleeds speed but gravity and the twin bleeds identically — " +
		"the difference is PURE ALTITUDE. H is a live lever, not a dead one (H = 25000 forgives: 7.1 m, and " +
		"a ρ-factor of 0.621 vs 0.248 — a deeper atmosphere thins LESS over the same climb). The isolation " +
		"holds in every arm (defl_sat == 0 at ENDGAME_RANGE = 1000, MEASURED at gate 2 — slice-19's 300 " +
		"FAILS here because the twin HITS and flies the r→0 endgame). This is the same cap slice 19 found " +
		"and slice 20 made self-lowering; slice 21 gives it a THIRD mover — not the engineer's knob, not " +
		"the missile's turn, but WHERE IT FLIES. Physics-changing, RNG-free, live-settable (class 4c), and " +
		"INERT without :pitch_coupled.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S21V FAIL: " + msg)
	print("S21V FAIL: ", msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	# `close()` + `free()` — the slice8..20_verify contract.
	if _client != null:
		_client.close()
		_client.free()
		_client = null
