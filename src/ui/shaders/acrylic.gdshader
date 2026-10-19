// A rendered acrylic slab (style v4 physical objects: the clear frosted tab, the orange card). Cycles
// rendered it over black and over white (tools/blender/physical_objects.py); finish_physical.py split
// that into what the slab lets through (t_tex: rgb transmission, linear; alpha = where the slab is)
// and the light it adds (l_tex: reflections, lit edges, its printed dots; sRGB). Here what is behind
// it on screen is frosted (blurred where the slab is), shaded by the slab's own tinted shadow (falling
// away from the UI's key light, which leans with ui_tilt), multiplied by the transmission and lit by
// the added light. Opaque: it redraws what was behind it. Drawn on a ColorRect larger than the slab by
// `margin`, after a BackBufferCopy (PhysicalKit.Acrylic).
shader_type canvas_item;
global uniform float ui_linear;
global uniform vec2 ui_tilt;
global uniform float ui_px;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D t_tex : filter_linear, repeat_disable;
uniform sampler2D l_tex : filter_linear, repeat_disable;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float margin = 24.0;
// Frost: blur radius (UI px) of what shows through.
uniform float frost = 6.0;
uniform float shadow_a = 0.4;
uniform float shadow_px = 8.0;
// 1 = the slab's own tint; 0 = clear.
uniform float tint = 1.0;
uniform float lift = 1.0;

vec3 lin(vec3 s) {
	s = max(s, vec3(0.0));
	return mix(pow(s, vec3(2.2)), s, ui_linear);
}

vec3 behind(vec2 suv, float rad, vec2 spx) {
	if (rad < 0.5) {
		return lin(texture(screen_tex, suv).rgb);
	}
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	for (int i = 0; i < 20; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / 20.0) * rad;
		float th = fi * 2.3999632;
		vec2 o = vec2(cos(th), sin(th)) * r * max(ui_px, 0.25) * spx;
		float w = 1.0 - r / (rad + 1.0) * 0.5;
		acc += lin(texture(screen_tex, suv + o).rgb) * w;
		ws += w;
	}
	return acc / ws;
}

void fragment() {
	vec2 sz = rect_size - vec2(margin * 2.0);
	vec2 p = UV * rect_size - vec2(margin);
	vec2 tuv = p / sz;
	bool inside = tuv.x >= 0.0 && tuv.y >= 0.0 && tuv.x <= 1.0 && tuv.y <= 1.0;
	vec4 T = inside ? texture(t_tex, tuv) : vec4(1.0, 1.0, 1.0, 0.0);
	vec3 L = inside ? texture(l_tex, tuv).rgb : vec3(0.0);
	L = pow(max(L, vec3(0.0)), vec3(2.2)) * lift;
	float cover = T.a;
	// The slab's shadow on what is behind it: soft (a few taps), tinted by what it lets through.
	vec3 l = normalize(vec3(-0.45 - ui_tilt.x * 0.6, -0.62 - ui_tilt.y * 0.6, 0.64));
	vec2 so = -l.xy / l.z * shadow_px;
	vec3 shade = vec3(0.0);
	float sw = 0.0;
	for (int i = 0; i < 9; i++) {
		vec2 o = vec2(float(i % 3) - 1.0, float(i / 3) - 1.0) * shadow_px * 0.6;
		vec2 su = (p - so + o) / sz;
		vec4 ts = (su.x >= 0.0 && su.y >= 0.0 && su.x <= 1.0 && su.y <= 1.0) ? texture(t_tex, su) : vec4(1.0, 1.0, 1.0, 0.0);
		shade += mix(vec3(1.0), ts.rgb * 0.7, ts.a * shadow_a);
		sw += 1.0;
	}
	shade /= sw;
	vec3 bg = behind(SCREEN_UV, frost * smoothstep(0.0, 0.6, cover), SCREEN_PIXEL_SIZE) * shade;
	vec3 res = bg * mix(vec3(1.0), T.rgb, tint * cover) + L;
	COLOR = vec4(mix(pow(max(res, vec3(0.0)), vec3(1.0 / 2.2)), res, ui_linear), 1.0);
}
