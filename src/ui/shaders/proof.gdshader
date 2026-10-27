// The proof under the loupe (the Legendary summon's close-up): a hero's art printed as a four-colour
// halftone, cyan, magenta, yellow and key dots, each screen at its own angle (the rosette of a real
// press sheet), multiplied on paper. The dot pitch is fixed to the art (`cell`, in texture pixels),
// so the dots read huge while the camera is close on her eyes and shrink as it pulls back, the way a
// printer's loupe lifts off a sheet; `resolve` (0..1) melts the dots into the art's continuous tone.
// `sheet` (0..1) is the paper around her: 1 a full proof sheet, 0 only her (the match cut into the
// poster). Maths in sRGB numbers, converted to the canvas at the end (no bloom: the iPhone build has
// no HDR 2D).
shader_type canvas_item;
render_mode unshaded;

// 1 when the canvas is linear HDR (viewport hdr_2d), 0 when it is plain sRGB (main.gd sets it).
global uniform float ui_linear;

// Dot pitch in texture pixels.
uniform float cell = 4.0;
uniform vec2 tex_size = vec2(1024.0, 2048.0);
uniform float resolve = 0.0;
uniform float sheet = 1.0;
// sRGB numbers (no source_color hint).
uniform vec4 paper = vec4(0.914, 0.91, 0.886, 1.0);

// Process inks, as printed on the paper (sRGB numbers).
const vec3 CYAN = vec3(0.0, 0.62, 0.88);
const vec3 MAGENTA = vec3(0.89, 0.05, 0.47);
const vec3 YELLOW = vec3(1.0, 0.92, 0.0);
const vec3 KEY = vec3(0.063, 0.067, 0.075);

vec3 to_srgb(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
}

vec3 to_canvas(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear);
}

// The CMYK separation of an sRGB colour (with some grey replaced by key, like a press's GCR).
vec4 separate(vec3 c) {
	float k = 1.0 - max(max(c.r, c.g), c.b);
	float d = max(1.0 - k, 0.001);
	vec3 cmy = (vec3(1.0) - c - vec3(k)) / d;
	return vec4(cmy, k * 0.8);
}

void fragment() {
	vec2 p = UV * tex_size;
	vec4 art = texture(TEXTURE, UV);
	art.rgb = to_srgb(art.rgb);
	// One screen per plate: cyan 15, magenta 75, yellow 0, key 45 degrees.
	vec4 ang = vec4(0.2618, 1.309, 0.0, 0.7854);
	vec4 cover = vec4(0.0);
	for (int i = 0; i < 4; i++) {
		float a = ang[i];
		mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		vec2 g = rot * p / cell;
		vec2 cc = floor(g) + 0.5;
		vec2 centre = inverse(rot) * (cc * cell);
		// The ink this dot carries: the art at the dot's centre, averaged over about one cell.
		vec4 s = textureLod(TEXTURE, centre / tex_size, log2(max(cell, 1.0)));
		s.rgb = to_srgb(s.rgb);
		float v = separate(s.rgb)[i] * s.a;
		// Area true to the tone (a dot of radius sqrt(v / pi) covers v of its cell), a little dot gain.
		float r = sqrt(clamp(v, 0.0, 1.0)) * 0.65;
		float dist = length(g - cc);
		float aa = max(fwidth(dist), 0.002);
		cover[i] = 1.0 - smoothstep(r - aa, r + aa, dist);
	}
	vec3 dots = paper.rgb;
	dots *= mix(vec3(1.0), CYAN, cover.x);
	dots *= mix(vec3(1.0), MAGENTA, cover.y);
	dots *= mix(vec3(1.0), YELLOW, cover.z);
	dots *= mix(vec3(1.0), KEY, cover.w);
	// The continuous-tone proof: the art over the paper.
	// (Without the sheet her own colour is kept to the edge: her alpha does the cut.)
	vec3 tone = mix(art.rgb, mix(paper.rgb, art.rgb, art.a), sheet);
	vec3 c = mix(dots, tone, resolve);
	// Around her: the sheet, or nothing (her own alpha, with her dots kept on the paper's ink).
	float ink_a = max(max(cover.x, cover.y), max(cover.z, cover.w));
	float a = mix(mix(ink_a, art.a, resolve), 1.0, sheet);
	COLOR = vec4(to_canvas(c), a);
}
