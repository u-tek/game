// HaloRig WARP skinning (docs/dev/halorig.md section 8.4), shared by warp.gdshader and the
// Legendary foil (src/art/holo_foil.gdshader): GPU linear-blend skinning of the painted image's grid
// mesh. Each vertex has up to 4 bone influences (CUSTOM0 = b0,w0,b1,w1; CUSTOM1 = b2,w2,b3,w3; rigs
// of format 1 have 3, their w3 is 0) and the rest of its weight goes to body_bone. Per bone (uniform
// arrays, at most 64 bones):
//   bone_a = world basis (x.x, x.y, y.x, y.y)       bone_b = (origin.x, origin.y, rest pivot x, y)
//   bone_c = (rest axis x, y, length, bend radians)
// deform(b, p) = W_b * bend_b(p - rest_pivot_b), bend rotating by bend * t^2 along the axis.

uniform vec4 bone_a[64];
uniform vec4 bone_b[64];
uniform vec4 bone_c[64];
uniform int body_bone = 0;
// Format 2 rigs with turn data (docs/dev/halorig.md 11.5): CUSTOM1 = (b2 + w2*0.98, b3 + w3*0.98,
// depth, floor(head share*255) + body share*0.98). A turn shifts each point by its depth: the bangs
// over the face, the face over the skull, the back hair and wings the other way.
uniform bool packed_skin = false;
uniform vec2 head_turn = vec2(0.0);     // rig px per unit of depth
uniform vec2 body_turn = vec2(0.0);

// Influences 2 and 3 (bone, weight) of a vertex, packed or not.
void skin_tail(vec4 c1, out int b2, out float w2, out int b3, out float w3) {
	if (packed_skin) {
		b2 = int(floor(c1.x));
		w2 = fract(c1.x) / 0.98;
		b3 = int(floor(c1.y));
		w3 = fract(c1.y) / 0.98;
	} else {
		b2 = int(c1.x + 0.5);
		w2 = c1.y;
		b3 = int(c1.z + 0.5);
		w3 = c1.w;
	}
}

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

// The skinned position of rest-space point p with the vertex's CUSTOM0 / CUSTOM1 influences.
vec2 warp_skin(vec2 p, vec4 c0, vec4 c1) {
	float w0 = c0.y;
	float w1 = c0.w;
	int b2;
	float w2;
	int b3;
	float w3;
	skin_tail(c1, b2, w2, b3, w3);
	float wb = max(0.0, 1.0 - w0 - w1 - w2 - w3);
	vec2 o = deform(int(c0.x + 0.5), p) * w0 + deform(int(c0.z + 0.5), p) * w1
		+ deform(b2, p) * w2 + deform(body_bone, p) * wb;
	if (w3 > 0.0) {
		o += deform(b3, p) * w3;
	}
	if (packed_skin) {
		float th = floor(c1.w) / 255.0;
		float tb = fract(c1.w) / 0.98;
		o += (head_turn * th + body_turn * tb) * c1.z;
	}
	return o;
}
