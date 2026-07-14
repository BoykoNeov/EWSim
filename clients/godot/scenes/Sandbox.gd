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
#   • "esm" (slice 6) — a TOA raster + difference-histogram view (none of the above shows a pulse
#     stream): intercepted pulses colored by recovered emitter, the cumulative difference histogram
#     (CORE output), the threshold line, and green markers at the detected PRIs (the phantom
#     subharmonic appears under cdif, vanishes under sdif). The fidelity button cycles the
#     deinterleaver rung (cdif↔sdif).
#   • "gps" (slice 7) — a GPS sky-plot + satellite-residual view (none of the above shows a polar
#     az/el sky or a per-satellite residual bar): a polar SKY PLOT (zenith center, horizon edge —
#     the geometry→DOP visual, satellites colored in-solve / masked-excluded), a RESIDUAL bar chart
#     (per-satellite sat_resid_m — the faulted satellite's bar spikes, the RAIM visual), and the
#     DOP/error scalars in the readout. The shared fidelity button cycles the raim rung
#     (off→detect→exclude); a NEW ROW of five error-term toggles (iono/tropo/clock/multipath/noise)
#     + a fault-bias slider are the error-budget / fault levers. ALL from telemetry.
#   • "terrain" (slice 18) — the client's FIRST true 3-D view: a Node3D world (behind the 2-D
#     HUD, CanvasLayer −1) rendering the CORE's handshake height grid as a mesh (never recomputed
#     here), the radar/target markers, the target trail, and the LOS ray colored by the core's
#     `<radar>.visible` verdict (green = clear, red = terrain-masked — the pop-up lesson). Drag
#     to orbit, wheel to zoom. The shared button becomes the 3-RING propagation cycler
#     (free_space → two_ray → terrain — the fidelity LADDER: no ground → smooth earth → hills).
# A handshake shipping `range_axis_m` selects "cfar"; one shipping `pri_axis_us` selects "esm";
# one shipping `terrain_grid` selects the 3-D "terrain" view; one whose fidelity carries
# `estimator` selects "geoloc"; one whose fidelity carries `raim` selects "gps"; otherwise "spatial".

const HOST := "127.0.0.1"
const PORT := 8765
const MARGIN := 64.0
const BLIP_TTL := 1.6            # s a detection blip lingers before fading out
const TARGET_R := 7.0            # px radius of the target marker

# --- visual palette (draw/UI layer ONLY — display constants, no physics) -------
# One set of colors shared by every view so the whole client reads as one instrument:
# a deep-navy sky/backdrop, slightly lighter filled plot panels, low-alpha grids with
# brighter tick labels. Semantic colors (detected green, threshold orange, decoy ✦,
# per-missile hues) are unchanged — this palette is chrome, not meaning.
const COL_BG_TOP := Color(0.035, 0.05, 0.085)        # sky gradient, zenith
const COL_BG_BOT := Color(0.075, 0.10, 0.14)         # sky gradient, horizon
const COL_GROUND := Color(0.085, 0.115, 0.085)       # below-the-ground fill strip
const COL_GROUND_LINE := Color(0.32, 0.44, 0.32)     # the altitude-0 line
const COL_PANEL_BG := Color(0.065, 0.09, 0.125, 0.92)  # filled plot-panel background
const COL_PANEL_BORDER := Color(0.30, 0.38, 0.48, 0.85)
const COL_GRID := Color(1, 1, 1, 0.05)               # in-panel grid lines
const COL_TICK := Color(1, 1, 1, 0.40)               # axis tick labels
# preload, NOT `class_name SimClient`: the global class cache isn't built on a
# headless/fresh load, so a bare type reference fails to resolve there. preload
# binds the script directly and works in the editor and headless alike.
const SimClientScript := preload("res://net/SimClient.gd")
# --- baked fx resources (res://fx/ — display-only chrome shared by every view, current
# and future). All text-format resources: a starfield/gradient backdrop shader (rides
# CanvasLayer -2 behind every view), a radial glow sprite (the _glow halo helper), the
# one UI theme, the terrain surface shader (slope shading + labeled contour lines over
# the CORE's height grid), and the 3-D environment (sky/fog/bloom). None of them touch
# a physics number — they dress what the core already said.
const FX_GLOW: Texture2D = preload("res://fx/glow.tres")
const FX_THEME: Theme = preload("res://fx/theme.tres")
const FX_BACKDROP_SHADER: Shader = preload("res://fx/backdrop.gdshader")
const FX_TERRAIN_SHADER: Shader = preload("res://fx/terrain.gdshader")
const FX_TERRAIN_ENV: Environment = preload("res://fx/terrain_env.tres")
# The baked 3-D prop & effect library (fx/props3d.gd): a DETERMINISTIC display-only
# scatter of military/civilian structures (SAM sites, a spinning search radar, a tank
# column, a lit city, villages, farm fields, a refinery with a burning flare, a factory,
# roads/power/pipeline, a wind farm) + GPU-particle fire/smoke/explosions over the
# terrain view. Grid-seeded RNG (same scenario → same layout); tall props keep OUT of
# the radar↔target LOS corridor so decoration can't contradict the core's verdict.
const FX_PROPS := preload("res://fx/props3d.gd")
const T3D_CONTOUR_M := 50.0       # real-metre interval of the terrain contour lines (HUD-labeled)

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
var _readout2: Label = null       # extra readout columns — the multi-entity views (salvo) ship ~46
var _readout3: Label = null       # scalar keys and one column runs off the window. Null in the headless
                                  # UI-test harnesses (they build _readout only), so always null-guarded.
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
var _mode := "spatial"            # "spatial" (1/2/4) | "cfar" (3) | "geoloc" (5) | "esm" (6) | "gps" (7)
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
# Slice-16 pitch-plane ROTATIONAL DYNAMICS: a handshake `airframe_view` marker (shipped by the core
# from airframe params, NOT a fidelity — slice 16 carries none; the Cmα slider is the lesson) flips the
# shared button OFF (nothing to cycle) and turns on the nose-vs-velocity attitude overlay in the missile
# draw. `att` is a DYNAMICAL output now (Cmα<0 weathervanes / Cmα>0 tumbles), read off the θ/γ telemetry.
var _airframe_view := false        # handshake airframe_view (slice 16) — the rotational-dynamics overlay
var _airframe_target := ""         # the missile id carrying the airframe params (handshake)
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

# --- ESM / PRI view (slice 6): populated only when the handshake ships pri_axis_us. Two stacked
# panels — a TOA raster (each intercepted pulse a tick, colored by its assigned emitter — chaos
# resolving into rows) and the difference HISTOGRAM (bars + the threshold line + green markers at
# the detected PRIs). ALL from telemetry: the histogram + threshold are CORE output (the client
# never recomputes the binning/threshold, HANDOFF §1); the rung changes only which PRIs are marked
# (the phantom subharmonic appears under cdif, vanishes under sdif — same bars, same line).
var _esm_id := ""                 # esm entity id whose "<id>.histogram" etc. we render
var _pri_axis: Array = []         # histogram bin centers (µs) — handshake, core output (the τ-axis)
var _dwell_us := 0.0              # collection dwell (µs) — the raster's time span
var _esm_hist: Array = []         # cumulative difference histogram (counts) — per frame, CORE output
var _esm_thresh: Array = []       # detection threshold (flat line) — CORE output, never recomputed
var _esm_toa: Array = []          # per-pulse TOAs (µs) — the raster x positions (display only)
var _esm_assign: Array = []       # per-pulse assigned-emitter index (0=unassigned) — raster color
var _esm_pri: Array = []          # detected PRIs (µs) — the histogram markers (phantom appears/vanishes)
var _esm_hist_hi := 1.0           # top of the histogram count axis (auto-expands)
const DEINT_RUNGS := ["cdif", "sdif"]   # slice-6 deinterleaver cycler (the §12 badge button)

# --- GPS / sky view (slice 7): populated only when the handshake fidelity carries `raim` (the
# GPS-view discriminator — no static axis ships since the satellites MOVE, unlike CFAR/ESM). A polar
# sky plot + a per-satellite residual bar chart, ALL from telemetry (the DOP/error scalars render in
# the left readout). The receiver id is discovered from the entity stream (the geoloc df_station
# pattern). The shared fidelity button becomes the raim cycler; the NEW five-toggle error row is the
# one genuinely new client-UI element this slice adds.
var _gps_rx := ""                 # gps_receiver id whose "<id>.sat_*"/DOP telemetry we render
var _gps_az: Array = []           # per-satellite azimuth (deg) — sky-plot angle (display only)
var _gps_el: Array = []           # per-satellite elevation (deg) — sky-plot radius (display only)
var _gps_resid: Array = []        # per-satellite range residual (m) — the RAIM bar chart (display only)
var _gps_used: Array = []         # per-satellite Bool — in-solve (green) vs masked/excluded (grey/red)
var _gps_toggle_row: HBoxContainer = null   # the NEW five-error-toggle button ROW
var _gps_toggle_btns := {}        # term(String) -> Button (findable + pressable by the headless UI test)
const GPS_ERR_TERMS := ["iono", "tropo", "clock", "multipath", "noise"]   # the five error-term toggles
const RAIM_RUNGS := ["off", "detect", "exclude"]   # slice-7 raim cycler (the shared fidelity button)

# --- missile spatial view (slice 8): REUSES the slice-1 elevation view (downrange×altitude) — no new
# render mode (the slice-4 "stay spatial" precedent). The handshake fidelity carrying `integrator`
# (and NO range_axis_m / pri_axis_us / estimator / raim) is the discriminator: the view stays SPATIAL,
# only the shared fidelity button becomes the integrator cycler. A missile marker (nose-oriented off
# the trail), a fading trajectory trail, an impact burst, and the energy readout — all telemetry /
# entity pos. `integrator` is PHYSICS-CHANGING (a rk4↔euler toggle changes the trajectory, the slice-2
# `propagation` shape), NOT a slice-5/6/7 draw-free toggle.
var _missile_id := ""             # missile entity id (for the .impacted flag telemetry)
var _missile_trail: Array = []    # WORLD [x,y,z] breadcrumbs (mapped through _world_to_screen each draw)
# Slice-14 salvo: per-missile WORLD breadcrumb trails, id -> Array[[x,y,z]]. Populated ONLY in the
# cooperation view (the multi-interceptor scenario), so slices 8–13 (single missile, _missile_trail)
# are untouched. The two trails ARE the visual: under :salvo the near missile weaves a stretched
# S-curve while the far reference flies ~straight (both converge together); under :solo both fly
# straight-in and one arrives well before the other (the spread).
var _salvo_trails := {}
# Airframe view (slice 16/17): a DISPLAY-ONLY α history for the strip chart drawn in the corner of the
# elevation view — the weathervane RINGING (α oscillating about trim at ω_sp, damped by Cmq) vs the
# tumble DIVERGENCE is a time-series lesson, so give it a time axis. Samples are the core's `<id>.alpha`
# telemetry, clamped to ±π for DISPLAY only (a tumbling α runs to the FINITE_CEIL sentinel, which would
# destroy the chart's autoscale; a pegged trace reads "tumble" just fine). Never fed back anywhere.
var _alpha_hist: Array = []
const ALPHA_HIST_MAX := 480       # ~8 s of state frames at the emit cadence
const INTEGRATOR_RUNGS := ["rk4", "euler"]   # slice-8 integrator cycler (the shared fidelity button)
const AUTOPILOT_RUNGS := ["ideal", "pid"]    # slice-9 autopilot cycler (the ONE source of truth for the rungs)
# The autopilot ring is PER-SCENARIO: slice-9 stays the 2-ring :ideal↔:pid (its UI test asserts the
# 2-cycle), slice-15 (autopilot:fin) upgrades to the 3-ring :ideal→:pid→:fin at handshake. Initialized
# FROM the const (one-list-no-drift — the fin branch appends `fin`, nothing re-lists the base rungs). Set
# once in the discriminator; reset leaves it (reset only resyncs _fidelity), so the 3-ring survives a
# re-launch.
var _autopilot_rungs: Array = AUTOPILOT_RUNGS.duplicate()
const GUIDANCE_RUNGS := ["pursuit", "pn", "apn"]   # slice-10/12 OUTER-law cycler (3-ring: +apn, slice 12)
const SEEKER_RUNGS := ["raw", "filtered"]    # slice-11 seeker cycler (raw finite-diff ↔ α-β filtered)
const DISCRIMINATION_RUNGS := ["none", "gated"]   # slice-13 countermeasures cycler (blend-all ↔ α-β predicted-LOS gate)
const COOPERATION_RUNGS := ["solo", "salvo"]   # slice-14 salvo cycler (uncoordinated PN ↔ impact-time-control)
const AIRFRAME_RUNGS := ["point_mass", "pitch_coupled"]   # slice-17 α→lift cycler (ballistic ↔ coupled turn)
const MISSILE_TRAIL_MAX := 2500   # cap the breadcrumb list (a full flight is ~1800 frames)

# --- terrain 3-D view (slice 18): the client's FIRST true 3-D view. Populated only when the
# handshake ships `terrain_grid` (the range_axis_m-precedent discriminator). A CanvasLayer at
# layer −1 hosts a SubViewport whose Node3D world renders the CORE's height grid as a mesh
# (client MESHES core output, never recomputes a height — HANDOFF §1), the radar/target
# markers, the fading target trail, and the LOS ray colored by the core's `<radar>.visible`
# verdict. The 2-D HUD (sliders/readout/badge + the propagation button) rides on top unchanged.
const PROP_RUNGS := ["free_space", "two_ray", "terrain"]   # slice-18: the FULL propagation ladder
# PER-SCENARIO ring (the _autopilot_rungs precedent): slice 1/2 keep their historical 2-ring
# free_space↔two_ray toggle (a `terrain` rung there would be a silent no-op — no heightfield);
# a terrain scenario upgrades to the full 3-ring in _enter_terrain_mode. SLICED from the one
# const, never re-listed (one-list-no-drift).
var _prop_rungs: Array = PROP_RUNGS.slice(0, 2)
const T3D_SCALE := 0.01           # metres → 3-D units (10 km → 100 u; display only)
const T3D_VEXAG := 2.5            # vertical exaggeration — DISPLAY ONLY, labeled in the HUD (§12)
var _terrain_n := 0               # handshake grid edge (n×n heights)
var _terrain_extent: Array = []   # [xmin, xmax, ymin, ymax] (m) — handshake
var _terrain_grid_h: Array = []   # row-major n² heights (m) — handshake, CORE output
var _terrain_radar := ""          # radar id whose .visible/.terrain_clearance_m colors the LOS
var _terrain_target := ""         # target id the LOS ray runs to
var _t3d_layer: CanvasLayer = null
var _t3d_cam: Camera3D = null
var _t3d_radar: Node3D = null
var _t3d_target: Node3D = null
var _t3d_los_mesh: ImmediateMesh = null
var _t3d_trail_mesh: ImmediateMesh = null
var _t3d_line_mat: StandardMaterial3D = null
var _t3d_trail_pts: Array = []    # Vector3 breadcrumbs (3-D units, display only)
# fx/props3d.gd decoration state (display only): built lazily on the FIRST state frame
# (the radar/target positions — the LOS keep-out corridor — are only known then).
var _t3d_root: Node3D = null      # the 3-D world root the props parent under
var _t3d_props_done := false      # decorate() ran for this scene build
var _t3d_props: Node3D = null
var _t3d_spin: Array = []         # nodes rotating per frame (radar heads, turbine rotors)
var _t3d_beacons: Array = []      # blinking obstruction lights
var _t3d_booms: Array = []        # periodic one-shot explosion emitters (the range)
var _t3d_cars: Array = []         # road traffic looping along baked Curve3D paths
var _t3d_sun: DirectionalLight3D = null   # kept so the shadow range can track the zoom
var _t3d_anim_t := 0.0
var _cam_yaw := -2.35             # orbit camera state (drag to rotate, wheel to zoom)
var _cam_pitch := 0.45
var _cam_dist := 180.0
var _cam_focus := Vector3.ZERO

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
	# The shared backdrop (fx/backdrop.gdshader on CanvasLayer -2): the starfield sky every 2-D
	# view sits on. Behind the Node2D canvas AND behind the terrain 3-D layer (-1), so the 3-D
	# view's own sky covers it. Pure chrome; sized by anchors so a window resize just works.
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

	# The left control panel rides in a PanelContainer skinned by the baked fx/theme.tres (the
	# one instrument-chrome skin — panel stylebox, buttons, sliders, labels, tooltips), so the
	# sliders/readout stay legible over whatever the view draws underneath (pure chrome — the
	# headless UI tests build the inner widgets directly and never touch this wrapper).
	var panel_box := PanelContainer.new()
	panel_box.position = Vector2(8, 8)
	panel_box.theme = FX_THEME
	ui.add_child(panel_box)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	panel_box.add_child(panel)

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
	# Font 14 (down from 18): the missile-arc views ship ~20 scalar keys and the taller
	# panel was running off the bottom of the window (and over the §12 badge). Up to three
	# columns side-by-side: _update_readout splits long key lists so the salvo view (~46 keys) fits.
	var readout_row := HBoxContainer.new()
	readout_row.add_theme_constant_override("separation", 18)
	panel.add_child(readout_row)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 14)
	readout_row.add_child(_readout)
	_readout2 = Label.new()
	_readout2.add_theme_font_size_override("font_size", 14)
	readout_row.add_child(_readout2)
	_readout3 = Label.new()
	_readout3.add_theme_font_size_override("font_size", 14)
	readout_row.add_child(_readout3)

	# §12: a visible "<fidelity> approximation" badge in every view. Text is filled
	# from the handshake's actual fidelity map, never hardcoded.
	_badge = Label.new()
	_badge.modulate = Color(1, 1, 1, 0.7)
	_badge.theme = FX_THEME
	_badge.add_theme_font_size_override("font_size", 12)
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
	# Slice-16 airframe view marker (handshake-once, the range_axis_m precedent): a rotational-
	# dynamics scenario ships airframe_view=true + the target id. It carries NO fidelity, so it
	# lands in the spatial branch below; _setup_spatial_fid_btn reads these to drop the button.
	_airframe_view = bool(obj.get("airframe_view", false))
	_airframe_target = str(obj.get("airframe_target", ""))
	# A CFAR scenario ships a STATIC range axis in the handshake (core output, §1/§8); that
	# presence flips the client into the range-power view. A slice-1/2 scenario omits it and
	# stays the spatial elevation view. Decide the mode ONCE here — the two render paths never
	# interleave after this.
	if obj.has("range_axis_m"):
		_enter_cfar_mode(obj)
	elif obj.has("pri_axis_us"):
		_enter_esm_mode(obj)
	elif obj.has("terrain_grid"):
		_enter_terrain_mode(obj)
	elif _fidelity.has("estimator"):
		_enter_geoloc_mode(obj)
	elif _fidelity.has("raim"):
		_enter_gps_mode(obj)
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
	if _airframe_view and not _fidelity.has("airframe"):
		# Slice-16 pitch-plane ROTATIONAL DYNAMICS: the handshake ships airframe_view (from the missile's
		# airframe params) but NO fidelity — the rotational integrator is gated on PARAMS-PRESENCE, and the
		# Cmα SLIDER (a knob, auto-built by _build_knobs) is the lesson, not a fidelity button. So there is
		# NOTHING for the shared button to cycle: DROP it (hide + guarded disconnect). CHECKED FIRST because
		# a slice-16 scenario carries no fidelity key, so every _fidelity.has(...) branch below would fall
		# through to `propagation` and mislabel the button (the advisor's Option-P′ fix: recognize the view
		# by its handshake key, keep the core params-gated with no `:airframe` false-fidelity toggle). The
		# lesson is DRAWN (the nose vector off θ vs the velocity vector off γ — their gap is α, the angle of
		# attack): Cmα<0 WEATHERVANES (α rings toward trim, ω_sp real) vs Cmα>0 TUMBLES (α diverges, ω_sp the
		# sentinel). The trajectory is BYTE-IDENTICAL across the slider (rotation ⊥ translation — the slice-16
		# isolation; α→lift coupling is slice 17). Class 4c, RNG-free. VALUE-GUARDED on the `:airframe`
		# fidelity being ABSENT (the slice-17 CLIENT NOTE): slice 17 ships an `:airframe` fidelity ALONGSIDE
		# airframe_view, so it falls to the cycler branch below; only the fidelity-LESS slice-16 view drops.
		_fid_kind = "airframe"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		_prop_btn.visible = false      # no fidelity to cycle — the Cmα slider is the lesson lever
		# Seed extents to fit the ballistic arc (40°/500 m/s → apex ~5 km alt, ~24 km down); they only grow.
		_x_max = 6000.0
		_z_max = 3000.0
	elif _fidelity.has("airframe"):
		# Slice-17 α→lift→γ COUPLING: the scenario NOW carries an `:airframe` fidelity (point_mass ↔
		# pitch_coupled) — the REAL path-changing toggle slice 16 deliberately refused (a coupling it
		# couldn't yet produce). The shared button comes BACK as the airframe cycler. SAME `_fid_kind =
		# "airframe"` as slice 16 (so the curved-trail + nose/velocity/α drawing at _draw_missile and the
		# _airframe_view α-vector overlay ALL carry over unchanged — reuse, not a new kind), but the button
		# is SHOWN + wired to the cycler here (vs hidden in the slice-16 branch above). Under :point_mass
		# the missile flies the ballistic arc (α inert, att kinematic); under :pitch_coupled α generates a
		# body lift ⟂ v that bends the path into a climbing turn (the trail CURVES). The δ/Cla sliders (auto
		# knobs) tighten the turn. Class 4c — physics-changing, NO RNG, live-settable, NO set_fidelity guard.
		_fid_kind = "airframe"
		_prop_btn.visible = true
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_airframe_pressed):
			_prop_btn.pressed.connect(_on_airframe_pressed)
		_prop_btn.tooltip_text = "Cycle airframe (set_fidelity): point_mass ↔ pitch_coupled"
		# Seed extents to fit the climbing turn (x ~0..3 km, z ~0..4 km); they only grow, so start close.
		_x_max = 4000.0
		_z_max = 4000.0
	elif _fidelity.has("cooperation"):
		# Slice-14 cooperative salvo (THE CAPSTONE): a `cooperation` fidelity keeps the SPATIAL elevation
		# view (the salvo engagement is planar in x-z — N interceptors climb, a common target crosses in
		# altitude) but repurposes the shared button as the :solo↔:salvo COOPERATION cycler. CHECKED FIRST —
		# BEFORE discrimination/seeker/guidance/autopilot — ON PURPOSE: a slice-14 scenario ships
		# cooperation + guidance:pn + autopilot:ideal (NO seeker/discrimination), all HELD FIXED so the
		# cooperation lesson is uncontaminated, and the ONE button must toggle `cooperation`, not the held
		# ones (convention 9 — one lesson per button; the slice-13 "discrimination before the held keys"
		# precedent, one lesson deeper). Same guarded disconnect as the other _fid_kind setups. Under :solo
		# each missile flies plain PN to its own natural t_go → the two trails arrive SPREAD out in time
		# (one hits while the sibling is still far); under :salvo the NEAR missile weaves a stretched S-curve
		# to delay toward the shared T_d while the FAR reference flies ~straight → both converge TOGETHER
		# (Δτ → 0, the per-missile t_go/impact_time_err readout is the number). `cooperation` is class 4c
		# (PHYSICS-CHANGING, NO RNG → live-settable, NO set_fidelity guard — the :integrator/:autopilot/:apn
		# precedent, the CONTRAST to slice-13 :scan's introduce-reject); "draw-count invariance" is VACUOUS
		# (no w.rng consumer — truth-fed PN, no seeker). It is INERT without a :datalink coordinator (no
		# salvo_t_d field → the :salvo decide! branch is unreachable → :salvo ≡ :solo).
		_fid_kind = "cooperation"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_cooperation_pressed):
			_prop_btn.pressed.connect(_on_cooperation_pressed)
		_prop_btn.tooltip_text = "Cycle cooperation (set_fidelity): solo ↔ salvo"
		# Seed extents to fit the salvo (x ~0..9 km, z ~3..5 km); they only grow, so start close.
		_x_max = 10000.0
		_z_max = 6000.0
	elif _fidelity.has("discrimination"):
		# Slice-13 countermeasures: a `discrimination` fidelity keeps the SPATIAL elevation view (the
		# crossing engagement is planar in x-z) but repurposes the shared button as the :none↔:gated
		# DISCRIMINATION cycler. CHECKED FIRST — BEFORE seeker/guidance/autopilot — ON PURPOSE: a
		# slice-13 scenario ships ALL FOUR keys (seeker:scan + guidance:pn + autopilot:ideal are HELD
		# FIXED so the discrimination lesson is uncontaminated), and the ONE button must toggle
		# `discrimination`, not the held ones (convention 9 — one lesson per button; the slice-11
		# "seeker before guidance/autopilot" precedent, one lesson deeper). Same guarded disconnect as
		# the other _fid_kind setups. Under :none the seeker's tracked-LOS ray (drawn from λ_est) walks
		# toward the brighter DECOY glyph → the missile leads the BLEND → a miss; under :gated the α-β
		# predicted-LOS gate rejects the separated decoy peak → the ray HOLDS on the target → intercept
		# (the visual tell; the aim_error readout is the number). `discrimination` is DRAW-INVARIANT among
		# its rungs (both paint+draw the same 2·N_p·N_bins profile — they differ only in peak SELECTION,
		# introduce-safe once :scan is on) YET TRAJECTORY-CHANGING, and INERT without seeker=:scan.
		_fid_kind = "discrimination"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_discrimination_pressed):
			_prop_btn.pressed.connect(_on_discrimination_pressed)
		_prop_btn.tooltip_text = "Cycle discrimination (set_fidelity): none ↔ gated"
		# Seed extents to fit the crossing (x ~0..8 km, z ~2..8 km); they only grow, so start close.
		_x_max = 8000.0
		_z_max = 8000.0
	elif _fidelity.has("ep"):
		_fid_kind = "ep"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_ep_pressed):
			_prop_btn.pressed.connect(_on_ep_pressed)
		_prop_btn.tooltip_text = "Cycle EP (set_fidelity): none → freq_agility → sidelobe_blanking"
	elif _fidelity.has("integrator"):
		# Slice-8 missile: an `integrator` fidelity (no range/pri axis, no estimator/raim) keeps the
		# SPATIAL elevation view but repurposes the shared button as the integrator cycler. Guarded
		# disconnect like the other _fid_kind setups so the headless UI test (button built without
		# _build_ui's connect) doesn't error.
		_fid_kind = "missile"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_integrator_pressed):
			_prop_btn.pressed.connect(_on_integrator_pressed)
		_prop_btn.tooltip_text = "Cycle integrator (set_fidelity): rk4 ↔ euler"
		# Seed the elevation-view extents small so the ballistic arc FILLS the view: the slice-1 radar
		# defaults (45 km × 5 km) are for a radar scene and only grow, so a ~6 km × 1.6 km arc would
		# render cramped in the corner (advisor). They grow to fit as the missile climbs/flies.
		_x_max = 2000.0
		_z_max = 1000.0
	elif _fidelity.has("seeker"):
		# Slice-11 noisy seeker: a `seeker` fidelity keeps the SPATIAL elevation view (the crossing
		# engagement is planar in x-z) but repurposes the shared button as the :raw↔:filtered SEEKER
		# cycler. CHECKED BEFORE `guidance` AND `autopilot` ON PURPOSE: slice-11 scenarios ship ALL THREE
		# keys (guidance:pn + autopilot:ideal are HELD FIXED so the seeker/filter lesson is uncontaminated),
		# and the ONE button must toggle `seeker`, not guidance/autopilot (convention 9 — one lesson per
		# button; the exact slice-10 "guidance before autopilot" precedent, one lesson deeper). Same guarded
		# disconnect as the other _fid_kind setups. The LOS/λ̇ readout JITTERS under :raw (saturated lit,
		# wild a_cmd) vs STEADY under :filtered (the α-β smoothing) — the visual tell. `seeker` is a NEW
		# fidelity-class combo: DRAW-INVARIANT (introduce-safe, no desync) YET TRAJECTORY-CHANGING.
		_fid_kind = "seeker"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_seeker_pressed):
			_prop_btn.pressed.connect(_on_seeker_pressed)
		_prop_btn.tooltip_text = "Cycle seeker (set_fidelity): raw ↔ filtered"
		# Seed extents to fit the crossing (x ~0..8 km, z ~2..8 km); they only grow, so start close.
		_x_max = 8000.0
		_z_max = 8000.0
	elif _fidelity.get("autopilot", "") == "fin":
		# Slice-15 rate-limited fin servo: ships autopilot:fin (the LESSON) + guidance:pn (HELD FIXED).
		# The shared button becomes the 3-RING autopilot cycler :ideal→:pid→:fin. Keyed on the autopilot
		# VALUE (== "fin", the FIRST value-keyed branch, not key-presence) and CHECKED BEFORE `guidance`
		# ON PURPOSE: a slice-15 scenario ships BOTH keys but the fin PLANT is the lesson, so the one
		# button must toggle `autopilot`, not the held `guidance` (convention 9 — one lesson per button;
		# the slice-13/14 "lesson key before the held keys" precedent). No existing slice ships
		# autopilot:fin, so nothing else matches this. Same guarded disconnect as the other _fid_kind
		# setups. The ring is PER-SCENARIO (_autopilot_rungs → the 3-ring here) so the slice-9 button
		# stays a 2-ring :ideal↔:pid — only a fin scenario reaches the third rung. `autopilot` is class 4c
		# (PHYSICS-CHANGING, NO RNG → live-settable, NO set_fidelity guard — the :integrator/:apn/
		# :cooperation precedent, the CONTRAST to slice-13 :scan's introduce-reject). The lesson is the
		# g-onset RATE cap: under :fin the achieved-g cannot BUILD faster than k_δ·δ̇_max (the g_onset /
		# fin_defl / fin_rate_sat / track-gap readout is the tell — the fins can't keep up), while :ideal
		# follows a_cmd instantly (uncapped) and :pid caps the onset via the τ-lag (a different mechanism).
		# The δ̇_max slider is the live lever (raise it → the cap rises → :fin approaches :ideal). The MISS
		# stays small across the slider (PN robust — the "lack of effect" that motivates the deferred 6-DOF).
		_fid_kind = "autopilot"
		_autopilot_rungs = AUTOPILOT_RUNGS + ["fin"]   # the 3-ring, built FROM the const (no re-list)
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_autopilot_pressed):
			_prop_btn.pressed.connect(_on_autopilot_pressed)
		_prop_btn.tooltip_text = "Cycle autopilot (set_fidelity): ideal → pid → fin"
		# Seed extents to fit the engagement (x ~0..9 km, z ~0..6 km); they only grow, so start close.
		_x_max = 9500.0
		_z_max = 6000.0
	elif _fidelity.has("guidance"):
		# Slice-10 PN missile: a `guidance` fidelity keeps the SPATIAL elevation view (the crossing
		# engagement is planar in x-z) but repurposes the shared button as the :pursuit↔:pn OUTER-law
		# cycler. CHECKED BEFORE `autopilot` ON PURPOSE: slice-10 scenarios ship BOTH keys (autopilot:
		# ideal is HELD FIXED so the guidance-law lesson is uncontaminated), and the ONE button must
		# toggle `guidance`, not `autopilot` (convention 9 — one lesson per button). Same guarded
		# disconnect as the other _fid_kind setups. The LOS line's constant-bearing-vs-swing is the
		# PN-vs-pursuit tell; the a_demand/saturated readout is the g-limit-saturation number.
		_fid_kind = "guidance"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_guidance_pressed):
			_prop_btn.pressed.connect(_on_guidance_pressed)
		_prop_btn.tooltip_text = "Cycle guidance (set_fidelity): pursuit → pn → apn"
		# Seed extents to fit the crossing (x ~0..8 km, z ~2..8 km); they only grow, so start close.
		_x_max = 8000.0
		_z_max = 8000.0
	elif _fidelity.has("autopilot"):
		# Slice-9 guided missile: an `autopilot` fidelity (no range/pri axis, no estimator/raim/integrator)
		# keeps the SPATIAL elevation view (the engagement is planar in x-z — the interceptor climbs, the
		# target crosses in altitude — so the pursuit shows) but repurposes the shared button as the
		# :ideal↔:pid cycler. Same guarded disconnect as the other _fid_kind setups.
		_fid_kind = "autopilot"
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_autopilot_pressed):
			_prop_btn.pressed.connect(_on_autopilot_pressed)
		_prop_btn.tooltip_text = "Cycle autopilot (set_fidelity): ideal ↔ pid"
		# Seed extents to fit the engagement (x ~0..9 km, z ~0..6 km); they only grow, so start close.
		_x_max = 9500.0
		_z_max = 6000.0
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

func _enter_esm_mode(obj: Dictionary) -> void:
	# Slice-6 multi-emitter EW: a handshake shipping the STATIC PRI-histogram axis (pri_axis_us,
	# the range_axis_m analog — it can't change frame-to-frame) flips the client into the ESM/PRI
	# view (a TOA raster + difference histogram — neither the elevation, plan, nor range-power view
	# shows it) and repurposes the shared fidelity button as the deinterleaver cycler. Adopt the
	# static axes, then swap the prop toggle (_on_prop_pressed) for _on_deint_pressed — the
	# disconnect is guarded so the headless UI test (which builds the button without _build_ui's
	# connect) doesn't error, exactly like _enter_cfar_mode / _enter_geoloc_mode.
	_mode = "esm"
	_fid_kind = "esm"
	_esm_id = str(obj.get("esm", ""))
	_pri_axis = obj.get("pri_axis_us", [])
	_dwell_us = float(obj.get("dwell_us", 0.0))
	if _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.disconnect(_on_prop_pressed)
	if not _prop_btn.pressed.is_connected(_on_deint_pressed):
		_prop_btn.pressed.connect(_on_deint_pressed)
	_prop_btn.tooltip_text = "Cycle deinterleaver (set_fidelity): cdif ↔ sdif"

func _enter_gps_mode(_obj: Dictionary) -> void:
	# Slice-7 GPS: a handshake whose fidelity carries `raim` (and NO range_axis_m / pri_axis_us /
	# estimator) flips the client into the sky/DOP view (no static axis ships — the satellites move,
	# unlike CFAR/ESM; `raim` presence is the discriminator). The shared fidelity button becomes the
	# raim cycler (off→detect→exclude); the disconnect is guarded so the headless UI test — which
	# builds the button without _build_ui's connect — doesn't error, exactly like _enter_cfar_mode.
	# Then build the NEW five-error-toggle button ROW (the one genuinely new client-UI element).
	_mode = "gps"
	_fid_kind = "gps"
	if _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.disconnect(_on_prop_pressed)
	if not _prop_btn.pressed.is_connected(_on_raim_pressed):
		_prop_btn.pressed.connect(_on_raim_pressed)
	_prop_btn.tooltip_text = "Cycle RAIM (set_fidelity): off → detect → exclude"
	_build_gps_toggles()

func _build_gps_toggles() -> void:
	# The NEW UI element: a ROW of five error-term toggle buttons — NOT a cycler (advisor: five
	# independent on/off keys, the genuinely new element). Each flips its fidelity key + sends
	# set_fidelity. Stored by term in `_gps_toggle_btns` so the headless UI test can find + press
	# them; re-rendered from `_fidelity` (the badge source) on toggle + on reset. Rebuilt fresh
	# (idempotent) so a load_scenario between GPS scenes can't leave freed buttons behind. Attached
	# under `_knob_box` (below the fault slider) — present in both the real UI and the UI-test harness.
	if _gps_toggle_row != null and is_instance_valid(_gps_toggle_row):
		_gps_toggle_row.queue_free()
	_gps_toggle_btns = {}
	_gps_toggle_row = HBoxContainer.new()
	_knob_box.add_child(_gps_toggle_row)
	for term in GPS_ERR_TERMS:
		var b := Button.new()
		b.tooltip_text = "Toggle the %s error term (set_fidelity): on ↔ off" % term
		b.pressed.connect(_on_gps_toggle_pressed.bind(term))
		_gps_toggle_row.add_child(b)
		_gps_toggle_btns[term] = b
	_update_gps_toggles()

func _update_gps_toggles() -> void:
	for term in _gps_toggle_btns:
		if is_instance_valid(_gps_toggle_btns[term]):
			_gps_toggle_btns[term].text = "%s:%s" % [term, str(_fidelity.get(term, "off"))]

func _on_gps_toggle_pressed(term: String) -> void:
	# Flip one error-term key on↔off + tell the core (set_fidelity — the slice-2 live toggle,
	# generalised; every GPS key is introduce-safe so the server accepts it even if the scenario
	# omitted it — the draw is 2·n_sats unconditionally, a toggle gates the CONTRIBUTION not the
	# draw, so a mid-run flip is bit-identical). The client owns the displayed state: update badge +
	# the toggle row locally (the server applies it silently on the next look, no reply).
	var cur := str(_fidelity.get(term, "off"))
	var next := "off" if cur == "on" else "on"
	_fidelity[term] = next
	_client.send({"type": "set_fidelity", "key": term, "value": next})
	_render_badge()
	_update_gps_toggles()

func _on_raim_pressed() -> void:
	# Advance the raim rung (off→detect→exclude→off) + tell the core (set_fidelity). `:raim` is
	# introduce-safe AND draw-free (the fault is a constant, the rung is post-draw), so a mid-run
	# cycle is bit-identical (the slice-4 :ep contract, NOT slice-3's draw-flip): only the solver's
	# phase-4 integrity check / exclusion changes — the flag raises under :detect, the bad satellite
	# drops + the fix snaps back under :exclude. The client owns the displayed rung: update badge +
	# button locally (the server applies it silently, no reply).
	var cur := str(_fidelity.get("raim", "off"))
	var i := RAIM_RUNGS.find(cur)
	var next: String = RAIM_RUNGS[(i + 1) % RAIM_RUNGS.size()] if i >= 0 else "off"
	_fidelity["raim"] = next
	_client.send({"type": "set_fidelity", "key": "raim", "value": next})
	_render_badge()
	_update_fid_btn()

func _enter_terrain_mode(obj: Dictionary) -> void:
	# Slice-18 terrain masking: a handshake shipping the STATIC height grid (terrain_grid — the
	# range_axis_m analog, LOAD-static by design: hills are not live knobs) flips the client into
	# the 3-D terrain view. The shared button stays the PROPAGATION cycler but upgrades to the
	# FULL 3-ring (free_space → two_ray → terrain — the per-scenario-ring precedent from
	# _autopilot_rungs): every propagation rung is class 4a (draw-invariant, introduce-safe), so
	# the mid-run cycle never desyncs. The 3-D world is built HERE (idempotent — a load_scenario
	# between terrain scenes rebuilds fresh, the _build_gps_toggles precedent); all of it is
	# DISPLAY: the mesh is the core's grid, the LOS verdict is the core's `visible` boolean.
	_mode = "terrain"
	_fid_kind = "propagation"
	_prop_rungs = PROP_RUNGS.duplicate()          # the full ladder (sliced default was 2-ring)
	_terrain_n = int(obj.get("terrain_n", 0))
	_terrain_extent = obj.get("terrain_extent_m", [])
	_terrain_grid_h = obj.get("terrain_grid", [])
	_terrain_radar = str(obj.get("radar", ""))
	_terrain_target = str(obj.get("target", ""))
	if not _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.connect(_on_prop_pressed)   # guarded for the headless UI test
	_prop_btn.tooltip_text = "Cycle propagation (set_fidelity): free_space → two_ray → terrain"
	_build_terrain_scene()

func _sim_to_3d(pos: Array) -> Vector3:
	# Sim (x, y, z-up; right-handed) → Godot (X, Y-up, Z): X = x, Y = z·exag, Z = −y (keeps the
	# handedness). The vertical exaggeration is DISPLAY-ONLY (labeled in the HUD) and applies to
	# markers AND mesh alike, so relative occlusion still reads true.
	return Vector3(float(pos[0]), float(pos[2]) * T3D_VEXAG, -float(pos[1])) * T3D_SCALE

func _build_terrain_scene() -> void:
	if _t3d_layer != null and is_instance_valid(_t3d_layer):
		_t3d_layer.queue_free()
	_t3d_layer = null
	_t3d_cam = null
	_t3d_trail_pts = []
	_t3d_root = null                  # props state resets with the scene (rebuild = fresh scatter)
	_t3d_props_done = false
	_t3d_props = null
	_t3d_spin = []
	_t3d_beacons = []
	_t3d_booms = []
	_t3d_cars = []
	_t3d_sun = null
	if _terrain_n < 2 or _terrain_extent.size() < 4 or _terrain_grid_h.size() < _terrain_n * _terrain_n:
		return                        # malformed handshake — leave the 2-D HUD alone
	_t3d_layer = CanvasLayer.new()
	_t3d_layer.layer = -1             # BEHIND the Node2D canvas + the UI CanvasLayer
	add_child(_t3d_layer)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE    # orbit input routes via _unhandled_input
	_t3d_layer.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	holder.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	_t3d_root = root                  # the props' parent (decorated lazily, first state frame)
	# camera + the baked fx/terrain_env.tres environment (procedural night-blue sky matching the
	# 2-D palette, sky ambient, subtle depth fog, filmic tonemap, and a soft glow pass so the
	# emissive markers / LOS ray / trail bloom) + a warm low key light that casts shadows off the
	# hills + a faint cool fill from the opposite side so shadowed slopes stay readable.
	_t3d_cam = Camera3D.new()
	_t3d_cam.environment = FX_TERRAIN_ENV
	_t3d_cam.far = 4000.0
	root.add_child(_t3d_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_blend_splits = true    # hide the split seams when zoomed out
	sun.shadow_blur = 1.6                         # soften map-scale prop shadows a touch
	root.add_child(sun)
	_t3d_sun = sun                    # range/opacity are zoom-tracked in _update_t3d_cam
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 140.0, 0.0)
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = 0.25
	root.add_child(fill)
	# the terrain mesh — CORE heights, client-meshed (display only)
	var ter := MeshInstance3D.new()
	ter.mesh = _build_terrain_mesh()
	root.add_child(ter)
	# markers: the radar (cyan, on its mast point) + the target (orange)
	_t3d_radar = _make_t3d_marker(root, Color(0.45, 0.90, 1.00))
	_t3d_target = _make_t3d_marker(root, Color(1.00, 0.62, 0.20))
	# the LOS ray + the trail — ImmediateMesh lines, rebuilt each state frame
	_t3d_line_mat = StandardMaterial3D.new()
	_t3d_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_t3d_line_mat.vertex_color_use_as_albedo = true
	_t3d_los_mesh = ImmediateMesh.new()
	var los := MeshInstance3D.new()
	los.mesh = _t3d_los_mesh
	root.add_child(los)
	_t3d_trail_mesh = ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.mesh = _t3d_trail_mesh
	root.add_child(trail)
	# orbit focus = the terrain center; distance frames the whole extent
	var cx := (float(_terrain_extent[0]) + float(_terrain_extent[1])) * 0.5
	var cy := (float(_terrain_extent[2]) + float(_terrain_extent[3])) * 0.5
	_cam_focus = _sim_to_3d([cx, cy, 0.0])
	_cam_dist = maxf(float(_terrain_extent[1]) - float(_terrain_extent[0]),
			float(_terrain_extent[3]) - float(_terrain_extent[2])) * T3D_SCALE * 1.05
	_update_t3d_cam()

func _grid_h(ix: int, iy: int) -> float:
	return float(_terrain_grid_h[iy * _terrain_n + ix])

func _grid_v(ix: int, iy: int) -> Vector3:
	var n := _terrain_n
	var x := float(_terrain_extent[0]) + ix * (float(_terrain_extent[1]) - float(_terrain_extent[0])) / (n - 1)
	var y := float(_terrain_extent[2]) + iy * (float(_terrain_extent[3]) - float(_terrain_extent[2])) / (n - 1)
	return _sim_to_3d([x, y, _grid_h(ix, iy)])

func _terrain_col(t: float) -> Color:
	# Height ramp (display only): valley green → slope brown → high tan.
	if t < 0.5:
		return Color(0.14, 0.24, 0.12).lerp(Color(0.36, 0.30, 0.17), t * 2.0)
	return Color(0.36, 0.30, 0.17).lerp(Color(0.62, 0.58, 0.48), (t - 0.5) * 2.0)

func _build_terrain_mesh() -> ArrayMesh:
	# Mesh the handshake grid: two triangles per cell, height-tinted vertex colors, generated
	# normals. The grid layout (row-major over y then x) is the CORE's `_terrain_info` contract.
	var n := _terrain_n
	var h_lo := 1.0e30
	var h_hi := -1.0e30
	for v in _terrain_grid_h:
		h_lo = minf(h_lo, float(v))
		h_hi = maxf(h_hi, float(v))
	var span: float = maxf(h_hi - h_lo, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]
	for iy in n - 1:
		for ix in n - 1:
			for c in corners:
				var gx: int = ix + c[0]
				var gy: int = iy + c[1]
				st.set_color(_terrain_col((_grid_h(gx, gy) - h_lo) / span))
				st.add_vertex(_grid_v(gx, gy))
	st.generate_normals()
	var mesh := st.commit()
	# the baked fx/terrain.gdshader surface: keeps the height-tinted vertex colors as albedo and
	# adds slope-based rock shading + antialiased elevation contours + noise grain — all DISPLAY.
	# The contour spacing is authored in REAL metres (T3D_CONTOUR_M, labeled in the HUD) and
	# converted to display units here, so the vertical exaggeration can't silently re-scale it.
	var mat := ShaderMaterial.new()
	mat.shader = FX_TERRAIN_SHADER
	mat.set_shader_parameter("contour_spacing", T3D_CONTOUR_M * T3D_SCALE * T3D_VEXAG)
	mesh.surface_set_material(0, mat)
	return mesh

func _make_t3d_marker(root: Node3D, col: Color) -> Node3D:
	var m := Node3D.new()
	root.add_child(m)
	var body := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.1
	sph.height = 2.2
	body.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6   # past the env glow threshold → the marker blooms
	body.material_override = mat
	m.add_child(body)
	return m

func _terrain_on_state(obj: Dictionary) -> void:
	_entities.clear()
	for e in obj.get("entities", []):
		var id := str(e.get("id", ""))
		_entities[id] = {"kind": str(e.get("kind", "")), "pos": e.get("pos", [0, 0, 0])}
		if _terrain_radar == "" and str(e.get("kind", "")) == "radar":
			_terrain_radar = id
		if _terrain_target == "" and str(e.get("kind", "")) == "target":
			_terrain_target = id
	if _t3d_layer == null or _t3d_los_mesh == null:
		return
	var rpos: Array = _entities.get(_terrain_radar, {}).get("pos", [0, 0, 0])
	var tpos: Array = _entities.get(_terrain_target, {}).get("pos", [0, 0, 0])
	var r3 := _sim_to_3d(rpos)
	var t3 := _sim_to_3d(tpos)
	_t3d_radar.position = r3
	_t3d_target.position = t3
	# Baked decorative props (fx/props3d.gd) — built ONCE per scene, lazily HERE because the
	# radar/target positions (the LOS keep-out corridor) are only known on a state frame.
	# Pure display: grid-seeded deterministic scatter, grounded on the same handshake grid.
	if not _t3d_props_done and _t3d_root != null:
		_t3d_props_done = true
		var deco: Dictionary = FX_PROPS.decorate(_t3d_root, _terrain_grid_h, _terrain_n,
				_terrain_extent, Callable(self, "_sim_to_3d"), FX_GLOW,
				Vector2(float(rpos[0]), float(rpos[1])), Vector2(float(tpos[0]), float(tpos[1])))
		_t3d_props = deco["root"]
		_t3d_spin = deco["spinners"]
		_t3d_beacons = deco["beacons"]
		_t3d_booms = deco["booms"]
		_t3d_cars = deco.get("cars", [])
	# trail breadcrumbs (skip the repeat point — the paused/held frame)
	if _t3d_trail_pts.is_empty() or _t3d_trail_pts[-1] != t3:
		_t3d_trail_pts.append(t3)
		if _t3d_trail_pts.size() > MISSILE_TRAIL_MAX:
			_t3d_trail_pts.pop_front()
	# the LOS ray — colored by the CORE's verdict (green clear / red terrain-masked); the
	# client never re-tests the occlusion (HANDOFF §1 — `visible` IS the core's answer)
	var vis := bool(_telemetry.get(_terrain_radar + ".visible", true))
	var col := Color(0.30, 1.00, 0.45) if vis else Color(1.00, 0.25, 0.20)
	_t3d_los_mesh.clear_surfaces()
	_t3d_los_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _t3d_line_mat)
	_t3d_los_mesh.surface_set_color(col)
	_t3d_los_mesh.surface_add_vertex(r3)
	_t3d_los_mesh.surface_add_vertex(t3)
	_t3d_los_mesh.surface_end()
	# the fading trail strip
	_t3d_trail_mesh.clear_surfaces()
	if _t3d_trail_pts.size() >= 2:
		_t3d_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _t3d_line_mat)
		var np := _t3d_trail_pts.size()
		for i in np:
			var a: float = 0.15 + 0.85 * float(i) / float(np - 1)
			_t3d_trail_mesh.surface_set_color(Color(1.00, 0.62, 0.20, a))
			_t3d_trail_mesh.surface_add_vertex(_t3d_trail_pts[i])
		_t3d_trail_mesh.surface_end()

func _draw_terrain_hud() -> void:
	# The 3-D layer (CanvasLayer −1) renders the world; the 2-D canvas only LABELS it: the
	# core's LOS verdict + signed clearance (the lesson number) + the §12 display-honesty note.
	var vp := get_viewport_rect().size
	var vis := true
	if _terrain_radar != "":
		vis = bool(_telemetry.get(_terrain_radar + ".visible", true))
	var lbl := "LOS CLEAR" if vis else "TERRAIN MASKED"
	var col := Color(0.30, 1.00, 0.45) if vis else Color(1.00, 0.30, 0.25)
	draw_string(_font, Vector2(vp.x - 320, 40), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	if _terrain_radar != "" and _telemetry.has(_terrain_radar + ".terrain_clearance_m"):
		var c := float(_telemetry[_terrain_radar + ".terrain_clearance_m"])
		draw_string(_font, Vector2(vp.x - 320, 64), "LOS clearance: %+.0f m" % c,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	draw_string(_font, Vector2(maxf(8.0, vp.x - 740), vp.y - 16),
			"3-D terrain view — vertical ×%.1f, props decorative/not-to-scale (display only) · contours every %.0f m · drag: orbit · wheel: zoom" % [T3D_VEXAG, T3D_CONTOUR_M],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TICK)

func _update_t3d_cam() -> void:
	if _t3d_cam == null or not _t3d_cam.is_inside_tree():
		return                        # off-tree in the headless UI harness — orbit is display-only
	var dir := Vector3(cos(_cam_pitch) * cos(_cam_yaw), sin(_cam_pitch), cos(_cam_pitch) * sin(_cam_yaw))
	_t3d_cam.position = _cam_focus + dir * _cam_dist
	_t3d_cam.look_at(_cam_focus, Vector3.UP)
	if _t3d_sun != null:
		# Shadow tuning tracks the zoom (display only): the shadow-map range follows the
		# camera so close-in props get crisp shadows instead of spreading the map over a
		# fixed 500 u, and the opacity eases off at far zoom where sub-pixel prop shadows
		# would only shimmer against the terrain tint.
		_t3d_sun.directional_shadow_max_distance = clampf(_cam_dist * 1.8, 100.0, 1200.0)
		_t3d_sun.shadow_opacity = clampf(1.15 - _cam_dist / 1500.0, 0.45, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	# Orbit/zoom for the terrain 3-D camera (display only; other views ignore input here).
	if _mode != "terrain" or _t3d_cam == null:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_cam_yaw -= event.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + event.relative.y * 0.006, 0.08, 1.45)
		_update_t3d_cam()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(_cam_dist * 0.9, 15.0)
			_update_t3d_cam()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(_cam_dist * 1.1, 1200.0)
			_update_t3d_cam()

func _render_badge() -> void:
	# §12: a visible "<fidelity> approximation" badge, built from the live local fidelity
	# map (never hardcoded), re-rendered whenever the propagation toggle changes it.
	var parts := PackedStringArray()
	for k in _fidelity.keys():
		parts.append("%s: %s" % [k, _fidelity[k]])
	parts.sort()
	# Slice-16 airframe: no fidelity map (params-presence gate) — name the approximation explicitly so the
	# badge isn't blank (pitch-plane only, linear aero, isolated rotation — the §1 named approximations).
	if _airframe_view and parts.is_empty():
		_badge.text = "approximation — airframe: pitch-plane rotational dynamics (linear aero, isolated: no α→lift)"
		return
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
		"esm":
			_prop_btn.text = "deint: %s" % str(_fidelity.get("deinterleaver", "?"))
		"gps":
			_prop_btn.text = "raim: %s" % str(_fidelity.get("raim", "?"))
		"missile":
			_prop_btn.text = "integrator: %s" % str(_fidelity.get("integrator", "?"))
		"autopilot":
			_prop_btn.text = "autopilot: %s" % str(_fidelity.get("autopilot", "?"))
		"guidance":
			_prop_btn.text = "guidance: %s" % str(_fidelity.get("guidance", "?"))
		"seeker":
			_prop_btn.text = "seeker: %s" % str(_fidelity.get("seeker", "?"))
		"discrimination":
			_prop_btn.text = "disc: %s" % str(_fidelity.get("discrimination", "?"))
		"cooperation":
			_prop_btn.text = "coop: %s" % str(_fidelity.get("cooperation", "?"))
		"airframe":
			if _fidelity.has("airframe"):
				# Slice-17 α→lift coupling: the button IS the airframe cycler (point_mass ↔ pitch_coupled).
				_prop_btn.visible = true
				_prop_btn.text = "airframe: %s" % str(_fidelity.get("airframe", "?"))
			else:
				# Slice-16: no fidelity to cycle — the button is hidden (dropped in _setup_spatial_fid_btn),
				# the Cmα slider is the lesson. Keep it hidden here too (defensive against a re-show).
				_prop_btn.visible = false
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
	# Advance the propagation rung round the PER-SCENARIO ring (slice 1/2: the historical
	# free_space↔two_ray toggle; slice 18: the FULL 3-ring …→terrain) and tell the core
	# (set_fidelity — the slice-2 live toggle). Every propagation rung is class 4a
	# (draw-invariant, introduce-safe — a terrain-less world treats :terrain as bit-exact
	# free space), so a mid-run cycle never desyncs the draw stream. Update the badge +
	# button locally; the server applies it on the next tick with no reply, so the client
	# owns the displayed state. On the 2-ring this is behavior-identical to the old flip.
	var cur := str(_fidelity.get("propagation", "two_ray"))
	var i := _prop_rungs.find(cur)
	var next: String = _prop_rungs[(i + 1) % _prop_rungs.size()] if i >= 0 else "two_ray"
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

func _on_deint_pressed() -> void:
	# Advance the deinterleaver rung (cdif↔sdif) and tell the core (set_fidelity). `:deinterleaver`
	# is introduce-safe AND draw-free (the ESMReceiver draws a fixed count/look regardless of rung —
	# the whole draw is phase-3), so a mid-run cycle is bit-identical (the slice-4 :ep / slice-5
	# :estimator contract, NOT slice-3's draw-flip): only the Deinterleaver's phase-4 acceptance
	# changes — the phantom subharmonic PRI marker appears under cdif and vanishes under sdif (same
	# histogram bars, same threshold line). The client owns the displayed rung: update badge + button
	# locally (the server applies it silently, no reply).
	var cur := str(_fidelity.get("deinterleaver", "cdif"))
	var i := DEINT_RUNGS.find(cur)
	var next: String = DEINT_RUNGS[(i + 1) % DEINT_RUNGS.size()] if i >= 0 else "cdif"
	_fidelity["deinterleaver"] = next
	_client.send({"type": "set_fidelity", "key": "deinterleaver", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_integrator_pressed() -> void:
	# Advance the integrator rung (rk4↔euler) and tell the core (set_fidelity). UNLIKE every other
	# fidelity cycler this is PHYSICS-CHANGING, not toggle-bit-identical: there is NO RNG in slice 8,
	# so a rk4↔euler toggle CHANGES the trajectory going forward (the slice-2 `propagation` shape — the
	# OPPOSITE of the slice-5/6/7 draw-free toggles). `:integrator` is introduce-safe (absent a missile
	# nothing reads it). The client owns the displayed rung: update badge + button locally (the server
	# applies it silently on the next step, no reply). NB launch geometry only changes on reset/reload,
	# but the integrator method IS well-defined mid-flight (it changes how the SAME state is advanced).
	var cur := str(_fidelity.get("integrator", "rk4"))
	var i := INTEGRATOR_RUNGS.find(cur)
	var next: String = INTEGRATOR_RUNGS[(i + 1) % INTEGRATOR_RUNGS.size()] if i >= 0 else "rk4"
	_fidelity["integrator"] = next
	_client.send({"type": "set_fidelity", "key": "integrator", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_autopilot_pressed() -> void:
	# Advance the autopilot rung (slice-9 :ideal↔:pid, or slice-15 :ideal→:pid→:fin) and tell the core
	# (set_fidelity). Like :integrator this is PHYSICS-CHANGING, not toggle-bit-identical: there is NO RNG
	# in the missile arc, so a rung flip CHANGES the trajectory going forward (the slice-2 `propagation`
	# shape — the OPPOSITE of the slice-5/6/7 draw-free toggles). Introduce-safe (absent an Autopilot
	# nothing reads it). The slice-15 :fin rung is the rate-limited fin plant (the g-onset cap). The client
	# owns the displayed rung: badge + button locally (the server applies it silently on the next tick).
	# NB the PID-gain sliders are INERT under :ideal (the loop is bypassed) — correct, not a bug.
	# The ring is PER-SCENARIO (_autopilot_rungs): slice-9 → :ideal↔:pid (2-ring), slice-15 →
	# :ideal→:pid→:fin (3-ring, the rate-limited fin plant is the third rung — physics-changing, no RNG).
	var cur := str(_fidelity.get("autopilot", "ideal"))
	var i := _autopilot_rungs.find(cur)
	var next: String = _autopilot_rungs[(i + 1) % _autopilot_rungs.size()] if i >= 0 else "ideal"
	_fidelity["autopilot"] = next
	_client.send({"type": "set_fidelity", "key": "autopilot", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_guidance_pressed() -> void:
	# Advance the OUTER-law rung (the 3-RING pursuit → pn → apn) and tell the core (set_fidelity). Like
	# :autopilot/:integrator this is PHYSICS-CHANGING, not toggle-bit-identical: there is NO RNG in the
	# missile arc, so a rung flip CHANGES the trajectory going forward (the slice-2 `propagation` shape —
	# the OPPOSITE of the slice-5/6/7 draw-free toggles). Introduce-safe (absent an Autopilot nothing
	# reads it; the core defaults to :pursuit). The client owns the displayed rung: badge + button locally
	# (the server applies it silently on the next tick). Under :pn the LOS line holds a constant bearing
	# (the collision triangle) and |a_cmd| falls; under :pursuit the LOS swings and |a_cmd| climbs (the
	# tail-chase); under :apn (slice 12) the `(N/2)·a_T⊥` feedforward anticipates a MANEUVERING target so
	# the demand stays LOW where plain :pn saturates (`saturated` lit) and MISSES — the augmented-PN
	# lesson, the a_demand/saturated readout is the tell. `:autopilot` stays FIXED (this toggles only
	# `guidance`); on a non-maneuvering (slice-10) target :apn ≈ :pn (the feedforward vanishes).
	var cur := str(_fidelity.get("guidance", "pursuit"))
	var i := GUIDANCE_RUNGS.find(cur)
	var next: String = GUIDANCE_RUNGS[(i + 1) % GUIDANCE_RUNGS.size()] if i >= 0 else "pursuit"
	_fidelity["guidance"] = next
	_client.send({"type": "set_fidelity", "key": "guidance", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_seeker_pressed() -> void:
	# Advance the SEEKER rung (raw↔filtered) and tell the core (set_fidelity). A NEW fidelity-class combo:
	# DRAW-INVARIANT (both rungs draw the SAME 1 randn/tick — the filter is pure post-processing, so a
	# mid-run flip does NOT desync the RNG; introduce-safe, UNLIKE the slice-3 :cfar draw-topology flip)
	# YET TRAJECTORY-CHANGING (an :raw↔:filtered toggle CHANGES the missile's flight — the slice-10 shape).
	# So copy NEITHER the slice-5 "toggle-bit-identical" NOR the slice-8/9/10 "no-RNG" language: the seeker
	# is the FIRST w.rng consumer in the missile arc. Introduce-safe (absent a Seeker nothing reads it; the
	# core defaults PN to truth). Under :filtered the α-β tracker yields a smooth λ̇ → a tight intercept,
	# `saturated` off; under :raw the naïve finite-diff amplifies the σ_seek angle noise by 1/dt → PN pegs
	# a_max, `saturated` lit, the miss opens (the LOS/λ̇ readout JITTERS — the visual tell). `guidance` +
	# `autopilot` stay FIXED (this button toggles only `seeker`). The client owns the displayed rung: badge
	# + button locally (the server applies it silently on the next tick, no reply).
	var cur := str(_fidelity.get("seeker", "filtered"))
	var i := SEEKER_RUNGS.find(cur)
	var next: String = SEEKER_RUNGS[(i + 1) % SEEKER_RUNGS.size()] if i >= 0 else "filtered"
	_fidelity["seeker"] = next
	_client.send({"type": "set_fidelity", "key": "seeker", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_discrimination_pressed() -> void:
	# Advance the DISCRIMINATION rung (none↔gated) and tell the core (set_fidelity). Like the slice-11
	# seeker this is DRAW-INVARIANT among its rungs YET TRAJECTORY-CHANGING: both :none and :gated paint
	# the SAME angular profile and draw the SAME 2·N_p·N_bins randn/tick (they differ ONLY in
	# post-detection peak SELECTION — blend-all vs α-β-predicted-LOS gate), so a mid-run flip does NOT
	# desync the RNG (introduce-safe ONCE seeker=:scan is on — the nested-in-4b property). So copy NEITHER
	# the slice-3 "draw-flip" NOR a "no-RNG" line: the :scan seeker DRAWS. Under :none the intensity-
	# weighted centroid of ALL detected peaks walks the aim toward the brighter DECOY (seduced → a miss);
	# under :gated the nearest peak to the α-β PREDICTED bearing is kept (the target-locked track rejects
	# the separated decoy → intercept) — the RGPO track-gate, in angle. `seeker`/`guidance`/`autopilot`
	# stay FIXED (this button toggles only `discrimination`). INERT without seeker=:scan (no profile → no
	# peaks → nothing to discriminate — the :raim-without-GPS coupling). The client owns the displayed
	# rung: badge + button locally (the server applies it silently on the next tick, no reply).
	var cur := str(_fidelity.get("discrimination", "none"))
	var i := DISCRIMINATION_RUNGS.find(cur)
	var next: String = DISCRIMINATION_RUNGS[(i + 1) % DISCRIMINATION_RUNGS.size()] if i >= 0 else "none"
	_fidelity["discrimination"] = next
	_client.send({"type": "set_fidelity", "key": "discrimination", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_cooperation_pressed() -> void:
	# Advance the COOPERATION rung (solo↔salvo) and tell the core (set_fidelity). THE CAPSTONE toggle.
	# Class 4c — PHYSICS-CHANGING, NO RNG (the :integrator/:autopilot/:apn shape, NOT slice-13's
	# draw-topology 4b): there is NO w.rng consumer in the salvo scenario (truth-fed PN, no seeker), so a
	# :solo↔:salvo flip CHANGES the trajectories going forward with NO RNG to desync — "draw-count
	# invariance" is VACUOUS. LIVE-SETTABLE with NO introduce-reject (the CONTRAST to slice-13 :scan): the
	# server's set_fidelity accepts cooperation freely (no draw-topology to flip). Under :salvo each missile
	# reads the coordinator's shared T_d and the NEAR (faster) missile stretches to arrive with the FAR
	# reference (Δτ → 0); under :solo each flies plain PN to its own natural t_go (they arrive SPREAD out).
	# INERT without a :datalink coordinator (no salvo_t_d → :salvo ≡ :solo). `guidance`/`autopilot` stay
	# FIXED (this button toggles only `cooperation`). The client owns the displayed rung: badge + button
	# locally (the server applies it silently on the next tick, no reply).
	var cur := str(_fidelity.get("cooperation", "solo"))
	var i := COOPERATION_RUNGS.find(cur)
	var next: String = COOPERATION_RUNGS[(i + 1) % COOPERATION_RUNGS.size()] if i >= 0 else "solo"
	_fidelity["cooperation"] = next
	_client.send({"type": "set_fidelity", "key": "cooperation", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_airframe_pressed() -> void:
	# Advance the AIRFRAME rung (point_mass↔pitch_coupled) and tell the core (set_fidelity). Slice-17's
	# α→lift→γ coupling — the REAL path-changing toggle slice 16 refused. Class 4c — PHYSICS-CHANGING,
	# NO RNG (the :integrator/:autopilot/:apn/:cooperation shape, NOT slice-13's draw-topology 4b): the
	# coupled scenario is truth-fed OPEN-LOOP with no seeker, so a :point_mass↔:pitch_coupled flip
	# CHANGES the trajectory going forward with NO RNG to desync — "draw-count invariance" is VACUOUS.
	# LIVE-SETTABLE, NO introduce-reject (the CONTRAST to slice-13 :scan): the server's set_fidelity
	# accepts airframe freely (no draw-topology). Under :pitch_coupled a fixed trim δ builds an α whose
	# body lift ⟂ v bends the path into a climbing turn (the trail CURVES); under :point_mass the missile
	# flies the ballistic arc (α inert). The Cla/δ sliders (auto knobs) tighten the turn. The client owns
	# the displayed rung: badge + button locally (the server applies it silently on the next tick, no reply).
	var cur := str(_fidelity.get("airframe", "point_mass"))
	var i := AIRFRAME_RUNGS.find(cur)
	var next: String = AIRFRAME_RUNGS[(i + 1) % AIRFRAME_RUNGS.size()] if i >= 0 else "point_mass"
	_fidelity["airframe"] = next
	_client.send({"type": "set_fidelity", "key": "airframe", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_state(obj: Dictionary) -> void:
	_telemetry = obj.get("telemetry", {})
	if _mode == "cfar":
		_cfar_on_state()
	elif _mode == "geoloc":
		_geoloc_on_state(obj)
	elif _mode == "esm":
		_esm_on_state()
	elif _mode == "gps":
		_gps_on_state(obj)
	elif _mode == "terrain":
		_terrain_on_state(obj)
	else:
		_spatial_on_state(obj)
	_update_readout()
	queue_redraw()

func _gps_on_state(obj: Dictionary) -> void:
	# Discover the receiver id from the entity stream (no handshake axis — the geoloc df_station
	# pattern), then pull the per-satellite display arrays the solver shipped (sky-plot az/el, the
	# RAIM residual bars, the in-solve flags). ALL display-only; the DOP/error/RAIM SCALARS render in
	# the left readout via _update_readout (which skips Array telemetry — the slice-3/6 float()-crash
	# watch-item, re-confirmed for the sat_* keys). Never recompute the fix/DOP/residuals here.
	if _gps_rx == "":
		for e in obj.get("entities", []):
			if str(e.get("kind", "")) == "gps_receiver":
				_gps_rx = str(e.get("id", ""))
				break
	if _gps_rx != "":
		_gps_az    = _telemetry.get(_gps_rx + ".sat_az_deg", [])
		_gps_el    = _telemetry.get(_gps_rx + ".sat_el_deg", [])
		_gps_resid = _telemetry.get(_gps_rx + ".sat_resid_m", [])
		_gps_used  = _telemetry.get(_gps_rx + ".sat_used", [])

func _esm_on_state() -> void:
	# Pull the ESM arrays the core shipped (the histogram + threshold are CORE output — we plot them,
	# never recompute the binning/threshold here, HANDOFF §1). The raster (toa_us/assign) + the
	# detected PRIs (pri_us) are display-only. Auto-expand the count axis to fit a tall peak.
	_esm_hist   = _telemetry.get(_esm_id + ".histogram", [])
	_esm_thresh = _telemetry.get(_esm_id + ".threshold", [])
	_esm_toa    = _telemetry.get(_esm_id + ".toa_us", [])
	_esm_assign = _telemetry.get(_esm_id + ".assign", [])
	_esm_pri    = _telemetry.get(_esm_id + ".pri_us", [])
	for v in _esm_hist:
		_esm_hist_hi = max(_esm_hist_hi, float(v) * 1.1)

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
		# Missile (slice 8): record the breadcrumb trail from the entity world pos (stored in world
		# coords, mapped to screen each draw so it survives the auto-expanding extents). Skip a repeat
		# point so the frozen post-impact pos doesn't stack; the cap bounds the list.
		if str(e.get("kind", "")) == "missile":
			_missile_id = id
			if _missile_trail.is_empty() or _missile_trail[-1] != pos:
				_missile_trail.append(pos)
				if _missile_trail.size() > MISSILE_TRAIL_MAX:
					_missile_trail.pop_front()
			# Slice-14 salvo: a PER-MISSILE trail (keyed by id) so N interceptors each render their own
			# path (the stretched-S vs straight-in contrast). Populated only in the cooperation view; the
			# single _missile_trail above stays the slice-8..13 path (untouched). Same repeat-skip + cap.
			if _fid_kind == "cooperation":
				var tr: Array = _salvo_trails.get(id, [])
				if tr.is_empty() or tr[-1] != pos:
					tr.append(pos)
					if tr.size() > MISSILE_TRAIL_MAX:
						tr.pop_front()
				_salvo_trails[id] = tr
		_x_max = max(_x_max, absf(float(pos[0])) * 1.08)
		_z_max = max(_z_max, float(pos[2]) * 1.15)

	# Airframe view (slice 16/17): sample the core's α into the display-only strip-chart history.
	# Clamped to ±π for DISPLAY (a tumbling α reaches the FINITE_CEIL sentinel — a pegged trace
	# reads "tumble" without wrecking the autoscale). Never consumed by anything but _draw.
	if _airframe_view and _missile_id != "" and _telemetry.has(_missile_id + ".alpha"):
		_alpha_hist.append(clampf(float(_telemetry[_missile_id + ".alpha"]), -PI, PI))
		if _alpha_hist.size() > ALPHA_HIST_MAX:
			_alpha_hist.pop_front()

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
		for extra in [_readout2, _readout3]:
			if extra != null:
				extra.text = ""
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
			# Route through _fmt (compact + scientific for |v| < 0.01), so a tiny-but-nonzero value
			# reads truthfully instead of rounding to "0.00": the slice-8 energy-conservation error
			# de_frac is ~1e-14 (rk4, machine eps) vs ~2.5e-4 (euler) — under a bare "%.2f" BOTH print
			# "0.00" and dialing the integrator looks like a dead button (advisor). Same widget the
			# Pfa slider already uses; all other views' scalars render unchanged.
			lines.append("%s: %s" % [k, _fmt(float(v))])
	# Split a long key list across up to three columns of ~18 rows (the multi-entity salvo view
	# ships ~46 scalars); short lists stay single-column. The extra columns are null in the
	# headless UI-test harnesses (they build _readout only), so the split degrades gracefully.
	var cols: Array = [_readout]
	for extra in [_readout2, _readout3]:
		if extra != null:
			cols.append(extra)
	var ncols := clampi(int(ceil(lines.size() / 18.0)), 1, cols.size())
	var rows := int(ceil(float(lines.size()) / float(ncols)))
	for ci in cols.size():
		if ci < ncols:
			cols[ci].text = "\n".join(lines.slice(ci * rows, mini((ci + 1) * rows, lines.size())))
		else:
			cols[ci].text = ""

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
	_missile_trail.clear()                # start the ballistic trail fresh on the re-launch
	_salvo_trails.clear()                 # slice-14: clear the per-missile salvo trails on re-launch
	_alpha_hist.clear()                   # airframe strip chart restarts with the re-launch
	_t3d_trail_pts.clear()                # slice-18: the 3-D target trail restarts with the re-launch
	# `reset` reloads the YAML server-side → propagation reverts to the scenario default,
	# but the server sends no new handshake. Resync the local fidelity so the badge/button
	# don't lie about a toggle the reset just undid.
	_fidelity = _fidelity_default.duplicate()
	_render_badge()
	_update_fid_btn()
	if _mode == "gps":
		_update_gps_toggles()   # resync the five error toggles to the scenario default too
	if _running:
		_client.send({"type": "run", "mode": "realtime", "speed": 1.0})

# --- view + rendering ---------------------------------------------------------

func _world_to_screen(pos: Array) -> Vector2:
	var vp := get_viewport_rect().size
	var sx := MARGIN + (float(pos[0]) / _x_max) * (vp.x - 2.0 * MARGIN)
	var sy := (vp.y - MARGIN) - (float(pos[2]) / _z_max) * (vp.y - 2.0 * MARGIN)
	return Vector2(sx, sy)

func _process(dt: float) -> void:
	# Terrain-view prop animation (fx/props3d.gd contract — all display-only): radar heads
	# and turbine rotors spin, obstruction beacons blink, the range's one-shot explosion
	# emitters restart on their timers, road cars loop along their baked ground curves.
	# No physics, no wire traffic, no redraw needed (the 3-D SubViewport renders
	# continuously).
	if _mode == "terrain" and _t3d_props != null and is_instance_valid(_t3d_props):
		_t3d_anim_t += dt
		for s in _t3d_spin:
			if is_instance_valid(s):
				s.rotate_object_local(s.get_meta("spin_axis", Vector3.UP),
						float(s.get_meta("spin_rate", 1.0)) * dt)
		for bcn in _t3d_beacons:
			if is_instance_valid(bcn):
				var p := float(bcn.get_meta("blink_period", 1.2))
				bcn.visible = fmod(_t3d_anim_t, p) < p * 0.55
		for bm in _t3d_booms:
			if is_instance_valid(bm):
				var tl := float(bm.get_meta("boom_t", 3.0)) - dt
				if tl <= 0.0:
					for ch in bm.get_children():
						if ch is GPUParticles3D:
							ch.restart()
					tl = float(bm.get_meta("boom_period", 8.0))
				bm.set_meta("boom_t", tl)
		for car in _t3d_cars:
			if is_instance_valid(car):
				var curve: Curve3D = car.get_meta("path", null)
				if curve == null or curve.get_baked_length() <= 0.0:
					continue
				var ln := curve.get_baked_length()
				var off := fmod(float(car.get_meta("off", 0.0)) + float(car.get_meta("speed", 1.0)) * dt, ln)
				car.set_meta("off", off)
				car.position = curve.sample_baked(off)
				var ahead: Vector3 = curve.sample_baked(minf(off + 0.4, ln)) - car.position
				if ahead.length_squared() > 1.0e-8:   # at the wrap point keep the last yaw
					car.rotation.y = atan2(-ahead.z, ahead.x)
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
	elif _mode == "esm":
		_draw_esm()
	elif _mode == "gps":
		_draw_gps()
	elif _mode == "terrain":
		_draw_terrain_hud()      # the 3-D layer draws the world; the canvas only labels it
	else:
		_draw_spatial()

func _nice_step(span: float) -> float:
	# A 1/2/5×10^k grid step so any auto-expanded extent shows ~4–8 labeled ticks (display only).
	if span <= 0.0:
		return 1.0
	var raw := span / 6.0
	var mag := pow(10.0, floor(log(raw) / log(10.0)))
	for m in [1.0, 2.0, 5.0]:
		if raw <= m * mag:
			return m * mag
	return 10.0 * mag

func _fmt_km(m: float) -> String:
	# Compact km tick label: whole km stay integers, sub-km show one decimal.
	var km := m / 1000.0
	return ("%.0f" % km) if absf(km - roundf(km)) < 0.05 else ("%.1f" % km)

func _glow(p: Vector2, r: float, col: Color) -> void:
	# A soft halo under a marker/blip/burst: the baked fx/glow.tres radial sprite, modulated to
	# the marker's color (alpha = strength). Pure chrome — shared by every 2-D view so all the
	# glows read as one instrument.
	draw_texture_rect(FX_GLOW, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _draw_spatial_backdrop() -> void:
	# The elevation view's scene-setting layer: a filled ground strip below altitude 0 and a
	# labeled km grid (downrange along the ground, altitude up the right edge — the left edge is
	# the UI panel). The SKY itself is the fx/backdrop.gdshader starfield on CanvasLayer -2 (one
	# shared backdrop for every view), so nothing opaque is painted above the ground line here.
	# Pure display; the world→screen mapping is the same _world_to_screen every marker uses, so
	# the grid is honest about the auto-expanding extents.
	var vp := get_viewport_rect().size
	var ground_y := (vp.y - MARGIN)
	draw_rect(Rect2(0, ground_y, vp.x, vp.y - ground_y), COL_GROUND)
	# downrange ticks (km): faint verticals through the sky + labels in the ground strip
	var xstep := _nice_step(_x_max)
	var wx := xstep
	while wx < _x_max * 0.999:
		var sx := _world_to_screen([wx, 0.0, 0.0]).x
		draw_line(Vector2(sx, 0), Vector2(sx, ground_y), COL_GRID, 1.0)
		draw_string(_font, Vector2(sx - 10, ground_y + 17), _fmt_km(wx), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
		wx += xstep
	draw_string(_font, Vector2(vp.x - 92, ground_y + 17), "downrange (km)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
	# altitude ticks (km): faint horizontals + labels on the right edge
	var zstep := _nice_step(_z_max)
	var wz := zstep
	while wz < _z_max * 0.999:
		var sy := _world_to_screen([0.0, 0.0, wz]).y
		draw_line(Vector2(0, sy), Vector2(vp.x, sy), COL_GRID, 1.0)
		draw_string(_font, Vector2(vp.x - 34, sy - 4), _fmt_km(wz), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
		wz += zstep
	draw_string(_font, Vector2(vp.x - 52, 16), "alt (km)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_TICK)
	# the altitude-0 line on top of the fill
	draw_line(Vector2(0, ground_y), Vector2(vp.x, ground_y), COL_GROUND_LINE, 1.5)

func _draw_trail(world_pts: Array, col: Color, width := 2.0) -> void:
	# A breadcrumb trail with an age fade (oldest ≈ transparent → newest = the given color), mapped
	# from WORLD points each draw so it stays correct under the auto-expanding extents.
	if world_pts.size() < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := world_pts.size()
	for i in n:
		pts.append(_world_to_screen(world_pts[i]))
		var t := float(i) / float(n - 1)
		cols.append(Color(col.r, col.g, col.b, lerpf(0.04, col.a, t * t)))
	draw_polyline_colors(pts, cols, width)

func _draw_missile_body(head: Vector2, dir: Vector2, col: Color) -> void:
	# A small missile silhouette oriented along `dir` (nose cone + hull + two tail fins) — the shared
	# marker for every missile view. Display only; ~32 px long, built from the screen-space direction.
	# The body glow (in the missile's own hue) plus a warm exhaust glow behind the tail come from the
	# baked fx sprite, so every missile view shares the one look.
	_glow(head, 22.0, Color(col.r, col.g, col.b, 0.28))
	_glow(head - dir * 17.0, 9.0, Color(1.0, 0.65, 0.25, 0.55))
	var p := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		head + dir * 16.0,
		head + dir * 8.0 + p * 3.4,
		head - dir * 14.0 + p * 3.4,
		head - dir * 14.0 - p * 3.4,
		head + dir * 8.0 - p * 3.4]), col)
	var fin := Color(col.r, col.g, col.b, 0.85)
	draw_colored_polygon(PackedVector2Array([
		head - dir * 8.0 + p * 3.0, head - dir * 15.0 + p * 9.0, head - dir * 15.0 + p * 3.0]), fin)
	draw_colored_polygon(PackedVector2Array([
		head - dir * 8.0 - p * 3.0, head - dir * 15.0 - p * 9.0, head - dir * 15.0 - p * 3.0]), fin)

func _draw_spatial() -> void:
	_draw_spatial_backdrop()

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
			# a small upward triangle for the site, over a soft site glow
			var rcol := Color(0.5, 0.8, 1.0)
			_glow(p, 26.0, Color(rcol.r, rcol.g, rcol.b, 0.35))
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
			# glow tracks the state color (dimmer when masked — the dark-red already says "gone")
			_glow(p, 20.0, Color(tcol.r, tcol.g, tcol.b, 0.18 if not visible else 0.32))
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
			_glow(p, 22.0, Color(jcol.r, jcol.g, jcol.b, 0.30))
			draw_colored_polygon(PackedVector2Array(
				[p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)]), jcol)
			draw_string(_font, p + Vector2(11, 4), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, jcol)
		elif e.kind == "decoy":
			# Countermeasure decoy (slice 13): a distinct ORANGE ✦ (a 4-point star) — the false lobe
			# the :scan seeker paints alongside the true target. It is NEVER the truth path
			# (`_nearest_target` skips kind :decoy → miss/CPA is always vs the true target); it exists to
			# SEDUCE the undiscriminated seeker (the :none blend leads the missile toward this glyph).
			var dcol := Color(1.0, 0.6, 0.15)
			_glow(p, 20.0, Color(dcol.r, dcol.g, dcol.b, 0.30))
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -9), p + Vector2(2.5, -2.5), p + Vector2(9, 0), p + Vector2(2.5, 2.5),
				p + Vector2(0, 9), p + Vector2(-2.5, 2.5), p + Vector2(-9, 0), p + Vector2(-2.5, -2.5)]), dcol)
			draw_string(_font, p + Vector2(11, 4), id + " (decoy)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dcol)

	# missile (slice 8): the fading trajectory trail + a nose-oriented marker + an impact burst,
	# on top of the elevation view (drawn only in the missile-view branch, so slice-1/2/4 are untouched)
	if _fid_kind == "missile" or _fid_kind == "airframe" or _fid_kind == "autopilot" or _fid_kind == "guidance" or _fid_kind == "seeker" or _fid_kind == "discrimination":
		_draw_missile()
	# guided missile (slice 9/10/11): a LOS line missile→target so the guidance geometry reads (the target
	# marker is drawn by the generic :target branch above; the a_cmd/a_ach/track_gap [slice 9] +
	# a_demand/saturated [slice 10] + lambda_dot_raw/lambda_dot_filt/lambda_dot_used [slice 11] readout is
	# the lesson number, rendered as text by _update_readout — all scalars, no Array-crash). Under :pn the
	# LOS line holds a constant bearing (the collision triangle); under :pursuit it swings. For the slice-11
	# seeker the λ̇ readout JITTERS under :raw (saturated lit) vs STEADY under :filtered (the α-β smoothing).
	if _fid_kind == "autopilot" or _fid_kind == "guidance" or _fid_kind == "seeker" or _fid_kind == "discrimination":
		_draw_guidance_los()
	# countermeasures (slice 13): the DECOY glyph is drawn in the entity loop above; here overlay the
	# faint missile→decoy LOS + the seeker's TRACKED-aim ray (from λ_est) — under :none it walks toward
	# the decoy (seduced), under :gated it holds on the target (the discrimination tell).
	if _fid_kind == "discrimination":
		_draw_discrimination_los()
	# cooperative salvo (slice 14 — THE CAPSTONE): the N-interceptor multi-missile render. NOT in the
	# single-missile _draw_missile/_draw_guidance_los branches above (those assume ONE _missile_id) — it
	# has its own per-missile-trail path so the two interceptors' stretched-vs-straight arcs both show.
	if _fid_kind == "cooperation":
		_draw_salvo()

	# detection blips: expanding rings that fade over BLIP_TTL, over a fading center glow
	for b in _blips:
		var a: float = 1.0 - (b.age / BLIP_TTL)
		var r: float = TARGET_R + 18.0 * (b.age / BLIP_TTL)
		_glow(b.pos, r + 12.0, Color(1.0, 0.55, 0.2, a * 0.35))
		draw_arc(b.pos, r, 0.0, TAU, 32, Color(1.0, 0.55, 0.2, a), 2.0)

	# airframe view (slice 16/17): the α-vs-time strip chart in the corner — the ringing/tumble lesson
	if _airframe_view and _alpha_hist.size() >= 2:
		_draw_alpha_strip()

func _draw_missile() -> void:
	# The flown arc as a faint polyline (mapped from the stored WORLD breadcrumbs each draw, so it
	# stays correct under the auto-expanding extents), then a marker at the head. The trajectory
	# SHAPE is the same clean parabola for rk4 vs euler (the euler bow is sub-pixel) — the integrator
	# lesson lives in the ΔE readout (de_frac), not the drawn curve; the drag lesson IS visible here
	# (the arc shortens as Cd·A rises). All from telemetry / entity pos — nothing recomputed.
	_draw_trail(_missile_trail, Color(1.0, 0.75, 0.3, 0.7), 2.0)
	if _missile_trail.is_empty():
		return
	var head := _world_to_screen(_missile_trail[-1])
	var impacted := bool(_telemetry.get(_missile_id + ".impacted", false)) if _missile_id != "" else false
	if impacted:
		# impact burst: an orange starburst at the ground crossing (the :impact terminal condition)
		var ic := Color(1.0, 0.5, 0.2)
		_glow(head, 36.0, Color(ic.r, ic.g, ic.b, 0.55))
		for k in 8:
			var a := TAU * float(k) / 8.0
			draw_line(head, head + Vector2(cos(a), sin(a)) * 10.0, ic, 2.0)
		draw_string(_font, head + Vector2(11, -8), "%s impact" % _missile_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ic)
		return
	# Slice-16 airframe view: `att` is a DYNAMICAL output, so the BODY marker points along θ (the
	# integrated pitch attitude, from telemetry) — DISTINCT from the velocity/flight-path γ. Draw the
	# nose triangle along θ, a CYAN velocity reference line along γ, and label the gap α = θ−γ (the angle
	# of attack). Both directions are built from WORLD angles mapped through _world_to_screen (so the
	# elevation projection is consistent) then normalized to a fixed screen length. Cmα<0 → the nose rings
	# around velocity (weathervane); Cmα>0 → the nose runs away (tumble). Falls back to the trail tangent
	# if the θ/γ keys are absent (defensive — an airframe scenario always ships them).
	if _airframe_view and _telemetry.has(_missile_id + ".pitch_theta") and _telemetry.has(_missile_id + ".gamma"):
		var head_w: Array = _missile_trail[-1]
		var th := float(_telemetry[_missile_id + ".pitch_theta"])
		var ga := float(_telemetry[_missile_id + ".gamma"])
		var alpha := float(_telemetry.get(_missile_id + ".alpha", th - ga))
		var Lw := 500.0                        # world-meter probe length (direction only; screen-normalized)
		var nose_tip := _world_to_screen([head_w[0] + Lw * cos(th), head_w[1], head_w[2] + Lw * sin(th)])
		var vel_tip := _world_to_screen([head_w[0] + Lw * cos(ga), head_w[1], head_w[2] + Lw * sin(ga)])
		var nose_dir := (nose_tip - head)
		var vel_dir := (vel_tip - head)
		nose_dir = nose_dir.normalized() if nose_dir.length() > 0.5 else Vector2(1, 0)
		vel_dir = vel_dir.normalized() if vel_dir.length() > 0.5 else Vector2(1, 0)
		# slice-17 steady-turn arc: the core's turn_radius_m drawn as the osculating circle the coupled
		# path is flying (the R = 2m/(ρSC_Lα·α) anchor made visible). The circle center sits R off the
		# velocity, on the NOSE side of v (sign(α) — where the lift pulls for the scenario's +C_Lα).
		# WORLD points mapped through _world_to_screen so the anisotropic extents can't distort it into
		# a lie. Faint + dashed: a reference, not a prediction. Skipped when R runs huge (α→0 → ∞/CEIL).
		var lift_s := 1.0 if alpha >= 0.0 else -1.0
		if _telemetry.has(_missile_id + ".turn_radius_m"):
			var Rt := float(_telemetry[_missile_id + ".turn_radius_m"])
			if Rt > 100.0 and Rt < 40000.0:
				var ccx := float(head_w[0]) - Rt * sin(ga) * lift_s
				var ccz := float(head_w[2]) + Rt * cos(ga) * lift_s
				var phi0 := atan2(float(head_w[2]) - ccz, float(head_w[0]) - ccx)
				var seg := 28
				var sweep := 1.0                    # rad of circle shown, centered on the missile
				var prev := Vector2.ZERO
				for k in seg + 1:
					var phi := phi0 + sweep * (float(k) / seg - 0.5)
					var pt := _world_to_screen([ccx + Rt * cos(phi), head_w[1], ccz + Rt * sin(phi)])
					if k > 0 and k % 2 == 1:        # dashed: draw every other segment
						draw_line(prev, pt, Color(0.45, 1.0, 0.6, 0.35), 1.5)
					prev = pt
				draw_string(_font, prev + Vector2(4, -4), "R=%.0f m" % Rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.45, 1.0, 0.6, 0.6))
		# the α wedge: a translucent fan swept from the velocity direction to the nose direction —
		# the angle of attack drawn AS an angle, not just a number. Degenerates to nothing at α≈0.
		var a0 := vel_dir.angle()
		var d_a := wrapf(nose_dir.angle() - a0, -PI, PI)
		if absf(d_a) > 0.005:
			var steps := maxi(2, int(ceil(absf(d_a) / 0.08)))
			var fan := PackedVector2Array([head])
			for k in steps + 1:
				var a := a0 + d_a * float(k) / steps
				fan.append(head + Vector2(cos(a), sin(a)) * 30.0)
			draw_polygon(fan, PackedColorArray([Color(1.0, 0.8, 0.25, 0.16)]))
			draw_arc(head, 30.0, a0, a0 + d_a, steps + 1, Color(1.0, 0.8, 0.25, 0.55), 1.5)
		# slice-17 lift arrow: the core's |a_lift| (⟂ v, the path-bending accel) as a green arrow off
		# the velocity line, on the nose side of v (sign(α), matching the turn-arc center). Length is
		# a clamped display scale — the number itself lives in the readout.
		if _telemetry.has(_missile_id + ".a_lift"):
			var aL := float(_telemetry[_missile_id + ".a_lift"])
			if aL > 0.05 and aL < 1.0e8:
				var lift_tip := _world_to_screen([
					float(head_w[0]) - Lw * sin(ga) * lift_s, head_w[1], float(head_w[2]) + Lw * cos(ga) * lift_s])
				var lift_dir := (lift_tip - head)
				lift_dir = lift_dir.normalized() if lift_dir.length() > 0.5 else Vector2(0, -1)
				var Ll := 14.0 + 34.0 * clampf(aL / 60.0, 0.0, 1.0)
				var lc := Color(0.45, 1.0, 0.55)
				var tip := head + lift_dir * Ll
				var lp := Vector2(-lift_dir.y, lift_dir.x)
				draw_line(head, tip, lc, 2.0)
				draw_colored_polygon(PackedVector2Array([
					tip + lift_dir * 7.0, tip - lift_dir * 2.0 + lp * 4.0, tip - lift_dir * 2.0 - lp * 4.0]), lc)
				draw_string(_font, tip + lift_dir * 10.0 + Vector2(-14, 0), "lift", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
		# velocity (flight-path γ) reference: a faint cyan arrow
		var vc := Color(0.4, 0.85, 1.0)
		var v_tip := head + vel_dir * 58.0
		var vp2 := Vector2(-vel_dir.y, vel_dir.x)
		draw_line(head, v_tip, vc, 1.5)
		draw_colored_polygon(PackedVector2Array([
			v_tip + vel_dir * 7.0, v_tip - vel_dir * 2.0 + vp2 * 4.0, v_tip - vel_dir * 2.0 - vp2 * 4.0]), vc)
		draw_string(_font, v_tip + Vector2(6, 2), "v (γ)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, vc)
		# the body itself, oriented along θ (the attitude — its angle off the cyan v line IS α)
		var mc := Color(1.0, 0.85, 0.2)
		_draw_missile_body(head, nose_dir, mc)
		draw_string(_font, head + Vector2(14, -14), "%s  α=%.1f°" % [_missile_id, rad_to_deg(alpha)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, mc)
		return
	# nose direction from the last trail segment (screen space); a dot if the segment is too short
	var dir := Vector2(0, -1)
	if _missile_trail.size() >= 2:
		var d := head - _world_to_screen(_missile_trail[-2])
		if d.length() > 0.5:
			dir = d.normalized()
	var mc := Color(1.0, 0.85, 0.2)
	_draw_missile_body(head, dir, mc)
	draw_string(_font, head + Vector2(14, -12), _missile_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, mc)

func _draw_guidance_los() -> void:
	# Slice 9: the line-of-sight from the guided missile to its target — the pursuit steers the velocity
	# toward THIS line (a tail-chaser), so drawing it makes the endgame geometry legible. When the range
	# closes to an intercept, ring the point. All from entity pos (nothing recomputed).
	if _missile_id == "" or not _entities.has(_missile_id):
		return
	var mp := _world_to_screen(_entities[_missile_id].pos)
	for id in _entities:
		if str(_entities[id].kind) != "target":
			continue
		var tp := _world_to_screen(_entities[id].pos)
		draw_line(mp, tp, Color(0.5, 0.9, 1.0, 0.35), 1.0)          # faint LOS line
		var rng := float(_telemetry.get(_missile_id + ".los_range", 1.0e9))
		if rng < 60.0:                                              # near intercept → ring it
			draw_arc(tp, 12.0, 0.0, TAU, 24, Color(1.0, 0.6, 0.2), 2.0)
		break                                                      # single target in slice 9

func _draw_discrimination_los() -> void:
	# Slice 13: the seduction-vs-discrimination tell drawn in the elevation view. Two overlays on top of
	# the true-target LOS (drawn by _draw_guidance_los): (1) a faint missile→decoy LOS (orange) so the
	# false lobe's geometry reads; (2) the seeker's TRACKED-aim ray from λ_est (the α-β bearing the core
	# shipped) — a bright yellow ray from the missile along (cos λ_est, 0, sin λ_est). Under :none the ray
	# walks BETWEEN the target and the brighter decoy (the seduced blend → the missile leads off-target →
	# a miss); under :gated the gate rejects the decoy peak so the ray HOLDS on the target (intercept).
	# ALL from entity pos / telemetry — nothing recomputed (the α-β estimate is core output, HANDOFF §1).
	if _missile_id == "" or not _entities.has(_missile_id):
		return
	var mpos: Array = _entities[_missile_id].pos
	var mp := _world_to_screen(mpos)
	# (1) faint missile→decoy LOS (drawn to every decoy in the scene)
	for id in _entities:
		if str(_entities[id].kind) != "decoy":
			continue
		draw_line(mp, _world_to_screen(_entities[id].pos), Color(1.0, 0.6, 0.15, 0.35), 1.0)
	# (2) the tracked-aim ray from λ_est — the seduced/held bearing the seeker is actually steering on.
	if _telemetry.has(_missile_id + ".lambda_est"):
		var lam := float(_telemetry[_missile_id + ".lambda_est"])
		# ray length ≈ the range to the true target so the ray reaches the target plane (clamped so a
		# huge/early los_range can't shoot far off screen); world x-z direction (cos λ, 0, sin λ).
		var L := clampf(float(_telemetry.get(_missile_id + ".los_range", 6000.0)), 500.0, 12000.0)
		var tip := [float(mpos[0]) + L * cos(lam), 0.0, float(mpos[2]) + L * sin(lam)]
		draw_line(mp, _world_to_screen(tip), Color(1.0, 0.95, 0.3, 0.9), 2.0)
		draw_string(_font, mp + Vector2(6, 18), "aim", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.95, 0.3))

func _draw_salvo() -> void:
	# Slice 14 (THE CAPSTONE): the N-interceptor salvo, drawn in the elevation view. Each :missile gets
	# its OWN colored trail (from _salvo_trails) + a nose marker + a faint LOS to the common target + a
	# per-missile t_go / range label — so the LESSON reads straight off the pixels: under :salvo the NEAR
	# missile weaves a stretched S-curve to delay while the FAR reference flies ~straight and both
	# converge together (Δτ → 0); under :solo both fly straight-in and one reaches the target well before
	# the sibling (the spread). The arrival-spread NUMBER lives in the text readout (each missile's t_go +
	# impact_time_err, the coordinator's salvo_t_d/T_d) — ALL scalars from telemetry, nothing recomputed
	# (the Godot-pure invariant). The two trail colors distinguish the interceptors; the common target is
	# drawn by the generic :target branch in _draw_spatial.
	var mids := PackedStringArray()
	for id in _entities:
		if str(_entities[id].kind) == "missile":
			mids.append(id)
	mids.sort()                                                    # canonical order → stable colors
	# the common target screen point (for the per-missile LOS lines + the intercept ring)
	var tgt_p := Vector2.ZERO
	var have_tgt := false
	for id in _entities:
		if str(_entities[id].kind) == "target":
			tgt_p = _world_to_screen(_entities[id].pos)
			have_tgt = true
			break
	# distinct per-missile hues (amber for the near/first, cyan for the far/second; extra ids wrap)
	var palette := [Color(1.0, 0.75, 0.2), Color(0.4, 0.85, 1.0), Color(0.8, 0.5, 1.0), Color(0.5, 1.0, 0.6)]
	for mi in mids.size():
		var mid: String = mids[mi]
		var col: Color = palette[mi % palette.size()]
		var tr: Array = _salvo_trails.get(mid, [])
		# the flown path (the stretched-S vs straight tell), age-faded, mapped fresh each draw
		_draw_trail(tr, Color(col.r, col.g, col.b, 0.7), 2.0)
		if not _entities.has(mid):
			continue
		var head := _world_to_screen(_entities[mid].pos)
		# faint LOS from this interceptor to the common target (the closing geometry)
		if have_tgt:
			draw_line(head, tgt_p, Color(col.r, col.g, col.b, 0.3), 1.0)
		# missile silhouette oriented along the last trail segment (points up if the segment is too short)
		var dir := Vector2(0, -1)
		if tr.size() >= 2:
			var d := head - _world_to_screen(tr[-2])
			if d.length() > 0.5:
				dir = d.normalized()
		_draw_missile_body(head, dir, col)
		# per-missile label: id + t_go + range (the arrival-timing readout, from telemetry scalars)
		var lbl := mid
		if _telemetry.has(mid + ".t_go"):
			lbl += "  t_go=%.2fs" % float(_telemetry[mid + ".t_go"])
		if _telemetry.has(mid + ".los_range"):
			lbl += "  r=%.0fm" % float(_telemetry[mid + ".los_range"])
		draw_string(_font, head + Vector2(11, -8), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# ring the target when ANY interceptor is at intercept range (the first-CPA moment — under :solo one
	# missile rings while the sibling is still far; under :salvo both close together).
	if have_tgt:
		for mid in mids:
			if float(_telemetry.get(mid + ".los_range", 1.0e9)) < 60.0:
				draw_arc(tgt_p, 12.0, 0.0, TAU, 24, Color(1.0, 0.6, 0.2), 2.0)
				break

func _draw_alpha_strip() -> void:
	# Airframe view (slice 16/17): the α time history in a corner panel — the LESSON as a trace.
	# Cmα<0: α rings about trim at ω_sp, decaying via Cmq (weathervane). Cmα>0: |α| diverges and the
	# display-clamped trace pegs at ±π (tumble). The dashed cyan line is the core's alpha_trim
	# telemetry. ALL display: samples are the core's α (clamped in _spatial_on_state), nothing recomputed.
	var vp := get_viewport_rect().size
	var rect := Rect2(vp.x - 314.0, vp.y - MARGIN - 120.0, 300.0, 104.0)
	draw_rect(rect, COL_PANEL_BG)
	draw_rect(rect, COL_PANEL_BORDER, false, 1.0)
	draw_string(_font, rect.position + Vector2(6, -5), "α history (rad) — ringing = weathervane, pegged = tumble",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	# symmetric autoscale over the visible window (floor keeps a flat α≈0 trace off the rails)
	var m := 0.02
	for v in _alpha_hist:
		m = maxf(m, absf(float(v)))
	var trim := float(_telemetry.get(_missile_id + ".alpha_trim", 0.0)) if _missile_id != "" else 0.0
	m = maxf(m, absf(trim)) * 1.15
	var y0 := rect.position.y + rect.size.y * 0.5
	draw_line(Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Color(1, 1, 1, 0.14), 1.0)
	# trim reference (dashed): where a stable α settles
	if _missile_id != "" and _telemetry.has(_missile_id + ".alpha_trim"):
		var ty := y0 - (trim / m) * rect.size.y * 0.5
		var xx := rect.position.x
		while xx < rect.end.x - 6.0:
			draw_line(Vector2(xx, ty), Vector2(xx + 6.0, ty), Color(0.4, 0.85, 1.0, 0.5), 1.0)
			xx += 12.0
		draw_string(_font, Vector2(rect.end.x - 32, ty - 3), "trim", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.85, 1.0, 0.7))
	# the trace itself (fills left→right, then scrolls once the window is full)
	var pts := PackedVector2Array()
	for i in _alpha_hist.size():
		var x := rect.position.x + (float(i) / float(ALPHA_HIST_MAX - 1)) * rect.size.x
		pts.append(Vector2(x, y0 - (float(_alpha_hist[i]) / m) * rect.size.y * 0.5))
	draw_polyline(pts, Color(1.0, 0.8, 0.25, 0.9), 1.5)
	draw_string(_font, rect.position + Vector2(6, 13), "±%.2f" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.4))

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
	draw_rect(rect, COL_PANEL_BG)
	draw_rect(rect, COL_PANEL_BORDER, false, 1.0)

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

	# profile polyline (what the receiver saw this look), over a translucent area fill —
	# the fill is the SAME per-cell data given visual weight (chrome, nothing recomputed)
	if _profile_db.size() >= 2:
		var pts := PackedVector2Array()
		for i in _profile_db.size():
			pts.append(Vector2(_cfar_x(i, rect), _cfar_y(float(_profile_db[i]), rect)))
		# per-segment quads, NOT one big polygon: a 512-point noisy trace routinely fails the
		# renderer's ear-clipping triangulation ("Invalid polygon data"); each quad is convex
		# so it always draws. Vertex alpha fades curve → baseline.
		var top := Color(0.5, 0.8, 1.0, 0.10)
		var bot := Color(0.5, 0.8, 1.0, 0.0)
		var base_y := rect.end.y
		for i in pts.size() - 1:
			draw_polygon(
				PackedVector2Array([pts[i], pts[i + 1], Vector2(pts[i + 1].x, base_y), Vector2(pts[i].x, base_y)]),
				PackedColorArray([top, top, bot, bot]))
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
			var dp := Vector2(_cfar_x(i, rect), _cfar_y(float(_profile_db[i]), rect))
			_glow(dp, 9.0, Color(0.4, 1.0, 0.4, 0.45))
			draw_circle(dp, 3.0, Color(0.4, 1.0, 0.4))

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
	draw_rect(_plan_view, COL_PANEL_BG)
	draw_rect(_plan_view, COL_PANEL_BORDER, false, 1.0)

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
			_glow(p, 18.0, Color(c.r, c.g, c.b, 0.30))
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
		_glow(fp, 16.0, Color(fc.r, fc.g, fc.b, 0.30))
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

# --- ESM / PRI view (slice 6) -------------------------------------------------
# Two stacked panels from core telemetry. TOP: a TOA raster — each intercepted pulse a vertical tick
# over [0, dwell), colored by its assigned emitter index (interleaved chaos resolving into rows).
# BOTTOM: the difference HISTOGRAM — bars over the τ-axis (the handshake pri_axis_us), the flat
# detection threshold (CORE output, NEVER recomputed here — HANDOFF §1), and a green marker per
# detected PRI. Toggling the deinterleaver rung leaves the bars + threshold untouched and only
# adds/removes the phantom-subharmonic marker (cdif marks 2×min_PRI; sdif doesn't — same bars, same
# line, different markers).

func _esm_color(idx: int) -> Color:
	# assigned emitter index → a distinct hue; 0 (unassigned / spurious) → grey. Built inline
	# (GDScript const-Color arrays are brittle across versions; the per-pulse cost is negligible).
	if idx <= 0:
		return Color(0.55, 0.55, 0.55, 0.7)
	var pal := [Color(0.4, 0.8, 1.0), Color(1.0, 0.7, 0.3), Color(0.5, 1.0, 0.5),
		Color(1.0, 0.5, 0.9), Color(0.9, 0.9, 0.4), Color(0.6, 0.7, 1.0)]
	return pal[(idx - 1) % pal.size()]

func _draw_esm() -> void:
	var vp := get_viewport_rect().size
	var full := Rect2(PLOT_L, PLOT_T, vp.x - PLOT_L - PLOT_R, vp.y - PLOT_T - PLOT_B)
	var gap := 44.0
	var raster := Rect2(full.position.x, full.position.y, full.size.x, full.size.y * 0.30)
	var histo := Rect2(full.position.x, raster.end.y + gap, full.size.x, full.end.y - (raster.end.y + gap))
	_draw_esm_raster(raster)
	_draw_esm_histogram(histo)

func _draw_esm_raster(rect: Rect2) -> void:
	draw_rect(rect, COL_PANEL_BG)
	draw_rect(rect, COL_PANEL_BORDER, false, 1.0)
	draw_string(_font, rect.position + Vector2(2, -6),
		"TOA raster — intercepted pulses, colored by recovered emitter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var span: float = _dwell_us if _dwell_us > 0.0 else 1.0
	for i in _esm_toa.size():
		var t := float(_esm_toa[i])
		var x := rect.position.x + clampf(t / span, 0.0, 1.0) * rect.size.x
		var idx: int = int(_esm_assign[i]) if i < _esm_assign.size() else 0
		draw_line(Vector2(x, rect.position.y + 5), Vector2(x, rect.end.y - 5), _esm_color(idx), 1.0)
	# time-axis labels (ms)
	var nt := 4
	for ti in range(nt + 1):
		var frac := float(ti) / nt
		var gx := rect.position.x + frac * rect.size.x
		draw_string(_font, Vector2(gx - 8, rect.end.y + 14), "%.0f" % (frac * span / 1000.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	draw_string(_font, Vector2(rect.position.x + rect.size.x * 0.5 - 26, rect.end.y + 28),
		"time (ms)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))

func _draw_esm_histogram(rect: Rect2) -> void:
	draw_rect(rect, COL_PANEL_BG)
	draw_rect(rect, COL_PANEL_BORDER, false, 1.0)
	draw_string(_font, rect.position + Vector2(2, -6),
		"difference histogram — peaks at each emitter's PRI (▼ = detected)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var n := _esm_hist.size()
	if n == 0:
		return
	var hi := maxf(1.0, _esm_hist_hi)
	# the τ-axis span (µs): last bin center + half a bin = n·bin_us = max_lag. Bars index by cell;
	# the PRI markers map τ→x by the SAME span, so a marker sits over its bar (see the note).
	var span_us: float = _pri_axis[n - 1] + (_pri_axis[1] - _pri_axis[0]) * 0.5 if _pri_axis.size() == n else float(n)
	# bars
	var bw := rect.size.x / float(n)
	for i in n:
		var h := float(_esm_hist[i])
		if h <= 0.0:
			continue
		var bh := (h / hi) * rect.size.y
		var x := rect.position.x + float(i) * bw
		draw_rect(Rect2(x, rect.end.y - bh, maxf(1.0, bw - 0.4), bh), Color(0.5, 0.75, 1.0, 0.85))
	# threshold (flat line, CORE output — never recomputed here)
	if _esm_thresh.size() == n:
		var ty := rect.end.y - (float(_esm_thresh[0]) / hi) * rect.size.y
		draw_line(Vector2(rect.position.x, ty), Vector2(rect.end.x, ty), Color(1.0, 0.5, 0.3), 1.5)
		draw_string(_font, Vector2(rect.end.x - 60, ty - 4), "threshold",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.7, 0.5))
	# detected-PRI markers (green ▼ + the value): the phantom subharmonic appears under cdif, gone under sdif
	for pv in _esm_pri:
		var tau := float(pv)
		var x := rect.position.x + clampf(tau / span_us, 0.0, 1.0) * rect.size.x
		_glow(Vector2(x, rect.position.y + 8.0), 11.0, Color(0.4, 1.0, 0.4, 0.4))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, rect.position.y + 13), Vector2(x - 5, rect.position.y + 3), Vector2(x + 5, rect.position.y + 3)]),
			Color(0.4, 1.0, 0.4))
		draw_string(_font, Vector2(x - 13, rect.position.y + 27), "%.0f" % tau,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 1.0, 0.6))
	# τ-axis labels (µs)
	var na := 5
	for ti in range(na + 1):
		var gx := rect.position.x + float(ti) / na * rect.size.x
		draw_string(_font, Vector2(gx - 12, rect.end.y + 14), "%.0f" % (float(ti) / na * span_us),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	draw_string(_font, Vector2(rect.position.x + rect.size.x * 0.5 - 22, rect.end.y + 28),
		"PRI τ (µs)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))

# --- GPS / sky view (slice 7) -------------------------------------------------
# Two panels from core telemetry. TOP: a polar SKY PLOT (zenith center, horizon edge) — each
# satellite at radius ∝ (90−el) and angle = az, colored in-solve (green) / masked-or-excluded (grey)
# / faulted-excluded (orange). A spread constellation fills the sky (low DOP); a clustered one bunches
# (high DOP) — the geometry→DOP visual. BOTTOM: a RESIDUAL bar chart — |sat_resid_m| per satellite;
# the spoofed satellite's bar SPIKES (the RAIM visual). The DOP/pos_err/raim_flag SCALARS render in
# the left readout (_update_readout skips these arrays). All core output — nothing recomputed here.

func _gps_color(i: int, used: bool, fault_sat: int) -> Color:
	if fault_sat == i + 1:                    # fault_sat is a 1-based CONFIGURED index (0 = none)
		return Color(1.0, 0.55, 0.15)         # faulted / excluded — orange
	if used:
		return Color(0.4, 1.0, 0.5)           # in-solve — green
	return Color(0.6, 0.6, 0.6)               # masked / excluded / not-used — grey

const GPS_PLOT_L := 268.0         # a wider left inset than PLOT_L so the sky plot + residual bars
                                  # clear the (tall, ~17-key) DOP/RAIM scalar readout panel on the left

func _draw_gps() -> void:
	var vp := get_viewport_rect().size
	var full := Rect2(GPS_PLOT_L, PLOT_T, vp.x - GPS_PLOT_L - PLOT_R, vp.y - PLOT_T - PLOT_B)
	var sky_h := full.size.y * 0.60
	var sky := Rect2(full.position.x, full.position.y, full.size.x, sky_h)
	var bars := Rect2(full.position.x, sky.end.y + 40.0, full.size.x, full.end.y - (sky.end.y + 40.0))
	_draw_gps_sky(sky)
	_draw_gps_resid(bars)

func _draw_gps_sky(rect: Rect2) -> void:
	draw_string(_font, rect.position + Vector2(2, -6),
		"sky plot — satellites at az/el (zenith center, horizon edge); spread → low DOP, clustered → high DOP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var c := rect.position + rect.size * 0.5
	var R := minf(rect.size.x, rect.size.y) * 0.46
	# filled sky disc + horizon + elevation rings (30°, 60°) + zenith dot
	draw_circle(c, R, COL_PANEL_BG)
	draw_arc(c, R, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 1.0)
	for el_ring in [30.0, 60.0]:
		draw_arc(c, R * (1.0 - el_ring / 90.0), 0.0, TAU, 48, Color(1, 1, 1, 0.10), 1.0)
	draw_circle(c, 2.0, Color(1, 1, 1, 0.35))
	# azimuth spokes + labels (0/90/180/270°, world az from +x, CCW, screen y up)
	for az_deg in [0.0, 90.0, 180.0, 270.0]:
		var a := deg_to_rad(az_deg)
		var edge := c + Vector2(R * cos(a), -R * sin(a))
		draw_line(c, edge, Color(1, 1, 1, 0.08), 1.0)
		draw_string(_font, edge + Vector2(-8, -4), "%d°" % int(az_deg),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
	# satellites
	var fault_sat := int(_telemetry.get(_gps_rx + ".fault_sat", 0)) if _gps_rx != "" else 0
	var n := _gps_az.size()
	for i in n:
		var az := deg_to_rad(float(_gps_az[i]))
		var el := clampf(float(_gps_el[i]), 0.0, 90.0)
		var r := R * (1.0 - el / 90.0)
		var p := c + Vector2(r * cos(az), -r * sin(az))
		var used: bool = bool(_gps_used[i]) if i < _gps_used.size() else true
		var col := _gps_color(i, used, fault_sat)
		_glow(p, 13.0, Color(col.r, col.g, col.b, 0.35))
		draw_circle(p, 5.0, col)
		draw_string(_font, p + Vector2(7, -6), "sv%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	_gps_sky_legend(rect)

func _gps_sky_legend(rect: Rect2) -> void:
	var x := rect.end.x - 140.0
	var y := rect.position.y + 14.0
	draw_circle(Vector2(x + 6, y), 5.0, Color(0.4, 1.0, 0.5))
	draw_string(_font, Vector2(x + 18, y + 4), "in solve", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.7))
	draw_circle(Vector2(x + 6, y + 16), 5.0, Color(0.6, 0.6, 0.6))
	draw_string(_font, Vector2(x + 18, y + 20), "masked/excluded", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
	draw_circle(Vector2(x + 6, y + 32), 5.0, Color(1.0, 0.55, 0.15))
	draw_string(_font, Vector2(x + 18, y + 36), "faulted", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.7, 0.4))

func _draw_gps_resid(rect: Rect2) -> void:
	draw_rect(rect, COL_PANEL_BG)
	draw_rect(rect, COL_PANEL_BORDER, false, 1.0)
	draw_string(_font, rect.position + Vector2(2, -6),
		"range residuals |r| per satellite — the spoofed satellite's bar spikes (the RAIM signature)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var n := _gps_resid.size()
	if n == 0:
		return
	var fault_sat := int(_telemetry.get(_gps_rx + ".fault_sat", 0)) if _gps_rx != "" else 0
	var hi := 1.0
	for v in _gps_resid:
		hi = maxf(hi, absf(float(v)))
	var bw := rect.size.x / float(n)
	for i in n:
		var mag := absf(float(_gps_resid[i]))
		var bh := (mag / hi) * (rect.size.y - 6.0)
		var x := rect.position.x + float(i) * bw
		var used: bool = bool(_gps_used[i]) if i < _gps_used.size() else true
		var col := _gps_color(i, used, fault_sat)
		draw_rect(Rect2(x + bw * 0.15, rect.end.y - bh, maxf(1.0, bw * 0.7), bh), col)
		draw_string(_font, Vector2(x + bw * 0.5 - 8, rect.end.y + 14), "sv%d" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	draw_string(_font, Vector2(rect.position.x + 2, rect.position.y + 12), "max |r| = %.0f m" % hi,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
