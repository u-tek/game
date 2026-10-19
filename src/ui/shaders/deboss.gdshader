// Debossed type (style v4 poster look): the giant poster titles pressed into the paper. The material
// of a CanvasGroup holding the type (PhysicalKit.deboss): the group draws its children into the back
// buffer, and this reads their coverage around each pixel. Where the letter's edge faces the light (the
// UI's key light, leaning with ui_tilt) its wall falls in shadow; where it faces away the wall catches
// the light (a rim of paper colour); the floor of the cut sits a little darker. Offsets are in UI
// pixels (global ui_px: device pixels per UI pixel).
shader_type canvas_item;
render_mode unshaded;
global uniform float ui_linear;
global uniform vec2 ui_tilt;
global uniform float ui_px;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// Width of the walls in UI px.
uniform float depth = 4.0;
uniform float shadow = 0.62;
uniform float light = 0.55;
uniform float floor_shade = 0.06;
// The rim's colour (sRGB numbers): the paper's.
uniform vec4 rim = vec4(0.96, 0.955, 0.94, 1.0);

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	vec2 ld = normalize(vec2(-0.45, -0.62) - ui_tilt * 0.6);
	float sh = 0.0;
	float hl = 0.0;
	float ws = 0.0;
	for (int i = 1; i <= 6; i++) {
		float k = float(i) / 6.0;
		vec2 o = ld * depth * max(ui_px, 0.25) * k * SCREEN_PIXEL_SIZE;
		float w = 1.0 - k * 0.55;
		sh += (1.0 - textureLod(screen_texture, SCREEN_UV + o, 0.0).a) * w;
		hl += (1.0 - textureLod(screen_texture, SCREEN_UV - o, 0.0).a) * w;
		ws += w;
	}
	sh /= ws;
	hl /= ws;
	vec3 col = mix(c.rgb, pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
	col *= 1.0 - floor_shade;
	col *= 1.0 - shadow * sh;
	col = mix(col, rim.rgb, light * hl * (1.0 - sh));
	col = mix(col, pow(max(col, vec3(0.0)), vec3(2.2)), ui_linear);
	COLOR = vec4(col, c.a) * COLOR;
}
