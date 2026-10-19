// Acrylic slab gloss (style v4, PrintCard): the light on a clear grading case laid over a print.
// Two soft diagonal reflections that slide as the phone tilts (ui_tilt), a bright rim along the top
// and left edges and a darker one along the bottom and right, all inside a rounded rectangle.
// Colours are sRGB numbers converted for the linear HDR canvas at the end (ui_linear); the alpha is
// corrected so a translucent white looks the same on both canvases. Nothing relies on bloom.
shader_type canvas_item;
render_mode unshaded;

global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform vec2 size = vec2(200.0, 300.0);
uniform float radius = 10.0;
uniform float strength = 1.0;

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
	float inside = 1.0 - smoothstep(-0.8, 0.6, d);
	if (inside <= 0.002) {
		discard;
	}
	vec2 q = UV;
	float diag = q.x * 0.75 + q.y * 0.45 + ui_tilt.x * 0.9 + ui_tilt.y * 0.5;
	float band1 = exp(-sq((diag - 0.42) * 9.0)) * 0.22;
	float band2 = exp(-sq((diag - 0.62) * 22.0)) * 0.12;
	// Rims: lit from the top left.
	float edge = smoothstep(-5.0, -0.8, d);
	vec2 n = (p - size * 0.5) / max(length(p - size * 0.5), 0.001);
	float lit = clamp(0.5 - 0.5 * dot(n, normalize(vec2(1.0, 1.4))), 0.0, 1.0);
	float rim_hi = edge * lit * 0.75;
	float rim_lo = edge * (1.0 - lit) * 0.28;
	float a = clamp((band1 + band2) * strength + rim_hi, 0.0, 1.0) * inside;
	vec3 c = vec3(1.0);
	// The dark rim as its own premultiplied darkening.
	float dk = rim_lo * inside;
	vec4 col = vec4(mix(c, vec3(0.0), dk / max(a + dk, 0.001)), clamp(a + dk, 0.0, 1.0));
	vec3 cl = clamp(col.rgb, 0.0, 1.0);
	float ca = clamp(col.a, 0.0, 1.0);
	vec3 rgb = mix(cl, pow(cl, vec3(2.2)), ui_linear);
	float al = mix(ca, 1.0 - pow(1.0 - ca, 2.2), ui_linear * step(0.5, dk / max(a + dk, 0.001)));
	COLOR = vec4(rgb, al);
}
