// Soft echo (style v4 posters): an out-of-focus, tinted copy of a hero behind her full-colour art,
// like the blurred red figure in the Lobby poster. Blur comes from a high mip level (cheap, no image
// read-back). `tint` is sRGB (no source_color hint) and converted for the linear HDR canvas.
shader_type canvas_item;

uniform float lod = 5.5;
uniform vec4 tint = vec4(1.0, 0.3, 0.12, 0.38);

void fragment() {
	vec4 t = textureLod(TEXTURE, UV, lod);
	float a = tint.a * smoothstep(0.02, 0.6, t.a);
	COLOR = vec4(pow(tint.rgb, vec3(2.2)), 1.0 - pow(1.0 - clamp(a, 0.0, 1.0), 2.2));
}
