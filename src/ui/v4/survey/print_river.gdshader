// A river ribbon on the survey map's hydrography sheet (style v4 "Signal", poster look;
// src/ui/v4/survey/survey_map.gd): signal red, with dashes of full signal running downstream over a
// paler signal line, so the water reads as flowing. UV.x is the distance along the river from its
// source (world units), UV.y runs across the ribbon. Unshaded and opaque (drawn before the vellum
// sheets, which tint it a little as they do the terrain). Colours are source_color (linear in the 3D
// buffer, like the terrain); `flow` 0 stops the dashes (Reduce motion).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 river : source_color = vec4(1.0, 0.294, 0.122, 1.0);
uniform vec4 paper : source_color = vec4(0.914, 0.910, 0.886, 1.0);
// One dash plus its gap (world units), the share of it that is dash, and the speed (units / s).
uniform float dash = 0.36;
uniform float duty = 0.58;
uniform float speed = 0.24;
uniform float flow = 1.0;

void fragment() {
	float s = (UV.x - TIME * flow * speed) / dash;
	float f = fract(s);
	float aa = clamp(fwidth(s) * 1.5, 0.001, 0.25);
	float on = smoothstep(0.0, aa, f) * (1.0 - smoothstep(duty - aa, duty, f));
	// The gaps stay a pale signal line; the dashes are full signal with a slightly darker core.
	vec3 pale = mix(river.rgb, paper.rgb, 0.55);
	float core = 1.0 - smoothstep(0.15, 0.5, abs(UV.y - 0.5));
	vec3 full = mix(river.rgb, river.rgb * 0.82, core * 0.5);
	ALBEDO = mix(pale, full, on);
}
