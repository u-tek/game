// A survey layer printed on vellum (style v4 "Signal", poster look; src/ui/v4/survey/survey_map.gd):
// a translucent paper sheet with an ink hairline frame, corner ticks and a coordinate edge, carrying
// one kind of line work: 0 a grid (the stage layer), 1 contours of the terrain (ink), 2 hydrography
// (a signal-red vein network around the rivers; the rivers themselves are ribbon meshes on top).
// Unshaded and blended; the camera sorts the sheets back to front.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform int mode = 0;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D river_tex : filter_linear, repeat_disable;
uniform sampler2D vein_tex : filter_linear, repeat_enable;
uniform vec4 paper : source_color = vec4(0.914, 0.910, 0.886, 1.0);
uniform vec4 ink : source_color = vec4(0.063, 0.067, 0.075, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.294, 0.122, 1.0);
uniform vec2 plane_size = vec2(12.0, 8.0);
// Paper opacity of the sheet and of its line work (the whole sheet fades with `fade`).
uniform float vellum = 0.42;
uniform float line_a = 0.85;
uniform float fade = 1.0;
uniform float levels = 12.0;
uniform float grid_step = 1.0;

float hair(float d, float fw, float px) {
	fw = max(fw, 1e-5);
	return 1.0 - smoothstep(px * 0.5 * fw - 0.5 * fw, px * 0.5 * fw + 0.5 * fw, abs(d));
}

void fragment() {
	vec2 w = UV * plane_size;
	vec3 col = paper.rgb;
	float a = vellum;
	// Frame: a hairline at the edge and a second one just inside.
	vec2 e2 = min(w, plane_size - w);
	float de = min(e2.x, e2.y);
	float fe = fwidth(de);
	float frame = max(hair(de, fe, 2.2), hair(de - 0.12, fe, 0.9) * 0.7);
	// Ticks along the front and left edges, every half unit (longer every 2).
	float tick = 0.0;
	if (e2.y < 0.22 || e2.x < 0.22) {
		float along = e2.y < 0.22 ? w.x : w.y;
		float across = e2.y < 0.22 ? e2.y : e2.x;
		float len = fract(along / 2.0 + 0.001) < 0.24 ? 0.22 : 0.12;
		tick = hair(fract(along * 2.0 + 0.5) - 0.5, fwidth(along * 2.0), 1.0) * step(across, len);
	}
	vec3 line = ink.rgb;
	float lw = 0.0;
	if (mode == 0) {
		// Fine survey grid, crosses at the intersections.
		vec2 gs = w / grid_step;
		vec2 gf = abs(fract(gs + 0.5) - 0.5);
		vec2 gw = fwidth(gs);
		float grid = max(hair(gf.x, gw.x, 0.7), hair(gf.y, gw.y, 0.7)) * 0.16;
		float cross = (hair(gf.x, gw.x, 1.0) * step(gf.y, 0.07) + hair(gf.y, gw.y, 1.0) * step(gf.x, 0.07)) * 0.55;
		lw = max(grid, cross);
	} else if (mode == 1) {
		float h = texture(height_tex, UV).r * levels;
		float fw = fwidth(h);
		float minor = hair(fract(h + 0.5) - 0.5, fw, 1.0) * 0.8;
		float major = hair(fract(h * 0.25 + 0.5) - 0.5, fw * 0.25, 1.7);
		lw = max(minor, major);
	} else {
		// Hydrography: a dendritic vein network (zero crossings of a noise field), dense near the
		// rivers and thinning out on the high ground.
		float n = texture(vein_tex, UV * vec2(plane_size.x / plane_size.y, 1.0) * 1.3).r;
		float fw = fwidth(n);
		float rd = texture(river_tex, UV).r;
		float near = 1.0 - smoothstep(0.15, 1.0, rd);
		float veins = hair(n - 0.5, fw, 1.3) * (0.45 + 0.55 * near);
		float n2 = texture(vein_tex, UV * 2.9 + vec2(0.37, 0.11)).r;
		float fine = hair(n2 - 0.5, fwidth(n2), 0.9) * near * 0.8;
		lw = max(veins, fine);
		line = accent.rgb;
	}
	col = mix(col, line, clamp(lw * line_a, 0.0, 1.0));
	a = max(a, clamp(lw * line_a, 0.0, 1.0));
	col = mix(col, ink.rgb, max(frame, tick));
	a = max(a, max(frame, tick));
	ALBEDO = col;
	ALPHA = a * fade;
}
