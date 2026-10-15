// HaloRig shared fragment tint (docs/dev/halorig.md section 6): hit flash, desaturate +
// violet shadow (enemy "echo"), luminance gradient map (fallback silhouettes) and the death
// "fade" dissolve. Included by rig.gdshader (cutout parts) and warp.gdshader (warp meshes).
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float desat = 0.0;
uniform float shade = 0.0;
uniform vec4 shade_color : source_color = vec4(0.45, 0.32, 0.78, 1.0);
uniform float map_on = 0.0;
uniform vec4 map_dark : source_color = vec4(0.07, 0.05, 0.14, 1.0);
uniform vec4 map_mid : source_color = vec4(0.45, 0.35, 0.6, 1.0);
uniform vec4 map_light : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float dissolve = 0.0;          // 0..1: burns away into light
uniform vec4 dissolve_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);

varying vec2 part_pos;

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
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (map_on > 0.0) {
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
	return vec4(c, a) * vcolor;
}
