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
# Slice-23 6-DOF: a handshake `airframe_6dof` marker (a missile carrying :af_cy_beta) upgrades the 2-D
# airframe overlay to a terrain-style 3-D view (the out-of-plane trail) + the 3-ring cycler. The 3-D
# scene reuses the slice-18 _t3d_* SubViewport machinery (camera/env/markers/trail), minus the terrain.
var _airframe_6dof := false        # handshake airframe_6dof — the 3-D-airframe discriminator
# Slice-26 RADOME: a missile carrying an authored :radome_slope. Reuses the 3-D airframe view above
# UNCHANGED; its only effect is that _enter_airframe3d_mode DROPS the shared fidelity button (there
# is no rung to cycle — the lesson is the radome_slope slider). Slice-16's Option-P′, second use.
var _radome_view := false          # handshake radome_view — the DROP-THE-BUTTON marker
# Slice-32 SEEKER FOV: a missile carrying an authored :seeker_fov_deg. Same job as `_radome_view` for
# the same reason — a FOV wire is also a two-angle host, so without a marker the dispatch would fall
# through to slice 25's `seeker_axes` cycler, whose other position (`:pitch_plane`) leaves the WINDOW
# LIVE on a missile that ALSO misses by 2000 m for a wholly unrelated reason (two mechanisms in one
# view, which convention 9 exists to prevent). A SEPARATE marker rather than a reuse of `radome_view`
# because the two select different HUD BRANCHES: the radome cascade reads `radome_slope`/
# `radome_residual`/…, none of which a FOV wire has, and reading them would print 0.0 into a label —
# the stale-readout class this arc has caught seven times.
var _seeker_fov_view := false      # handshake seeker_fov_view — the DROP-THE-BUTTON marker, 3rd use
# Slice-34 GIMBAL: a missile carrying an authored :gimbal_tau_s. ⚠⚠ THIS MARKER EXISTS BECAUSE THE
# LOADER'S REFUSAL LEAVES A HOLE THIS FILE WOULD FALL THROUGH SILENTLY. `scenario.jl` refuses
# `seeker_fov_deg` beside a head — a gimballed seeker has NO body-fixed window, its body-fixed limit
# is the mechanical STOP — so a gimbal wire raises `radome_view` (it HAS glass) and NOT
# `seeker_fov_view`, and without a marker of its own the dispatch below would fall past BOTH FOV
# branches into slice 26/27/28's RADOME cascade. That failure is worse than the stale-readout class
# this arc has caught eight times, because NOTHING IN IT IS STALE: a gimbal wire carries
# `radome_slope`, `radome_residual*`, `radome_slope_worst` and `omega_q`/`omega_r`, so every number
# the cascade reads is LIVE and PLAUSIBLE. It would print a confident ring/quiet verdict about the
# GLASS on a wire whose whole subject is the HEAD — the wrong subject, from real telemetry, and not
# one test would fail.
# ⚠ The BUTTON needs no edit at either site (`radome_view` is raised here too and already drops it —
# slice 33's finding, second occurrence); what this marker selects is the HUD BRANCH ALONE.
var _gimbal_view := false          # handshake gimbal_view — 4th marker of the drop-the-button family
# Slice-34 DISPLAY-ONLY LATCH, the head's own equivalent of `_fov_lost` and NOT a reuse of it: the two
# read DIFFERENT core booleans (`gimbal_valid`, about the DETECTOR window off the HEAD axis, against
# `seeker_valid`, about the body-fixed window off the NOSE) and a gimbal wire ships only the first.
# ⚠ Sharing the variable would be safe today and wrong the moment a wire carried both — which the
# loader refuses, so the separation is what keeps that refusal visible in the client too.
var _gimbal_lost := false
# Slice-35 RATE-LIMITED SERVO marker. ⚠⚠ A BRANCH SELECTOR, NOT A HOLE PLUG — the marker-hole re-check
# the plan demanded came back NEGATIVE (a slice-35 wire is a slice-34 wire PLUS one key; the loader
# refuses nothing extra and `gimbal_view` routes it to a branch that is still about the HEAD). What it
# selects is the half slice 34's HUD cannot say: those lines pair the tracking error against the
# DETECTOR WINDOW, which is authored WIDE here and never binds, so they would report a comfortable
# budget and never mention the SERVO — every number true, the slice invisible. See the core marker.
var _gimbal_rate_view := false     # handshake gimbal_rate_view — 5th marker of the family
# Slice-36 HANDOVER BASKET marker. ⚠⚠ AND THIS ONE IS **BOTH** — slice 34's HOLE PLUG *and* slice 32's
# BUTTON DROP — which is why slice 35's "a branch selector, not a hole plug" must NOT be carried
# forward to it. Two independent failures, and the first is one no earlier slice of this arc could have
# had, because THIS IS THE FIRST NO-GLASS WIRE SINCE SLICE 25:
#   (1) THE BUTTON. Slices 26–35 all dropped it for free by riding `_radome_view`, which is raised by
#       authored glass. This wire has none (the drop is measured — a handover error is EXACTLY inert on
#       the trajectory without a window or an index), and `_seeker_fov_view` is absent too because the
#       loader REFUSES `seeker_fov_deg` beside a head. So both drop-branches in
#       `_enter_airframe3d_mode` fail, the dispatch falls through to slice 25's `seeker_axes` cycler,
#       and the button comes BACK — whose other position (`:pitch_plane`) leaves the handover error LIVE
#       beside slice 25's unrelated 2000 m blind miss. Slice 26's argument, and the drop therefore needs
#       BOTH sites (its 4th occurrence), because `_update_fid_btn`'s "seeker_axes" arm re-shows it
#       unconditionally and never reaches the "airframe" arm's two defences.
#   (2) THE HUD. `_gimbal_rate_view` IS raised here (the servo is this slice's one slider), so without
#       this marker slice 35's lines take the wire — and its line 4, the one it calls THE CURE, reads
#       `radome_slope_est` / `radome_slope_worst`, neither of which exists on a glass-free wire. It
#       would print `R̂ +0.000   aim point R₀+2A +0.000`: the stale-readout class's 9th occurrence,
#       landing on another slice's payoff line, with `_radome_qpeak` structurally frozen at 0.0 beside
#       it. ⇒ not merely slice 35's INVISIBLE SLICE (every number true, the subject unmentioned) but an
#       invisible slice PLUS two fabricated zeros.
var _gimbal_handover_view := false # handshake gimbal_handover_view — 6th marker, and the first to
                                   # plug a BUTTON hole and a HUD hole at once
# Slice-37 SERVO REFERENCE FRAME marker. ⭐⭐ AND IT IS THE FIRST OF THIS FAMILY WHOSE BUTTON JOB IS THE
# **OPPOSITE** OF EVERY MARKER ABOVE — it UN-DROPS the shared fidelity button. Slices 26–36 each had no
# rung to cycle (the lesson was a slider every time), so `_radome_view`, `_seeker_fov_view` and
# `_gimbal_handover_view` all HIDE it and 32/33/34/35 rode one of them for free. `:seeker_head` is a
# genuine two-rung fidelity — the first since slice 25 — so here THE BUTTON IS THE LESSON, and this wire
# raises `_radome_view`, `_gimbal_view` AND `_gimbal_rate_view`, i.e. the dispatch below would hide it
# three times over. ⚠ THE RULE THIS FAMILY TEACHES IS NOT "a gimbal marker drops the button"; it is
# *the button shows what there is to cycle, and these wires mostly have nothing*. Written here because
# a later slice reading only the six markers above would learn the wrong one.
# ⚠ AND THE HUD HOLE IS REAL TOO, so this is slice 36's "BOTH" shape rather than slice 35's "branch
# selector": without it `_gimbal_rate_view` wins and draws slice 35's servo block, whose headline pairs
# `head_rate_dps` against the rate cap — a number that MEANS A DIFFERENT THING ON EACH SIDE OF THIS
# BUTTON (body-frame demand, which includes tracking out the missile's own rotation, against
# inertial-frame demand with body motion already rejected). Every number would be true and the invited
# arithmetic — *press it, watch the demand fall, conclude the stabilized head is the cheaper build* —
# is exactly the inference the core's own seam comment forbids. Slice 36's INVITED ARITHMETIC defect,
# in a new quantity, and the fix is that the frame is NAMED in the same string as the number.
var _gimbal_frame_view := false    # handshake gimbal_frame_view — 7th marker, and the FIRST that
                                   # RESTORES the button rather than dropping it
# Slice-36 DISPLAY-ONLY FREEZE on the shipped requirement (see `_handover_peak_hold`): `head_off_peak_deg`
# is a running maximum, so it runs to 179.4998° at CPA on EVERY arm, hit or miss, and a peak cannot
# forget. This holds the last sample taken while r > 200 m — the same gate the core's own requirement
# claim uses. A FOURTH instrument shape beside slice 27's decaying peak-hold, slice 32's latch and slice
# 35's EMA duty: a RANGE-GATED FREEZE, and it is the only one whose reason is the endgame rather than the
# ring. ⚠ Instrument, not physics: it selects which shipped sample to draw.
var _handover_peak := 0.0
# Slice-36 DISPLAY-ONLY LATCH on the head's BIRTH angle — the tick-1 body-frame LOS azimuth, which is
# where the handover put the head and the start of the 33.2° journey the servo has to chase. Latched
# rather than shipped because it is a ONE-TICK fact (the seam's handover branch runs exactly once) and
# the core has no telemetry shape for "the value this key had at t = 0" — while the HUD needs it beside
# the live value or the excursion is invisible and the lesson reads as an assertion.
# ⚠ The sentinel is NAN, not 0.0: an azimuth of exactly 0.000000° is a REAL birth angle (it is what
# `err = −18.105` produces — the domain's own lower endpoint), so a zero sentinel would be indistinguish-
# able from the arm the domain is bounded by.
var _handover_los0 := NAN
# Slice-35 DISPLAY-ONLY SATURATION DUTY — the servo's own instrument, and a THIRD shape beside slice
# 27's decaying peak-hold and slice 32's latch, because it answers a third kind of question. The rate
# limit binds on a FRACTION of ticks (measured: 8.6 % at the slider's ceiling, 64.6 % at the shipped
# default, 97.1 % at its floor on the same design), so neither an instantaneous read (it would flicker
# with the ring, ~2 Hz) nor a latch (it would go true on every arm and stay) says anything. What a
# student needs is the DUTY, so this is an exponential moving average of the core's own `head_rate_sat`
# FLAG — the same ~0.5 s time constant as the peak-hold above, for the same reason (comfortably longer
# than the ring's half-period, so the verdict is steady across a whole cycle).
# ⚠ INSTRUMENT, NOT PHYSICS (convention 13): it smooths a shipped boolean and decides only WHICH
# STRING to draw. It computes no threshold, no rate comparison and no stability test — the core ships
# the flag as its own branch predicate precisely so the client never re-derives `demand > cap` across
# two unit conversions and a `max(·, 0)`.
var _servo_duty := 0.0
# Slice-27 DISPLAY-ONLY peak-hold on the body rate (see _airframe3d_on_state): a limit cycle crosses
# zero twice per cycle, so an instantaneous verdict mislabels half the frames. Instrument, not physics.
var _radome_qpeak := 0.0
# Slice-32 DISPLAY-ONLY LATCH on "this run has lost lock". A LATCH rather than slice 27's decaying
# peak-hold, because the two instruments answer different questions: a limit cycle crosses zero twice
# per cycle so its verdict must FORGET (else a cured missile reads ringing forever), while a track
# break is a THING THAT HAPPENED — the missile is coasting on a stale rate from then on, and an
# instantaneous `seeker_valid` would blink back to 1 the moment the runaway geometry swings the LOS
# back through the window and label a lost missile "tracking". Instrument, not physics; cleared on
# reset with the trails.
var _fov_lost := false
var _af3d_missile := ""            # the interceptor id (the trail source)
var _af3d_target := ""             # the target id (the +Y off-plane marker)
var _af3d_nose_mesh: ImmediateMesh = null   # the nose-direction vector (from att_q), coupled/six_dof only
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
# Slice-19 inner α/g autopilot: the HEADLINE readout — the FLIGHT-CONDITION g-ceiling
# `a_max_aero = Q·S·C_Lα·α_max/m` against the guidance `a_demand`, both live, on one axis. THE CROSSING
# IS THE VERDICT (the analog of slice-18's clearance sign): where the demand rises above the ceiling the
# air cannot give the missile the g PN is asking for. DISPLAY-ONLY histories of the core's own scalars —
# nothing is recomputed here (HANDOFF §1 / convention 13). Present ONLY when the `:alpha` rung ships the
# keys, so slices 16/17 (airframe_view, no α/g keys) draw nothing new.
var _ceil_hist: Array = []        # <id>.a_max_aero — the ceiling
var _demand_hist: Array = []      # <id>.a_demand — the PRE-clamp PN demand
var _aero_sat_now := false        # <id>.aero_sat — the ceiling-binding tell (lights the panel)
# SLICE-22 NONLINEAR C_L(α) / TRUE STALL — ⚠ THE BREACH INDICATOR CANNOT KEY ON `aero_sat` ANY MORE
# (gate-2 G10, and it is BY DESIGN, not a bug to route around). Under an authored stall the ceiling
# `a_max_aero` drops to the lift curve's INTERIOR PEAK, while `aero_sat` still keys off the **α_max
# CLAMP** — the higher, LINEAR limit. So there is a real regime, **past the physics ceiling but with
# the command not yet pegged**, where the demand exceeds the ceiling and `aero_sat` STAYS 0. Keying
# the indicator on `aero_sat` would UNDER-REPORT the very breach this slice is about.
# ⭐ GATE 3 MEASURED HOW BADLY: on the shipped wire `aero_sat` is 36.7% on the PARKED (linear) arm
# and 37.3% on the STALL arm — it BARELY MOVES, because both arms share the same α_max clamp. The
# discriminator is `post_stall`: **0/3793 parked vs 1461/3820 stalled.** That is the whole reason
# this key exists.
# PRESENCE-GATED (the core's own discipline): slices 19/20/21 ship NO `post_stall` key, so
# `_has_post_stall` stays false there and the panel keeps keying on `aero_sat` EXACTLY as before —
# this is additive, and those three views are untouched.
var _post_stall_now := false      # <id>.post_stall — |α| ≥ α_stall: the AIRFRAME is past its peak
var _has_post_stall := false      # does this wire ship the key at all? (absent on slices 19–21)
const AERO_HIST_MAX := 480        # match the α strip's window (~8 s at the emit cadence)
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
# Slice-23 6-DOF: the airframe cycler is PER-SCENARIO (the _autopilot_rungs precedent). Slice 17/19
# keep the 2-ring; a slice-23 (airframe_6dof) scenario upgrades to the 3-ring in _enter_airframe3d_mode.
var _airframe_rungs: Array = AIRFRAME_RUNGS.duplicate()
const ATMOSPHERE_RUNGS := ["constant", "exponential"]   # slice-21 atmosphere cycler (authored ρ ↔ ρ₀·exp(−z/H))
# Slice-24 BANK-TO-TURN: the STEERING cycler on the HELD :six_dof plant. skid_to_turn (slice 23 — lift
# in two planes at once, no roll) ↔ bank_to_turn (lift in ONE plane, ROLL to point it with a finite
# τ_roll lag). Shown when the handshake fidelity carries `steering` (the airframe cycler is dropped —
# convention 9, ONE toggled fidelity: airframe is HELD :six_dof). The cross-fidelity dependency: this
# rung is inert without :airframe:six_dof (the scalar plant has no roll DOF).
const STEERING_RUNGS := ["skid_to_turn", "bank_to_turn"]
# Slice-25 A SEEKER IN THE 6-DOF LOOP: the SEEKER-AXES cycler on the HELD :six_dof skid-to-turn plant.
# pitch_plane (slice 11's SCALAR in-plane tracker — ω ∥ ±ŷ, so the cross-range command is never FORMED
# and the missile flies straight down the x–z plane) ↔ az_el (an azimuth/elevation PAIR → the LOS-rate
# VECTOR ω = û × û̇ → the out-of-plane component survives → intercept). Shown when the handshake
# fidelity carries `seeker_axes`; it is checked BEFORE `steering`/`airframe` (the "check the NEW key
# first" rule — slices 21/22/24, 4th occurrence) so the ONE toggled fidelity owns the shared button.
const SEEKER_AXES_RUNGS := ["pitch_plane", "az_el"]
# Slice-37: the GIMBAL SERVO'S REFERENCE FRAME (body_referenced ↔ space_stabilized) — the first rung
# on the shared button since slice 25, and the ORDER IS THE SHOWCASE'S: the wire opens on
# `body_referenced` (slice 34/35/36's shipped servo, quiet and hitting at this wire's R̂) so the FIRST
# press is the one that breaks it. ⚠ Mirrors the core's `SEEKER_HEAD_MODES` and must stay in that
# order — a client ring that started on the other rung would open the showcase on its own punchline.
const SEEKER_HEAD_RUNGS := ["body_referenced", "space_stabilized"]
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
var _t3d_missile: Node3D = null   # slice-23 3-D airframe view: the interceptor marker (cyan)
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
	# Slice-23 3-D-airframe discriminator (a missile carrying :af_cy_beta) — recognized alongside
	# airframe_view; the dispatch below routes it to the 3-D view BEFORE the 2-D airframe branch.
	_airframe_6dof = bool(obj.get("airframe_6dof", false))
	# Slice-26 RADOME discriminator (a missile carrying an authored :radome_slope). It does NOT pick
	# a view — it reuses the slice-23 3-D airframe view wholesale — its only job is to make
	# _enter_airframe3d_mode DROP the shared button, because slice 26 has no fidelity rung at all
	# (the lesson is the radome_slope slider). Slice-16's Option-P′ mechanism, second use.
	_radome_view = bool(obj.get("radome_view", false))
	# Slice-32 SEEKER-FOV discriminator (a missile carrying an authored :seeker_fov_deg). Same shape:
	# it does NOT pick a view — the slice-23 3-D airframe view is reused wholesale — its only job is
	# to make _enter_airframe3d_mode DROP the shared button, because slice 32 has no fidelity rung
	# either (the lesson is the FOV slider against the crossing-speed slider). Option-P′, third use.
	_seeker_fov_view = bool(obj.get("seeker_fov_view", false))
	# Slice-34 GIMBAL discriminator (a missile carrying an authored :gimbal_tau_s). Same shape as the
	# three above — it does NOT pick a view, the slice-23 3-D airframe view is reused wholesale — but
	# unlike them its job is NOT the button (see `_gimbal_view`): `radome_view` already drops that.
	# Its job is the HUD BRANCH, which is checked FIRST and is a SWITCH ahead of the radome cascade.
	_gimbal_view = bool(obj.get("gimbal_view", false))
	# Slice-35 RATE-LIMITED SERVO discriminator (a missile carrying an authored :gimbal_rate_dps).
	# ⚠⚠ IT IS A BRANCH SELECTOR, NOT A HOLE PLUG, and the core says why at the marker: a slice-35 wire
	# is a slice-34 wire PLUS one key, so `gimbal_view` routes it correctly and nothing is silently
	# re-routed (the marker-hole re-check came back NEGATIVE). What it selects is the half slice 34's
	# HUD cannot say — that HUD pairs the tracking error against the DETECTOR WINDOW, which is authored
	# WIDE here and never binds, so it would report a comfortable budget and never mention the SERVO.
	# Every number it drew would be true; the slice would simply be invisible.
	# ⚠ It does NOT pick a view (the slice-23 3-D airframe view is reused wholesale) and it does NOT
	# touch the button — `radome_view` already drops that at both sites.
	_gimbal_rate_view = bool(obj.get("gimbal_rate_view", false))
	# Slice-36 HANDOVER-BASKET discriminator (a missile carrying an authored :gimbal_handover_err_deg).
	# ⚠⚠ AND IT IS THE FIRST OF THIS FAMILY TO DO BOTH JOBS — the BUTTON *and* the HUD BRANCH — because
	# it is the first NO-GLASS wire since slice 25, so `radome_view` is absent and the free ride that
	# dropped the button for slices 26–35 has ended. See `_gimbal_handover_view`'s own comment for the
	# two failures it prevents, and note that slice 35's "branch selector, not a hole plug" sentence
	# does NOT transfer to it.
	_gimbal_handover_view = bool(obj.get("gimbal_handover_view", false))
	# Slice-37 SERVO-REFERENCE-FRAME discriminator, and ⚠ it is the FIRST of this family gated on a
	# **FIDELITY** rather than a comp key — deliberately, because the thing that distinguishes a
	# slice-37 wire IS the rung (it reuses slice 34's head verbatim, so there is no slice-37 comp key
	# to gate on). It does BOTH jobs like slice 36's marker, but the BUTTON job is the OPPOSITE one:
	# it RESTORES the button rather than dropping it. See `_gimbal_frame_view`'s own comment.
	_gimbal_frame_view = bool(obj.get("gimbal_frame_view", false))
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
	elif _airframe_view and _airframe_6dof:
		# Slice-23 6-DOF: the out-of-plane engagement needs a TRUE 3-D view (the pitch plane's
		# out-of-plane discard is invisible in the 2-D side-on airframe view). Recognized BEFORE the
		# 2-D airframe branch in _setup_spatial_fid_btn (the slice-21/22 "check the new one first"
		# precedent) and BEFORE terrain would be a different 3-D view (the multi-view discriminator:
		# terrain_grid → slice-18 terrain 3-D, airframe_6dof → this).
		_enter_airframe3d_mode(obj)
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
	if _fidelity.has("atmosphere"):
		# Slice-21 THE EXPONENTIAL ATMOSPHERE — **the ceiling you lower by CLIMBING**. The scenario ships
		# airframe_view + `:airframe` + `:atmosphere`, so it would otherwise be CAPTURED by the airframe
		# branch below. CHECKED FIRST — BEFORE both airframe branches — ON PURPOSE, and this is the
		# slice-13/14 rule ("a scenario ships several keys, all but one HELD FIXED; the ONE button must
		# toggle the LESSON's key, not the held ones" — convention 9), applied for the third time.
		# `:airframe` is AUTHORED FIXED at :pitch_coupled here: the missile must stay COUPLED for a lift
		# ceiling to EXIST at all, so it is this slice's REFERENCE ARM, not its contrast. Checking
		# atmosphere first is also strictly safer than slotting it between the two airframe branches: an
		# atmosphere scenario that somehow carried NO `:airframe` key would fall into the slice-16 DROP
		# branch and lose its button entirely.
		#
		# Under :constant the missile flies slices 8–20's authored ρ, the ceiling never binds, and it HITS;
		# under :exponential ρ = ρ₀·exp(−z/H) falls as it CLIMBS, the ceiling collapses to meet the demand,
		# and it MISSES by ~360 m. The H slider (an auto knob) sets how FAST the air thins. SAME
		# `_fid_kind` treatment as the airframe view — the aero strip (slice 19), the α strip (16/17) and
		# the nose-vs-velocity vectors are all gated on `_airframe_view`, so they carry over UNTOUCHED;
		# only `_draw_missile`'s `_fid_kind` gate needed this kind added. Class 4c — physics-changing, NO
		# RNG, live-settable, NO set_fidelity guard.
		_fid_kind = "atmosphere"
		_prop_btn.visible = true
		if _prop_btn.pressed.is_connected(_on_prop_pressed):
			_prop_btn.pressed.disconnect(_on_prop_pressed)
		if not _prop_btn.pressed.is_connected(_on_atmosphere_pressed):
			_prop_btn.pressed.connect(_on_atmosphere_pressed)
		_prop_btn.tooltip_text = "Cycle atmosphere (set_fidelity): constant ↔ exponential"
		# Seed extents to fit the 22 km / 14 km climbing intercept (vs the airframe view's 4×4 km); they
		# only grow, so starting at the engagement's own scale just avoids a rescale on the first frames.
		_x_max = 20000.0
		_z_max = 15000.0
	elif _airframe_view and not _fidelity.has("airframe"):
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

# --- slice-23 3-D AIRFRAME view: the out-of-plane engagement ------------------------------------
# The pitch plane's out-of-plane discard is INVISIBLE in the 2-D side-on airframe view (both plants
# look identical from the side — the difference is entirely in y). So a 6-DOF scenario gets a TRUE
# 3-D view, reusing slice-18's terrain SubViewport machinery (_sim_to_3d / _make_t3d_marker /
# _update_t3d_cam / the _t3d_* line meshes) MINUS the terrain heightfield/props. Under :pitch_coupled
# the trail stays FLAT in the x–z plane (the discard); cycle to :six_dof and the SAME PN law YAWS the
# trail OUT toward the +Y target (the discard dies). Pure display — every position is the core's.
func _enter_airframe3d_mode(obj: Dictionary) -> void:
	_mode = "airframe3d"
	_af3d_missile = _airframe_target                # the interceptor (handshake) — the trail source
	_af3d_target = ""                               # resolved from the first :target on the first state
	if _prop_btn.pressed.is_connected(_on_prop_pressed):
		_prop_btn.pressed.disconnect(_on_prop_pressed)
	# SLICE 24 — if the scenario carries a `steering` fidelity, the shared button is the STEERING cycler
	# (skid_to_turn ↔ bank_to_turn) with :airframe HELD :six_dof (convention 9 — the slice-21/22
	# two-view-claiming-keys precedent, "check the NEW key first"). Otherwise it is the slice-23 airframe
	# 3-ring cycler. The 3-D view + trail/nose drawing are shared either way (the bank is a NEW thing to
	# draw on the same scene). VALUE-GUARDED: a slice-23 wire (no `steering`) keeps the airframe cycler.
	# SLICE 25 — checked FIRST (the "check the NEW key first" rule, 4th occurrence): a seeker-axes
	# scenario puts the SEEKER's measurement dimensionality on the shared button, with :airframe HELD
	# :six_dof AND :steering held at the loader default (the scenario omits it) — convention 9, ONE
	# toggled fidelity. VALUE-GUARDED three ways: slice 25 → this cycler, slice 24 (`steering`, no
	# `seeker_axes`) → the steering cycler, slice 23 (neither) → the airframe 3-ring.
	# SLICE 26 — THE RADOME, and it is the ONE case in this whole dispatch that DROPS the button
	# rather than re-pointing it. Checked FIRST (the "check the NEW key first" rule, 5th occurrence).
	# The lesson is the `radome_slope` SLIDER: a radome bends the LOS by ε = R·(look angle), so the
	# missile's own body rate moves the LOS it reports, and past a critical loop gain N·|R| the loop
	# is unstable and the missile shakes itself into a limit cycle. There is NO fidelity rung to
	# cycle (R = 0 is an in-domain slider value AND bit-identical to the radome not existing), so
	# this is slice 16's Option-P′ exactly: recognize the view by its handshake key and HIDE the
	# button (hide + guarded disconnect).
	#
	# ⚠ THE SLICE-20 PRECEDENT DELIBERATELY DOES NOT TRANSFER. Slice 20 also had no rung and kept
	# the INHERITED cycler, because its other position (`:point_mass`) makes induced drag INERT —
	# nothing false is displayed. Here the inherited cycler would be the `seeker_axes` one below,
	# and its other position (`:pitch_plane`) leaves the radome LIVE AND REFRACTING on a missile
	# that ALSO misses by 2000 m for a wholly unrelated reason: two mechanisms compounding in one
	# view, which is what convention 9 exists to prevent, and the "identical signature, different
	# mechanism" trap slice 25 spent a section on. So the button goes, and the slider stays.
	# SLICE 32 — THE SEEKER'S FIELD OF VIEW, checked FIRST (the "check the NEW key first" rule, 6th
	# occurrence) and the SECOND case in this dispatch that DROPS the button rather than re-pointing
	# it. Slice 26's whole argument transfers verbatim: a FOV wire is a two-angle host, so the
	# inherited cycler would be the `seeker_axes` one below, and its other position (`:pitch_plane`)
	# leaves the WINDOW LIVE on a missile that ALSO misses by 2000 m for a wholly unrelated reason.
	# There is no rung to cycle here either — the lesson is the FOV slider against the crossing-speed
	# slider, `fov = 180` being an in-domain value that flies the key-absent trajectory.
	# ⚠ THE ORDER AGAINST `_radome_view` IS A STATEMENT OF INTENT, NOT A SHIPPED PATH: the two markers
	# never co-occur on any scenario in the tree (the radome × FOV corollary is a SECOND mechanism and
	# convention 9 keeps it off the wire — it lives in `test_missile.jl`). The BUTTON outcome is
	# identical either way; only the HUD branch differs, and the FOV framing is the right headline for
	# a wire that has a window at all.
	# SLICE 36 — THE HANDOVER BASKET, checked FIRST (the "check the NEW key first" rule, 7th occurrence)
	# and the THIRD case in this dispatch that DROPS the button — but the FIRST that had to, because
	# ⚠⚠ THIS IS THE FIRST NO-GLASS WIRE SINCE SLICE 25 AND THE FREE RIDE HAS ENDED. Slices 26–35 all
	# dropped the button by riding `_radome_view` below (slice 33 wrote that down as a finding and 34/35
	# inherited it); this wire authors no glass — measured, not stylistic: a handover error is EXACTLY
	# inert on the trajectory without a window or an index, so the wire that isolates the basket is a
	# wire with no radome at all — and the loader refuses `seeker_fov_deg` beside a head, so
	# `_seeker_fov_view` is absent too. Without this branch BOTH drops fail, the dispatch reaches
	# `_fidelity.has("seeker_axes")` below, and the button returns as slice 25's cycler — whose other
	# position (`:pitch_plane`) leaves the handover error LIVE beside slice 25's unrelated 2000 m blind
	# miss. That is slice 26's own argument, and the drop needs BOTH sites (its 4th occurrence): the
	# `"seeker_axes"` arm of `_update_fid_btn` re-shows the button unconditionally and never reaches the
	# `"airframe"` arm's defences. ⚠ THE MIRROR IS THE PROOF: strip this marker in the UI test and the
	# button must come BACK.
	# SLICE 37 — THE SERVO'S REFERENCE FRAME, checked FIRST ("check the NEW key first", 10th occurrence)
	# and ⭐⭐ THE FIRST BRANCH IN THIS DISPATCH SINCE SLICE 25 THAT **KEEPS** THE BUTTON. Every gimbal
	# branch below drops it, because slices 26–36 had no rung to cycle — the lesson was a slider every
	# time. `:seeker_head` IS a rung, it is live-settable with no `set_fidelity` guard (there is no draw
	# topology to flip — measured: over a mid-run press the RNG state stays EQUAL to the never-pressed
	# run's while the trajectories differ by 2.000 m), and THE PRESS IS THE LESSON: at the wire's
	# default R̂ the body-referenced head is quiet and hits, and one press makes the same missile ring
	# 85.4× harder with nothing else changed.
	# ⚠⚠ IT MUST BE FIRST OR IT IS UNREACHABLE — this wire raises `radome_view`, `gimbal_view` AND
	# `gimbal_rate_view`, so all three of the branches below would hide the button before this one ran.
	# That is the OPPOSITE hazard from slice 36's (whose wire raised none of the drop markers and had to
	# ADD a drop); the two are the same lesson from the two sides, which is why both are spelled out.
	# ⚠ AND THE SECOND SITE IS `_update_fid_btn` — but NOT as a defence inside its `"airframe"` arm this
	# time: `_fid_kind` is a NEW value here, so the button's label lives in its own match arm, exactly
	# as slice 24's `"steering"` and slice 25's `"seeker_axes"` do. Both are `_fid_kind` values that
	# appear in NO drawing gate (the 3-D view keys off `_mode`, not `_fid_kind`), which is what makes a
	# new kind free — slice 21's "only `_draw_missile`'s gate needed this kind added" checked, and here
	# the answer is that none did.
	if _gimbal_frame_view:
		_fid_kind = "seeker_head"
		if not _prop_btn.pressed.is_connected(_on_seeker_head_pressed):
			_prop_btn.pressed.connect(_on_seeker_head_pressed)   # guarded for the headless UI test
		_prop_btn.tooltip_text = "Cycle seeker head servo frame (set_fidelity): body_referenced → space_stabilized"
		_prop_btn.visible = true
		_build_airframe3d_scene()
		return
	if _gimbal_handover_view:
		_fid_kind = "airframe"                      # the 3-D view's drawing/badge treatment, unchanged
		_prop_btn.visible = false
		_prop_btn.tooltip_text = ""
		_build_airframe3d_scene()
		return
	if _seeker_fov_view:
		_fid_kind = "airframe"                      # the 3-D view's drawing/badge treatment, unchanged
		_prop_btn.visible = false
		_prop_btn.tooltip_text = ""
		_build_airframe3d_scene()
		return
	if _radome_view:
		_fid_kind = "airframe"                      # the 3-D view's drawing/badge treatment, unchanged
		_prop_btn.visible = false
		_prop_btn.tooltip_text = ""
		_build_airframe3d_scene()
		return
	if _fidelity.has("seeker_axes"):
		_fid_kind = "seeker_axes"
		if not _prop_btn.pressed.is_connected(_on_seeker_axes_pressed):
			_prop_btn.pressed.connect(_on_seeker_axes_pressed)   # guarded for the headless UI test
		_prop_btn.tooltip_text = "Cycle seeker axes (set_fidelity): pitch_plane → az_el"
	elif _fidelity.has("steering"):
		_fid_kind = "steering"
		if not _prop_btn.pressed.is_connected(_on_steering_pressed):
			_prop_btn.pressed.connect(_on_steering_pressed)   # guarded for the headless UI test
		_prop_btn.tooltip_text = "Cycle steering (set_fidelity): skid_to_turn → bank_to_turn"
	else:
		_fid_kind = "airframe"                      # reuse the airframe cycler kind (button/badge/label)
		_airframe_rungs = AIRFRAME_RUNGS + ["six_dof"]  # the 3-ring, built FROM the const (no re-list)
		if not _prop_btn.pressed.is_connected(_on_airframe_pressed):
			_prop_btn.pressed.connect(_on_airframe_pressed)   # guarded for the headless UI test
		_prop_btn.tooltip_text = "Cycle airframe (set_fidelity): point_mass → pitch_coupled → six_dof"
	_prop_btn.visible = true
	_build_airframe3d_scene()

func _build_airframe3d_scene() -> void:
	# The slice-18 _build_terrain_scene scaffolding, duplicated MINUS the terrain mesh + props
	# ("duplicate, don't share" keeps the byte-frozen terrain path untouched). A SubViewport Node3D
	# world: the baked night-sky env, a key + fill light, the interceptor (cyan) + target (orange)
	# markers, the missile→target LOS line, the fading trail, and the nose-direction vector.
	if _t3d_layer != null and is_instance_valid(_t3d_layer):
		_t3d_layer.queue_free()
	_t3d_layer = null
	_t3d_cam = null
	_t3d_trail_pts = []
	_t3d_root = null
	_t3d_sun = null
	_t3d_layer = CanvasLayer.new()
	_t3d_layer.layer = -1                           # BEHIND the Node2D canvas + the UI CanvasLayer
	add_child(_t3d_layer)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t3d_layer.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	holder.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	_t3d_root = root
	_t3d_cam = Camera3D.new()
	_t3d_cam.environment = FX_TERRAIN_ENV           # the shared night-blue sky/glow env
	_t3d_cam.far = 6000.0
	root.add_child(_t3d_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	root.add_child(sun)
	_t3d_sun = sun
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 135.0, 0.0)
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = 0.28
	root.add_child(fill)
	# a faint ground reference plane at z = 0 (the launch-plane floor — a subtle grid gives the eye
	# a horizon so the out-of-plane curve reads as depth, not a wobble).
	_af3d_add_floor(root)
	_t3d_missile = _make_t3d_marker(root, Color(0.45, 0.90, 1.00))   # interceptor (cyan)
	_t3d_target = _make_t3d_marker(root, Color(1.00, 0.62, 0.20))    # target (orange, off the plane)
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
	_af3d_nose_mesh = ImmediateMesh.new()
	var nose := MeshInstance3D.new()
	nose.mesh = _af3d_nose_mesh
	root.add_child(nose)
	# Orbit focus = the engagement midpoint; a 3/4 view (azimuth off the downrange axis + elevated)
	# so BOTH the downrange run (godot +X) AND the cross-range curve into godot −Z are legible —
	# looking straight down either axis would make the out-of-plane curve edge-on and invisible.
	_cam_focus = _sim_to_3d([3100.0, 1050.0, 3700.0])
	_cam_dist = 88.0
	_cam_yaw = 2.36
	_cam_pitch = 0.70
	_update_t3d_cam()

func _af3d_add_floor(root: Node3D) -> void:
	# A dim wireframe grid on the sim z = 0 plane (display only) — a horizon reference so the
	# out-of-plane curve reads as depth. 12×12 lines over the engagement footprint.
	var m := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = m
	root.add_child(mi)
	var x0 := -1000.0; var x1 := 7500.0; var y0 := -3200.0; var y1 := 3200.0
	var col := Color(0.30, 0.42, 0.55, 0.22)
	m.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for k in 13:
		var xx: float = x0 + (x1 - x0) * float(k) / 12.0
		m.surface_set_color(col); m.surface_add_vertex(_sim_to_3d([xx, y0, 0.0]))
		m.surface_set_color(col); m.surface_add_vertex(_sim_to_3d([xx, y1, 0.0]))
		var yy: float = y0 + (y1 - y0) * float(k) / 12.0
		m.surface_set_color(col); m.surface_add_vertex(_sim_to_3d([x0, yy, 0.0]))
		m.surface_set_color(col); m.surface_add_vertex(_sim_to_3d([x1, yy, 0.0]))
	m.surface_end()

func _airframe3d_on_state(obj: Dictionary) -> void:
	_entities.clear()
	for e in obj.get("entities", []):
		var id := str(e.get("id", ""))
		_entities[id] = {"kind": str(e.get("kind", "")), "pos": e.get("pos", [0, 0, 0])}
		if _af3d_missile == "" and str(e.get("kind", "")) == "missile":
			_af3d_missile = id
		if _af3d_target == "" and str(e.get("kind", "")) == "target":
			_af3d_target = id
	# SLICE 27 — a DISPLAY-ONLY PEAK-HOLD on |q|, and it fixes a real defect the shot harness caught.
	# The limit cycle crosses zero TWICE PER CYCLE, so ANY instantaneous |q| > threshold verdict
	# mislabels roughly half the frames: the first slice-27 shot landed at q = −0.301 mid-swing (peak
	# 1.47) and the headline read "loop STABLE" on a ringing missile. Slice 26 has the same structure
	# and merely got lucky with its capture instant.
	# ⚠ THIS IS AN INSTRUMENT, NOT PHYSICS (convention 13). It is a peak-hold meter with decay — the
	# same thing a real rate display does — and it decides only WHICH STRING to draw. It computes no
	# threshold from R, R̂ or N: |R_crit| moves with N and ρ, so a client-side stability test would be
	# physics in GDScript AND wrong the moment a scenario changes N.
	# ⚠ Gated on the slice-27 telemetry key so slice 26's label path is untouched (the same SWITCH
	# discipline as the HUD lines below).
	# ⚠ SLICE 28 — THE PEAK-HOLD READS A DIFFERENT CHANNEL, and that is not a detail. On a slope-CURVE
	# wire the lead angle is in AZIMUTH, so the two seeker channels sit at DIFFERENT points on the same
	# glass and the ring is in YAW (measured: rms r 1.042 against rms q 0.101). A peak-hold left on |q|
	# would meter the quiet channel and label a shaking missile STABLE — the same class of defect the
	# instantaneous verdict had. Gated on the slice-28 telemetry key, so 26/27 keep |q| verbatim.
	if _telemetry.has(_af3d_missile + ".radome_residual"):
		var qn := absf(float(_telemetry.get(_af3d_missile + _ring_channel_key(), 0.0)))
		# decay ~0.97 per state frame at 62.5 Hz ⇒ a ~0.5 s hold, comfortably longer than the
		# ~2 Hz ring's half-period, so the verdict is steady across a whole cycle.
		_radome_qpeak = maxf(qn, _radome_qpeak * 0.97)
	# SLICE 32 — the TRACK-BREAK LATCH, the FOV view's equivalent instrument (see `_fov_lost`). It is
	# RANGE-GATED at r > 200 m for exactly the reason every look-angle number in this slice is: a quiet
	# arm leaves the window for one or two ticks at r = 0.1–0.6 m as the LOS unit vector swings through
	# a large angle in the last millisecond before impact, and latching on THAT would paint every
	# healthy intercept as a lost track at the moment of the hit. The core's own `seeker_valid` is the
	# verdict; the client only remembers it (convention 13).
	if _telemetry.has(_af3d_missile + ".seeker_valid"):
		if float(_telemetry[_af3d_missile + ".seeker_valid"]) < 0.5 \
		   and float(_telemetry.get(_af3d_missile + ".los_range", 0.0)) > 200.0:
			_fov_lost = true
	# SLICE 34 — the HEAD's track-break latch. ⚠ AN INDEPENDENT `if`, NOT AN `elif` OR AN `or` ON THE
	# LINE ABOVE, which is slice 33's own finding one slice later: a chained dispatch would freeze one
	# instrument the moment the other's key appeared. The two keys never co-occur (the loader refuses
	# it), so today the branches are exclusive anyway — but the reason they are separate is that
	# nothing here should DEPEND on that refusal holding.
	# ⚠ RANGE-GATED at r > 200 m for the reason `_fov_lost` gives and gate 2 re-measured in this
	# quantity: EVERY held arm leaves its detector window in the last metres as the LOS unit vector
	# swings through a large angle at r → 0, and latching on that would paint every clean intercept a
	# lost track. The core's `gimbal_valid` is the verdict; the client only remembers it (convention 13).
	if _telemetry.has(_af3d_missile + ".gimbal_valid"):
		if float(_telemetry[_af3d_missile + ".gimbal_valid"]) < 0.5 \
		   and float(_telemetry.get(_af3d_missile + ".los_range", 0.0)) > 200.0:
			_gimbal_lost = true
	# SLICE 35 — the SERVO's SATURATION DUTY. ⚠ AN INDEPENDENT `if`, NOT AN `elif` OR AN `or` ON THE
	# BLOCK ABOVE — slice 33's finding, and here the two DO co-occur on every shipped frame (this wire
	# carries `gimbal_valid` AND `head_rate_sat`), so a chained dispatch would freeze one of them
	# outright rather than merely being fragile.
	# ⚠ AN EMA, NOT A PEAK-HOLD AND NOT A LATCH, and the reason is in the variable's own comment: the
	# question a rate limit raises is "what FRACTION of the time is it binding?", which is the shape
	# the core measures in the band (0.00 % vs 97.14 % at one servo) and the only shape that separates
	# a servo with headroom from one that is pegged. Gated on the slice-35 telemetry key so slice 34's
	# label path is untouched — the same SWITCH discipline as the HUD lines below.
	if _telemetry.has(_af3d_missile + ".head_rate_sat"):
		var st := 1.0 if float(_telemetry[_af3d_missile + ".head_rate_sat"]) >= 0.5 else 0.0
		_servo_duty = _servo_duty * 0.97 + st * 0.03
	# SLICE 36 — the REQUIREMENT's display freeze and the BIRTH angle's latch. ⚠ TWO INDEPENDENT `if`s,
	# NOT AN `elif` AND NOT CHAINED ONTO THE BLOCK ABOVE — slice 33's finding, and here the keys DO
	# co-occur on every shipped frame (this wire carries `head_rate_sat` AND both keys below), so a
	# chained dispatch would freeze one of them outright rather than merely being fragile.
	if _telemetry.has(_af3d_missile + ".head_off_peak_deg"):
		# ⚠ THE RANGE IS AN ARGUMENT, so the freeze is provable headless (convention 14): the raw key
		# runs to 179.4998° at CPA on every arm, and a HUD that printed that would end every clean
		# intercept displaying a 179° "requirement" — slice 19's lying picture in a new widget.
		_handover_peak = _handover_peak_hold(_handover_peak,
				float(_telemetry[_af3d_missile + ".head_off_peak_deg"]),
				float(_telemetry.get(_af3d_missile + ".los_range", 0.0)))
	if is_nan(_handover_los0) and _telemetry.has(_af3d_missile + ".look_body_az_deg"):
		# The BIRTH angle — latched on the first frame that carries the key, which is the handover's own
		# tick as far as any client can see it. Without it the live azimuth is a number with nothing to
		# be measured against, and the 33.2° excursion that IS the mechanism never appears on screen.
		_handover_los0 = float(_telemetry[_af3d_missile + ".look_body_az_deg"])
	if _t3d_layer == null or _t3d_los_mesh == null:
		return
	var mpos: Array = _entities.get(_af3d_missile, {}).get("pos", [0, 0, 0])
	var tpos: Array = _entities.get(_af3d_target, {}).get("pos", [0, 0, 0])
	var m3 := _sim_to_3d(mpos)
	var t3 := _sim_to_3d(tpos)
	_t3d_missile.position = m3
	_t3d_target.position = t3
	# trail breadcrumbs (skip the repeat point on a paused/held frame)
	if _t3d_trail_pts.is_empty() or _t3d_trail_pts[-1] != m3:
		_t3d_trail_pts.append(m3)
		if _t3d_trail_pts.size() > MISSILE_TRAIL_MAX:
			_t3d_trail_pts.pop_front()
	# the missile→target LOS line (cyan)
	_t3d_los_mesh.clear_surfaces()
	_t3d_los_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _t3d_line_mat)
	_t3d_los_mesh.surface_set_color(Color(0.45, 0.90, 1.00, 0.55))
	_t3d_los_mesh.surface_add_vertex(m3)
	_t3d_los_mesh.surface_set_color(Color(1.00, 0.62, 0.20, 0.55))
	_t3d_los_mesh.surface_add_vertex(t3)
	_t3d_los_mesh.surface_end()
	# the fading cyan trail — FLAT in x–z under :pitch_coupled, CURVING out toward +Y under :six_dof
	_t3d_trail_mesh.clear_surfaces()
	if _t3d_trail_pts.size() >= 2:
		_t3d_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _t3d_line_mat)
		var np := _t3d_trail_pts.size()
		for i in np:
			var a: float = 0.15 + 0.85 * float(i) / float(np - 1)
			_t3d_trail_mesh.surface_set_color(Color(0.45, 0.90, 1.00, a))
			_t3d_trail_mesh.surface_add_vertex(_t3d_trail_pts[i])
		_t3d_trail_mesh.surface_end()
	# the NOSE vector (the airframe's pointing direction) — six_dof ships att_q as 4 scalars
	# [w,x,y,z]; Godot's Quaternion is (x,y,z,w). Rotate body-x by it → the nose in the SIM/inertial
	# frame, then map to a godot DIRECTION with the axis swap (x, z, −y) but NO scale/exag (a
	# direction, not a position). Absent (pitch_coupled ships no att_q) ⇒ no nose vector drawn.
	_af3d_nose_mesh.clear_surfaces()
	var tel: Dictionary = _telemetry
	if tel.has(_af3d_missile + ".att_qw"):
		var q := Quaternion(float(tel[_af3d_missile + ".att_qx"]), float(tel[_af3d_missile + ".att_qy"]),
				float(tel[_af3d_missile + ".att_qz"]), float(tel[_af3d_missile + ".att_qw"]))
		var nose_sim := q * Vector3(1.0, 0.0, 0.0)
		var nose_dir := Vector3(nose_sim.x, nose_sim.z, -nose_sim.y).normalized()
		_af3d_nose_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _t3d_line_mat)
		_af3d_nose_mesh.surface_set_color(Color(1.00, 0.95, 0.55))
		_af3d_nose_mesh.surface_add_vertex(m3)
		_af3d_nose_mesh.surface_set_color(Color(1.00, 0.95, 0.55))
		_af3d_nose_mesh.surface_add_vertex(m3 + nose_dir * 9.0)
		# SLICE 24 — the LIFT AXIS (body "up" = q·(0,0,1)): where the single lift plane points. This makes
		# the BANK visible — under bank_to_turn the missile ROLLS this axis toward the cross-range target,
		# and the roll LAGS. A second segment in the same nose mesh (magenta). Drawn on any 6-DOF wire; it
		# only reads differently once the airframe banks (β≈0 STT keeps it ≈vertical, BTT rolls it over).
		var up_sim := q * Vector3(0.0, 0.0, 1.0)
		var up_dir := Vector3(up_sim.x, up_sim.z, -up_sim.y).normalized()
		_af3d_nose_mesh.surface_set_color(Color(1.00, 0.45, 0.85))
		_af3d_nose_mesh.surface_add_vertex(m3)
		_af3d_nose_mesh.surface_set_color(Color(1.00, 0.45, 0.85))
		_af3d_nose_mesh.surface_add_vertex(m3 + up_dir * 7.0)
		_af3d_nose_mesh.surface_end()

# ⚠⚠ EXTRACTED SO IT IS TESTABLE HEADLESSLY, and that is the whole reason it is a function: the
# label lives in `_draw`, which never runs under `--headless`, so the FIRST version of this
# comparison shipped with only a windowed SHOT as evidence — and the shot caught it (slice 31).
# ⭐ THE COMPARISON IS `R̂(1+s)` AGAINST `R_worst`, NOT AGAINST `radome_aim_gyro`. The two aim
# points live on OPPOSITE SIDES of the (1+s) factor: the HUD line tells the student where to put
# the SLIDER (`R̂ ≤ R_worst/(1+s)` = `radome_aim_gyro`), while the VERDICT is about what the LOOP
# ends up seeing (`R̂(1+s) ≤ R_worst`). Mixing them labelled a correctly-aimed missile "the gyro
# eats the margin". The two statements are equivalent while `1 + s > 0`; this form stays right
# when it is not.
# ⚠ THE THIRD STATE IS SLICE 30's AND MEANS THE SAME THING HERE: quiet at THIS gyro is not quiet
# at the gyro you will be shipped.
# ⚠ the same 1e−9 tolerance slice 30 needed, for the same reason: both sides are Float64 products
# a student is asked to match with a decimal slider.
# ⚠⚠ EXTRACTED FOR THE SAME REASON `_gyro_verdict_label` was, and the reason is now a convention:
# anything the verdict computes inside `_draw` has NO headless proof, because `_draw` never runs
# under `--headless` (convention 14, slice 31 — whose aim-point comparison shipped WRONG and only the
# windowed SHOT caught it). The UI test calls this directly.
# ⭐ THE COMPARISON IS THE WHOLE LESSON IN ONE LINE: the ENGAGEMENT's demand (`lead_angle_deg`, the
# collision triangle's own lead — `V_m·sin λ = V_t·sin θ`) against the HARDWARE's limit
# (`seeker_fov_deg`), in the same degrees. Both arrive from the CORE as numbers; the client evaluates
# no geometry (convention 13, the slice-21 `rho_air` precedent).
# ⚠ THREE STATES, BECAUSE THE SITUATION REALLY HAS THREE. `lost` is the LATCH on the core's own
# `seeker_valid` (see `_fov_lost`) and it wins outright — once the track has broken, the missile is
# coasting on a stale rate and nothing about the current geometry changes that. The middle state is
# the one a two-way label would hide: the lead has passed the window but the tracker has not dropped
# yet, which is where a student watching the crossing-speed slider is about to lose the engagement.
# ⚠ THE MARGIN IS 0.0 AND DELIBERATELY SO — no client-side "about to break" threshold on the physics.
# The lead and the window are compared as they are; the ~1 % gap between the lead and the LOOK angle
# is the missile's aerodynamic incidence, a core-side fact this label makes no claim about.
# ⚠ WIDTHS ARE MEASURED, NOT GUESSED, AND THE FIRST CAPTURE OF THIS SLICE PAID FOR IT AGAIN: at
# 20 px from `vp.x − 430` about 34 characters fit, and "TRACK BROKEN — the lead outgrew the FOV" (39)
# ran off the right edge with the clipped word being "FOV" — the part that names the mechanism. Slice
# 26 ate this on its headline and slice 28 on two body lines. Every string below is counted.
func _fov_verdict_label(lost: bool, lead: float, fov: float) -> String:
	if lost:
		return "TRACK BROKEN — lead outgrew FOV"
	if lead <= fov:
		return "IN THE WINDOW — FOV holds the lead"
	return "LEAD PAST WINDOW — about to break"

# ⭐ WHICH BODY-RATE CHANNEL THE RING IS IN — SLICE 28's SWITCH, EXTRACTED AT SLICE 33 SO THE TWO
# SITES THAT NEED IT CANNOT DIVERGE (advisor). Slice 28 measured that on a slope-CURVE wire the lead
# is in AZIMUTH, so the YAW channel sits on the steep part of the glass while pitch sits near the
# boresight slope (rms r 1.042 against rms q 0.101) — a meter left on `q` reads the QUIET channel of
# a shaking missile. Slice 26/27's FLAT glass has no such split and rings in PITCH.
# ⚠⚠ THE REASON THIS IS A FUNCTION AND NOT A COPIED LINE: slice 33's composition HUD branch fires on
# `_seeker_fov_view and _radome_view`, and `radome_view` is ALSO raised by slice-26-shaped glass with
# NO ripple. The shipped slice-33 wire has a ripple, so a hardcoded `omega_r` is correct THERE and
# would stay silently correct through every test — but on a future no-ripple composition the HUD
# would print a near-zero `omega_r` underneath an orange "← RINGING" tag driven by the peak-hold's
# `omega_q`. That is slice 28's own defect in a new place, and sharing the decision removes the
# possibility structurally rather than by remembering to duplicate the switch.
func _ring_channel_key() -> String:
	return ".omega_r" if _telemetry.has(_af3d_missile + ".radome_slope_az") else ".omega_q"

# SLICE 33 — THE RING IS AN FOV BUDGET ITEM. The COMPOSITION verdict, and it exists because slice
# 32's would be CONFIDENTLY WRONG on this wire.
# ⚠⚠ THE DEFECT IT REPLACES, MEASURED: `_fov_verdict_label` compares the LEAD against the WINDOW, and
# on this wire the lead is ~18.1° inside a 21° window — so on the arm that misses by 3.7 km it would
# print "IN THE WINDOW — FOV holds the lead", and after the latch "TRACK BROKEN — lead outgrew FOV".
# THE LEAD NEVER OUTGREW THE WINDOW; THE RING DID. Slice 32's own numbers are still right on slice
# 32's wire (no glass ⇒ look ≡ lead + incidence), which is why that helper is left VERBATIM and this
# is a SWITCH ahead of it, never an edit to it.
# ⭐ THE COMPARISON IS THE LESSON: what is being spent (`seeker_fov_margin_deg`, the SIGNED budget
# this slice ships) against the one slider that stops the bill (`radome_slope_est` vs slice 30's
# `radome_slope_worst`). Both sides arrive from the CORE as numbers — the client evaluates no
# geometry and no stability threshold (convention 13; |R_crit| moves with N and ρ).
# ⚠⚠ FOUR STATES, AND THE RANGE GATE IS THE THIRD ARGUMENT FOR A MEASURED REASON (advisor). EVERY
# held arm on this wire leaves the window in the last metres — first out at r = 0.18–8.55 m, at look
# angles of 21–162°, because the LOS unit vector swings through a huge angle as r → 0 (gate 2 paid
# for this in five failing asserts). Without the gate the "breaking" state would fire at the instant
# of a CLEAN INTERCEPT and paint the CURE arm as a failure. It is the same 200 m gate `_fov_lost`
# already carries and the same one every look-angle number in 32/33 is measured behind.
# ⚠ EXTRACTED, LIKE `_fov_verdict_label` AND `_gyro_verdict_label`, BECAUSE ANYTHING THE VERDICT
# COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF — `_draw` never runs under `--headless` (convention
# 14; slice 31's aim-point comparison shipped WRONG and only the windowed shot caught it). The UI
# test calls this directly, including the endgame case.
# ⚠ WIDTHS ARE MEASURED: ~34 characters at 20 px from `vp.x − 430`. All four are counted (30/31/30/27).
func _budget_verdict_label(lost: bool, margin: float, r: float, rhat: float, aim: float) -> String:
	if lost:
		return "TRACK BROKEN — the RING ate it"
	if margin < 0.0 and r > 200.0:
		return "RING PAST THE WINDOW — breaking"
	# ⚠ the same 1e−9 tolerance slices 30 and 31 needed, for the same reason: the aim point is a
	# Float64 sum that lands at −0.32999999999999996, not −0.33, and the slider a student drags
	# carries the decimal. Without it the verdict flips on a rounding direction at EXACTLY the value
	# the lesson asks them to hit.
	if rhat <= aim + 1.0e-9:
		return "AIMED AT R₀+2A — budget intact"
	return "RING IS SPENDING THE BUDGET"

# SLICE 34 — THE GIMBAL. The head's verdict, and it exists because slice 33's would compare THE WRONG
# PAIR on this wire — which is the plan's own gate-3 warning, made structural.
# ⚠⚠ WHAT MOVED. Under a head there are TWO limits and they are read against TWO DIFFERENT ANGLES:
# the head's TRAVEL against the mechanical STOP (which is the ENGAGEMENT's lead, i.e. slice 33's
# excursion RESTATED), and the head's TRACKING ERROR against the DETECTOR window (new, and where the
# margin the self-referential index buys is actually paid for). Slice 33's `_budget_verdict_label`
# compares a body look angle against a body window and knows nothing about either. A HUD that kept it
# would report a budget that is not the one being spent.
# ⭐ THE COMPARISON IS THE LESSON: `gimbal_fov_margin_deg` — the SIGNED detector budget the core
# ships, slice 18's `terrain_clearance_m` / slice 33's `seeker_fov_margin_deg` shape, THE SIGN IS THE
# VERDICT — against the ring that is spending it. Both arrive from the CORE as numbers; the client
# evaluates no geometry and no stability threshold (convention 13; |R_crit| moves with N and ρ, and on
# this wire it moves with the head as well, which is the whole point).
# ⚠⚠ FOUR STATES, AND THE ORDER IS LOAD-BEARING RATHER THAN TIDY. `lost` WINS OUTRIGHT because of the
# metric inversion gate 2 measured in this slice's own quantities: a broken window FREEZES the index
# (no error signal, no slew — the head HOLDS), a frozen index produces a CONSTANT bend, and a constant
# bend is QUIET at every R̂. So on a broken arm the ring meter reads calm while the missile misses by
# kilometres, and a ring-first ordering would print "the loop is quiet" on it.
# ⚠ THE RANGE GATE IS AN ARGUMENT FOR THE SAME REASON SLICE 33 NEEDED ONE: every held arm leaves its
# detector window in the last metres (r = 0.2–9 m) as the LOS unit vector swings, so without the gate
# the "breaking" state fires at the instant of a CLEAN INTERCEPT.
# ⚠ EXTRACTED, LIKE `_fov_verdict_label` / `_budget_verdict_label` / `_gyro_verdict_label`, BECAUSE
# ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF — `_draw` never runs under
# `--headless` (convention 14; slice 31's aim-point comparison shipped WRONG and only the windowed
# shot caught it). The UI test calls this directly, including the endgame case.
# ⚠ WIDTHS ARE MEASURED: ~34 characters at 20 px from `vp.x − 430`. All four are counted (30/31/32/31).
func _gimbal_verdict_label(lost: bool, margin: float, r: float, ringing: bool) -> String:
	if lost:
		return "TRACK LOST — the head let go"
	if margin < 0.0 and r > 200.0:
		return "ERROR PAST THE WINDOW — breaking"
	if ringing:
		return "RINGING — the index is not enough"
	return "SELF-INDEXED — the loop is quiet"

# SLICE 35 — THE SERVO's verdict, and it is a FOUR-WAY on TWO booleans rather than slice 34's cascade
# on one, because THE WHOLE SLICE IS THAT THE TWO MOVE IN OPPOSITE DIRECTIONS. A rate limit buys the
# ring DOWN and sells the tracking error UP, so the interesting states are the two MIXED ones — and a
# verdict built on either boolean alone would collapse exactly the pair the student is dragging.
# ⚠ `lost` STILL WINS OUTRIGHT, inherited from slice 34 with its reason UNCHANGED and re-earned here:
# a broken window FREEZES the index, a frozen index makes a CONSTANT bend, and a constant bend is
# QUIET at every R̂ — so the ring meter reads calm while the missile misses by kilometres. ⚠ AND THE
# SERVO METER INVERTS ON THAT SAME ARM FOR THE SAME REASON: the head HOLDS when it has no error
# signal, so it demands nothing and `head_rate_sat` reads 0 — a FREE-LOOKING servo on a broken track.
# That is the plan's two-run discipline arriving in its FOURTH quantity, and it is why `lost` is first.
# ⭐ THE PAYLOAD IS THE `not ringing and pegged` STATE: the ring was bought DOWN and the bandwidth is
# what paid for it. Slices 32/33/34 all end "widen it, it's free"; there is no free direction here.
# ⚠ EXTRACTED, LIKE `_fov_verdict_label` / `_budget_verdict_label` / `_gimbal_verdict_label`, BECAUSE
# ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF — `_draw` never runs under
# `--headless` (convention 14; slice 31's aim-point comparison shipped WRONG and only the windowed
# shot caught it). The UI test calls this directly, on all four states plus the lost one.
# ⚠ THE DUTY THRESHOLD IS THE ARGUMENT'S, NOT A CONSTANT READ OFF A GLOBAL: the caller passes the
# smoothed duty and this compares it against 0.5, so the UI test drives every branch with numbers
# rather than having to reproduce an EMA.
# ⚠ WIDTHS ARE MEASURED: ~34 characters at 20 px from `vp.x − 430`. All five are counted (28/32/32/
# 30/31).
func _servo_verdict_label(lost: bool, ringing: bool, duty: float) -> String:
	if lost:
		return "TRACK LOST — the head let go"
	var pegged := duty >= 0.5
	if ringing:
		return "SERVO PEGGED — and still RINGING" if pegged else "RINGING — the servo has room yet"
	return "QUIET, BOUGHT WITH BANDWIDTH" if pegged else "FREE — the servo costs nothing"

# SLICE 36 — THE HANDOVER BASKET's verdict, a FOUR-WAY on two booleans like slice 35's, and the pair it
# splits on is `lost × was the handover perfect`. ⭐⭐ THE POINT IS THE DIAGONAL: the two states a
# student must be able to read off one line are PERFECT-AND-LOST (the foil wire at its default servo,
# missing by 3290 m) and BIASED-AND-HELD (the twin, 0.191 m at the SAME servo behind the SAME window).
# Naming them is the whole headline — *zero is outside the basket* — and a verdict built on `lost` alone
# would print the same string on both halves of the pair.
# ⚠ THE TOLERANCE IS AN ARGUMENT'S, NOT A GLOBAL'S: `err` arrives as the AUTHORED degrees straight off
# the wire (`_finite_coord`, no arithmetic), so an exact `== 0.0` would be defensible — but the epsilon
# costs nothing and keeps the branch readable for any future wire that authors a computed error.
# ⚠ EXTRACTED, LIKE `_fov_verdict_label` / `_budget_verdict_label` / `_gimbal_verdict_label` /
# `_servo_verdict_label`, BECAUSE ANYTHING THE VERDICT COMPUTES INSIDE `_draw` HAS NO HEADLESS PROOF —
# `_draw` never runs under `--headless` (convention 14; slice 31's aim-point comparison shipped WRONG
# and only the windowed shot caught it). The UI test calls this directly, on all four states.
# ⚠ WIDTHS ARE MEASURED: ~34 characters at 20 px from `vp.x − 430`. All four are counted (29/26/30/28).
func _handover_verdict_label(lost: bool, err: float) -> String:
	var perfect := absf(err) < 1.0e-9
	if lost:
		return "PERFECT HANDOVER — TRACK LOST" if perfect else "TOO MUCH BIAS — TRACK LOST"
	return "ON THE LOS — the servo kept up" if perfect else "BIASED HANDOVER — track HELD"

# SLICE 36 — THE DISPLAY FREEZE THE CORE ASKED GATE 3 TO OWN, and it is not cosmetic: `head_off_peak_deg`
# is a RUNNING MAXIMUM, so it reads the clean requirement bit-identically from r = 3000 m down to
# r = 200 m and then runs to **179.4998° at CPA ON EVERY ARM, HIT OR MISS** — the target is simply
# behind the head by then. A PEAK CANNOT FORGET, so a HUD that printed the raw key would end every run
# — including every clean intercept — displaying a 179° "requirement". That is slice 19's lying picture
# in a new widget, and it is the same endgame spike that made gate 2 DROP the signed peak-margin key.
# ⇒ the display holds the last value taken while r > 200 m, which is the SAME gate the core's own
# requirement claims and the verifier's arms use ([[ewsim-missile-verifier-sampling]]).
# ⚠ AN INSTRUMENT, NOT PHYSICS (convention 13): it selects WHICH shipped sample to show and computes
# nothing. ⚠ AND IT IS A PURE HELPER FOR CONVENTION 14's REASON — the UI test drives it with the 179.5°
# endgame sample directly, which is the only way that case is ever proven.
func _handover_peak_hold(held: float, peak_now: float, r: float) -> float:
	return peak_now if r > 200.0 else held

# SLICE 36 — the requirement line's text, and the branch in it is the TWO-RUN DISCIPLINE's FIFTH
# QUANTITY. ⚠⚠ ON A BROKEN ARM THIS KEY IS NOT A REQUIREMENT AT ALL: the head holds with no error
# signal while the LOS leaves, so the peak becomes the POST-BREAK RUNAWAY — 104.56 / 65.79 / 73.77°
# against free-window requirements of 12.346 / 10.000 / 18.000° on the same arms. Slice 34's frozen
# `head_angle_deg` failed plausibly-but-TOO-SMALL; this one fails LARGE, so a reader who takes it for a
# requirement over-designs by 8× rather than under-designing. The label says which it is.
# ⚠⚠ AND IT PRINTS THE **PAIR**, NEVER THE DIFFERENCE. A signed peak MARGIN was drafted at gate 2,
# measured, and DROPPED: it would latch negative on the first breached tick and never recover, which
# fires on 100 % of arms including every hit (the endgame breaches any window). Subtracting the two
# here would rebuild exactly that dropped key in GDScript — so the two numbers are shown side by side
# and the comparison shows up as a MARKER, not as a manufactured degree count.
# SLICE 36 — the MECHANISM line's text, and the branch in it was found BY THE WINDOWED SHOT, which is
# what the shot is for. ⚠⚠ THE EXCURSION IS THE TWO-RUN DISCIPLINE's SIXTH QUANTITY AND IT INFLATES ON A
# BROKEN ARM: the verifier measures the body-frame LOS azimuth spanning 33.182° on an arm that HELD and
# 110.473° (~3.3×) on the shipped broken one, because a missile that has lost its track is in a runaway
# geometry. The first capture of shot A printed `handover +0.0°   body LOS az −39.18°  (first frame
# +18.00°)` — three true numbers a reader would subtract into a 57° "excursion" that is not the
# mechanism at all. Slice 33's defect exactly ("it would print IN THE WINDOW on the arm missing by
# 3.7 km"), in a new quantity: the numbers are live, the verdict above is correct, and the INVITED
# ARITHMETIC is wrong. ⇒ once the track is lost the line SAYS the azimuth is running away.
# ⚠ EXTRACTED for convention 14's reason, like the four verdict helpers: `_draw` has no headless proof.
# ⚠⚠ AND THE WIDTHS ARE MEASURED, WHICH THE FIRST RETAKE OF SHOT A PAID FOR: ~55 characters fit at 15 px
# from `vp.x − 430`, and "handover +0.0°   body LOS az −38.02° — RUNNING AWAY since the break" (67) ran
# off the right edge, cutting the clause to "RUNNING AWAY sin". The 3rd occurrence of that overrun after
# slices 26 and 28 — and the part that gets cut is always the part that carries the meaning.
# ⚠ "from %+.2f°" rather than "(first frame %+.2f°)" for the same budget reason; it is exact either way
# (the server emits every 16th tick, so the earliest azimuth any client sees is 16 ms after the handover
# tick that set it — tick 1 reads +18.11° on this wire).
func _handover_los_text(err: float, az: float, az0: float, lost: bool) -> String:
	if lost:
		return "handover %+.1f°   LOS az %+.2f° — RUNNING AWAY" % [err, az]
	return "handover %+.1f°   LOS az %+.2f° from %+.2f°" % [err, az, az0]

func _handover_req_text(peak: float, window: float, lost: bool) -> String:
	if lost:
		return "peak head err %.1f° — POST-BREAK, NOT a requirement" % peak
	return "requirement (peak) %.2f°  vs  window %.1f°%s" % \
			[peak, window, "   ← OVER" if peak > window else ""]

# ⭐⭐ SLICE 37 — THE SERVO REFERENCE FRAME's verdict. A THREE-WAY on `lost × ringing`, with the FRAME
# NAMED IN EVERY STRING, and the naming is the whole design: a HUD only ever sees ONE arm, so what has
# to be legible is THE PRESS — the student holds one design still, changes the architecture, and reads
# the verdict change. Naming the rung is what turns two consecutive frames into a comparison.
# ⚠ THE TWO RINGING STRINGS ARE DELIBERATELY SYMMETRIC and neither hints at the other rung. Near the
# slider's ceiling BOTH rungs ring, and a label like "RINGING TOO" would be asserting a fact about an
# arm this frame has no access to — the asymmetry the slice teaches is something the student MEASURES
# by pressing, not something the client may claim on their behalf.
# ⚠ THE COLOUR RIDES THE LATCH AND THE LABEL RIDES THE PEAK-HOLD, inherited from 34/35 with their
# reasons: a ringing arm here still HITS (every arm on this wire does, 0.16–1.9 m), and a limit cycle
# crosses zero twice per cycle so an instantaneous ring verdict mislabels half the frames (slice 27).
# ⚠ EXTRACTED, LIKE `_fov_verdict_label` / `_budget_verdict_label` / `_gimbal_verdict_label` /
# `_servo_verdict_label` / `_handover_verdict_label`, BECAUSE ANYTHING THE VERDICT COMPUTES INSIDE
# `_draw` HAS NO HEADLESS PROOF — `_draw` never runs under `--headless` (convention 14; slice 31's
# aim-point comparison shipped WRONG and only the windowed shot caught it).
# ⚠ WIDTHS ARE MEASURED: ~34 characters at 20 px from `vp.x − 430`. All five are counted (28/26/25/30/29).
func _frame_verdict_label(lost: bool, ringing: bool, stabilized: bool) -> String:
	if lost:
		return "TRACK LOST — the head let go"
	if ringing:
		return "SPACE-STABILIZED — RINGING" if stabilized else "BODY-REFERENCED — RINGING"
	return "SPACE-STABILIZED — loop STABLE" if stabilized else "BODY-REFERENCED — loop STABLE"

# ⚠⚠ SLICE 37 — THE DEMAND LINE, AND ITS ONLY JOB IS TO STOP AN INVITED SUBTRACTION. `head_rate_dps`
# keeps its slice-35 name across this button and MEANS A DIFFERENT THING ON EACH SIDE OF IT: under
# `:body_referenced` it is the step in BODY angles, so it INCLUDES tracking out the missile's own
# rotation; under `:space_stabilized` it is the step in INERTIAL angles, with body motion already
# rejected. The core's seam says so at the telemetry line; nothing on the wire otherwise would.
# ⭐⭐ AND THE TRAP IS LIVE ON THIS WIRE IN BOTH DIRECTIONS. At the slider's default the press makes the
# demand RISE (0.9 → 17.3 °/s, because the space arm is the one that rings there); at its ceiling,
# where BOTH rungs ring and a demand comparison is legal at all, the press makes it FALL 3.4× (63.1 →
# 18.4) while the ring goes UP 1.7×. A student who reads the fall alone concludes *"the stabilized head
# is the cheaper build"* — three true numbers whose invited arithmetic is exactly the inference the
# core forbids (cheaper in SERVO BANDWIDTH, dearer in STABILITY MARGIN). Slice 36's INVITED-ARITHMETIC
# defect in a new quantity, and the fix is that the frame is printed INSIDE the same string.
# ⚠ A ZERO HERE IS AMBIGUOUS BY CONSTRUCTION (the handover tick and every held tick both ship 0.0 —
# the two-run discipline's fourth quantity), which is why the head's state is on its own line below.
# ⚠ WIDTH MEASURED: ~55 characters at 15 px. Longest form is 54 with the PEGGED tag.
func _frame_demand_text(dem: float, cap: float, sat: bool, stabilized: bool) -> String:
	return "head rate %.1f°/s in the %s frame  vs %.0f°/s%s" % \
			[dem, "INERTIAL" if stabilized else "BODY", cap, "  PEGGED" if sat else ""]

# ⭐⭐ SLICE 37 — THE MECHANISM, IN ONE LINE PER RUNG, and it is the line that makes the two above
# readable together. The position servo's LAG is not merely slowness: it LOW-PASSES the missile's own
# body motion out of the radome's INDEX, and slice 26's limit cycle lives at 1.7–2.1 Hz — exactly where
# a τ = 0.05 s filter is worth 12–16 % of gain and ~30° of phase. Stabilize the head and that filter is
# gone (unity gain at every frequency, measured on a frozen-geometry bench), so the index sees the body
# in full. ⇒ the improvement REMOVES margin, which is why the wire needs a sentence and not just numbers.
# ⚠ IT NAMES THE MECHANISM, NEVER A THRESHOLD: no client-side stability test appears anywhere on this
# wire, because |R_crit| moves with N and ρ (convention 13 — slice 26's rule, still in force).
func _frame_mech_text(stabilized: bool) -> String:
	return "SPACE-STABILIZED: no lag — the index sees the body" if stabilized \
			else "BODY-REFERENCED: the servo's LAG filters the index"

# ⭐ SLICE 37 — THE CURE LINE, and slice 30's rule paying a FOURTH time (33 = FOV, 34 = detector
# window, 35 = servo bandwidth, 37 = the head's REFERENCE FRAME). Two numbers the CORE ships, never a
# client-side stability test: |R_crit| moves with N and ρ, so a "residual < x ⇒ unstable" line would be
# physics in GDScript AND wrong the moment a scenario changes N (convention 13, slice 26's rule).
# ⚠⚠ EXTRACTED FROM `_draw` **BECAUSE THE FIRST SHOT CAUGHT IT AT 59 CHARACTERS** against the measured
# ~55-character budget — inside `_draw` it had no headless proof at all (convention 14), so the width
# could only ever be caught by a capture. Now the UI test pins it.
# ⚠ "button goes dead" rather than "frame stops mattering": shorter, and truer — at the aim point the
# two rungs read 0.05901 and 0.06030 (1.022×), so what visibly stops working is the CONTROL.
func _frame_cure_text(rhat: float, aim: float) -> String:
	return "R̂ %+.3f   aim point R₀+2A %+.3f   ← button goes dead" % [rhat, aim]

# ⭐⭐ SLICE 37 — THE RING LINE, AND THE PEAK'S **VALUE** IS ON IT BECAUSE THE FIRST PAIR OF SHOTS
# CAUGHT THE INSTANTANEOUS NUMBER LYING. Slices 26–36 all drew the live body rate beside a tag driven
# by the peak-hold, and on those wires that was fine because nothing invited a frame-to-frame
# comparison. HERE THE WHOLE DEMONSTRATION IS TWO FRAMES EITHER SIDE OF ONE BUTTON PRESS — and the
# captures read `ring r −0.019 rad/s` on the QUIET arm against `ring r +0.021 rad/s` on the one
# RINGING 84× harder, because a limit cycle crosses zero twice per cycle and a single frame catches it
# wherever it happens to be. Two live, TRUE numbers whose comparison says the architecture did not
# matter — the exact inverse of the claim, and slice 36's INVITED ARITHMETIC in this slice's own
# headline quantity. The DECAYING PEAK separates them (~0.02 against ~1.3, the ratio the slice is
# about), so it is drawn as a number and not only as an orange tag.
# ⚠ AN INSTRUMENT, NOT PHYSICS (convention 13): a peak-hold of a shipped key, exactly slice 27's, and
# the LIVE value stays on the line beside it so nothing is hidden behind the instrument.
# ⚠ EXTRACTED for convention 14's reason — inside `_draw` it would have no headless proof, which is
# precisely how it shipped wrong for one capture. Width measured: 51 characters at the widest.
func _frame_ring_text(live: float, peak: float, lag: float, yaw_ch: bool) -> String:
	return "ring %s %+.3f (peak %.2f) rad/s%s  lag %.2f°" % \
			["r" if yaw_ch else "q", live, peak, "  RINGING" if peak > 0.5 else "", lag]

func _gyro_verdict_label(ringing: bool, eff: float, worst: float) -> String:
	if ringing:
		return "GYRO — RINGING: loop sees R̂(1+s)"
	if eff <= worst + 1.0e-9:
		return "AIMED PAST THE GYRO — the SAFE side"
	return "QUIET HERE — the gyro eats the margin"

# SLICE 32 — the four lines that ARE the lesson, split out so the label above stays one screenful.
# ⚠ WIDTHS ARE MEASURED, NOT GUESSED: ~55 characters fit at 15 px from `vp.x − 430` (slice 28's
# first capture ran two lines off the right edge; slice 26 ate the same defect at 20 px).
# ⭐ THE PAIR A STUDENT MUST SEE IS *DEMAND BESIDE LIMIT*: the lead this collision triangle requires
# against the window this seeker has, in the same degrees. That pairing is the entire claim — the FOV
# a seeker needs is not a seeker number, it is the ENGAGEMENT's — and both sliders move one of the
# two numbers, so the comparison is what the student is actually dragging.
# ⚠ THE LOOK ANGLE IS *NOT* THE LEAD, and both are on screen because the difference is real: the look
# angle is what the WINDOW tests (off the body boresight, so it carries the missile's aerodynamic
# incidence — about 1 % against a ~29° lead), while the lead is the geometry's own requirement. On a
# BROKEN arm they diverge completely as the coasting missile's geometry runs away, and that
# divergence is the mechanism made visible.
# ⚠ EVERY NUMBER ARRIVES FROM THE CORE (convention 13): the client compares two shipped degrees and
# reports a shipped boolean. It evaluates no triangle.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE *NOT* HERE — the shared block above already draws them at
# y = 66/88 for every 3-D airframe wire, and the cross-range one is a DISCRIMINATING TOOTH on this
# slice rather than decoration: 23 and 25 produce the same ≈2000 m signature with `max|y| = 0.0`
# (the command thrown away; the command never formed), while here it WAS formed and flown, so it
# runs to thousands. The `fov = 0` degenerate reaches the 0.0 signature by a FOURTH route, which is
# exactly why the miss alone cannot carry the claim.
func _draw_fov_hud_lines(vp: Vector2, fov: float, lead: float) -> void:
	var look32 := float(_telemetry.get(_af3d_missile + ".look_angle", 0.0))
	var valid := float(_telemetry.get(_af3d_missile + ".seeker_valid", 1.0)) >= 0.5
	draw_string(_font, Vector2(vp.x - 430, 110), "look %.1f°  vs  FOV %.1f°%s" % [look32, fov, "" if valid else "   ← OUTSIDE"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK if valid else Color(1.00, 0.62, 0.30))
	draw_string(_font, Vector2(vp.x - 430, 132), "ENGAGEMENT needs a lead of %.1f°  ← the requirement" % lead,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
	# coloured by the LATCH, not the instantaneous flag, for the same reason slice 27's headline rides
	# a peak-hold: a runaway geometry swings the LOS back through the window and this line would blink
	# green on a missile that lost its target seconds ago.
	draw_string(_font, Vector2(vp.x - 430, 154), "seeker: %s" % ("COASTING — no measurement since the break" if _fov_lost else ("MEASURING" if valid else "outside the window")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _fov_lost else Color(0.55, 1.00, 0.65))

# SLICE 33 — the four lines that ARE the composition, split out so the label chain stays readable
# (slice 32's `_draw_fov_hud_lines` precedent, and the same measured width: ~55 characters at 15 px
# from `vp.x − 430`; every line below is counted).
# ⭐ THE PAIRING A STUDENT MUST SEE IS *WHAT IS SPENDING* BESIDE *WHAT IS BEING SPENT*. The ring is
# the body YAW rate (slice 28's channel choice, and it is not cosmetic here either: this wire's lead
# is in AZIMUTH, so the yaw channel sits on the steep part of the slope curve while pitch sits near
# the boresight slope). The budget is `seeker_fov_margin_deg` — SIGNED, so a student watches a needle
# go to zero rather than being told a boolean. Slice 18's `terrain_clearance_m` is the precedent
# exactly: the SIGN IS THE VERDICT, and the client never re-derives the test (convention 13).
# ⚠ AND THE THIRD LINE IS THE CURE, AS TWO NUMBERS THE CORE SHIPS: the belief the student is
# dragging (`radome_slope_est`) against slice 30's aim point (`radome_slope_worst`, computed core-
# side as min(R₀, R₀+2A)). No client-side stability test — |R_crit| moves with N and ρ.
# ⚠ THE MARGIN LINE IS COLOURED BY THE SHIPPED SIGN, NOT BY A CLIENT COMPARISON of `look` and `fov`:
# gate 1 measured that those two keys DO NOT reconstruct the margin on a negative slider (the window
# ships AUTHORED, the margin uses the CLAMPED one), diverging by exactly |fov| on the very side the
# never-locked state is defined by. That divergence is why this key exists.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE NOT HERE — the shared block above already draws them at
# y = 66/88 for every 3-D airframe wire.
func _draw_budget_hud_lines(vp: Vector2) -> void:
	# ⚠ THE CHANNEL COMES FROM THE SHARED HELPER, NOT A HARDCODED KEY — see `_ring_channel_key`. The
	# shipped wire has a ripple so this reads `omega_r`, but the branch above is reachable by any
	# glass+window composition, and a rate line on the wrong channel would print a calm number under
	# the peak-hold's orange RINGING tag.
	var chan := _ring_channel_key()
	var rr := float(_telemetry.get(_af3d_missile + chan, 0.0))
	var yaw_ch := chan == ".omega_r"
	var look := float(_telemetry.get(_af3d_missile + ".look_angle", 0.0))
	var fov := float(_telemetry.get(_af3d_missile + ".seeker_fov_deg", 0.0))
	var marg := float(_telemetry.get(_af3d_missile + ".seeker_fov_margin_deg", 0.0))
	var rhat := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
	var aim := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
	# WHAT IS SPENDING. Coloured by the peak-hold, for the reason slice 27 settled: a limit cycle
	# crosses zero twice per cycle, so an instantaneous verdict mislabels half the frames.
	draw_string(_font, Vector2(vp.x - 430, 110), "body %s rate %s: %+.3f rad/s%s" % ["yaw" if yaw_ch else "pitch", "r" if yaw_ch else "q", rr, "   ← RINGING" if _radome_qpeak > 0.5 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else COL_TICK)
	# WHAT IS BEING SPENT — and the ring is visibly seen to EAT it.
	draw_string(_font, Vector2(vp.x - 430, 132), "look %.1f°  vs  FOV %.1f°   BUDGET LEFT %+.1f°" % [look, fov, marg],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45) if marg >= 0.0 else Color(1.00, 0.62, 0.30))
	# THE CURE, as two shipped numbers.
	draw_string(_font, Vector2(vp.x - 430, 154), "R̂ %+.3f   aim point R₀+2A %+.3f   ← drag R̂ here" % [rhat, aim],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	# THE STATE — slice 32's line verbatim, coloured by the LATCH rather than the instantaneous flag
	# for the reason it gives: a runaway geometry swings the LOS back through the window and this
	# would blink green on a missile that lost its target seconds ago.
	var valid := float(_telemetry.get(_af3d_missile + ".seeker_valid", 1.0)) >= 0.5
	draw_string(_font, Vector2(vp.x - 430, 176), "seeker: %s" % ("COASTING — no measurement since the break" if _fov_lost else ("MEASURING" if valid else "outside the window")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _fov_lost else Color(0.55, 1.00, 0.65))

# SLICE 34 — the five lines that ARE the head, split out so the label chain stays readable (slice
# 32/33's precedent, and the same measured width: ~55 characters at 15 px from `vp.x − 430`; every
# line below is counted).
# ⭐⭐ THE PAIR A STUDENT MUST SEE IS *WHERE THE GLASS IS INDEXED*. That is the entire slice: a
# strapdown seeker's radome index is handed to it by the AIRFRAME (the LOS off the nose), a gimballed
# seeker's by its OWN LAST MEASUREMENT (the head's pointing). Both numbers are on screen — the head's
# angle, which is the index the glass ACTUALLY used, and `look_body_deg`, the angle the NOSE is at and
# therefore the one a strapdown seeker WOULD have used. On the twin wire the second number is the
# only one that exists and it swings to 22.1° while it rings; here it stays near the lead.
# ⚠ `head_angle_deg` AND `look_angle` CARRY THE SAME NUMBER UNDER A HEAD, BY CONSTRUCTION — the seam
# sets `look_az, look_el = head_az, head_el` before the bend is taken, so slice 26's key ships the
# HEAD's index. This block reads `head_angle_deg` because that is the name that says what it is; the
# identity is asserted core-side rather than relied on silently here.
# ⭐ AND THE TWO LIMITS ARE DRAWN AGAINST THE TWO DIFFERENT ANGLES THEY ARE READ AGAINST — the
# TRAVEL against the STOP (slice 33's excursion, restated) and the TRACKING ERROR against the
# DETECTOR window (new). Drawing both is what stops the HUD comparing the wrong pair; drawing them on
# separate lines is what stops a student pairing them by accident.
# ⚠ EVERY NUMBER ARRIVES FROM THE CORE (convention 13). In particular the BUDGET is the core's own
# `gimbal_fov_margin_deg` and never `window − error` computed here: gate 2 measured that those two
# keys DO NOT reconstruct it on a negative slider (the window ships AUTHORED, the margin uses the
# CLAMPED one), which is slice 33's divergence and the reason the key exists.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE NOT HERE — the shared block above draws them at y = 66/88.
func _draw_gimbal_hud_lines(vp: Vector2) -> void:
	# ⚠ THE CHANNEL COMES FROM THE SHARED HELPER, NOT A HARDCODED KEY (slice 33's reason, inherited):
	# this wire has a slope RIPPLE so the lead — and hence the ring — is in AZIMUTH and this reads
	# `omega_r`, but the branch is reachable by any head on any glass, and a rate line on the wrong
	# channel would print a calm number under the peak-hold's orange RINGING tag.
	var chan := _ring_channel_key()
	var rr := float(_telemetry.get(_af3d_missile + chan, 0.0))
	var yaw_ch := chan == ".omega_r"
	var head := float(_telemetry.get(_af3d_missile + ".head_angle_deg", 0.0))
	var body := float(_telemetry.get(_af3d_missile + ".look_body_deg", 0.0))
	var stop := float(_telemetry.get(_af3d_missile + ".gimbal_stop_deg", 0.0))
	var off := float(_telemetry.get(_af3d_missile + ".head_off_deg", 0.0))
	var win := float(_telemetry.get(_af3d_missile + ".gimbal_fov_deg", 0.0))
	var marg := float(_telemetry.get(_af3d_missile + ".gimbal_fov_margin_deg", 0.0))
	# WHAT IS SPENDING. Coloured by the peak-hold, for the reason slice 27 settled: a limit cycle
	# crosses zero twice per cycle, so an instantaneous verdict mislabels half the frames.
	draw_string(_font, Vector2(vp.x - 430, 110), "body %s rate %s: %+.3f rad/s%s" % ["yaw" if yaw_ch else "pitch", "r" if yaw_ch else "q", rr, "   ← RINGING" if _radome_qpeak > 0.5 else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else COL_TICK)
	# ⭐⭐ THE MECHANISM, AS TWO NUMBERS: where the glass is indexed, and where it would have been.
	draw_string(_font, Vector2(vp.x - 430, 132), "glass indexed at HEAD %.1f°   (the nose is at %.1f°)" % [head, body],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.45, 0.90, 1.00))
	# THE PRICE — the detector budget, SIGNED, and it is what the head's decoupling is spent from.
	draw_string(_font, Vector2(vp.x - 430, 154), "detector err %.2f° vs window %.1f°   LEFT %+.2f°" % [off, win, marg],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45) if marg >= 0.0 else Color(1.00, 0.62, 0.30))
	# THE OTHER LIMIT, against the OTHER angle — slice 33's excursion, restated as head travel.
	draw_string(_font, Vector2(vp.x - 430, 176), "head travel %.1f° of %.0f° stop   ← the lead it covers" % [head, stop],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	# THE STATE — coloured by the LATCH rather than the instantaneous flag, for the reason slice 32
	# gives: a runaway geometry swings the LOS back through the window and this would blink green on a
	# missile that lost its target seconds ago.
	var valid := float(_telemetry.get(_af3d_missile + ".gimbal_valid", 1.0)) >= 0.5
	draw_string(_font, Vector2(vp.x - 430, 198), "head: %s" % ("HOLDING — no error signal since the break" if _gimbal_lost else ("TRACKING" if valid else "outside the detector window")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.55, 1.00, 0.65))

# SLICE 35 — the five lines that ARE the servo, split out so the label chain stays readable (slice
# 32/33/34's precedent, and the same measured width: ~55 characters at 15 px from `vp.x − 430`; every
# line below is counted).
# ⭐⭐ THE PAIR A STUDENT MUST SEE IS *DEMAND BESIDE CAP*. That is the whole slice: the head's motion
# stopped being free and became a RESOURCE, so the screen must show what was ASKED FOR against what
# the servo can DELIVER. Both arrive from the core in the same degrees per second, off the same wire,
# and the demand is the kernel's PRE-LIMIT step — which is the entire reason `head_slew_full` exists.
# A post-hoc difference of `:head_az` would read the CLIPPED motion and report the CAP as the demand,
# i.e. the answer as the question: measured at the slider's floor, demand p95 214.958 °/s against an
# achieved 8.000, ~27×, with the achieved step EXACTLY the cap on every saturated tick.
# ⭐ AND THE SECOND PAIR IS THE TRADE ITSELF — the ring beside the tracking error, which is what makes
# this the arc's first TWO-SIDED knob. Drag the servo down and the first number FALLS while the second
# RISES (0.885 → 0.386 against 5.9° → 12.8° across the slider). Drawing them adjacent is what makes
# "there is no free direction" a thing you watch rather than a thing you are told.
# ⚠ THE SATURATION IS THE CORE's OWN FLAG, SMOOTHED FOR DISPLAY AND NEVER RE-DERIVED HERE (convention
# 13). ⚠⚠ AND THE REASON IS ARCHITECTURAL, NOT EMPIRICAL — the first draft of this comment claimed a
# measurement it did not have (advisor). On THIS wire a client-side `demand > cap` would agree with
# the flag to the ULP, because the two are the same comparison rearranged; the verifier says so
# explicitly rather than pretending otherwise. What the flag buys is that the comparison lives in ONE
# place: the kernel forms it as `head_dem > max(rate_max, 0)·Δt` in RADIANS PER STEP while the wire
# carries DEGREES PER SECOND, so a client reconstruction would re-cross a `deg2rad`, a `Δt` and a
# `max(·, 0)` — three chances for a HUD to disagree with the branch it claims to report, at the
# boundary tick where the disagreement is least visible. That is a reason of construction, and it
# holds whether or not any wire has ever exercised it.
# ⚠ THE DETECTOR WINDOW IS DELIBERATELY *NOT* THE HEADLINE HERE, unlike slice 34: it is authored WIDE
# on this wire (25° against a measured worst requirement of 19.279° over 184 domain cells) precisely
# so the break is NOT what a student sees, because gate 0's own ship/no-ship gate found the break to
# be SLICE 34's mechanism. It is drawn as a single reassurance line — the budget is intact, so what
# you are watching is the trade and not a failure.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE NOT HERE — the shared block above draws them at y = 66/88.
func _draw_gimbal_rate_hud_lines(vp: Vector2) -> void:
	# ⚠ THE CHANNEL COMES FROM THE SHARED HELPER, NOT A HARDCODED KEY (slice 33's reason, inherited
	# through 34): this wire has a slope RIPPLE so the lead — and hence the ring — is in AZIMUTH and
	# this reads `omega_r`, but the branch is reachable by any rate-limited head on any glass, and a
	# rate line on the wrong channel would print a calm number under the peak-hold's orange tag.
	var chan := _ring_channel_key()
	var rr := float(_telemetry.get(_af3d_missile + chan, 0.0))
	var yaw_ch := chan == ".omega_r"
	var dem := float(_telemetry.get(_af3d_missile + ".head_rate_dps", 0.0))
	var cap := float(_telemetry.get(_af3d_missile + ".gimbal_rate_dps", 0.0))
	var sat := float(_telemetry.get(_af3d_missile + ".head_rate_sat", 0.0)) >= 0.5
	var off := float(_telemetry.get(_af3d_missile + ".head_off_deg", 0.0))
	var marg := float(_telemetry.get(_af3d_missile + ".gimbal_fov_margin_deg", 0.0))
	var rhat := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
	var aim := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
	# ⭐⭐ THE MECHANISM, AS TWO NUMBERS: what the loop ASKED the head for, against what it can give.
	draw_string(_font, Vector2(vp.x - 430, 110), "head rate: DEMAND %.1f°/s  vs  SERVO %.0f°/s%s" % [dem, cap, "   ← PEGGED" if sat else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if sat else Color(0.45, 0.90, 1.00))
	# …and how much of the time it is pegged, which is the shape the core measures in the band and the
	# only one that separates a servo with headroom from one that is saturated (0.00 % vs 97.14 %).
	draw_string(_font, Vector2(vp.x - 430, 132), "servo saturated ~%.0f%% of the time   ← the resource" % [100.0 * _servo_duty],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45) if _servo_duty >= 0.5 else COL_TICK)
	# ⭐ THE TRADE — the two bounds side by side, moving in OPPOSITE directions under one slider.
	# The ring is coloured by the peak-hold for the reason slice 27 settled: a limit cycle crosses zero
	# twice per cycle, so an instantaneous verdict mislabels half the frames.
	draw_string(_font, Vector2(vp.x - 430, 154), "ring %s %+.3f rad/s%s   ↔   head lag %.2f°" % ["r" if yaw_ch else "q", rr, "  RINGING" if _radome_qpeak > 0.5 else "", off],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else COL_TICK)
	# THE CURE, as two shipped numbers — slice 30's rule paying a THIRD time (33 = FOV, 34 = detector
	# window, 35 = servo bandwidth). No client-side stability test: |R_crit| moves with N and ρ.
	draw_string(_font, Vector2(vp.x - 430, 176), "R̂ %+.3f   aim point R₀+2A %+.3f   ← servo goes free" % [rhat, aim],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	# THE DETECTOR BUDGET, as ONE reassurance line rather than the headline (see the block comment):
	# it is authored wide here so the trade is what shows, not a break. Coloured by the shipped SIGN.
	draw_string(_font, Vector2(vp.x - 430, 198), "detector budget %+.1f°   head: %s" % [marg, "HOLDING — no error signal since the break" if _gimbal_lost else "TRACKING"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if (_gimbal_lost or marg < 0.0) else Color(0.55, 1.00, 0.65))

# SLICE 36 — the five lines that ARE the handover basket, split out like 32/33/34/35's (same measured
# width: ~55 characters at 15 px from `vp.x − 430`; every line below is counted).
# ⭐⭐ THE PAIR A STUDENT MUST SEE IS *WHERE THE HEAD WAS PUT* BESIDE *WHERE THE LOS WENT*. That is the
# whole slice: the body-frame LOS is not a fixed target — it travels +18.11° → −15.15° over the approach
# as the missile swings its nose onto the collision course — so a head handed over ON it must chase the
# entire journey while one handed over part-way ALONG it starts with a head start. Line 1 carries all
# three numbers (the authored error, where the LOS was at first sight, where it is now) because the
# excursion is the mechanism and a single instantaneous angle cannot show it.
# ⭐ AND THE SECOND PAIR IS THE REQUIREMENT BESIDE THE WINDOW, in the same degrees. Slice 32 measured
# `held ⟺ lead < fov`, slice 34 re-measured it as `tracking error < detector window`, and this slice
# measures it a THIRD time in the basket's own currency — so the two numbers that decide it are adjacent
# and a student watches the verdict rather than being told it.
# ⚠⚠ THERE IS NO RING LINE HERE AND THAT IS DELIBERATE — THIS WIRE HAS NO GLASS. Slice 35's block draws
# `R̂` against the aim point as its CURE line; both keys are absent on a radome-free wire and would render
# as `+0.000`, which is precisely the stale-readout defect this slice's marker exists to prevent. The
# body rate is not drawn either: it is real here, but nothing is refracting, so labelling it would invite
# exactly the radome reading the whole wire is built to exclude.
# ⚠ THE REQUIREMENT IS THE FROZEN SAMPLE (`_handover_peak`), NEVER THE RAW KEY — see `_handover_peak_hold`.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE NOT HERE — the shared block above draws them at y = 66/88.
func _draw_handover_hud_lines(vp: Vector2) -> void:
	var err := float(_telemetry.get(_af3d_missile + ".gimbal_handover_err_deg", 0.0))
	var az := float(_telemetry.get(_af3d_missile + ".look_body_az_deg", 0.0))
	var win := float(_telemetry.get(_af3d_missile + ".gimbal_fov_deg", 0.0))
	var off := float(_telemetry.get(_af3d_missile + ".head_off_deg", 0.0))
	var marg := float(_telemetry.get(_af3d_missile + ".gimbal_fov_margin_deg", 0.0))
	var dem := float(_telemetry.get(_af3d_missile + ".head_rate_dps", 0.0))
	var cap := float(_telemetry.get(_af3d_missile + ".gimbal_rate_dps", 0.0))
	var sat := float(_telemetry.get(_af3d_missile + ".head_rate_sat", 0.0)) >= 0.5
	# ⭐⭐ THE MECHANISM, AS THREE NUMBERS. ⚠ "first frame" is exact and "at handover" would not be: the
	# server emits every 16th tick, so the earliest azimuth any client sees is 16 ms after the handover
	# tick that set it (tick 1 reads +18.11° on this wire against the first frame's own value). The
	# excursion is what matters and it is 33.2° wide, so a 16 ms offset changes nothing about the reading
	# — but the label may not claim a tick the client never received.
	draw_string(_font, Vector2(vp.x - 430, 110), _handover_los_text(err, az, _handover_los0, _gimbal_lost),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.45, 0.90, 1.00))
	# ⭐ THE REQUIREMENT BESIDE THE WINDOW — the frozen peak, and on a broken arm the text says outright
	# that the number is the post-break runaway and not a requirement (the two-run discipline's fifth
	# quantity, which fails LARGE where slice 34's failed small).
	draw_string(_font, Vector2(vp.x - 430, 132), _handover_req_text(_handover_peak, win, _gimbal_lost),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if (_gimbal_lost or _handover_peak > win) else Color(1.00, 0.85, 0.45))
	# THE PER-TICK BUDGET, whose SIGN is the shipped verdict (`gimbal_fov_margin_deg`, slice 33's shape).
	draw_string(_font, Vector2(vp.x - 430, 154), "tracking err %.2f°   detector LEFT %+.2f°" % [off, marg],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if marg < 0.0 else COL_TICK)
	# THE ONE SLIDER, and what it is being asked for — slice 35's demand-vs-cap pair, kept because on
	# THIS wire it is the CURE (drag it up and the perfect handover's track comes back at the measured
	# 10.0 → 10.5 °/s bracket) and, on the biased twin, the thing that stops mattering.
	draw_string(_font, Vector2(vp.x - 430, 176), "servo %.0f°/s   demand %.1f°/s%s" % [cap, dem, "   ← PEGGED" if sat else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45) if sat else COL_TICK)
	# THE STATE — coloured by the LATCH, not the instantaneous flag, for the reason slice 32/34 give: the
	# runaway geometry swings the LOS back through the window and this would blink green on a missile
	# that lost its target seconds ago.
	draw_string(_font, Vector2(vp.x - 430, 198), "head: %s" % ("HOLDING — no error signal since the break" if _gimbal_lost else "TRACKING"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.55, 1.00, 0.65))

# ⭐⭐ SLICE 37 — the five lines that ARE the servo's reference frame, split out like 32/33/34/35/36's
# (same measured width: ~55 characters at 15 px from `vp.x − 430`; every line below is counted).
# THE PAIR A STUDENT MUST SEE IS *THE RING* BESIDE *THE DEMAND*, because they move in OPPOSITE
# directions across the press and the whole payload is that there is no free direction. Slice 35 found
# the arc's first two-sided knob; this wire moves that shape onto the ARCHITECTURE — the stabilized
# head is cheaper in SERVO BANDWIDTH and dearer in STABILITY MARGIN, and both halves are on screen.
# ⚠⚠ THE FRAME IS NAMED INSIDE THE DEMAND LINE AND THAT IS THE ONE NON-NEGOTIABLE THING HERE — see
# `_frame_demand_text`. Drawing `head_rate_dps` unlabelled across this button would be three true
# numbers inviting the one conclusion the core's seam comment forbids.
# ⚠ THE RING LINE FOLLOWS THE RINGING CHANNEL through the shared helper, not a hardcoded key: this
# wire's lead is in AZIMUTH so it reads `omega_r`, but the branch is reachable by any head on any
# glass and a rate line on the wrong channel prints a calm number under an orange tag (slice 28/33).
# ⚠ THE DETECTOR BUDGET IS ONE REASSURANCE LINE, NOT THE HEADLINE: the window is authored at 25°
# against a worst measured requirement of 5.391° over the whole slider, so it never binds — and that
# is what makes every `rms r` here a STABILITY read at all (the two-run discipline). It is drawn
# because a budget that never binds still has to be SEEN not to bind.
# ⚠ THE RANGE AND CROSS-RANGE LINES ARE NOT HERE — the shared block above draws them at y = 66/88.
func _draw_frame_hud_lines(vp: Vector2) -> void:
	var stab := str(_fidelity.get("seeker_head", "body_referenced")) == "space_stabilized"
	var chan := _ring_channel_key()
	var rr := float(_telemetry.get(_af3d_missile + chan, 0.0))
	var yaw_ch := chan == ".omega_r"
	var dem := float(_telemetry.get(_af3d_missile + ".head_rate_dps", 0.0))
	var cap := float(_telemetry.get(_af3d_missile + ".gimbal_rate_dps", 0.0))
	var sat := float(_telemetry.get(_af3d_missile + ".head_rate_sat", 0.0)) >= 0.5
	var off := float(_telemetry.get(_af3d_missile + ".head_off_deg", 0.0))
	var marg := float(_telemetry.get(_af3d_missile + ".gimbal_fov_margin_deg", 0.0))
	var rhat := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
	var aim := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
	# ⭐⭐ THE MECHANISM, IN WORDS — why the two numbers below trade against each other at all.
	draw_string(_font, Vector2(vp.x - 430, 110), _frame_mech_text(stab),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.45, 0.90, 1.00))
	# THE STABILITY SIDE — coloured by the peak-hold (slice 27's reason: a limit cycle crosses zero
	# twice per cycle, so an instantaneous verdict mislabels half the frames).
	# ⚠⚠ AND THE PEAK'S **VALUE** IS DRAWN BESIDE THE LIVE RATE BECAUSE THE FIRST PAIR OF SHOTS CAUGHT
	# THE INSTANTANEOUS NUMBER LYING — see `_frame_ring_text`. This is the one line whose two states a
	# student compares ACROSS THE PRESS, so it is the one line that must not need the tag to be read.
	draw_string(_font, Vector2(vp.x - 430, 132), _frame_ring_text(rr, _radome_qpeak, off, yaw_ch),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else COL_TICK)
	# …and THE BANDWIDTH SIDE, with its FRAME printed in the same string. See `_frame_demand_text`.
	draw_string(_font, Vector2(vp.x - 430, 154), _frame_demand_text(dem, cap, sat, stab),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45) if sat else COL_TICK)
	# ⭐ THE CURE — slice 30's rule paying a FOURTH time (33 = FOV, 34 = detector window, 35 = servo
	# bandwidth, 37 = THE REFERENCE FRAME), and here it is the slider's own FLOOR: at R₀+2A the two
	# rungs read 0.05890 and 0.06016 (1.021×), so the BUTTON GOES DEAD. Two shipped numbers, never a
	# client-side stability test — |R_crit| moves with N and ρ (convention 13, slice 26's rule).
	# ⚠⚠ THE TRAILING CLAUSE WAS SHORTENED BY THE FIRST SHOT AND THE MEASUREMENT IS WHY. "← frame stops
	# mattering" made this line 59 characters against the measured ~55-character budget at 15 px from
	# `vp.x − 430`; at 1600 px it cleared the right edge by ~10 px and any narrower window would have
	# cut the clause — the 4th occurrence of that overrun after slices 26, 28 and 36, and the part that
	# gets cut is always the part that carries the meaning. "← button goes dead" is also the truer
	# phrase: at the aim point the two rungs read 0.05901 and 0.06030, so the CONTROL is what stops
	# working. Pinned by width in `slice37_ui_test.gd`.
	draw_string(_font, Vector2(vp.x - 430, 176), _frame_cure_text(rhat, aim),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	# THE DETECTOR BUDGET + THE HEAD's STATE — the window never binds on this wire, which is the
	# precondition for reading the ring at all. Coloured by the shipped SIGN and by the LATCH.
	draw_string(_font, Vector2(vp.x - 430, 198), "detector budget %+.1f°   head: %s" % [marg, "HOLDING — no error signal since the break" if _gimbal_lost else "TRACKING"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if (_gimbal_lost or marg < 0.0) else Color(0.55, 1.00, 0.65))

func _draw_airframe3d_hud() -> void:
	# The 3-D layer renders the world; the 2-D canvas only LABELS it (the terrain-view discipline).
	# The headline: the plant, the cross-range miss (los_range), and the out-of-plane excursion.
	var vp := get_viewport_rect().size
	# SLICE 24 — a steering scenario labels the STEERING law (skid_to_turn ↔ bank_to_turn); a slice-23
	# scenario labels the airframe rung. Both share this 3-D view (value-guarded on the `steering` key).
	var lbl := ""
	var col := Color(0.45, 0.90, 1.00)
	var is_bank := false
	# SLICE 25 — checked FIRST, matching _enter_airframe3d_mode's routing: a seeker-axes wire labels
	# what the SEEKER can SEE (the plant is held). This is the one case where the missile is fully
	# capable and simply never commanded — so the label says BLIND, not "discarded" (slice 23) and not
	# "lagging" (slice 24).
	# SLICE 26 — checked FIRST (the same order as _enter_airframe3d_mode). A radome wire ALSO carries
	# `seeker_axes` (HELD at az_el), so without this the label would read slice 25's and name the wrong
	# lesson. There is no rung here, so the label is driven by the KNOB's own sign: only NEGATIVE
	# slopes close the loop, and the threshold is a LOOP GAIN, not a slope value.
	# SLICE 32 — checked FIRST (the same order as _enter_airframe3d_mode, and the "check the NEW key
	# first" rule's 6th occurrence). A FOV wire ALSO carries `seeker_axes` (HELD at az_el), so without
	# this the label would read slice 25's and name the wrong lesson entirely — "BLIND out of plane"
	# on a missile whose seeker sees perfectly well until the lead outgrows its window.
	# ⚠ IT IS ITS OWN BRANCH, NEVER A RUNG OF THE RADOME CASCADE BELOW: that cascade reads
	# `radome_slope`/`radome_residual`/`radome_slope_worst`/…, and a FOV wire has NONE of them, so
	# every one would `get(..., 0.0)` and print a confident 0.000 — the stale-readout class this arc
	# has now caught seven times, and the exact defect gate 2's advisor catch was about.
	# SLICE 33 — THE COMPOSITION, checked FIRST and it is a SWITCH ahead of BOTH branches below (not
	# an `or`, and not an edit to either). This is the FIRST wire in the project to carry glass AND a
	# window, so it is the first to raise BOTH markers — slice 32's own gate-3 testset asserts
	# `!haskey(info, :radome_view)` on ITS wire AS A FEATURE, and gate 2 pinned both `=== true` here.
	# ⚠⚠ THE BUTTON OUTCOME IS IDENTICAL EITHER WAY (both markers DROP it, at both sites, so
	# `_enter_airframe3d_mode` and `_update_fid_btn` need no edit at all — the OPPOSITE of slice 26's
	# "the drop needs BOTH sites"), BUT THE HUD BRANCH IS NOT: without this, `_seeker_fov_view` would
	# win and print slice 32's lead-vs-window verdict, which is wrong here in the way that matters
	# (see `_budget_verdict_label`) AND would silence the radome cascade entirely — the ring, the
	# residual and the aim point would all vanish from a view whose whole subject is what the ring
	# costs. The stale-readout class this arc has caught eight times, in its mirror form: not a stale
	# number printed confidently, but the LIVE half of a composition never drawn.
	# SLICE 34 — THE HEAD, checked FIRST and a SWITCH ahead of everything below ("check the NEW key
	# first", 7th occurrence). ⚠⚠ AND THE REASON IS NOT SYMMETRY WITH 32/33 — IT IS THAT WITHOUT IT
	# THIS WIRE LANDS IN THE RADOME CASCADE AND IS CONFIDENTLY WRONG. The loader refuses
	# `seeker_fov_deg` beside a head, so a gimbal wire raises `radome_view` and NOT `seeker_fov_view`:
	# both branches below fail their conjunction and the `elif _radome_view` arm takes it. Every number
	# that arm reads is LIVE here (this wire HAS glass), so it would print a fluent verdict about the
	# GLASS on a wire whose subject is the HEAD — the stale-readout class's worst form, in which
	# nothing is stale and the subject is simply wrong.
	# ⚠ THE BUTTON NEEDS NO EDIT AT EITHER SITE (`radome_view` already drops it) — slice 33's finding,
	# second occurrence, and the OPPOSITE of slice 26's "the drop needs BOTH sites".
	# SLICE 35 — THE SERVO, checked FIRST and a SWITCH ahead of the head branch below ("check the NEW
	# key first", 8th occurrence). ⚠⚠ AND THE REASON IS NEITHER 33's NOR 34's, WHICH IS WHY IT IS
	# SPELLED OUT RATHER THAN CROSS-REFERENCED. Slice 34's marker plugged a REAL HOLE (its wire fell
	# through both FOV branches into the radome cascade and was confidently wrong about the subject).
	# Nothing of the kind happens here: a slice-35 wire is a slice-34 wire PLUS one key, `gimbal_view`
	# is raised, and the branch below is about the HEAD, which is still the right subject. This is a
	# BRANCH SELECTOR, and what it selects is the half slice 34's verdict CANNOT SAY — that verdict
	# compares the tracking error against the DETECTOR WINDOW, which is authored WIDE here (25° against
	# a measured worst requirement of 19.279° over 184 domain cells) and NEVER BINDS. So it would print
	# "SELF-INDEXED — the loop is quiet" or "RINGING — the index is not enough", both TRUE, on a wire
	# whose entire subject is a servo it never mentions. ⚠ The failure mode is therefore not a wrong
	# number but an INVISIBLE SLICE, and that distinction is the thing to carry forward.
	# ⚠ THE BUTTON NEEDS NO EDIT AT EITHER SITE (`radome_view` and `gimbal_view` both drop it) — slice
	# 33's finding, third occurrence.
	# SLICE 36 — THE HANDOVER BASKET, checked FIRST and a SWITCH ahead of the servo branch below ("check
	# the NEW key first", 9th occurrence). ⚠⚠ AND THE REASON IS **BOTH** OF THE PREVIOUS TWO AT ONCE,
	# which is why it is spelled out rather than cross-referenced. Slice 35's marker was a pure BRANCH
	# SELECTOR (its wire routed correctly and every number its inherited HUD drew was true — the failure
	# was an INVISIBLE SLICE). Slice 34's plugged a real HOLE (its wire fell into the radome cascade and
	# was confidently wrong about the subject). This wire does both: `gimbal_rate_view` IS raised, so
	# without this branch slice 35's block takes it — and slice 35's line 4, the one its own comment calls
	# THE CURE, reads `radome_slope_est` and `radome_slope_worst`, NEITHER OF WHICH EXISTS ON A GLASS-FREE
	# WIRE. It would print `R̂ +0.000   aim point R₀+2A +0.000` beside a `_radome_qpeak` frozen at 0.0 by
	# its own presence gate: the stale-readout class's 9th occurrence, landing on another slice's payoff
	# line, on a wire that is missing by 3.3 km for a reason no line mentions.
	# ⚠ AND THE BUTTON IS NOT FREE HERE EITHER — see `_enter_airframe3d_mode`. Slices 26–35 all dropped it
	# by riding `radome_view`; this is the first no-glass wire of the arc, so the drop needs both sites
	# (slice 26's finding, 4th occurrence) and this marker owns that too.
	# SLICE 37 — THE SERVO'S REFERENCE FRAME, checked FIRST and a SWITCH ahead of every branch below
	# ("check the NEW key first", 10th occurrence). ⚠⚠ AND THE REASON IS SLICE 36's — BOTH FAILURES AT
	# ONCE — rather than slice 35's single one, which is why it is spelled out and not cross-referenced.
	# (1) THE SUBJECT. This wire raises `gimbal_rate_view`, so without this branch slice 35's servo
	# block takes it and prints a comfortable demand-vs-cap budget on a wire whose entire subject is
	# WHICH FRAME that demand is measured in — slice 35's own INVISIBLE SLICE, one slice later.
	# (2) ⚠⚠ WORSE, IT IS AN INVITED SUBTRACTION. `head_rate_dps` keeps its name across this button and
	# changes MEANING with the rung (body-frame demand, which includes tracking out the missile's own
	# rotation, against inertial-frame demand with body motion already rejected). At the slider's
	# ceiling the press makes that number FALL 3.4× while the ring RISES 1.7×, so slice 35's unlabelled
	# line would invite exactly the reading the core's seam forbids: *the stabilized head is the cheaper
	# build*. It is cheaper in SERVO BANDWIDTH and dearer in STABILITY MARGIN. Slice 36's INVITED
	# ARITHMETIC defect in a new quantity — three live, true numbers under a correct verdict line.
	# ⚠ AND THE BUTTON IS NOT FREE HERE EITHER, IN THE DIRECTION NO EARLIER SLICE NEEDED — see
	# `_enter_airframe3d_mode`: this is the first wire of the family with a rung to cycle, so the marker
	# RESTORES the button that three separate markers on this same wire would otherwise drop.
	if _gimbal_frame_view:
		lbl = _frame_verdict_label(_gimbal_lost, _radome_qpeak > 0.5,
				str(_fidelity.get("seeker_head", "body_referenced")) == "space_stabilized")
		# ⚠ THE COLOUR RIDES THE LATCH, NOT THE PEAK-HOLD, inherited from 34/35 with their reason and
		# one of this wire's own: EVERY arm in the slider's domain HITS (0.16–1.9 m) on BOTH rungs, so a
		# ring-coloured headline would paint every successful intercept orange — and the ring is named
		# in the LABEL, which is where the comparison the student is making actually lives.
		col = Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.45, 0.90, 1.00)
	elif _gimbal_handover_view:
		lbl = _handover_verdict_label(_gimbal_lost,
				float(_telemetry.get(_af3d_missile + ".gimbal_handover_err_deg", 0.0)))
		# ⚠ THE COLOUR RIDES THE LATCH, and here that is not merely inherited — it is the ONLY honest
		# choice available. There is no ring to meter on this wire and the requirement is a FROZEN PEAK,
		# so `lost` is the one thing that separates the pair: same servo, same window, same seed, one arm
		# holds and one does not. ⚠ And the price of the bias is EXACTLY ZERO on every arm that holds
		# (miss `===` to 64 bits across the whole domain), so nothing else could be painted as a cost.
		col = Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.45, 0.90, 1.00)
	elif _gimbal_rate_view:
		lbl = _servo_verdict_label(_gimbal_lost, _radome_qpeak > 0.5, _servo_duty)
		# ⚠ THE COLOUR RIDES THE LATCH, NOT THE PEAK-HOLD AND NOT THE DUTY, inherited from slice 34 with
		# its reason and one of this slice's own on top: a RINGING arm here still HITS (every arm in the
		# domain does), and so does a PEGGED one — the servo saturating is the lesson, not a failure, so
		# painting it orange would say the opposite of what the slice claims. The latch tracks the one
		# thing that actually ends an engagement.
		col = Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.45, 0.90, 1.00)
	elif _gimbal_view:
		lbl = _gimbal_verdict_label(_gimbal_lost,
				float(_telemetry.get(_af3d_missile + ".gimbal_fov_margin_deg", 0.0)),
				float(_telemetry.get(_af3d_missile + ".los_range", 0.0)),
				_radome_qpeak > 0.5)
		# ⚠ THE COLOUR RIDES THE LATCH, NOT THE PEAK-HOLD, AND THAT IS THE TWO-RUN DISCIPLINE IN ONE
		# CHOICE: on this wire a RINGING head can still hold its window and HIT (the free arm at
		# R̂ = −0.16 rings at 0.353 and lands at 7.0 m), so a peak-hold colour would paint a successful
		# intercept orange — while a BROKEN arm's ring meter reads CALM, because a frozen index makes a
		# constant bend. The ring is named in the LABEL, where it belongs; the colour tracks the thing
		# that actually ended the engagement.
		col = Color(1.00, 0.62, 0.30) if _gimbal_lost else Color(0.45, 0.90, 1.00)
	elif _seeker_fov_view and _radome_view:
		lbl = _budget_verdict_label(_fov_lost,
				float(_telemetry.get(_af3d_missile + ".seeker_fov_margin_deg", 0.0)),
				float(_telemetry.get(_af3d_missile + ".los_range", 0.0)),
				float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0)),
				float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0)))
		# ⚠ THE COLOUR RIDES THE LATCH, NOT `_radome_qpeak`, AND THAT IS THE SLICE IN ONE CHOICE: on
		# this wire the ring is LOUD on the cure-A arm too (rms r 1.072 at fov 26) and it HITS — the
		# ring is not the failure, spending more budget than you have is. A peak-hold colour would
		# paint the successful intercept orange.
		col = Color(1.00, 0.62, 0.30) if _fov_lost else Color(0.45, 0.90, 1.00)
	elif _seeker_fov_view:
		lbl = _fov_verdict_label(_fov_lost,
				float(_telemetry.get(_af3d_missile + ".lead_angle_deg", 0.0)),
				float(_telemetry.get(_af3d_missile + ".seeker_fov_deg", 0.0)))
		col = Color(1.00, 0.62, 0.30) if _fov_lost else Color(0.45, 0.90, 1.00)
	elif _radome_view:
		var slope := float(_telemetry.get(_af3d_missile + ".radome_slope", 0.0))
		var qr := absf(float(_telemetry.get(_af3d_missile + ".omega_q", 0.0)))
		# ⚠ The label reports the MEASURED body rate, not a threshold comparison: |R_crit| moves with
		# N and ρ (the boundary is N·|R|/ρ ≈ 0.38), so a client-side "R < −0.095 ⇒ unstable" test would
		# be physics in GDScript AND wrong the moment a scenario changes N (convention 13).
		# ⚠ Keep these SHORT — the headline is drawn at `vp.x − 430` in 20 px, so ~38 characters is
		# the width. A longer string runs off the right edge and the lesson's own name is the part
		# that gets cut (measured: "…the body rate fe|" on the first shot).
		# SLICE 27 — a COMPENSATED wire names the cure, not just the disease. A SWITCH on the
		# compensator's own telemetry key, so a slice-26 wire keeps its label verbatim.
		# ⚠ The verdict is still driven by the MEASURED body rate, never by a client-side threshold
		# test on the residual: |R_crit| moves with N and ρ (the boundary is N·|R − R̂|/ρ ≈ 0.38), so
		# "residual < −0.0475 ⇒ unstable" would be physics in GDScript AND wrong the moment a
		# scenario changes N (convention 13). ⚠ Keep these SHORT — ~38 chars at 20 px is the width
		# at `vp.x − 430`, measured when slice 26's headline ran off the right edge.
		# SLICE 28 — checked FIRST, and it is a SWITCH not an `or`: a slope-CURVE wire ships
		# `radome_slope_az`, which 26/27 never do, so their labels stay verbatim. Two reasons this
		# needs its own string rather than slice 27's: the ring is in YAW here (the lead angle is in
		# azimuth), and "under-comp" would be WRONG — the compensator is EXACTLY right at the slope it
		# was characterized at; it is MIS-characterized for the look angle the engagement flies.
		# SLICE 29 — checked FIRST, and a SWITCH ahead of slice 28's (not an `or`): a SCHEDULED
		# compensator ships `radome_sched_slope`, which 26/27/28 never do, so their labels stay
		# verbatim. It needs its own string because the lesson is not "the belief is wrong" — on the
		# shipped arm the belief is a BETTER model of the glass than the one that stays quiet — it is
		# that the belief is evaluated at an index the radome already bent.
		# SLICE 30 — checked FIRST, and a SWITCH ahead of slice 29's (not an `or`): only a wire whose
		# TARGET carries the crossing-speed knob ships `cross_speed_mps`, so 26/27/28/29 keep their
		# labels verbatim. ⚠ NOT `radome_slope_worst` — gate 2 measured that key as ADDITIVE on every
		# ripple-carrying wire, so 28/29 grow it too and would take this branch.
		# ⚠ THE THIRD STATE IS THE WHOLE POINT, and it is why this is not a two-way label: quiet HERE
		# is not the same claim as quiet EVERYWHERE. A student who dials one engagement quiet without
		# reaching the aim point has bought nothing for the next one — that is the trap the envelope
		# exists to show. The comparison is between two numbers the CORE ships (belief vs aim point),
		# never a client-side threshold on the physics (convention 13; slice 27's `rh != 0.0` label
		# is the precedent).
		# SLICE 31 — checked FIRST, and a SWITCH ahead of slice 30's (not an `or`): only a wire with an
		# IMPERFECT GYRO ships `gyro_scale_err`, so 26/27/28/29/30 keep their labels verbatim. It needs
		# its own string because the lesson is not "the belief is wrong" — the belief is whatever the
		# student set — it is that a SENSOR ERROR RESCALES IT, so the number that closes the loop is
		# `R̂(1+s)` and the design rule's own target moves to `R_worst/(1+s)`.
		# ⚠ THE THIRD STATE IS SLICE 30's AND IT MEANS THE SAME THING HERE: quiet at THIS gyro is not
		# quiet at the gyro you will actually be shipped. The comparison is between two numbers the CORE
		# ships (the EFFECTIVE belief vs the re-aimed point), never a client-side threshold on the
		# physics (convention 13).
		if _telemetry.has(_af3d_missile + ".gyro_scale_err"):
			qr = _radome_qpeak                    # rides |r| here too (a slice-31 wire has a ripple)
			var eff31 := float(_telemetry.get(_af3d_missile + ".radome_slope_est_eff", 0.0))
			var aim31 := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
			lbl = _gyro_verdict_label(qr > 0.5, eff31, aim31)
		elif _telemetry.has(_af3d_missile + ".cross_speed_mps"):
			qr = _radome_qpeak                    # rides |r| here too (an envelope wire has a ripple)
			var rh30 := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			var aim30 := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
			if qr > 0.5:
				lbl = "ENVELOPE — RINGING at this crossing"
			else:
				# ⚠ THE TOLERANCE IS NOT COSMETIC: the aim point is a Float64 sum that lands at
				# −0.32999999999999996, not −0.33 (gate 2's own note), and the slider a student drags
				# carries the decimal. Without the epsilon the verdict flips on a rounding direction
				# at EXACTLY the value the lesson asks them to hit. Nothing headless can catch this —
				# `_draw` never runs there — so the shot is the only evidence this branch has.
				lbl = "AIMED AT R₀+2A — the SAFE side" if rh30 <= aim30 + 1.0e-9 \
					  else "QUIET HERE — R̂ above the aim point"
		elif _telemetry.has(_af3d_missile + ".radome_sched_slope"):
			qr = _radome_qpeak                    # rides |r| here too (a schedule wire has a ripple)
			lbl = "SCHEDULED R̂ — RINGING at own INDEX" if qr > 0.5 \
				  else "SCHEDULED R̂(look) — loop STABLE"
		elif _telemetry.has(_af3d_missile + ".radome_slope_az"):
			qr = _radome_qpeak                    # rides |r| on this wire (see _airframe3d_on_state)
			if qr > 0.5:
				lbl = "RADOME SLOPE CURVE — RINGING in YAW"
			elif float(_telemetry.get(_af3d_missile + ".radome_ripple", 0.0)) != 0.0:
				lbl = "SLOPE CURVE — R̂ matched, loop STABLE"
			else:
				lbl = "FLAT GLASS (A = 0) — loop STABLE"
		elif _telemetry.has(_af3d_missile + ".radome_residual"):
			# ⚠ THE VERDICT USES THE PEAK-HOLD, NOT THE INSTANTANEOUS RATE (see _airframe3d_on_state):
			# the first shot of this slice caught the cycle mid-swing at q = −0.301 and the headline
			# read "loop STABLE" on a ringing missile.
			# ⚠ AND "COMPENSATED" IS EARNED, NOT ASSUMED — the shipped wire OPENS with R̂ = 0, a
			# compensator that BELIEVES NOTHING, and calling that "compensated" would have named the
			# cure on the arm that has none. Three states, because the knob really has three.
			var rh := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			qr = _radome_qpeak                    # the verdict below (and `col`) ride the peak-hold
			if qr > 0.5:
				lbl = "RADOME LOOP — RINGING, under-comp" if rh != 0.0 \
					  else "RADOME LOOP — RINGING, NO comp"
			else:
				lbl = "RADOME COMPENSATED — loop STABLE" if rh != 0.0 \
					  else "RADOME — refracting, loop STABLE"
		else:
			lbl = "RADOME PARASITIC LOOP — RINGING" if qr > 0.5 \
				  else ("RADOME — refracting, loop STABLE" if slope != 0.0 else "NO RADOME — R = 0")
		col = Color(1.00, 0.62, 0.30) if qr > 0.5 else Color(0.45, 0.90, 1.00)
	elif _fidelity.has("seeker_axes"):
		var see := str(_fidelity.get("seeker_axes", "pitch_plane"))
		var is3d := see == "az_el"
		lbl = "AZ/EL SEEKER — LOS rate in 3-D" if is3d else "IN-PLANE SEEKER — BLIND out of plane"
		col = Color(0.45, 0.90, 1.00) if is3d else Color(1.00, 0.62, 0.30)
	elif _fidelity.has("steering"):
		is_bank = str(_fidelity.get("steering", "skid_to_turn")) == "bank_to_turn"
		lbl = "BANK-TO-TURN — banking to turn (roll lag)" if is_bank else "SKID-TO-TURN — lift in two planes, no roll"
		col = Color(1.00, 0.62, 0.30) if is_bank else Color(0.45, 0.90, 1.00)
	else:
		var rung := str(_fidelity.get("airframe", "point_mass"))
		var is6 := rung == "six_dof"
		lbl = "SKID-TO-TURN — turning in 3-D" if is6 else ("PITCH-PLANE — out-of-plane DISCARDED" if rung == "pitch_coupled" else "POINT-MASS reference")
		col = Color(0.45, 0.90, 1.00) if is6 else Color(1.00, 0.62, 0.30)
	draw_string(_font, Vector2(vp.x - 430, 40), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	if _af3d_missile != "" and _telemetry.has(_af3d_missile + ".los_range"):
		draw_string(_font, Vector2(vp.x - 430, 66), "range to target: %.0f m" % float(_telemetry[_af3d_missile + ".los_range"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	var mpos: Array = _entities.get(_af3d_missile, {}).get("pos", [0, 0, 0])
	if mpos.size() >= 2:
		draw_string(_font, Vector2(vp.x - 430, 88), "cross-range (out of plane): %+.0f m" % float(mpos[1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	# SLICE 24 — the BANK angle (roll about velocity), the roll-lag tell (shipped only on the bank_to_turn
	# wire). φ ≈ 0 wings-level; the missile must roll to ~±90° to point its single lift plane cross-range.
	# SLICE 25 — THE HEADLINE READOUT: the out-of-plane content of the LOS rate THE SEEKER REPORTS.
	# EXACTLY 0.0 under :pitch_plane (ω ∥ ±ŷ by construction) — the blindness as ONE number, straight
	# from the core's `omega_oop` telemetry (no client-side physics — convention 13). Presence-gated,
	# so slices 23/24 are untouched; checked before the bank/β lines for the same reason the label is.
	# SLICE 26 — THE HEADLINE READOUT: the body rate (the thing that rings) and the boresight error
	# (the mechanism that makes it ring), both straight from core telemetry. Presence-gated on
	# `radome_eps`, which only a radome wire ships, so slices 23/24/25 are untouched; checked before
	# the omega_oop line for the same reason the label is (a radome wire carries BOTH keys).
	# SLICE 32 — checked FIRST, matching the label chain above, and it is a SWITCH ahead of the whole
	# radome cascade (not an `or`): a FOV wire has NONE of the `radome_*` keys, so every line below
	# would `get(..., 0.0)` and print a confident 0.000 — the stale-readout class this arc has caught
	# seven times, and precisely what gate 2's blocking advisor catch was about one layer up.
	# SLICE 33 — THE COMPOSITION, checked FIRST and a SWITCH ahead of both (the same order as the
	# label chain above). It draws BOTH instruments because the lesson is a TRANSACTION: what is
	# spending (the ring, in the yaw channel — the lead is in AZIMUTH on this crossing geometry, so a
	# `q` meter would show a calm number in front of a shaking missile, slice 28's catch) and what is
	# being spent (`seeker_fov_margin_deg`, this slice's one new number). Slice 32's block draws only
	# the second half and the whole radome cascade draws only the first; neither can show a budget.
	# SLICE 34 — THE HEAD, checked FIRST here too and for the same reason (the two chains must agree,
	# or the headline would name the head while the body lines described the glass). It draws FIVE
	# lines rather than four because a gimbal has TWO limits read against TWO DIFFERENT ANGLES, and
	# collapsing them is exactly the defect the plan's gate-3 note predicted.
	# SLICE 35 — THE SERVO, checked FIRST here too and for the reason the two chains must always agree:
	# a headline naming the servo above body lines describing the DETECTOR BUDGET would pair the wrong
	# two numbers, which is the defect slice 34's own gate-3 note predicted one slice earlier. It draws
	# FIVE lines like slice 34's, but only ONE of them is shared — the trade is DEMAND vs CAP and RING
	# vs LAG, where slice 34's is TRAVEL vs STOP and ERROR vs WINDOW.
	# SLICE 36 — THE HANDOVER BASKET, checked FIRST here too and for the reason the two chains must always
	# agree: a headline naming the handover above body lines describing a CURE THAT DOES NOT EXIST ON THIS
	# WIRE (two 0.000s of absent glass) is the worst pairing in the family so far — it is slice 35's
	# invisible slice AND the stale-readout class in one frame. It draws FIVE lines like 34's and 35's, and
	# shares exactly two of them (the detector budget and the head's state); the mechanism line and the
	# requirement-vs-window line are this slice's own, and no ring line is drawn at all.
	# SLICE 37 — THE SERVO'S REFERENCE FRAME, checked FIRST here too and for the reason the two chains
	# must ALWAYS agree: a headline naming the frame above body lines drawing slice 35's unlabelled
	# demand-vs-cap pair would be the invited subtraction with a correct verdict sitting on top of it —
	# which is precisely the shape slice 36's windowed shot caught and no test would have.
	if _gimbal_frame_view:
		_draw_frame_hud_lines(vp)
	elif _gimbal_handover_view:
		_draw_handover_hud_lines(vp)
	elif _gimbal_rate_view:
		_draw_gimbal_rate_hud_lines(vp)
	elif _gimbal_view:
		_draw_gimbal_hud_lines(vp)
	elif _seeker_fov_view and _radome_view:
		_draw_budget_hud_lines(vp)
	elif _seeker_fov_view:
		_draw_fov_hud_lines(vp,
				float(_telemetry.get(_af3d_missile + ".seeker_fov_deg", 0.0)),
				float(_telemetry.get(_af3d_missile + ".lead_angle_deg", 0.0)))
	elif _telemetry.has(_af3d_missile + ".radome_eps"):
		# ⚠ SLICE 28 — THE RATE LINE FOLLOWS THE RINGING CHANNEL, and that is not cosmetic. On a
		# slope-CURVE wire the lead angle is in AZIMUTH, so the yaw channel sits on the steep part of
		# the glass while the pitch channel sits on the boresight slope: showing `q` here would put a
		# small, calm number in front of a student watching the missile shake (measured rms 0.101
		# pitch against 1.042 yaw). A SWITCH on the slice-28 key, so 26/27 render byte-identically.
		var yaw_ch := _telemetry.has(_af3d_missile + ".radome_slope_az")
		var bq := float(_telemetry.get(_af3d_missile + (".omega_r" if yaw_ch else ".omega_q"), 0.0))
		var eps := float(_telemetry[_af3d_missile + ".radome_eps"])
		var lka := float(_telemetry.get(_af3d_missile + ".look_angle", 0.0))
		draw_string(_font, Vector2(vp.x - 430, 110), "body %s rate %s: %+.3f rad/s%s" % ["yaw" if yaw_ch else "pitch", "r" if yaw_ch else "q", bq, "   ← RINGING" if absf(bq) > 0.5 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if absf(bq) > 0.5 else COL_TICK)
		draw_string(_font, Vector2(vp.x - 430, 132), "radome boresight error ε: %+.5f rad   (look angle %.1f°)" % [eps, lka],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
		# SLICE 27 — the COMPENSATOR line, a SWITCH on `radome_residual` (not an `or`): a slice-26
		# wire ships no such key and renders its own line unchanged, byte-identical. The RESIDUAL is
		# what actually decides — `N·|R − R̂|/ρ ≈ 0.38` — and it arrives from the core as ONE NUMBER
		# so the client never subtracts (convention 13, the slice-21 `rho_air` precedent).
		# ⚠ A student who drags R̂ and sees the ring die with R̂ nowhere on screen has been shown
		# nothing, which is why this slice is not zero client code.
		# SLICE 28 — THE THREE LINES THAT ARE THE LESSON, and they must be a SWITCH ahead of slice
		# 27's (not an `or`): a slope-curve wire ships `radome_slope_az`, which 26/27 never do, so
		# their block below renders verbatim. What a student has to SEE is the PAIR: the HARDWARE
		# residual R0 − R̂ is exactly 0.000 — the compensator matches the glass it was characterized
		# against, perfectly — while the ENGAGEMENT residual R(look_az) − R̂ is nowhere near it,
		# because the seeker is looking through a steeper part of the same glass. Dragging either
		# slider moves the second number, and the ring follows THAT one.
		# ⚠ PER AXIS, NEVER AN AGGREGATE AT hypot(look_az, look_el): that third quantity is the gain
		# of NEITHER channel (the gate-2 hardening), and the HUD is exactly where a student would read
		# it as the lesson. Both gains arrive from the core as NUMBERS — the client never evaluates
		# the curve (convention 13, the slice-21 `rho_air` precedent).
		# SLICE 29 — THE THREE LINES THAT ARE ITS LESSON, a SWITCH ahead of slice 28's (not an `or`):
		# only a SCHEDULED wire ships `radome_sched_slope`, so 26/27/28 render byte-identically.
		# What a student must SEE is that the TWO error numbers DISAGREE, and which one the ring
		# follows. The MODEL error is the belief against the glass at the SAME look angle — the bench
		# number, what "how good is my schedule?" naturally means. The LOOP RESIDUAL is the belief
		# against the glass where the compensator ACTUALLY EVALUATES IT: at its own index, which the
		# radome bent. On the shipped arm the model error is the SMALLER of the two and it rings;
		# drag k̂ up past the truth and the model gets WORSE while the ring dies.
		# ⚠ Both arrive from the core as NUMBERS — the client never evaluates a curve or subtracts
		# anything (convention 13, the slice-21 `rho_air` precedent). ⚠ And the index pair is on
		# screen because without it the crossover looks like a contradiction rather than a mechanism.
		# SLICE 30 — THE THREE LINES THAT ARE ITS LESSON, a SWITCH ahead of slice 29's (not an `or`):
		# only a wire whose TARGET carries the crossing-speed knob ships `cross_speed_mps`, so
		# 26/27/28/29 render byte-identically below. ⚠ THE DISCRIMINATOR IS *NOT*
		# `radome_slope_worst`: gate 2 measured that key as ADDITIVE on every ripple-carrying wire,
		# so slices 28 and 29 grow it too and it would capture their views.
		# ⭐⭐ THE ONE LINE THE LESSON REQUIRES IS THE AIM POINT SHOWN *LIVE BESIDE* R̂. The rule is
		# "put the scalar at or below the most negative slope this glass reaches ANYWHERE" — and the
		# glass is a SLIDER here, so dragging A MOVES THE RULE'S OWN TARGET. Without this line a
		# student who deepens the glass silently invalidates the R̂ they already set, which is the
		# exact defect slice 28 ate once. ⚠ It arrives from the core as a NUMBER (`radome_slope_worst`
		# = min(R₀, R₀+2A)); the client never evaluates the curve or adds anything (convention 13,
		# the slice-21 `rho_air` precedent).
		# ⚠ "OR BELOW", NEVER "= the threshold": the rule is SUFFICIENT, NEVER TIGHT (the envelope
		# goes quiet ABOVE it, at −0.28 against −0.33), and the HUD is exactly where a student would
		# read a bound as a measured boundary.
		# ⚠ AND THE CROSSING SPEED IS ON SCREEN BECAUSE THE ENGAGEMENT IS THIS SLICE'S NEW AXIS: the
		# residual below is a property of the engagement, not of the hardware, so the label that says
		# WHICH engagement is being flown belongs beside it.
		# SLICE 31 — THE FOUR LINES THAT ARE ITS LESSON, a SWITCH ahead of slice 30's (not an `or`):
		# only a wire with an IMPERFECT GYRO ships `gyro_scale_err`, so 26/27/28/29/30 render
		# byte-identically below. ⚠ THE DISCRIMINATOR IS THE GYRO KEY ITSELF — the same reason slice 30
		# could not use `radome_slope_worst` (an ADDITIVE key captures the earlier views), and it is
		# checked FIRST because a slice-31 wire may carry any of the earlier keys as well.
		# ⭐⭐ THE ONE LINE THE LESSON REQUIRES IS THE **EFFECTIVE** BELIEF BESIDE THE AUTHORED ONE. A
		# scale-factor error is common-mode on the feed-forward product, so what closes the loop is
		# `R̂(1+s)` and NOT the R̂ the designer set — a student who reads only the slider cannot see why a
		# competent-looking design rings. ⚠ BOTH numbers arrive from the core (convention 13: the client
		# never multiplies physics).
		# ⭐ AND THE AIM POINT IS RE-AIMED FOR THE GYRO: slice 30's rule becomes `R_worst/(1+s)`, shipped
		# as `radome_aim_gyro`, so dragging the GYRO slider moves THE RULE'S OWN TARGET exactly as
		# dragging the glass did in slice 30. ⚠ "or below", never "= the threshold" — the rule is
		# SUFFICIENT, NEVER TIGHT, and the HUD is exactly where a student would misread a bound.
		# ⚠ THE BIAS LINE IS NOT DECORATION: it is the OTHER CURRENCY, and the term no other knob on this
		# wire reaches. It ships the injection `R̂·b` as a number, so a student can watch it GROW as they
		# cure the ring by aiming deeper — the same sensor costing more the more you compensate.
		if _telemetry.has(_af3d_missile + ".gyro_scale_err"):
			var s31 := float(_telemetry[_af3d_missile + ".gyro_scale_err"])
			var rh31 := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			var eff31 := float(_telemetry.get(_af3d_missile + ".radome_slope_est_eff", 0.0))
			var aim31 := float(_telemetry.get(_af3d_missile + ".radome_aim_gyro", 0.0))
			var rez31 := float(_telemetry.get(_af3d_missile + ".radome_residual_az_eff", 0.0))
			var bz31 := float(_telemetry.get(_af3d_missile + ".gyro_bias_z", 0.0))
			var inj31 := float(_telemetry.get(_af3d_missile + ".gyro_inject_az", 0.0))
			# ⚠ WIDTHS ARE MEASURED, NOT GUESSED: ~55 characters fit at 15 px from `vp.x − 430`, and
			# slice 28's first capture ran two lines off the right edge. Each line below is counted.
			draw_string(_font, Vector2(vp.x - 430, 154), "R̂ %+.3f  ×(1%+.2f) → LOOP SEES %+.3f" % [rh31, s31, eff31],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
			draw_string(_font, Vector2(vp.x - 430, 176), "gyro AIM AT %+.3f or below  (bias %+.3f rad/s)" % [aim31, bz31],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
			# coloured by the SAME peak-hold verdict as the headline, so a frame caught mid-swing cannot
			# show an orange headline over a green residual (slice 27's shot-harness defect)
			draw_string(_font, Vector2(vp.x - 430, 198), "ENGAGEMENT RESIDUAL %+.3f (eff) ← closes the loop" % rez31,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else Color(0.55, 1.00, 0.65))
			draw_string(_font, Vector2(vp.x - 430, 220), "bias injects %+.5f rad/s — the OTHER currency" % inj31,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.70, 0.80, 1.00))
		elif _telemetry.has(_af3d_missile + ".cross_speed_mps"):
			var rh30 := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			var aim30 := float(_telemetry.get(_af3d_missile + ".radome_slope_worst", 0.0))
			var saz30 := float(_telemetry.get(_af3d_missile + ".radome_slope_az", 0.0))
			var rez30 := float(_telemetry.get(_af3d_missile + ".radome_residual_az", 0.0))
			var vy30 := float(_telemetry[_af3d_missile + ".cross_speed_mps"])
			# ⚠ WIDTHS ARE MEASURED, NOT GUESSED: ~55 characters fit at 15 px from `vp.x − 430`, and
			# slice 28's first capture ran two lines off the right edge. Each line below is counted.
			draw_string(_font, Vector2(vp.x - 430, 154), "R₀ %+.3f   R̂ %+.3f   AIM AT %+.3f or below" % [float(_telemetry.get(_af3d_missile + ".radome_slope", 0.0)), rh30, aim30],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
			draw_string(_font, Vector2(vp.x - 430, 176), "engagement: crossing %.0f m/s   R(look) yaw %+.3f" % [vy30, saz30],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
			# coloured by the SAME peak-hold verdict as the headline (which rides |r| on a
			# ripple-carrying wire), so a frame caught mid-swing cannot show an orange headline over
			# a green residual (slice 27's shot-harness defect)
			draw_string(_font, Vector2(vp.x - 430, 198), "ENGAGEMENT RESIDUAL %+.3f  ← THIS closes the loop" % rez30,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else Color(0.55, 1.00, 0.65))
		elif _telemetry.has(_af3d_missile + ".radome_sched_slope"):
			var lt29 := float(_telemetry.get(_af3d_missile + ".look_angle", 0.0))
			var le29 := float(_telemetry.get(_af3d_missile + ".look_angle_est", 0.0))
			var mde29 := float(_telemetry.get(_af3d_missile + ".radome_model_err_az", 0.0))
			var rez29 := float(_telemetry.get(_af3d_missile + ".radome_residual_az", 0.0))
			# ⚠ WIDTHS ARE MEASURED, NOT GUESSED: ~55 characters fit at 15 px from `vp.x − 430`, and
			# slice 28's first capture ran two lines off the right edge (slice 26 ate the same defect
			# at 20 px). Every line below is counted against that budget.
			draw_string(_font, Vector2(vp.x - 430, 154), "schedule Â %+.3f  k̂ %.1f   (glass A %+.3f)" % [float(_telemetry.get(_af3d_missile + ".radome_ripple_est", 0.0)), float(_telemetry.get(_af3d_missile + ".radome_ripple_k_est", 0.0)), float(_telemetry.get(_af3d_missile + ".radome_ripple", 0.0))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
			draw_string(_font, Vector2(vp.x - 430, 176), "MODEL err vs glass %+.3f   ← the BENCH number" % mde29,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
			# coloured by the SAME peak-hold verdict as the headline, so a frame caught mid-swing
			# cannot show an orange headline over a green residual (slice 27's shot-harness defect)
			draw_string(_font, Vector2(vp.x - 430, 198), "LOOP RESID %+.3f @ own index %.1f° (truth %.1f°)" % [rez29, le29, lt29],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else Color(0.55, 1.00, 0.65))
		elif _telemetry.has(_af3d_missile + ".radome_slope_az"):
			var rh2 := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			var saz := float(_telemetry[_af3d_missile + ".radome_slope_az"])
			var sel := float(_telemetry.get(_af3d_missile + ".radome_slope_el", 0.0))
			var rez := float(_telemetry.get(_af3d_missile + ".radome_residual_az", 0.0))
			# ⚠ WIDTHS ARE MEASURED, NOT GUESSED: at 15 px from `vp.x − 430` about 55 characters fit,
			# and the first capture of this slice ran BOTH of these lines off the right edge — the
			# clipped words being "…← this closes t|", i.e. exactly the part that says which residual
			# matters. Slice 26 ate the same defect on its 20 px headline.
			draw_string(_font, Vector2(vp.x - 430, 154), "R₀ %+.3f   R̂ %+.3f   hardware residual %+.3f" % [float(_telemetry.get(_af3d_missile + ".radome_slope", 0.0)), rh2, float(_telemetry.get(_af3d_missile + ".radome_residual", 0.0))],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
			draw_string(_font, Vector2(vp.x - 430, 176), "R(look) — yaw channel %+.3f, pitch channel %+.3f" % [saz, sel],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
			# coloured by the SAME peak-hold verdict as the headline (which rides |r| here), so a
			# frame caught mid-swing cannot show an orange headline over a green residual
			draw_string(_font, Vector2(vp.x - 430, 198), "ENGAGEMENT RESIDUAL %+.3f  ← THIS closes the loop" % rez,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else Color(0.55, 1.00, 0.65))
		elif _telemetry.has(_af3d_missile + ".radome_residual"):
			var rhat := float(_telemetry.get(_af3d_missile + ".radome_slope_est", 0.0))
			var resid := float(_telemetry[_af3d_missile + ".radome_residual"])
			draw_string(_font, Vector2(vp.x - 430, 154), "R %+.3f   estimate R̂ %+.3f" % [float(_telemetry.get(_af3d_missile + ".radome_slope", 0.0)), rhat],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
			# the residual is coloured by the SAME peak-hold verdict as the headline, so a frame
			# caught mid-swing cannot show an orange headline over a green residual (or vice versa)
			draw_string(_font, Vector2(vp.x - 430, 176), "RESIDUAL R − R̂ = %+.3f   ← this closes the loop" % resid,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if _radome_qpeak > 0.5 else Color(0.55, 1.00, 0.65))
		else:
			draw_string(_font, Vector2(vp.x - 430, 154), "slope R = %+.3f   —   the threshold is the LOOP GAIN N·|R|" % float(_telemetry.get(_af3d_missile + ".radome_slope", 0.0)),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	elif _telemetry.has(_af3d_missile + ".omega_oop"):
		var oop := float(_telemetry[_af3d_missile + ".omega_oop"])
		draw_string(_font, Vector2(vp.x - 430, 110), "seeker ω out-of-plane: %.5f rad/s%s" % [oop, "   ← BLIND" if oop == 0.0 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.62, 0.30) if oop == 0.0 else Color(0.45, 0.90, 1.00))
	elif _telemetry.has(_af3d_missile + ".bank_deg"):
		draw_string(_font, Vector2(vp.x - 430, 110), "bank φ: %+.0f°  (τ_roll roll lag)" % float(_telemetry[_af3d_missile + ".bank_deg"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.00, 0.85, 0.45))
	elif _telemetry.has(_af3d_missile + ".beta"):
		draw_string(_font, Vector2(vp.x - 430, 110), "sideslip β: %+.1f°" % rad_to_deg(float(_telemetry[_af3d_missile + ".beta"])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_TICK)
	draw_string(_font, Vector2(maxf(8.0, vp.x - 760), vp.y - 16),
			"3-D airframe view — vertical ×%.1f (display only) · cyan trail = interceptor, orange = target off the x–z plane · drag: orbit · wheel: zoom" % T3D_VEXAG,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TICK)

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
	# Orbit/zoom for the 3-D camera — terrain (slice 18) AND airframe3d (slice 23) both use the
	# _t3d_cam orbit (display only; other views ignore input here).
	if (_mode != "terrain" and _mode != "airframe3d") or _t3d_cam == null:
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
		"atmosphere":
			# Slice-21: the button IS the atmosphere cycler (constant ↔ exponential). Unlike "airframe"
			# below there is no hidden arm — an atmosphere scenario ALWAYS has something to cycle (the
			# rung is the lesson), so no visibility branch.
			_prop_btn.text = "atm: %s" % str(_fidelity.get("atmosphere", "?"))
		"steering":
			# Slice-24: the button IS the steering cycler (skid_to_turn ↔ bank_to_turn). Always something
			# to cycle (the rung is the lesson), like atmosphere — no visibility branch.
			_prop_btn.visible = true
			_prop_btn.text = "steering: %s" % str(_fidelity.get("steering", "?"))
		"seeker_axes":
			# Slice-25: the button IS the seeker-axes cycler (pitch_plane ↔ az_el). Same shape as
			# steering/atmosphere — the rung IS the lesson, so no visibility branch.
			_prop_btn.visible = true
			_prop_btn.text = "seeker: %s" % str(_fidelity.get("seeker_axes", "?"))
		"seeker_head":
			# ⭐⭐ SLICE 37: the button IS the servo-reference-frame cycler (body_referenced ↔
			# space_stabilized), and this arm is the SECOND SITE of the button's RESTORATION — the
			# mirror image of the drop that the `"airframe"` arm below performs three times over. It
			# gets its OWN arm rather than a defence inside `"airframe"` (slice 26/32/36's shape)
			# precisely because the outcome is the opposite one: those arms exist to STOP a re-show,
			# this one exists to GUARANTEE one. ⚠ `visible = true` is EXPLICIT and not inherited —
			# falling through to the `"airframe"` arm would cycle the HELD `:airframe` key, which is
			# the convention-9 "toggle a held key" trap those very defences were built for.
			_prop_btn.visible = true
			_prop_btn.text = "head: %s" % str(_fidelity.get("seeker_head", "?"))
		"airframe":
			if _gimbal_handover_view:
				# SLICE 36 THE HANDOVER BASKET — the SECOND site of the same drop, and here it is
				# LOAD-BEARING rather than defensive, unlike the two arms below. ⚠⚠ On a no-glass wire
				# `_enter_airframe3d_mode` sets `_fid_kind = "airframe"` from its OWN new branch, so
				# without this arm the `_fidelity.has("airframe")` branch below would re-show the button
				# it just dropped (the scenario DOES carry an `:airframe` fidelity, HELD at six_dof) and
				# cycling that held key is the convention-9 "toggle a held key" trap. There is no rung to
				# cycle: the lesson is an AUTHORED pair of wires plus ONE servo slider, and the authored
				# key is structurally a dead knob. Option-P′'s fourth use, and the FIRST time since slice
				# 26 that the drop genuinely needs both sites.
				_prop_btn.visible = false
			elif _seeker_fov_view:
				# Slice-32 THE SEEKER'S FIELD OF VIEW: same defence as the radome arm below and for
				# the same reason — the scenario DOES carry an `:airframe` fidelity (HELD at six_dof),
				# so the `_fidelity.has("airframe")` branch would re-show the button that
				# _enter_airframe3d_mode deliberately dropped. There is no rung to cycle (the lesson
				# is the FOV slider), and cycling the HELD :airframe would be the convention-9
				# "toggle a held key" trap. Option-P′'s third use needs BOTH sites, exactly as slice
				# 26 found for its second.
				_prop_btn.visible = false
			elif _radome_view:
				# Slice-26 THE RADOME: the scenario DOES carry an `:airframe` fidelity (HELD at six_dof),
				# so the branch below would re-show the button that _enter_airframe3d_mode deliberately
				# dropped. There is no rung to cycle here — the lesson is the radome_slope SLIDER — and
				# cycling the HELD :airframe would be the convention-9 "toggle a held key" trap. Keep it
				# hidden (the slice-16 arm's "defensive against a re-show" shape, second use).
				_prop_btn.visible = false
			elif _fidelity.has("airframe"):
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
	# PER-SCENARIO ring (_airframe_rungs): the slice-17/19 2-ring point_mass↔pitch_coupled, or the
	# slice-23 3-ring point_mass→pitch_coupled→six_dof (set in _enter_airframe3d_mode). six_dof there
	# is a DEAD rung (no 6-DOF params) so the 2-ring scenarios never expose it.
	var cur := str(_fidelity.get("airframe", "point_mass"))
	var i := _airframe_rungs.find(cur)
	var next: String = _airframe_rungs[(i + 1) % _airframe_rungs.size()] if i >= 0 else "point_mass"
	_fidelity["airframe"] = next
	_client.send({"type": "set_fidelity", "key": "airframe", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_steering_pressed() -> void:
	# Advance the STEERING rung (skid_to_turn ↔ bank_to_turn) and tell the core (set_fidelity). Slice-24
	# BANK-TO-TURN — the payoff of the STT-first arc. Both laws run on the HELD :six_dof plant; the ONLY
	# variable is HOW the ⟂-v lift is pointed. Under :skid_to_turn the missile makes lift in TWO body
	# planes at once (no roll) and INTERCEPTS the out-of-plane target (slice 23). Press once → :bank_to_turn
	# makes lift in ONE plane and must ROLL to point it; with a finite τ_roll the roll LAGS, so the trail
	# stays flat then banks LATE and MISSES (~372 m at τ_roll = 1.0). Class 4c — PHYSICS-CHANGING, NO RNG
	# (truth-fed PN, no seeker ⇒ "draw-count invariance" VACUOUS; the :airframe/:atmosphere precedent),
	# LIVE-SETTABLE (no set_fidelity guard). The τ_roll slider (auto knob) dials the lag: → 0 recovers STT.
	# The client owns the displayed rung (badge + button locally; the server applies it on the next tick).
	var cur := str(_fidelity.get("steering", "skid_to_turn"))
	var i := STEERING_RUNGS.find(cur)
	var next: String = STEERING_RUNGS[(i + 1) % STEERING_RUNGS.size()] if i >= 0 else "skid_to_turn"
	_fidelity["steering"] = next
	_client.send({"type": "set_fidelity", "key": "steering", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_seeker_axes_pressed() -> void:
	# A SEEKER IN THE 6-DOF LOOP — the sensor half of the 3-D arc. Both rungs run the SAME α-β tracker
	# on the SAME held :six_dof skid-to-turn plant against the SAME target; the ONLY variable is how
	# many ANGLES the seeker measures. Under :pitch_plane (the default — the showcase OPENS on the
	# miss) it measures ONE in-plane bearing, so its ω is structurally ∥ ±ŷ, the cross-range command is
	# never FORMED, and the trail stays FLAT in the x–z plane (max|y| = 0.0 EXACTLY) → ~2000 m miss.
	# Press once → :az_el measures an az/el PAIR, rebuilds the LOS-rate VECTOR, and the SAME airframe
	# yaws out to intercept. ⚠ NOT a ceiling miss: `aero_sat` is 0 in BOTH arms (the isolation) — the
	# missile has the authority and is simply never told to use it. Class 4a — DRAW-INVARIANT (both
	# rungs draw 2 randn/tick; the foil DISCARDS the azimuth sample) YET TRAJECTORY-CHANGING, so it is
	# LIVE-SETTABLE with NO set_fidelity guard, UNLIKE :cfar/:scan. The client owns the displayed rung
	# (badge + button locally; the server applies it on the next tick).
	var cur := str(_fidelity.get("seeker_axes", "pitch_plane"))
	var i := SEEKER_AXES_RUNGS.find(cur)
	var next: String = SEEKER_AXES_RUNGS[(i + 1) % SEEKER_AXES_RUNGS.size()] if i >= 0 else "pitch_plane"
	_fidelity["seeker_axes"] = next
	_client.send({"type": "set_fidelity", "key": "seeker_axes", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_seeker_head_pressed() -> void:
	# ⭐⭐ SLICE 37 — THE GIMBAL SERVO'S REFERENCE FRAME, and this is the first rung on the shared button
	# since slice 25 (slices 26–36 all dropped it — the lesson was a slider every time). Both rungs fly
	# the SAME head, the SAME glass, the SAME believed slope, the SAME seed and the SAME 40 °/s servo;
	# the ONLY variable is WHICH FRAME the servo closes its loop in. Under :body_referenced (the default
	# — the showcase OPENS on the design that WORKS) the servo target is the LOS in BODY angles, so the
	# servo's job includes TRACKING OUT the missile's own rotation, and its LAG therefore LOW-PASSES
	# body motion out of the radome's INDEX. Press once → :space_stabilized holds the pointing in the
	# INERTIAL frame (head-mounted rate gyros), body motion is REJECTED PASSIVELY, the index is
	# unfiltered — and at this wire's R̂ the SAME quiet missile RINGS 85.4× harder. ⚠ IT STILL HITS: the
	# miss is not the metric here, as in every slice of this family since 26.
	# ⚠⚠ THE TEXTBOOK IMPROVEMENT REMOVES MARGIN — the classical reason gimbals exist INVERTS on this
	# wire, because the position servo's lag was doing stability work nobody had asked it for.
	# ⚠ Class 4a — DRAW-INVARIANT (no draw topology to flip), so LIVE-SETTABLE with NO set_fidelity
	# guard, UNLIKE :cfar/:scan. Measured rather than assumed: over a mid-run press the RNG state after
	# 4000 ticks is EQUAL to the never-pressed run's while the trajectories differ by 2.000 m, and the
	# head's pointing CARRIES ACROSS the press (its body angle moves 1.034× a normal tick's motion —
	# one birth held in two frames, not two births). The client owns the displayed rung (badge + button
	# locally; the server applies it on the next tick).
	var cur := str(_fidelity.get("seeker_head", "body_referenced"))
	var i := SEEKER_HEAD_RUNGS.find(cur)
	var next: String = SEEKER_HEAD_RUNGS[(i + 1) % SEEKER_HEAD_RUNGS.size()] if i >= 0 else "body_referenced"
	_fidelity["seeker_head"] = next
	_client.send({"type": "set_fidelity", "key": "seeker_head", "value": next})
	_render_badge()
	_update_fid_btn()

func _on_atmosphere_pressed() -> void:
	# Advance the ATMOSPHERE rung (constant↔exponential) and tell the core (set_fidelity). Slice-21 —
	# **the live side-by-side IS the punchline**, which is exactly why this is a rung and not a slider:
	# constant ρ is H = ∞, a LIMIT POINT no H value on the slider reaches, so only this button can show
	# you the old model. Under :constant the missile flies slices 8–20's authored ρ — its ceiling never
	# binds ONCE and it HITS (1.95 m); press once and ρ = ρ₀·exp(−z/H) falls as the missile CLIMBS, the
	# ceiling collapses to meet the demand, and the SAME missile on the SAME geometry MISSES by ~360 m.
	# Nothing else changed: ρ₀, S, C_Lα, α_max, mass, the target and its jink are all held. Class 4c —
	# PHYSICS-CHANGING, NO RNG (truth-fed PN, no seeker ⇒ "draw-count invariance" is VACUOUS — do NOT
	# copy the slice-11/13 draw language). LIVE-SETTABLE, NO introduce-reject (the
	# :integrator/:autopilot/:apn/:cooperation/:airframe precedent; the CONTRAST is slice-13's :scan).
	# The rung is INERT without :airframe === :pitch_coupled (ρ(z) reaches the coupled path only) — a
	# non-issue here, where the scenario authors :pitch_coupled fixed and this button cannot change it.
	# The client owns the displayed rung: badge + button locally (the server applies it silently, no reply).
	var cur := str(_fidelity.get("atmosphere", "constant"))
	var i := ATMOSPHERE_RUNGS.find(cur)
	var next: String = ATMOSPHERE_RUNGS[(i + 1) % ATMOSPHERE_RUNGS.size()] if i >= 0 else "constant"
	_fidelity["atmosphere"] = next
	_client.send({"type": "set_fidelity", "key": "atmosphere", "value": next})
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
	elif _mode == "airframe3d":
		_airframe3d_on_state(obj)
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

	# Slice-19: sample the g-ceiling vs the demand for the headline strip. Gated on `a_max_aero`, the
	# rung-gated key the `:alpha` autopilot ships (under BOTH :airframe arms — the ceiling is a
	# FLIGHT-CONDITION property, true whichever plant is active, which is exactly what makes the
	# point_mass contrast legible: the demand crosses the ceiling and the missile hits ANYWAY).
	if _airframe_view and _missile_id != "" and _telemetry.has(_missile_id + ".a_max_aero"):
		_ceil_hist.append(float(_telemetry[_missile_id + ".a_max_aero"]))
		_demand_hist.append(float(_telemetry.get(_missile_id + ".a_demand", 0.0)))
		_aero_sat_now = float(_telemetry.get(_missile_id + ".aero_sat", 0.0)) > 0.5
		# Slice 22: sample the stall tell alongside it. PRESENCE, not value, is the gate — a slice-19/20/21
		# wire never ships the key, so `_has_post_stall` stays false and nothing below it changes.
		_has_post_stall = _telemetry.has(_missile_id + ".post_stall")
		_post_stall_now = _has_post_stall and float(_telemetry[_missile_id + ".post_stall"]) > 0.5
		if _ceil_hist.size() > AERO_HIST_MAX:
			_ceil_hist.pop_front()
			_demand_hist.pop_front()

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
	_ceil_hist.clear()                    # slice-19: the g-ceiling/demand headline restarts too
	_demand_hist.clear()
	_aero_sat_now = false
	_post_stall_now = false               # slice-22: the stall tell restarts with the re-launch too
	_fov_lost = false                     # slice-32: the track-break latch restarts with the re-launch
	_gimbal_lost = false                  # slice-34: the HEAD's latch, for the same reason
	# ⚠ AND THIS IS A DELIBERATE BEHAVIOUR CHANGE TO SLICES 26–31, NAMED RATHER THAN SLIPPED IN
	# (advisor): `_radome_qpeak` was never cleared on reset, so pressing Reset on a RINGING wire
	# carried a stale RINGING verdict ~0.5 s into the re-launch (the hold is ~0.5 s at 62.5 Hz) —
	# the headline and the residual line both lying about a missile that has just been re-launched.
	# It is the same defect the slice-32 latch is built to avoid one slice later, so it is fixed
	# here rather than left as an asymmetry between two instruments in the same HUD. A tooth in
	# `slice32_ui_test.gd` drives `_on_reset_pressed()` on the slice-26 mirror and asserts it.
	_radome_qpeak = 0.0
	# Slice-35: the servo duty is cleared for EXACTLY the reason named above, and it is the sharper
	# case of the two — the duty's ~0.5 s time constant would carry a PEGGED-servo verdict straight
	# into a re-launch that opens on the LAUNCH TURN, which is itself the largest slew demand in the
	# engagement (gate 0 §0.4). A stale reading there would be indistinguishable from a real one.
	_servo_duty = 0.0
	# Slice-36: BOTH of this slice's instruments are cleared, and each for its own reason — this is the
	# THIRD time the family has had to fix a stale-instrument-across-reset defect, so it is done at the
	# same time as the code that creates it rather than found later.
	#   `_handover_peak` is a FROZEN MAXIMUM, so without this the requirement line would carry the
	#     PREVIOUS run's peak through a whole re-launch — and on a broken arm that peak is the ~105°
	#     post-break runaway, i.e. the single most misleading number this HUD can display.
	#   `_handover_los0` is a ONE-SHOT LATCH on the first frame's LOS azimuth; a stale one would pair the
	#     new run's live azimuth against the old run's birth angle, silently misreporting the excursion
	#     that IS the mechanism. Back to NAN, never 0.0 — a 0.000000° birth angle is a real state.
	_handover_peak = 0.0
	_handover_los0 = NAN
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
	elif _mode == "airframe3d":
		_draw_airframe3d_hud()   # the 3-D layer draws the world; the canvas only labels it
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
	if _fid_kind == "missile" or _fid_kind == "airframe" or _fid_kind == "atmosphere" or _fid_kind == "autopilot" or _fid_kind == "guidance" or _fid_kind == "seeker" or _fid_kind == "discrimination":
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

	# airframe view (slice 19): the g-ceiling vs the demand — THE HEADLINE. Only when the `:alpha`
	# rung ships the keys (slices 16/17 draw nothing new — the strip sits above the α chart).
	if _airframe_view and _ceil_hist.size() >= 2:
		_draw_aero_strip()

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

func _draw_aero_strip() -> void:
	# Slice-19 THE HEADLINE: the FLIGHT-CONDITION g-ceiling `a_max_aero = Q·S·C_Lα·α_max/m` (cyan) against
	# the guidance `a_demand` (orange), both live on one axis. Where the demand climbs ABOVE the ceiling the
	# air cannot give the missile the g PN asks for — the region is shaded RED and `aero_sat` lights. That
	# crossing is the whole slice: slices 10/12 capped the missile with an authored NUMBER (a_max); here the
	# cap is a physical consequence of the flight condition, and it MOVES (drag ρ down — thinner air — and
	# the cyan line drops while the orange one does not).
	#
	# ⚠ THE PLOT IS ILLUSTRATIVE, NOT EXACT — and the HUD says so. `aero_sat` fires on |a_perp| (the ⟂-v
	# PROJECTION of the command — the only component an airframe can actually make), while `a_demand` is the
	# FULL-magnitude pre-clamp demand. Since |a_perp| ≤ |a_cmd| ≤ |a_dem| the sets NEST: the drawn crossing
	# reads "breached" EARLIER and MORE OFTEN than the flag lights (the along-v̂ component reaches
	# 0.55·|a_cmd| and is unproducible by any airframe). Shipping `a_perp` as a 7th key would make them
	# agree exactly; the deliberate call (gate 3) is to keep the wire at 6 keys and LABEL the plot. The
	# FLAG is the ground truth — which is why the verifier asserts `aero_sat` and never a hand-rolled
	# `a_demand > a_max_aero`. All values are the core's own scalars; nothing is recomputed here.
	#
	# ⚠ SLICE 22 CHANGED WHICH FLAG LIGHTS THIS PANEL, and the reason is in the state-var comment
	# above (gate-2 G10): under a stall the ceiling drops to the curve's INTERIOR PEAK while
	# `aero_sat` still keys off the α_max CLAMP, so `aero_sat` alone UNDER-REPORTS the breach. On a
	# stall wire the tell is `post_stall` (the airframe is past its lift peak — 0 vs 1461 ticks
	# across the arms, where `aero_sat` moved only 36.7% → 37.3%). PRESENCE-GATED: slices 19/20/21
	# ship no `post_stall` key, so `_breach` collapses to `_aero_sat_now` and they are UNCHANGED.
	var _breach := _post_stall_now if _has_post_stall else _aero_sat_now
	var vp := get_viewport_rect().size
	var rect := Rect2(vp.x - 314.0, vp.y - MARGIN - 246.0, 300.0, 104.0)
	draw_rect(rect, COL_PANEL_BG)
	# the border LIGHTS while the aero ceiling is binding — the at-a-glance tell
	draw_rect(rect, Color(1.0, 0.35, 0.3, 0.95) if _breach else COL_PANEL_BORDER, false,
		2.0 if _breach else 1.0)
	draw_string(_font, rect.position + Vector2(6, -5),
		("g-ceiling vs demand (m/s²) — ceiling = the lift curve's PEAK" if _has_post_stall
			else "g-ceiling vs demand (m/s²) — crossing = the air can't give it"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	# Autoscale on the CEILING (×2.6), not the demand: the pre-clamp demand spikes to ~1e4 in the endgame
	# and would squash the ceiling to a flat line at the axis. The demand trace is CLAMPED to the top of
	# the panel and reads "pegged ≫ ceiling", which is the honest summary of a demand that far above it.
	var m := 1.0
	for v in _ceil_hist:
		m = maxf(m, float(v))
	m *= 2.6
	var y_of := func(a: float) -> float:
		return rect.end.y - clampf(a / m, 0.0, 1.0) * rect.size.y
	# the SHADED breach band: demand above ceiling (illustrative — see the header)
	for i in range(1, _ceil_hist.size()):
		var d: float = float(_demand_hist[i])
		var c: float = float(_ceil_hist[i])
		if d <= c:
			continue
		var x := rect.position.x + (float(i) / float(AERO_HIST_MAX - 1)) * rect.size.x
		draw_line(Vector2(x, y_of.call(c)), Vector2(x, y_of.call(d)), Color(1.0, 0.3, 0.25, 0.16), 1.5)
	var ceil_pts := PackedVector2Array()
	var dem_pts := PackedVector2Array()
	for i in _ceil_hist.size():
		var x := rect.position.x + (float(i) / float(AERO_HIST_MAX - 1)) * rect.size.x
		ceil_pts.append(Vector2(x, y_of.call(float(_ceil_hist[i]))))
		dem_pts.append(Vector2(x, y_of.call(float(_demand_hist[i]))))
	draw_polyline(dem_pts, Color(1.0, 0.62, 0.2, 0.85), 1.5)      # a_demand (PN, pre-clamp)
	draw_polyline(ceil_pts, Color(0.35, 0.9, 1.0, 0.95), 2.0)     # a_max_aero — THE ceiling
	draw_string(_font, rect.position + Vector2(6, 13), "%.0f" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.4))
	var ceil_now: float = float(_ceil_hist[-1])
	draw_string(_font, Vector2(rect.position.x + 6, rect.end.y - 5),
		("a_max_aero %.0f  (= C_L PEAK / m — illustrative, see HUD)" if _has_post_stall
			else "a_max_aero %.0f  (illustrative: flag keys off ⟂v projection)") % ceil_now,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.9, 1.0, 0.75))
	if _breach:
		# The label NAMES which flag lit, so the panel can never be read as claiming the other one.
		# "POST-STALL" = |α| past the lift peak (slice 22); "AERO SAT" = the α_max clamp bound (19–21).
		draw_string(_font, Vector2(rect.end.x - 92, rect.position.y + 13),
			"POST-STALL" if _has_post_stall else "AERO SAT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.4, 0.32, 0.95))

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
