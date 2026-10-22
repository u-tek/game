extends Control
## Notification mark (Kit.dot / Kit.set_dot), style v4 with restraint: a small solid signal dot
## printed flat (no rim, no gloss), smaller than the slot it is given. Pops in when shown and
## breathes, slowly.

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
	_tw.tween_interval(2.4)
	_tw.tween_property(self, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.32
	var c := size * 0.5
	draw_circle(c, r, Color("ff4b1f"), true, -1.0, true)
