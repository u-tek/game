// The soft shadow of the survey map's terrain model on the poster (style v4 "Signal";
// src/ui/v4/survey/survey_map.gd): a plane under the slab, dark in a rounded rectangle the slab's
// size that fades out over `soft` world units. Blended over the paper (the IsoView composites
// premultiplied), so the model reads as an object lying on the sheet.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 plane_size = vec2(14.0, 10.0);
uniform vec2 slab = vec2(11.0, 7.0);
uniform float soft = 0.9;
uniform float strength = 0.42;
uniform vec4 shade : source_color = vec4(0.05, 0.05, 0.06, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * plane_size;
	vec2 q = abs(p) - slab * 0.5;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
	float a = 1.0 - smoothstep(-0.2, soft, d);
	ALBEDO = shade.rgb;
	ALPHA = a * a * strength;
}
