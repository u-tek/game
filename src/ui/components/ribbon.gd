extends Control
## Ribbon banner (Kit.ribbon): a gold (or any color) band with folded, notched tails and a
## Marcellus title. Used for reward popups and battle results.

const OUTLINE := Color("2a1d3d")

var text := ""
var color := Color("f2c14e")
var text_color := Color("3d2306")
var font_size := 44
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_override("font", Kit.font("title"))
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
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
		_label.text = t
		_layout()


func _layout() -> void:
	if _label == null:
		return
	var tail := size.x * 0.12
	_label.position = Vector2(tail, 0)
	_label.size = Vector2(size.x - tail * 2.0, size.y * 0.78)
	# Shrink long titles to fit the band.
	var fs := font_size
	var f := Kit.font("title")
	while fs > 24 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _label.size.x - 16.0:
		fs -= 2
	_label.add_theme_font_size_override("font_size", fs)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var band_h := h * 0.78
	var tail := w * 0.12
	var drop := h * 0.22
	var dark := color.darkened(0.45)
	var darker := color.darkened(0.65)
	# Tails (behind), with a V notch.
	for side in [-1, 1]:
		var x0 := 0.0 if side < 0 else w
		var x1 := tail * 1.35 if side < 0 else w - tail * 1.35
		var notch := tail * 0.45 * (1.0 if side < 0 else -1.0)
		var pts := PackedVector2Array([
			Vector2(x1, drop), Vector2(x0, drop), Vector2(x0 + notch, drop + band_h * 0.5),
			Vector2(x0, drop + band_h), Vector2(x1, drop + band_h)])
		draw_colored_polygon(pts, dark)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, OUTLINE, 3.0, true)
		# Fold triangle between tail and band.
		var fx := tail if side < 0 else w - tail
		var fold := PackedVector2Array([Vector2(fx, band_h), Vector2(fx + (tail * 0.35 if side < 0 else -tail * 0.35), drop + band_h), Vector2(fx, drop + band_h)])
		draw_colored_polygon(fold, darker)
	# Main band with vertical gradient.
	var band := PackedVector2Array([Vector2(tail, 0), Vector2(w - tail, 0), Vector2(w - tail, band_h), Vector2(tail, band_h)])
	var light := color.lightened(0.45)
	var deep := color.darkened(0.18)
	draw_polygon(band, PackedColorArray([light, light, deep, deep]))
	# Sheen and trim lines.
	draw_line(Vector2(tail + 6, 5), Vector2(w - tail - 6, 5), Color(1, 1, 1, 0.55), 2.0, true)
	draw_line(Vector2(tail + 4, band_h - 7), Vector2(w - tail - 4, band_h - 7), Color(darker, 0.6), 2.0, true)
	var loop2 := band.duplicate()
	loop2.append(band[0])
	draw_polyline(loop2, OUTLINE, 3.0, true)
