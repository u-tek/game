extends Control
## Decoration (Kit.deco): the v2 "technical" ornaments, drawn as geometry.
##   kind "hatch"     diagonal hatching over the whole rect
##   kind "barcode"   vertical bars of varied widths (decorative, not a real code)
##   kind "brackets"  thin L-brackets at the four corners
##   kind "chevrons"  `count` stacked upward chevrons (rarity mark), filled with `color`
##   kind "techline"  a hairline with a short thick start segment and small end ticks
##   kind "pips"      `count` small diamonds, the first `filled` ones solid (stars, ranks)
##   kind "dots"      a row of small squares
##   kind "cross"     a small "+" crosshair
## All colors via `color` (and `color2` for empty pips / secondary strokes).

const KitBox := preload("res://src/ui/components/kit_box.gd")

var kind := "hatch"
var color := Color(1, 1, 1, 0.12)
var color2 := Color(1, 1, 1, 0.25)
var spacing := 9.0
var line_width := 2.0
var count := 3
var filled := 3
## Barcode seed so neighbouring barcodes differ.
var seed_value := 7


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var ci := get_canvas_item()
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"hatch":
			var poly := PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)])
			KitBox.hatch(ci, poly, color, spacing, line_width)
		"barcode":
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var x := 0.0
			var unit := maxf(1.0, size.x / 26.0) if size.x >= size.y else maxf(1.0, size.y / 26.0)
			if size.x >= size.y:
				while x < size.x:
					var w := unit * float(rng.randi_range(1, 3))
					if rng.randf() < 0.62:
						draw_rect(Rect2(x, 0, minf(w, size.x - x), size.y), color)
					x += w + unit * float(rng.randi_range(1, 2))
			else:
				while x < size.y:
					var h := unit * float(rng.randi_range(1, 3))
					if rng.randf() < 0.62:
						draw_rect(Rect2(0, x, size.x, minf(h, size.y - x)), color)
					x += h + unit * float(rng.randi_range(1, 2))
		"brackets":
			KitBox.corner_marks(ci, r.grow(-line_width * 0.5), color, minf(spacing * 1.4, minf(size.x, size.y) * 0.4), line_width)
		"chevrons":
			var n := maxi(count, 1)
			var h := size.y / (n * 0.62 + 0.38)
			var w := size.x
			for i in n:
				var y0 := size.y - h - i * h * 0.62
				var th := h * 0.42
				var pts := PackedVector2Array([Vector2(0, y0 + h), Vector2(w * 0.5, y0), Vector2(w, y0 + h),
					Vector2(w - th * 1.1, y0 + h), Vector2(w * 0.5, y0 + th * 1.25), Vector2(th * 1.1, y0 + h)])
				var c := color.lightened(0.12 * i)
				draw_colored_polygon(pts, c)
				draw_polyline(_closed(pts), color.darkened(0.35), 1.0, true)
		"techline":
			var cy := size.y * 0.5
			draw_line(Vector2(0, cy), Vector2(size.x, cy), color, line_width, true)
			draw_rect(Rect2(0, cy - line_width * 1.5, minf(size.x * 0.18, 40.0), line_width * 3.0), color2)
			draw_rect(Rect2(size.x - 4.0, cy - 4.0, 4.0, 8.0), color2)
			draw_rect(Rect2(size.x - 12.0, cy - 2.5, 3.0, 5.0), color2)
		"pips":
			var n2 := maxi(count, 1)
			var d := minf(size.y, size.x / (n2 * 1.25))
			var gap := d * 0.25
			var total := n2 * d + (n2 - 1) * gap
			var x0 := (size.x - total) * 0.5
			for i in n2:
				var cx := x0 + i * (d + gap) + d * 0.5
				var cy2 := size.y * 0.5
				var k := d * 0.5
				var dia := PackedVector2Array([Vector2(cx, cy2 - k), Vector2(cx + k, cy2), Vector2(cx, cy2 + k), Vector2(cx - k, cy2)])
				if i < filled:
					draw_colored_polygon(dia, color)
				else:
					draw_colored_polygon(dia, Color(color2, color2.a * 0.5))
					draw_polyline(_closed(dia), color2, 1.0, true)
		"dots":
			var sq := size.y
			var x2 := 0.0
			while x2 + sq <= size.x:
				draw_rect(Rect2(x2, 0, sq, sq), color)
				x2 += sq * 2.0
		"cross":
			var c2 := size * 0.5
			var k2 := minf(size.x, size.y) * 0.5
			draw_line(c2 - Vector2(k2, 0), c2 + Vector2(k2, 0), color, line_width, true)
			draw_line(c2 - Vector2(0, k2), c2 + Vector2(0, k2), color, line_width, true)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var p := pts.duplicate()
	p.append(pts[0])
	return p
