extends Control
## Gold filigree line used by Kit.section_header and Kit.divider: a hairline that fades
## out toward the outer end, a thinner echo line, and a diamond + bead at the inner end.

## -1 = sits left of a title (bright end on the right), 1 = right of a title.
var direction: int = 1
var color := Color("e8c36a")
var ornament := true


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 24.0), 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var cy := roundf(size.y * 0.5)
	if w < 4.0:
		return
	var d := 6.0 if ornament else 0.0
	var inner_x := (w - d * 2.4) if direction < 0 else d * 2.4
	var outer_x := 0.0 if direction < 0 else w
	var bright := Color(color, 0.95)
	var clear := Color(color, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(outer_x, cy), Vector2(inner_x, cy)]),
		PackedColorArray([clear, bright]), 2.0, true)
	if not ornament:
		return
	# Echo line (shorter, thinner) below.
	var echo_end := inner_x + direction * 8.0
	var echo_start := lerpf(inner_x, outer_x, 0.55)
	draw_polyline_colors(PackedVector2Array([Vector2(echo_start, cy + 5), Vector2(echo_end, cy + 5)]),
		PackedColorArray([Color(color, 0.0), Color(color, 0.45)]), 1.0, true)
	# Diamond with a dark core and a bead beyond it.
	var cx := (w - d * 1.2) if direction < 0 else d * 1.2
	var dia := PackedVector2Array([Vector2(cx, cy - d), Vector2(cx + d, cy), Vector2(cx, cy + d), Vector2(cx - d, cy)])
	draw_colored_polygon(dia, Color(color, 1.0))
	var k := d * 0.45
	draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - k), Vector2(cx + k, cy), Vector2(cx, cy + k), Vector2(cx - k, cy)]), Color("3a2a10"))
	var loop := dia.duplicate()
	loop.append(dia[0])
	draw_polyline(loop, Color(color, 1.0), 1.0, true)
	var bead_x := lerpf(inner_x, outer_x, 0.12)
	draw_circle(Vector2(bead_x, cy), 2.2, Color(color, 0.9), true, -1.0, true)
