shader_type canvas_item;
// The Epic's die-cut (src/ui/summon/summon_reveal.gd), drawn from her still's alpha on a TextureRect lined
// up with her figure. mode 0: the kiss-cut, a paper-white line just outside her silhouette, drawn on as
// the cutter travels round her (k 0..1, clockwise from the top of `pivot`). mode 1: her shadow on the
// sheet while she is lifted off it, a soft ink blur (the still has mipmaps).

uniform int mode = 0;
uniform float k = 1.0;
// The line's distance out from her edge, in screen px, and the TextureRect's size.
uniform float width = 4.0;
uniform vec2 rect_size = vec2(400.0, 800.0);
uniform vec2 pivot = vec2(0.5, 0.42);
uniform vec4 ink : source_color = vec4(1.0);
uniform float strength = 1.0;

void fragment() {
	if (mode == 1) {
		float a = textureLod(TEXTURE, UV, 4.5).a;
		COLOR = vec4(ink.rgb, a * strength);
	} else {
		vec2 d = width / rect_size;
		float a = textureLod(TEXTURE, UV, 1.0).a;
		float dil = 0.0;
		for (int i = 0; i < 12; i++) {
			float ang = float(i) * 0.5235988;
			dil = max(dil, textureLod(TEXTURE, UV + vec2(cos(ang), sin(ang)) * d, 1.0).a);
		}
		float line = smoothstep(0.3, 0.6, dil) * (1.0 - smoothstep(0.25, 0.55, a));
		vec2 p = (UV - pivot) * rect_size;
		float u = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
		// a short bright head where the cutter is now
		float head = smoothstep(k - 0.025, k, u) * step(u, k) * step(k, 0.999);
		COLOR = vec4(mix(ink.rgb, vec3(1.0), head * 0.6), line * step(u, k) * strength);
	}
}
