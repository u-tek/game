shader_type canvas_item;
// HaloRig part shader (docs/dev/halorig.md section 6).
// vertex: BEND - progressive rotation about the bone pivot (mesh origin), growing with the
//         square of the distance along the part's rest axis, so long soft parts curve.
// fragment: rig-wide tint - hit flash, desaturate + violet shadow (enemy "echo"), and a
//         luminance gradient map (fallback silhouettes take their faction colours from it).

uniform float bend = 0.0;              // radians at the tip (t = 1)
uniform float bend_len = 100.0;        // rig units from pivot to the tip
uniform vec2 bend_axis = vec2(0.0, 1.0);

uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float desat = 0.0;
uniform float shade = 0.0;
uniform vec4 shade_color : source_color = vec4(0.45, 0.32, 0.78, 1.0);
uniform float map_on = 0.0;
uniform vec4 map_dark : source_color = vec4(0.07, 0.05, 0.14, 1.0);
uniform vec4 map_mid : source_color = vec4(0.45, 0.35, 0.6, 1.0);
uniform vec4 map_light : source_color = vec4(1.0, 0.95, 0.8, 1.0);

void vertex() {
	if (bend != 0.0) {
		float t = clamp(dot(VERTEX, bend_axis) / bend_len, 0.0, 1.25);
		float a = bend * t * t;
		float c = cos(a);
		float s = sin(a);
		VERTEX = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y);
	}
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
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
		// pull darks toward a deep violet, keep lights cool and slightly dimmed
		vec3 tinted = mix(shade_color.rgb * (0.25 + 0.75 * l), c * vec3(0.86, 0.84, 1.0), smoothstep(0.25, 0.95, l));
		c = mix(c, tinted, shade);
	}
	c = mix(c, flash_color.rgb, flash);
	COLOR = vec4(c, tex.a) * COLOR;
}
