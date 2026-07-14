extends Node2D
# BattleBoard.gd — the 2-D BATTLE / COORDINATOR overview screen (display-only).
#
# A standalone top-down commander's board: BLUE air + land assets in the west, RED
# forces in the east, and YOU are the coordinator — click (or drag a box) to select
# blue units, right-click ground to MOVE them, right-click a red unit to ENGAGE it.
# Red SAMs/artillery auto-defend inside their threat rings, so the coordinator's job
# is real: route strike packages around the rings or roll the SAMs back first.
#
# PURE THEATRE, ZERO PHYSICS (HANDOFF §1/§8/§12): this scene never connects to the
# Julia core — every speed, range, Pk and engagement here is display-only
# choreography, exaggerated for map-scale readability and labeled as such on the
# HUD. It is the CLIENT-SIDE FACE of the future Tier-C "Decision / C2 layer"
# (HANDOFF §11): when that slice lands, the core owns weapon–target assignment and
# engagement truth and this board becomes a thin view of it — until then nothing
# drawn here is a core number, and none of it touches the wire.
#
# House rails kept: everything is code-built off a trivial .tscn root (the Sandbox
# precedent); all "assets" are programmatic _draw glyphs + the shared res://fx chrome
# (backdrop shader, glow sprite, theme) — no imported art; the layout/dice RNG is
# FIXED-SEEDED so every launch replays the same board (the props3d determinism
# spirit, though nothing here has a replay contract to protect).
#
# Run:  godot --path clients/godot res://scenes/BattleBoard.tscn

const FX_GLOW: Texture2D = preload("res://fx/glow.tres")
const FX_THEME: Theme = preload("res://fx/theme.tres")
const FX_BACKDROP_SHADER: Shader = preload("res://fx/backdrop.gdshader")

# --- board geometry (display metres; not a core frame) -------------------------
const WORLD_W := 48000.0          # board span, east (+x) — 48 × 32 km
const WORLD_H := 32000.0          # board span, north (+y)
const FLOT_X := 24000.0           # forward line of own troops (the dashed divider)
const PANEL_W := 312.0            # left UI panel clearance (px)
const RNG_SEED := 20260714        # fixed → same board, same dice, every launch

# --- palette (chrome; matches the Sandbox instrument look) ---------------------
const COL_BLUE := Color(0.38, 0.75, 1.0)
const COL_RED := Color(1.0, 0.38, 0.34)
const COL_DEAD := Color(0.45, 0.45, 0.45)
const COL_SEL := Color(1.0, 1.0, 1.0, 0.9)
const COL_GRID := Color(1, 1, 1, 0.05)
const COL_TICK := Color(1, 1, 1, 0.40)
const COL_PANEL_BORDER := Color(0.30, 0.38, 0.48, 0.85)
const COL_MOVE := Color(0.55, 0.95, 0.65, 0.85)
const COL_ENG := Color(1.0, 0.55, 0.25, 0.9)

var _font: Font
var _rng := RandomNumberGenerator.new()

# --- the display-only battle state ---------------------------------------------
# One Dictionary per unit:
#   id, label, side ("blue"/"red"), dom ("air"/"land"), type (glyph key),
#   pos: Vector2 (board m), hdg (rad), vmax (m/s, EXAGGERATED — HUD-labeled),
#   hp, alive, wpn {vs, rng, pk, cd, spd, name}, cool,
#   order: null | {kind:"move", to} | {kind:"engage", tgt},
#   air extras: station (orbit anchor), orbit_r, oa (orbit angle)
#   land extras: patrol [A, B] + pi (red armor's loop)
var _units: Array = []
var _shots: Array = []            # {p, aim, tgt, spd, pk, side, trail:Array, name, shooter}
var _booms: Array = []            # {p, age, max, r, col}
var _log_lines: Array = []        # newest first, capped
var _sel: Array = []              # selected blue unit ids
var _t := 0.0                     # board clock (s)
var _paused := false
var _speed := 1.0                 # 1 / 2 / 4 / 8 time compression
var _terrain_tex: ImageTexture = null

# --- input state ----------------------------------------------------------------
var _drag_a := Vector2.ZERO
var _dragging := false
var _drag_now := Vector2.ZERO

# --- UI --------------------------------------------------------------------------
var _status: Label
var _card: Label
var _roster_blue: Label
var _roster_red: Label
var _log_label: Label
var _play_btn: Button
var _speed_btn: Button
var _panel_accum := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_rng.seed = RNG_SEED
	_build_terrain()
	_spawn_forces()
	_build_ui()
	_logline("coordinator on station — awaiting orders")

# =============================================================== forces ==========
func _mk(id: String, label: String, side: String, dom: String, type: String,
		km: Vector2, vmax: float, wpn: Dictionary) -> Dictionary:
	return {
		"id": id, "label": label, "side": side, "dom": dom, "type": type,
		"pos": km * 1000.0, "hdg": 0.0 if side == "blue" else PI, "vmax": vmax,
		"hp": 2, "alive": true, "wpn": wpn, "cool": 0.0, "order": null,
		"station": km * 1000.0, "orbit_r": 3000.0, "oa": _rng.randf() * TAU,
	}

func _no_wpn() -> Dictionary:
	return {"vs": "none", "rng": 0.0, "pk": 0.0, "cd": 0.0, "spd": 0.0, "name": ""}

func _wpn(vs: String, rng_km: float, pk: float, cd: float, spd: float, name: String) -> Dictionary:
	return {"vs": vs, "rng": rng_km * 1000.0, "pk": pk, "cd": cd, "spd": spd, "name": name}

func _spawn_forces() -> void:
	_units.clear()
	_shots.clear()
	_booms.clear()
	_sel.clear()
	_t = 0.0
	_rng.seed = RNG_SEED
	# ---- BLUE (west of the FLOT; the coordinator's assets) ----
	_units.append(_mk("B-HQ", "HQ / C2", "blue", "land", "hq", Vector2(5, 16), 0.0, _no_wpn()))
	_units.append(_mk("B-EW", "EW RADAR", "blue", "land", "radar", Vector2(8, 20), 0.0, _no_wpn()))
	_units.append(_mk("B-SAM", "SAM BTY", "blue", "land", "sam", Vector2(10, 12), 0.0,
			_wpn("air", 12.0, 0.85, 5.0, 800.0, "SAM")))
	_units.append(_mk("B-ARM1", "TANK PLT A", "blue", "land", "armor", Vector2(14, 10), 44.0,
			_wpn("land", 2.8, 0.7, 3.0, 900.0, "APFSDS")))
	_units.append(_mk("B-ARM2", "TANK PLT B", "blue", "land", "armor", Vector2(14, 22), 44.0,
			_wpn("land", 2.8, 0.7, 3.0, 900.0, "APFSDS")))
	_units.append(_mk("B-ARTY", "ARTY BTY", "blue", "land", "arty", Vector2(9, 17), 28.0,
			_wpn("land", 16.0, 0.65, 6.0, 350.0, "155 mm")))
	_units.append(_mk("B-CAP1", "F-16 CAP 1", "blue", "air", "fighter", Vector2(12, 26), 300.0,
			_wpn("air", 9.0, 0.8, 4.0, 1000.0, "AMRAAM")))
	_units.append(_mk("B-CAP2", "F-16 CAP 2", "blue", "air", "fighter", Vector2(12, 6), 300.0,
			_wpn("air", 9.0, 0.8, 4.0, 1000.0, "AMRAAM")))
	_units.append(_mk("B-STK1", "F-16 STRIKE 1", "blue", "air", "strike", Vector2(6, 14), 280.0,
			_wpn("land", 10.0, 0.75, 5.0, 700.0, "AGM-65")))
	_units.append(_mk("B-STK2", "F-16 STRIKE 2", "blue", "air", "strike", Vector2(6, 18), 280.0,
			_wpn("land", 10.0, 0.75, 5.0, 700.0, "AGM-65")))
	_units.append(_mk("B-AEW", "AEW&C", "blue", "air", "aew", Vector2(4, 16), 180.0, _no_wpn()))
	_units.append(_mk("B-HELO", "AH-64", "blue", "air", "helo", Vector2(13, 16), 90.0,
			_wpn("land", 5.0, 0.75, 4.0, 500.0, "HELLFIRE")))
	# ---- RED (east; the enemy — SAM rings are the coordinator's problem) ----
	_units.append(_mk("R-CP", "RED CP", "red", "land", "cp", Vector2(42, 16), 0.0, _no_wpn()))
	_units.append(_mk("R-SAM1", "SA-BTY N", "red", "land", "sam", Vector2(36, 22), 0.0,
			_wpn("air", 13.0, 0.6, 7.0, 850.0, "SAM")))
	_units.append(_mk("R-SAM2", "SA-BTY S", "red", "land", "sam", Vector2(36, 12), 0.0,
			_wpn("air", 13.0, 0.6, 7.0, 850.0, "SAM")))
	_units.append(_mk("R-EW", "EW RADAR", "red", "land", "radar", Vector2(40, 18), 0.0, _no_wpn()))
	var arm := _mk("R-ARM", "ARMOR COY", "red", "land", "armor", Vector2(30, 14), 36.0,
			_wpn("land", 2.5, 0.65, 3.5, 900.0, "APFSDS"))
	arm["patrol"] = [Vector2(30000, 14000), Vector2(30000, 20000)]
	arm["pi"] = 1
	_units.append(arm)
	_units.append(_mk("R-ARTY", "ARTY BTY", "red", "land", "arty", Vector2(38, 10), 0.0,
			_wpn("land", 15.0, 0.6, 7.0, 350.0, "152 mm")))
	var rcap := _mk("R-CAP", "MiG-29", "red", "air", "fighter", Vector2(40, 26), 290.0,
			_wpn("air", 8.0, 0.7, 5.0, 950.0, "AA-10"))
	rcap["orbit_r"] = 4000.0
	_units.append(rcap)
	_units.append(_mk("R-AFLD", "AIRFIELD", "red", "land", "airfield", Vector2(44, 24), 0.0, _no_wpn()))

func _by_id(id: String) -> Variant:
	for u in _units:
		if u["id"] == id:
			return u
	return null

# =============================================================== orders ==========
# The coordinator API — also the seam the headless UI test drives directly.
func _issue_move(to: Vector2) -> void:
	var i := 0
	for id in _sel:
		var u = _by_id(id)
		if u == null or not u["alive"] or u["side"] != "blue" or u["vmax"] <= 0.0:
			continue
		# small deterministic formation offset so a group doesn't stack on one pixel
		var off := Vector2((i % 3 - 1) * 800.0, floorf(i / 3.0) * 800.0)
		u["order"] = {"kind": "move", "to": to + off}
		i += 1
	if i > 0:
		_logline("MOVE order → %d unit(s) to (%.0f, %.0f) km" % [i, to.x / 1000.0, to.y / 1000.0])
	_refresh_panel()

func _issue_engage(tgt_id: String) -> void:
	var tgt = _by_id(tgt_id)
	if tgt == null or not tgt["alive"] or tgt["side"] != "red":
		return
	var n := 0
	for id in _sel:
		var u = _by_id(id)
		if u == null or not u["alive"]:
			continue
		var vs: String = u["wpn"]["vs"]
		if vs == "none":
			_logline("%s cannot engage (no weapon)" % u["id"])
			continue
		if vs != tgt["dom"]:
			_logline("%s cannot engage %s (%s weapon vs %s target)" % [u["id"], tgt_id, vs, tgt["dom"]])
			continue
		u["order"] = {"kind": "engage", "tgt": tgt_id}
		n += 1
	if n > 0:
		_logline("ENGAGE order → %d unit(s) on %s" % [n, tgt_id])
	_refresh_panel()

# ============================================================ simulation =========
# Display-only choreography — seek/orbit kinematics, cooldown dice, homing streaks.
func _process(dt: float) -> void:
	if not _paused:
		_sim_step(dt * _speed)
	_panel_accum += dt
	if _panel_accum > 0.5:
		_panel_accum = 0.0
		_refresh_panel()
	queue_redraw()

func _sim_step(dt: float) -> void:
	_t += dt
	for u in _units:
		if u["alive"]:
			_step_unit(u, dt)
	_red_ai()
	_blue_defense()
	_step_shots(dt)
	var keep: Array = []
	for b in _booms:
		b["age"] += dt
		if b["age"] < b["max"]:
			keep.append(b)
	_booms = keep

func _step_unit(u: Dictionary, dt: float) -> void:
	u["cool"] = maxf(0.0, u["cool"] - dt)
	var order = u["order"]
	if order == null:
		if u["dom"] == "air":
			_orbit(u, dt)
		elif u.has("patrol"):
			u["order"] = {"kind": "move", "to": u["patrol"][u["pi"]]}
		return
	if order["kind"] == "move":
		var to: Vector2 = order["to"]
		if _seek(u, to, dt):
			u["order"] = null
			if u["dom"] == "air":
				u["station"] = to
				_logline("%s on station" % u["id"])
			elif u.has("patrol"):
				u["pi"] = 1 - int(u["pi"])
			else:
				_logline("%s in position" % u["id"])
	elif order["kind"] == "engage":
		var tgt = _by_id(order["tgt"])
		if tgt == null or not tgt["alive"]:
			u["order"] = null
			if u["dom"] == "air":
				u["station"] = u["pos"]
			_logline("%s: target down — holding" % u["id"])
			return
		var d: float = u["pos"].distance_to(tgt["pos"])
		var rng_m: float = u["wpn"]["rng"]
		if u["dom"] == "air":
			if d > rng_m * 0.9:
				_seek(u, tgt["pos"], dt)         # attack run: close to launch range…
			else:
				# …then ARC at standoff instead of overflying the target (survivability)
				var tang: float = (u["pos"] - tgt["pos"]).angle() + PI / 2.0
				u["hdg"] = lerp_angle(u["hdg"], tang, minf(1.0, 1.4 * dt))
				u["pos"] += Vector2.from_angle(u["hdg"]) * u["vmax"] * dt
		elif d > rng_m * 0.85 and u["vmax"] > 0.0:
			_seek(u, tgt["pos"], dt)             # land closes to 85% of max range, then holds
		else:
			u["hdg"] = (tgt["pos"] - u["pos"]).angle()
		if d <= rng_m:
			_try_fire(u, tgt)

# seek toward a point; returns true on arrival. Turn rate is domain-flavored chrome.
func _seek(u: Dictionary, to: Vector2, dt: float) -> bool:
	var dv: Vector2 = to - u["pos"]
	var step: float = u["vmax"] * dt
	if dv.length() <= maxf(250.0, step * 1.5):
		u["pos"] = to
		return true
	var turn := 1.4 if u["dom"] == "air" else 3.0
	u["hdg"] = lerp_angle(u["hdg"], dv.angle(), minf(1.0, turn * dt))
	u["pos"] += Vector2.from_angle(u["hdg"]) * step
	return false

func _orbit(u: Dictionary, dt: float) -> void:
	if u["vmax"] <= 0.0:
		return
	var r: float = u["orbit_r"]
	u["oa"] = fmod(u["oa"] + (u["vmax"] / r) * dt, TAU)
	u["pos"] = u["station"] + Vector2.from_angle(u["oa"]) * r
	u["hdg"] = u["oa"] + PI / 2.0

func _try_fire(u: Dictionary, tgt: Dictionary) -> void:
	if u["cool"] > 0.0 or not tgt["alive"]:
		return
	if u["pos"].distance_to(tgt["pos"]) > u["wpn"]["rng"]:
		return
	u["cool"] = u["wpn"]["cd"]
	_shots.append({
		"p": u["pos"], "aim": tgt["pos"], "tgt": tgt["id"], "spd": u["wpn"]["spd"],
		"pk": u["wpn"]["pk"], "side": u["side"], "trail": [], "name": u["wpn"]["name"],
		"shooter": u["id"],
	})
	_logline("%s fires %s → %s" % [u["id"], u["wpn"]["name"], tgt["id"]])

# Red auto-defense: every armed red unit engages the nearest valid blue target inside
# its ring (the MiG chases; statics just shoot). This is what makes the rings REAL.
func _red_ai() -> void:
	for u in _units:
		if u["side"] != "red" or not u["alive"] or u["wpn"]["vs"] == "none":
			continue
		var best = null
		var best_d := INF
		for b in _units:
			if b["side"] != "blue" or not b["alive"] or b["dom"] != u["wpn"]["vs"]:
				continue
			var d: float = u["pos"].distance_to(b["pos"])
			if d < best_d:
				best_d = d
				best = b
		if best == null:
			continue
		if u["id"] == "R-CAP":
			var cur = u["order"]
			if best_d < 15000.0 and (cur == null or cur["kind"] != "engage"):
				u["order"] = {"kind": "engage", "tgt": best["id"]}
			elif best_d > 20000.0 and cur != null and cur["kind"] == "engage":
				u["order"] = null                # break off, return to CAP station
		if best_d <= u["wpn"]["rng"]:
			_try_fire(u, best)

# Blue's ONLY autonomy: the SAM battery self-defends vs red air in its ring — every
# other blue trigger pull is a coordinator order.
func _blue_defense() -> void:
	var sam = _by_id("B-SAM")
	if sam == null or not sam["alive"]:
		return
	for r in _units:
		if r["side"] == "red" and r["alive"] and r["dom"] == "air":
			if sam["pos"].distance_to(r["pos"]) <= sam["wpn"]["rng"]:
				_try_fire(sam, r)
				break

func _step_shots(dt: float) -> void:
	var keep: Array = []
	for s in _shots:
		var tgt = _by_id(s["tgt"])
		if tgt != null and tgt["alive"]:
			s["aim"] = tgt["pos"]
		var dv: Vector2 = s["aim"] - s["p"]
		var step: float = s["spd"] * dt
		if dv.length() <= maxf(150.0, step):
			_resolve_shot(s, tgt)
		else:
			var tr: Array = s["trail"]
			tr.push_front(s["p"])
			if tr.size() > 8:
				tr.pop_back()
			s["p"] += dv.normalized() * step
			keep.append(s)
	_shots = keep

func _resolve_shot(s: Dictionary, tgt: Variant) -> void:
	if tgt == null or not tgt["alive"]:
		_boom(s["aim"], 10.0, Color(0.8, 0.8, 0.8))
		return
	if _rng.randf() < s["pk"]:
		tgt["hp"] = int(tgt["hp"]) - 1
		if int(tgt["hp"]) <= 0:
			tgt["alive"] = false
			tgt["order"] = null
			_sel.erase(tgt["id"])
			_boom(tgt["pos"], 30.0, Color(1.0, 0.6, 0.25))
			_logline("%s DESTROYED by %s (%s)" % [tgt["id"], s["shooter"], s["name"]])
		else:
			_boom(tgt["pos"], 16.0, Color(1.0, 0.75, 0.35))
			_logline("%s hit %s" % [s["shooter"], tgt["id"]])
	else:
		_boom(s["aim"] + Vector2(_rng.randf_range(-300, 300), _rng.randf_range(-300, 300)),
				9.0, Color(0.85, 0.85, 0.85))
		_logline("%s missed %s" % [s["shooter"], s["tgt"]])
	_refresh_panel()

func _boom(p: Vector2, r: float, col: Color) -> void:
	_booms.append({"p": p, "age": 0.0, "max": 1.2, "r": r, "col": col})

func _logline(msg: String) -> void:
	_log_lines.push_front("[%s] %s" % [_clock(), msg])
	if _log_lines.size() > 10:
		_log_lines.pop_back()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)

func _clock() -> String:
	return "%02d:%02d" % [int(_t / 60.0), int(_t) % 60]

# ================================================================ input ==========
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_drag_a = ev.position
				_drag_now = ev.position
				_dragging = true
			elif _dragging:
				_dragging = false
				if _drag_a.distance_to(ev.position) < 6.0:
					_click_select(ev.position)
				else:
					_box_select(Rect2(_drag_a, Vector2.ZERO).expand(ev.position))
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_issue_at(ev.position)
	elif ev is InputEventMouseMotion and _dragging:
		_drag_now = ev.position

func _click_select(sp: Vector2) -> void:
	var best_id := ""
	var best_d := 18.0
	for u in _units:
		if u["side"] != "blue" or not u["alive"]:
			continue
		var d: float = _w2s(u["pos"]).distance_to(sp)
		if d < best_d:
			best_d = d
			best_id = u["id"]
	_sel = [best_id] if best_id != "" else []
	_refresh_panel()

func _box_select(r: Rect2) -> void:
	_sel = []
	for u in _units:
		if u["side"] == "blue" and u["alive"] and r.has_point(_w2s(u["pos"])):
			_sel.append(u["id"])
	_refresh_panel()

func _issue_at(sp: Vector2) -> void:
	if _sel.is_empty():
		return
	# right-click a red unit → ENGAGE; right-click ground → MOVE
	for u in _units:
		if u["side"] == "red" and u["alive"] and _w2s(u["pos"]).distance_to(sp) < 16.0:
			_issue_engage(u["id"])
			return
	var w := _s2w(sp)
	if w.x < 0 or w.x > WORLD_W or w.y < 0 or w.y > WORLD_H:
		return
	_issue_move(w)

# ============================================================== mapping ==========
func _map_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(PANEL_W + 14.0, 10.0, maxf(vp.x - PANEL_W - 28.0, 50.0), maxf(vp.y - 58.0, 50.0))

func _map_scale() -> float:
	var r := _map_rect()
	return minf(r.size.x / WORLD_W, r.size.y / WORLD_H)

func _w2s(w: Vector2) -> Vector2:
	var r := _map_rect()
	var sc := _map_scale()
	var org := r.position + (r.size - Vector2(WORLD_W, WORLD_H) * sc) * 0.5
	return org + Vector2(w.x, WORLD_H - w.y) * sc   # +y north → screen up

func _s2w(sp: Vector2) -> Vector2:
	var r := _map_rect()
	var sc := _map_scale()
	var org := r.position + (r.size - Vector2(WORLD_W, WORLD_H) * sc) * 0.5
	var q := (sp - org) / sc
	return Vector2(q.x, WORLD_H - q.y)

# ============================================================== terrain ==========
# A deterministic Gaussian-hill tint (the terrain.jl aesthetic, regenerated as 2-D
# chrome — NOT the core's heightfield; this board has no core).
func _build_terrain() -> void:
	var w := 240
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var hills := []
	var trng := RandomNumberGenerator.new()
	trng.seed = RNG_SEED
	for i in range(9):
		hills.append({
			"x": trng.randf() * WORLD_W, "y": trng.randf() * WORLD_H,
			"a": trng.randf_range(0.25, 1.0), "s": trng.randf_range(2500.0, 7000.0),
		})
	for py in range(h):
		for px in range(w):
			var wx := (px + 0.5) / w * WORLD_W
			var wy := (1.0 - (py + 0.5) / h) * WORLD_H
			var z := 0.0
			for hl in hills:
				var dx: float = wx - hl["x"]
				var dy: float = wy - hl["y"]
				var s2: float = hl["s"] * hl["s"]
				z += hl["a"] * exp(-(dx * dx + dy * dy) / (2.0 * s2))
			z = clampf(z, 0.0, 1.3)
			var lo := Color(0.075, 0.115, 0.075)      # lowland dark green
			var mid := Color(0.14, 0.15, 0.095)       # olive
			var hi := Color(0.21, 0.17, 0.12)         # brown hilltop
			var c: Color
			if z < 0.62:
				c = lo.lerp(mid, clampf(z * 1.6, 0.0, 1.0))
			else:
				c = mid.lerp(hi, clampf((z - 0.62) * 2.2, 0.0, 1.0))
			img.set_pixel(px, py, c)
	_terrain_tex = ImageTexture.create_from_image(img)

# ================================================================= draw ==========
func _draw() -> void:
	var r := _map_rect()
	# map panel + terrain tint
	draw_rect(r.grow(4.0), Color(0.065, 0.09, 0.125, 0.92))
	if _terrain_tex != null:
		var tl := _w2s(Vector2(0, WORLD_H))
		var br := _w2s(Vector2(WORLD_W, 0))
		draw_texture_rect(_terrain_tex, Rect2(tl, br - tl), false, Color(1, 1, 1, 0.9))
	draw_rect(r.grow(4.0), COL_PANEL_BORDER, false, 1.5)
	_draw_grid()
	_draw_flot()
	for u in _units:                                  # rings under the icons
		if u["alive"]:
			_draw_rings(u)
	for u in _units:                                  # order overlays under icons too
		if u["alive"]:
			_draw_order(u)
	for u in _units:
		if not u["alive"]:
			_draw_wreck(u)
	for u in _units:
		if u["alive"] and u["side"] == "red":
			_draw_unit(u)
	for u in _units:
		if u["alive"] and u["side"] == "blue":
			_draw_unit(u)
	_draw_shots()
	_draw_booms()
	if _dragging and _drag_a.distance_to(_drag_now) >= 6.0:
		var box := Rect2(_drag_a, Vector2.ZERO).expand(_drag_now)
		draw_rect(box, Color(1, 1, 1, 0.06))
		draw_rect(box, COL_SEL, false, 1.0)
	_draw_hud()

func _draw_grid() -> void:
	var step := 8000.0
	var x := 0.0
	while x <= WORLD_W:
		var a := _w2s(Vector2(x, 0))
		var b := _w2s(Vector2(x, WORLD_H))
		draw_line(a, b, COL_GRID, 1.0)
		draw_string(_font, Vector2(b.x - 8, a.y + 14), "%d" % int(x / 1000.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
		x += step
	var y := 0.0
	while y <= WORLD_H:
		var a2 := _w2s(Vector2(0, y))
		var b2 := _w2s(Vector2(WORLD_W, y))
		draw_line(a2, b2, COL_GRID, 1.0)
		draw_string(_font, Vector2(a2.x - 22, a2.y + 4), "%d" % int(y / 1000.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
		y += step
	var corner := _w2s(Vector2(WORLD_W, 0))
	draw_string(_font, corner + Vector2(-32, 28), "km", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)

func _draw_flot() -> void:
	var a := _w2s(Vector2(FLOT_X, 0))
	var b := _w2s(Vector2(FLOT_X, WORLD_H))
	draw_dashed_line(a, b, Color(1, 1, 1, 0.25), 1.5, 10.0)
	draw_string(_font, b + Vector2(6, 14), "FLOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1, 1, 1, 0.45))

func _draw_rings(u: Dictionary) -> void:
	var p := _w2s(u["pos"])
	var sc := _map_scale()
	if u["type"] == "radar":                          # surveillance coverage (dashed)
		var rr := (22000.0 if u["side"] == "blue" else 20000.0) * sc
		var col := COL_BLUE if u["side"] == "blue" else COL_RED
		draw_arc(p, rr, 0, TAU, 96, Color(col.r, col.g, col.b, 0.18), 1.0, true)
	elif u["id"] == "B-AEW":
		draw_arc(p, 26000.0 * sc, 0, TAU, 96, Color(0.5, 0.9, 1.0, 0.14), 1.0, true)
	if u["wpn"]["vs"] == "air":                       # SAM threat ring (the lesson)
		var col2 := COL_BLUE if u["side"] == "blue" else COL_RED
		var rr2: float = u["wpn"]["rng"] * sc
		draw_arc(p, rr2, 0, TAU, 96, Color(col2.r, col2.g, col2.b, 0.45), 1.4, true)
		draw_circle_region(p, rr2, Color(col2.r, col2.g, col2.b, 0.045))

# filled translucent disc (draw_circle with alpha stacks badly at big radii on some
# drivers when antialiased arcs overlap; one polygon keeps it flat)
func draw_circle_region(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(48):
		pts.append(p + Vector2.from_angle(TAU * i / 48.0) * r)
	draw_colored_polygon(pts, col)

func _draw_order(u: Dictionary) -> void:
	var order = u["order"]
	if order == null or u["side"] != "blue":
		return
	var p := _w2s(u["pos"])
	if order["kind"] == "move":
		var q := _w2s(order["to"])
		draw_dashed_line(p, q, COL_MOVE, 1.2, 7.0)
		draw_line(q + Vector2(0, -10), q, COL_MOVE, 1.5)   # waypoint flag
		var flag := PackedVector2Array([q + Vector2(0, -10), q + Vector2(8, -7), q + Vector2(0, -4)])
		draw_colored_polygon(flag, COL_MOVE)
	elif order["kind"] == "engage":
		var tgt = _by_id(order["tgt"])
		if tgt != null and tgt["alive"]:
			draw_dashed_line(p, _w2s(tgt["pos"]), COL_ENG, 1.2, 6.0)

func _side_col(u: Dictionary) -> Color:
	return COL_BLUE if u["side"] == "blue" else COL_RED

func _draw_unit(u: Dictionary) -> void:
	var p := _w2s(u["pos"])
	var col := _side_col(u)
	if u["dom"] == "air":
		_draw_air(u, p, col)
	else:
		_draw_land(u, p, col)
	if _sel.has(u["id"]):
		_draw_brackets(p, 16.0)
	# label + hp pips
	draw_string(_font, p + Vector2(-24, 26), u["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(col.r, col.g, col.b, 0.9))
	for i in range(int(u["hp"])):
		draw_rect(Rect2(p + Vector2(-8 + i * 7, 29), Vector2(5, 3)), Color(col.r, col.g, col.b, 0.7))

# ---- land glyphs: NATO-flavored frames (blue rect / red diamond) + a type mark ----
func _draw_land(u: Dictionary, p: Vector2, col: Color) -> void:
	_glow(p, 18.0, Color(col.r, col.g, col.b, 0.20))
	if u["side"] == "blue":
		draw_rect(Rect2(p - Vector2(12, 8), Vector2(24, 16)), col, false, 1.6)
	else:
		var d := PackedVector2Array([p + Vector2(0, -12), p + Vector2(12, 0),
				p + Vector2(0, 12), p + Vector2(-12, 0)])
		draw_polyline(d + PackedVector2Array([d[0]]), col, 1.6, true)
	match u["type"]:
		"armor":                                       # the oval track mark
			var pts := PackedVector2Array()
			for i in range(25):
				var a := TAU * i / 24.0
				pts.append(p + Vector2(cos(a) * 7.0, sin(a) * 4.0))
			draw_polyline(pts, col, 1.3, true)
		"arty":
			draw_circle(p, 3.0, col)
		"sam":
			var ch := PackedVector2Array([p + Vector2(-6, 4), p + Vector2(0, -6), p + Vector2(6, 4)])
			draw_polyline(ch, col, 1.6, true)
		"radar":
			draw_arc(p + Vector2(0, 3), 6.0, PI + 0.5, TAU - 0.5, 12, col, 1.4, true)
			draw_circle(p + Vector2(0, 3), 1.6, col)
			draw_line(p + Vector2(0, 3), p + Vector2(0, -6), col, 1.2)
		"hq":
			draw_string(_font, p + Vector2(-9, 5), "HQ", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		"cp":
			draw_string(_font, p + Vector2(-8, 5), "CP", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		"airfield":
			draw_line(p + Vector2(-8, 4), p + Vector2(8, -4), col, 2.0)
			draw_line(p + Vector2(-8, -2), p + Vector2(8, 2), col, 1.2)

# ---- air glyphs: heading-oriented silhouettes + a velocity leader ----
func _draw_air(u: Dictionary, p: Vector2, col: Color) -> void:
	_glow(p, 16.0, Color(col.r, col.g, col.b, 0.25))
	var hdg: float = u["hdg"]
	var tf := Transform2D(-hdg, p)                     # board +y is up on screen → negate
	match u["type"]:
		"helo":
			draw_circle(p, 5.0, Color(col.r, col.g, col.b, 0.35))
			draw_arc(p, 5.0, 0, TAU, 20, col, 1.4, true)
			var ra := _t * 9.0
			draw_line(p + Vector2.from_angle(ra) * 8.0, p - Vector2.from_angle(ra) * 8.0, col, 1.2)
			draw_line(p + Vector2.from_angle(ra + PI / 2) * 8.0,
					p - Vector2.from_angle(ra + PI / 2) * 8.0, col, 1.2)
		"aew":
			_draw_plane(tf, col, 1.2)
			draw_arc(p, 4.0, 0, TAU, 16, Color(0.5, 0.9, 1.0), 1.4, true)
		_:
			_draw_plane(tf, col, 1.0)
			if u["type"] == "strike":                  # strike carries visible pylons
				draw_line(tf * Vector2(-2, -7), tf * Vector2(-2, 7), col, 1.0)
	# velocity leader
	var lead := Vector2.from_angle(-hdg) * 20.0
	draw_line(p + lead * 0.55, p + lead, Color(col.r, col.g, col.b, 0.7), 1.0)

func _draw_plane(tf: Transform2D, col: Color, k: float) -> void:
	var pts := PackedVector2Array([
		tf * (Vector2(9, 0) * k), tf * (Vector2(1, 2) * k), tf * (Vector2(-2, 8) * k),
		tf * (Vector2(-4, 8) * k), tf * (Vector2(-3, 2) * k), tf * (Vector2(-6, 1.5) * k),
		tf * (Vector2(-8, 4) * k), tf * (Vector2(-8.5, 0) * k), tf * (Vector2(-8, -4) * k),
		tf * (Vector2(-6, -1.5) * k), tf * (Vector2(-3, -2) * k), tf * (Vector2(-4, -8) * k),
		tf * (Vector2(-2, -8) * k), tf * (Vector2(1, -2) * k),
	])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.9))

func _draw_brackets(p: Vector2, r: float) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := p + Vector2(sx * r, sy * r)
			draw_line(c, c - Vector2(sx * 6.0, 0), COL_SEL, 1.3)
			draw_line(c, c - Vector2(0, sy * 6.0), COL_SEL, 1.3)

func _draw_wreck(u: Dictionary) -> void:
	var p := _w2s(u["pos"])
	_glow(p, 12.0, Color(0.2, 0.2, 0.2, 0.5))
	draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), COL_DEAD, 2.0)
	draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), COL_DEAD, 2.0)
	draw_string(_font, p + Vector2(-24, 22), u["id"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_DEAD)

func _draw_shots() -> void:
	for s in _shots:
		var p := _w2s(s["p"])
		var col := COL_BLUE if s["side"] == "blue" else COL_RED
		var tr: Array = s["trail"]
		var prev := p
		for i in range(tr.size()):
			var q := _w2s(tr[i])
			draw_line(prev, q, Color(col.r, col.g, col.b, 0.6 * (1.0 - i / 8.0)), 1.4)
			prev = q
		_glow(p, 8.0, Color(1.0, 0.85, 0.5, 0.8))
		draw_circle(p, 2.0, Color(1.0, 0.95, 0.8))

func _draw_booms() -> void:
	for b in _booms:
		var p := _w2s(b["p"])
		var k: float = b["age"] / b["max"]
		var col: Color = b["col"]
		_glow(p, b["r"] * (0.6 + k * 1.4), Color(col.r, col.g, col.b, (1.0 - k) * 0.8))
		draw_arc(p, b["r"] * k * 1.2 + 2.0, 0, TAU, 24, Color(col.r, col.g, col.b, 1.0 - k), 1.6, true)

func _glow(p: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(FX_GLOW, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _draw_hud() -> void:
	var r := _map_rect()
	var right := r.position.x + r.size.x
	draw_string(_font, Vector2(right - 330, r.position.y + 22), "BATTLE BOARD — coordinator view",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.85))
	draw_string(_font, Vector2(right - 330, r.position.y + 40), "T+%s   speed ×%d%s" %
			[_clock(), int(_speed), "   PAUSED" if _paused else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TICK)
	# §12 display honesty: this board is theatre, and says so on screen.
	draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y + 34),
			"DISPLAY-ONLY THEATRE — speeds/ranges/Pk are readability-exaggerated choreography, " +
			"not core truth (the Tier-C C2 layer will own this)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.8, 0.4, 0.55))

# ================================================================== UI ===========
func _build_ui() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -2
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = FX_BACKDROP_SHADER
	bg.material = bg_mat
	bg_layer.add_child(bg)

	var ui := CanvasLayer.new()
	add_child(ui)
	var panel_box := PanelContainer.new()
	panel_box.position = Vector2(8, 8)
	panel_box.theme = FX_THEME
	panel_box.custom_minimum_size = Vector2(PANEL_W - 12.0, 0)
	ui.add_child(panel_box)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	panel_box.add_child(panel)

	_status = Label.new()
	_status.text = "BATTLE BOARD — C2 coordinator"
	panel.add_child(_status)

	var row := HBoxContainer.new()
	panel.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "Pause"
	_play_btn.pressed.connect(_on_play)
	row.add_child(_play_btn)
	_speed_btn = Button.new()
	_speed_btn.text = "×1"
	_speed_btn.pressed.connect(_on_speed)
	row.add_child(_speed_btn)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(_on_reset)
	row.add_child(reset)

	var help := Label.new()
	help.text = ("OBJECTIVE: destroy RED CP.\n" +
			"Red SAM rings kill aircraft — suppress\nthem or route around.\n" +
			"left-click / drag-box: select blue\n" +
			"right-click ground: MOVE\n" +
			"right-click red unit: ENGAGE")
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.75)
	panel.add_child(help)

	_card = Label.new()
	_card.add_theme_font_size_override("font_size", 12)
	panel.add_child(_card)
	_roster_blue = Label.new()
	_roster_blue.add_theme_font_size_override("font_size", 12)
	_roster_blue.modulate = Color(0.75, 0.9, 1.0)
	panel.add_child(_roster_blue)
	_roster_red = Label.new()
	_roster_red.add_theme_font_size_override("font_size", 12)
	_roster_red.modulate = Color(1.0, 0.8, 0.78)
	panel.add_child(_roster_red)
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 11)
	_log_label.modulate = Color(1, 1, 1, 0.65)
	panel.add_child(_log_label)
	_refresh_panel()

func _on_play() -> void:
	_paused = not _paused
	_play_btn.text = "Resume" if _paused else "Pause"

func _on_speed() -> void:
	_speed = _speed * 2.0 if _speed < 8.0 else 1.0
	_speed_btn.text = "×%d" % int(_speed)

func _on_reset() -> void:
	_spawn_forces()
	_log_lines.clear()
	_logline("board reset — awaiting orders")
	_refresh_panel()

func _status_word(u: Dictionary) -> String:
	if not u["alive"]:
		return "destroyed"
	var order = u["order"]
	if order == null:
		return "on station" if u["dom"] == "air" else "holding"
	if order["kind"] == "move":
		return "moving"
	return "engaging %s" % order["tgt"]

func _refresh_panel() -> void:
	if _roster_blue == null:
		return
	var bl := "BLUE FORCE"
	var rl := "RED FORCE"
	for u in _units:
		var line := "\n%s %-7s %-13s %s" % ["■" if u["alive"] else "✕", u["id"], u["label"],
				_status_word(u)]
		if u["side"] == "blue":
			bl += line
		else:
			rl += line
	_roster_blue.text = bl
	_roster_red.text = rl
	if _sel.is_empty():
		_card.text = "selected: —"
	else:
		var txt := "selected:"
		for id in _sel:
			var u = _by_id(id)
			if u == null:
				continue
			var w: String = "unarmed" if u["wpn"]["vs"] == "none" else \
					"%s vs %s, %.0f km" % [u["wpn"]["name"], u["wpn"]["vs"], u["wpn"]["rng"] / 1000.0]
			txt += "\n%s %s — %s" % [id, u["label"], w]
		_card.text = txt
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
