extends Control
## The route between campaign stage nodes (style v2): a technical line. `points` are node
## centres (local px); segments up to `reached` (the index of the furthest unlocked node) are
## a solid cyan line with a soft glow and a white core, later ones a dashed grey trail.
## Small tick marks sit at each segment's midpoint.

var points := PackedVector2Array()
var reached := 0
var color := Color("12a8f4")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_points(p: PackedVector2Array, reached_index: int) -> void:
	points = p
	reached = reached_index
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	for i in points.size() - 1:
		var curve := _segment(points[i], points[i + 1])
		if i + 1 <= reached:
			draw_polyline(curve, Color(color, 0.18), 16.0, true)
			draw_polyline(curve, Color(0, 0, 0, 0.45), 8.0, true)
			draw_polyline(curve, color, 5.0, true)
			draw_polyline(curve, Color(1, 1, 1, 0.75), 1.5, true)
		else:
			_dashed(curve, Color(0, 0, 0, 0.45), 7.0)
			_dashed(curve, Color(0.78, 0.82, 0.88, 0.55), 3.0)
		# Tick pair at the midpoint, across the line.
		var m := curve[curve.size() / 2]
		var d := (curve[curve.size() / 2 + 1] - curve[curve.size() / 2 - 1]).normalized()
		var n := Vector2(-d.y, d.x)
		var tc := Color(1, 1, 1, 0.6) if i + 1 <= reached else Color(1, 1, 1, 0.25)
		for s: float in [-5.0, 5.0]:
			draw_line(m + d * s - n * 9.0, m + d * s + n * 9.0, tc, 2.0, true)


func _dashed(curve: PackedVector2Array, col: Color, width: float) -> void:
	var on := true
	var left := 14.0
	for k in range(1, curve.size()):
		var a := curve[k - 1]
		var b := curve[k]
		var seg := a.distance_to(b)
		var t := 0.0
		while t < seg:
			var step := minf(left, seg - t)
			var p0 := a.lerp(b, t / seg)
			var p1 := a.lerp(b, (t + step) / seg)
			if on:
				draw_line(p0, p1, col, width, true)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = 14.0 if on else 10.0


## A gentle S-curve from a to b (cubic with vertical tangents).
func _segment(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dy := (b.y - a.y) * 0.55
	var c1 := a + Vector2(0, dy)
	var c2 := b - Vector2(0, dy)
	var n := 18
	for k in n + 1:
		var t := k / float(n)
		var u := 1.0 - t
		out.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	return out
