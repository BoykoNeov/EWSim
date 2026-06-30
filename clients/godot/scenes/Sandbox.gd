extends Node2D
# Sandbox.gd — the EWSim spatial/CFAR client (HANDOFF §8). Connects to the Julia server
# (tools/server.jl) via SimClient, builds its sliders from the `scenario` handshake (so the
# YAML knob list is the single source of truth), and renders the live `state` stream. Slider
# drags send `set_param` — the §5 universal knob channel — so moving a knob changes the
# physics live.
#
# This is a PURE CLIENT: zero physics. It draws what the core says and writes knobs back;
# everything else (SNR, Pd, the detection draw, the CFAR threshold curve) is the core's truth.
#
# TWO render modes, chosen ONCE from the handshake (advisor: the paths share no state and
# never interleave):
#   • "spatial" (slice 1/2) — a 2-D elevation slice: screen-x downrange (world +X, target
#     closing from the right), screen-y altitude (world +Z, up). World Y is 0, so this shows
#     the two coords that move. Radar + target marker + a detection-blip ring per event.
#   • "cfar" (slice 3) — a range-power profile plot: x is range (the core's static range
#     axis from the handshake), y is power in dB. The drawn profile, the CFAR threshold curve
#     (CORE output, never recomputed here), and a marker per detected cell. The fidelity
#     button cycles the cfar rung (fixed→ca→go→so→os) instead of the binary prop toggle.
#   • "geoloc" (slice 5) — a top-down x-y PLAN view (the elevation x-z view can't show a 2-D
#     bearing-crossing geometry or a ground-plane ellipse): DF sensor markers + their measured
#     bearing RAYS (the LOPs), the emitter truth, the C2 station, the position FIX, and the
#     error ELLIPSE (all core output / telemetry). The fidelity button cycles the estimator
#     rung (pseudolinear↔ml).
# A handshake shipping `range_axis_m` selects "cfar"; one whose fidelity carries `estimator`
# selects "geoloc"; otherwise "spatial".

const HOST := "127.0.0.1"
const PORT := 8765
const MARGIN := 64.0
const BLIP_TTL := 1.6            # s a detection blip lingers before fading out
const TARGET_R := 7.0            # px radius of the target marker
# preload, NOT `class_name SimClient`: the global class cache isn't built on a
# headless/fresh load, so a bare type reference fails to resolve there. preload
# binds the script directly and works in the editor and headless alike.
const SimClientScript := preload("res://net/SimClient.gd")

var _client
var _font: Font

# --- live world mirror (rebuilt each `state` frame; the core owns the truth) ---
var _entities := {}              # id -> {kind:String, pos:Array[float] (x,y,z meters)}
var _telemetry := {}             # flat "key" -> number/bool (HANDOFF §5)
var _blips: Array = []           # [{pos:Vector2 (screen), age:float}]
var _radar_id := ""              # discovered from the first radar entity
var _x_max := 45000.0            # downrange span shown, m (auto-expands)
var _z_max := 5000.0             # altitude span shown, m (auto-expands)

# --- UI (built in code so the .tscn stays a trivial root node) ---
var _status: Label
var _readout: Label
var _badge: Label
var _knob_box: VBoxContainer
var _play_btn: Button
var _prop_btn: Button             # propagation fidelity toggle (sends set_fidelity)
var _running := false
# Live local copy of the world fidelity map: the §12 badge's source AND the toggle's
# state. The server applies set_fidelity silently (no handshake reply), and a `reset`
# reloads the YAML server-side without a new handshake either — so the client owns the
# displayed fidelity and resyncs itself. _fidelity_default is the scenario default the
# toggle reverts to on reset.
var _fidelity := {}
var _fidelity_default := {}

# --- CFAR range-power view (slice 3): populated only when the handshake ships a range axis.
# `_mode` switches the whole render path AND the fidelity-toggle button. The spatial mirror
# (_entities/_blips) and the cfar mirror (_profile_db/...) are disjoint — only one is live.
var _mode := "spatial"            # "spatial" (slice 1/2/4) | "cfar" (slice 3) | "geoloc" (slice 5)
var _cfar_radar := ""             # radar id whose "<id>.profile_db" etc. we render
var _range_axis: Array = []       # per-cell slant range (m) — handshake, core output
var _n_cells := 0
var _dr_m := 0.0
var _profile_db: Array = []       # per-cell power (dB), the noisy profile — per frame
var _threshold_db: Array = []     # per-cell CFAR threshold (dB) — CORE output, never recomputed here
var _detections: Array = []       # per-cell bool — cells the active rung flagged this look
var _cfar_y_hi := 35.0            # top of the dB axis (auto-expands to fit a tall return)
const CFAR_RUNGS := ["fixed", "ca", "go", "so", "os"]
# Which fidelity the shared toggle button drives — decided ONCE from the handshake: "cfar"
# (slice 3, range_axis present), "ep" (slice 4, an `ep` fidelity), else "propagation" (slice
# 1/2). The render `_mode` stays "spatial" for slice 4 (no range axis); only the button differs.
var _fid_kind := "propagation"
const EP_RUNGS := ["none", "freq_agility", "sidelobe_blanking"]
const EST_RUNGS := ["pseudolinear", "ml"]   # slice-5 estimator cycler (the §12 badge button)
const CFAR_Y_LO := -15.0          # bottom of the dB axis (noise floor ≈ 0 dB; deep nulls clamp)
const PLOT_L := 70.0              # plot rect insets (px) — left edge clears the first range label,
const PLOT_T := 120.0             # top clears the UI panel, bottom leaves room for range labels
const PLOT_R := 44.0              # right gutter holds the dB axis labels (left is the UI panel)
const PLOT_B := 48.0

# --- geoloc plan view (slice 5): top-down x-y. Populated only when the handshake fidelity carries
# `estimator`. Sensors/emitter/station ride the normal _entities mirror (drawn from their pos); the
# fix/ellipse/gdop come from <station>.* telemetry. The world↔plan mapping uses EQUAL aspect (a
# single px/m scale for both axes) so the error ellipse renders un-distorted; it's recomputed each
# frame into these members so _world_to_plan can stay a plain helper.
const PLAN_M := 92.0              # plan-view margin (px) — leaves room for the left UI panel + labels
var _df_station := ""             # station id whose fix/ellipse telemetry we render
var _plan_view := Rect2()         # the plot rect (screen px)
var _plan_b := Rect2()            # the world-space bounding box (m) currently shown
var _plan_sc := 1.0               # px per metre (equal aspect)

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build_ui()
	_client = SimClientScript.new()
	add_child(_client)
	_client.connected.connect(func() -> void: _status.text = "connected — waiting for scenario…")
	_client.disconnected.connect(func() -> void: _status.text = "disconnected (server serves one client, then exits)")
	_client.frame_received.connect(_on_frame)
	_status.text = "connecting to %s:%d …" % [HOST, PORT]
	_client.start(HOST, PORT)
	get_viewport().size_changed.connect(_layout_badge)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	var panel := VBoxContainer.new()
	panel.position = Vector2(12, 12)
	panel.add_theme_constant_override("separation", 6)
	ui.add_child(panel)

	_status = Label.new()
	panel.add_child(_status)

	var row := HBoxContainer.new()
	panel.add_child(row)
	_play_btn = Button.new()
	_play_btn.text = "Pause"
	_play_btn.pressed.connect(_on_play_pressed)
	row.add_child(_play_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(_on_reset_pressed)
	row.add_child(reset_btn)
	# Slice-2 live fidelity toggle: flips the `propagation` rung (free_space ↔ two_ray)
	# via set_fidelity. Label is filled from the handshake fidelity; "…" until then.
	_prop_btn = Button.new()
	_prop_btn.text = "prop: …"
	_prop_btn.tooltip_text = "Toggle propagation fidelity (set_fidelity): free_space ↔ two_ray"
	_prop_btn.pressed.connect(_on_prop_pressed)
	row.add_child(_prop_btn)

	_knob_box = VBoxContainer.new()
	_knob_box.add_theme_constant_override("separation", 4)
	panel.add_child(_knob_box)

	# Live SNR/Pd readout — kept prominent because at the 42 km cold start Pd is
	# near zero and no blip fires for a while; this is what shows the view is alive.
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 18)
	panel.add_child(_readout)

	# §12: a visible "<fidelity> approximation" badge in every view. Text is filled
	# from the handshake's actual fidelity map, never hardcoded.
	_badge = Label.new()
	_badge.modulate = Color(1, 1, 1, 0.7)
	ui.add_child(_badge)
	_layout_badge()

func _layout_badge() -> void:
	if _badge == null:
		return
	var vp := get_viewport_rect().size
	_badge.position = Vector2(12, vp.y - 26)

# --- frame handling -----------------------------------------------------------

func _on_frame(obj: Dictionary) -> void:
	match str(obj.get("type", "")):
		"scenario":
			_on_scenario(obj)
		"state":
			_on_state(obj)
		"error":
			_status.text = "server error: " + str(obj.get("message", "?"))
		_:
			pass  # `artifact` etc. — not used by the spatial view

func _on_scenario(obj: Dictionary) -> void:
	_status.text = "running: " + str(obj.get("name", "scenario"))
	_build_knobs(obj.get("knobs", []))
	# The fidelity map is the badge source and the toggle's state. Keep the scenario
	# default so a `reset` (which reverts the server to the YAML, with no new handshake)
	# can resync the client unilaterally.
	_fidelity = (obj.get("fidelity", {}) as Dictionary).duplicate()
	_fidelity_default = _fidelity.duplicate()
	# A CFAR scenario ships a STATIC range axis in the handshake (core output, §1/§8); that
	# presence flips the client into the range-power view. A slice-1/2 scenario omits it and
	# stays the spatial elevation view. Decide the mode ONCE here — the two render paths never
	# interleave after this.
	if obj.has("range_axis_m"):
		_enter_cfar_mode(obj)
	elif _fidelity.has("estimator"):
		_enter_geoloc_mode(obj)
	else:
		_mode = "spatial"
		_setup_spatial_fid_btn()
	_render_badge()
	_update_fid_btn()
	# Server boots PAUSED; start running so there is something to watch.
	_set_running(true)

func _enter_cfar_mode(obj: Dictionary) -> void:
	# Adopt the static range axis + which radar's telemetry arrays to render, then repurpose
	# the fidelity-toggle button as the CFAR rung cycler. The spatial path's binary prop toggle
	# (_on_prop_pressed, wired in _build_ui) is swapped for _on_cfar_pressed. The disconnect is
	# guarded so the headless UI test — which builds the button without _build_ui's connect —
	# doesn't error.
	_mode = "cfar"
	_fid_kind = "cfar"
	_cfar_radar = str(obj.get("radar", ""))
	_range_axis = obj.get("range_axis_m", [])
	_n_cells = int(obj.get("n_cells", _range_axis.size()))
	_dr_m = float(obj.get("dr_m", 0.0))
	if _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.disconnect(_on_prop_pressed)
	if not _prop_btn.pressed.is_connected(_on_cfar_pressed):
		_prop_btn.pressed.connect(_on_cfar_pressed)
	_prop_btn.tooltip_text = "Cycle CFAR rung (set_fidelity): fixed → ca → go → so → os"

func _setup_spatial_fid_btn() -> void:
	# Spatial view (slice 1/2/4): the shared button drives `ep` if the scenario carries one
	# (slice 4 — no `propagation`, so the button is unambiguously the EP cycler, advisor catch),
	# else `propagation` (slice 1/2, the binary toggle wired in _build_ui). The disconnect is
	# guarded so the headless UI tests — which build the button without _build_ui's connect —
	# don't error, exactly like _enter_cfar_mode.
	if _fidelity.has("ep"):
		_fid_kind = "ep"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_ep_pressed):
			_prop_btn.pressed.connect(_on_ep_pressed)
		_prop_btn.tooltip_text = "Cycle EP (set_fidelity): none → freq_agility → sidelobe_blanking"
	else:
		_fid_kind = "propagation"

func _enter_geoloc_mode(_obj: Dictionary) -> void:
	# Slice-5 DF: a handshake whose fidelity carries `estimator` (and NO range_axis_m) flips the
	# client into the top-down PLAN view and repurposes the shared fidelity button as the estimator
	# cycler. The spatial path's binary prop toggle (_on_prop_pressed, wired in _build_ui) is swapped
	# for _on_est_pressed; the disconnect is guarded so the headless UI test — which builds the button
	# without _build_ui's connect — doesn't error, exactly like _enter_cfar_mode / _setup_spatial_fid_btn.
	_mode = "geoloc"
	_fid_kind = "geoloc"
	if _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.disconnect(_on_prop_pressed)
	if not _prop_btn.pressed.is_connected(_on_est_pressed):
		_prop_btn.pressed.connect(_on_est_pressed)
	_prop_btn.tooltip_text = "Cycle estimator (set_fidelity): pseudolinear ↔ ml"

func _render_badge() -> void:
	# §12: a visible "<fidelity> approximation" badge, built from the live local fidelity
	# map (never hardcoded), re-rendered whenever the propagation toggle changes it.
	var parts := PackedStringArray()
	for k in _fidelity.keys():
		parts.append("%s: %s" % [k, _fidelity[k]])
	parts.sort()
	_badge.text = "approximation — " + (" · ".join(parts) if not parts.is_empty() else "unspecified")

func _update_fid_btn() -> void:
	# Kind-aware label for the shared fidelity button: the cfar rung (slice 3), the ep rung
	# (slice 4), or the propagation rung (slice 1/2) — keyed off `_fid_kind`, decided at handshake.
	match _fid_kind:
		"cfar":
			_prop_btn.text = "cfar: %s" % str(_fidelity.get("cfar", "?"))
		"ep":
			_prop_btn.text = "ep: %s" % str(_fidelity.get("ep", "?"))
		"geoloc":
			_prop_btn.text = "est: %s" % str(_fidelity.get("estimator", "?"))
		_:
			_update_prop_btn()

func _update_prop_btn() -> void:
	_prop_btn.text = "prop: %s" % str(_fidelity.get("propagation", "?"))

func _on_cfar_pressed() -> void:
	# Advance the cfar rung one step round the ring (fixed→ca→go→so→os→fixed) and tell the core
	# (set_fidelity — the slice-2 live toggle, generalised). The server applies it silently on
	# the next look (no reply), so the client owns the displayed rung: update badge + button
	# locally. The rung changes ONLY the thresholding rule, never the draw, so a mid-run cycle
	# is bit-identical (the slice-3 determinism contract).
	var cur := str(_fidelity.get("cfar", "ca"))
	var i := CFAR_RUNGS.find(cur)
	var next: String = CFAR_RUNGS[(i + 1) % CFAR_RUNGS.size()] if i >= 0 else "ca"
	_fidelity["cfar"] = next
	_client.send({"type": "set_fidelity", "key": "cfar", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_prop_pressed() -> void:
	# Flip the propagation rung and tell the core (set_fidelity — the slice-2 live toggle).
	# Update the badge + button locally; the server applies it on the next tick with no
	# reply, so the client owns the displayed state.
	var cur := str(_fidelity.get("propagation", "two_ray"))
	var next := "free_space" if cur == "two_ray" else "two_ray"
	_fidelity["propagation"] = next
	_client.send({"type": "set_fidelity", "key": "propagation", "value": next})
	_render_badge()
	_update_prop_btn()

func _on_ep_pressed() -> void:
	# Advance the EP rung one step round the ring (none→freq_agility→sidelobe_blanking→none) and
	# tell the core (set_fidelity — the slice-2 live toggle, generalised; `ep` is introduce-safe
	# so the server accepts it even if the scenario started at :none). EP changes only the
	# detection BOOLEANS / the jnr_db·js_db readout, never the draw stream — so a mid-run cycle
	# is bit-identical (slice-4 is slice-2-shaped, not slice-3's draw-flip). The client owns the
	# displayed rung: update badge + button locally (the server applies it silently, no reply).
	var cur := str(_fidelity.get("ep", "none"))
	var i := EP_RUNGS.find(cur)
	var next: String = EP_RUNGS[(i + 1) % EP_RUNGS.size()] if i >= 0 else "none"
	_fidelity["ep"] = next
	_client.send({"type": "set_fidelity", "key": "ep", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_est_pressed() -> void:
	# Advance the estimator rung (pseudolinear↔ml) and tell the core (set_fidelity). `:estimator`
	# is introduce-safe AND draw-free (each DFSensor draws one randn/look regardless of rung), so a
	# mid-run cycle is bit-identical (the slice-4 :ep contract, NOT slice-3's draw-flip): only the
	# Geolocator's post-processing changes — the fix walks toward truth under ml. The client owns the
	# displayed rung: update badge + button locally (the server applies it silently, no reply).
	var cur := str(_fidelity.get("estimator", "pseudolinear"))
	var i := EST_RUNGS.find(cur)
	var next: String = EST_RUNGS[(i + 1) % EST_RUNGS.size()] if i >= 0 else "pseudolinear"
	_fidelity["estimator"] = next
	_client.send({"type": "set_fidelity", "key": "estimator", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_state(obj: Dictionary) -> void:
	_telemetry = obj.get("telemetry", {})
	if _mode == "cfar":
		_cfar_on_state()
	elif _mode == "geoloc":
		_geoloc_on_state(obj)
	else:
		_spatial_on_state(obj)
	_update_readout()
	queue_redraw()

func _geoloc_on_state(obj: Dictionary) -> void:
	# Mirror the entity list (sensors/emitter/station drawn from their pos) and note which station's
	# fix/ellipse telemetry to render. No blips, no spatial extents — the plan view recomputes its
	# own world bounds each draw. The fix/ellipse/gdop all arrive as scalar telemetry (no arrays).
	_entities.clear()
	for e in obj.get("entities", []):
		var id := str(e.get("id", ""))
		_entities[id] = {"kind": str(e.get("kind", "")), "pos": e.get("pos", [0, 0, 0])}
		if str(e.get("kind", "")) == "df_station" and _df_station == "":
			_df_station = id

func _spatial_on_state(obj: Dictionary) -> void:
	_entities.clear()
	for e in obj.get("entities", []):
		var id := str(e.get("id", ""))
		var pos: Array = e.get("pos", [0, 0, 0])
		_entities[id] = {"kind": str(e.get("kind", "")), "pos": pos}
		if str(e.get("kind", "")) == "radar" and _radar_id == "":
			_radar_id = id
		_x_max = max(_x_max, absf(float(pos[0])) * 1.08)
		_z_max = max(_z_max, float(pos[2]) * 1.15)

	# Drop a blip at the detected target's current screen position. The event
	# carries `of` (the target id) but no position; the entity's pos this frame is
	# within emit_every·dt (~16 ms) of when it fired — close enough for a blip.
	for ev in obj.get("events", []):
		if str(ev.get("kind", "")) == "detection":
			var of := str(ev.get("of", ""))
			if _entities.has(of):
				_blips.append({"pos": _world_to_screen(_entities[of].pos), "age": 0.0})

func _cfar_on_state() -> void:
	# Pull the per-cell arrays the core shipped (the threshold curve is CORE output — we plot
	# it, never recompute α here, HANDOFF §1). Auto-expand the dB axis so a tall target/clutter
	# return stays on screen.
	_profile_db   = _telemetry.get(_cfar_radar + ".profile_db", [])
	_threshold_db = _telemetry.get(_cfar_radar + ".threshold_db", [])
	_detections   = _telemetry.get(_cfar_radar + ".detections", [])
	for v in _profile_db:
		_cfar_y_hi = max(_cfar_y_hi, float(v) + 4.0)
	for v in _threshold_db:
		_cfar_y_hi = max(_cfar_y_hi, float(v) + 4.0)

func _update_readout() -> void:
	if _telemetry.is_empty():
		_readout.text = ""
		return
	var keys := _telemetry.keys()
	keys.sort()
	var lines := PackedStringArray()
	for k in keys:
		var v = _telemetry[k]
		if v is Array:
			continue                # CFAR profile/threshold/detections arrays render in _draw, not as text
		if v is bool:
			lines.append("%s: %s" % [k, "YES" if v else "no"])
		else:
			lines.append("%s: %.2f" % [k, float(v)])
	_readout.text = "\n".join(lines)

# --- knobs (sliders built from the handshake; drag → set_param) ---------------

func _build_knobs(knobs: Array) -> void:
	for c in _knob_box.get_children():
		c.queue_free()
	for k in knobs:
		var lo := float(k.get("min", 0.0))
		var hi := float(k.get("max", 1.0))
		var cur := float(k.get("value", lo))
		var target := str(k.get("target", ""))
		var key := str(k.get("key", ""))

		var name_lbl := Label.new()
		name_lbl.text = str(k.get("label", key))
		_knob_box.add_child(name_lbl)

		var row := HBoxContainer.new()
		_knob_box.add_child(row)
		var slider := HSlider.new()
		slider.min_value = lo
		slider.max_value = hi
		slider.custom_minimum_size = Vector2(190, 0)
		if bool(k.get("log", false)):
			slider.exp_edit = true        # log-feel slider (built-in); needs min > 0
			slider.step = 0.0             # continuous
		else:
			slider.step = (hi - lo) / 200.0
		slider.value = cur                # open at the live value (handshake `value`)
		row.add_child(slider)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(64, 0)
		val_lbl.text = _fmt(cur)
		row.add_child(val_lbl)

		slider.value_changed.connect(
			func(v: float) -> void:
				val_lbl.text = _fmt(v)
				_client.send({"type": "set_param", "target": target, "key": key, "value": v})
		)

func _fmt(v: float) -> String:
	# GDScript's % formatter has no %g/%e. A small nonzero value (e.g. the Pfa knob at
	# 1e-3..1e-6) would round to "0" via either the whole-number branch OR "%.2f" → it'd LIE
	# about the value the slider is sending. Build a compact mantissa-exponent by hand for
	# |v| < 0.01; integer-valued knobs (pt_w, rcs_m2, N_train, …) stay on the clean branches.
	if v == 0.0:
		return "0"
	var a := absf(v)
	if a < 0.01:
		var ex := int(floor(log(a) / log(10.0)))
		var mant := v / pow(10.0, ex)
		return "%.1fe%d" % [mant, ex]
	if absf(v - roundf(v)) < 0.005:
		return str(int(roundf(v)))
	return "%.2f" % v

# --- controls -----------------------------------------------------------------

func _on_play_pressed() -> void:
	_set_running(not _running)

func _set_running(run: bool) -> void:
	_running = run
	if run:
		_client.send({"type": "run", "mode": "realtime", "speed": 1.0})
		_play_btn.text = "Pause"
	else:
		_client.send({"type": "pause"})
		_play_btn.text = "Play"

func _on_reset_pressed() -> void:
	_client.send({"type": "reset"})       # reload scenario, held seed re-applied (clean replay)
	_blips.clear()
	# `reset` reloads the YAML server-side → propagation reverts to the scenario default,
	# but the server sends no new handshake. Resync the local fidelity so the badge/button
	# don't lie about a toggle the reset just undid.
	_fidelity = _fidelity_default.duplicate()
	_render_badge()
	_update_fid_btn()
	if _running:
		_client.send({"type": "run", "mode": "realtime", "speed": 1.0})

# --- view + rendering ---------------------------------------------------------

func _world_to_screen(pos: Array) -> Vector2:
	var vp := get_viewport_rect().size
	var sx := MARGIN + (float(pos[0]) / _x_max) * (vp.x - 2.0 * MARGIN)
	var sy := (vp.y - MARGIN) - (float(pos[2]) / _z_max) * (vp.y - 2.0 * MARGIN)
	return Vector2(sx, sy)

func _process(dt: float) -> void:
	var i := _blips.size() - 1
	var changed := false
	while i >= 0:
		_blips[i].age += dt
		if _blips[i].age >= BLIP_TTL:
			_blips.remove_at(i)
		changed = true
		i -= 1
	if changed:
		queue_redraw()

func _draw() -> void:
	if _mode == "cfar":
		_draw_cfar()
	elif _mode == "geoloc":
		_draw_plan()
	else:
		_draw_spatial()

func _draw_spatial() -> void:
	var vp := get_viewport_rect().size
	# ground line (altitude 0) for spatial reference
	var ground_y := (vp.y - MARGIN)
	draw_line(Vector2(0, ground_y), Vector2(vp.x, ground_y), Color(0.25, 0.35, 0.25), 1.0)

	var detected := bool(_telemetry.get(_radar_id + ".detected", false)) if _radar_id != "" else false
	# §12 watch-item: "below horizon" keys off the `visible` telemetry flag, NOT the
	# absence of detection events — a masked target still false-alarms at rate pfa and can
	# blip. Defaults true, so free_space (infinite LOS, `visible` always true) and the
	# pre-handshake state both render the target normally. Single-target scenario: this is
	# the radar's best-target flag, which here is tgt1.
	var visible := bool(_telemetry.get(_radar_id + ".visible", true)) if _radar_id != "" else true

	for id in _entities:
		var e = _entities[id]
		var p := _world_to_screen(e.pos)
		if e.kind == "radar":
			# a small upward triangle for the site
			var rcol := Color(0.5, 0.8, 1.0)
			draw_colored_polygon(
				PackedVector2Array([p + Vector2(0, -10), p + Vector2(-9, 6), p + Vector2(9, 6)]), rcol)
			draw_string(_font, p + Vector2(12, 4), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, rcol)
		elif e.kind == "target":
			# below horizon (no LOS) → dark red; visible+detected → green; visible+miss → grey.
			var tcol: Color
			var tag := ""
			if not visible:
				tcol = Color(0.45, 0.12, 0.12)
				tag = " (below horizon)"
			elif detected:
				tcol = Color(0.4, 1.0, 0.4)
			else:
				tcol = Color(0.75, 0.75, 0.75)
			draw_circle(p, TARGET_R, tcol)
			draw_string(_font, p + Vector2(10, -8), id + tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tcol)
		elif e.kind == "jammer":
			# Noise jammer (slice 4): a magenta diamond, with a faint line back to the radar so the
			# geometry reads — a SELF-SCREEN jammer sits ON the target (line along the boresight →
			# mainlobe), a STANDOFF jammer sits off-axis/elevated (the line shows the sidelobe angle
			# the radar receives it through). The J/S·JNR numbers are in the readout (telemetry
			# keys), so the marker only needs to place the threat in the scene.
			var jcol := Color(1.0, 0.35, 0.9)
			if _radar_id != "" and _entities.has(_radar_id):
				draw_line(_world_to_screen(_entities[_radar_id].pos), p, Color(1.0, 0.35, 0.9, 0.25), 1.0)
			draw_colored_polygon(PackedVector2Array(
				[p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)]), jcol)
			draw_string(_font, p + Vector2(11, 4), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, jcol)

	# detection blips: expanding rings that fade over BLIP_TTL
	for b in _blips:
		var a: float = 1.0 - (b.age / BLIP_TTL)
		var r: float = TARGET_R + 18.0 * (b.age / BLIP_TTL)
		draw_arc(b.pos, r, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, a), 2.0)

# --- CFAR range-power view (slice 3) ------------------------------------------
# A plot: x = range (the core's static range axis), y = power in dB. Three layers, all from
# core output — the drawn profile, the CFAR threshold curve (NEVER recomputed here), and a
# marker per detected cell. Toggling the cfar rung redraws the threshold and the markers.

func _cfar_plot_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(PLOT_L, PLOT_T, vp.x - PLOT_L - PLOT_R, vp.y - PLOT_T - PLOT_B)

func _cfar_x(i: int, rect: Rect2) -> float:
	var n := maxi(1, _n_cells - 1)
	return rect.position.x + (float(i) / float(n)) * rect.size.x

func _cfar_y(db: float, rect: Rect2) -> float:
	var t := clampf((db - CFAR_Y_LO) / (_cfar_y_hi - CFAR_Y_LO), 0.0, 1.0)
	return rect.position.y + (1.0 - t) * rect.size.y

func _draw_cfar() -> void:
	var rect := _cfar_plot_rect()
	draw_rect(rect, Color(0.2, 0.25, 0.3), false, 1.0)

	# y grid + dB labels every 10 dB — labels live in the RIGHT gutter; the left edge is the
	# slider/readout panel (drawing them at x=8 collided with the knob labels, slice-3 fix).
	var db := ceilf(CFAR_Y_LO / 10.0) * 10.0
	while db <= _cfar_y_hi:
		var gy := _cfar_y(db, rect)
		draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), Color(1, 1, 1, 0.06), 1.0)
		draw_string(_font, Vector2(rect.end.x + 6, gy + 4), "%d" % int(db), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		db += 10.0
	draw_string(_font, Vector2(rect.end.x + 6, rect.position.y - 6), "dB", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))

	# x grid + range labels (km)
	var nticks := 6
	for ti in range(nticks + 1):
		var idx := int(round(float(ti) / nticks * maxi(1, _n_cells - 1)))
		var gx := _cfar_x(idx, rect)
		draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(1, 1, 1, 0.05), 1.0)
		var rng_km := (float(_range_axis[idx]) / 1000.0) if idx < _range_axis.size() else 0.0
		draw_string(_font, Vector2(gx - 10, rect.end.y + 16), "%.0f" % rng_km, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
	draw_string(_font, Vector2(rect.position.x + rect.size.x * 0.5 - 30, rect.end.y + 32), "range (km)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))

	# profile polyline (what the receiver saw this look)
	if _profile_db.size() >= 2:
		var pts := PackedVector2Array()
		for i in _profile_db.size():
			pts.append(Vector2(_cfar_x(i, rect), _cfar_y(float(_profile_db[i]), rect)))
		draw_polyline(pts, Color(0.5, 0.8, 1.0), 1.5)

	# threshold polyline (CORE output — the adaptive curve the rung produced)
	if _threshold_db.size() >= 2:
		var tpts := PackedVector2Array()
		for i in _threshold_db.size():
			tpts.append(Vector2(_cfar_x(i, rect), _cfar_y(float(_threshold_db[i]), rect)))
		draw_polyline(tpts, Color(1.0, 0.5, 0.3), 1.5)

	# a marker per detected cell (profile crossed the threshold there)
	for i in _detections.size():
		if bool(_detections[i]) and i < _profile_db.size():
			draw_circle(Vector2(_cfar_x(i, rect), _cfar_y(float(_profile_db[i]), rect)), 3.0, Color(0.4, 1.0, 0.4))

	_cfar_legend(rect)

func _cfar_legend(rect: Rect2) -> void:
	var x := rect.end.x - 150.0
	var y := rect.position.y + 14.0
	draw_line(Vector2(x, y), Vector2(x + 18, y), Color(0.5, 0.8, 1.0), 2.0)
	draw_string(_font, Vector2(x + 24, y + 4), "profile", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.9, 1.0))
	draw_line(Vector2(x, y + 16), Vector2(x + 18, y + 16), Color(1.0, 0.5, 0.3), 2.0)
	draw_string(_font, Vector2(x + 24, y + 20), "threshold", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.5))
	draw_circle(Vector2(x + 9, y + 32), 3.0, Color(0.4, 1.0, 0.4))
	draw_string(_font, Vector2(x + 24, y + 36), "detection", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.6))

# --- DF / geolocation plan view (slice 5) -------------------------------------
# A top-down x-y plan: screen-x = world +x (down-range, to the right), screen-y = world +y (cross-
# range, UP — standard math orientation). The y-flip lives in _world_to_plan, and EVERY shape (the
# bearing rays, the error ellipse) is computed in WORLD coords then mapped, so the ellipse rotation
# (ell_deg, a math-convention CCW angle) and the ray directions render correctly through the flip.
# EQUAL aspect (one px/m scale for both axes) keeps the ellipse un-distorted. All layers are core
# output: sensor markers + measured bearing RAYS (the LOPs), the emitter truth, the C2 station, the
# position FIX, and the error ELLIPSE (fix ± linearized covariance).

func _plan_bounds() -> Rect2:
	# World-space bbox over the entities + the fix point (so a wildly biased pseudolinear fix stays
	# on screen), padded, with a floor span so an early tight geometry isn't over-zoomed.
	var have := false
	var x0 := 0.0; var x1 := 0.0; var y0 := 0.0; var y1 := 0.0
	for id in _entities:
		var p = _entities[id].pos
		var wx := float(p[0]); var wy := float(p[1])
		if not have:
			x0 = wx; x1 = wx; y0 = wy; y1 = wy; have = true
		else:
			x0 = minf(x0, wx); x1 = maxf(x1, wx); y0 = minf(y0, wy); y1 = maxf(y1, wy)
	if _df_station != "" and _telemetry.has(_df_station + ".fix_x"):
		var fx := float(_telemetry[_df_station + ".fix_x"])
		var fy := float(_telemetry[_df_station + ".fix_y"])
		if have:
			x0 = minf(x0, fx); x1 = maxf(x1, fx); y0 = minf(y0, fy); y1 = maxf(y1, fy)
	if not have:
		return Rect2(0.0, -20000.0, 60000.0, 40000.0)
	var pad := 6000.0
	x0 -= pad; y0 -= pad; x1 += pad; y1 += pad
	# floor the span so a degenerate (single-point) bbox doesn't divide-by-zero in the scale
	if x1 - x0 < 1000.0:
		x1 = x0 + 1000.0
	if y1 - y0 < 1000.0:
		y1 = y0 + 1000.0
	return Rect2(x0, y0, x1 - x0, y1 - y0)

func _world_to_plan(wx: float, wy: float) -> Vector2:
	# Map a world (x, y) into the centred, equal-aspect plot rect, flipping y so +y is UP.
	var cx := _plan_view.position.x + (_plan_view.size.x - _plan_b.size.x * _plan_sc) * 0.5
	var cy := _plan_view.position.y + (_plan_view.size.y - _plan_b.size.y * _plan_sc) * 0.5
	var sx := cx + (wx - _plan_b.position.x) * _plan_sc
	var sy := cy + (_plan_b.size.y - (wy - _plan_b.position.y)) * _plan_sc
	return Vector2(sx, sy)

func _draw_plan() -> void:
	var vp := get_viewport_rect().size
	_plan_view = Rect2(PLAN_M, PLAN_M, vp.x - 2.0 * PLAN_M, vp.y - 2.0 * PLAN_M)
	_plan_b = _plan_bounds()
	_plan_sc = minf(_plan_view.size.x / _plan_b.size.x, _plan_view.size.y / _plan_b.size.y)
	draw_rect(_plan_view, Color(0.2, 0.25, 0.3), false, 1.0)

	# bearing rays first (drawn UNDER the markers): a line from each sensor along its measured
	# bearing. They cross near the emitter at good geometry and graze near-parallel at bad geometry
	# (the GDOP lesson). bearing_deg is core telemetry; the ray points toward (cosθ, sinθ) in world.
	var L := _plan_b.size.x + _plan_b.size.y      # long enough (world m) to cross the whole scene
	for id in _entities:
		var e = _entities[id]
		if e.kind != "df_sensor":
			continue
		if not _telemetry.has(id + ".bearing_deg"):
			continue
		var th := deg_to_rad(float(_telemetry[id + ".bearing_deg"]))
		var sx := float(e.pos[0]); var sy := float(e.pos[1])
		draw_line(_world_to_plan(sx, sy), _world_to_plan(sx + L * cos(th), sy + L * sin(th)),
			Color(0.45, 0.7, 1.0, 0.45), 1.0)

	# entity markers (sensors = cyan triangles, emitter truth = orange X, station = yellow square)
	for id in _entities:
		var e = _entities[id]
		var p := _world_to_plan(float(e.pos[0]), float(e.pos[1]))
		if e.kind == "df_sensor":
			var c := Color(0.5, 0.85, 1.0)
			draw_colored_polygon(PackedVector2Array(
				[p + Vector2(0, -8), p + Vector2(-7, 5), p + Vector2(7, 5)]), c)
			draw_string(_font, p + Vector2(9, 4), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
		elif e.kind == "emitter":
			var c := Color(1.0, 0.55, 0.2)
			draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), c, 2.0)
			draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), c, 2.0)
			draw_string(_font, p + Vector2(10, 4), id + " (truth)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		elif e.kind == "df_station":
			var c := Color(1.0, 0.9, 0.4)
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), c, false, 2.0)
			draw_string(_font, p + Vector2(9, -6), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)

	# the fix + error ellipse (core output via telemetry — never recomputed here)
	if _df_station != "" and _telemetry.has(_df_station + ".fix_x"):
		var fx := float(_telemetry[_df_station + ".fix_x"])
		var fy := float(_telemetry[_df_station + ".fix_y"])
		var a := float(_telemetry.get(_df_station + ".ell_a", 0.0))
		var b := float(_telemetry.get(_df_station + ".ell_b", 0.0))
		var ang := deg_to_rad(float(_telemetry.get(_df_station + ".ell_deg", 0.0)))
		if a > 0.0 and b > 0.0:
			var pts := PackedVector2Array()
			var n := 48
			for i in n + 1:
				var t := TAU * float(i) / n
				var ex := a * cos(t); var ey := b * sin(t)            # ellipse-local
				var wx := fx + ex * cos(ang) - ey * sin(ang)         # rotate into world
				var wy := fy + ex * sin(ang) + ey * cos(ang)
				pts.append(_world_to_plan(wx, wy))
			draw_polyline(pts, Color(0.4, 1.0, 0.5, 0.9), 1.5)
		var fp := _world_to_plan(fx, fy)                              # the fix marker (green +)
		var fc := Color(0.4, 1.0, 0.5)
		draw_line(fp + Vector2(-7, 0), fp + Vector2(7, 0), fc, 2.0)
		draw_line(fp + Vector2(0, -7), fp + Vector2(0, 7), fc, 2.0)
		draw_string(_font, fp + Vector2(9, -6), "fix", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)

	_plan_legend(_plan_view)

func _plan_legend(rect: Rect2) -> void:
	var x := rect.end.x - 150.0
	var y := rect.position.y + 14.0
	draw_line(Vector2(x, y), Vector2(x + 18, y), Color(0.45, 0.7, 1.0), 2.0)
	draw_string(_font, Vector2(x + 24, y + 4), "bearing (LOP)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.85, 1.0))
	draw_line(Vector2(x, y + 16) + Vector2(-4, -4), Vector2(x, y + 16) + Vector2(4, 4), Color(1.0, 0.55, 0.2), 2.0)
	draw_line(Vector2(x, y + 16) + Vector2(-4, 4), Vector2(x, y + 16) + Vector2(4, -4), Color(1.0, 0.55, 0.2), 2.0)
	draw_string(_font, Vector2(x + 24, y + 20), "emitter truth", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.45))
	draw_line(Vector2(x - 5, y + 32), Vector2(x + 5, y + 32), Color(0.4, 1.0, 0.5), 2.0)
	draw_line(Vector2(x, y + 27), Vector2(x, y + 37), Color(0.4, 1.0, 0.5), 2.0)
	draw_string(_font, Vector2(x + 24, y + 36), "fix + ellipse", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.7))
