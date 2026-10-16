extends Control
## Red-orange notification dot (Kit.dot / Kit.set_dot) with a light rim. Pops in when shown
## and breathes gently.

var _tw: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility)
	_on_resized()
	_on_visibility()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _on_visibility() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if not is_visible_in_tree():
		return
	scale = Vector2(0.4, 0.4)
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(_breathe)


func _breathe() -> void:
	_tw = create_tween().set_loops()
	_tw.tween_interval(1.2)
	_tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.35).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.35), true, -1.0, true)
	draw_circle(c, r, Color("f4f5f7"), true, -1.0, true)
	draw_circle(c, r - maxf(2.0, r * 0.2), Color("ee3b22"), true, -1.0, true)
	draw_circle(c - Vector2(0, r * 0.1), r - maxf(3.5, r * 0.36), Color("ff5a38"), true, -1.0, true)
