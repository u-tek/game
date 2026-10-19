// Print halftone (style v4 "Signal"): redraws a texture as a rotated grid of ink dots whose size
// follows the image's brightness (or darkness), for poster bands, loading cards and big moments.
// The grid is in screen pixels, so the dot pitch stays the same however the image is scaled.
shader_type canvas_item;

uniform float cell = 9.0;
uniform float angle = 0.5236;
// sRGB ink colour (no source_color hint: converted to the linear HDR canvas at the end).
uniform vec4 ink = vec4(1.0, 0.33, 0.14, 1.0);
// Dots grow with brightness (a negative print on a dark band) unless false.
uniform bool light_dots = true;
uniform float gain = 1.2;
uniform float lift = 0.0;

void fragment() {
	vec2 sp = FRAGCOORD.xy;
	mat2 rot = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 g = rot * sp / cell;
	vec2 cc = floor(g) + 0.5;
	vec2 sc = inverse(rot) * (cc * cell);
	vec2 off = sc - sp;
	vec2 uv_c = UV + dFdx(UV) * off.x + dFdy(UV) * off.y;
	vec4 t = texture(TEXTURE, uv_c);
	float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float v = light_dots ? lum : 1.0 - lum;
	v = clamp((v + lift) * gain, 0.0, 1.0) * t.a;
	float r = sqrt(v) * 0.64;
	float dist = length(g - cc);
	float aa = max(fwidth(dist), 0.001);
	float dotv = 1.0 - smoothstep(r - aa, r + aa, dist);
	COLOR = vec4(pow(ink.rgb, vec3(2.2)), ink.a * dotv);
}
