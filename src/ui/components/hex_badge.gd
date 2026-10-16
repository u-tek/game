extends Control
## Hexagon badge (Kit.hex_badge): a pointy-top hexagon plate with a centered glyph or short
## text. Used for role marks on cards, tier numerals, nav centre, skill slots.

const KitBox := preload("res://src/ui/components/kit_box.gd")

var fill := Color("26282c")
var fill_bottom := Color("1a1b1e")
var border := Color(1, 1, 1, 0.55)
var border_width := 2.0
## Second, inner hex outline (0 alpha = none).
var inner := Color(1, 1, 1, 0.0)
## Flat-top instead of pointy-top.
var flat := false
## Colored roof over the top third (the faction mark on tier numerals; alpha 0 = none).
var cap := Color(0, 0, 0, 0)
## Glow around the plate (alpha 0 = none).
var glow := Color(0, 0, 0, 0)
var glow_size := 0.0

var _icon: TextureRect
var _label: Label


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(_layout)
	_layout()


## Glyph inside (assets/art/ui/<name>.svg), tinted `color`, at `scale` of the badge size.
func set_icon(icon_name: String, color: Color = Color.WHITE, scale_k: float = 0.56) -> void:
	if _icon == null:
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icon.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_icon)
	_icon.texture = Kit.icon_texture(icon_name)
	_icon.modulate = color
	_icon.set_meta("k", scale_k)
	_layout()


## Short text inside (a tier numeral, a number).
func set_text(text: String, color: Color = Color.WHITE, font_size: int = 0, weight: String = "title") -> void:
	if _label == null:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_label)
	_label.text = text
	_label.add_theme_font_override("font", Kit.font(weight))
	_label.add_theme_color_override("font_color", color)
	_label.set_meta("fs", font_size)
	_layout()


func _layout() -> void:
	var s := minf(size.x, size.y)
	if _icon:
		var k: float = _icon.get_meta("k", 0.56)
		_icon.size = Vector2(s * k, s * k)
		_icon.position = (size - _icon.size) * 0.5
	if _label:
		var fs: int = _label.get_meta("fs", 0)
		_label.add_theme_font_size_override("font_size", fs if fs > 0 else int(s * 0.5))
		_label.position = Vector2(0, s * 0.07 if cap.a > 0.0 else 0.0)
		_label.size = size
	queue_redraw()


func _draw() -> void:
	var ci := get_canvas_item()
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var pts := KitBox.hex_points(c, r - border_width * 0.5, flat)
	if glow.a > 0.0 and glow_size > 0.0:
		KitBox.soft_shadow(ci, pts, glow, glow_size)
	KitBox.fill_poly(ci, pts, fill, fill_bottom)
	if cap.a > 0.0 and not flat:
		# Pointy top: vertices 3 (210 deg), 4 (270 deg, top), 5 (330 deg).
		KitBox.add_convex(ci, PackedVector2Array([pts[3], pts[4], pts[5]]), cap)
	if inner.a > 0.0:
		KitBox.stroke_poly(ci, KitBox.offset_poly(pts, -maxf(4.0, r * 0.14)), inner, maxf(1.0, border_width * 0.6))
	if border.a > 0.0 and border_width > 0.0:
		KitBox.stroke_poly(ci, pts, border, border_width)
