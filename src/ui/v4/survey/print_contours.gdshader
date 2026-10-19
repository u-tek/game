// A printed contour map (style v4 "Signal", poster look; the quests mission sheet): ink iso-lines of
// a height texture (every 4th heavier) and the rivers as a signal-red line, on transparent paper.
// Canvas shader: colours are sRGB numbers, converted to the linear HDR canvas at the end.
shader_type canvas_item;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D river_tex : filter_linear, repeat_disable;
uniform vec4 ink = vec4(0.063, 0.067, 0.075, 1.0);
uniform vec4 accent = vec4(1.0, 0.294, 0.122, 1.0);
uniform float levels = 14.0;
uniform float line_a = 0.8;
// River line half-width in units of the river field (0..1 over the field's reach).
uniform float river_w = 0.035;

vec4 to_canvas(vec4 c) {
	return vec4(pow(max(c.rgb, vec3(0.0)), vec3(2.2)), 1.0 - pow(1.0 - clamp(c.a, 0.0, 1.0), 2.2));
}

float hair(float d, float fw, float px) {
	fw = max(fw, 1e-5);
	return 1.0 - smoothstep(px * 0.5 * fw - 0.5 * fw, px * 0.5 * fw + 0.5 * fw, abs(d));
}

void fragment() {
	float h = texture(height_tex, UV).r * levels;
	float fw = fwidth(h);
	float minor = hair(fract(h + 0.5) - 0.5, fw, 0.9) * 0.45;
	float major = hair(fract(h * 0.25 + 0.5) - 0.5, fw * 0.25, 1.4) * 0.9;
	float rd = texture(river_tex, UV).r;
	float frd = fwidth(rd);
	float riv = 1.0 - smoothstep(river_w - frd, river_w + frd, rd);
	vec4 c = vec4(ink.rgb, max(minor, major) * line_a);
	c = mix(c, vec4(accent.rgb, 1.0), riv);
	COLOR = to_canvas(c);
}
