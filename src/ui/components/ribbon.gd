extends Control
## Banner plate (Kit.ribbon), style v2: a skewed parallelogram band in `color` with diagonal
## hatching on its right end, a darker under-plate offset behind it, thin tick lines out to
## both sides, and an uppercase Barlow Condensed title. Used for reward popups and battle
## results. Keeps the old API: text, color, text_color, font_size, set_text().

const KitBox := preload("res://src/ui/components/kit_box.gd")

var text := ""
var color := Color("12a8f4")
var text_color := Color.WHITE
var font_size := 44
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = text.to_upper()
	_label.add_theme_font_override("font", Kit.font("title"))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.clip_text = true
	add_child(_label)
	resized.connect(_layout)
	_layout()


## Changes the banner text (re-fits the font size).
func set_text(t: String) -> void:
	text = t
	if _label:
		_label.text = t.to_upper()
		_layout()


func _band() -> Rect2:
	var side := size.x * 0.1
	return Rect2(side, size.y * 0.08, size.x - side * 2.0, size.y * 0.8)


func _layout() -> void:
	if _label == null:
		return
	var b := _band()
	_label.position = b.position
	_label.size = b.size
	var fs := font_size
	var f := Kit.font("title")
	while fs > 22 and f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > b.size.x - b.size.y * 0.5 - 24.0:
		fs -= 2
	_label.add_theme_font_size_override("font_size", fs)
	queue_redraw()


func _draw() -> void:
	var ci := get_canvas_item()
	var b := _band()
	var sk := 0.32
	# Side tick lines.
	var cy := b.get_center().y
	var lc := Color(color.lightened(0.3), 0.85)
	draw_line(Vector2(0, cy), Vector2(b.position.x - 4.0, cy), lc, 2.0, true)
	draw_line(Vector2(b.end.x + 4.0, cy), Vector2(size.x, cy), lc, 2.0, true)
	draw_rect(Rect2(b.position.x - 18.0, cy - 5.0, 4.0, 10.0), lc)
	draw_rect(Rect2(b.end.x + 14.0, cy - 5.0, 4.0, 10.0), lc)
	# Under-plate (darker, offset down-right) and main band.
	var under := KitBox.shape_points(Rect2(b.position + Vector2(10, 7), b.size), 0.0, 0.0, 0, sk)
	KitBox.fill_poly(ci, under, color.darkened(0.55), color.darkened(0.65))
	var band := KitBox.shape_points(b, 0.0, 0.0, 0, sk)
	KitBox.soft_shadow(ci, band, Color(color, 0.45), 16.0)
	KitBox.fill_poly(ci, band, color.lightened(0.18), color.darkened(0.12), true)
	KitBox.hatch(ci, band, Color(1, 1, 1, 0.16), 9.0, 2.0, 0.66, 1.0)
	draw_line(band[0] + Vector2(2, 3), band[1] + Vector2(-2, 3), Color(1, 1, 1, 0.55), 2.0, true)
	KitBox.stroke_poly(ci, band, Color(1, 1, 1, 0.35), 1.5)
