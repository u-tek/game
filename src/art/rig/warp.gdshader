shader_type canvas_item;
// HaloRig WARP shader (docs/dev/halorig.md section 8.4): GPU linear-blend skinning of the
// painted image's grid mesh (warp_skin.gdshaderinc) and the shared tint. Legendary heroes shown
// large draw with src/art/holo_foil.gdshader instead (the same skinning plus the holographic foil).
#include "res://src/art/rig/rig_tint.gdshaderinc"
#include "res://src/art/rig/warp_skin.gdshaderinc"

void vertex() {
	vec2 p = VERTEX;
	part_pos = p;
	v_mod = COLOR;
	VERTEX = warp_skin(p, CUSTOM0, CUSTOM1);
}

void fragment() {
	vec4 o = halo_tint(texture(TEXTURE, UV), v_mod);
	COLOR = o;
}
