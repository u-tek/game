// Thick frosted glass block (style v4 "Signal"): what is behind it is blurred (a 32-tap disc), bent
// at the rounded edges like a real slab (refraction along the edge normal, stronger near the rim),
// split into colour at the rim (dispersion), tinted, frosted with fine grain, rimmed with a fresnel
// highlight and crossed now and then by a slow light sweep. Casts a soft shadow. Drawn on a
// ColorRect larger than the slab by `margin` (GlassBlock, src/ui/components/plate.gd).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float margin = 24.0;
uniform float radius = 14.0;
// Bevel (px) over which the slab curves, and how far the edge bends the image (px).
uniform float bevel = 22.0;
uniform float refract_px = 26.0;
uniform float blur_px = 14.0;
uniform float dispersion = 0.35;
uniform vec4 tint = vec4(0.82, 0.86, 0.9, 1.0);
uniform float tint_amount = 0.16;
uniform float brightness = 1.06;
uniform float frost = 0.035;
uniform float sweep = 1.0;
uniform float shadow_a = 0.45;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

vec3 blur_at(vec2 uv, vec2 px, float rad) {
	vec3 acc = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 32; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / 32.0) * rad;
		float th = fi * 2.3999632;
		vec2 o = vec2(cos(th), sin(th)) * r;
		float w = 1.0 - r / (rad + 1.0) * 0.6;
		acc += pow(max(texture(screen_tex, uv + o * px).rgb, vec3(0.0)), vec3(1.0 / 2.2)) * w;
		wsum += w;
	}
	return acc / wsum;
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 c = rect_size * 0.5;
	vec2 half_size = rect_size * 0.5 - vec2(margin);
	float d = sd_round_box(p - c, half_size, radius);
	vec2 px = SCREEN_PIXEL_SIZE;

	// Outside: soft shadow below.
	float sd = sd_round_box(p - c - vec2(2.0, 10.0), half_size, radius);
	vec4 outside = vec4(0.0, 0.0, 0.0, shadow_a * (1.0 - smoothstep(-6.0, margin * 0.9, sd)));

	float t = -d;
	float e = 0.75;
	vec2 grad = vec2(sd_round_box(p - c + vec2(e, 0.0), half_size, radius) - sd_round_box(p - c - vec2(e, 0.0), half_size, radius),
		sd_round_box(p - c + vec2(0.0, e), half_size, radius) - sd_round_box(p - c - vec2(0.0, e), half_size, radius));
	grad = grad / max(length(grad), 0.0001);
	float k = clamp(1.0 - t / bevel, 0.0, 1.0);
	float bend = k * k;
	// Edge bend (toward the inside, like looking through a lens rim) plus a slight magnification.
	vec2 off = -grad * bend * refract_px - (p - c) * 0.025;
	vec2 uv = SCREEN_UV + off * px;
	float rad = blur_px * (1.0 + bend * 0.6);
	vec3 col;
	if (dispersion > 0.0 && bend > 0.02) {
		vec2 dsp = grad * bend * refract_px * dispersion * px;
		col.r = blur_at(uv - dsp, px, rad).r;
		col.g = blur_at(uv, px, rad).g;
		col.b = blur_at(uv + dsp, px, rad).b;
	} else {
		col = blur_at(uv, px, rad);
	}
	// Milky frost: lift toward the tint (keeps a hint of what is behind), then the tint's hue.
	col = mix(col, tint.rgb * (0.55 + 0.45 * dot(col, vec3(0.33))), tint_amount) * brightness;
	col += (hash(floor(p)) - 0.5) * frost;
	// Fresnel rim: bright on the edges facing the light, a thin inner line all round.
	vec3 l = normalize(vec3(-0.45, -0.62, 0.64));
	float facing = clamp(dot(grad, -l.xy) * 1.2, 0.0, 1.0);
	col += vec3(1.0) * smoothstep(2.2, 0.0, t) * (0.25 + 0.45 * facing);
	col += vec3(1.0) * smoothstep(1.2, 0.0, abs(t - 5.0)) * 0.06;
	col += vec3(1.0) * bend * facing * 0.12;
	col *= 1.0 - bend * (1.0 - facing) * 0.22;
	// Light sweep: a soft diagonal band crossing every few seconds.
	if (sweep > 0.0) {
		float period = 7.0;
		float ph = fract(TIME / period);
		float pos = mix(-0.6, 1.6, ph) * (rect_size.x + rect_size.y);
		float band = (p.x + p.y * 0.55) - pos;
		col += vec3(1.0) * exp(-band * band / 1800.0) * 0.1 * sweep;
	}
	float a = clamp(0.5 - d, 0.0, 1.0);
	vec4 res = mix(outside, vec4(col, 1.0), a);
	// Back to the linear HDR canvas (the screen samples were taken to sRGB terms in blur_at).
	COLOR = vec4(pow(max(res.rgb, vec3(0.0)), vec3(2.2)), 1.0 - pow(1.0 - res.a, 2.2));
}
