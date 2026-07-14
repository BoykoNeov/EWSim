shader_type canvas_item;
// EWSim shared backdrop (fx/) — the instrument "sky" every view sits on: a vertical
// deep-navy gradient, a subtle twinkling starfield that thins toward the horizon, a
// faint atmospheric haze band, and a soft vignette. PURE CHROME (display only, no
// data): it rides a full-rect ColorRect on CanvasLayer -2, BEHIND every view's canvas,
// so any future view inherits the look for free. Colors default to the Sandbox.gd
// palette (COL_BG_TOP/COL_BG_BOT) and are uniforms so a view can retint if it ever
// needs to.

uniform vec4 col_top : source_color = vec4(0.035, 0.05, 0.085, 1.0);
uniform vec4 col_bot : source_color = vec4(0.075, 0.10, 0.14, 1.0);
uniform float star_density : hint_range(0.0, 1.0) = 0.16; // fraction of grid cells holding a star
uniform float star_cell_px = 30.0;                        // px per star-grid cell (layer 1)
uniform float twinkle_speed = 0.55;
uniform float vignette : hint_range(0.0, 1.0) = 0.30;
uniform float haze : hint_range(0.0, 1.0) = 0.35;         // horizon haze band strength

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = UV * res;
	// vertical gradient (zenith -> horizon)
	vec3 col = mix(col_top.rgb, col_bot.rgb, smoothstep(0.0, 1.0, UV.y));
	// faint haze lift near the bottom — reads as atmosphere, not data
	col += col_bot.rgb * (haze * 0.4) * smoothstep(0.5, 1.0, UV.y);
	// starfield: two hashed grid layers; stars fade out toward the ground strip so
	// they never compete with plot panels / ground-plane markers
	for (int L = 0; L < 2; L++) {
		float cell = star_cell_px * (L == 0 ? 1.0 : 1.9);
		vec2 g = px / cell;
		vec2 id = floor(g) + float(L) * 137.0;
		float h = hash21(id);
		if (h < star_density) {
			vec2 sp = 0.15 + 0.7 * vec2(hash21(id + 7.3), hash21(id + 3.1)); // pos in cell
			float d = length((fract(g) - sp) * cell);
			float tw = 0.72 + 0.28 * sin(TIME * twinkle_speed * (1.5 + 4.0 * h) + h * 40.0);
			float b = (0.30 + 0.70 * hash21(id + 1.7)) * tw;
			b *= 1.0 - smoothstep(0.30, 0.80, UV.y);
			col += vec3(0.75, 0.85, 1.0) * b * exp(-d * d * 1.3) * 0.55;
		}
	}
	// vignette (kept gentle — the corners hold labels)
	vec2 q = UV - 0.5;
	col *= 1.0 - vignette * dot(q, q) * 2.0;
	COLOR = vec4(col, 1.0);
}
