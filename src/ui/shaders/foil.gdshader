// Foil (the rarity language, style v4 poster look; src/ui/v4/rarity_kit.gd): metallic foil stamped
// on the print, the way a press lays gold or violet foil. Its light leans with the phone (global
// ui_tilt): a soft glint band slides across as the device tilts (and drifts slowly by itself), the
// foil's crinkle catches it unevenly, and a few cells sparkle as the angle passes them.
//   mode 0  sheet   the whole rect is foil (a Legendary poster's foil flood, the press's gold flood)
//   mode 1  sheen   a light sheen over a print (hero cards): mostly clear, a slow glint band, the
//                   foil's sparkles, and a solid foil frame `edge` px wide
//   mode 2  die     foil inside the texture's alpha, relief from the art's tones (her figure as a
//                   gold foil die on the Legendary press plate)
//   mode 3  sweep   a band of light inside the texture's alpha at `sweep` (0..1 across), a light sweep
//                   over her art
// Colours are sRGB numbers; the maths is done in sRGB and converted to the canvas at the end (global
// ui_linear). Nothing goes above paper white and nothing relies on bloom (HDR 2D is off on iOS).
shader_type canvas_item;
render_mode unshaded;

global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform int mode = 0;
// The foil's mid tone, its highlight and its shadow (sRGB numbers).
uniform vec4 base = vec4(0.80, 0.62, 0.24, 1.0);
uniform vec4 hi = vec4(1.0, 0.94, 0.74, 1.0);
uniform vec4 lo = vec4(0.38, 0.25, 0.07, 1.0);
// Overall opacity (fades the whole effect).
uniform float amount = 1.0;
uniform float glint = 1.0;
uniform float sparkle = 1.0;
// A rainbow tint in the glint (holo foil).
uniform float rainbow = 0.0;
// 0 under Reduce motion: the light still follows the tilt but no longer drifts by itself.
uniform float motion = 1.0;
// Drift speed of the glint band (cycles per second, about). travel: the band runs across the rect
// and comes round again (a sheen sweep) instead of swaying about the middle.
uniform float speed = 0.12;
uniform bool travel = false;
// The rect's size in px (for the frame and the sparkle grid).
uniform vec2 rect_size = vec2(200.0, 300.0);
// Sheen: opacity of the clear part's sheen, and the solid frame's width in px (0 = none).
uniform float sheen = 0.35;
uniform float edge = 0.0;
// Sweep: a one-off band of light at this position across the rect (0..1; outside = off) and its
// width (mode 3, and over a sheen in mode 1: a card's entrance).
uniform float sweep = -1.0;
uniform float sweep_w = 0.12;
// Phase so neighbouring cards don't glint in step.
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.31) * 43758.5453);
}

float sq(float x) {
	return x * x;
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 to_srgb(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
}

vec4 to_canvas(vec3 c, float a) {
	c = clamp(c, 0.0, 1.0);
	a = clamp(a, 0.0, 1.0);
	return vec4(mix(c, pow(c, vec3(2.2)), ui_linear), mix(a, 1.0 - pow(1.0 - a, 2.2), ui_linear * 0.6));
}

// The foil at pixel p (px in the rect) with uv (0..1): tone 0..1 (relief), returns the lit colour and
// the glint strength in w.
vec4 foil(vec2 p, vec2 uv, float tone) {
	float tm = TIME * motion;
	// Crinkle: the foil is never perfectly flat. Soft facets from a warped wave field (no grid), so
	// each patch catches the light at its own angle.
	vec2 q = p / 85.0 + vec2(seed * 3.1, seed * 1.7);
	float w1 = sin(q.x * 1.7 + sin(q.y * 1.3 + 1.7) * 1.6);
	float w2 = sin(q.y * 2.1 + sin(q.x * 1.1 + 0.4) * 1.9 + 2.0);
	float w3 = sin((q.x + q.y) * 3.4 + sin(q.x * 2.7 - q.y * 1.9) * 1.2);
	float cr = clamp(0.5 + 0.24 * w1 + 0.18 * w2 + 0.1 * w3, 0.0, 1.0);
	// Brushed: faint hairlines along the press direction, and a pixel grain.
	float br = sin(p.y * 1.7 + sin(p.x * 0.011 + p.y * 0.02) * 9.0) * 0.5;
	float fine = hash(floor(p / 2.0)) - 0.5;
	// The light's position across the sheet follows the tilt and drifts; facets shift it.
	float pos = uv.x * 0.78 + uv.y * 0.52 + (cr - 0.5) * 0.5 + tone * 0.22;
	float drift = travel ? fract(tm * speed + seed * 0.37) * 2.8 - 0.9 : 0.62 + sin(tm * speed * 6.2832 + seed) * 0.42;
	float lp = drift + ui_tilt.x * 1.5 + ui_tilt.y * 0.9;
	float band = exp(-sq((pos - lp) * 4.2));
	float band2 = exp(-sq((pos - lp + 0.6) * 6.5)) * 0.5;
	float shade = clamp(0.18 + 0.78 * cr + 0.05 * br + 0.45 * (tone - 0.5), 0.0, 1.0);
	vec3 col = mix(lo.rgb, base.rgb, smoothstep(0.0, 0.55, shade));
	col = mix(col, hi.rgb, smoothstep(0.62, 1.0, shade) * 0.55);
	col *= 1.0 + fine * 0.07;
	float g = clamp((band + band2) * glint, 0.0, 1.0);
	vec3 gl = hi.rgb;
	if (rainbow > 0.0) {
		gl = mix(gl, hsv2rgb(vec3(fract(pos * 1.3 - lp + tm * 0.03), 0.45, 1.0)), rainbow);
	}
	col = mix(col, gl, g * 0.8);
	return vec4(col, g);
}

// Sparkles: a few grid cells flash as the angle passes them.
float sparkles(vec2 p, float cell) {
	vec2 cp = floor(p / cell);
	float h = hash(cp);
	vec2 f = fract(p / cell) - 0.5;
	float star = max(0.0, 1.0 - (abs(f.x) * abs(f.y)) * 240.0 - length(f) * 2.4);
	float tw = pow(max(0.0, sin(h * 40.0 + TIME * motion * 2.0 + (ui_tilt.x - ui_tilt.y) * 9.0)), 24.0);
	return star * tw * step(0.74, h);
}

// The vertex colour (modulate): fragment's COLOR already has the texture multiplied in.
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * rect_size;
	if (mode == 0) {
		vec4 f = foil(p, uv, 0.5);
		vec3 col = mix(f.rgb, vec3(1.0, 0.99, 0.95), clamp(sparkles(p, 16.0) * sparkle, 0.0, 1.0));
		COLOR = to_canvas(col, amount * vcol.a);
	} else if (mode == 1) {
		// The frame: solid foil `edge` px wide; inside, a translucent sheen and sparkles.
		float d = min(min(p.x, p.y), min(rect_size.x - p.x, rect_size.y - p.y));
		float frame = edge > 0.0 ? 1.0 - smoothstep(edge - 0.75, edge + 0.75, d) : 0.0;
		// Only the frame needs the lit foil (cheap on the clear inside, where most pixels are).
		vec4 f = frame > 0.0 ? foil(p, uv, 0.5) : vec4(0.0);
		float sp = clamp(sparkles(p, 12.0) * sparkle, 0.0, 1.0);
		// Over the print: a narrow glint running across (not a haze: her art stays vivid), with a
		// thin second reflection, both following the tilt.
		float tm = TIME * motion;
		float pos = uv.x * 0.8 + uv.y * 0.45;
		float drift = travel ? fract(tm * speed + seed * 0.37) * 2.8 - 0.9 : 0.62 + sin(tm * speed * 6.2832 + seed) * 0.42;
		float lp = drift + ui_tilt.x * 1.5 + ui_tilt.y * 0.9;
		float gb = exp(-sq((pos - lp) * 13.0)) + exp(-sq((pos - lp + 0.14) * 28.0)) * 0.6;
		vec3 gc = hi.rgb;
		if (rainbow > 0.0) {
			gc = mix(gc, hsv2rgb(vec3(fract(pos * 2.0 - lp + uv.y * 0.6), 0.5, 1.0)), rainbow);
		}
		float sw = 0.0;
		if (sweep >= 0.0 && sweep <= 1.0) {
			sw = exp(-sq((pos - (sweep * 1.9 - 0.3)) / max(sweep_w, 0.01)));
		}
		float a = max(frame, clamp(gb, 0.0, 1.0) * sheen + sp * 0.9 + sw * 0.7);
		// The frame's foil a touch brighter than a sheet's (it is thin), with a dark inner hairline.
		vec3 fr = mix(f.rgb, hi.rgb, 0.18) * (1.0 - 0.45 * smoothstep(edge - 1.6, edge - 0.2, d));
		vec3 col = mix(gc, fr, frame);
		col = mix(col, hi.rgb, sw * (1.0 - frame));
		col = mix(col, vec3(1.0, 0.99, 0.96), sp * (1.0 - frame));
		COLOR = to_canvas(col, a * amount * vcol.a);
	} else if (mode == 2) {
		vec4 t = texture(TEXTURE, uv);
		vec3 s = to_srgb(t.rgb);
		float tone = dot(s, vec3(0.299, 0.587, 0.114));
		// Relief: the art's tones lift and sink the foil; its edges catch a rim of light.
		vec4 f = foil(p, uv, tone);
		COLOR = to_canvas(f.rgb, t.a * amount * vcol.a);
	} else {
		vec4 t = texture(TEXTURE, uv);
		float pos = uv.x * 0.8 + uv.y * 0.45;
		float b = exp(-sq((pos - (sweep * 1.9 - 0.3)) / max(sweep_w, 0.01)));
		b += exp(-sq((pos - (sweep * 1.9 - 0.3) + sweep_w * 2.2) / max(sweep_w * 0.35, 0.005))) * 0.5;
		COLOR = to_canvas(hi.rgb, t.a * clamp(b, 0.0, 1.0) * amount * vcol.a);
	}
}
