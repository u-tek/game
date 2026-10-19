extends Control
## Small notice badge (Kit.new_badge / Kit.set_new): a red-orange rounded square with a
## white letter ("N" = new, "!" = attention) or a short count. round = blue circle style
## (used for "!" prompts). Pops in when shown, then breathes gently now and then (each badge
## on its own beat, so a screen of badges never pulses in lockstep).

const KitBox := preload("res://src/ui/components/kit_box.gd")

var text := "N"
var color := Color("f04a1d")
var round := false
var _tw: Tween

static var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		queue_redraw())
	visibility_changed.connect(_pop)
	pivot_offset = size * 0.5
	_pop()


func _pop() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if not is_visible_in_tree():
		return
	scale = Vector2(0.5, 0.5)
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(_breathe)


func _breathe() -> void:
	if not Kit.motion_ok():
		return
	_tw = create_tween().set_loops()
	_tw.tween_interval(_rng.randf_range(1.6, 2.6))
	_tw.tween_property(self, "scale", Vector2(1.14, 1.14), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "scale", Vector2(0.96, 0.96), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var ci := get_canvas_item()
	var r := Rect2(Vector2.ZERO, size)
	var s := minf(size.x, size.y)
	var pts: PackedVector2Array
	if round:
		pts = KitBox.shape_points(r, s * 0.5, 0.0, 0, 0.0, 10)
	else:
		pts = KitBox.shape_points(r, s * 0.22, 0.0, 0, 0.0, 4)
	KitBox.soft_shadow(ci, pts, Color(0, 0, 0, 0.45), s * 0.12, Vector2(0, s * 0.05))
	KitBox.fill_poly(ci, pts, color.lightened(0.18), color.darkened(0.08))
	KitBox.stroke_poly(ci, KitBox.offset_poly(pts, -1.0), Color(1, 1, 1, 0.55), maxf(1.0, s * 0.05))
	var f := Kit.font("title")
	var fs := int(s * 0.74)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var pos := Vector2((size.x - tw.x) * 0.5, (size.y + asc - desc) * 0.5 - s * 0.02)
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
