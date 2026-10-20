// A rendered growth that is alive (style v4 physical objects: the chrome and black thorns, the jelly
// and moss, the rival's thorns). Its growth map (tools/blender/growth_maps.py: R growth order from
// the root, G moss and fur, B LED beads and crystal, A the sway weight) drives:
//  - the reveal: pixels appear in growth order, a soft front running out from the root along every
//    branch (grow 0 -> 1, PhysicalKit tweens it once when the piece appears);
//  - the idle: a slow twist around the root and a slow wave running out along the branches, both
//    weighted by the sway weight (root still, tips a few px), moss and fur barely shimmering, beads
//    and crystal softly pulsing.
// The quad is grown by `margin` px on every side so swaying tips are not cut at the render's edge.
// Drawn on the piece's TextureRect (STRETCH_SCALE, the whole texture); `flip` mirrors like flip_h /
// flip_v. All colour maths is a multiply, made the same on the linear HDR canvas (ui_linear) and the
// plain sRGB one; nothing depends on bloom.
shader_type canvas_item;
global uniform float ui_linear;

uniform sampler2D grow_map : filter_linear, repeat_disable;
// Reveal progress: 0 = not yet sprouted, 1 = fully grown.
uniform float grow = 1.0;
// 0 = still (no idle motion).
uniform float motion = 1.0;
// The piece's drawn size (local px) and its root (UV of the texture).
uniform vec2 draw_size = vec2(300.0, 300.0);
uniform vec2 root = vec2(0.0, 0.0);
uniform vec2 flip = vec2(1.0, 1.0);
uniform float margin = 6.0;
// Tip sway (px), twist at the tips (px), shimmer (px), bead pulse (brightness), per-piece phase.
uniform float sway_px = 2.6;
uniform float twist_px = 3.0;
uniform float shimmer_px = 0.45;
uniform float pulse = 0.22;
uniform float seed = 0.0;
// The softness of the growing front (growth-order units).
uniform float front = 0.07;

varying vec4 tint;

void vertex() {
	tint = COLOR;
	vec2 d = sign(UV - vec2(0.5));
	VERTEX += d * flip * margin;
	UV += d * margin / max(draw_size, vec2(1.0));
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * motion + seed * 7.31;
	vec4 g = texture(grow_map, clamp(uv, vec2(0.0), vec2(1.0)));
	float w = g.a * g.a;
	// Twist: a small turn around the root (offset = angle x the perpendicular of the reach), scaled
	// so the furthest tip moves twist_px.
	vec2 reach = (uv - root) * draw_size;
	float len = max(max(draw_size.x, draw_size.y), 1.0);
	float ang = (twist_px / len) * (sin(t * 0.41) * 0.7 + sin(t * 0.23 + 1.9) * 0.3);
	vec2 off = vec2(-reach.y, reach.x) * ang * w * flip.x * flip.y;
	// Undulation: a slow wave running out from the root along the branches.
	float ph = g.r * 5.5 - t * 0.9;
	off += vec2(sin(ph + uv.y * 2.7), cos(ph * 0.83 + uv.x * 3.1 + 1.3)) * sway_px * w;
	// Moss and fur: a fine, barely there shimmer.
	off += vec2(sin(t * 2.3 + uv.y * 150.0 + uv.x * 41.0), cos(t * 1.9 + uv.x * 137.0 - uv.y * 23.0)) * shimmer_px * g.g * motion;
	vec2 suv = uv - off / draw_size;
	vec4 c = texture(TEXTURE, suv);
	vec4 gs = texture(grow_map, clamp(suv, vec2(0.0), vec2(1.0)));
	float inside = step(0.0, suv.x) * step(0.0, suv.y) * step(suv.x, 1.0) * step(suv.y, 1.0);
	// Beads and crystal pulse (each at its own phase), moss flickers a hair.
	float k = 1.0 + gs.b * pulse * (sin(t * 2.1 + suv.x * 11.0 + suv.y * 7.0) * 0.6 + 0.25) * motion
		+ gs.g * 0.035 * sin(t * 1.7 + suv.x * 60.0 + suv.y * 45.0) * motion;
	k = max(k, 0.0);
	c.rgb *= mix(k, pow(k, 2.2), ui_linear);
	// Reveal by growth order: a soft front running out along the branches.
	float f = grow * (1.0 + front);
	c.a *= (1.0 - smoothstep(f - front, f, gs.r)) * inside;
	COLOR = c * tint;
}
