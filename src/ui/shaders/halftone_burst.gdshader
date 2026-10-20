// Radial halftone burst (the Epic press in the summon reveal; src/ui/summon/summon_reveal.gd): a ring
// of halftone dots racing out from `center`, big dots at its front, the screen thinning behind it,
// in `ink`. `k` (0..1) is the burst's progress, set from the reveal's clock (a held frame holds it).
// The dot grid is in screen pixels, like every halftone in the poster look. Colours are sRGB numbers,
// converted to the canvas at the end (global ui_linear).
shader_type canvas_item;
render_mode unshaded;

global uniform float ui_linear;

uniform vec2 rect_size = vec2(684.0, 1100.0);
uniform vec2 center = vec2(400.0, 500.0);
uniform float k = 0.0;
uniform float reach = 900.0;
uniform float cell = 12.0;
uniform float angle = 0.35;
uniform vec4 ink = vec4(0.42, 0.30, 0.94, 1.0);
// A second ink for the trailing ring (the second plate, out of register), alpha 0 = none.
uniform vec4 ink2 = vec4(0.07, 0.71, 0.77, 0.0);
uniform vec2 offset2 = vec2(10.0, -6.0);

float dots(vec2 sp, float v, float ang, float c) {
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 g = rot * sp / c;
	vec2 cc = floor(g) + 0.5;
	float r = sqrt(clamp(v, 0.0, 1.0)) * 0.72;
	float dist = length(g - cc);
	float aa = max(fwidth(dist), 0.001);
	return 1.0 - smoothstep(r - aa, r + aa, dist);
}

float field(vec2 p) {
	float e = 1.0 - pow(1.0 - clamp(k, 0.0, 1.0), 3.0);
	float front = 40.0 + e * reach;
	float r = length(p - center);
	float w = 34.0 + 90.0 * e;
	float ring = exp(-pow((r - front) / w, 2.0));
	float behind = (1.0 - smoothstep(0.0, front, r)) * 0.14;
	return (ring + behind * (1.0 - e)) * (1.0 - k * k);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 sp = FRAGCOORD.xy;
	float c1 = dots(sp, field(p), angle, cell);
	float c2 = ink2.a > 0.0 ? dots(sp + offset2, field(p + offset2) * 0.9, angle + 0.52, cell) * ink2.a : 0.0;
	vec3 col = ink.rgb;
	float a = c1 * ink.a;
	// The second plate under the first.
	col = mix(ink2.rgb, col, a / max(a + c2 * (1.0 - a), 0.0001));
	a = a + c2 * (1.0 - a);
	vec3 cc = clamp(col, 0.0, 1.0);
	COLOR = vec4(mix(cc, pow(cc, vec3(2.2)), ui_linear), a);
}
