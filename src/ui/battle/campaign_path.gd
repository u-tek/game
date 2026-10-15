extends Control
## The winding road between campaign stage nodes. `points` are node centers (local px);
## segments up to `reached` (the index of the furthest unlocked node) are a gilded road,
## later ones a faint dotted trail.

var points := PackedVector2Array()
var reached := 0
var color := Color("f2c14e")


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
			draw_polyline(curve, Color(0.05, 0.02, 0.1, 0.55), 22.0, true)
			draw_polyline(curve, color.darkened(0.35), 14.0, true)
			draw_polyline(curve, color, 8.0, true)
			draw_polyline(curve, Color(1, 0.95, 0.8, 0.55), 2.5, true)
		else:
			draw_polyline(curve, Color(0.05, 0.02, 0.1, 0.35), 12.0, true)
			# Dots along the curve at even spacing.
			var total := 0.0
			var next_dot := 10.0
			for k in range(1, curve.size()):
				var a2 := curve[k - 1]
				var b2 := curve[k]
				var seg2 := a2.distance_to(b2)
				while next_dot <= total + seg2:
					var p := a2.lerp(b2, (next_dot - total) / maxf(seg2, 0.001))
					draw_circle(p, 4.0, Color(0.75, 0.7, 0.95, 0.45), true, -1.0, true)
					next_dot += 24.0
				total += seg2


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
