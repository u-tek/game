// Frosted smoked glass for Kit glass panels (style v4 "Signal", docs/dev/ui-style-v4.md).
// Set as the PanelContainer's material: the panel's StyleBox fill (alpha 0.60-0.80) becomes an
// opaque blur of what is behind it, tinted by the fill colour, with a faint frost grain. Lines,
// brackets and anti-aliased edges (other alphas) draw as usual. Children keep their own look.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Blur reach in screen pixels (two rings of 6 taps plus the centre).
uniform float blur_px = 9.0;
uniform float frost = 0.03;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float a = COLOR.a;
	if (a > 0.595 && a < 0.805) {
		vec2 px = SCREEN_PIXEL_SIZE * blur_px;
		vec3 acc = texture(screen_tex, SCREEN_UV).rgb * 0.2;
		for (int i = 0; i < 6; i++) {
			float ang = float(i) * 1.0471976;
			vec2 d = vec2(cos(ang), sin(ang));
			vec2 d2 = vec2(cos(ang + 0.5235988), sin(ang + 0.5235988));
			acc += texture(screen_tex, SCREEN_UV + d * px).rgb * 0.08;
			acc += texture(screen_tex, SCREEN_UV + d2 * px * 2.1).rgb * 0.0533;
		}
		vec3 col = mix(acc, COLOR.rgb, a);
		col += (hash(floor(FRAGCOORD.xy)) - 0.5) * frost;
		COLOR = vec4(col, 1.0);
	}
}
