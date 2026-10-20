// Legend foil (style v4 "Signal", the Legendary hero page; LegendKit, src/ui/v4/legend_kit.gd): hot-
// stamped gold holo foil. A brushed gold whose reflection bands slide as the phone tilts (the ui_tilt
// global) and drift slowly with time, a faint rainbow in the highlights and sparkles that catch as
// the angle passes them.
//   mode 0  foil      paints whatever the item draws (a Label's glyphs, a shape) in foil, keeping its
//                     alpha (coverage): foil type, foil discs
//   mode 1  frame     a foil border inside the rect (`inset` from its edges, `frame_w` wide) and a
//                     hairline inside that: the certificate frame round a Legendary's poster
//   mode 2  sheen     only the glint: a holographic band and sparkles over what is below (a dark band)
// The pattern runs in the item's own pixels (VERTEX), so it follows the item when it turns.
// Colours are sRGB numbers, converted to the linear HDR canvas at the end (ui_linear); never above
// paper white: nothing relies on bloom (the iPhone build has no HDR 2D).
shader_type canvas_item;
render_mode unshaded;

// 1 when the canvas is linear HDR (viewport hdr_2d), 0 when it is plain sRGB (main.gd sets it).
global uniform float ui_linear;
// The phone's tilt (high-passed gravity; a slow drift on desktop), main.gd sets it.
global uniform vec2 ui_tilt;

uniform int mode = 0;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float inset = 10.0;
uniform float frame_w = 4.0;
uniform float strength = 1.0;
// 0 under Reduce motion: the foil still follows the tilt but no longer drifts by itself.
uniform float drift = 1.0;
// Pattern scale: bigger = broader reflection bands (pixels per band).
uniform float band_px = 260.0;
uniform vec4 dark = vec4(0.36, 0.22, 0.05, 1.0);
uniform vec4 mid = vec4(0.80, 0.58, 0.20, 1.0);
uniform vec4 light = vec4(1.0, 0.93, 0.66, 1.0);
uniform float holo = 0.32;
uniform float sparkle = 1.0;
uniform float seed = 0.0;
// Moves the reflection bands and the glint along (animated by a sweep).
uniform float shift = 0.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 rainbow(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

vec3 to_canvas(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear);
}

// A sparkle at p (px): a few cells light up as the angle passes them.
float sparkles(vec2 p, float t) {
	vec2 cellp = floor(p / 9.0);
	float h = hash(cellp + seed);
	vec2 f = fract(p / 9.0) - 0.5;
	float star = max(0.0, 1.0 - abs(f.x) * abs(f.y) * 200.0 - length(f) * 2.4);
	float tw = pow(max(0.0, sin(h * 40.0 + t * 2.4 + (ui_tilt.x - ui_tilt.y) * 9.0)), 22.0) * step(0.8, h);
	return clamp(star * tw * sparkle, 0.0, 1.0);
}

// The foil's colour at p (px) and its sparkle.
vec4 foil(vec2 p, float t) {
	vec2 q = p / band_px;
	// Brushed streaks across the stamp.
	float brush = vnoise(vec2(p.x * 0.012, p.y * 0.35) + seed) * 0.55 + vnoise(vec2(p.x * 0.04, p.y * 0.9) + seed * 1.7) * 0.25;
	float a = q.x * 0.82 - q.y * 0.57 + shift * 0.3;
	float r1 = 0.5 + 0.5 * sin(a * 6.2832 + ui_tilt.x * 2.6 - ui_tilt.y * 1.9 + t * 0.35 + brush * 0.9);
	float r2 = 0.5 + 0.5 * sin(a * 15.0 + 1.7 + ui_tilt.x * 4.2 + ui_tilt.y * 3.1 - t * 0.21);
	float v = clamp(r1 * 0.68 + r2 * 0.22 + brush * 0.18, 0.0, 1.0);
	vec3 g = v < 0.5 ? mix(dark.rgb, mid.rgb, v * 2.0) : mix(mid.rgb, light.rgb, (v - 0.5) * 2.0);
	// The holographic layer: a rainbow in the highlights that slides with the tilt.
	float hue = fract(q.x * 0.55 + q.y * 0.35 + ui_tilt.x * 0.9 - ui_tilt.y * 0.7 + t * 0.04);
	g = mix(g, g * 0.55 + rainbow(hue) * 0.55, holo * smoothstep(0.55, 1.0, v));
	return vec4(clamp(g, 0.0, 1.0), sparkles(p, t));
}

void fragment() {
	float t = TIME * drift;
	vec2 p = local;
	if (mode == 2) {
		// The glint alone: a narrow diagonal band and the sparkles, light gold with a rainbow edge
		// (no brushed foil underneath: cheap over a whole band).
		vec2 q = p / band_px;
		float b = q.x * 0.8 + q.y * 0.55 + ui_tilt.x * 1.6 + ui_tilt.y * 1.1 + t * 0.05 + shift;
		float d = fract(b * 0.45) - 0.5;
		// A narrow bright core in a soft shoulder.
		float glint = exp(-d * d * 3000.0) * 0.8 + exp(-d * d * 320.0) * 0.1;
		float hue = fract(b * 0.9 + 0.1);
		vec3 c = mix(light.rgb, rainbow(hue) * 0.6 + light.rgb * 0.5, holo);
		float sp = sparkles(p, t);
		float alpha = clamp(glint * 0.5 + sp * 0.9, 0.0, 1.0) * strength;
		COLOR = vec4(to_canvas(mix(c, vec3(1.0, 0.98, 0.9), sp)), alpha * COLOR.a);
	} else {
		float alpha = COLOR.a;
		if (mode == 1) {
			// Distance in from the nearest edge; the foil rule and a hairline inside it. Everything else
			// is clear (and skips the foil).
			float m = min(min(p.x, p.y), min(rect_size.x - p.x, rect_size.y - p.y));
			float rule = smoothstep(inset - 0.8, inset + 0.2, m) * (1.0 - smoothstep(inset + frame_w - 0.2, inset + frame_w + 0.8, m));
			float hair_at = inset + frame_w + 5.0;
			float hair = smoothstep(hair_at - 0.7, hair_at, m) * (1.0 - smoothstep(hair_at + 1.0, hair_at + 1.7, m));
			alpha = max(rule, hair * 0.85) * COLOR.a;
		}
		if (alpha <= 0.001) {
			COLOR = vec4(0.0);
		} else {
			vec4 fo = foil(p, t);
			vec3 g = mix(fo.rgb, vec3(1.0, 0.98, 0.92), fo.a);
			COLOR = vec4(to_canvas(g), alpha * strength);
		}
	}
}
