extends RefCounted
## Shared bits of the summon sequence (src/ui/summon/): cached soft textures, the additive
## blend material, easing curves and a smooth noise for camera shake. Everything here is
## built once and reused, so the per-frame effects allocate nothing.

static var _soft: GradientTexture2D
static var _ring: GradientTexture2D
static var _add: CanvasItemMaterial


## White radial dot with a soft falloff (draw it tinted: draw_texture_rect(..., color)).
static func soft_dot() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.18, Color(1, 1, 1, 0.62))
		g.add_point(0.45, Color(1, 1, 1, 0.2))
		g.add_point(0.75, Color(1, 1, 1, 0.05))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 128
		_soft.height = 128
	return _soft


## White soft ring (a shockwave): transparent centre, bright band near the edge.
static func ring() -> Texture2D:
	if _ring == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.62, Color(1, 1, 1, 0.0))
		g.add_point(0.86, Color(1, 1, 1, 0.55))
		g.add_point(0.93, Color(1, 1, 1, 1.0))
		_ring = GradientTexture2D.new()
		_ring.gradient = g
		_ring.fill = GradientTexture2D.FILL_RADIAL
		_ring.fill_from = Vector2(0.5, 0.5)
		_ring.fill_to = Vector2(0.5, 0.0)
		_ring.width = 256
		_ring.height = 256
	return _ring


## Additive blending: light adds up (glows, streaks, sparks). Shared by every effect node.
static func additive() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add


# ------------------------------------------------------------------ easing

## 0..1 progress of t between a and b (clamped).
static func k01(t: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if t >= b else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func out_cubic(x: float) -> float:
	var u := 1.0 - x
	return 1.0 - u * u * u


static func in_cubic(x: float) -> float:
	return x * x * x


static func out_expo(x: float) -> float:
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)


static func out_back(x: float, s: float = 1.70158) -> float:
	var u := x - 1.0
	return 1.0 + (s + 1.0) * u * u * u + s * u * u


static func out_sine(x: float) -> float:
	return sin(x * PI * 0.5)


static func smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Smooth pseudo-random wave in -1..1 (sum of sines), for camera shake.
static func wave(t: float, seed_k: float) -> float:
	return sin(t * 39.1 + seed_k) * 0.55 + sin(t * 67.3 + seed_k * 2.3) * 0.3 + sin(t * 23.7 + seed_k * 5.1) * 0.15


## Fills `quad` (4 points, preallocated) with a streak from `head` toward `tail`, `w0` wide
## at the head and `w1` at the tail.
static func streak(quad: PackedVector2Array, head: Vector2, tail: Vector2, w0: float, w1: float) -> void:
	var d := tail - head
	var n := Vector2(-d.y, d.x).normalized()
	quad[0] = head + n * w0 * 0.5
	quad[1] = tail + n * w1 * 0.5
	quad[2] = tail - n * w1 * 0.5
	quad[3] = head - n * w0 * 0.5
