shader_type canvas_item;
// Halloween night by candlelight (main.gd _update_lamp): a multiply over everything, as if the phone
// were lit by a jack-o'-lantern just below the screen. Warm and bright low down, falling to a
// deeper amber toward the top corners; the light breathes and gutters like a flame (layered slow
// noise), and its hot spot sways a little with the phone's tilt. flicker 0 holds it still
// (Reduce motion). Colours are multipliers on the linear canvas.
render_mode blend_mul, unshaded;

global uniform vec2 ui_tilt;
uniform float flicker = 1.0;
uniform float strength = 1.0;

float n1(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = fract(sin(i * 127.1) * 43758.55);
	float b = fract(sin((i + 1.0) * 127.1) * 43758.55);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float t = TIME;
	// A flame: a slow breath, a quicker waver, and now and then a gutter.
	float fl = 0.55 * n1(t * 1.3) + 0.3 * n1(t * 4.7 + 3.1) + 0.15 * n1(t * 11.0 + 7.7);
	fl = mix(0.5, fl, flicker);
	vec2 src = vec2(0.5 - ui_tilt.x * 0.18 + (n1(t * 0.9) - 0.5) * 0.04 * flicker, 1.12);
	vec2 d = (UV - src) * vec2(1.0, 0.62);
	float r = length(d);
	float glow = smoothstep(1.05, 0.15, r);
	// (Tuned on the iPhone's path, HDR off: the multiply is in sRGB there and reads stronger.)
	vec3 warm = vec3(1.0, 0.92, 0.8);
	vec3 deep = vec3(0.8, 0.66, 0.54);
	vec3 c = mix(deep, warm, glow);
	c *= 0.95 + 0.08 * (fl - 0.5) + 0.05 * glow * (fl - 0.5);
	c = mix(vec3(1.0), c, strength);
	COLOR = vec4(min(c, vec3(1.0)), 1.0);
}
