// A shimmer on type (the rarity language: a Legendary's name on her card; src/ui/v4/rarity_kit.gd):
// the glyphs as drawn (font colour, MSDF and all), with a band of foil light running along the text
// now and then; the band leans with the phone's tilt (global ui_tilt). `length_px` is the text's
// length along its own x axis (the label's local px). Colours are sRGB numbers, converted to the
// canvas (global ui_linear). motion 0 (Reduce motion): no running band.
shader_type canvas_item;

global uniform float ui_linear;
global uniform vec2 ui_tilt;

uniform vec4 shine = vec4(1.0, 0.86, 0.48, 1.0);
uniform float strength = 0.75;
uniform float period = 4.6;
uniform float length_px = 300.0;
uniform float motion = 1.0;
uniform float seed = 0.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float x = lp.x / max(length_px, 1.0) + lp.y * 0.004;
	float t = fract(TIME * motion / period + seed) * 2.2 - 0.6 + ui_tilt.x * 0.25;
	float band = exp(-pow((x - t) * 6.0, 2.0)) * motion;
	vec3 s = clamp(shine.rgb, 0.0, 1.0);
	s = mix(s, pow(s, vec3(2.2)), ui_linear);
	COLOR = vec4(mix(c.rgb, s, clamp(band * strength, 0.0, 1.0)), c.a);
}
