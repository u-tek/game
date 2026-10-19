// Felt stock (style v4, the Rival's poster): a grey pressed-felt board like the owner's reference
// poster, drawn from noise: fine fibres in two crossing directions, soft lumps, flecks, a light from
// the top left and a darker rim. `size` is the rect in pixels so the fibres keep their scale.
// Colours are sRGB numbers converted for the linear HDR canvas at the end (ui_linear); nothing here
// relies on bloom.
shader_type canvas_item;
render_mode unshaded;

global uniform float ui_linear;

uniform vec2 size = vec2(688.0, 1200.0);
uniform vec4 base = vec4(0.55, 0.553, 0.565, 1.0);
uniform float fibre = 1.0;
uniform float seed = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * size;
	// Fibres: noise stretched along two crossing directions, a hair finer than a pixel apart.
	vec2 d1 = vec2(0.94, 0.34);
	vec2 d2 = vec2(-0.3, 0.95);
	float f1 = noise(vec2(dot(p, d1) * 0.18, dot(p, vec2(-d1.y, d1.x)) * 1.6));
	float f2 = noise(vec2(dot(p, d2) * 0.2, dot(p, vec2(-d2.y, d2.x)) * 1.5) + 31.0);
	float fib = (f1 + f2 - 1.0) * 0.07 * fibre;
	float lumps = (fbm(p * 0.012) - 0.5) * 0.09;
	float fine = (noise(p * 0.9) - 0.5) * 0.05;
	float fleck = step(0.996, hash(floor(p * 0.5))) * 0.12;
	vec3 c = base.rgb * (1.0 + fib + lumps + fine) + fleck * 0.6;
	// Light from the top left, a darker rim.
	float light = 1.06 - 0.12 * (UV.x * 0.6 + UV.y * 0.4);
	vec2 e = min(UV, 1.0 - UV) * size;
	float rim = smoothstep(0.0, 28.0, min(e.x, e.y));
	c *= light * mix(0.82, 1.0, rim);
	c = clamp(c, 0.0, 1.0);
	COLOR = vec4(mix(c, pow(c, vec3(2.2)), ui_linear), 1.0);
}
