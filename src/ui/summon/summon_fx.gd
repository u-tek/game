extends RefCounted
## Shared bits of the summon sequence (src/ui/summon/): the additive blend material, easing
## curves and a smooth noise for camera shake. The material is built once and reused, so the
## per-frame effects allocate nothing.

static var _add: CanvasItemMaterial


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


static func smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Smooth pseudo-random wave in -1..1 (sum of sines), for camera shake.
static func wave(t: float, seed_k: float) -> float:
	return sin(t * 39.1 + seed_k) * 0.55 + sin(t * 67.3 + seed_k * 2.3) * 0.3 + sin(t * 23.7 + seed_k * 5.1) * 0.15


## A zoom with a pan between two framings (window centre x, y, scale): the window's size moves on a
## log scale and its centre with the size, so the move reads as one lift, not a slide and a zoom.
static func zoom_pan(a: Vector3, b: Vector3, k: float) -> Vector3:
	var s := exp(lerpf(log(a.z), log(b.z), k))
	var wa := 1.0 / a.z
	var wb := 1.0 / b.z
	var f := k if absf(wb - wa) < 0.0001 else (1.0 / s - wa) / (wb - wa)
	return Vector3(lerpf(a.x, b.x, f), lerpf(a.y, b.y, f), s)


static func in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5
