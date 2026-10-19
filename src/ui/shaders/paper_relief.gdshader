// Paper relief over a printed poster (style v4 poster look): what is already drawn (the paper and
// its print) is re-lit through the paper's normal map, so ink sits in the paper's grain instead of
// floating on it. The light is the UI's key light and leans with the phone (global ui_tilt), so the
// grain catches the light as the device moves. A faint sheen on the slopes facing the light lifts dark
// ink a touch. Drawn on a ColorRect over the whole sheet, last in the sheet, after a BackBufferCopy
// (PhysicalKit.relief); the hero figures stay above it.
shader_type canvas_item;
global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D nmap : repeat_enable, filter_linear;
uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float tex_scale = 1.0;
uniform vec2 tex_offset = vec2(0.0);
uniform float relief = 1.0;
uniform float strength = 0.8;
uniform float sheen = 0.05;

vec3 key_light() {
	return normalize(vec3(-0.45 - ui_tilt.x * 0.6, -0.62 - ui_tilt.y * 0.6, 0.64));
}

void fragment() {
	vec3 s = max(texture(screen_tex, SCREEN_UV).rgb, vec3(0.0));
	vec3 c = mix(s, pow(s, vec3(1.0 / 2.2)), ui_linear);
	vec2 p = UV * rect_size;
	vec2 uv = (p + tex_offset) * tex_scale / 512.0;
	vec3 n = texture(nmap, uv).rgb * 2.0 - 1.0;
	n = normalize(vec3(n.x * relief, -n.y * relief, max(n.z, 0.3)));
	vec3 l = key_light();
	float shade = clamp(dot(n, l) / l.z, 0.0, 2.0);
	c *= mix(1.0, shade, strength);
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float sp = pow(max(dot(n, h), 0.0), 40.0) * max(shade - 1.0, 0.0) * 4.0;
	c += vec3(sheen) * sp * (1.0 - c);
	c = clamp(c, vec3(0.0), vec3(1.0));
	COLOR = vec4(mix(c, pow(c, vec3(2.2)), ui_linear), 1.0);
}
