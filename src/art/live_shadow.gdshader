shader_type canvas_item;
// Live Light's shadow (HeroSprite.live, iPhone 15 Pro and newer): her silhouette, softened (a
// 16-tap disc blur of the art's alpha, wider further from her), thrown onto the paper behind her
// away from the light, which follows the phone's tilt (the same light as live_light.gdshaderinc).
// Drawn under her rig, from her still image at the rest pose (soft enough to hide the breathing).

global uniform vec2 ui_tilt;
uniform float strength = 0.42;
// The throw in rest-space px at the reference light (and how far the tilt swings it).
uniform vec2 throw_px = vec2(90.0, 30.0);
uniform float spread = 14.0;    // blur radius in texels
uniform vec4 shadow_color : source_color = vec4(0.06, 0.03, 0.07, 1.0);

void vertex() {
	vec2 l = vec2(-0.5 + ui_tilt.x * 1.5, -0.6 + ui_tilt.y * 1.5);
	VERTEX += -l * throw_px;
}

void fragment() {
	float a = 0.0;
	for (int i = 0; i < 16; i++) {
		float t = float(i) / 16.0;
		float ang = t * 6.2831853 * 2.618;
		float r = sqrt(t + 0.03) * spread;
		a += textureLod(TEXTURE, UV + vec2(cos(ang), sin(ang)) * r * TEXTURE_PIXEL_SIZE, 2.0).a;
	}
	a /= 16.0;
	COLOR = vec4(shadow_color.rgb, a * strength);
}
