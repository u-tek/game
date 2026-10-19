// Lit material plate (style v4 "Signal", docs/dev/ui-style-v4.md): a flat UI shape rendered like a
// machined part in a photo studio. The shape is a polygon (up to 16 points) or a circle, as a signed
// distance field. Its bevel and face reflect a procedural studio (a big softbox top left, a strip
// light on the right, a dark floor) seen from a view that follows the phone's tilt (global ui_tilt),
// so edges flash as the device moves. Materials: brushed silver, matte graphite / slate, emissive
// signal glass (HDR, so it blooms), a machined dial, dark glass. Optional engraved contour grooves,
// screws, a recessed (cut-in) variant, light spilled by glowing parts nearby, a contact shadow plus a
// soft shadow, and an animated glow. Drawn on a ColorRect larger than the shape by the margin
// (Plate, src/ui/components/plate.gd, sets every uniform).
shader_type canvas_item;

global uniform vec2 ui_tilt;

uniform vec2 rect_size = vec2(100.0, 100.0);
// Shape: 0 = polygon (pts, npts, px), 1 = circle (circle.xy centre, circle.z radius).
uniform int shape = 0;
uniform int npts = 4;
uniform vec2 pts[16];
uniform vec3 circle = vec3(50.0, 50.0, 40.0);
uniform float bevel = 5.0;
uniform float bevel_tilt = 1.4;
// Cut into the surface instead of raised (engraved panels, wells): inner shadow, no cast shadow.
uniform bool recess = false;
// Material: 0 brushed silver, 1 matte graphite, 2 matte slate, 3 emissive signal, 4 machined dial,
// 5 dark glass.
uniform int mat = 0;
// Colours are sRGB numbers (no source_color hint): all the maths here is done in sRGB terms and
// converted to the linear HDR canvas at the end (to_canvas).
uniform vec4 albedo = vec4(0.80, 0.82, 0.80, 1.0);
uniform vec4 albedo_low = vec4(0.62, 0.65, 0.63, 1.0);
uniform vec4 emit = vec4(1.0, 0.29, 0.1, 1.0);
uniform float emit_strength = 1.0;
uniform float pulse = 0.0;
uniform float pulse_period = 2.6;
uniform float glow_radius = 0.0;
uniform float glow_strength = 0.0;
uniform float shadow_r = 16.0;
uniform vec2 shadow_off = vec2(3.0, 9.0);
uniform float shadow_a = 0.6;
// Engraved contour grooves over the face (0 = none), seeded per plate.
uniform float topo = 0.0;
uniform float seed = 0.0;
uniform int nscrews = 0;
uniform vec3 screws[8];
uniform float press = 0.0;
// Light spilled by up to 4 glowing parts: rect (centre xy, half size zw; negative = round, radius)
// and colour (rgb, w = intensity).
uniform int nspill = 0;
uniform vec4 spill_rect[4];
uniform vec4 spill_col[4];

const vec3 KEY_LIGHT = vec3(-0.45, -0.62, 0.64);

// sRGB-authored colour to the linear HDR canvas (rendering/viewport/hdr_2d). Alpha is corrected
// too, so a translucent dark (a shadow) darkens as much as it would in sRGB blending.
vec4 to_canvas(vec4 c) {
	return vec4(pow(max(c.rgb, vec3(0.0)), vec3(2.2)), 1.0 - pow(1.0 - clamp(c.a, 0.0, 1.0), 2.2));
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float sd_poly(vec2 p) {
	float d = dot(p - pts[0], p - pts[0]);
	float s = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= npts) {
			break;
		}
		int j = i == 0 ? npts - 1 : i - 1;
		vec2 e = pts[j] - pts[i];
		vec2 w = p - pts[i];
		vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
		d = min(d, dot(b, b));
		bool c1 = p.y >= pts[i].y;
		bool c2 = p.y < pts[j].y;
		bool c3 = e.x * w.y > e.y * w.x;
		if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) {
			s *= -1.0;
		}
	}
	return s * sqrt(d);
}

float sdf(vec2 p) {
	if (shape == 1) {
		return length(p - circle.xy) - circle.z;
	}
	return sd_poly(p);
}

// The studio, as seen along reflection direction r (x right, y down, z toward the viewer).
// rough widens the lights (rougher metal = softer reflections).
vec3 studio(vec3 r, float rough) {
	float up = -r.y;
	vec3 c = mix(vec3(0.02, 0.021, 0.024), vec3(0.2, 0.205, 0.21), smoothstep(-0.7, 0.9, up));
	// Key softbox: big, just above and left of the view axis, so faces pointing at the viewer catch
	// its soft falloff (a product-shot gradient) and tilting slides its edge across them.
	vec2 kb = vec2(r.x + 0.16, r.y + 0.3);
	float kd = max(abs(kb.x) * 0.75, abs(kb.y) * 1.2);
	c += vec3(1.05, 1.04, 1.02) * smoothstep(0.62 + rough, 0.12 - rough * 0.3, kd);
	// Strip light, right.
	float sd = abs(r.x - 0.6);
	c += vec3(1.25) * smoothstep(0.07 + rough * 0.6, 0.0, sd) * smoothstep(0.95, 0.35, abs(r.y + 0.1));
	// A low fill bouncing off the floor, bottom left.
	c += vec3(0.22, 0.2, 0.19) * smoothstep(0.8, 0.0, length(vec2(r.x + 0.7, r.y - 0.75)));
	return c;
}

void fragment() {
	vec2 p = UV * rect_size;
	float d = sdf(p);
	float pul = 1.0 + pulse * (0.5 + 0.5 * sin(TIME * 6.2831853 / pulse_period)) - pulse * 0.5;
	vec2 q = p / rect_size;
	float win = smoothstep(0.0, 12.0, min(min(p.x, p.y), min(rect_size.x - p.x, rect_size.y - p.y)));

	// ---- outside: a tight contact shadow plus a wide soft one, and the glow
	vec4 outside = vec4(0.0);
	if (!recess) {
		float sd = sdf(p - shadow_off * 1.5 * (1.0 - press * 0.7));
		float sh = shadow_a * 0.75 * (1.0 - smoothstep(-shadow_r * 0.5, shadow_r * 1.8, sd)) * (1.0 - press * 0.35);
		float sc = sdf(p - vec2(0.5, 1.5));
		sh = max(sh, shadow_a * 0.9 * (1.0 - smoothstep(-1.0, 4.0, sc)));
		outside = vec4(0.0, 0.0, 0.0, sh * win);
	}
	if (glow_strength > 0.0 && d > 0.0) {
		// A tight edge glow only: the HDR bloom pass spreads the light (the edges run above 1.0).
		float g = glow_strength * pul * exp(-d / max(glow_radius * 0.5, 1.0)) * win;
		outside.rgb = mix(outside.rgb, emit.rgb, clamp(g / max(outside.a + g, 0.001), 0.0, 1.0));
		outside.a = clamp(outside.a + g, 0.0, 1.0);
	}

	// ---- inside: the surface normal (bevel, grooves), then the material
	float t = -d;
	vec2 grad;
	{
		float e = 0.75;
		grad = vec2(sdf(p + vec2(e, 0.0)) - sdf(p - vec2(e, 0.0)), sdf(p + vec2(0.0, e)) - sdf(p - vec2(0.0, e)));
		grad = grad / max(length(grad), 0.0001);
	}
	float k = clamp(1.0 - t / max(bevel, 0.5), 0.0, 1.0);
	float slope = bevel_tilt * k * k * 2.0;
	vec2 tiltn = grad * slope * (recess ? -1.0 : 1.0);
	float groove = 0.0;
	if (topo > 0.0) {
		// Engraved contour grooves: each groove's two walls tilt opposite ways (one lit, one dark).
		float f = fbm(p * 0.0045 + vec2(seed * 3.1, seed)) * 9.0;
		float fx = fract(f);
		float x = 0.5 - abs(fx - 0.5);
		float w = fwidth(f) * 1.6;
		groove = 1.0 - smoothstep(0.0, w, x);
		vec2 fg = vec2(dFdx(f), dFdy(f));
		fg = fg / max(length(fg), 0.0001);
		float side = fx < 0.5 ? 1.0 : -1.0;
		tiltn += fg * side * groove * 0.45 * topo;
	}
	vec3 n = normalize(vec3(tiltn, 1.0));
	vec3 l = normalize(KEY_LIGHT);
	float diff = max(dot(n, l), 0.0);
	// The view leans with the phone; across a big plate the reflection also drifts (perspective).
	vec3 v = normalize(vec3(-ui_tilt * 0.7 - (q - 0.5) * 0.45, 1.0));
	vec3 r = reflect(-v, n);
	float fres = 0.04 + 0.96 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
	float soft = mix(1.06, 0.86, clamp(q.x * 0.35 + q.y * 0.65, 0.0, 1.0));

	vec3 col;
	if (mat == 0) {
		// Brushed silver: the studio reflected through fine horizontal streaks.
		float br = fbm(vec2(p.x * 0.018 + seed, p.y * 1.7));
		float fine = hash(vec2(floor(p.x * 0.07), floor(p.y)));
		vec3 tint = mix(albedo_low.rgb, albedo.rgb, 0.55 + 0.25 * br);
		vec3 refl = studio(r, 0.22 + 0.08 * br);
		col = tint * (0.56 + 0.56 * refl) * (0.96 + 0.05 * br + 0.03 * fine);
		col += vec3(0.06) * diff;
	} else if (mat == 1 || mat == 2) {
		// Matte powder coat: diffuse light, fine grain, a faint sheen, pooling at the edges.
		float grain = hash(floor(p));
		float mott = fbm(p * 0.01 + seed);
		vec3 base = mix(albedo_low.rgb, albedo.rgb, clamp(soft - 0.25 + mott * 0.3, 0.0, 1.0)) * (0.95 + 0.08 * grain);
		col = base * (0.5 + 0.62 * diff);
		col += studio(r, 0.6) * (mat == 2 ? 0.05 : 0.035) + fres * 0.04;
		col *= 0.9 + 0.1 * smoothstep(0.0, 14.0, t);
	} else if (mat == 3) {
		// Emissive signal glass (HDR, it blooms): a deep core, lit edges, slow flowing light, and the
		// studio on its glassy surface.
		float edge = exp(-t / 30.0);
		float flow = fbm(p * 0.008 + vec2(TIME * 0.04, seed));
		float lift = mix(1.15, 0.82, q.y);
		col = emit.rgb * (0.3 + 0.36 * edge + 0.18 * flow) * emit_strength * pul * lift * 0.8;
		col += mix(emit.rgb, vec3(1.0, 0.8, 0.65), 0.35) * pow(edge, 6.0) * 0.75 * pul;
		col += studio(r, 0.12) * (0.08 + 0.3 * fres);
		col *= 0.97 + 0.06 * hash(floor(p));
	} else if (mat == 4) {
		// Machined dial: concentric turning marks; the studio streaks radially (anisotropic).
		vec2 rv = p - circle.xy;
		float rr = length(rv);
		float ang = atan(rv.y, rv.x);
		float rings = 0.5 + 0.25 * sin(rr * 2.2) + 0.25 * hash(vec2(floor(rr * 1.5), 3.0));
		vec3 rad = normalize(vec3(cos(ang) * 0.5, sin(ang) * 0.5, 1.0));
		vec3 refl = studio(reflect(-v, normalize(n + rad * 0.35)), 0.3);
		col = mix(albedo_low.rgb, albedo.rgb, 0.5) * (0.5 + 0.8 * refl) * (0.9 + 0.12 * rings);
	} else {
		// Dark glass: a black mirror.
		col = albedo.rgb * 0.6 + studio(r, 0.05) * (0.1 + 0.6 * fres);
	}
	if (recess) {
		// A cut: the floor sits lower, the wall facing the light is in shadow.
		float wall = smoothstep(bevel * 1.6, 0.0, t);
		col *= 0.78 - wall * 0.25 * clamp(dot(grad, l.xy) + 0.6, 0.0, 1.0);
	}
	col *= 1.0 - groove * 0.06 * topo;
	// Spill from glowing parts nearby.
	for (int i = 0; i < 4; i++) {
		if (i >= nspill) {
			break;
		}
		vec2 sc2 = spill_rect[i].xy;
		vec2 hs = spill_rect[i].zw;
		float dist;
		vec2 closest;
		if (hs.x < 0.0) {
			vec2 dv = p - sc2;
			float lv = max(length(dv), 0.001);
			dist = max(lv + hs.x, 0.0);
			closest = sc2 + dv / lv * min(lv, -hs.x);
		} else {
			dist = length(max(abs(p - sc2) - hs, vec2(0.0)));
			closest = clamp(p, sc2 - hs, sc2 + hs);
		}
		vec3 ldir = normalize(vec3(closest - p, mix(-6.0, 16.0, smoothstep(0.0, 6.0, dist))));
		float ndl = max(dot(n, ldir), 0.0);
		float fall = exp(-dist / 24.0);
		col += spill_col[i].rgb * spill_col[i].w * fall * (0.15 + 0.85 * ndl);
	}
	// Edge definition: a hairline flash on edges facing the key, a dark crease opposite.
	float rim = smoothstep(1.6, 0.0, t) * clamp(dot(grad, -l.xy * 1.3), 0.0, 1.0) * (recess ? 0.0 : 1.0);
	float crease = smoothstep(1.6, 0.0, t) * clamp(dot(grad, l.xy * 1.3), 0.0, 1.0);
	col += vec3(rim * (mat == 0 ? 0.55 : 0.32));
	col *= 1.0 - crease * 0.4;
	col *= 1.0 - smoothstep(1.0, 0.0, t) * 0.3 * (1.0 - rim);
	col *= 1.0 + press * 0.12;

	// Screws: domed heads with a hex socket, reflecting the studio.
	for (int i = 0; i < 8; i++) {
		if (i >= nscrews) {
			break;
		}
		vec2 sv = p - screws[i].xy;
		float sr = screws[i].z;
		float sl = length(sv);
		if (sl < sr + 1.5) {
			float sa = clamp(sr + 0.5 - sl, 0.0, 1.0);
			vec3 sn = normalize(vec3(sv / sr * 0.9, 1.0));
			vec3 scol = vec3(0.5, 0.52, 0.53) * (0.3 + 0.6 * studio(reflect(-v, sn), 0.25)) + vec3(0.05) * max(dot(sn, l), 0.0);
			float hx = max(abs(sv.x) * 0.866 + abs(sv.y) * 0.5, abs(sv.y));
			scol *= mix(0.2, 1.0, smoothstep(sr * 0.32, sr * 0.42, hx));
			scol *= mix(0.35, 1.0, smoothstep(sr - 0.2, sr - 1.2, sl));
			col = mix(col, scol, sa);
		}
	}

	float a = clamp(0.5 - d, 0.0, 1.0);
	COLOR = to_canvas(mix(outside, vec4(col, 1.0), a));
}
