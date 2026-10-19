// A campaign world (style v4 "Signal", poster look; src/ui/v4/survey/world_view.gd): a planet modelled
// and baked in Blender (tools/blender/planets.py, finish_worlds.py), shaded here in real time so it
// can turn and react to touch. The day side is a grey studio render of the relief (the albedo with
// its baked cavity, the normal map lit by a key light from the upper left, a cool fill and a rim);
// towards the terminator the shading turns into print: halftone ink dots grow in the shadow (their
// size still follows the relief), an ink line drawn along the terminator wobbles with the terrain,
// and the night side is paper and dots. The feature mask glows (lava, embers: a painted emissive
// colour, no bloom) or glints (ice, crystal). The height map displaces the vertices, so the
// silhouette is rough. Unshaded (the shading is ours, in view space); colours are source_color
// (linear in the 3D buffer, like the survey map's shaders).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Normal in the sphere's own frame (R east, G north; B is rebuilt), from finish_worlds.py.
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// R height (0.5 = the mean radius), G the feature mask.
uniform sampler2D height_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 paper : source_color = vec4(0.914, 0.910, 0.886, 1.0);
uniform vec4 ink : source_color = vec4(0.063, 0.067, 0.075, 1.0);
// The dots' ink (ink, or signal for the Infernal worlds' night side).
uniform vec4 dot_ink : source_color = vec4(0.063, 0.067, 0.075, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.294, 0.122, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow = 0.0;
// The mask range that glows (low edge, full).
uniform vec2 glow_range = vec2(0.12, 0.8);
uniform float glint = 0.0;
// Vertex displacement (radius units over the 0..1 height) and the normal map's strength.
uniform float relief = 0.045;
uniform float normal_k = 1.0;
// Key light (view space: +x right, +y up, +z towards the viewer).
uniform vec3 light_dir = vec3(-0.74, 0.52, 0.42);
uniform float key = 1.12;
uniform float ambient = 0.05;
// Halftone cell (viewport px) and screen angle; where the print starts (smooth N.L) and how far
// it fades in.
uniform float cell = 5.0;
uniform float angle = 0.785;
uniform float print_from = 0.2;
uniform float print_soft = 0.42;
// 1 = the world is still locked: drained and printed over.
uniform float locked = 0.0;
// Seconds, for the glow's slow breathing (0 = still: Reduce motion).
uniform float flow = 1.0;

varying vec3 obj_dir;

void vertex() {
	float h = textureLod(height_tex, UV, 0.0).r;
	obj_dir = normalize(VERTEX);
	VERTEX += NORMAL * (h - 0.5) * relief;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	// The sphere frame at this point (east along +u, north towards v = 0).
	vec3 up = normalize(obj_dir);
	float el = length(vec2(up.z, up.x));
	vec3 east = el > 1e-4 ? vec3(up.z, 0.0, -up.x) / el : vec3(1.0, 0.0, 0.0);
	vec3 north = cross(up, east);
	vec2 txy = (texture(normal_tex, UV).rg * 2.0 - 1.0) * normal_k;
	float tz = sqrt(max(1.0 - dot(txy, txy), 0.04));
	vec3 n_obj = normalize(east * txy.x + north * txy.y + up * tz);
	mat3 to_view = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	vec3 n = normalize(to_view * n_obj);
	vec3 ns = normalize(to_view * up);
	vec3 L = normalize(light_dir);
	float d = dot(n, L);
	float ds = dot(ns, L);
	vec3 alb = texture(albedo_tex, UV).rgb * tint.rgb;
	vec2 hm = texture(height_tex, UV).rg;
	alb = mix(alb, vec3(luma(alb)) * 1.05, locked * 0.8);

	// Day side: a studio render of the relief.
	float k = clamp(d, 0.0, 1.0);
	vec3 F = normalize(vec3(0.75, -0.42, 0.5));
	float fill = clamp(dot(n, F), 0.0, 1.0) * 0.14;
	float rim = pow(1.0 - clamp(ns.z, 0.0, 1.0), 2.6) * clamp(ds + 0.25, 0.0, 1.0);
	vec3 lit = alb * (ambient + k * key + fill);
	lit += paper.rgb * rim * 0.28;
	// Glints: a tight highlight on the mask (ice cracks, crystal facets).
	vec3 R = reflect(-L, n);
	float spec = pow(clamp(R.z, 0.0, 1.0), 36.0);
	lit += paper.rgb * spec * hm.g * glint * 1.6;

	// Night side: the print. The dots grow with the darkness; a back fill keeps the relief in them.
	float tone = luma(alb) * (0.42 + 0.9 * clamp(dot(n, normalize(vec3(0.55, -0.25, 0.8))), 0.0, 1.0));
	tone = mix(tone, luma(lit), clamp(ds / max(print_from, 0.01), 0.0, 1.0));
	tone = clamp(tone * 1.15 + 0.06, 0.0, 1.0);
	vec2 sp = FRAGCOORD.xy;
	mat2 rot = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 g = rot * sp / cell;
	float dist = length(fract(g) - 0.5);
	float r = sqrt(1.0 - tone) * 0.64;
	float aa = max(fwidth(dist), 0.001);
	float dotv = 1.0 - smoothstep(r - aa, r + aa, dist);
	vec3 printed = mix(paper.rgb, dot_ink.rgb, dotv);
	float pk = smoothstep(print_from, print_from - print_soft, ds);
	pk = max(pk, locked * 0.55);
	vec3 col = mix(lit, printed, pk);

	// The terminator, drawn in ink; it wobbles with the terrain.
	float t0 = 0.015 + (hm.r - 0.5) * 0.12;
	float tw = fwidth(ds) * 1.4;
	float tline = 1.0 - smoothstep(tw * 0.5, tw * 1.5, abs(ds - t0));
	col = mix(col, ink.rgb, tline * 0.85 * (1.0 - locked * 0.5));

	// Feature glow (lava, embers): a painted emissive colour, strongest in the dark.
	float breath = 0.85 + 0.15 * sin(TIME * flow * 1.3 + hm.r * 9.0);
	float gm = smoothstep(glow_range.x, glow_range.y, hm.g) * glow * breath * (1.0 - locked * 0.7);
	vec3 hot = mix(glow_color.rgb, vec3(1.0, 0.86, 0.55), smoothstep(0.75, 1.0, hm.g) * 0.6);
	col = mix(col, hot, clamp(gm * (0.55 + 0.45 * pk), 0.0, 1.0));

	ALBEDO = col;
}
