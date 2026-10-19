// A cumulus cloud drifting over the survey map's terrain model (style v4 "Signal", poster look;
// src/ui/v4/survey/survey_map.gd): a Blender-rendered sprite (tools/blender/clouds.py, packed by
// finish_worlds.py into a 3 x 2 atlas) on a quad that always faces the camera. Straight alpha,
// blended; `fade` takes it in and out at the slab's ends. Colours are source_color (linear).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
// The atlas cell (0..5), the fade (0..1) and a tint over the white.
uniform float cell = 0.0;
uniform float fade = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Lifts the sprite towards white (the renders are lit for a grey sky).
uniform float lift = 0.1;

void vertex() {
	// Billboard: keep the quad's position and scale, face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 a = (vec2(mod(cell, 3.0), floor(cell / 3.0)) + UV) / vec2(3.0, 2.0);
	vec4 c = texture(atlas, a);
	ALBEDO = mix(c.rgb, vec3(1.0), lift) * tint.rgb;
	ALPHA = c.a * fade;
}
