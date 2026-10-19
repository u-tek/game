// Misprint (style v4 "Signal"; data/prints.json): a hero's art printed onto paper the way the press
// printed it, flaw and all. Draws the whole print window (paper included) so the plates multiply
// like ink on stock:
//   flaw 0 clean   the art in full colour on the paper
//   flaw 1 shift   off register: the signal plate (a red halftone copy) landed beside the ink
//   flaw 2 swap    wrong ink: the red plate printed in `ink` (cyan, violet, acid green, gold)
//   flaw 3 ghost   missing plate: no colour at all, the key plate's ink-only halftone
//   flaw 4 double  double hit: the key plate struck twice, a hair apart
//   flaw 5 flood   ink flood: the shadows crushed, pooled and spread
// holo > 0 lays a holographic foil over it: a rainbow sheen and sparkles that move with the phone's
// tilt (the ui_tilt global) and time. `amount` (0..1) fades the flaw in (the reveal's flip).
// Maths in sRGB numbers: samples are taken back to sRGB when the canvas is linear (ui_linear = 1)
// and every colour written is converted at the end, so an unflawed print is exactly the art.
// Nothing relies on bloom (the iPhone build has no HDR 2D).
shader_type canvas_item;
render_mode unshaded;

// 1 when the canvas is linear HDR (viewport hdr_2d), 0 when it is plain sRGB (main.gd sets it).
global uniform float ui_linear;
// The phone's tilt (high-passed gravity; a slow drift on desktop), main.gd sets it.
global uniform vec2 ui_tilt;

uniform int flaw = 0;
uniform float amount = 1.0;
// sRGB numbers (no source_color hint).
uniform vec4 ink = vec4(0.0, 0.66, 0.86, 1.0);
uniform vec4 paper = vec4(0.914, 0.91, 0.886, 1.0);
// Direction of the misregistration (from the print's v) and its size in screen pixels.
uniform vec2 dir = vec2(0.92, -0.38);
uniform float px = 9.0;
uniform float holo = 0.0;
// The atlas region the art comes from (normalized); samples never leave it.
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float cell = 5.0;
uniform float seed = 0.0;
// false: no paper of its own (the print laid over a poster): alpha is the inks' coverage.
uniform bool on_paper = true;
// 0 under Reduce motion: the foil still follows the tilt but no longer drifts by itself.
uniform float motion = 1.0;

const vec3 SIG = vec3(1.0, 0.294, 0.122);
const vec3 KEY = vec3(0.063, 0.067, 0.075);

vec3 to_srgb(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
}

vec3 to_canvas(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear);
}

// A sample of the art (clamped to its region), back in sRGB numbers, with no ink outside the region
// (a shifted plate reaching past the art's edge). A macro: TEXTURE can't be passed to a function.
vec4 art_fix(vec4 c, vec2 uv) {
	vec2 lo = region.xy;
	vec2 hi = region.xy + region.zw;
	float inside = step(lo.x, uv.x) * step(uv.x, hi.x) * step(lo.y, uv.y) * step(uv.y, hi.y);
	c.a *= inside;
	c.rgb = to_srgb(c.rgb);
	return c;
}

#define ART(uv) art_fix(texture(TEXTURE, clamp((uv), region.xy, region.xy + region.zw)), (uv))

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Coverage of a halftone dot of value v (0..1) on a grid at `ang`, in screen pixels.
float dots(vec2 sp, float v, float ang, float c) {
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 g = rot * sp / c;
	vec2 cc = floor(g) + 0.5;
	float r = sqrt(clamp(v, 0.0, 1.0)) * 0.7;
	float dist = length(g - cc);
	float aa = max(fwidth(dist), 0.001);
	return 1.0 - smoothstep(r - aa, r + aa, dist);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
}

float sq(float x) {
	return x * x;
}

void fragment() {
	vec2 sp = FRAGCOORD.xy;
	// One screen pixel in UV, for offsets that stay the same size however the print is scaled.
	vec2 du = vec2(length(dFdx(UV)), length(dFdy(UV)));
	vec2 d = normalize(dir) * px * du;
	vec4 c = ART(UV);
	vec3 base = mix(paper.rgb, c.rgb, c.a);
	vec3 col = base;
	float k = clamp(amount, 0.0, 1.0);
	// Ink coverage outside the art's own alpha (a plate that landed beside her).
	float ink_a = 0.0;
	if (flaw == 1) {
		// The signal plate: a red halftone of the art's darks, printed beside the ink.
		vec4 g = ART(UV - d);
		float v = (1.0 - lum(g.rgb)) * 1.15 - 0.04;
		float cov = dots(sp, v * g.a, 0.2618, cell) * k;
		col = base * mix(vec3(1.0), SIG, cov * 0.9);
		ink_a = cov * 0.9;
	} else if (flaw == 2) {
		// The red plate in the wrong ink: reds take the ink's hue, and the plate's halftone of the
		// shadows overprints in that ink.
		vec3 h = rgb2hsv(c.rgb);
		float hd = min(h.x, 1.0 - h.x);
		float red = smoothstep(0.42, 0.72, h.y) * (1.0 - smoothstep(0.035, 0.1, hd)) * c.a;
		vec3 ih = rgb2hsv(ink.rgb);
		vec3 swapped = hsv2rgb(vec3(ih.x, max(h.y, 0.55), h.z));
		col = mix(base, swapped, red * k);
		// The colour plate, in register but in the wrong ink: a halftone of her mid tones and darks.
		float v = ((1.0 - lum(c.rgb)) * 1.15 - 0.02) * c.a;
		float cov = dots(sp, v, 0.2618, cell) * k;
		col *= mix(vec3(1.0), ink.rgb, cov * 0.85);
	} else if (flaw == 3) {
		// No colour plate: only the key plate's halftone of her.
		float v = (1.0 - lum(c.rgb)) * 1.25 * c.a;
		float cov = dots(sp, v, 0.7854, cell * 0.9);
		vec3 ghost = mix(paper.rgb, KEY, cov);
		col = mix(base, ghost, k);
	} else if (flaw == 4) {
		// The key plate twice: the darks printed again a hair off.
		vec4 g = ART(UV + d * 1.4);
		float dk = smoothstep(0.66, 0.2, lum(g.rgb)) * g.a;
		// The first strike a touch light (the plate lifted), the second one solid.
		col = mix(base, mix(base, paper.rgb, 0.18), k);
		col *= mix(vec3(1.0), KEY * 1.4 + 0.08, dk * 0.85 * k);
		ink_a = dk * 0.85 * k;
	} else if (flaw == 5) {
		// Too much ink: the shadows spread (the darkest neighbour wins) and crush to black.
		float m = lum(base);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7854 + seed;
			vec2 o = vec2(cos(a), sin(a)) * px * 1.25 * du;
			vec4 n = ART(UV + o);
			m = min(m, lum(mix(paper.rgb, n.rgb, n.a)));
		}
		float blot = hash(floor(sp / 3.0)) * 0.12;
		float pool = smoothstep(0.5 + blot, 0.16, m);
		vec3 crushed = pow(base, vec3(2.0)) * 0.88;
		col = mix(base, mix(crushed, KEY * 1.2, pool * 0.92), k);
		ink_a = pool * 0.92 * k;
	}
	if (holo > 0.0) {
		// The foil: a rainbow that slides as the phone tilts, a diagonal glint band and sparkles.
		vec2 q = UV - region.xy;
		q /= max(region.zw, vec2(0.0001));
		float tm = TIME * motion;
		float t = tm * 0.06;
		float hue = fract(q.x * 0.9 + q.y * 0.55 + ui_tilt.x * 1.6 - ui_tilt.y * 1.1 + t);
		vec3 rb = hsv2rgb(vec3(hue, 0.55, 1.0));
		float band = q.x * 0.8 - q.y * 0.6 + ui_tilt.x * 2.2 + ui_tilt.y * 1.4 + sin(tm * 0.7) * 0.25;
		float glint = exp(-sq((fract(band * 0.7) - 0.5) * 5.0));
		float fig = 0.55 + 0.45 * c.a;
		col = mix(col, col * 0.55 + rb * 0.62, holo * 0.42 * fig);
		col = mix(col, rb, glint * holo * 0.3);
		// Sparkles: a few cells light up as the angle passes them.
		vec2 cellp = floor(sp / 14.0);
		float h = hash(cellp);
		vec2 f = fract(sp / 14.0) - 0.5;
		float star = max(0.0, 1.0 - (abs(f.x) * abs(f.y)) * 260.0 - length(f) * 2.6);
		float tw = pow(max(0.0, sin(h * 40.0 + tm * 2.2 + (ui_tilt.x - ui_tilt.y) * 9.0)), 24.0);
		col = mix(col, vec3(1.0, 0.99, 0.97), clamp(star * tw * step(0.72, h) * holo, 0.0, 1.0));
	}
	// Never above paper white: nothing here may bloom on the HDR canvas.
	float alpha = on_paper ? 1.0 : clamp(max(c.a, ink_a), 0.0, 1.0);
	COLOR = vec4(to_canvas(clamp(col, 0.0, 1.0)), alpha);
}
