// Physical paper sheet (style v4 poster look, docs/dev/ui-style-v4.md): a poster's paper with a
// seamless felt or parchment tile (a grey detail map, 0.5 = the paper's own colour) lit by the UI's key
// light, which leans with the phone (global ui_tilt). The sheet's edge shows a hair of thickness (a
// lit hairline on the edges that face the light, a shaded lip opposite) and the sheet casts a tight
// contact shadow plus a soft shadow on the matte, away from the light. Drawn on a ColorRect larger
// than the sheet by `margin` (PhysicalKit.sheet). relief > 0 lights the paper's normal map here too
// (sheets without a paper_relief overlay, which lights the paper and its print together).
shader_type canvas_item;
// 1 when the canvas is linear HDR (viewport hdr_2d), 0 when it is plain sRGB (main.gd sets it).
global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float margin = 32.0;
// sRGB numbers (no source_color hint): the maths is done in sRGB terms and converted at the end.
uniform vec4 fill = vec4(0.914, 0.91, 0.886, 1.0);
uniform sampler2D detail : repeat_enable, filter_linear;
uniform sampler2D nmap : repeat_enable, filter_linear;
// Tile pixels per screen pixel, and where the tile starts (so neighbouring sheets differ).
uniform float tex_scale = 1.0;
uniform vec2 tex_offset = vec2(0.0);
uniform float grain = 0.6;
uniform float relief = 0.0;
uniform float shadow_a = 0.28;
uniform float shadow_r = 22.0;
uniform float thickness = 1.6;
// The light's falloff across the sheet (brighter toward the light).
uniform float falloff = 0.035;

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

vec3 key_light() {
	return normalize(vec3(-0.45 - ui_tilt.x * 0.6, -0.62 - ui_tilt.y * 0.6, 0.64));
}

vec4 to_canvas(vec4 c) {
	vec4 lin = vec4(pow(max(c.rgb, vec3(0.0)), vec3(2.2)), 1.0 - pow(1.0 - clamp(c.a, 0.0, 1.0), 2.2));
	return mix(vec4(max(c.rgb, vec3(0.0)), clamp(c.a, 0.0, 1.0)), lin, ui_linear);
}

void fragment() {
	vec2 p = UV * rect_size - vec2(margin);
	vec2 hs = rect_size * 0.5 - vec2(margin);
	vec2 c = p - hs;
	float d = sd_box(c, hs);
	vec3 l = key_light();
	vec2 away = -l.xy / l.z;

	// Outside: a tight contact shadow and a wide soft one, both falling away from the light.
	float soft = shadow_a * (1.0 - smoothstep(-shadow_r * 0.45, shadow_r, sd_box(c - away * 6.0 * thickness, hs)));
	float contact = 0.4 * (1.0 - smoothstep(-0.6, 2.4 * thickness, sd_box(c - away * 0.9 * thickness, hs)));
	vec4 outside = vec4(0.0, 0.0, 0.0, max(soft, contact));

	// Inside: the paper.
	vec2 uv = (p + tex_offset) * tex_scale / 512.0;
	float g = texture(detail, uv).r - 0.5;
	vec3 col = fill.rgb * (1.0 + g * 2.0 * grain);
	if (relief > 0.0) {
		vec3 n = texture(nmap, uv).rgb * 2.0 - 1.0;
		n = normalize(vec3(n.x * relief, -n.y * relief, max(n.z, 0.3)));
		col *= mix(1.0, clamp(dot(n, l) / l.z, 0.0, 2.0), 0.85);
	}
	vec2 q = p / max(hs * 2.0, vec2(1.0)) - 0.5;
	col *= 1.0 + falloff * dot(q, -normalize(l.xy)) * 2.0;

	// The sheet's edge.
	float e = 0.75;
	vec2 grad = vec2(sd_box(c + vec2(e, 0.0), hs) - sd_box(c - vec2(e, 0.0), hs), sd_box(c + vec2(0.0, e), hs) - sd_box(c - vec2(0.0, e), hs));
	grad = grad / max(length(grad), 0.0001);
	float facing = dot(grad, -normalize(l.xy));
	float t = -d;
	float edge = smoothstep(thickness + 0.8, 0.0, t);
	col += vec3(0.07) * edge * max(facing, 0.0);
	col *= 1.0 - 0.2 * edge * max(-facing, 0.0);

	float a = clamp(0.5 - d, 0.0, 1.0);
	COLOR = to_canvas(mix(outside, vec4(col, fill.a), a));
}
