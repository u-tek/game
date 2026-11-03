// HaloRig shared fragment tint (docs/dev/halorig.md section 6): hit flash, desaturate +
// violet shadow (enemy "echo"), luminance gradient map (fallback silhouettes) and the death
// "fade" dissolve. Included by rig.gdshader (cutout parts) and warp.gdshader (warp meshes).
// map_hard cuts the map to two tones at map_cut (the ultimate's impact frame: her shadows in one
// ink, her lights in the other, like a single printing plate). halftone prints the figure as dots of
// halftone_ink on a 45-degree grid in the art's own space (rest-pose rig pixels, so the dots ride the
// warp and never crawl), as big as she is dark; halftone_lift shrinks them away, lights first (a
// fallen unit in battle).
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float desat = 0.0;
uniform float shade = 0.0;
uniform vec4 shade_color : source_color = vec4(0.45, 0.32, 0.78, 1.0);
uniform float map_on = 0.0;
uniform vec4 map_dark : source_color = vec4(0.07, 0.05, 0.14, 1.0);
uniform vec4 map_mid : source_color = vec4(0.45, 0.35, 0.6, 1.0);
uniform vec4 map_light : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float map_hard = 0.0;
uniform float map_cut = 0.5;
uniform float dissolve = 0.0;          // 0..1: burns away into light
uniform vec4 dissolve_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float halftone = 0.0;
uniform vec4 halftone_ink : source_color = vec4(0.914, 0.91, 0.886, 1.0);
uniform float halftone_cell = 14.0;
uniform float halftone_lift = 0.0;

// 1 when the canvas is linear HDR (the desktop), 0 on the iPhone (HDR 2D off). The tints' luma is
// taken from the sRGB numbers either way, so a cut or a dot size lands the same on both.
global uniform float ui_linear;

varying vec2 part_pos;
// The vertex colour (modulate) alone. In fragment() Godot's COLOR is already the texture times it,
// so tinting texture(TEXTURE, UV) and multiplying by COLOR again would square the art (darker,
// more saturated than the painting); each vertex() stores it here instead.
varying vec4 v_mod;

float halo_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float halo_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(halo_hash(i), halo_hash(i + vec2(1.0, 0.0)), u.x), mix(halo_hash(i + vec2(0.0, 1.0)), halo_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec4 halo_tint(vec4 tex, vec4 vcolor) {
	vec3 c = tex.rgb;
	float l = dot(mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear), vec3(0.299, 0.587, 0.114));
	if (map_on > 0.0) {
		l = mix(l, step(map_cut, l), map_hard);
		vec3 m = l < 0.5 ? mix(map_dark.rgb, map_mid.rgb, l * 2.0) : mix(map_mid.rgb, map_light.rgb, l * 2.0 - 1.0);
		c = mix(c, m, map_on);
		l = dot(c, vec3(0.299, 0.587, 0.114));
	}
	if (desat > 0.0) {
		c = mix(c, vec3(l), desat);
	}
	if (shade > 0.0) {
		vec3 tinted = mix(shade_color.rgb * (0.25 + 0.75 * l), c * vec3(0.86, 0.84, 1.0), smoothstep(0.25, 0.95, l));
		c = mix(c, tinted, shade);
	}
	c = mix(c, flash_color.rgb, flash);
	float a = tex.a;
	if (dissolve > 0.0) {
		float n = halo_noise(part_pos / 40.0) * 0.6 + halo_noise(part_pos / 9.0) * 0.4;
		float d = dissolve * 1.12 - 0.06;
		if (n < d) {
			a = 0.0;
		}
		c = mix(c, dissolve_color.rgb * 1.6, smoothstep(d + 0.1, d, n));
	}
	if (halftone > 0.0) {
		vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * part_pos / max(halftone_cell, 1.0);
		float dist = length(fract(q) - 0.5);
		// Her lights go empty, her darks draw her (not a uniform grid of touching dots).
		float cov = smoothstep(0.25, 0.85, 1.0 - l);
		float r = 0.68 * sqrt(cov) - halftone_lift * 0.76;
		float dotm = 1.0 - smoothstep(r - 0.07, r + 0.07, dist);
		c = mix(c, halftone_ink.rgb, halftone);
		a = mix(a, a * dotm, halftone);
	}
	return vec4(c, a) * vcolor;
}
