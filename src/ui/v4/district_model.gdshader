// One building of the district maquette (src/ui/v4/district_model.gd), white clay rendered in Blender
// with its cast shadow. state: 0 open, 1 kept, 2 kept by a heroine of the side (doubled: the side's
// ink in halftone over its shading), 3 not yet built (a frosted placeholder, its shadow faint), 4 the
// next to open (frosted, warmed with signal). The halftone grid runs in plan px (offset_px is this
// sprite's place) so it lines up across buildings. RGBA textures arrive in canvas space (linear on the
// HDR 2D canvas), so the work is done in sRGB and converted back by ui_linear.
shader_type canvas_item;
global uniform float ui_linear;

uniform int state = 0;
uniform vec3 tint = vec3(0.86, 0.66, 0.24);
uniform vec3 sig = vec3(1.0, 0.294, 0.122);
uniform vec2 rect_px = vec2(100.0, 100.0);
uniform vec2 offset_px = vec2(0.0);
uniform float cell = 5.0;

float dots(vec2 p, float v, float c) {
	mat2 r = mat2(vec2(0.966, 0.259), vec2(-0.259, 0.966));
	vec2 f = fract(r * p / c) - 0.5;
	float rad = sqrt(clamp(v, 0.0, 1.0)) * c * 0.56;
	return 1.0 - smoothstep(rad - 0.6, rad + 0.6, length(f) * c);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	// TEXTURE arrives in canvas space (linear on the HDR 2D canvas): work in sRGB.
	vec3 c = mix(t.rgb, pow(max(t.rgb, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
	float a = t.a;
	float lum = dot(c, vec3(0.3333));
	bool shadow = max(c.r, max(c.g, c.b)) < 0.07;
	if (state >= 3) {
		c = mix(vec3(0.975, 0.97, 0.955), vec3(0.8, 0.79, 0.77), clamp((0.85 - lum) * 1.6, 0.0, 1.0));
		if (state == 4) {
			c = mix(c, sig, 0.22);
		}
		a *= shadow ? 0.12 : (state == 4 ? 0.55 : 0.32);
	} else if (!shadow) {
		if (state == 2) {
			vec2 p = UV * rect_px + offset_px;
			float g = dots(p, clamp((0.9 - lum) * 1.3, 0.0, 1.0), cell);
			c = mix(c * mix(vec3(1.0), tint, 0.3), tint * 0.82, g * 0.75);
		} else if (state == 1) {
			c = mix(c, c * tint, 0.18);
		}
	}
	COLOR = vec4(mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear), a);
}
