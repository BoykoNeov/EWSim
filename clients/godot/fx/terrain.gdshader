shader_type spatial;
render_mode cull_disabled, specular_disabled;
// EWSim terrain surface (fx/) — DISPLAY-ONLY dressing of the CORE's handshake height
// grid (meshed in Sandbox.gd with height-tinted vertex colors; this shader only
// shades that truth, it never moves a vertex or invents a height):
//   • base albedo = the client's height-ramp vertex color (unchanged data path)
//   • slope-based rock darkening (steep faces read as terrain, not plastic)
//   • antialiased elevation CONTOUR lines every `contour_spacing` display units,
//     with a stronger index line every 5th — Sandbox.gd sets the spacing so the
//     HUD can label the real-metre interval (vertical exaggeration included)
//   • a little two-octave value-noise grain so large flats aren't dead-flat color
// Any future 3-D ground view (land clutter is the named next consumer of this
// heightfield) reuses this material as-is.

uniform float contour_spacing = 1.25;  // 3-D display units between contour lines
uniform vec4 contour_color : source_color = vec4(0.85, 0.95, 1.0, 0.20);
uniform float slope_darken : hint_range(0.0, 1.0) = 0.55;
uniform float grain : hint_range(0.0, 0.5) = 0.10;

varying vec3 wpos;

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	// slope: compare the world-space normal against up; steep -> darker, desaturated
	vec3 wn = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	float slope = 1.0 - clamp(abs(wn.y), 0.0, 1.0);   // abs: cull_disabled backfaces too
	vec3 rock = mix(base, vec3(dot(base, vec3(0.333))), 0.5) * 0.62;
	base = mix(base, rock, smoothstep(0.15, 0.7, slope) * slope_darken);
	// grain: two octaves of value noise in world xz (breaks up dead-flat fills)
	float g = (vnoise(wpos.xz * 1.7) - 0.5) + (vnoise(wpos.xz * 7.3) - 0.5) * 0.5;
	base *= 1.0 + g * grain;
	// contour lines (fwidth-antialiased); every 5th is an index line, drawn stronger
	float h = wpos.y / max(contour_spacing, 1e-4);
	float d1 = abs(fract(h + 0.5) - 0.5) / max(fwidth(h), 1e-4);
	float minor = 1.0 - clamp(d1, 0.0, 1.0);
	float h5 = h / 5.0;
	float d5 = abs(fract(h5 + 0.5) - 0.5) / max(fwidth(h5), 1e-4);
	float major = 1.0 - clamp(d5, 0.0, 1.0);
	base = mix(base, contour_color.rgb, minor * contour_color.a);
	base = mix(base, contour_color.rgb, major * contour_color.a * 1.6);
	ALBEDO = base;
	ROUGHNESS = 1.0;
}
