// The survey map's terrain as a physical model (style v4 "Signal", poster look;
// src/ui/v4/survey/survey_map.gd), built like the owner's isometric-terrain reference: a matte relief
// model lying on the poster, its rock dark and lit from the upper left, its valleys lit warm by the
// molten river that runs the stage route (a painted emissive gradient, no bloom: the warmth is in the
// colour), fine relief grain from a tiling detail normal, faint engraved contour lines, and the
// shadows of the drifting clouds. The cut sides are dark with paper strata lines; where a river leaves
// the slab it pours down the side as a glowing fall. Unshaded (the shading is ours); colours are
// source_color (linear in the 3D buffer). `flow` 0 holds everything still (Reduce motion).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 rock_lo : source_color = vec4(0.11, 0.1, 0.12, 1.0);
uniform vec4 rock_hi : source_color = vec4(0.36, 0.33, 0.37, 1.0);
// The valleys' warm light, and the hot colour near the river.
uniform vec4 warm : source_color = vec4(0.95, 0.42, 0.16, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform vec4 side_ink : source_color = vec4(0.07, 0.065, 0.075, 1.0);
uniform vec4 paper : source_color = vec4(0.914, 0.910, 0.886, 1.0);
uniform vec3 light_dir = vec3(-0.78, 0.5, 0.36);
uniform float ambient = 0.16;
// How far from the river (0..1 of the river field) the warm light reaches, and the height (0..1)
// under which low ground glows.
uniform float warm_reach = 0.42;
uniform float warm_low = 0.2;
uniform float warm_k = 1.0;
// 1 = the river runs molten, 0 = it has cooled (a world not reached yet): the bed and the fall go dark.
uniform float melt = 1.0;
uniform float river_w = 0.12;
uniform float levels = 14.0;
uniform float contour_a = 0.16;
uniform float base_y = -0.9;
// Fine relief: a tiling normal map in world xz.
uniform sampler2D detail_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail = 0.95;
uniform float detail_scale = 1.1;
// Cloud shadows: a top-down silhouette atlas (3 x 2) and up to six clouds
// (x, z, half size, atlas cell), offset away from the light.
uniform sampler2D cloud_shadow_tex : filter_linear, repeat_disable;
uniform vec4 clouds[6];
uniform int cloud_count = 0;
uniform float cloud_k = 0.5;
uniform vec2 shadow_shift = vec2(0.9, -0.5);
uniform float flow = 1.0;

varying vec3 world_n;
varying vec3 world_p;

void vertex() {
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hair(float d, float fw, float px) {
	fw = max(fw, 1e-5);
	return 1.0 - smoothstep(px * 0.5 * fw - 0.5 * fw, px * 0.5 * fw + 0.5 * fw, abs(d));
}

float cloud_shade(vec2 xz) {
	float s = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= cloud_count) {
			break;
		}
		vec4 c = clouds[i];
		vec2 uv = (xz - c.xy - shadow_shift) / (2.0 * c.z) + 0.5;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			continue;
		}
		float cell = c.w;
		vec2 a = (vec2(mod(cell, 3.0), floor(cell / 3.0)) + uv) / vec2(3.0, 2.0);
		s = max(s, texture(cloud_shadow_tex, a).r);
	}
	return s;
}

void fragment() {
	vec3 col;
	vec3 L = normalize(light_dir);
	float tt = TIME * flow;
	if (UV2.y < -0.5) {
		// Cut side: dark, paper strata lines, a lighter seam at the base; a river leaving the slab
		// pours down it, glowing.
		float lit = 0.55 + 0.45 * max(dot(normalize(world_n), L), 0.0);
		col = side_ink.rgb * lit;
		float s = world_p.y * 9.0;
		float strata = hair(fract(s + 0.5) - 0.5, fwidth(s), 0.8) * 0.22;
		float seam = hair(world_p.y - (base_y + 0.06), fwidth(world_p.y), 1.2) * 0.45;
		col = mix(col, paper.rgb * 0.6, max(strata, seam));
		float fall = (1.0 - smoothstep(river_w * 0.4, river_w * 1.6, UV2.x)) * melt;
		float down = clamp((world_p.y - base_y) / 1.2, 0.0, 1.0);
		float ripple = 0.75 + 0.25 * sin(world_p.y * 30.0 + tt * 6.0);
		col = mix(col, mix(warm.rgb, hot.rgb, fall * down) * ripple, fall * (0.35 + 0.65 * down));
	} else {
		float h = UV2.x;
		float rd = UV2.y;
		// Relief: the mesh normal with a fine tiling grain on top (stronger on the high ground).
		vec4 dt = texture(detail_tex, world_p.xz / detail_scale);
		vec2 dn = dt.rg * 2.0 - 1.0;
		vec3 n = normalize(world_n + vec3(dn.x, 0.0, dn.y) * detail * (0.4 + 0.6 * smoothstep(0.1, 0.6, h)));
		float diff = max(dot(n, L), 0.0);
		float cav = clamp((COLOR.r - 0.5) * 1.6, -0.4, 0.7);
		vec3 rock = mix(rock_lo.rgb, rock_hi.rgb, smoothstep(0.05, 0.95, h));
		col = rock * (ambient + diff * 1.2) * (1.0 - cav * 0.7);
		// Warm valleys: lit by the river, strongest near it and in the low ground; broken up by the
		// grain so it reads as lit ground, not a glowing outline.
		float grain = texture(detail_tex, world_p.xz / (detail_scale * 3.7) + vec2(0.31, 0.17)).r;
		float near = 1.0 - smoothstep(0.0, warm_reach * (0.75 + 0.5 * grain), rd);
		float low = 1.0 - smoothstep(warm_low * 0.4, warm_low * (0.8 + 0.4 * grain), h);
		float valley = clamp(max(near * near * 0.8, low * 0.75) * warm_k, 0.0, 1.0);
		vec3 warm_col = warm.rgb * (0.45 + 0.7 * diff) + warm.rgb * 0.18;
		warm_col = mix(warm_col, hot.rgb, pow(near, 4.0) * 0.55);
		col = mix(col, warm_col, valley);
		// Faint contours engraved in the model.
		float hl = h * levels;
		float cl = hair(fract(hl + 0.5) - 0.5, fwidth(hl), 0.9);
		col = mix(col, col * 0.55, cl * contour_a * (1.0 - near));
		// The river bed under the molten ribbon.
		float core = 1.0 - smoothstep(river_w * 0.6, river_w, rd);
		col = mix(col, mix(col * 0.35, hot.rgb, melt), core);
		// Cloud shadows.
		float cs = cloud_shade(world_p.xz);
		col *= 1.0 - cs * cloud_k;
	}
	ALBEDO = col;
}
