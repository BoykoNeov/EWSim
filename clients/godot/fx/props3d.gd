extends RefCounted
# fx/props3d.gd — the baked 3-D PROP & EFFECT library (res://fx/ — display-only chrome
# for the Node3D views; the slice-18 terrain view today, land-clutter/6-DOF views later).
#
# PURE EYE CANDY, ZERO PHYSICS (HANDOFF §1/§8): nothing here reads or produces a wire
# number — the core never learns these exist. `decorate()` runs a DETERMINISTIC scatter
# (RNG seeded from the CORE's handshake height grid, so the same scenario always dresses
# the same way) siting military structures (SAM batteries inside earth berms, a spinning
# search-radar site on a hilltop, a tank column + truck convoy on the roads), civilian
# infrastructure (a city with lit-window towers and a night glow, villages, a farm with
# a field patchwork, an oil refinery with a burning flare stack, a sawtooth factory with
# smoking chimneys, an airstrip, roads, a sagging power line, an elevated pipeline, a
# wind farm with turning rotors, a comms mast) and GPU-particle EFFECTS (fire, drifting
# smoke, a periodic range explosion, a burning wreck) onto the terrain the client
# already meshes. Every prop is grounded by bilinear-sampling that SAME handshake grid —
# PLACEMENT only; occlusion/detection remain the core's verdict, and nothing tall is
# sited inside the radar↔target LOS corridor so the decoration can never visually
# contradict the core's `visible` boolean. Prop sizes are READABILITY-exaggerated at map
# scale (the HUD labels the view decorative/not-to-scale — the §12 display-honesty rule).
#
# Animation contract (the CALLER drives from its _process; nothing here ticks itself):
#   spinners: rotate_object_local(meta "spin_axis", meta "spin_rate" * dt) each frame
#   beacons:  visible = fmod(t, meta "blink_period") < 0.55 * meta "blink_period"
#   booms:    meta "boom_t" counts down; at 0 restart() every GPUParticles3D child and
#             re-arm from meta "boom_period" (one-shot fireball + flash + smoke).

static var _mats := {}            # shared material cache (key -> Material; survives rebuilds)
static var _win_texs: Array = []  # lit-window emission textures (generated once, deterministic)

# ---------------------------------------------------------------- entry point ----------
static func decorate(root: Node3D, grid_h: Array, n: int, extent: Array,
		to3d: Callable, glow_tex: Texture2D, keep_a: Vector2, keep_b: Vector2) -> Dictionary:
	var out := {"root": null, "spinners": [], "beacons": [], "booms": []}
	if root == null or n < 2 or extent.size() < 4 or grid_h.size() < n * n:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(grid_h) ^ (n * 2654435761)   # grid-seeded → same scenario, same layout
	var pr := Node3D.new()
	root.add_child(pr)
	out["root"] = pr
	var span_x := float(extent[1]) - float(extent[0])
	var span_y := float(extent[3]) - float(extent[2])
	var span_m := maxf(maxf(span_x, span_y), 1.0)
	# display units per sim metre, measured through the caller's mapping (no scale const dup)
	var upm: float = to3d.call([1.0, 0.0, 0.0]).distance_to(to3d.call([0.0, 0.0, 0.0]))
	var c := {
		"g": grid_h, "n": n, "e": extent, "to3d": to3d, "out": pr, "rng": rng,
		"glow": glow_tex, "k": clampf(span_m * upm / 70.0, 0.8, 2.6), "upm": upm,
		"spin": out["spinners"], "beac": out["beacons"], "boom": out["booms"],
	}
	# ---- site survey: coarse lattice scored by height/slope/LOS-corridor distance ----
	var keep_r := span_m * 0.10
	var cands: Array = []
	var m := 22
	for iy in range(2, m - 1):
		for ix in range(2, m - 1):
			var x := float(extent[0]) + span_x * ix / float(m)
			var y := float(extent[2]) + span_y * iy / float(m)
			var d := span_m / float(m)
			var sl := maxf(
					absf(_height(c, x + d, y) - _height(c, x - d, y)),
					absf(_height(c, x, y + d) - _height(c, x, y - d))) / (2.0 * d)
			cands.append({"x": x, "y": y, "h": _height(c, x, y), "s": sl,
					"dl": _seg_d(Vector2(x, y), keep_a, keep_b)})
	var open := cands.filter(func(q): return q["dl"] > keep_r)
	if open.is_empty():
		open = cands
	var flats := open.duplicate()   # flattest-and-lowest first — settlements/industry
	flats.sort_custom(func(a, b): return a["s"] * 2000.0 + a["h"] < b["s"] * 2000.0 + b["h"])
	var highs := open.duplicate()   # highest first — radar/comms/wind sites
	highs.sort_custom(func(a, b): return a["h"] > b["h"])
	var fars := open.duplicate()    # farthest from the LOS corridor — the live-fire range
	fars.sort_custom(func(a, b): return a["dl"] > b["dl"])
	var used: Array = []
	var sep := span_m * 0.09
	var city = _pick(flats, used, sep * 1.5)
	var refinery = _pick(flats, used, sep)
	var factory = _pick(flats, used, sep)
	var vill1 = _pick(flats, used, sep)
	var vill2 = _pick(flats, used, sep)
	var farm = _pick(flats, used, sep)
	var strip = _pick(flats, used, sep)
	var sam1 = _pick(flats, used, sep * 0.8)
	var sam2 = _pick(flats, used, sep * 0.8)
	var radar_hill = _pick(highs, used, sep * 0.7)
	var comms_hill = _pick(highs, used, sep * 0.7)
	var wind_ridge = _pick(highs, used, sep * 0.7)
	var range_site = _pick(fars, used, sep * 0.8)
	# ---- structures ----
	if city != null:
		_city(c, city["x"], city["y"], span_x)
	if refinery != null:
		_refinery(c, refinery["x"], refinery["y"])
	if factory != null:
		_factory(c, factory["x"], factory["y"])
	if vill1 != null:
		_village(c, vill1["x"], vill1["y"], span_x)
	if vill2 != null:
		_village(c, vill2["x"], vill2["y"], span_x)
	if farm != null:
		_farm(c, farm["x"], farm["y"], span_x)
	if strip != null:
		_airstrip(c, strip["x"], strip["y"], span_x)
	if sam1 != null:
		_sam(c, sam1["x"], sam1["y"])
	if sam2 != null:
		_sam(c, sam2["x"], sam2["y"])
	if radar_hill != null:
		_radar_site(c, radar_hill["x"], radar_hill["y"])
	if comms_hill != null:
		_comms_tower(c, comms_hill["x"], comms_hill["y"])
	if wind_ridge != null:
		_windfarm(c, wind_ridge["x"], wind_ridge["y"], span_x)
	if range_site != null:
		_range(c, range_site["x"], range_site["y"])
	# ---- lines: roads / power / pipeline (flat ribbons & wires — corridor-safe) ----
	var road_w := clampf(span_m * 0.004, 20.0, 80.0)
	if city != null:
		var cp := Vector2(city["x"], city["y"])
		for q in [vill1, vill2, refinery, factory, strip]:
			if q != null:
				_ribbon(c, cp, Vector2(q["x"], q["y"]), road_w, Color(0.085, 0.09, 0.105), 2.5, 0.10)
		if sam1 != null:
			var sp := Vector2(sam1["x"], sam1["y"])
			_ribbon(c, cp, sp, road_w * 0.8, Color(0.10, 0.10, 0.095), 2.5, 0.10)
			_column(c, cp, sp)                       # the tank column, road-marching to the SAM site
		if refinery != null:
			_convoy(c, cp, Vector2(refinery["x"], refinery["y"]))
			_powerline(c, Vector2(refinery["x"], refinery["y"]), cp)
		if vill1 != null:                             # a burning wreck beside the village road
			var wp := cp.lerp(Vector2(vill1["x"], vill1["y"]), 0.55)
			_wreck(c, wp.x + span_m * 0.006, wp.y + span_m * 0.006)
	if vill1 != null and farm != null:
		_ribbon(c, Vector2(vill1["x"], vill1["y"]), Vector2(farm["x"], farm["y"]),
				road_w * 0.7, Color(0.11, 0.10, 0.085), 2.5, 0.12)
	if refinery != null:
		var px: float = refinery["x"]
		var edge_x := float(extent[0]) if (px - float(extent[0])) < (float(extent[1]) - px) else float(extent[1])
		_pipeline(c, Vector2(px, refinery["y"]), Vector2(edge_x, refinery["y"]))
	return out

# ---------------------------------------------------------------- terrain helpers ------
static func _height(c: Dictionary, x: float, y: float) -> float:
	# Bilinear sample of the CORE's handshake grid (row-major over y then x — the
	# `_terrain_info` contract). Placement only — never an occlusion answer.
	var n: int = c["n"]
	var e: Array = c["e"]
	var fx := clampf((x - float(e[0])) / (float(e[1]) - float(e[0])) * (n - 1), 0.0, n - 1.001)
	var fy := clampf((y - float(e[2])) / (float(e[3]) - float(e[2])) * (n - 1), 0.0, n - 1.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var g: Array = c["g"]
	return lerpf(lerpf(float(g[iy * n + ix]), float(g[iy * n + ix + 1]), tx),
			lerpf(float(g[(iy + 1) * n + ix]), float(g[(iy + 1) * n + ix + 1]), tx), ty)

static func _gv(c: Dictionary, x: float, y: float, up_m := 0.0) -> Vector3:
	return c["to3d"].call([x, y, _height(c, x, y) + up_m])

static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.0:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _pick(list: Array, used: Array, sep: float) -> Variant:
	for q in list:
		var p := Vector2(q["x"], q["y"])
		var ok := true
		for u in used:
			if p.distance_to(u) < sep:
				ok = false
				break
		if ok:
			used.append(p)
			return q
	return null

# ---------------------------------------------------------------- build helpers --------
static func _site(c: Dictionary, x: float, y: float, yaw := 0.0) -> Node3D:
	var s := Node3D.new()
	s.position = _gv(c, x, y)
	s.rotation.y = yaw
	c["out"].add_child(s)
	return s

static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

static func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b

static func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var cy := CylinderMesh.new()
	cy.top_radius = rt
	cy.bottom_radius = rb
	cy.height = h
	cy.radial_segments = 20
	cy.rings = 1
	return cy

static func _sph(r: float) -> SphereMesh:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = 2.0 * r
	sp.radial_segments = 16
	sp.rings = 8
	return sp

static func _prism(w: float, h: float, d: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(w, h, d)
	return p

static func _m(key: String, albedo: Color, rough := 0.9, metal := 0.0,
		emis := Color(0, 0, 0), e_en := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	mat.metallic = metal
	if e_en > 0.0:
		mat.emission_enabled = true
		mat.emission = emis
		mat.emission_energy_multiplier = e_en
	_mats[key] = mat
	return mat

static func _lm() -> StandardMaterial3D:
	# The one unshaded vertex-color material for ribbons / field patches / wires.
	if _mats.has("__line"):
		return _mats["__line"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["__line"] = mat
	return mat

static func _win_tex(rng: RandomNumberGenerator) -> ImageTexture:
	# A tiny lit-window emission map (nearest-filtered → blocky windows at night).
	var img := Image.create_empty(6, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.025, 0.035, 1.0))
	for yy in 12:
		for xx in 6:
			if rng.randf() < 0.30:
				var w := 0.45 + rng.randf() * 0.35
				img.set_pixel(xx, yy, Color(w, w * 0.85, w * 0.55, 1.0))
	return ImageTexture.create_from_image(img)

static func _win_mat(c: Dictionary, v: int) -> StandardMaterial3D:
	var key := "win%d" % (v % 3)
	if _mats.has(key):
		return _mats[key]
	if _win_texs.is_empty():
		for i in 3:
			_win_texs.append(_win_tex(c["rng"]))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.11, 0.135)
	mat.roughness = 0.8
	mat.emission_enabled = true
	# emission stays BLACK: the default emission operator is ADD, so any base emission
	# color washes the whole face — the warm tint lives in the texture's lit pixels only.
	mat.emission_energy_multiplier = 1.6
	mat.emission_texture = _win_texs[v % _win_texs.size()]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(3.0, 4.0, 3.0)
	_mats[key] = mat
	return mat

# ---------------------------------------------------------------- particle effects -----
static func _grad(pts: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for p in pts:
		offs.append(p[0])
		cols.append(p[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

static func _puff_mesh(c: Dictionary, size: float, additive: bool) -> QuadMesh:
	# One soft billboard quad per particle, textured with the baked fx/glow.tres sprite.
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = c["glow"]
	q.material = mat
	return q

static func _fire(c: Dictionary, parent: Node3D, pos: Vector3, s: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.9
	p.randomness = 0.4
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.gravity = Vector3(0, 0.9 * s, 0)           # buoyant — flames accelerate upward
	pm.initial_velocity_min = 0.5 * s
	pm.initial_velocity_max = 1.1 * s
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.10 * s
	pm.scale_min = 0.55
	pm.scale_max = 1.25
	pm.color_ramp = _grad([[0.0, Color(1.0, 0.95, 0.75, 0.9)], [0.35, Color(1.0, 0.55, 0.12, 0.8)],
			[0.75, Color(0.9, 0.2, 0.05, 0.45)], [1.0, Color(0.4, 0.05, 0.02, 0.0)]])
	p.process_material = pm
	p.draw_pass_1 = _puff_mesh(c, 0.34 * s, true)
	parent.add_child(p)
	return p

static func _smoke(c: Dictionary, parent: Node3D, pos: Vector3, s: float, shade := 0.42) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 3.2
	p.randomness = 0.5
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0
	pm.gravity = Vector3(0.16 * s, 0.28 * s, 0)   # rises and drifts downwind
	pm.initial_velocity_min = 0.30 * s
	pm.initial_velocity_max = 0.55 * s
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08 * s
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var cur := Curve.new()                        # puffs swell as they age
	cur.add_point(Vector2(0.0, 0.35))
	cur.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = cur
	pm.scale_curve = ct
	pm.color_ramp = _grad([[0.0, Color(shade, shade, shade * 1.1, 0.0)],
			[0.15, Color(shade, shade, shade * 1.1, 0.32)],
			[1.0, Color(shade * 0.6, shade * 0.6, shade * 0.65, 0.0)]])
	p.process_material = pm
	p.draw_pass_1 = _puff_mesh(c, 0.55 * s, false)
	parent.add_child(p)
	return p

static func _boom_fx(c: Dictionary, parent: Node3D, pos: Vector3, s: float) -> Node3D:
	# One-shot explosion (fireball + flash + smoke), ARMED but not emitting — the caller
	# restart()s the children on its boom timer (see the animation contract up top).
	var nd := Node3D.new()
	nd.position = pos
	parent.add_child(nd)
	var ball := GPUParticles3D.new()
	ball.amount = 48
	ball.lifetime = 0.8
	ball.one_shot = true
	ball.emitting = false
	ball.explosiveness = 1.0
	ball.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var bm := ParticleProcessMaterial.new()
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 180.0
	bm.gravity = Vector3(0, 0.6 * s, 0)
	bm.initial_velocity_min = 2.0 * s
	bm.initial_velocity_max = 4.2 * s
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bm.emission_sphere_radius = 0.12 * s
	bm.scale_min = 0.6
	bm.scale_max = 1.4
	bm.color_ramp = _grad([[0.0, Color(1.0, 0.98, 0.85, 1.0)], [0.25, Color(1.0, 0.6, 0.15, 0.9)],
			[0.7, Color(0.85, 0.2, 0.05, 0.5)], [1.0, Color(0.3, 0.05, 0.02, 0.0)]])
	ball.process_material = bm
	ball.draw_pass_1 = _puff_mesh(c, 0.5 * s, true)
	nd.add_child(ball)
	var flash := GPUParticles3D.new()
	flash.amount = 3
	flash.lifetime = 0.22
	flash.one_shot = true
	flash.emitting = false
	flash.explosiveness = 1.0
	flash.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var fm := ParticleProcessMaterial.new()
	fm.gravity = Vector3.ZERO
	fm.initial_velocity_min = 0.0
	fm.initial_velocity_max = 0.0
	fm.color_ramp = _grad([[0.0, Color(1.0, 1.0, 0.92, 1.0)], [1.0, Color(1.0, 0.8, 0.4, 0.0)]])
	flash.process_material = fm
	flash.draw_pass_1 = _puff_mesh(c, 3.0 * s, true)
	nd.add_child(flash)
	var smk := GPUParticles3D.new()
	smk.amount = 24
	smk.lifetime = 3.0
	smk.one_shot = true
	smk.emitting = false
	smk.explosiveness = 1.0
	smk.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 35.0
	sm.gravity = Vector3(0.1 * s, 0.3 * s, 0)
	sm.initial_velocity_min = 0.7 * s
	sm.initial_velocity_max = 1.5 * s
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.1 * s
	sm.scale_min = 0.7
	sm.scale_max = 1.3
	sm.color_ramp = _grad([[0.0, Color(0.35, 0.33, 0.32, 0.0)], [0.12, Color(0.30, 0.28, 0.27, 0.4)],
			[1.0, Color(0.18, 0.17, 0.17, 0.0)]])
	smk.process_material = sm
	smk.draw_pass_1 = _puff_mesh(c, 0.7 * s, false)
	nd.add_child(smk)
	return nd

# ---------------------------------------------------------------- structures -----------
static func _city(c: Dictionary, x: float, y: float, span_x: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var r_m := span_x * 0.040
	# night-glow pool under the district (an additive glow quad flat on the ground)
	var gq := QuadMesh.new()
	gq.size = Vector2(2.6, 2.6) * r_m * float(c["upm"])
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = c["glow"]
	gm.albedo_color = Color(1.0, 0.72, 0.38, 0.15)
	_mi(c["out"], gq, gm, _gv(c, x, y, 8.0), Vector3(-90, 0, 0))
	var nt := 13 + rng.randi_range(0, 5)
	for i in nt:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * r_m
		var tx := x + cos(a) * rr
		var ty := y + sin(a) * rr
		var w := (0.28 + rng.randf() * 0.35) * k
		var hgt := (0.6 + rng.randf() * 1.7) * k * (1.25 - 0.6 * rr / maxf(r_m, 1.0))
		_mi(c["out"], _box(w, hgt, w * (0.8 + rng.randf() * 0.4)), _win_mat(c, i),
				_gv(c, tx, ty) + Vector3(0, hgt * 0.5 - 0.03, 0),
				Vector3(0, rng.randf() * 180.0, 0))
	for i in 10:                                    # a low-rise ring around downtown
		var a := TAU * i / 10.0 + rng.randf() * 0.3
		_house(c, x + cos(a) * r_m * 1.3, y + sin(a) * r_m * 1.3, rng.randf() * TAU)
	var bn := _site(c, x, y)                        # the aviation beacon downtown
	_mi(bn, _cyl(0.015 * k, 0.03 * k, 2.7 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(0, 1.35 * k, 0))
	var bcn := _mi(bn, _sph(0.06 * k),
			_m("beacon", Color(1.0, 0.25, 0.2), 0.6, 0.0, Color(1.0, 0.2, 0.15), 3.0),
			Vector3(0, 2.73 * k, 0))
	bcn.set_meta("blink_period", 1.4)
	(c["beac"] as Array).append(bcn)

static func _house(c: Dictionary, x: float, y: float, yaw := 0.0, sc := 1.0) -> void:
	var k: float = c["k"] * sc
	var rng: RandomNumberGenerator = c["rng"]
	var s := _site(c, x, y, yaw)
	_mi(s, _box(0.17 * k, 0.13 * k, 0.24 * k), _m("wall", Color(0.34, 0.31, 0.27)),
			Vector3(0, 0.055 * k, 0))
	_mi(s, _prism(0.19 * k, 0.09 * k, 0.26 * k), _m("roof", Color(0.26, 0.13, 0.10)),
			Vector3(0, 0.165 * k, 0))
	if rng.randf() < 0.45:                          # a lit window, warm against the night
		_mi(s, _box(0.012 * k, 0.045 * k, 0.06 * k),
				_m("winlit", Color(1.0, 0.8, 0.5), 0.6, 0.0, Color(1.0, 0.75, 0.42), 1.6),
				Vector3(0.088 * k, 0.06 * k, 0))

static func _village(c: Dictionary, x: float, y: float, span_x: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var sp := span_x * 0.016
	for i in 9:
		if i == 4:
			continue                                # the centre plot hosts the water tower
		var gx := x + (i % 3 - 1) * sp + (rng.randf() - 0.5) * sp * 0.5
		var gy := y + (floori(i / 3.0) - 1) * sp + (rng.randf() - 0.5) * sp * 0.5
		_house(c, gx, gy, PI * 0.5 * rng.randi_range(0, 3))
	var wt := _site(c, x, y)
	_mi(wt, _cyl(0.025 * k, 0.035 * k, 0.5 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(0, 0.25 * k, 0))
	_mi(wt, _cyl(0.10 * k, 0.10 * k, 0.14 * k), _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8),
			Vector3(0, 0.55 * k, 0))

static func _farm(c: Dictionary, x: float, y: float, span_x: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _site(c, x, y, rng.randf() * TAU)
	_mi(s, _box(0.28 * k, 0.20 * k, 0.42 * k), _m("barn", Color(0.38, 0.16, 0.12)),
			Vector3(0, 0.09 * k, 0))
	_mi(s, _prism(0.30 * k, 0.13 * k, 0.44 * k), _m("roof", Color(0.26, 0.13, 0.10)),
			Vector3(0, 0.255 * k, 0))
	_mi(s, _cyl(0.09 * k, 0.09 * k, 0.42 * k), _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8),
			Vector3(0.3 * k, 0.21 * k, 0))
	var cap := _sph(0.09 * k)
	cap.is_hemisphere = true
	_mi(s, cap, _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8), Vector3(0.3 * k, 0.42 * k, 0))
	_house(c, x + span_x * 0.008, y - span_x * 0.006, rng.randf() * TAU)
	# the field patchwork: one vertex-colored mesh of ground-hugging quads
	var pw := span_x * 0.028
	var ph := span_x * 0.020
	var palette := [Color(0.13, 0.22, 0.10), Color(0.18, 0.26, 0.11), Color(0.30, 0.28, 0.12),
			Color(0.36, 0.30, 0.14), Color(0.22, 0.17, 0.11)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 2:
		for col in 4:
			var fx := x + span_x * 0.02 + col * pw * 1.12
			var fy := y + span_x * 0.015 + (row - 1) * ph * 1.15
			st.set_color(palette[rng.randi_range(0, palette.size() - 1)])
			var v00 := _gv(c, fx, fy, 2.0)
			var v10 := _gv(c, fx + pw, fy, 2.0)
			var v01 := _gv(c, fx, fy + ph, 2.0)
			var v11 := _gv(c, fx + pw, fy + ph, 2.0)
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v00)
			st.add_vertex(v11)
			st.add_vertex(v01)
	var mesh := st.commit()
	mesh.surface_set_material(0, _lm())
	_mi(c["out"], mesh, null, Vector3.ZERO)

static func _refinery(c: Dictionary, x: float, y: float) -> void:
	var k: float = c["k"]
	var s := _site(c, x, y)
	_mi(s, _box(2.4 * k, 0.04 * k, 1.7 * k), _m("pad", Color(0.30, 0.31, 0.33), 0.95),
			Vector3(0, 0.02 * k, 0))
	for i in 3:                                     # the tank farm
		for j in 2:
			_mi(s, _cyl(0.28 * k, 0.28 * k, 0.26 * k), _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8),
					Vector3((-0.85 + i * 0.62) * k, 0.15 * k, (0.35 + j * 0.62 - 0.31) * k))
	for i in 3:                                     # distillation columns
		_mi(s, _cyl(0.07 * k, 0.07 * k, 1.15 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
				Vector3((-0.55 + i * 0.35) * k, 0.6 * k, -0.55 * k))
	_mi(s, _box(1.5 * k, 0.03 * k, 0.05 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(-0.2 * k, 0.24 * k, -0.25 * k))   # the pipe rack run
	_mi(s, _box(0.5 * k, 0.18 * k, 0.3 * k), _m("wall", Color(0.34, 0.31, 0.27)),
			Vector3(0.8 * k, 0.09 * k, 0.55 * k))
	var flare_x := 1.05 * k
	var flare_z := -0.6 * k
	_mi(s, _cyl(0.022 * k, 0.03 * k, 1.5 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(flare_x, 0.75 * k, flare_z))
	_fire(c, s, Vector3(flare_x, 1.53 * k, flare_z), 0.75 * k)     # the burning flare stack
	_smoke(c, s, Vector3(flare_x, 1.62 * k, flare_z), 0.9 * k, 0.30)
	for i in 4:                                     # sodium yard lights
		_mi(s, _sph(0.022 * k), _m("lamp", Color(1.0, 0.8, 0.55), 0.6, 0.0, Color(1.0, 0.72, 0.4), 2.0),
				Vector3((-1.0 + (i % 2) * 2.0) * k, 0.12 * k, (-0.7 + floori(i / 2.0) * 1.4) * k))

static func _factory(c: Dictionary, x: float, y: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _site(c, x, y, rng.randf() * TAU)
	_mi(s, _box(1.0 * k, 0.30 * k, 0.62 * k), _m("brick", Color(0.25, 0.15, 0.13)),
			Vector3(0, 0.14 * k, 0))
	for i in 3:                                     # the sawtooth roof
		_mi(s, _prism(0.30 * k, 0.13 * k, 0.62 * k), _m("roofdk", Color(0.14, 0.14, 0.16)),
				Vector3((-0.33 + i * 0.33) * k, 0.355 * k, 0))
	for i in 2:
		_mi(s, _cyl(0.045 * k, 0.055 * k, 0.85 * k), _m("brick", Color(0.25, 0.15, 0.13)),
				Vector3((-0.62 + i * 0.18) * k, 0.55 * k, -0.36 * k))
	_smoke(c, s, Vector3(-0.62 * k, 0.99 * k, -0.36 * k), 0.8 * k, 0.38)
	_smoke(c, s, Vector3(-0.44 * k, 0.99 * k, -0.36 * k), 0.6 * k, 0.44)
	for i in 3:                                     # yard crates
		_mi(s, _box(0.12 * k, 0.10 * k, 0.16 * k), _m("olive_dk", Color(0.16, 0.18, 0.12)),
				Vector3(0.62 * k, 0.05 * k, (-0.2 + i * 0.22) * k))
	_truck(c, s, Vector3(0.75 * k, 0, 0.35 * k), 1.2)

static func _airstrip(c: Dictionary, x: float, y: float, span_x: float) -> void:
	var k: float = c["k"]
	var half := span_x * 0.085
	_ribbon(c, Vector2(x - half, y), Vector2(x + half, y), clampf(span_x * 0.006, 40.0, 90.0),
			Color(0.16, 0.165, 0.175), 3.0, 0.06)
	var s := _site(c, x - half * 0.5, y + span_x * 0.012)
	var hang := _cyl(0.28 * k, 0.28 * k, 0.7 * k)   # a quonset hangar (cylinder on its side)
	_mi(s, hang, _m("hangar", Color(0.35, 0.37, 0.40), 0.7, 0.3), Vector3(0, 0.05 * k, 0),
			Vector3(90.0, 90.0, 0))
	var tw := _site(c, x + half * 0.4, y + span_x * 0.012)
	_mi(tw, _cyl(0.04 * k, 0.05 * k, 0.5 * k), _m("concrete", Color(0.42, 0.42, 0.44), 0.95),
			Vector3(0, 0.25 * k, 0))
	_mi(tw, _box(0.16 * k, 0.09 * k, 0.16 * k),
			_m("winlit", Color(1.0, 0.8, 0.5), 0.6, 0.0, Color(1.0, 0.75, 0.42), 1.6),
			Vector3(0, 0.54 * k, 0))

static func _sam(c: Dictionary, x: float, y: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _site(c, x, y, rng.randf() * TAU)
	var berm := TorusMesh.new()                     # the earth revetment ring
	berm.inner_radius = 0.55 * k
	berm.outer_radius = 0.85 * k
	berm.rings = 24
	berm.ring_segments = 12
	var bmi := _mi(s, berm, _m("earth", Color(0.22, 0.18, 0.12), 1.0), Vector3(0, 0.02 * k, 0))
	bmi.scale = Vector3(1, 0.28, 1)
	_mi(s, _cyl(0.5 * k, 0.5 * k, 0.05 * k), _m("pad", Color(0.30, 0.31, 0.33), 0.95),
			Vector3(0, 0.025 * k, 0))
	for i in 4:                                     # four canted launch tubes
		var lx := (-0.16 + 0.32 * (i % 2)) * k
		var lz := (-0.16 + 0.32 * floori(i / 2.0)) * k
		_mi(s, _box(0.14 * k, 0.05 * k, 0.20 * k), _m("olive", Color(0.24, 0.27, 0.18)),
				Vector3(lx, 0.07 * k, lz))
		_mi(s, _cyl(0.045 * k, 0.045 * k, 0.55 * k), _m("olive_dk", Color(0.16, 0.18, 0.12)),
				Vector3(lx + 0.08 * k, 0.28 * k, lz), Vector3(0, 0, -55.0))
	_mi(s, _box(0.14 * k, 0.10 * k, 0.14 * k), _m("olive", Color(0.24, 0.27, 0.18)),
			Vector3(-0.36 * k, 0.05 * k, -0.02 * k))
	_mi(s, _box(0.02 * k, 0.16 * k, 0.16 * k), _m("olive_dk", Color(0.16, 0.18, 0.12)),
			Vector3(-0.30 * k, 0.16 * k, -0.02 * k), Vector3(0, 0, -20.0))  # the engagement panel
	_mi(s, _box(0.20 * k, 0.10 * k, 0.12 * k), _m("olive", Color(0.24, 0.27, 0.18)),
			Vector3(0.02 * k, 0.05 * k, -0.40 * k))  # crew cabin / generator

static func _radar_site(c: Dictionary, x: float, y: float) -> void:
	var k: float = c["k"]
	var s := _site(c, x, y)
	_mi(s, _box(0.22 * k, 0.12 * k, 0.16 * k), _m("olive", Color(0.24, 0.27, 0.18)),
			Vector3(0.22 * k, 0.055 * k, 0))
	_mi(s, _cyl(0.035 * k, 0.05 * k, 0.7 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(0, 0.35 * k, 0))
	var head := Node3D.new()                        # the spinning antenna head
	head.position = Vector3(0, 0.74 * k, 0)
	s.add_child(head)
	_mi(head, _box(0.05 * k, 0.08 * k, 0.05 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3.ZERO)
	_mi(head, _cyl(0.34 * k, 0.04 * k, 0.10 * k), _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8),
			Vector3(0, 0.09 * k, 0.05 * k), Vector3(-65.0, 0, 0))
	head.set_meta("spin_axis", Vector3(0, 1, 0))
	head.set_meta("spin_rate", 1.3)
	(c["spin"] as Array).append(head)
	var bcn := _mi(s, _sph(0.03 * k),
			_m("beacon", Color(1.0, 0.25, 0.2), 0.6, 0.0, Color(1.0, 0.2, 0.15), 3.0),
			Vector3(0, 0.92 * k, 0))
	bcn.set_meta("blink_period", 1.0)
	(c["beac"] as Array).append(bcn)

static func _comms_tower(c: Dictionary, x: float, y: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _site(c, x, y)
	_mi(s, _cyl(0.015 * k, 0.06 * k, 1.5 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
			Vector3(0, 0.75 * k, 0))
	for i in 3:                                     # microwave drums up the mast
		_mi(s, _cyl(0.05 * k, 0.05 * k, 0.03 * k), _m("silver", Color(0.72, 0.74, 0.78), 0.35, 0.8),
				Vector3(0.05 * k, (0.9 + i * 0.2) * k, 0),
				Vector3(0, rng.randf() * 180.0, 90.0))
	var bcn := _mi(s, _sph(0.035 * k),
			_m("beacon", Color(1.0, 0.25, 0.2), 0.6, 0.0, Color(1.0, 0.2, 0.15), 3.0),
			Vector3(0, 1.53 * k, 0))
	bcn.set_meta("blink_period", 0.9)
	(c["beac"] as Array).append(bcn)

static func _windfarm(c: Dictionary, x: float, y: float, span_x: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var sp := span_x * 0.028
	for i in 4:
		_turbine(c, x + (i - 1.5) * sp, y + (rng.randf() - 0.5) * sp * 0.6)

static func _turbine(c: Dictionary, x: float, y: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _site(c, x, y, rng.randf() * TAU)
	_mi(s, _cyl(0.028 * k, 0.05 * k, 1.4 * k), _m("white", Color(0.80, 0.81, 0.83), 0.6),
			Vector3(0, 0.7 * k, 0))
	_mi(s, _box(0.16 * k, 0.08 * k, 0.08 * k), _m("white", Color(0.80, 0.81, 0.83), 0.6),
			Vector3(0.02 * k, 1.42 * k, 0))
	var rotor := Node3D.new()
	rotor.position = Vector3(0.11 * k, 1.42 * k, 0)
	s.add_child(rotor)
	_mi(rotor, _sph(0.045 * k), _m("white", Color(0.80, 0.81, 0.83), 0.6), Vector3.ZERO)
	for j in 3:
		var pivot := Node3D.new()
		pivot.rotation_degrees = Vector3(120.0 * j, 0, 0)
		rotor.add_child(pivot)
		_mi(pivot, _box(0.012 * k, 0.62 * k, 0.035 * k), _m("white", Color(0.80, 0.81, 0.83), 0.6),
				Vector3(0, 0.31 * k, 0))
	rotor.set_meta("spin_axis", Vector3(1, 0, 0))
	rotor.set_meta("spin_rate", 1.2 + rng.randf() * 0.8)
	(c["spin"] as Array).append(rotor)

static func _range(c: Dictionary, x: float, y: float) -> void:
	# The live-fire range — sited FARTHEST from the LOS corridor so the periodic burst
	# can never read as part of the lesson. Craters, two charred hulks, a repeating boom.
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var e: Array = c["e"]
	var jit := (float(e[1]) - float(e[0])) * 0.008
	for i in 3:
		var cx := x + (rng.randf() - 0.5) * jit * 2.0
		var cy := y + (rng.randf() - 0.5) * jit * 2.0
		_mi(c["out"], _cyl((0.18 + rng.randf() * 0.14) * k, (0.2 + rng.randf() * 0.14) * k, 0.015 * k),
				_m("crater", Color(0.05, 0.05, 0.05), 1.0), _gv(c, cx, cy, 1.5))
	_tank(c, x + jit, y - jit, rng.randf() * TAU, "charred")
	_tank(c, x - jit, y + jit * 0.6, rng.randf() * TAU, "charred")
	var boom := _boom_fx(c, c["out"], _gv(c, x, y, 4.0), k)
	boom.set_meta("boom_period", 6.0 + rng.randf() * 5.0)
	boom.set_meta("boom_t", 2.0 + rng.randf() * 4.0)
	(c["boom"] as Array).append(boom)

static func _wreck(c: Dictionary, x: float, y: float) -> void:
	var rng: RandomNumberGenerator = c["rng"]
	var k: float = c["k"]
	var s := _tank(c, x, y, rng.randf() * TAU, "charred")
	_fire(c, s, Vector3(0, 0.18 * k, 0), 0.5 * k)
	_smoke(c, s, Vector3(0, 0.26 * k, 0), 0.9 * k, 0.22)

static func _tank(c: Dictionary, x: float, y: float, yaw: float, key := "olive") -> Node3D:
	var k: float = c["k"] * 0.9
	var hull := _m(key, Color(0.24, 0.27, 0.18) if key == "olive" else Color(0.06, 0.06, 0.06),
			1.0 if key == "charred" else 0.95)
	var s := _site(c, x, y, yaw)
	for dz in [-0.10, 0.10]:
		_mi(s, _box(0.50 * k, 0.07 * k, 0.07 * k), _m("track", Color(0.10, 0.10, 0.10), 1.0),
				Vector3(0, 0.035 * k, dz * k))
	_mi(s, _box(0.46 * k, 0.08 * k, 0.18 * k), hull, Vector3(0, 0.10 * k, 0))
	_mi(s, _cyl(0.08 * k, 0.08 * k, 0.06 * k), hull, Vector3(-0.04 * k, 0.17 * k, 0))
	_mi(s, _cyl(0.013 * k, 0.013 * k, 0.30 * k), hull, Vector3(0.16 * k, 0.17 * k, 0),
			Vector3(0, 0, -90.0))
	return s

static func _truck(c: Dictionary, parent: Node3D, local: Vector3, sc := 1.0) -> void:
	var k: float = c["k"] * 0.9 * sc
	var nd := Node3D.new()
	nd.position = local
	parent.add_child(nd)
	_mi(nd, _box(0.20 * k, 0.09 * k, 0.11 * k), _m("olive_dk", Color(0.16, 0.18, 0.12)),
			Vector3(-0.03 * k, 0.09 * k, 0))
	_mi(nd, _box(0.07 * k, 0.08 * k, 0.10 * k), _m("olive", Color(0.24, 0.27, 0.18)),
			Vector3(0.12 * k, 0.085 * k, 0))
	for dz in [-0.03, 0.03]:
		_mi(nd, _sph(0.013 * k), _m("lamp", Color(1.0, 0.8, 0.55), 0.6, 0.0, Color(1.0, 0.72, 0.4), 2.0),
				Vector3(0.16 * k, 0.07 * k, dz * k))

static func _column(c: Dictionary, a: Vector2, b: Vector2) -> void:
	# A tank platoon road-marching toward the SAM site, staggered off the centreline.
	var rng: RandomNumberGenerator = c["rng"]
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var off := a.distance_to(b) * 0.012
	for i in 5:
		var p := a.lerp(b, 0.30 + 0.42 * i / 4.0) + perp * (off if i % 2 == 0 else -off)
		_tank(c, p.x, p.y, atan2(dir.y, dir.x) + (rng.randf() - 0.5) * 0.2)

static func _convoy(c: Dictionary, a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var off := a.distance_to(b) * 0.010
	for i in 4:
		var p := a.lerp(b, 0.35 + 0.30 * i / 3.0) + perp * off
		var s := _site(c, p.x, p.y, atan2(dir.y, dir.x))
		_truck(c, s, Vector3.ZERO)

# ---------------------------------------------------------------- lines ----------------
static func _ribbon(c: Dictionary, a: Vector2, b: Vector2, w_m: float, col: Color,
		up_m: float, jitter: float) -> void:
	# A terrain-hugging strip (roads, the runway): sampled along the path, each quad
	# grounded on the SAME handshake heightfield the terrain mesh uses.
	var rng: RandomNumberGenerator = c["rng"]
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var steps := maxi(int(L / 120.0), 2)
	var dir := (b - a).normalized()
	var pp := Vector2(-dir.y, dir.x) * (w_m * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var p := a.lerp(b, i / float(steps))
		var vl := _gv(c, p.x + pp.x, p.y + pp.y, up_m)
		var vr := _gv(c, p.x - pp.x, p.y - pp.y, up_m)
		if i > 0:
			st.set_color(col.darkened(rng.randf() * jitter))
			st.add_vertex(prev_l)
			st.add_vertex(prev_r)
			st.add_vertex(vl)
			st.add_vertex(vr)
			st.add_vertex(vl)
			st.add_vertex(prev_r)
		prev_l = vl
		prev_r = vr
	var mesh := st.commit()
	mesh.surface_set_material(0, _lm())
	_mi(c["out"], mesh, null, Vector3.ZERO)

static func _powerline(c: Dictionary, a: Vector2, b: Vector2) -> void:
	var k: float = c["k"]
	var dir := (b - a).normalized()
	var yaw := atan2(dir.y, dir.x)
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var n_p := maxi(int(L / 700.0), 2)
	# the display-space perpendicular (crossarm direction) — measured through to3d
	var o3: Vector3 = c["to3d"].call([0.0, 0.0, 0.0])
	var dperp: Vector3 = (c["to3d"].call([-dir.y * 100.0, dir.x * 100.0, 0.0]) - o3).normalized()
	var tips_l: Array = []
	var tips_r: Array = []
	for i in n_p + 1:
		var p := a.lerp(b, i / float(n_p))
		var s := _site(c, p.x, p.y, yaw)
		_mi(s, _cyl(0.02 * k, 0.035 * k, 0.6 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
				Vector3(0, 0.3 * k, 0))
		_mi(s, _box(0.03 * k, 0.03 * k, 0.40 * k), _m("steel", Color(0.55, 0.58, 0.62), 0.45, 0.7),
				Vector3(0, 0.56 * k, 0))
		var top := _gv(c, p.x, p.y) + Vector3(0, 0.56 * k, 0)
		tips_l.append(top + dperp * 0.18 * k)
		tips_r.append(top - dperp * 0.18 * k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(0.72, 0.75, 0.82, 0.75))
	for arr in [tips_l, tips_r]:
		for i in arr.size() - 1:
			var pv: Vector3 = arr[i]
			for j in range(1, 9):                   # sagging catenary, 8 segments per span
				var t := j / 8.0
				var q: Vector3 = (arr[i] as Vector3).lerp(arr[i + 1], t) \
						- Vector3(0, 0.08 * k * 4.0 * t * (1.0 - t), 0)
				st.add_vertex(pv)
				st.add_vertex(q)
				pv = q
	var mesh := st.commit()
	mesh.surface_set_material(0, _lm())
	_mi(c["out"], mesh, null, Vector3.ZERO)

static func _pipeline(c: Dictionary, a: Vector2, b: Vector2) -> void:
	# An elevated trunk line running from the refinery off the map edge, with supports.
	var k: float = c["k"]
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var steps := maxi(int(L / 250.0), 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(0.62, 0.60, 0.55, 0.9))
	var prev := _gv(c, a.x, a.y, 6.0)
	for i in range(1, steps + 1):
		var p := a.lerp(b, i / float(steps))
		var v := _gv(c, p.x, p.y, 6.0)
		st.add_vertex(prev)
		st.add_vertex(v)
		if i % 2 == 0:
			st.add_vertex(v)
			st.add_vertex(_gv(c, p.x, p.y))
		prev = v
	var mesh := st.commit()
	mesh.surface_set_material(0, _lm())
	_mi(c["out"], mesh, null, Vector3.ZERO)
	var mid := a.lerp(b, 0.5)                       # the pump station
	var s := _site(c, mid.x, mid.y)
	_mi(s, _box(0.18 * k, 0.10 * k, 0.14 * k), _m("wall", Color(0.34, 0.31, 0.27)),
			Vector3(0, 0.045 * k, 0.10 * k))
