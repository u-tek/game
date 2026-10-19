// Emissive light tube (style v4 "Signal"): a white-hot capsule core with a coloured halo that breathes
// and, now and then, flickers like a real tube. Drawn on a ColorRect with room for the halo
// (LightStrip, src/ui/components/plate.gd).
shader_type canvas_item;
// 1 when the canvas is linear HDR (viewport hdr_2d), 0 when it is plain sRGB (main.gd sets it).
global uniform float ui_linear;
render_mode blend_add;

uniform vec2 rect_size = vec2(40.0, 200.0);
// Capsule from a to b (px), core radius.
uniform vec2 a = vec2(20.0, 20.0);
uniform vec2 b = vec2(20.0, 180.0);
uniform float core = 4.0;
uniform vec4 color = vec4(1.0, 0.33, 0.12, 1.0);
uniform float intensity = 1.0;
uniform float halo = 18.0;
uniform float breathe = 0.25;
uniform float period = 3.0;
uniform float flicker = 1.0;
uniform float phase = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 pa = p - a;
	vec2 ba = b - a;
	float hcl = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	float d = length(pa - ba * hcl) - core;
	float t = TIME + phase;
	float k = intensity * (1.0 - breathe * 0.5 + breathe * 0.5 * sin(t * 6.2831853 / period));
	// Flicker: a few frames dim every several seconds.
	float slot = floor(t * 14.0);
	if (flicker > 0.0 && hash(slot + phase * 13.0) > 0.985) {
		k *= 0.45;
	}
	float core_a = clamp(0.5 - d, 0.0, 1.0);
	float glow = exp(-max(d, 0.0) / halo) * 0.55 + exp(-max(d, 0.0) / (halo * 0.25)) * 0.45;
	vec3 hot = mix(color.rgb, vec3(1.0, 0.97, 0.94), 0.75);
	// HDR: the core runs well above 1.0 so the bloom pass catches it.
	vec3 col = hot * core_a * k * 1.35 + color.rgb * glow * k * 0.55 * (1.0 - core_a);
	// sRGB terms to the linear HDR canvas (the core stays far above 1.0 and blooms).
	COLOR = vec4(mix(max(col, vec3(0.0)), pow(max(col, vec3(0.0)), vec3(2.2)), ui_linear), 1.0);
}
