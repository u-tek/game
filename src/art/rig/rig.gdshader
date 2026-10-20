shader_type canvas_item;
// HaloRig CUTOUT part shader (docs/dev/halorig.md section 6).
// vertex: BEND - progressive rotation about the bone pivot (mesh origin), growing with the
//         square of the distance along the part's rest axis, so long soft parts curve.
// fragment: shared tint (rig_tint.gdshaderinc).
#include "res://src/art/rig/rig_tint.gdshaderinc"

uniform float bend = 0.0;              // radians at the tip (t = 1)
uniform float bend_len = 100.0;        // rig units from pivot to the tip
uniform vec2 bend_axis = vec2(0.0, 1.0);

void vertex() {
	if (bend != 0.0) {
		float t = clamp(dot(VERTEX, bend_axis) / bend_len, 0.0, 1.25);
		float a = bend * t * t;
		float c = cos(a);
		float s = sin(a);
		VERTEX = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y);
	}
	part_pos = VERTEX;
	v_mod = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 o = halo_tint(tex, v_mod);
	COLOR = o;
}
