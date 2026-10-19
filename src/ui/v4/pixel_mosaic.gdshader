// Pixel mosaic (style v4 posters, the dossier's framed pixel squares): one region of a texture drawn
// over the whole rect as a grid of flat cells, each the average colour of its patch (a high mip
// level), with a faint seam. `region` is the part of the texture to show, in UV (x, y, w, h); the
// TextureRect draws the full texture (STRETCH_SCALE), so UV runs 0..1 over the rect.
shader_type canvas_item;

uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float cells = 9.0;
uniform float lod = 4.0;
uniform float seam = 0.06;

void fragment() {
	vec2 g = UV * cells;
	vec2 c = (floor(g) + 0.5) / cells;
	vec4 t = textureLod(TEXTURE, region.xy + c * region.zw, lod);
	vec2 f = fract(g);
	float edge = step(f.x, seam) + step(f.y, seam);
	t.rgb *= 1.0 - 0.18 * min(edge, 1.0);
	COLOR = t;
}
