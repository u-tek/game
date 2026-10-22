// Live Light (iPhone 15 Pro and newer: DeviceTier.live_light; HeroSprite.live): the phone works out a
// relief of the painting every frame and relights her from a light that follows its tilt.
//   shape:  for each pixel, how far her silhouette's edge is in eight directions (four radii each,
//           32 alpha taps) gives a soft rounded surface: its slope leans toward the nearer edges;
//           the painting's own shading (its luminance slope) adds the folds and curves on top.
//   light:  from the upper left, swung by ui_tilt (about -0.6..0.6), never straight on.
//   adds:   a gentle wrap (lighter toward the light, a touch darker away), a sheen that slides over
//           the painted highlights (latex, chrome, wet skin) as the phone tilts, and a warm rim on
//           the silhouette's lit side. The face is kept almost as painted (live_face, rest space).
// Two parts: this file (uniforms and helpers, at the top level after the shader declares
// global uniform float ui_linear; global uniform vec2 ui_tilt;) and live_light_body.gdshaderinc,
// included inside fragment() after `vec4 o` holds her colour (it reads TEXTURE, UV,
// TEXTURE_PIXEL_SIZE and part_pos, the rest-space position, and updates o). Built-in samplers can't
// be passed to functions on every renderer, hence the snippet. Off (live_light 0): one uniform
// branch, no taps.

uniform float live_light = 0.0;
uniform vec4 live_face = vec4(0.0, -1050.0, 70.0, 60.0);

vec3 ll_srgb(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)), ui_linear);
}

vec3 ll_canvas(vec3 c) {
	return mix(c, pow(max(c, vec3(0.0)), vec3(2.2)), ui_linear);
}

float ll_luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Toward the light (screen y down): upper left at rest, swung by the tilt.
vec3 ll_light_dir() {
	return normalize(vec3(-0.5 + ui_tilt.x * 1.5, -0.6 + ui_tilt.y * 1.5, 0.75));
}


// Lights one pixel: her colour (canvas space), the relief normal, how deep inside the silhouette it
// is (0 at the edge, 1 well inside), the neighbourhood's luminance and the rest-space position.
vec3 live_light_shade(vec3 rgb, vec3 n, float h, float lavg, vec2 pp) {
	vec3 L = ll_light_dir();
	vec3 c = ll_srgb(rgb);
	float lum = ll_luma(c);
	vec2 fq = (pp - live_face.xy) / max(live_face.zw * vec2(1.3, 1.4), vec2(1.0));
	float body = smoothstep(0.8, 1.3, length(fq));
	float amp = mix(0.3, 1.0, body);
	// 1) the wrap
	float ndl = dot(n, L);
	c *= 1.0 + (ndl - 0.45) * 0.24 * amp;
	// 2) the sheen on what the painting already made glossy
	float gloss = clamp((lum - lavg) * 4.0, 0.0, 1.0) * smoothstep(0.3, 0.75, lum) + smoothstep(0.78, 0.96, lum) * 0.35;
	vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(n, hv), 0.0), 26.0);
	c += vec3(1.0, 0.96, 0.9) * spec * gloss * 0.6 * body;
	// 3) the rim on the lit side of the silhouette
	float edge = 1.0 - smoothstep(0.0, 0.3, h);
	float side = max(dot(normalize(n.xy + vec2(1e-4)), normalize(L.xy)), 0.0);
	c += vec3(1.0, 0.86, 0.68) * edge * side * side * 0.3 * amp;
	return ll_canvas(clamp(c, vec3(0.0), vec3(1.0)));
}
