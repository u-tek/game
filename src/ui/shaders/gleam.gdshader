// A soft sheen on a rendered glossy cap (style v4 physical objects: the red dome, the red cap in its
// knurled bezel; PhysicalKit.PushCap): a broad reflection of the key light sits top left on the cap
// and drifts with the phone's tilt (global ui_tilt) and, slowly, on its own, so the plastic looks
// lit rather than printed. Only on the cap (an ellipse: centre and radii in UV), never on the bezel's
// knurl. The maths is in sRGB numbers, converted to the canvas (ui_linear); nothing relies on bloom.
shader_type canvas_item;
global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform vec2 center_uv = vec2(0.5, 0.5);
uniform vec2 radius_uv = vec2(0.45, 0.45);
uniform float strength = 0.1;
uniform float motion = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float t = TIME * motion + seed;
	vec2 q = (UV - center_uv) / radius_uv;
	float cap = 1.0 - smoothstep(0.78, 1.0, length(q));
	vec2 hp = vec2(-0.36, -0.4) + ui_tilt * 0.3 + vec2(sin(t * 0.33), cos(t * 0.27 + 1.1)) * 0.08 * motion;
	vec2 dq = (q - hp) * vec2(1.0, 1.35);
	float k = exp(-dot(dq, dq) / 0.07) * strength * cap;
	vec3 s = mix(c.rgb, pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
	s += vec3(k) * (1.0 - s * 0.5);
	c.rgb = mix(s, pow(max(s, vec3(0.0)), vec3(2.2)), ui_linear);
	COLOR = c;
}
