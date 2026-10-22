// The War for Souls' relief map (src/ui/v4/front_relief.gd): a white clay slab of land rendered in
// Blender (tools/blender/front_terrain.py), painted live with who holds what. data_tex gives each
// pixel of the slab's top its sector (R), how far it is from Heaven's end to Hell's (G) and its height
// (B). Each sector's front sits at 0.5 + control * 0.44 (Heaven pushes it toward Hell's end):
//   Heaven's ground: pale paper over the clay, gold halftone dots in its shadows;
//   Hell's ground: dark ink with red halftone where the light catches it, lava glowing and slowly
//                  breathing in the low cracks;
//   the front: an ink trench line with teeth, a thin red glow on Hell's side;
//   the player's sector: its borders ruled in signal.
// Worked in sRGB (texture values as stored), converted for the HDR 2D canvas by ui_linear.
shader_type canvas_item;
global uniform float ui_linear;

uniform sampler2D data_tex : filter_nearest;
uniform float control[7];
uniform int focus = -1;
uniform float grow = 1.0;
uniform vec2 rect_px = vec2(650.0, 640.0);
uniform float cell = 6.0;
uniform vec3 paper = vec3(0.965, 0.955, 0.93);
uniform vec3 gold = vec3(0.86, 0.66, 0.24);
uniform vec3 ink = vec3(0.075, 0.075, 0.085);
uniform vec3 sig = vec3(1.0, 0.294, 0.122);

// Coverage of a halftone dot grid at p (px) for a tone v (0..1), turned by ang.
float dots(vec2 p, float v, float c, float ang) {
	mat2 r = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = r * p / c;
	vec2 f = fract(q) - 0.5;
	float d = length(f) * c;
	float rad = sqrt(clamp(v, 0.0, 1.0)) * c * 0.56;
	return 1.0 - smoothstep(rad - 0.7, rad + 0.7, d);
}

int sector_at(vec2 uv) {
	vec4 d = texture(data_tex, uv);
	return d.r > 0.02 ? clamp(int(floor(d.r * 7.0)), 0, 6) : -1;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// The relief is a grey + alpha texture, which has no sRGB form: it arrives as stored (unlike RGBA
	// textures on the HDR 2D canvas, which arrive linear). The output is converted for the canvas.
	vec3 c = tex.rgb;
	// The clay's light, stretched to its real range (about 0.43 to 0.81 as rendered).
	float lum = smoothstep(0.42, 0.83, tex.r);
	vec4 d = texture(data_tex, UV);
	vec2 p = UV * rect_px;
	if (d.r > 0.02 && tex.a > 0.5) {
		int s = clamp(int(floor(d.r * 7.0)), 0, 6);
		float t = d.g;
		float hgt = d.b;
		// The front, with trench teeth.
		float line = 0.5 + control[s] * 0.44 * grow + sin(p.x * 0.9) * 0.0035;
		float px_t = max(fwidth(t), 1e-4);
		float dist = (t - line) / px_t;     // in pixels, + toward Hell's end
		if (dist < 0.0) {
			// Heaven's ground.
			vec3 base = paper * mix(0.62, 1.03, lum);
			float g = dots(p, (1.0 - lum) * 0.85, cell, 0.26);
			c = mix(base, gold * 0.88, g * 0.5);
		} else {
			// Hell's ground.
			vec3 base = mix(ink, vec3(0.24, 0.09, 0.07), lum);
			float r = dots(p, pow(lum, 2.2) * 0.75, cell, 0.26);
			c = mix(base, sig, r * 0.92);
			// Lava only in the deepest cracks (the lowest tenth of Hell's basin).
			float low = 1.0 - smoothstep(0.13, 0.21, hgt);
			float breathe = 0.72 + 0.28 * sin(TIME * 1.1 + hgt * 37.0 + p.x * 0.015 + p.y * 0.01);
			c = mix(c, vec3(1.0, 0.42, 0.12), low * breathe * 0.9);
			// A red glow along the front on Hell's side.
			c = mix(c, sig, (1.0 - smoothstep(0.0, 9.0, dist)) * 0.55);
		}
		// The trench line itself.
		c = mix(c, ink, 1.0 - smoothstep(1.2, 2.4, abs(dist)));
		// The player's sector: its borders in signal.
		if (s == focus) {
			vec2 dx = vec2(1.6 / rect_px.x, 0.0);
			if (sector_at(UV + dx) != s || sector_at(UV - dx) != s) {
				c = mix(c, sig, 0.95);
			}
		}
	} else if (tex.a > 0.01) {
		// The cut walls: ink and paper strata, as rendered, a little warmer.
		c = c * vec3(1.0, 0.97, 0.93);
	}
	COLOR = vec4(mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear), tex.a);
}
