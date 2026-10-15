shader_type canvas_item;
// HaloRig WARP shader (docs/dev/halorig.md section 8.4): GPU linear-blend skinning of the
// painted image's grid mesh. Each vertex has up to 3 bone influences (CUSTOM0 = b0,w0,b1,w1;
// CUSTOM1 = b2,w2) and the rest of its weight goes to body_bone. Per bone (uniform arrays):
//   bone_a = world basis (x.x, x.y, y.x, y.y)       bone_b = (origin.x, origin.y, rest pivot x, y)
//   bone_c = (rest axis x, y, length, bend radians)
// deform(b, p) = W_b * bend_b(p - rest_pivot_b), bend rotating by bend * t^2 along the axis.
#include "res://src/art/rig/rig_tint.gdshaderinc"

uniform vec4 bone_a[32];
uniform vec4 bone_b[32];
uniform vec4 bone_c[32];
uniform int body_bone = 0;

vec2 deform(int b, vec2 p) {
	vec4 A = bone_a[b];
	vec4 B = bone_b[b];
	vec4 C = bone_c[b];
	vec2 l = p - B.zw;
	if (C.w != 0.0) {
		float t = clamp(dot(l, C.xy) / max(C.z, 1.0), 0.0, 1.25);
		float a = C.w * t * t;
		float c = cos(a);
		float s = sin(a);
		l = vec2(c * l.x - s * l.y, s * l.x + c * l.y);
	}
	return vec2(A.x * l.x + A.z * l.y, A.y * l.x + A.w * l.y) + B.xy;
}

void vertex() {
	vec2 p = VERTEX;
	float w0 = CUSTOM0.y;
	float w1 = CUSTOM0.w;
	float w2 = CUSTOM1.y;
	float wb = max(0.0, 1.0 - w0 - w1 - w2);
	vec2 r = deform(int(CUSTOM0.x + 0.5), p) * w0 + deform(int(CUSTOM0.z + 0.5), p) * w1
		+ deform(int(CUSTOM1.x + 0.5), p) * w2 + deform(body_bone, p) * wb;
	part_pos = p;
	VERTEX = r;
}

void fragment() {
	vec4 o = halo_tint(texture(TEXTURE, UV), COLOR);
	COLOR = o;
}
