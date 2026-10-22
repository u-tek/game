// Paper relief over a printed poster (style v4 poster look): what is already drawn (the paper and
// its print) is re-lit through the paper's normal map, so ink sits in the paper's grain instead of
// floating on it. The light is the UI's key light and leans with the phone (global ui_tilt), so the
// grain catches the light as the device moves. A faint sheen on the slopes facing the light lifts dark
// ink a touch. Drawn on a ColorRect over the whole sheet, last in the sheet, after a BackBufferCopy
// (PhysicalKit.relief); the hero figures stay above it.
// Age (the Lobby's poster only: age_days = how long the account has had it on the wall): from a month
// a fold across the middle, a valley that catches the light as the phone tilts, its crest a touch
// paler where the fibres broke; from a hundred days a second fold down the middle and the edges
// warmed by the sun; after a year two pin holes at the top. Each grows in over weeks. 0 = new.
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
uniform float age_days = 0.0;

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
	float crest = 0.0;
	if (age_days >= 30.0) {
		// The first fold, across the middle (not quite straight: it was folded by hand).
		float k = smoothstep(30.0, 75.0, age_days);
		float d = p.y - (rect_size.y * 0.47 + (p.x / rect_size.x) * 7.0 + sin(p.x * 0.011) * 1.2);
		n = normalize(n + vec3(0.0, -sign(d) * exp(-abs(d) / 6.0) * 0.32 * k, 0.0));
		crest += exp(-d * d / 2.2) * k;
	}
	if (age_days >= 100.0) {
		// The second, down the middle: the poster was folded in four.
		float k2 = smoothstep(100.0, 160.0, age_days);
		float dx = p.x - (rect_size.x * 0.52 - (p.y / rect_size.y) * 5.0 + sin(p.y * 0.009) * 1.0);
		n = normalize(n + vec3(-sign(dx) * exp(-abs(dx) / 6.0) * 0.26 * k2, 0.0, 0.0));
		crest += exp(-dx * dx / 2.2) * k2 * 0.8;
	}
	vec3 l = key_light();
	float shade = clamp(dot(n, l) / l.z, 0.0, 2.0);
	c *= mix(1.0, shade, strength);
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float sp = pow(max(dot(n, h), 0.0), 40.0) * max(shade - 1.0, 0.0) * 4.0;
	c += vec3(sheen) * sp * (1.0 - c);
	if (age_days >= 30.0) {
		c = mix(c, vec3(0.97, 0.96, 0.93), clamp(crest, 0.0, 1.0) * 0.2);
	}
	if (age_days >= 100.0) {
		// Sun on the edges: a warm, slightly faded rim.
		float e = min(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y));
		float sun = (1.0 - smoothstep(0.0, 70.0, e)) * smoothstep(100.0, 200.0, age_days);
		c = mix(c, c * vec3(1.0, 0.95, 0.87) + vec3(0.025, 0.015, 0.0), sun * 0.35);
	}
	if (age_days >= 365.0) {
		// Two pin holes at the top corners, a little torn.
		for (int i = 0; i < 2; i++) {
			vec2 pin = vec2(i == 0 ? 22.0 : rect_size.x - 24.0, 21.0 + float(i) * 2.0);
			float r = length(p - pin);
			c = mix(c, c * 0.72, (1.0 - smoothstep(2.4, 4.6, r)) * 0.6);
			c = mix(c, vec3(0.08, 0.07, 0.07), 1.0 - smoothstep(1.0, 1.8, r));
		}
	}
	c = clamp(c, vec3(0.0), vec3(1.0));
	COLOR = vec4(mix(c, pow(c, vec3(2.2)), ui_linear), 1.0);
}
