// A living growth (the rarity language, src/ui/v4/rarity_kit.gd): one of the Blender growth renders
// (thorns, jelly and moss; assets/art/ui/physical/) that grows out of its poster corner and twists
// slowly there. Drawn on the piece's TextureRect:
//   grow     0..1  how far it has grown out of the corner: the piece shows up to that distance from
//                  its origin, behind an uneven living front (a summon eruption tweens it 0 -> 1)
//   breathe  0..1  the slow cycle that pulls the front back a little and lets it grow out again
//   twist    rad   the curl at the far tips: the piece turns around its corner by an angle that grows
//                  with the distance, swaying slowly, so the tips coil and uncoil
// Only the alpha and the sampling position change: colours pass through untouched (no ui_linear
// conversion needed). motion 0 (Reduce motion) holds it still at `grow`.
shader_type canvas_item;

// The poster corner in UV (the piece's manifest origin / its size).
uniform vec2 origin = vec2(0.15, 0.15);
// The piece's aspect (width / height), so distances are round.
uniform float aspect = 1.0;
uniform float grow = 1.0;
uniform float breathe = 0.0;
uniform float twist = 0.05;
uniform float speed = 0.35;
uniform float motion = 1.0;
uniform float phase = 0.0;
// How far the farthest tip is from the origin (UV units, aspect corrected).
uniform float reach = 1.25;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1)) + phase * 7.1) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The vertex colour (modulate and self_modulate), without the texture: fragment's COLOR already has
// the texture multiplied in at the untwisted UV.
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	float tm = TIME * motion * speed + phase;
	vec2 d = UV - origin;
	d.x *= aspect;
	float r = length(d);
	// The curl: the angle grows with the distance and sways (two slow waves so it never loops).
	float sway = sin(tm) * 0.7 + sin(tm * 0.61 + 1.3) * 0.3;
	float a = twist * sway * (r / reach) * (r / reach) * 2.0;
	float ca = cos(a);
	float sa = sin(a);
	vec2 q = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
	q.x /= aspect;
	vec2 uv = origin + q;
	vec4 c = texture(TEXTURE, uv);
	// Outside the piece: nothing (no edge smear from clamping).
	c.a *= step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	// The growing front: uneven, so it reads as growing along the stems rather than a circle.
	float g = clamp(grow, 0.0, 1.2) * (1.0 - breathe * 0.18 * (0.5 + 0.5 * sin(TIME * motion * speed * 0.7 + phase * 2.0)));
	float front = g * reach;
	float n = vnoise(uv * 9.0 + phase) * 0.16 - 0.08;
	float m = 1.0 - smoothstep(front - 0.07, front + 0.01, r + n);
	COLOR = vec4(c.rgb, c.a * m) * vcol;
}
