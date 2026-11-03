// Ink print: a battle hit's impression (src/ui/battle/press_layer.gd). The texture is an edge field,
// not a picture (tools/blender/finish_hit_fx.py: 8-bit grey, the printed edge at 0.5, rising inside
// the ink), cut crisply at any scale. The plate's colour and the lift ride on the draw's modulate:
// rgb is the ink (as any sprite's modulate), a = 1 - lift. As the ink lifts, the cut rises against
// the paper grain, so thin bristles and edges go first and the rest breaks up instead of fading.
// fade (the uniform) is a plain opacity for prints that stay, like a fallen echo's blot.
// Nothing here relies on bloom (the iPhone build has no HDR 2D): it is ink, blend_mix.
shader_type canvas_item;
render_mode unshaded;

// 1 when the canvas is linear HDR (the desktop): samples arrive linear and are taken back to the
// stored numbers, so the cut lands where it does on the iPhone (HDR 2D off).
global uniform float ui_linear;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
// 0 on phones that are not Pro (DeviceTier.pro): a clean cut, no grain bite.
uniform float grain_on = 1.0;
uniform float fade = 1.0;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

void fragment() {
	float f = texture(TEXTURE, UV).r;
	f = mix(f, pow(max(f, 0.0), 1.0 / 2.2), ui_linear);
	float lift = clamp(1.0 - v_mod.a, 0.0, 1.0);
	// The grain is anchored to the sheet's pixels, so it moves with the print and never swims.
	float g = texture(grain, UV / TEXTURE_PIXEL_SIZE / 256.0).r;
	g = mix(g, pow(max(g, 0.0), 1.0 / 2.2), ui_linear);
	float cut = 0.5 + lift * 0.5 + (g - 0.5) * (0.06 + 0.34 * lift) * grain_on;
	float w = fwidth(f) * 0.75 + 0.002;
	COLOR = vec4(v_mod.rgb, smoothstep(cut - w, cut + w, f) * fade);
}
