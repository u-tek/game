extends RefCounted
## The survey map's printed legend (style v4 "Signal", poster look), from the owner's isometric
## terrain reference: the route profile (a sine-wave graph over a row of stage circles, the river's
## profile from the first stage to the boss, with its length and a slider), the survey data (area,
## relief, river length, climate in two units) and the scale bar with a north arrow.
## Drawn crisp in _draw; ink on paper.
##
##   var p := SurveyLegend.RouteProfile.new(); p.stages = [...]; p.size = ...   # tap = pressed(j)
##   var t := SurveyLegend.DataTable.new(); t.rows = [[label, value, alt], ...]
##   var s := SurveyLegend.ScaleBar.new()

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")


## The route profile: a row of overlapping circles, one per stage, with a sine wave threaded
## through them (solid up to the current stage, dashed beyond); stage dots on the baseline; a
## signal spark runs along the open stretch now and then (with the river's pulse); the caption,
## the length and a slider with the progress knob. A tap on the strip selects that stage.
class RouteProfile:
	extends Control
	signal pressed(index: int)
	## [{id, status, boss}] in order.
	var stages: Array = []
	var selected := -1
	## Route length (world units) and how much is open; the caption's name.
	var length_km := 0.0
	var title := "THE ROUTE"
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP

	func _ready() -> void:
		set_process(Kit.motion_ok())

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _geom() -> Array:
		var n := maxi(stages.size(), 1)
		var x0 := 8.0
		var x1 := size.x - 8.0
		var sp := (x1 - x0) / n
		var r := sp * 0.62
		var ym := 50.0
		return [n, x0, sp, r, ym]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			var g := _geom()
			var j := clampi(int(((event as InputEventMouseButton).position.x - float(g[1])) / float(g[2])), 0, int(g[0]) - 1)
			if j < stages.size():
				pressed.emit(j)
			accept_event()

	func _draw() -> void:
		if stages.is_empty():
			return
		var g := _geom()
		var n: int = g[0]
		var x0: float = g[1]
		var sp: float = g[2]
		var r: float = g[3]
		var ym: float = g[4]
		var f := Kit.font("mono")
		var fb := Kit.font("mono_bold")
		var cur := -1
		var reach := -1
		for j in stages.size():
			var stt := str(stages[j].get("status", ""))
			if stt != "locked":
				reach = j
			if stt == "current":
				cur = j
		# Caption and length.
		draw_string(fb, Vector2(x0, 10.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
		var tw := fb.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(fb, Vector2(x0 + tw + 8.0, 10.0), "[L]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, SIGNAL)
		var ln := "LENGTH  %d STAGES  |%5.1f KM" % [n, length_km]
		var lw := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(f, Vector2(size.x - 8.0 - lw, 10.0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.75))
		# The circles.
		for j in n:
			var c := Vector2(x0 + sp * (j + 0.5), ym)
			draw_arc(c, r, 0.0, TAU, 48, Color(INK, 0.22), 1.0, true)
		# The wave: touches the top of one circle and the bottom of the next.
		var pts := PackedVector2Array()
		var steps := n * 16
		for i in steps + 1:
			var x := x0 + (sp * n) * i / steps
			pts.append(Vector2(x, ym - r * cos(PI * (x - x0 - sp * 0.5) / sp)))
		var cut := 0
		if reach >= 0:
			cut = clampi(int(round((sp * (reach + 0.5)) / (sp * n) * steps)), 0, steps)
		if cut > 0:
			draw_polyline(pts.slice(0, cut + 1), INK, 2.0, true)
		if cut < steps:
			var rest := pts.slice(cut)
			for i in range(0, rest.size() - 1, 2):
				draw_line(rest[i], rest[i + 1], Color(INK, 0.45), 1.2, true)
		# The spark along the open stretch, in step with the river's pulse.
		if Kit.motion_ok() and cut > 1:
			var pk := fmod(_t, 5.0) / 1.6
			if pk < 1.0:
				var e := 1.0 - (1.0 - pk) * (1.0 - pk)
				var hi := int(e * cut)
				for q in 4:
					var a := maxi(hi - (q + 1) * 3, 0)
					var b := maxi(hi - q * 3, 0)
					if b > a:
						draw_polyline(pts.slice(a, b + 1), Color(SIGNAL, 0.95 - q * 0.22), 3.0, true)
		# Stage dots on the baseline.
		for j in stages.size():
			var c := Vector2(x0 + sp * (j + 0.5), ym)
			var stt := str(stages[j].get("status", "locked"))
			var boss := bool(stages[j].get("boss", false))
			if boss:
				var q2 := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
				draw_colored_polygon(q2, SIGNAL if stt == "current" else (INK if stt == "cleared" else PAPER))
				q2.append(q2[0])
				draw_polyline(q2, INK, 1.2, true)
			elif stt == "cleared":
				draw_circle(c, 3.6, INK)
			elif stt == "current":
				draw_circle(c, 5.0, SIGNAL)
				draw_circle(c, 2.0, PAPER)
			else:
				draw_circle(c, 3.4, PAPER)
				draw_arc(c, 3.4, 0.0, TAU, 16, Color(INK, 0.7), 1.0, true)
			if j == selected:
				draw_arc(c, 9.0, 0.0, TAU, 24, INK, 1.4, true)
		# The slider: first id, a rule with the knob at the progress, the boss id.
		var sy := size.y - 8.0
		var a_id := str(stages[0].get("id", ""))
		var b_id := str(stages[stages.size() - 1].get("id", ""))
		draw_string(f, Vector2(x0, sy + 3.0), a_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.8))
		var bw := f.get_string_size(b_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		# The slider runs under the left half (the stage's stamps land on the right half below).
		var rx0 := x0 + 34.0
		var rx1 := size.x * 0.5 - bw - 14.0
		draw_line(Vector2(rx0, sy), Vector2(rx1, sy), Color(INK, 0.35), 1.0, true)
		var kx := lerpf(rx0, rx1, clampf((float(cur if cur >= 0 else reach) + 0.5) / n, 0.0, 1.0))
		draw_rect(Rect2(kx - 3.0, sy - 3.0, 6.0, 6.0), INK)
		var tri := PackedVector2Array([Vector2(rx1 + 2.0, sy - 4.0), Vector2(rx1 + 8.0, sy), Vector2(rx1 + 2.0, sy + 4.0)])
		draw_colored_polygon(tri, INK)
		draw_string(f, Vector2(rx1 + 12.0, sy + 3.0), b_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.8))


## The survey data: a small mono table under a heading, label left, value right-aligned in two
## units ("– Area   55.6 km²  | 21.5 sq mi"), like the reference's data block.
class DataTable:
	extends Control
	## [[label, value, alt], ...] (alt: the second unit, may be "").
	var rows: Array = []
	var heading := "survey data"
	## The survey's coordinates, under the heading.
	var coords := ""

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Kit.font("mono")
		# A paper slip under it (it may lie over the model's far corner), with a hairline shadow.
		draw_rect(Rect2(-8, -6, size.x + 14, size.y + 4), Color(0, 0, 0, 0.12))
		draw_rect(Rect2(-10, -8, size.x + 14, size.y + 4), Color(PAPER, 0.96))
		draw_string(f, Vector2(0, 10), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, 0.75))
		var y := 30.0
		if coords != "":
			draw_string(f, Vector2(0, 26), coords, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
			y += 14.0
		draw_line(Vector2(0, y - 14.0), Vector2(size.x, y - 14.0), Color(INK, 0.35), 1.0)
		var c2 := size.x * 0.74
		for row: Array in rows:
			draw_string(f, Vector2(0, y), "– " + str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
			var v := str(row[1])
			var w := f.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(f, Vector2(c2 - 8.0 - w, y), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
			if row.size() > 2 and str(row[2]) != "":
				draw_string(f, Vector2(c2, y), "| " + str(row[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.6))
			y += 13.0


## The scale bar (alternating ink and paper blocks, 0 / 1 / 2 KM) under a north arrow and the
## sheet's scale.
class ScaleBar:
	extends Control
	var scale_text := "1:25 000"

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := Kit.font("mono")
		# North arrow: a diagonal arrow up and to the right, "NORTH" beside it.
		var a := Vector2(4, 34)
		var b := Vector2(26, 12)
		draw_line(a, b, INK, 1.2, true)
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([b, b - d * 8.0 + nrm * 4.0, b - d * 8.0 - nrm * 4.0]), INK)
		draw_string(f, Vector2(32, 18), "NORTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
		draw_string(f, Vector2(32, 30), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.7))
		# The bar.
		var y := 46.0
		var seg := (size.x - 30.0) / 4.0
		for k in 4:
			var r := Rect2(4.0 + k * seg, y, seg, 5.0)
			draw_rect(r, INK if k % 2 == 0 else PAPER)
			draw_rect(r, INK, false, 1.0)
		for k in 3:
			var lbl := str(k) if k < 2 else "2 KM"
			draw_string(f, Vector2(4.0 + k * seg * 2.0 - (0.0 if k < 2 else 6.0), y + 17.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
