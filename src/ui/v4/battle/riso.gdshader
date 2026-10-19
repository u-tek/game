// Risograph print (style v4 "Signal", battle results): a texture redrawn as two overprinted
// halftone screens, signal red-orange and ink, each on its own screen angle and printed a few
// pixels out of register, multiplied onto the paper under it like riso ink. The grids are in
// screen pixels (the dot pitch stays the same however the image is scaled).
// Maths in sRGB numbers (no source_color hints). The multiply factor is converted at the end only
// when the canvas is linear HDR (ui_linear = 1; (a * b)^2.2 = a^2.2 * b^2.2, so multiplying in
// linear light is exact); on a plain sRGB canvas (ui_linear = 0, the iPhone build) it is used as is.
// Nothing here relies on bloom.
shader_type canvas_item;
render_mode blend_mul, unshaded;

// 1 = linear HDR canvas, 0 = plain sRGB (main.gd sets it).
global uniform float ui_linear;

// Plate A: signal, prints the mid tones and shadows.
uniform vec4 ink_a = vec4(1.0, 0.294, 0.122, 1.0);
uniform float cell_a = 7.0;
uniform float angle_a = 0.2618;
uniform vec2 shift_a = vec2(0.0, 0.0);
uniform float gain_a = 1.3;
uniform float lift_a = 0.06;
// Plate B: ink, prints only the darks (below cut_b brightness), out of register by shift_b px.
uniform vec4 ink_b = vec4(0.063, 0.067, 0.075, 1.0);
uniform float cell_b = 6.0;
uniform float angle_b = 1.309;
uniform vec2 shift_b = vec2(5.0, -3.0);
uniform float gain_b = 1.25;
uniform float cut_b = 0.4;
// 0..1: fades both plates in (the print being pulled).
uniform float strength = 1.0;

float dot_cover(vec2 g, float v) {
	vec2 cc = floor(g) + 0.5;
	float r = sqrt(clamp(v, 0.0, 1.0)) * 0.66;
	float dist = length(g - cc);
	float aa = max(fwidth(dist), 0.001);
	return 1.0 - smoothstep(r - aa, r + aa, dist);
}

void fragment() {
	vec2 sp = FRAGCOORD.xy;
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);

	mat2 ra = mat2(vec2(cos(angle_a), sin(angle_a)), vec2(-sin(angle_a), cos(angle_a)));
	vec2 ga = ra * sp / cell_a;
	vec2 offa = inverse(ra) * ((floor(ga) + 0.5) * cell_a) - shift_a - sp;
	vec4 ta = texture(TEXTURE, UV + dx * offa.x + dy * offa.y);
	float la = dot(ta.rgb, vec3(0.299, 0.587, 0.114));
	float va = clamp((1.0 - la + lift_a) * gain_a, 0.0, 1.0) * ta.a * strength;
	float cov_a = dot_cover(ga, va);

	mat2 rb = mat2(vec2(cos(angle_b), sin(angle_b)), vec2(-sin(angle_b), cos(angle_b)));
	vec2 gb = rb * sp / cell_b;
	vec2 offb = inverse(rb) * ((floor(gb) + 0.5) * cell_b) - shift_b - sp;
	vec4 tb = texture(TEXTURE, UV + dx * offb.x + dy * offb.y);
	float lb = dot(tb.rgb, vec3(0.299, 0.587, 0.114));
	float vb = clamp((cut_b - lb) / max(cut_b, 0.01) * gain_b, 0.0, 1.0) * tb.a * strength;
	float cov_b = dot_cover(gb, vb);

	vec3 f = mix(vec3(1.0), ink_a.rgb, cov_a * ink_a.a) * mix(vec3(1.0), ink_b.rgb, cov_b * ink_b.a);
	COLOR = vec4(mix(f, pow(f, vec3(2.2)), ui_linear), 1.0);
}
