extends Control
## Technical rule line used by Kit.section_header and Kit.divider (style v2): a hairline
## that fades toward the outer end, with a short thick segment and two small ticks at the
## inner end (next to the title). The file keeps its old name so older references work.

## -1 = sits left of a title (inner end on the right), 1 = right of a title.
var direction: int = 1
var color := Color(1, 1, 1, 0.5)
var accent := Color("12a8f4")
## false = plain hairline (dividers).
var ornament := true


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 24.0), 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var cy := roundf(size.y * 0.5)
	if w < 4.0:
		return
	var inner_x := w if direction < 0 else 0.0
	var outer_x := 0.0 if direction < 0 else w
	draw_polyline_colors(PackedVector2Array([Vector2(outer_x, cy), Vector2(inner_x, cy)]),
		PackedColorArray([Color(color, 0.0), color]), 1.5, true)
	if not ornament:
		return
	# Short thick accent segment at the inner end, then two ticks further out.
	var seg := minf(26.0, w * 0.3)
	var out := float(direction) # direction away from the title
	var a0 := inner_x
	var a1 := inner_x + out * seg
	draw_line(Vector2(minf(a0, a1), cy), Vector2(maxf(a0, a1), cy), accent, 3.0, true)
	for i in 2:
		var tx := inner_x + out * (seg + 7.0 + i * 7.0)
		draw_rect(Rect2(tx - 1.5, cy - 4.0, 3.0, 8.0), Color(color, 0.8 - i * 0.3))
