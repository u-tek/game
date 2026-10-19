extends Control
## A short burst of four-point glints flying out from a point (Kit.sparkle): reward tiles
## landing, level-ups, coins arriving. Draws only while it plays, then frees itself.

var color := Color.WHITE
var count := 6
var radius := 60.0
var star := 12.0
var duration := 0.6

var _t := 0.0
var _dirs: PackedVector2Array
var _spd: PackedFloat32Array

static var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_dirs = PackedVector2Array()
	_spd = PackedFloat32Array()
	var a0 := _rng.randf() * TAU
	for i in count:
		var a := a0 + TAU * float(i) / count + _rng.randf_range(-0.3, 0.3)
		_dirs.append(Vector2(cos(a), sin(a)))
		_spd.append(_rng.randf_range(0.55, 1.0))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_t = v
		queue_redraw(), 0.0, 1.0, duration)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var e := 1.0 - pow(1.0 - _t, 3.0)
	var fade := 1.0 - _t * _t
	for i in _dirs.size():
		var p := _dirs[i] * radius * e * _spd[i]
		var s := star * sin(PI * minf(_t * 1.6, 1.0)) * (0.6 + 0.4 * _spd[i])
		if s < 0.5:
			continue
		var w := s * 0.22
		var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(w, -w), p + Vector2(s, 0), p + Vector2(w, w),
			p + Vector2(0, s), p + Vector2(-w, w), p + Vector2(-s, 0), p + Vector2(-w, -w)])
		draw_colored_polygon(pts, Color(color, fade))
		draw_circle(p, w * 1.3, Color(1, 1, 1, fade), true, -1.0, true)
