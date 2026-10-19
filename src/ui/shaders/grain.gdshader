// Film grain over the whole UI (style v4 "Signal": "clean, grit on big moments").
// A full-rect ColorRect on a top CanvasLayer (UI.set_grain); `amount` is the grain strength,
// raised for summons, loading screens and transitions. Animated unless `still` (Reduce motion).
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform float amount = 0.035;
uniform bool still = false;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float t = still ? 0.0 : floor(TIME * 24.0);
	float n = hash(floor(FRAGCOORD.xy) + vec2(t * 37.0, t * 11.0));
	// Multiplied in: each pixel brightens or darkens by a few percent, like film grain, the same
	// on dark and light areas (the canvas is linear HDR, so a factor above 1.0 is fine).
	COLOR = vec4(vec3(1.0 + (n - 0.5) * 4.0 * amount), 1.0);
}
