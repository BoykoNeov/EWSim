extends SceneTree
# Headless slice-22 gate-3 verifier (the slice8..21_verify analog). Drives the REAL Julia server through
# SimClient.gd — the same protocol code Sandbox.tscn renders off — and asserts slice-22's nonlinear-aero
# "done" criteria as machine checks on the SCALAR telemetry (los_range / a_max_aero / post_stall /
# aero_sat / defl_sat / alpha / omega_sp / pos_*).
#
# ⚠ ONE FILE, TWO SCENARIOS — AND THE SPLIT IS A **MEASURED CONFIG CONFLICT**, NOT A STYLE CHOICE.
# Slice 22 ships TWO scenarios because its two halves need INCOMPATIBLE WIRES (the lift half needs
# k_drop 0.7 / δ_max 0.4; the departure half needs k_drop 1.0 / δ_max 1.0, and at k_drop 0.7 the
# authority cliff is INVISIBLE — gate-2 G2). This file DETECTS which one the server loaded, from the
# declared knob key, and runs the matching phase set. Run it twice, once against each server:
#   godot --headless --path clients/godot --script res://net/slice22_verify.gd
# Exit codes: 0 = all asserts pass, 1 = assertion failed, 2 = timeout.
#
# ════════════════════════════════════════════════════════════════════════════════════════════════
# HALF A — `slice22_stall.yaml`: **THE CEILING THE AIRFRAME SETS** (knob `af_alpha_stall`)
# ════════════════════════════════════════════════════════════════════════════════════════════════
# Slices 19/20/21 gave cap #4 (`a_max_aero`) three movers and ALL THREE MOVED Q (the engineer's ρ knob;
# the missile's own turn via V; where it flies via ρ(z)). Slice 22 moves the OTHER factor: every one of
# those slices assumed the lift curve is a STRAIGHT LINE out to α_max. Past α_stall the flow SEPARATES,
# C_L PEAKS AND FALLS, and the ceiling is the curve's own INTERIOR PEAK — no amount of Q buys past it.
#
# ⭐ THE HEADLINE IS AN EXACT IDENTITY: at fixed Q the linear→stall ceiling ratio is IDENTICALLY
# α_stall/α_max, because Q, S, C_Lα and m ALL CANCEL. ⚠ **THE EXACT TOOTH IS A CORE TEST, NOT THIS
# FILE** — `test_aero_curve.jl` pins the coefficient ratio to 1e-15 and `test_missile.jl` pins
# `aero_accel_limit` linear-vs-stall on IDENTICAL inputs to 1e-12 (|Δ| measures 0.0). This file can
# only CORROBORATE it from frame-sampled scalars, and it does so honestly: the ratio is read at
# `ceil_first` — the first sampled frame, at r ≈ 6000 m, where the missile is still PRE-STALL and both
# arms are in the SAME state, so it is legitimately a same-inputs comparison. Read any later and
# separation drag has made V (hence Q) diverge between the arms and it would CONFOUND ITSELF.
#
# ⭐⭐ AND THE SHARPEST TOOTH: **`aero_sat` FIRES ON THE PARKED, LINEAR ARM TOO** (26.3% in BOTH arms),
# so it CANNOT be the stall tell. `aero_sat` keys off the α_max CLAMP, which both arms SHARE, while the
# ceiling that moved is the interior peak (gate-2 G10). **`post_stall` is the discriminator: EXACTLY 0
# on the parked arm vs 894 frames stalled.** This is asserted as a POSITIVE fact in both directions,
# and it is precisely what licenses the client's breach indicator keying on `post_stall`.
#
# ════════════════════════════════════════════════════════════════════════════════════════════════
# HALF B — `slice22_departure.yaml`: **RELAXED STATIC STABILITY** (knob `af_cma_post`)
# ════════════════════════════════════════════════════════════════════════════════════════════════
#     ★ A STATICALLY UNSTABLE AIRFRAME IS PERFECTLY FLYABLE — UNTIL THE AUTOPILOT RUNS OUT
#       OF AUTHORITY. **THE THRESHOLD IS THE LESSON, NOT THE TUMBLE.**
#
# ⚠⚠ THIS IS A **THREE-POINT** CLAIM AND THE MIDDLE POINT IS THE LESSON. A two-point 0-vs-8 check
# would demonstrate "NEUTRAL vs LOST" — a weaker and DIFFERENT claim than the ratified one — because
# at `cma_post 0` the airframe is NEUTRALLY stable past the break (slope 0), **not unstable at all**:
# the ω_sp sentinel never fires. It is the CONTROL. The lesson is `cma_post 4`: the sentinel FIRES
# (947 ticks — nearly a second with NO REAL SHORT-PERIOD MODE, so the airframe is genuinely
# statically unstable) and **the autopilot HOLDS IT ANYWAY** (α@500 only 0.43; the miss is 302 vs the
# 280 baseline, within 8%). Only past ~6 does the same autopilot, same fin, same gains lose it.
# So the phases assert SILENT → FIRING-BUT-HELD → LOST, precisely so the middle cannot be dropped.
#
# ⚠ THE MISS IS **NOT** THE METRIC FOR HALF B (gate-0 F4/F10, and it is final): even at full tumble
# the LIFT file's miss moves only +1.4% — a missile that departs 0.7 s before CPA keeps its momentum.
# The miss is used here ONLY as a corroborating bound (held ≈ baseline vs lost > baseline), never as
# the headline. ⚠ AND "TIME WITH ω_sp CEILED" IS **NOT** A SEVERITY MEASURE — it RUNS BACKWARDS
# (gate-2 G6): the count FALLS 947 → 526 → 442 as cma_post rises 4 → 8 → 10, because α blows straight
# past α_sat into the deep-stall RESTORING region where ω_sp is real again. It is asserted as a
# BOOLEAN (fired / silent), never compared for magnitude.
#
# ⚠ α IS SAMPLED AT A **FIXED RANGE (r = 500 m)**, NOT AT CPA — and that is a gate-3 finding, not a
# preference. The break is reached at t = 3.12 s / r = 1474.7 m in EVERY arm (identical to the metre);
# the divergence then develops between there and CPA, and α_pk lands within a few ms OF the CPA frame,
# i.e. exactly where PN's r→0 demand spike lives. A fixed-range sample at 500 m sits well past the
# break and well above the r→0 artifact, so it needs no common-mode argument at all.
#   ⚠ AND THE LIFT FILE'S LOS GATE (1000) WOULD **DELETE** HALF B's LESSON: at r > 1000 the arms have
#   barely diverged (α@1000 spans only 0.297 → 0.399 across the whole knob range). The correct gate
#   differs between the two halves — MEASURED, not assumed ([[ewsim-missile-verifier-sampling]]).
#
# ════════════════════════════════════════════════════════════════════════════════════════════════
# FRAME SAMPLING IS LOAD-BEARING, AND THE NUMBERS BELOW ARE PER-TICK PROBE VALUES. This file reads
# emit_every = 16 frames (~24 m of closure per sample at these speeds), so every α bound is asserted
# as a THRESHOLD WITH MARGIN and every count as a BOOLEAN or an ORDERING — never as an absolute value.
#   • A MISS samples FAITHFULLY (radial rate → 0 at CPA), so the miss bounds are tight-ish.
#   • α@500 has ~24 m of sample jitter; at cma_post 8 the local gradient is ~0.04 rad/frame, so the
#     bounds carry several frames of slack.
#   • ω_ceiled 947 ticks ⇒ only ~59 frames. Asserted as "> 5" / "== 0", never as a count.
# Slice-21's THREE proof bugs are live watch-items and all three are avoided here: `%.2e` is NOT a
# GDScript specifier (an unknown one makes the WHOLE `%` fail SILENTLY and print the literal format
# string — a number that does not print is not a proof), so residuals print via `str()`; the frame-vs-
# tick numbers are labelled everywhere; and no magic multiple is pinned that was not measured.
#
# Everything is RNG-FREE (truth-fed PN, no seeker) so "draw-count invariance" is VACUOUS (class 4c) —
# do NOT copy slice-11/13 draw language. CPA is measured from the core's own `los_range` on the FIRST
# DESCENDING BAND only.

const HOST := "127.0.0.1"
const PORT := 8765
const MAX_SECONDS := 900.0
const SimClientScript := preload("res://net/SimClient.gd")

# Step counts are MULTIPLES of emit_every (16) so the LAST emit lands cleanly (the drain contract).
# 8000 = 500·16 = 8 s. CPA is at t ≈ 4.1 s on both files, so the first-descending band closes and
# latches with ~4 s to spare on every arm.
const STEPS := 8000

# --- Half A (lift) constants -----------------------------------------------------------------
const A_STALL_SHIPPED := 0.20     # the authored corner
const A_STALL_PARKED := 0.35      # = α_max ⇒ the corner leaves every reachable α: THE LINEAR TWIN
const A_STALL_FLOOR := 0.15       # the knob's measured floor
const ALPHA_MAX := 0.35           # the scenario's α_max — the identity's denominator
# ⚠ MEASURED (gate 2), and it is the LIFT file's gate only. Both arms miss by 125–437 m, so every arm
# reaches r ≤ 1000 and is endgame-excluded IDENTICALLY — the consistency the range-gate rule demands.
# It is also what makes `defl_sat == 0` an assertion rather than a hope: the PARKED arm records ONE
# defl_sat frame in the r→0 endgame, which is the artifact this gate exists to exclude.
const ENDGAME_RANGE := 1000.0
const STALL_MISS_MIN := 180.0     # stall frame CPA (per-tick 240.9)
const PARKED_MISS_MAX := 160.0    # parked frame CPA (per-tick 125.14) — the linear twin
const MISS_RATIO_MIN := 1.5       # stall/parked (per-tick 1.92×)
const POST_STALL_FRAC_MIN := 0.15 # stall arm's post_stall fraction (per-tick 894/3253 = 27.5%)
const RATIO_ATOL := 1.0e-6        # the ceil_first ratio vs α_stall/α_max (a same-inputs read, see header)

# --- Half B (departure) constants ------------------------------------------------------------
const CMA_LOST := 8.0             # the authored default — the autopilot LOSES it
const CMA_UNSTABLE := 4.0         # ⭐ THE LESSON: unstable (sentinel FIRES) and STILL FLYABLE
const CMA_NEUTRAL := 0.0          # the CONTROL: neutral past the break, sentinel SILENT
const FIXED_RANGE := 500.0        # α sampled HERE, not at CPA (see the header)
const A500_NEUTRAL_MAX := 0.40    # per-tick 0.3091
const A500_UNSTABLE_MIN := 0.35   # per-tick 0.4314 — bounded on BOTH sides: it must move, but HOLD
const A500_UNSTABLE_MAX := 0.70
const A500_LOST_MIN := 0.75       # per-tick 0.9873
const OMEGA_FIRED_MIN := 5        # 947 ticks ⇒ ~59 frames; asserted as "fired", never as a count
const HELD_MISS_TOL := 0.25       # the held arm's miss must stay near baseline (per-tick 302 vs 280)
const LOST_MISS_MIN := 1.15       # the lost arm's miss must open vs baseline (per-tick 371/280 = 1.33)

enum P { HANDSHAKE,
	A_STALL, A_REPLAY, A_PARKED, A_FLOOR,
	B_LOST, B_REPLAY, B_UNSTABLE, B_NEUTRAL }

var _client
var _inbox: Array = []
var _phase: P = P.HANDSHAKE
var _dt := 1.0e-3
var _mid := ""
var _t_target := 0.0
var _last_state: Dictionary = {}
var _t0 := 0.0
var _half := ""                   # "lift" | "departure" — decided at the handshake

# scan accumulators (reset per burst)
var _min_los := 1.0e30            # CPA on the FIRST DESCENDING BAND only
var _prev_los := 1.0e30
var _closing := true              # latched false at the first ascent (no post-CPA re-crossing)
var _past_endgame := false
var _sampled_n := 0               # frames in the LOS-gated window (half A's counters)
var _aero_sat_n := 0              # the α_max-clamp flag — fires on BOTH arms (the G10 tooth)
var _post_stall_n := 0            # ⭐ the STALL discriminator (0 on the linear arm)
var _defl_sat_gated := 0          # δ_max in the gated window (half A's isolation)
var _defl_sat_full := 0           # …and over the WHOLE band (half B's isolation — measured 0)
var _omega_ceiled_n := 0          # frames with ω_sp at FINITE_CEIL — the sentinel FIRING
var _ceil_first := -1.0           # the ceiling at the first sampled frame (PRE-STALL — same-inputs)
var _ceil_min := 1.0e30
var _alpha_at_fixed := -1.0       # ⭐ α at the first frame with r ≤ FIXED_RANGE
var _alpha_pk := 0.0
var _post_stall_key := false
var _pos_trace: Array = []
# recorded across phases
var _ref_pos: Array = []
var _ref_miss := 0.0
var _stall_ceil := -1.0
var _stall_miss := 0.0
var _neutral_miss := 0.0

func _initialize() -> void:
	print("S22V_INIT godot=", Engine.get_version_info().string)
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
			print("S22V_HALF %s" % _half)
			_begin_scan(STEPS, P.A_STALL if _half == "lift" else P.B_LOST)

		# ══ HALF A ═══════════════════════════════════════════════════════════════════════════
		# --- the authored corner: the curve's INTERIOR PEAK is the ceiling, and it BINDS --------
		P.A_STALL:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_ref_pos = _pos_trace.duplicate(true)
			_ref_miss = _min_los
			_stall_miss = _min_los
			_stall_ceil = _ceil_first
			print("S22V_A_STALL a_stall=%.2f  miss(frame)=%.3f  ceiling %.2f→%.2f  post_stall=%d/%d (%.1f%%)  aero_sat=%d/%d (%.1f%%)  defl_sat=%d  a_pk=%.4f" %
				[A_STALL_SHIPPED, _min_los, _ceil_first, _ceil_min, _post_stall_n, _sampled_n,
				 100.0 * _frac(_post_stall_n), _aero_sat_n, _sampled_n, 100.0 * _frac(_aero_sat_n),
				 _defl_sat_gated, _alpha_pk])
			if not _post_stall_key:
				return _fail("an authored alpha_stall must ship the `post_stall` telemetry — it is the DISCRIMINATOR (`aero_sat` fires on the linear arm too, gate-2 G10) and the client's breach indicator keys on it; without it the client would have to infer the stall in GDScript (convention 13)")
			if not (_min_los > STALL_MISS_MIN):
				return _fail("the stall ceiling must open the miss (frame CPA > %.0f m, per-tick 240.9), got %.2f" % [STALL_MISS_MIN, _min_los])
			# ⭐ THE DISCRIMINATOR FIRES. The airframe spends a large fraction of the approach PAST ITS
			# OWN LIFT PEAK — the regime slices 19–21 could not represent at all.
			if not (_frac(_post_stall_n) > POST_STALL_FRAC_MIN):
				return _fail("the missile must fly PAST ITS LIFT PEAK for a real fraction of the approach (post_stall > %.0f%%, per-tick 27.5%%), got %.1f%%" % [100.0 * POST_STALL_FRAC_MIN, 100.0 * _frac(_post_stall_n)])
			if _defl_sat_gated != 0:
				return _fail("the FOURTH cap (δ_max) must NOT bind — defl_sat must stay 0 in the gated window, got %d frames (the lesson would be δ_max in a stall costume — slice-19 FINDING 2 / gate-2 G3)" % _defl_sat_gated)
			_reset_then_scan([], STEPS, P.A_REPLAY)

		P.A_REPLAY:
			if not _drain_scan():
				return false
			var rdiff := _pos_max_diff(_ref_pos, _pos_trace)
			print("S22V_A_REPLAY posdiff=%s m  miss=%.3f (must be 0.0 — class-4c RNG-free)" % [str(rdiff), _min_los])
			if not (rdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c)" % str(rdiff))
			if not (_min_los == _ref_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ref_miss])
			_reset_then_scan([_set_param_cmd("m1", "af_alpha_stall", A_STALL_PARKED)], STEPS, P.A_PARKED)

		# --- THE KNOB'S OWN TOP IS THE LINEAR TWIN: park the corner out of every reachable α ----
		P.A_PARKED:
			if not _drain_scan():
				return false
			var ratio := _stall_miss / maxf(_min_los, 1.0e-9)
			var ceil_ratio := _stall_ceil / maxf(_ceil_first, 1.0e-9)
			print("S22V_A_PARKED a_stall=%.2f  miss(frame)=%.3f (vs stall %.3f = %.2fx)  ceiling %.2f→%.2f  post_stall=%d/%d  aero_sat=%d/%d (%.1f%%)  defl_sat=%d" %
				[A_STALL_PARKED, _min_los, _stall_miss, ratio, _ceil_first, _ceil_min,
				 _post_stall_n, _sampled_n, _aero_sat_n, _sampled_n, 100.0 * _frac(_aero_sat_n), _defl_sat_gated])
			if not (_min_los < PARKED_MISS_MAX):
				return _fail("parking the corner at α_max must recover the LINEAR miss (frame CPA < %.0f m, per-tick 125.14), got %.2f — this is the KNOB-not-RUNG claim (gate-0 F7/Decision 1): the off-state is an IN-DOMAIN slider value, so no fidelity rung is needed" % [PARKED_MISS_MAX, _min_los])
			# ⭐ THE DISCRIMINATOR IS EXACTLY ZERO HERE — the corner is out of reach, so the airframe
			# NEVER goes past its lift peak. An EXACT 0, not a small fraction.
			if _post_stall_n != 0:
				return _fail("⭐ with the corner PARKED at α_max the airframe must NEVER reach post-stall — post_stall must be EXACTLY 0, got %d/%d frames" % [_post_stall_n, _sampled_n])
			# ⭐⭐ AND THE TOOTH THAT JUSTIFIES THE CLIENT EDIT (gate-2 G10): `aero_sat` FIRES ANYWAY on
			# this LINEAR arm, because it keys off the α_max CLAMP that BOTH arms share — so it cannot
			# be the stall tell, and a breach indicator keyed on it would under-report the very breach
			# this slice is about. Asserted POSITIVELY (it fires here), not as an approximate equality.
			if not (_aero_sat_n > 0):
				return _fail("⭐⭐ `aero_sat` must fire on the LINEAR arm too (per-tick 26.3%%, the same as the stall arm) — that is WHY it cannot be the stall tell and why `post_stall` exists (gate-2 G10). Got %d/%d: if it no longer fires here, the G10 argument and the client's breach indicator both need re-deriving" % [_aero_sat_n, _sampled_n])
			# ⭐ THE HEADLINE, CORROBORATED ON THE WIRE. `ceil_first` is the first sampled frame at
			# r ≈ 6000 m, where BOTH arms are still PRE-STALL and in the SAME state — so this is a
			# same-inputs comparison, not a confounded run-vs-run. The EXACT identity (|Δ| = 0.0) is
			# pinned in test_aero_curve.jl / test_missile.jl; this only shows it survives the wire.
			print("S22V_A_IDENTITY ceiling ratio %.9f  vs  a_stall/a_max %.9f   (residual %s)" %
				[ceil_ratio, A_STALL_SHIPPED / ALPHA_MAX, str(absf(ceil_ratio - A_STALL_SHIPPED / ALPHA_MAX))])
			if not (absf(ceil_ratio - A_STALL_SHIPPED / ALPHA_MAX) < RATIO_ATOL):
				return _fail("⭐ the linear→stall ceiling ratio must be IDENTICALLY α_stall/α_max (Q, S, C_Lα and m ALL cancel): %.9f vs %.9f, residual %s" % [ceil_ratio, A_STALL_SHIPPED / ALPHA_MAX, str(absf(ceil_ratio - A_STALL_SHIPPED / ALPHA_MAX))])
			if not (ratio > MISS_RATIO_MIN):
				return _fail("the curve must be a REAL side-by-side: stall/linear frame ratio > %.1fx (per-tick 1.92×), got %.2fx" % [MISS_RATIO_MIN, ratio])
			if _defl_sat_gated != 0:
				return _fail("the linear twin must keep the 4th cap clear too (defl_sat == 0), got %d" % _defl_sat_gated)
			_reset_then_scan([_set_param_cmd("m1", "af_alpha_stall", A_STALL_FLOOR)], STEPS, P.A_FLOOR)

		# --- the knob's floor: a LOWER corner is a LOWER ceiling. The not-a-dead-knob tripwire ----
		P.A_FLOOR:
			if not _drain_scan():
				return false
			print("S22V_A_FLOOR a_stall=%.2f  miss(frame)=%.3f (vs stall %.3f)  ceiling %.2f (vs stall %.2f)  post_stall=%d/%d  defl_sat=%d" %
				[A_STALL_FLOOR, _min_los, _stall_miss, _ceil_first, _stall_ceil, _post_stall_n, _sampled_n, _defl_sat_gated])
			# THE TRIPWIRE THE DEAD `speed` KNOB SLIPPED THROUGH (slice-19 gate 3): a knob must MOVE
			# THE PHYSICS, not merely fail to crash. Assert it on a NUMBER, in BOTH the ceiling and
			# the outcome — and note the CEILING is the monotone-by-construction one (the miss REVERSES
			# below α_stall ≈ 0.12, which is exactly why the knob floors at 0.15).
			if not (_ceil_first < _stall_ceil):
				return _fail("the α_stall knob must MOVE the physics: a LOWER corner must give a LOWER ceiling (%.2f vs %.2f) — a knob that changes nothing is a DEAD knob" % [_ceil_first, _stall_ceil])
			if not (_min_los > _stall_miss):
				return _fail("a lower corner must open the miss further (%.2f vs %.2f)" % [_min_los, _stall_miss])
			if not (_frac(_post_stall_n) > POST_STALL_FRAC_MIN):
				return _fail("the floor arm must still fly post-stall, got %.1f%%" % [100.0 * _frac(_post_stall_n)])
			if _defl_sat_gated != 0:
				return _fail("the floor arm must keep the 4th cap clear (defl_sat == 0), got %d — the knob domain is bounded so this stays true" % _defl_sat_gated)
			# ⚠ 150, NOT slice-21's 300 — a MEASURED window, not a copied constant. Slice 21 ran 48000
			# steps (3000 frames) for a 43 s climbing intercept; this engagement's CPA is at t ≈ 4.1 s,
			# so STEPS = 8000 gives 500 frames total and ~215 in the LOS-gated window. Copying the 300
			# failed here on a run where every physics assertion had already passed.
			if not (_sampled_n > 150):
				return _fail("the sampled window must be real, got %d frames" % _sampled_n)
			return _pass_lift()

		# ══ HALF B ═══════════════════════════════════════════════════════════════════════════
		# --- the authored default: the autopilot LOSES the airframe ----------------------------
		P.B_LOST:
			if not _drain_scan():
				return false
			if _mid == "":
				_mid = _find_missile(_last_state)
			if _mid == "":
				return _fail("no :missile entity in the state stream")
			_ref_pos = _pos_trace.duplicate(true)
			_ref_miss = _min_los
			print("S22V_B_LOST cma_post=%.1f  a@%.0fm=%.4f (%.1f deg)  a_pk=%.4f  omega_ceiled=%d  miss=%.3f  defl_sat(full)=%d" %
				[CMA_LOST, FIXED_RANGE, _alpha_at_fixed, rad_to_deg(_alpha_at_fixed), _alpha_pk,
				 _omega_ceiled_n, _min_los, _defl_sat_full])
			if _alpha_at_fixed < 0.0:
				return _fail("no frame sampled at r <= %.0f m — the fixed-range α sample is the headline and it must exist" % FIXED_RANGE)
			if not (_alpha_at_fixed > A500_LOST_MIN):
				return _fail("the autopilot must LOSE the airframe at the authored cma_post (α@%.0fm > %.2f rad, per-tick 0.987 = 56.6°), got %.4f" % [FIXED_RANGE, A500_LOST_MIN, _alpha_at_fixed])
			# ⭐ SLICE 16's SENTINEL FIRES IN FLIGHT — first time in project history. Built for an
			# AUTHORED Cmα ≥ 0 and never fired mid-run until this slice; past the break the LOCAL slope
			# is cma_post > 0, so ω² < 0 and it fires DYNAMICALLY. Asserted as a BOOLEAN: the count
			# RUNS BACKWARDS with severity (gate-2 G6) and must never be compared for magnitude.
			if not (_omega_ceiled_n > OMEGA_FIRED_MIN):
				return _fail("the ω_sp sentinel must FIRE in flight (> %d frames; per-tick 526 ticks) — it is the readout that says there is no longer an oscillation to have. Got %d" % [OMEGA_FIRED_MIN, _omega_ceiled_n])
			# THE ISOLATION, over the WHOLE band (not merely a gated window): δ_max = 1.0 rad is
			# authored unphysically generous SPECIFICALLY so the deflection cap is provably not the
			# story. Gate-2 G9 found that at δ_max 0.4 the cap AMPLIFIES the divergence (α_pk 1.22 →
			# 3.02) — part of gate 0's dramatic 2.7779 was that contamination, which is why it is
			# never quoted. This assertion is what keeps the clean progression clean.
			if _defl_sat_full != 0:
				return _fail("δ_max must NOT bind anywhere on the band — defl_sat must be 0, got %d frames. At δ_max 0.4 it binds and AMPLIFIES the divergence (gate-2 G9); that contamination is exactly what this file must not ship" % _defl_sat_full)
			_reset_then_scan([], STEPS, P.B_REPLAY)

		P.B_REPLAY:
			if not _drain_scan():
				return false
			var bdiff := _pos_max_diff(_ref_pos, _pos_trace)
			print("S22V_B_REPLAY posdiff=%s m  miss=%.3f (must be 0.0 — class-4c RNG-free)" % [str(bdiff), _min_los])
			if not (bdiff == 0.0):
				return _fail("held-config replay must be BIT-IDENTICAL (posdiff %s m) — RNG-free determinism (class 4c), and a DEPARTING airframe is the hardest case for it" % str(bdiff))
			if not (_min_los == _ref_miss):
				return _fail("held-config replay CPA must be bit-identical (%.9f vs %.9f)" % [_min_los, _ref_miss])
			_reset_then_scan([_set_param_cmd("m1", "af_cma_post", CMA_NEUTRAL)], STEPS, P.B_NEUTRAL)

		# --- the CONTROL: neutral past the break. The sentinel is SILENT ------------------------
		P.B_NEUTRAL:
			if not _drain_scan():
				return false
			_neutral_miss = _min_los
			print("S22V_B_NEUTRAL cma_post=%.1f  a@%.0fm=%.4f (%.1f deg)  a_pk=%.4f  omega_ceiled=%d  miss=%.3f  defl_sat(full)=%d" %
				[CMA_NEUTRAL, FIXED_RANGE, _alpha_at_fixed, rad_to_deg(_alpha_at_fixed), _alpha_pk,
				 _omega_ceiled_n, _min_los, _defl_sat_full])
			if not (_alpha_at_fixed < A500_NEUTRAL_MAX):
				return _fail("with a NEUTRAL post-break slope the autopilot must hold α down (α@%.0fm < %.2f, per-tick 0.309), got %.4f" % [FIXED_RANGE, A500_NEUTRAL_MAX, _alpha_at_fixed])
			# ⭐ THE CONTROL: cma_post = 0 is NEUTRAL, **not unstable** — so the sentinel must be
			# SILENT. This is what makes the middle arm's FIRING meaningful rather than ambient.
			if _omega_ceiled_n != 0:
				return _fail("⭐ at a NEUTRAL post-break slope the ω_sp sentinel must be EXACTLY SILENT (ω² ≥ 0 everywhere) — got %d frames. If it fires here, the sentinel is not evidence of instability and half B's whole argument collapses" % _omega_ceiled_n)
			if _defl_sat_full != 0:
				return _fail("the control arm must keep the 4th cap clear (defl_sat == 0), got %d" % _defl_sat_full)
			_reset_then_scan([_set_param_cmd("m1", "af_cma_post", CMA_UNSTABLE)], STEPS, P.B_UNSTABLE)

		# --- ⭐⭐ THE LESSON: statically UNSTABLE, and the autopilot HOLDS IT ANYWAY ---------------
		P.B_UNSTABLE:
			if not _drain_scan():
				return false
			var miss_ratio := _min_los / maxf(_neutral_miss, 1.0e-9)
			print("S22V_B_UNSTABLE cma_post=%.1f  a@%.0fm=%.4f (%.1f deg)  a_pk=%.4f  omega_ceiled=%d  miss=%.3f (%.3fx the neutral %.3f)  defl_sat(full)=%d" %
				[CMA_UNSTABLE, FIXED_RANGE, _alpha_at_fixed, rad_to_deg(_alpha_at_fixed), _alpha_pk,
				 _omega_ceiled_n, _min_los, miss_ratio, _neutral_miss, _defl_sat_full])
			# ⭐ HALF B's ACTUAL CLAIM, IN TWO ASSERTIONS THAT MUST BOTH HOLD AT ONCE.
			# (1) The airframe IS statically unstable — the sentinel FIRES (per-tick 947 ticks, nearly
			#     a second with no real short-period mode).
			if not (_omega_ceiled_n > OMEGA_FIRED_MIN):
				return _fail("⭐ the LESSON arm must be genuinely UNSTABLE — the ω_sp sentinel must FIRE (> %d frames, per-tick 947 ticks). Got %d: without this the arm is just 'a bit worse than neutral' and the ratified lesson ('unstable YET FLYABLE') is not demonstrated at all" % [OMEGA_FIRED_MIN, _omega_ceiled_n])
			# (2) …AND THE AUTOPILOT HOLDS IT. α moves off the neutral baseline but stays FAR below
			#     the lost arm, and the miss stays essentially at baseline. THIS PAIR IS THE LESSON:
			#     "statically unstable is perfectly flyable — until the authority runs out."
			if not (_alpha_at_fixed > A500_UNSTABLE_MIN and _alpha_at_fixed < A500_UNSTABLE_MAX):
				return _fail("⭐⭐ the LESSON arm must be UNSTABLE **AND STILL FLYABLE**: α@%.0fm must sit in (%.2f, %.2f) — above the neutral control, far below the LOST arm's %.2f (per-tick 0.431). Got %.4f: outside this band the three-point story (SILENT → FIRING-BUT-HELD → LOST) collapses to a two-point one, which is a WEAKER and DIFFERENT claim than the ratified lesson" % [FIXED_RANGE, A500_UNSTABLE_MIN, A500_UNSTABLE_MAX, A500_LOST_MIN, _alpha_at_fixed])
			if not (miss_ratio < 1.0 + HELD_MISS_TOL):
				return _fail("⭐⭐ 'still FLYABLE' must show in the OUTCOME: the unstable-but-held arm's miss must stay within %.0f%% of the neutral baseline (per-tick 302 vs 280 = +8%%), got %.3fx" % [100.0 * HELD_MISS_TOL, miss_ratio])
			# …and the LOST arm must actually be worse, or "until the authority runs out" is unearned.
			if not (_ref_miss > LOST_MISS_MIN * _neutral_miss):
				return _fail("the LOST arm's miss must OPEN vs the neutral baseline (> %.2fx, per-tick 371/280 = 1.33×), got %.3fx — the miss is NOT the headline here (gate-0 F4) but it must at least corroborate the direction" % [LOST_MISS_MIN, _ref_miss / maxf(_neutral_miss, 1.0e-9)])
			if _defl_sat_full != 0:
				return _fail("the lesson arm must keep the 4th cap clear (defl_sat == 0), got %d" % _defl_sat_full)
			return _pass_departure()
	return false

# --- stepping / scanning (the slice-10..21 contract) --------------------------------------

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
	_sampled_n = 0
	_aero_sat_n = 0
	_post_stall_n = 0
	_defl_sat_gated = 0
	_defl_sat_full = 0
	_omega_ceiled_n = 0
	_ceil_first = -1.0
	_ceil_min = 1.0e30
	_alpha_at_fixed = -1.0
	_alpha_pk = 0.0
	_post_stall_key = false
	_pos_trace = []

func _frac(n: int) -> float:
	return float(n) / maxf(float(_sampled_n), 1.0)

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
			if _closing:
				# FULL-BAND accumulators (half B's — its lesson lives INSIDE r ≤ 1000, so the lift
				# file's gate would delete it; see the header. The r→0 spike is common mode across
				# these arms and the fixed-range α sample sits well above it anyway).
				var a := absf(float(tel.get(_mid + ".alpha", 0.0)))
				_alpha_pk = maxf(_alpha_pk, a)
				if float(tel.get(_mid + ".defl_sat", 0.0)) > 0.5:
					_defl_sat_full += 1
				if float(tel.get(_mid + ".omega_sp", 0.0)) >= 1.0e9:
					_omega_ceiled_n += 1          # FINITE_CEIL — ω² < 0, no real short-period mode
				# ⭐ α AT A FIXED RANGE — latched at the FIRST frame at or below it, so the sample is
				# a fixed GEOMETRY rather than a fixed time or the CPA frame.
				if _alpha_at_fixed < 0.0 and r <= FIXED_RANGE:
					_alpha_at_fixed = a
				# LOS-GATED accumulators (half A's — the r→0 endgame spikes the demand for reasons
				# that are not the lesson, and the PARKED arm records one defl_sat frame there).
				if not _past_endgame and r > ENDGAME_RANGE and tel.has(_mid + ".a_max_aero"):
					_post_stall_key = tel.has(_mid + ".post_stall")
					_sampled_n += 1
					var c := float(tel[_mid + ".a_max_aero"])
					if _ceil_first < 0.0:
						_ceil_first = c   # the first sampled frame — PRE-STALL, so a same-inputs read
					_ceil_min = minf(_ceil_min, c)
					if float(tel.get(_mid + ".aero_sat", 0.0)) > 0.5:
						_aero_sat_n += 1
					if float(tel.get(_mid + ".post_stall", 0.0)) > 0.5:
						_post_stall_n += 1
					if float(tel.get(_mid + ".defl_sat", 0.0)) > 0.5:
						_defl_sat_gated += 1
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
	# Slice 22 reuses slice-17/19/20/21's `airframe_view` marker, so the aero strip / α strip /
	# nose-vs-velocity drawing all carry over. Like slice 20 (the other KNOB-only slice) the scenario
	# ships an `:airframe` fidelity, so the shared button is the airframe cycler — established
	# precedent, NOT a new deviation: slice 22 has NO fidelity of its own to cycle (Decision 1).
	if not bool(f.get("airframe_view", false)):
		return "a slice-22 handshake must ship airframe_view=true (the airframe view discriminator)"
	var fid: Dictionary = f.get("fidelity", {})
	# THE CROSS-FIDELITY DEPENDENCY, ASSERTED (slice 19's, restated — never implied). `_stall_on`
	# carries `:pitch_coupled` as a THIRD CONJUNCT, deliberately: `pitch_moment` is ALSO live on the
	# :point_mass rotational path, so without it a :point_mass wire would integrate θ/q through a
	# BREAKING moment while pos/vel flew a linear-aero fiat accel — half the missile in one
	# aerodynamic model and half in another (slice 21's `_atm_on` latent bug exactly).
	if str(fid.get("airframe", "")) != "pitch_coupled":
		return "a slice-22 scenario must AUTHOR :airframe at pitch_coupled — the whole stall curve is INERT without it (a point-mass plant makes its accel by fiat on a LINEAR aero model and has no lift curve to bend), got %s" % str(fid.get("airframe", "<absent>"))
	if str(fid.get("autopilot", "")) != "alpha":
		return "a slice-22 scenario must AUTHOR the autopilot at :alpha (the inner α/g loop is what commands INTO the stall), got %s" % str(fid.get("autopilot", "<absent>"))
	if str(fid.get("guidance", "")) != "pn":
		return "a slice-22 scenario must hold :guidance at :pn (convention 9 — the curve is the only variable), got %s" % str(fid.get("guidance", "<absent>"))
	# ⚠ NO `:aero_curve` FIDELITY EXISTS, AND ITS ABSENCE IS ASSERTED ON PURPOSE (gate-0 F7 /
	# Decision 1). The plan asserted linear was `α_stall → ∞`, a LIMIT POINT ⇒ RUNG, and told gate 0
	# to VERIFY it. The verification FAILED: the achieved α self-limits to ~0.24 over every reachable
	# state, so a FINITE α_stall ≥ 0.25 is linear-in-effect and the off-state IS knob-reachable.
	# `test_aero_curve.jl` asserts the absence too, so adding one later breaks a test ON PURPOSE.
	if fid.has("aero_curve"):
		return "slice 22 must NOT ship an :aero_curve fidelity — gate-0 F7 MEASURED the off-state at a finite in-domain α_stall (0.25 gives the linear miss to the printed digit), so slice 21's own knob-vs-rung discriminator returns KNOB. A rung here would be a DELIBERATE DEVIATION and could not cite the discriminator in support"
	if f.has("range_axis_m") or f.has("pri_axis_us"):
		return "a slice-22 scenario must NOT ship range_axis_m / pri_axis_us (that flips the client to cfar/esm)"
	if f.has("terrain_grid"):
		return "a slice-22 scenario must NOT ship terrain_grid (that flips the client to the slice-18 3-D view)"
	# Decide WHICH HALF from the declared knob — the two halves need incompatible wires (gate-2 G2/G9).
	var keys := {}
	for k in f.get("knobs", []):
		keys[str(k.get("key", ""))] = true
	if keys.has("af_alpha_stall") and keys.has("af_cma_post"):
		return "the two halves of slice 22 must NOT be merged into one scenario — they need INCOMPATIBLE wires (the lift half k_drop 0.7 / δ_max 0.4; the departure half k_drop 1.0 / δ_max 1.0, and at k_drop 0.7 the authority cliff is INVISIBLE — gate-2 G2). This is a MEASURED config conflict, not a convention-9 preference"
	if keys.has("af_alpha_stall"):
		_half = "lift"
	elif keys.has("af_cma_post"):
		_half = "departure"
	else:
		return "a slice-22 scenario must expose exactly one of the 'af_alpha_stall' (lift half) or 'af_cma_post' (departure half) sliders — THE lesson lever"
	# The confounded / disqualified levers must NOT be exposed, in EITHER half.
	if keys.has("speed"):
		return "slice-22 must NOT expose a 'speed' knob — comp[:speed] is consumed ONCE at load and read by NOTHING per-tick, so the slider would be DEAD (slice-19 gate-3 finding)"
	if keys.has("af_alpha_max"):
		return "slice-22 must NOT expose 'af_alpha_max' — it is the DENOMINATOR of the headline identity (ratio ≡ α_stall/α_max), so moving it moves the very ratio being pinned; and it is slice 19's causation lever telling slice 19's story (convention 9)"
	if keys.has("rho"):
		return "slice-22 must NOT expose 'rho' — it scales Q, which the identity shows CANCELS: it cannot move the ceiling RATIO at all, which is the precise point of this slice (and it is slice 19's lever)"
	if keys.has("af_k_induced"):
		return "slice-22 must NOT expose 'af_k_induced' — slice 20's spiral would confound the isolation (K = 0 AND cd_area = 0 is what keeps the stall the only thing bending this trajectory)"
	if keys.has("af_k_sep"):
		return "slice-22 must NOT expose 'af_k_sep' — it is measured NEARLY INERT (0.9%% over its whole range, gate-2 G5). A slider that does nothing visible would teach that separation drag does not matter, which is false and is the OPPOSITE of why the term is mandatory"
	# Per-half knob-domain checks. BOTH domains are MEASURED, and both floors/ceilings are binding.
	for k in f.get("knobs", []):
		var kk := str(k.get("key", ""))
		if kk == "af_alpha_stall":
			# The FLOOR is the binding constraint: the miss PEAKS at α_stall ≈ 0.12 and FALLS below it
			# (at 0.10 it misses by LESS than at 0.12 — the missile stops being able to pull at all and
			# flies nearly ballistically), which would REVERSE the lesson. Third occurrence of that
			# pattern ([[ewsim-df-ellipse-sigma-monotonicity]], then slice-19's ρ).
			if float(k.get("min", 0.0)) < 0.15:
				return "af_alpha_stall must floor at or above the measured monotone bound (0.15; the miss TURNS at ≈0.12 and the lesson REVERSES below it), got %s" % str(k.get("min"))
			# The TOP must be α_max — that is what makes "the knob's own top IS the linear twin" true,
			# which is the entire knob-not-rung argument.
			if not is_equal_approx(float(k.get("max", 0.0)), ALPHA_MAX):
				return "af_alpha_stall's max must BE α_max (%.2f) — the knob's own top IS the in-scenario linear twin, which is the whole knob-not-rung claim (Decision 1). Got %s" % [ALPHA_MAX, str(k.get("max"))]
		if kk == "af_cma_post":
			if float(k.get("min", -1.0)) != 0.0:
				return "af_cma_post must floor at 0.0 — the NEUTRAL control arm (sentinel silent) is what makes the unstable arm's firing meaningful, got %s" % str(k.get("min"))
			# MEASURED at gate 3: defl_sat is EXACTLY 0 through cma_post 10 and is MONOTONE in it, so
			# the whole declared domain is provably clean; it first binds at 10.5 (65 frames). The
			# margin is ~1.03×, NOT slice-20's 2× — stated rather than hidden, and it cannot be widened
			# by raising δ_max, which is already an unphysical 1.0 rad (57°) precisely so the
			# deflection cap is provably not the story.
			if float(k.get("max", 1.0e9)) > 10.0:
				return "af_cma_post must cap at 10.0 — MEASURED: defl_sat is exactly 0 through 10 and monotone, but binds (65 frames) at 10.5, which would CONTAMINATE the verdict with slice-15's deflection cap (slice-19 FINDING 2 / gate-2 G3/G9). Got %s" % str(k.get("max"))
	return ""

func _set_param_cmd(target: String, key: String, value: float) -> Dictionary:
	return {"type": "set_param", "target": target, "key": key, "value": value}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pass_lift() -> bool:
	print("S22V OK (HALF A — THE LIFT CEILING): **the ceiling the AIRFRAME sets.** Slices 19/20/21 gave " +
		"cap #4 three movers and all three moved Q — the engineer's ρ knob, the missile's own turn via V, " +
		"and where it flies via ρ(z). Slice 22 moves the OTHER factor: they all assumed the lift curve is " +
		"a STRAIGHT LINE out to α_max. It is not. Past α_stall the flow SEPARATES, C_L PEAKS AND FALLS, " +
		"and the ceiling is the curve's own INTERIOR PEAK — no amount of Q buys past it. ⭐ THE HEADLINE " +
		"IS EXACT: at fixed Q the linear→stall ceiling ratio is IDENTICALLY α_stall/α_max, because Q, S, " +
		"C_Lα and m ALL CANCEL — 471.44 → 269.39 = 4/7, with |Δ| = 0.0 in the core tests and the ratio " +
		"reproduced here on the wire at the pre-stall frame where both arms are still in the same state. " +
		"⭐ THE REVERSAL IS NEW IN THE SUITE: every prior cap is a MAGNITUDE that SATURATES (pull harder, " +
		"get no more); this one is a DERIVATIVE THAT CHANGES SIGN — past the peak, pulling HARDER turns " +
		"you LESS *and* costs you MORE, which is why the user chose the true-drop curve over a saturating " +
		"one. The autopilot keeps inverting on the LINEAR C_Lα (an autopilot carries an internal linear " +
		"model of its airframe), so it OVER-commands α as the real curve goes concave — slice-19's " +
		"command-vs-achieved gap MADE PHYSICAL. ⚠ ALL COUNTS BELOW ARE FRAME-SAMPLED (emit_every = 16) " +
		"— what THIS file measured; the per-tick truth belongs to test_missile.jl, which sees every " +
		"tick. On the wire the missile misses by 241.06 m against the linear twin's 125.33 m (1.92×; " +
		"per-tick 240.90 / 125.14 — a MISS samples faithfully), flying past its own lift peak for " +
		"56/215 frames = 26.0% of the gated approach (per-tick 894/3253 = 27.5%). ⭐⭐ AND THE " +
		"DISCRIMINATOR IS `post_stall`, NOT `aero_sat`: aero_sat fires 53/215 = 24.7% on the PARKED, " +
		"LINEAR arm TOO — bit-for-bit the same count as the stall arm, because it keys off the α_max " +
		"CLAMP that both arms share (per-tick 26.3% in both) — so there is a real regime past the " +
		"physics ceiling with the command not yet pegged where it stays 0. post_stall separates the " +
		"arms EXACTLY 0-vs-56 frames (per-tick 0-vs-894), which is why it exists and why the client's " +
		"breach indicator keys on it. " +
		"KNOB, NOT RUNG, and that was MEASURED not argued: the plan asserted linear was α_stall → ∞ (a " +
		"limit point ⇒ rung) and gate 0 REFUTED it — the achieved α self-limits to ~0.24 over every " +
		"reachable state, so parking the corner at α_max recovers the linear miss to the printed digit " +
		"and the knob's own top IS the twin. The isolation holds: defl_sat == 0 in every arm (the 4th " +
		"cap provably not standing in for the lesson), a_max inert, K = 0 and cd_area = 0. Class 4c — " +
		"physics-changing, RNG-free, live-settable — and INERT without :pitch_coupled.")
	_teardown()
	quit(0)
	return true

func _pass_departure() -> bool:
	print("S22V OK (HALF B — RELAXED STATIC STABILITY): **a statically unstable airframe is perfectly " +
		"flyable — until the autopilot runs out of authority. THE THRESHOLD IS THE LESSON, NOT THE " +
		"TUMBLE.** ⭐ AND THE LESSON IS THE MIDDLE OF THREE POINTS, WHICH IS WHY ALL THREE ARE ASSERTED: " +
		"at cma_post 0 the airframe is NEUTRALLY stable past the break — not unstable at all — and the " +
		"ω_sp sentinel is EXACTLY SILENT (0 frames) and α at 500 m is 0.3092 with a 280.58 m miss; that " +
		"is the CONTROL. ⚠ ALL NUMBERS HERE ARE FRAME-SAMPLED (emit_every = 16) — the per-tick truth " +
		"belongs to test_missile.jl. At cma_post 4 the sentinel FIRES for 60 frames (per-tick 947 ticks — " +
		"nearly a second with NO REAL SHORT-PERIOD MODE, so the airframe is genuinely statically " +
		"unstable) and THE AUTOPILOT HOLDS IT ANYWAY: α at 500 m reaches only 0.4340 rad (24.9°) and the " +
		"miss is 302.36 m — 1.078× the neutral baseline, within 8%. THAT is 'unstable yet flyable', and a " +
		"two-point 0-vs-8 check would have demonstrated only 'neutral vs lost' — a weaker and different " +
		"claim. Only at cma_post 8 does the SAME autopilot, SAME fin, SAME gains lose it: α at 500 m " +
		"reaches 1.0081 rad (57.8°) and the miss opens to 371.93 m. ⭐ SLICE 16's ω_sp SENTINEL FIRES IN " +
		"FLIGHT FOR THE FIRST TIME IN PROJECT " +
		"HISTORY — built for an AUTHORED Cmα ≥ 0 and never fired mid-run until now; past the break the " +
		"LOCAL slope is positive, so it fires DYNAMICALLY, and it reaches the wire as FINITE_CEIL, never " +
		"a NaN (convention 6). ⭐ SLICE 16's TUMBLE, NOW SELF-INFLICTED: slice 16 taught static stability " +
		"with af_cma as an AUTHORED value — an engineer typed the unstable case. Here the airframe DRIVES " +
		"ITSELF INTO THAT REGIME BY FLYING THERE. ⚠ THE MISS IS NOT THE METRIC (even at full tumble it " +
		"moves +1.4% — a missile that departs 0.7 s before CPA keeps its momentum) and it is used only to " +
		"corroborate the direction; ⚠ nor is 'time with ω_sp ceiled' a severity measure — it RUNS " +
		"BACKWARDS — measured on THIS wire, 60 frames at cma_post 4 vs 33 at cma_post 8 (per-tick 947 → " +
		"526 → 442), because α blows past α_sat into the deep-stall RESTORING region where ω_sp is real " +
		"again — so it is asserted as a BOOLEAN only. α is sampled at a FIXED RANGE (500 m), " +
		"well past the break at 1475 m and well above the r→0 artifact, because α_pk lands on the CPA " +
		"frame. The isolation is total: defl_sat == 0 over the WHOLE band in every arm — δ_max is an " +
		"unphysical 1.0 rad SPECIFICALLY so the deflection cap is provably not the story, since at 0.4 it " +
		"AMPLIFIES the divergence (α_pk 1.22 → 3.02) and part of gate 0's dramatic 2.7779 was that " +
		"contamination, which is why it is never quoted. Class 4c — physics-changing, RNG-free, " +
		"live-settable — and INERT without :pitch_coupled.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String, code := 1) -> bool:
	push_error("S22V FAIL: " + msg)
	print("S22V FAIL: ", msg)
	_teardown()
	quit(code)
	return true

func _teardown() -> void:
	# `close()` + `free()` — the slice8..21_verify contract.
	if _client != null:
		_client.close()
		_client.free()
		_client = null
