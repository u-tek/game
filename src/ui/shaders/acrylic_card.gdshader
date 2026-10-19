// Tinted acrylic card (style v4, the Rival's record card; after the owner's reference: an orange
// translucent acrylic plate printed with a dot grid, a round cut-out): a rounded slab of signal
// acrylic over whatever lies under it, a printed grid of dots, a round hole with a lit inner edge,
// a bright rim on the lit edges and a frosted streak that slides with the phone's tilt (ui_tilt).
// Colours are sRGB numbers converted for the linear HDR canvas (ui_linear), alpha corrected so the
// tint reads the same on both canvases; nothing here relies on bloom.
shader_type canvas_item;
render_mode unshaded;

global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform vec2 size = vec2(330.0, 200.0);
uniform vec4 tint = vec4(1.0, 0.36, 0.1, 0.8);
uniform float radius = 14.0;
// The cut-out: centre in pixels, radius in pixels (0 = none).
uniform vec2 hole = vec2(70.0, 70.0);
uniform float hole_r = 34.0;
uniform float pitch = 9.0;
uniform float dot_r = 2.0;
// Where the dot grid stops (pixels from the left): the text side stays clear.
uniform float grid_from = 0.0;
uniform float grid_to = 10000.0;

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sq(float x) {
	return x * x;
}

void fragment() {
	vec2 p = UV * size;
	float d = rbox(p - size * 0.5, size * 0.5, radius);
	float inside = 1.0 - smoothstep(-0.7, 0.7, d);
	if (inside <= 0.002) {
		discard;
	}
	float hd = hole_r > 0.0 ? length(p - hole) - hole_r : 1000.0;
	float in_hole = 1.0 - smoothstep(-0.7, 0.7, hd);
	vec3 c = tint.rgb;
	float a = tint.a;
	// Thicker toward the bottom: a touch deeper colour.
	c = mix(c, c * vec3(0.86, 0.7, 0.62), UV.y * 0.35);
	// The printed dot grid (darker ink on the acrylic).
	vec2 g = p / pitch;
	vec2 cc = (floor(g) + 0.5) * pitch;
	float dd = length(p - cc);
	float dots = (1.0 - smoothstep(dot_r - 0.6, dot_r + 0.6, dd)) * step(grid_from, p.x) * step(p.x, grid_to);
	c = mix(c, c * vec3(0.55, 0.32, 0.22), dots * 0.85);
	a = mix(a, min(1.0, a + 0.15), dots);
	// Rims: lit top-left edge, a darker bottom-right, the hole's inner wall lit on its far side.
	float edge = smoothstep(-4.0, -0.5, d);
	vec2 n = (p - size * 0.5) / max(length(p - size * 0.5), 0.001);
	float lit = clamp(0.5 - 0.5 * dot(n, normalize(vec2(1.0, 1.2))), 0.0, 1.0);
	c = mix(c, vec3(1.0, 0.92, 0.85), edge * lit * 0.8);
	c = mix(c, c * 0.6, edge * (1.0 - lit) * 0.6);
	float hedge = (1.0 - smoothstep(0.0, 3.5, abs(hd))) * (1.0 - in_hole * 0.0);
	vec2 hn = (p - hole) / max(length(p - hole), 0.001);
	float hlit = clamp(0.5 + 0.5 * dot(hn, normalize(vec2(1.0, 1.2))), 0.0, 1.0);
	c = mix(c, vec3(1.0, 0.9, 0.8), hedge * hlit * 0.9);
	// A frosted streak that slides with the tilt.
	float diag = UV.x * 0.8 + UV.y * 0.5 + ui_tilt.x * 0.9 + ui_tilt.y * 0.4;
	float streak = exp(-sq((diag - 0.45) * 10.0)) * 0.22;
	c = mix(c, vec3(1.0), streak);
	a = max(a, streak + edge * 0.5);
	a *= inside * (1.0 - in_hole) + hedge * inside * 0.9;
	a = clamp(a, 0.0, 1.0);
	c = clamp(c, 0.0, 1.0);
	COLOR = vec4(mix(c, pow(c, vec3(2.2)), ui_linear), mix(a, 1.0 - pow(1.0 - a, 2.2), ui_linear * 0.6));
}
