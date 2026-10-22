extends RefCounted
## Drawn print pieces for the v4 poster sheets (docs/dev/ui-style-v4.md section 0): dialogs, the
## reward receipt, toasts, the Sanctum sheet, Settings, the loading veil and the boot poster. Kit
## builds them (Kit.tick_rule, Kit.fill_dial, Kit.reward_receipt, Kit.loading_veil ...); screens
## normally never touch these classes directly.
##
##   TickRule   a hairline with ticks (optionally a meter: the first `filled` part in signal)
##   Dial       a printed fill dial: a ring of 60 ticks, the filled ones in signal, a signal arc
##   Zigzag     the torn edge of a receipt
##   Leader     a dotted leader line (receipt rows: name ........ amount)
##   CropMarks  printer's crop marks at the four corners of a sheet
##   Sweep      an indeterminate printed progress rule (a signal run sliding along the ticks)


class TickRule:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.55)
	## Minor tick spacing (px) and every how many ticks a long one is drawn.
	var step := 12.0
	var major := 5
	var tick := 4.0
	## A short signal bar over the start of the rule (transparent = none).
	var lead := Color(0, 0, 0, 0)
	var lead_w := 34.0
	## 0..1: a meter; the ticks up to this fraction are drawn tall in fill_color. < 0 = a plain rule.
	var filled := -1.0
	var fill_color := Color("ff4b1f")
	var ticks := true

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_filled(v: float) -> void:
		filled = clampf(v, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var y := roundf(size.y * 0.5) + 0.5
		var w := size.x
		draw_line(Vector2(0, y), Vector2(w, y), color, 1.0)
		if ticks:
			var n := int(floor(w / maxf(step, 2.0)))
			var meter := filled >= 0.0
			var lit := int(roundf(filled * n)) if meter else -1
			for i in n + 1:
				var x := roundf(i * w / maxf(1.0, float(n))) + 0.5
				var long := i % maxi(major, 1) == 0
				var h := tick * (2.0 if long else 1.0)
				if meter:
					h = tick * (2.6 if long else 1.8)
				var on := meter and i < lit
				draw_line(Vector2(x, y), Vector2(x, y - h), fill_color if on else color, 2.0 if on else 1.0)
		if lead.a > 0.0:
			draw_rect(Rect2(0, y - 1.5, minf(lead_w, w), 3.0), lead)


class Dial:
	extends Control
	var frac := 0.0
	var ink := Color("101113")
	var on := Color("ff4b1f")
	var count := 60

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_frac(v: float) -> void:
		var f := clampf(v, 0.0, 1.0)
		if absf(f - frac) > 0.0005:
			frac = f
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(c, r, 0.0, TAU, 128, Color(ink, 0.6), 1.0, true)
		draw_arc(c, r - 30.0, 0.0, TAU, 96, Color(ink, 0.3), 1.0, true)
		var lit := int(roundf(frac * count))
		for i in count:
			var a := -PI * 0.5 + TAU * float(i) / count
			var d := Vector2(cos(a), sin(a))
			var long := i % 5 == 0
			var hit := i < lit
			var r0 := r - 6.0
			var r1 := r - (20.0 if long or hit else 13.0)
			draw_line(c + d * r0, c + d * r1, on if hit else Color(ink, 0.6 if long else 0.4), 2.6 if hit else (1.6 if long else 1.0), true)
		if frac > 0.002:
			draw_arc(c, r - 26.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 96, on, 3.0, true)
			var a1 := -PI * 0.5 + TAU * frac
			var tip := c + Vector2(cos(a1), sin(a1)) * (r - 26.0)
			draw_circle(tip, 4.0, on, true, -1.0, true)
		# Hairline crosshair ticks at the four quarters, inside the inner ring.
		for q in 4:
			var aq := PI * 0.5 * q
			var dq := Vector2(cos(aq), sin(aq))
			draw_line(c + dq * (r - 34.0), c + dq * (r - 42.0), Color(ink, 0.5), 1.0, true)


class Zigzag:
	extends Control
	var color := Color("f4f3ef")
	var tooth := 16.0
	var shadow := 0.12

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := maxi(1, int(ceil(size.x / tooth)))
		var w := size.x / n
		var pts := PackedVector2Array([Vector2(0, 0)])
		for i in n:
			pts.append(Vector2((i + 0.5) * w, size.y))
			pts.append(Vector2((i + 1) * w, 0))
		if shadow > 0.0:
			var sh := PackedVector2Array()
			for p in pts:
				sh.append(p + Vector2(0, 3))
			draw_colored_polygon(sh, Color(0, 0, 0, shadow))
		draw_colored_polygon(pts, color)


class Leader:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.35)
	var gap := 7.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := roundf(size.y * 0.62)
		var x := 3.0
		while x < size.x - 3.0:
			draw_rect(Rect2(x, y, 2, 2), color)
			x += gap


class CropMarks:
	extends Control
	var color := Color(0.063, 0.067, 0.075, 0.45)
	var arm := 12.0
	var inset := 10.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		for c: Array in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
				[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var o: Vector2 = c[0]
			var d: Vector2 = c[1]
			draw_line(o, o + Vector2(arm * d.x, 0), color, 1.0)
			draw_line(o, o + Vector2(0, arm * d.y), color, 1.0)


class Sweep:
	extends Control
	var ink := Color(0.96, 0.957, 0.94, 0.55)
	var on := Color("ff4b1f")
	var step := 10.0
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var y := roundf(size.y * 0.5) + 0.5
		draw_line(Vector2(0, y), Vector2(size.x, y), ink, 1.0)
		var n := int(floor(size.x / step))
		# A run of a quarter of the ticks slides back and forth (eased), lit in signal.
		var k := 0.5 - 0.5 * cos(_t * 2.4)
		var run := maxi(4, n / 4)
		var start := int(roundf(k * float(n - run)))
		for i in n + 1:
			var x := roundf(i * size.x / maxf(1.0, float(n))) + 0.5
			var lit := i >= start and i < start + run
			var h := 9.0 if lit else (8.0 if i % 5 == 0 else 4.0)
			draw_line(Vector2(x, y), Vector2(x, y - h), on if lit else ink, 2.0 if lit else 1.0)
