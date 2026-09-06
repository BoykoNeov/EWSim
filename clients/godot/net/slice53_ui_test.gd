extends SceneTree
# Headless UI test for the slice-53 TAIL-LOBE view routing + HUD — the piece slice53_verify.gd
# cannot reach. The verifier drives SimClient directly (the wire + the physics); the Sandbox.tscn
# smoke-load proves the scene loads. Neither exercises the CLIENT routing, the dispatch, or the HUD
# this slice adds, and ⚠ ANYTHING THE HUD COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF AT ALL
# (convention 14) — which is why every line of this slice's HUD is a pure helper this file calls.
#
# ⭐⭐⭐ THE ONE THING THIS FILE EXISTS FOR ABOVE ALL OTHERS: **TWO MARKERS ARE UP AT ONCE.** A
# slice-53 wire authors an `:rcs_fineness` beside its tail gain, so `aspect_view` raises alongside
# `tail_view` — and slice 49's block draws into the SAME right-anchored 390 px column with a gauge
# (the longest loss run WHILE CLOSING) that belongs to a different slice. Two collisions follow, and
# they live in two different places:
#   (a) THE DRAW DISPATCH, which used to be an `if` inside `_draw` — where convention 14 says there
#       is no headless proof of which chain wins (slice 50 paid for that). It is now
#       `_spatial_hud_kind()`, a pure function, and this file asserts it in all three states.
#   (b) ⚠⚠ SLICE 49's GAUGE ACCUMULATOR, which is NOT in `_draw` at all — it is in the frame
#       handler, gated on `_aspect_view` + an observer + `target_range_m`, all three of which this
#       wire has. It would run all pass, silently, ready to be printed under this slice's label.
#       Asserted here with its own paired control, because a windowed shot cannot see it either.
#
# ⭐⭐ AND THE SECOND REASON: **THE VOCABULARY IS A RETRACTION.** `slice50_ui_test.gd` tooth 9b
# asserts `_s50_word(d) == _s50_word(180 − d)` as an IDENTITY, correct because `rcs_aspect` was
# fore/aft symmetric by construction. On a wire that authors a tail gain it no longer is. That tooth
# is not replaced — slice 50's wire authors no gain, so it stands there with one clause naming the
# condition it was always relying on — and this file ships the MIRROR: the word at θ and at 180 − θ
# must DIFFER where the lobe bites, and must still AGREE at broadside, where the kernel's lobe
# weight is exactly zero at every `G`. A vocabulary is a gauge and is scored like one (slice 50).
#
# THE TEETH, in order of what would actually break:
#   1. a slice-53 handshake stays in _mode=spatial and records the marker AND THE PAIR
#   2. ⭐⭐⭐ THE DISPATCH: both markers up → "tail"; aspect only → "aspect"; neither → ""
#   3. ⭐⭐⭐ SLICE 49's GAUGE MUST NOT RUN on this wire — with its own paired control
#   4. ⭐⭐ THE BUTTON STAYS SLICE 49's, and the mirror: strip both markers and multipath comes back
#   5. ⭐⭐⭐ THE PAIR IS NOT SYMMETRIC — the keys are the OBSERVER's, the prose names the TARGET
#   6. ⭐⭐⭐ PRESENCE DECIDES on `track_asym_m`: 0.0 is the LESSON'S NULL, absence is "not finished"
#   7. ⭐⭐⭐ THE VOCABULARY — the mirror of slice 50's tooth 9b, both halves
#   8. ⚠⚠ THE RULE TRAVELS WITH THE METRES — §2.14's binding constraint, asserted as a string
#   9. ⚠ THE LOOK INDEX IS ON THE EDGE LINES — a flat stretch must not read as a dead knob
#  10. ⭐⭐ THE DIRTY STATE prints NO metres — slice 50's "Reset to measure", through the wire
#  11. ⚠ `rcs_loss_db` is CONDITIONAL, never an identity — a negative reads "ABOVE broadside"
#  12. ⚠⚠ WIDTHS: **390 px, not the family's 430** — this view has altitude labels up the right edge
#  13. every key `_draw_tail_hud_lines` reads is present and scalar, and no default is a LIE
#  14. ONE slider → set_param on the TARGET's `rcs_tail_gain`
#  15. ⭐ THE MIRROR THE OTHER WAY: slice 49's own wire raises no tail marker and keeps its block
#  16. ⭐⭐ THE DOWNRANGE FLOOR — a crossing pass needs one, and it is exactly 0.0 everywhere else
#
# Run:  godot --headless --path clients/godot --script res://net/slice53_ui_test.gd
# Exit codes: 0 = pass, 1 = assertion failed.
#
# ⚠ `%.Nf` / `%d` / `%s` ONLY — GDScript's `%` supports a SMALL set of specifiers and an unknown one
# makes the WHOLE format fail SILENTLY, printing the format string itself ON A GREEN RUN (slice 21's
# bug, reproduced verbatim by slice 25). Do not "tidy" this.

const SandboxScript := preload("res://scenes/Sandbox.gd")

const RAD := "radar1"
const TID := "tgt1"

# ⚠ THE BUDGET IS 390 px AND NOT THE FAMILY'S 430, AND THE REASON IS THIS VIEW AND NOT THIS SLICE.
# The SPATIAL view puts its ALTITUDE TICK LABELS up the right edge (`_draw_spatial_backdrop`:
# `vp.x − 34`, with "alt (km)" at `vp.x − 52`), so a line drawn from `vp.x − 430` that uses all 430
# runs straight through them — at EVERY window size, because both origins are anchored to the right
# edge. Inherited from slice 49's block, which measured it.
const HUD_ORIGIN := 430.0
const LABEL_GUTTER := 40.0
const HUD_ROOM := HUD_ORIGIN - LABEL_GUTTER      # 390

# THE WIRE's OWN NUMBERS (core-pinned in `core/test/test_track.jl`, seed 250, revisit 0.1, N* = 3).
const GAIN_M := 6243.9596
const GAIN_LOOK := 375
const LOSS20_M := 9760.4272
const LOSS20_LOOK := 781
const ASYM20_M := 3516.4676
const ASYM1_M := 583.1127                        # ⚠ the NULL, and it is NOISE rather than zero

class MockClient extends RefCounted:
	var sent: Array = []
	func send(d: Dictionary) -> void:
		sent.append(d)

var _sb
var _sb_asp
var _sb_none
var _sb49

# The fixture reproduces the wire's own shape: the four ASPECT keys ride the target's shape and the
# eleven TRACK keys ride the radar's give-up rule, so on this wire both families ship every frame.
func _tail_tel(deg: float, sigma: float, loss_db: float, range_m: float, det: bool, pd: float,
			   look: int, closing: bool, alive: bool, misses: int,
			   gain_m: float, gain_look: int, loss_m: float, loss_look: int,
			   asym, dirty := false) -> Dictionary:
	var d := {
		RAD + ".snr_db": 21.4 if det else -4.2,
		RAD + ".pd": pd,
		RAD + ".detected": det,
		RAD + ".visible": true,
		RAD + ".target_aspect_deg": deg,
		RAD + ".rcs_eff_m2": sigma,
		RAD + ".rcs_loss_db": loss_db,
		RAD + ".target_range_m": range_m,
		RAD + ".track_drop_looks": 3.0,
		RAD + ".track_revisit_s": 0.1,
		RAD + ".track_alive": alive,
		RAD + ".track_closing": closing,
		RAD + ".track_misses": float(misses),
		RAD + ".track_look": float(look),
		RAD + ".track_gain_range_m": gain_m,
		RAD + ".track_gain_look": float(gain_look),
		RAD + ".track_loss_range_m": loss_m,
		RAD + ".track_loss_look": float(loss_look),
		RAD + ".track_pass_dirty": dirty,
	}
	# ⚠⚠ PRESENCE, NOT A SENTINEL. `track_asym_m` ships ONLY when both edges exist, because 0.0 is a
	# legitimate reading of this gauge. The fixture models that exactly — `null` means ABSENT.
	if asym != null:
		d[RAD + ".track_asym_m"] = float(asym)
	return d

func _handshake(tail: bool, aspect: bool) -> Dictionary:
	var h := {
		"name": "slice53_taillobe",
		"knobs": [
			{"target": TID, "key": "rcs_tail_gain", "min": 1.0, "max": 50.0, "value": 20.0,
			 "label": "TAIL BRIGHTNESS G (× the nose) — 1 = fore/aft symmetric, the null you drag back to"},
		],
		"fidelity": {"propagation": "free_space", "detection": "analytic"},
		"dt_physics": 1.0e-3,
	}
	# ⚠ BOTH, because that is what the core actually ships on this wire — the target carries an
	# `:rcs_fineness`, so `_aspect_view_info` raises on it exactly as it does on slice 49's.
	if aspect:
		h["aspect_view"] = true
		h["aspect_target"] = TID
		h["aspect_observer"] = RAD
	if tail:
		h["tail_view"] = true
		h["tail_target"] = TID
		h["tail_observer"] = RAD
	return h

func _st(x: float, t: float) -> Dictionary:
	return {"t": t, "entities": [
		{"id": RAD, "kind": "radar", "pos": [0.0, 0.0, 30.0]},
		{"id": TID, "kind": "target", "pos": [x, 0.0, 5000.0]},
	]}

func _feed(sb, t: float, range_m: float, det: bool, deg := 40.0) -> void:
	# One frame through the REAL client path, so anything that accumulates is exercised where it
	# actually lives — which for slice 49's gauge is the FRAME HANDLER and not `_draw`.
	sb._telemetry = _tail_tel(deg, 0.0004, 34.5, range_m, det, 0.02 if not det else 0.94,
			int(t * 10.0), true, det, 0, -1.0, -1, -1.0, -1, null)
	sb._spatial_on_state(_st(-15000.0 + t * 300.0, t))

func _initialize() -> void:
	print("S53UI_INIT godot=", Engine.get_version_info().string)
	var sb = _build_sandbox()
	_sb = sb
	var mock: MockClient = sb._client
	sb._on_scenario(_handshake(true, true))

	# ══ TOOTH 1 — ROUTE, AND THE PAIR ════════════════════════════════════════════════════════════
	if sb._mode != "spatial":
		return _fail("a slice-53 handshake must STAY in the spatial elevation view, got %s — this is a ground radar watching an aircraft fly past, and the marker deliberately does NOT pick a view" % sb._mode)
	if not sb._tail_view:
		return _fail("the client must record the `tail_view` handshake marker")
	if sb._tail_target != TID or sb._tail_observer != RAD:
		return _fail("⚠ the marker is the PAIR and it carries both: got target '%s' / observer '%s'. Half a pair is not a marker — every `track_*` line is keyed off the OBSERVER, so an empty one renders six defaulted numbers on a green run" % [sb._tail_target, sb._tail_observer])
	if not sb._aspect_view:
		return _fail("⚠ slice 49's marker must ALSO be recorded — this wire authors an `rcs_fineness`, so the core raises both, and pretending otherwise here would hide the collision this file exists to test")
	print("S53UI_ROUTE  spatial view kept; tail_view + aspect_view BOTH up, %s→%s pair recorded" % [sb._tail_target, sb._tail_observer])

	# ══ TOOTH 2 — ⭐⭐⭐ THE DISPATCH, IN ALL THREE STATES ═══════════════════════════════════════
	# ⚠⚠ CONVENTION 14's OWN BLIND SPOT, ANSWERED. This decision used to be an `if` inside `_draw`,
	# which never runs under `--headless` — so which chain won had no headless proof at all (slice
	# 50's finding). It now lives in `_spatial_hud_kind()`, one function read by BOTH `_draw` and
	# this file, which is convention 7 as well: one list, no drift.
	if sb._spatial_hud_kind() != "tail":
		return _fail("⭐⭐⭐ with BOTH markers up the TAIL block must win the 390 px column, got '%s'. Falling through to slice 49 would draw its gauge — the longest loss run WHILE CLOSING, a duration on the inbound leg — under this slice's headline, which is about the difference between the two ENDS of the pass" % sb._spatial_hud_kind())
	_sb_asp = _build_sandbox()
	_sb_asp._on_scenario(_handshake(false, true))
	if _sb_asp._spatial_hud_kind() != "aspect":
		return _fail("⭐⭐ …and with ONLY slice 49's marker the ASPECT block must still win, got '%s' — the new branch is checked FIRST, so a bug there steals slice 49's own lesson" % _sb_asp._spatial_hud_kind())
	_sb_none = _build_sandbox()
	_sb_none._on_scenario(_handshake(false, false))
	if _sb_none._spatial_hud_kind() != "":
		return _fail("⚠ with NEITHER marker the column must stay empty, got '%s' — every slice-1..48 spatial wire draws exactly what it drew before" % _sb_none._spatial_hud_kind())
	print("S53UI_DISPATCH both→'tail', aspect-only→'aspect', neither→'' — the decision is out of `_draw` and provable")

	# ══ TOOTH 3 — ⭐⭐⭐ SLICE 49's GAUGE MUST NOT RUN ON THIS WIRE ══════════════════════════════
	# ⚠⚠ THIS IS THE ONE A WINDOWED SHOT CANNOT SEE AND `_spatial_hud_kind` DOES NOT COVER. Slice
	# 49's longest-closing-loss accumulator lives in the FRAME HANDLER, gated on `_aspect_view` + an
	# observer + `target_range_m` — all three of which this wire has. It would run silently for the
	# whole pass, and the only thing standing between it and the screen would be that nothing
	# currently prints `_asp_loss_s`. That is not a guarantee; it is a coincidence one edit deep.
	var g = _build_sandbox()
	g._on_scenario(_handshake(true, true))
	_feed(g, 0.0, 15800.0, true, 18.0)
	for k in range(30):
		_feed(g, 1.0 + float(k), 15500.0 - 300.0 * float(k), false, 20.0 + float(k))
	if g._asp_loss_s != 0.0 or g._asp_loss_km != 0.0 or not is_nan(g._asp_run_t0):
		return _fail("⭐⭐⭐ slice 49's gauge accumulated %.3f s / %.3f km on a slice-53 wire — a DURATION from another slice, running all pass and one `draw_string` away from being printed under this slice's label. The gate is `and not _tail_view` at the accumulator's own site, which is NOT in `_draw`" % [g._asp_loss_s, g._asp_loss_km])
	# ⚠ THE PAIRED CONTROL, OR THIS PROVES NOTHING. The identical frames on an ASPECT-ONLY client
	# must accumulate — otherwise the tooth above would pass just as well if the accumulator were
	# broken outright, and slice 49's own proof would be the thing silently retired.
	var c = _build_sandbox()
	c._on_scenario(_handshake(false, true))
	_feed(c, 0.0, 15800.0, true, 18.0)
	for k in range(30):
		_feed(c, 1.0 + float(k), 15500.0 - 300.0 * float(k), false, 20.0 + float(k))
	if c._asp_loss_s <= 0.0:
		return _fail("⚠ the CONTROL must accumulate (%.3f s) — without it the tooth above passes on a broken accumulator, retiring slice 49's proof instead of scoping it" % c._asp_loss_s)
	print("S53UI_NOGAUGE slice 49's clock reads 0.000 s here and %.1f s on the identical frames without the tail marker" % c._asp_loss_s)
	g.free(); c.free()

	# ══ TOOTH 4 — ⭐⭐ THE BUTTON STAYS SLICE 49's, AND THE MIRROR ══════════════════════════════
	# ⚠ HUD ONLY. This marker takes the HUD and slice 49's gauge; it does NOT take the button,
	# because the drop slice 49 performs is the correct drop here for its own reason: the wire
	# authors `propagation: free_space`, so the fallback offers `free_space ↔ two_ray` — MULTIPATH
	# LOBING, a second way for a target to vanish, on a scenario about a third (convention 9).
	if sb._fid_kind != "aspect":
		return _fail("⭐⭐ the shared button must still be claimed by slice 49's branch (got _fid_kind '%s') — the tail marker is HUD-only and must not disturb it" % sb._fid_kind)
	if sb._prop_btn.visible:
		return _fail("⭐⭐ the shared button must be HIDDEN: what it would offer is `free_space ↔ two_ray` on a wire whose lesson is which END the target is showing")
	sb._update_fid_btn()
	if sb._prop_btn.visible or str(sb._prop_btn.text).begins_with("prop:"):
		return _fail("⚠ `_update_fid_btn` re-showed or re-labelled the dropped button ('%s') — it runs again on every reset" % sb._prop_btn.text)
	if _sb_none._fid_kind != "propagation" or not _sb_none._prop_btn.visible:
		return _fail("⭐⭐ THE HOLE: with NEITHER marker this wire must fall to the PROPAGATION cycler with the button visible — that fallback is the failure being prevented, and it must be reproduced here or the mirror proves nothing. Got '%s' / visible=%s" % [_sb_none._fid_kind, _sb_none._prop_btn.visible])
	print("S53UI_BUTTON the free_space↔two_ray toggle stays dropped by slice 49's branch; strip both markers and it comes back")

	# ══ TOOTH 5 — ⭐⭐⭐ THE PAIR IS NOT SYMMETRIC ════════════════════════════════════════════════
	# The telemetry is keyed on the **RADAR** while the prose names the **TARGET**. Read the keys off
	# the target by mistake and every `.get(k, default)` fires — and on THIS HUD the defaults would
	# print "GOT IT coming in 0.00 km @ look #0" beside "no reading yet", i.e. a fabricated edge and
	# a denial of the gauge on the same frame.
	if sb._tail_key("track_asym_m") != RAD + ".track_asym_m":
		return _fail("⭐⭐⭐ the HUD must form its keys off the OBSERVER (got '%s') — the wire is keyed on the radar, not on the target the prose names" % sb._tail_key("track_asym_m"))
	sb._telemetry = {}
	if absf(sb._tail_deg() - 90.0) > 1.0e-9:
		return _fail("⭐⭐ with no key on the wire the aspect must default to BROADSIDE (90°), got %.3f — a defaulted 0.0 asserts NOSE-ON and a defaulted 180.0 asserts TAIL-ON, and this slice's whole lesson is the difference between those two" % sb._tail_deg())
	var pair_line: String = sb._tail_aspect_text(sb._tail_target, sb._tail_observer, 156.0)
	if not (pair_line.contains(TID) and pair_line.contains(RAD)):
		return _fail("⭐ the aspect line must NAME THE PAIR — the same aircraft is nose-on to one radar and tail-on to another in the same tick. Got '%s'" % pair_line)
	print("S53UI_PAIR   keys off '%s', prose names both: '%s'" % [sb._tail_observer, pair_line])

	# ══ TOOTH 6 — ⭐⭐⭐ PRESENCE DECIDES, AND 0.0 IS THE LESSON'S OWN NULL ═══════════════════════
	# ⚠⚠ THE SHARPEST CASE OF THIS CLASS IN THE CLIENT. `track_asym_m` = 0.0 is what a fore/aft
	# SYMMETRIC target reads — it is the arm the entire slice is proved against — and `.get(k, 0.0)`
	# on an instrument that has not finished reads exactly the same. No value assertion can separate
	# them, so the block tracks PRESENCE and the two states get two sentences (slice 50's rule).
	var unfinished: String = sb._tail_gauge_text(false, false, 0.0, 0.1, 3)
	var null_arm: String = sb._tail_gauge_text(false, true, 0.0, 0.1, 3)
	if unfinished == null_arm:
		return _fail("⭐⭐⭐ an unfinished instrument and a measured 0.0 m must not read the same — both gave '%s'. 0.0 is what a symmetric target GIVES, so a defaulted zero would print the lesson's own result over a pass that has not produced one" % unfinished)
	if unfinished.contains("km"):
		return _fail("⭐⭐ the unfinished state must print NO METRES at all — got '%s'" % unfinished)
	if not null_arm.contains("0.00 km"):
		return _fail("⭐ …and the measured null must print its number, not a sentence about roundness — got '%s'" % null_arm)
	# ⚠ AND THE NULL IS NOISE RATHER THAN ZERO ON A REAL SEED (+583 m here; −658 … +968 m over the 8
	# gate-0 seeds), so the sign must survive to the screen in BOTH directions. A magnitude-only
	# format would turn a target whose tail is DIMMER than its nose into one whose tail is brighter.
	var neg: String = sb._tail_gauge_text(false, true, -403.6, 0.1, 3)
	if not (neg.contains("SHORTER") or neg.contains("-0.40")):
		return _fail("⚠ a NEGATIVE asymmetry (a tail DIMMER than the nose, legal at G < 1 and measured at −404 m) must not read as 'further out' — got '%s'" % neg)
	var pos: String = sb._tail_gauge_text(false, true, ASYM1_M, 0.1, 3)
	if not pos.contains("+0.58"):
		return _fail("⚠ the null's measured +583 m must print with its sign — got '%s'" % pos)
	print("S53UI_PRESENCE unfinished='%s' | measured null='%s' — the same 0.0, two sentences" % [unfinished, null_arm])

	# ══ TOOTH 7 — ⭐⭐⭐ THE VOCABULARY: THE MIRROR OF SLICE 50's TOOTH 9b ════════════════════════
	# ⚠⚠ THAT TOOTH IS NOT REPLACED. `slice50_defensive.yaml` authors no `rcs_tail_gain`, so on that
	# wire the model still genuinely cannot tell nose from tail and `_s50_word(d) == _s50_word(180−d)`
	# stands as an identity — with one clause added there naming the condition it was always relying
	# on. THIS is the vocabulary for the wire where the condition fails, and it is scored as a gauge:
	# resolution over the domain it describes, and no word claiming something the frame does not have.
	#
	# HALF ONE — WHERE THE LOBE BITES, THE MIRROR MUST DIFFER. That is the retraction, stated as an
	# assertion rather than as prose.
	for d in [10.0, 24.0, 45.0, 60.0]:
		if sb._tail_word(d) == sb._tail_word(180.0 - d):
			return _fail("⭐⭐⭐ at %.0f° the target is showing its NOSE and at %.0f° its TAIL, and on this wire those are different cross-sections — both read '%s'. Slice 49's and 50's words could not tell them apart because the model could not; here it can" % [d, 180.0 - d, sb._tail_word(d)])
	# HALF TWO — ⚠⚠ AND AT BROADSIDE IT MUST **AGREE**, WHICH IS THE HALF THAT IS EASY TO MISS. The
	# kernel's lobe weight is `max(0, −cos θ)²`, exactly ZERO at θ = 90° at every `G`, so 89° and 91°
	# really are the same brightness. A word that differed there would claim an asymmetry the model
	# does not have — the same over-claim as the one above, pointing the other way.
	for d in [89.0, 85.0, 71.0]:
		if sb._tail_word(d) != sb._tail_word(180.0 - d):
			return _fail("⚠⚠ at %.0f° the lobe weight is ~0 at every G and the two ends really are alike, but the words differ ('%s' vs '%s') — that claims an asymmetry the kernel does not have" % [d, sb._tail_word(d), sb._tail_word(180.0 - d)])
	# ⚠ …AND NO WORD MAY NAME AN END THE FRAME IS NOT SHOWING. "tail" forward of broadside is the
	# lie in one direction; "nose" behind it is the lie in the other.
	for d in [0.0, 10.0, 24.0, 45.0, 60.0, 89.0]:
		if sb._tail_word(d).contains("tail"):
			return _fail("⚠ %.0f° is forward of broadside and the word says 'tail': '%s'" % [d, sb._tail_word(d)])
	for d in [91.0, 120.0, 135.0, 156.0, 180.0]:
		if sb._tail_word(d).contains("nose"):
			return _fail("⚠ %.0f° is behind broadside and the word says 'nose': '%s'" % [d, sb._tail_word(d)])
	# ⚠ RESOLUTION OVER THE PASS, which is the domain this vocabulary describes — the aspect sweeps
	# 18° → 167° over the fly-past while the slider moves no angle at all. A word constant across
	# that sweep is the objection that disqualified `min R_acq/r` as a gauge, one instrument over.
	var words := {}
	for d in [18.0, 40.0, 52.7, 90.0, 120.0, 149.7, 166.7]:
		words[sb._tail_word(d)] = true
	if words.size() < 4:
		return _fail("⚠ the vocabulary resolves into only %d words over the pass's own 18°→167° sweep — a word that barely changes is a gauge with no resolution over the domain it describes" % words.size())
	print("S53UI_WORD   18°='%s' → 52.7°='%s' → 90°='%s' → 149.7°='%s' → 166.7°='%s' — the mirror DIFFERS where the lobe bites and AGREES at broadside" % [
			sb._tail_word(18.0), sb._tail_word(52.7), sb._tail_word(90.0), sb._tail_word(149.7), sb._tail_word(166.7)])

	# ══ TOOTH 8 — ⚠⚠ THE RULE TRAVELS WITH THE METRES ═══════════════════════════════════════════
	# Gate 0 §2.14's binding constraint on this whole block: the metres are a JOINT property of the
	# tail lobe and the TRACKER — at a halved revisit with a matched give-up TIME the same physics
	# reads +2191 m more at `G` = 20 — so a figure quoted without `revisit_s` and `N`* is not a
	# measurement. The core ships both keys beside the metres so no client CAN print one without the
	# other; this is where that promise is kept, and it is asserted on the STRING.
	var gauge20: String = sb._tail_gauge_text(false, true, ASYM20_M, 0.1, 3)
	if not gauge20.contains("3.52 km"):
		return _fail("the gauge line must print the measured +3516 m as km — got '%s'" % gauge20)
	if not (gauge20.contains("0.10") and gauge20.contains("3")):
		return _fail("⚠⚠ the metres must be quoted WITH the rule that produced them (revisit 0.10 s, give up at 3) — got '%s'. §2.14 measured +2191 m of movement from retuning the tracker alone, so a bare figure is not a measurement" % gauge20)
	var rule: String = sb._tail_rule_text(0.1, 3)
	if not (rule.contains("look") and rule.contains("0.10") and rule.contains("3")):
		return _fail("⚠ the rule line must say a look every 0.10 s and a give-up at 3 MISSED LOOKS — got '%s'. 'Looks' is load-bearing: the same 3 is 0.3 s of blindness at this revisit and 0.15 s at half of it" % rule)
	print("S53UI_RULE   '%s' — and the gauge line carries it too: '%s'" % [rule, gauge20])

	# ══ TOOTH 9 — ⚠ THE LOOK INDEX IS ON BOTH EDGE LINES ════════════════════════════════════════
	# Gate 0 §2.9 measured DEAD ZONES in this slider: on the shipped seed `G` = 2, 5 and 10 all read
	# the same +878 m at the same look #671. Without the index a student dragging across that stretch
	# cannot tell "the edge has not moved" from "nothing is being read" — a flat stretch reading as a
	# dead knob is precisely what this block was told to prevent.
	var gline: String = sb._tail_gain_edge_text(true, GAIN_M, GAIN_LOOK)
	var lline: String = sb._tail_loss_edge_text(true, LOSS20_M, LOSS20_LOOK, false, 3, 0.0, 800)
	# ⚠ AND THE LIVE BRANCH CARRIES THE MISS COUNT, which is this wire's blindness readout — the
	# give-up rule is `n_drop` CONSECUTIVE misses, so "2 missed" at `N`* = 3 is one look from losing
	# the track, and no single frame's detection verdict says that.
	if not (gline.contains("#%d" % GAIN_LOOK) and gline.contains("6.24")):
		return _fail("⚠ the inbound edge must carry its LOOK index and its range — got '%s'" % gline)
	if not (lline.contains("#%d" % LOSS20_LOOK) and lline.contains("9.76")):
		return _fail("⚠ the outbound edge must carry its LOOK index and its range — got '%s'" % lline)
	# ⚠ AND THE NOT-YET STATES MUST NOT PRINT A SENTINEL AS A MEASUREMENT. `-1.0` is "not yet" on the
	# wire (the `search_t_lock_s` posture, unambiguous because a range is strictly positive), and a
	# line reading "GOT IT coming in −0.00 km @ look #−1" is the sentinel wearing the result's words.
	var gnone: String = sb._tail_gain_edge_text(false, -1.0, -1)
	var lalive: String = sb._tail_loss_edge_text(false, -1.0, -1, true, 1, 8412.0, 712)
	for line in [gnone, lalive]:
		if str(line).contains("#-1") or str(line).contains("-0.00"):
			return _fail("⚠ a not-yet sentinel reached the screen as a number: '%s'" % line)
	if not lalive.contains("8.41"):
		return _fail("⚠ before the loss edge exists the line must show the LIVE range instead of going blank — got '%s'" % lalive)
	if not lalive.contains("1 missed"):
		return _fail("⚠ …and it must carry the live MISS COUNT — got '%s'. At N* = 3 a count of 2 is one look from losing the track, which the echo line's absent per-frame `SEEN` deliberately does not say" % lalive)
	print("S53UI_LOOKS  '%s' | '%s' — the index is what makes a flat stretch of the drag read as a state" % [gline, lline])

	# ══ TOOTH 10 — ⭐⭐ THE DIRTY STATE PRINTS NO METRES ════════════════════════════════════════
	# ⚠⚠ SLICE 50's "RESET TO MEASURE", REACHED THROUGH THE WIRE. `track_pass_dirty` is the core
	# saying a knob moved mid-pass: both edges were deleted at the next look and, past closest
	# approach, the inbound one can never be re-declared. The HUD must render that as a REFUSAL and
	# not as a number — an instrument may refuse to show a figure it can no longer stand behind; it
	# may never show one measured on a different configuration.
	var dirty_gauge: String = sb._tail_gauge_text(true, true, ASYM20_M, 0.1, 3)
	if dirty_gauge.contains("km") or dirty_gauge.contains("3.52"):
		return _fail("⭐⭐ a dirty pass must print NO METRES — got '%s'. Anything numeric here was measured under a setting that is no longer on the wire" % dirty_gauge)
	if not dirty_gauge.to_lower().contains("reset"):
		return _fail("⭐ …and it must say what to do about it — got '%s'" % dirty_gauge)
	var dirty_head: String = sb._tail_verdict_label(true, true, ASYM20_M, true, false)
	if dirty_head.contains("km") or not dirty_head.to_lower().contains("reset"):
		return _fail("⭐⭐ the HEADLINE must go to the reset state too, or the refused number is still the loudest thing on screen — got '%s'" % dirty_head)
	print("S53UI_DIRTY  head='%s' gauge='%s' — a pass that spans two settings reports neither" % [dirty_head, dirty_gauge])

	# ══ TOOTH 11 — ⚠ `rcs_loss_db` IS CONDITIONAL, NEVER AN IDENTITY ═══════════════════════════
	# Gate 1's own correction: `rcs_loss_db` is documented "positive = this much QUIETER than the
	# authored broadside", and a tail gain makes the rear hemisphere BRIGHTER than broadside wherever
	# `G` outruns `F⁴` — at `F` = 1, any `G` > 1. Nothing on THIS wire reaches it (F = 8 needs
	# G > 4096 and the slider stops at 50), but a HUD that hard-codes "below" is one authored
	# fineness away from printing a gain as a loss. The SIGN decides the word.
	var quiet: String = sb._tail_echo_text(0.00043, 34.5)
	var loud: String = sb._tail_echo_text(9.4, -3.7)
	if not quiet.contains("below"):
		return _fail("⚠ a positive `rcs_loss_db` is QUIETER than broadside and must read 'below' — got '%s'" % quiet)
	if loud.contains("below") or not loud.contains("ABOVE"):
		return _fail("⚠ a NEGATIVE `rcs_loss_db` is BRIGHTER than broadside and must not read 'below' — got '%s'. Writing the wording as an identity is what gate 1 flagged" % loud)
	if loud.contains("-3.7"):
		return _fail("⚠ …and the magnitude must be positive once the word carries the sign — got '%s'" % loud)
	# ⚠⚠ AND A TINY-BUT-REAL σ MUST NOT PRINT AS A ZERO — the slice-8 `de_frac` defect that slice
	# 49's windowed shot caught on this exact readout. Nose-on at F = 8 the echo is ~1e-6 m².
	for sg in [1.2e-6, 9.8e-7, 4.3e-4]:
		var line: String = sb._tail_echo_text(float(sg), 41.5)
		if line.contains("echo 0 ") or line.contains("0.00 m²"):
			return _fail("⚠⚠ a live σ of %.9f printed as a zero: '%s'" % [sg, line])
	# ⚠ AND THERE IS NO `Pd` OR `SEEN` ON THIS LINE, DELIBERATELY — slice 49 prints both because its
	# lesson IS the per-frame fade, while this one's rule is counted in LOOKS. `track_misses` on the
	# edge line is the live blindness readout here, and tooth 9 asserts it. This is the tooth that
	# would catch a well-meaning re-addition.
	for line in [quiet, loud]:
		if str(line).contains("Pd") or str(line).contains("SEEN"):
			return _fail("⚠ a per-frame detector verdict is back on the echo line ('%s') — beside a look-counted gauge it invites reading one as evidence about the other, which is §2.14's confusion in miniature" % line)
	print("S53UI_DB     '%s' | '%s' — the sign picks the word, and 1e-6 m² survives to the screen" % [quiet, loud])

	# ══ TOOTH 12 — ⚠⚠ THE WIDTH BUDGETS, IN PIXELS, AGAINST 390 AND NOT 430 ════════════════════
	var heads := [
		sb._tail_verdict_label(false, false, 0.0, false, true),
		sb._tail_verdict_label(false, false, 0.0, true, true),
		sb._tail_verdict_label(false, false, 0.0, true, false),
		sb._tail_verdict_label(false, true, ASYM20_M, true, false),
		sb._tail_verdict_label(false, true, -403.6, true, false),
		sb._tail_verdict_label(true, true, ASYM20_M, true, false),
	]
	var body := [
		sb._tail_aspect_text(TID, RAD, 18.0),
		sb._tail_aspect_text(TID, RAD, 149.7),
		# ⚠ TWO SEPARATE STRESSES, AND THEIR CROSS PRODUCT IS **NOT** ASSERTED — a stated limit
		# rather than a hidden one. `entity_id` length is unbounded in the YAML, so no format can be
		# proved to fit for every author; what IS proved is the longest word this vocabulary can
		# emit at the SHIPPED ids (below, ~295 px of 390), and slice 49's own long-id stress pair at
		# the shortest. The two together at once measures 404 px and would clip, and it is not a
		# combination any scenario in this repo can produce.
		sb._tail_aspect_text(TID, RAD, 120.0),
		sb._tail_aspect_text("interceptor1", "search_radar1", 156.0),
		quiet, loud,
		sb._tail_echo_text(1.2e-6, 41.48),
		gline, gnone, lline, lalive,
		sb._tail_loss_edge_text(false, -1.0, -1, false, 3, 12904.0, 964),
		gauge20, null_arm, unfinished, dirty_gauge, neg,
		sb._tail_gauge_text(false, true, 8113.9609, 0.1, 3),
		rule, sb._tail_rule_text(0.05, 6),
		sb._tail_cure_text(false, 0.0), sb._tail_cure_text(true, ASYM1_M),
		sb._tail_cure_text(true, ASYM20_M),
	]
	var fnt: Font = sb._font
	for line in body:
		var w: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		if w > HUD_ROOM:
			return _fail("⚠⚠ HUD BODY line is %.0f px at 15 px, over the %.0f px this view leaves — the origin `vp.x − %.0f` is anchored to the RIGHT edge and the ALTITUDE TICK LABELS sit at `vp.x − 34`, so it clips at every window size. '%s'" % [w, HUD_ROOM, HUD_ORIGIN, line])
	for line in heads:
		var wh: float = fnt.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		if wh > HUD_ROOM:
			return _fail("⚠⚠ HUD HEADLINE is %.0f px at 20 px, over %.0f — a SEPARATE and much tighter budget, because it is drawn LARGER from the same origin. '%s'" % [wh, HUD_ROOM, line])
	# ⚠ AND A MARGIN IS REQUIRED, NOT JUST A FIT (slice 49's first run passed at exactly 390.0 of 390
	# — one glyph from clipping, and a "pass" a font substitution would turn into slice 46's defect).
	var widest_body: float = _maxpx(fnt, body, 15)
	if widest_body > HUD_ROOM - 12.0:
		return _fail("⚠ the widest body line is %.1f px of %.0f — it FITS, but with under 12 px to spare, which is one glyph from clipping. '%s'" % [widest_body, HUD_ROOM, _widest(fnt, body, 15)])
	# ⚠ AND NONE MAY CONTAIN A LITERAL UNSUBSTITUTED SPECIFIER — the silent-format bug shows up as
	# the FORMAT STRING itself on screen, on a run that passes.
	for line in body + heads:
		if str(line).contains("%.") or str(line).contains("%d") or str(line).contains("%s"):
			return _fail("a formatted line still carries an unsubstituted specifier: '%s'" % line)
	print("S53UI_WIDTH  body ≤ %.1f px, headline ≤ %.1f px, against %.0f px of room (NOT 430 — the altitude labels own the rest)" % [
			_maxpx(fnt, body, 15), _maxpx(fnt, heads, 20), HUD_ROOM])
	print("S53UI_WIDEST body: '%s' (%.1f px)   headline: '%s' (%.1f px)" %
		  [_widest(fnt, body, 15), _maxpx(fnt, body, 15), _widest(fnt, heads, 20), _maxpx(fnt, heads, 20)])

	# ══ TOOTH 13 — every key the HUD reads is present and scalar ════════════════════════════════
	var need := [RAD + ".target_aspect_deg", RAD + ".rcs_eff_m2", RAD + ".rcs_loss_db",
				 RAD + ".target_range_m", RAD + ".track_drop_looks", RAD + ".track_revisit_s", RAD + ".track_alive",
				 RAD + ".track_closing", RAD + ".track_misses", RAD + ".track_look",
				 RAD + ".track_gain_range_m", RAD + ".track_gain_look",
				 RAD + ".track_loss_range_m", RAD + ".track_loss_look",
				 RAD + ".track_pass_dirty"]
	var tel := _tail_tel(149.7, 0.0021, 32.8, 9760.0, true, 0.61, 781, false, false, 3,
			GAIN_M, GAIN_LOOK, LOSS20_M, LOSS20_LOOK, ASYM20_M)
	for k in need:
		if not tel.has(k):
			return _fail("the HUD reads %s and the wire must carry it" % k)
		var ty := typeof(tel[k])
		if ty != TYPE_FLOAT and ty != TYPE_INT and ty != TYPE_BOOL:
			return _fail("%s must be a SCALAR on the wire (convention 6/13)" % k)
	# ⚠ AND `track_asym_m` IS **NOT** ON THAT LIST BY DESIGN — it is the one key whose ABSENCE is a
	# state, so a "must be present" tooth on it would assert the opposite of the rule above.
	if need.has(RAD + ".track_asym_m"):
		return _fail("⚠ `track_asym_m` must NOT be in the always-present list — its absence is the 'not finished' state, and 0.0 is the lesson's null")
	# …and the block reads it through PRESENCE, on the client's own accessor.
	sb._telemetry = _tail_tel(149.7, 0.0021, 32.8, 9760.0, true, 0.61, 781, false, false, 3,
			GAIN_M, GAIN_LOOK, LOSS20_M, LOSS20_LOOK, null)
	if sb._tail_has("track_asym_m"):
		return _fail("the presence accessor must report the key ABSENT when the core omits it")
	sb._telemetry = tel
	if not sb._tail_has("track_asym_m"):
		return _fail("…and PRESENT when it ships")
	if absf(sb._tail_f("track_asym_m", 0.0) - ASYM20_M) > 1.0e-6:
		return _fail("…and read the value it ships (%.4f)" % sb._tail_f("track_asym_m", 0.0))
	print("S53UI_KEYS   all %d HUD keys present and scalar; `track_asym_m` is read by PRESENCE and is not on the list" % need.size())

	# ══ TOOTH 14 — ONE slider → set_param on the TARGET ═════════════════════════════════════════
	# ⚠ THE TARGET IS `tgt1`, NOT THE RADAR. The lobe is the target's — and every telemetry key this
	# HUD reads is prefixed with the RADAR's id, so the two ids appear side by side all through this
	# slice and copying the wrong one is a live hazard rather than a theoretical one.
	var sliders := _find_all_sliders(sb._knob_box)
	if sliders.size() != 1:
		return _fail("exactly ONE slider (convention 9) — got %d" % sliders.size())
	mock.sent.clear()
	sliders[0].value = 50.0
	sliders[0].value_changed.emit(50.0)
	var saw_param := false
	for d in mock.sent:
		if str(d.get("type", "")) == "set_param" and str(d.get("key", "")) == "rcs_tail_gain":
			if str(d.get("target", "")) != TID:
				return _fail("⚠ the slider must address the TARGET (`%s`) — the lobe is the target's, while every telemetry key here is the RADAR's. Got '%s'" % [TID, str(d.get("target", ""))])
			saw_param = true
	if not saw_param:
		return _fail("dragging the slider must send set_param on the target's `rcs_tail_gain` — got %s" % str(mock.sent))
	# ⭐⭐ AND THIS BLOCK KEEPS **NO STATE**, SO THE DRAG NEEDS NO CLIENT-SIDE INVALIDATION — which is
	# the first time in this family that is true, and it is worth asserting rather than assuming.
	# Slices 46/47/48/49/50/52 all accumulate something and every one had to answer what a drag does
	# to it. Here the latch lives in the CORE and arrives as `track_pass_dirty`, because a gate-3
	# verifier reads the wire and would otherwise read a stale latch as a live measurement.
	if sb._tail_view and (sb.get("_tail_asym_peak") != null or sb.get("_tail_latched") != null):
		return _fail("⭐⭐ this block must accumulate NOTHING — the invalidation is the core's (`track_pass_dirty`), and a client-side twin is convention 7's exact failure: two instruments measuring one quantity, one of which goes stale")
	print("S53UI_WIRE   one slider → set_param(%s.rcs_tail_gain), and the block holds no state to invalidate" % TID)

	# ══ TOOTH 15 — ⭐ THE MIRROR THE OTHER WAY: slice 49's wire keeps its own block ═════════════
	_sb49 = _build_sandbox()
	_sb49._on_scenario({
		"name": "slice49_aspect",
		"knobs": [{"target": TID, "key": "rcs_fineness", "min": 1.0, "max": 12.0, "value": 8.0,
				   "label": "Target fineness L/r (1 = sphere)"}],
		"fidelity": {"propagation": "free_space", "detection": "analytic"},
		"dt_physics": 1.0e-3,
		"aspect_view": true, "aspect_target": TID, "aspect_observer": RAD,
	})
	if _sb49._tail_view or _sb49._tail_target != "" or _sb49._tail_observer != "":
		return _fail("⭐ slice 49's own wire must raise NO tail marker and name no pair — it authors no `rcs_tail_gain` and its radar keeps no track")
	if _sb49._spatial_hud_kind() != "aspect":
		return _fail("⭐ …and it must keep its OWN block (got '%s') — the new branch is checked first, so a bug there steals slice 49's lesson" % _sb49._spatial_hud_kind())
	print("S53UI_PRIOR  slice 49's wire raises no tail marker and keeps its aspect block — the new first-checked branch steals nothing")

	# ══ TOOTH 16 — ⭐⭐ THE DOWNRANGE **FLOOR**, AND THAT IT IS 0 EVERYWHERE ELSE ════════════════
	# ⚠ Every scenario 1–52 launches at the origin and flies OUTWARD, so the elevation view mapped
	# `x = 0` to the left margin and never needed a lower bound. A straight FLY-PAST does not work
	# that way: this target starts 15 km on the FAR side of the radar, so with a floor of 0 the whole
	# INBOUND leg — including the look the track is OPENED at, the half of the lesson the slider
	# provably cannot move — draws off the left edge. The windowed shot is what found it; nothing
	# else could have, because the mapping is only ever exercised inside `_draw`.
	if not (sb._x_min < -10000.0 and sb._x_max > 20000.0):
		return _fail("⭐⭐ a fly-past must seed BOTH ends of the downrange axis (got %.0f … %.0f m) — the target crosses the radar, so a floor of 0 puts the entire acquisition half of the pass off the left edge" % [sb._x_min, sb._x_max])
	# ⚠⚠ AND THE MIRROR IS THE WHOLE SAFETY ARGUMENT: at `_x_min` = 0.0 the mapping is the OLD
	# expression to the bit (`x − 0.0 === x`), so every other spatial wire renders exactly as before.
	# A floor that grew on any wire with a negative-downrange entity would be a silent re-framing of
	# scenarios this slice never touched (convention 2 — slices are ADDITIVE).
	for other in [_sb_asp, _sb_none, _sb49]:
		if other._x_min != 0.0:
			return _fail("⚠⚠ a wire without the tail marker must keep a downrange floor of exactly 0.0 (got %.4f) — at 0.0 the mapping reduces to the old one bit for bit, which is what makes this change additive" % other._x_min)
	print("S53UI_EXTENT the fly-past spans %.0f … %.0f m of downrange; every other wire keeps a floor of exactly 0.0" % [sb._x_min, sb._x_max])

	return _pass()

func _maxpx(fnt: Font, a: Array, sz: int) -> float:
	var m := 0.0
	for s in a:
		m = maxf(m, fnt.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	return m

func _widest(fnt: Font, a: Array, sz: int) -> String:
	var m := -1.0
	var best := ""
	for x in a:
		var w: float = fnt.get_string_size(str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if w > m:
			m = w
			best = str(x)
	return best

func _build_sandbox():
	var sb = SandboxScript.new()
	sb._client = MockClient.new()
	sb._build_ui()
	# ⚠ `_font` is set in `_ready`, which a mock never runs — so it is null here and the PIXEL width
	# tooth would CRASH on it rather than fail. Assign the SAME font `_draw` uses, from the same
	# source, or the tooth measures a different typeface than the one in the photograph.
	sb._font = ThemeDB.fallback_font
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
	print("S53UI OK: which way a target points does not only change how BRIGHT it is — it changes " +
		"it ASYMMETRICALLY, and the on-screen half has to say which END is showing, how far out " +
		"each edge of the pass was declared, and UNDER WHAT RULE. ⭐⭐⭐ THE MARKER TAKES THE HUD " +
		"AND SLICE 49's GAUGE BUT NOT ITS BUTTON: this wire raises BOTH markers, so the draw " +
		"dispatch had to move OUT of `_draw` (where convention 14 says nothing can prove which " +
		"chain wins) and slice 49's closing-loss accumulator — which is not in `_draw` at all — had " +
		"to be gated at its own site or it would run all pass. ⭐⭐ AND THE VOCABULARY IS A " +
		"RETRACTION: slice 50's tooth 9b asserts the word at θ equals the word at 180−θ, correct on " +
		"a wire with no tail gain and false on this one — so the mirror must DIFFER where the lobe " +
		"bites and still AGREE at broadside, where its weight is exactly zero at every G.")
	_teardown()
	quit(0)
	return true

func _fail(msg: String) -> bool:
	push_error("S53UI FAIL: " + msg)
	print("S53UI FAIL: " + msg)
	_teardown()
	quit(1)
	return true

func _teardown() -> void:
	for sb in [_sb, _sb_asp, _sb_none, _sb49]:
		if sb != null and is_instance_valid(sb):
			sb.free()
