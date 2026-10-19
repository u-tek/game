extends Control
## The Spire's printed exploded stack (style v4 "Signal", poster look; docs/dev/ui-style-v4.md):
## floors as octagonal plates pulled apart in isometric line art, drawn crisp in 2D with our own
## orthographic projection. Each plate: visible side faces (ink for cleared floors, signal red and
## glowing for the next floor, paper with strata for locked ones), a paper top with its floor number
## printed on it in true perspective, a ring and corner ticks; boss floors get a second rim and a
## signal band. Leaders run from each plate to a mono label column on the right. The stack sways
## slowly (off with Reduce motion) and turns with a drag.
##
##   var s := PlateStack.new(); s.floors = [{floor, state ("cleared"|"next"|"locked"), boss, label}]
##   s.size = ...; add_child(s)

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")
const SIDES := 8

## Bottom to top: {floor: int, state: String, boss: bool, label: String, sub: String}.
var floors: Array = []
## The bottom plate's radius; each floor above is `taper` smaller (the Spire narrows as it climbs).
var radius := 2.6
var taper := 0.08
var thickness := 0.3
var gap := 2.3
var pitch := -28.0
var yaw := 22.5
## Idle sway (degrees) and its period (s).
var sway := 9.0
var sway_period := 22.0
var ppu := 60.0
## Centre of the stack on screen (local px) and the x where the label column starts.
var center := Vector2.ZERO
var label_x := 0.0
## Fades the whole print (the locked Spire prints grey).
var muted := false

var _t := 0.0
var _drag := 0.0
var _holding := false
var _last_x := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_t += delta
	if not _holding:
		_drag = lerpf(_drag, 0.0, clampf(delta * 0.8, 0.0, 1.0))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_holding = (event as InputEventMouseButton).pressed
		_last_x = (event as InputEventMouseButton).position.x
	elif event is InputEventMouseMotion and _holding:
		var x := (event as InputEventMouseMotion).position.x
		_drag += (x - _last_x) * 0.35
		_last_x = x


func _yaw() -> float:
	var y := yaw + _drag
	if Kit.motion_ok():
		y += sin(_t * TAU / sway_period) * sway
	return deg_to_rad(y)


## World (x, y, z) to local px.
func project(p: Vector3) -> Vector2:
	var t := _yaw()
	var pr := deg_to_rad(pitch)
	var sx := p.x * cos(t) - p.z * sin(t)
	var sy := p.x * sin(t) * sin(pr) + p.y * cos(pr) + p.z * cos(t) * sin(pr)
	return center + Vector2(sx, -sy) * ppu


func _ring(y: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in SIDES:
		var a := TAU * (i + 0.5) / SIDES
		out.append(project(Vector3(cos(a) * r, y, sin(a) * r)))
	return out


## World y of floor slot k (0 = the bottom plate), centred on the stack's middle.
func slot_y(k: int) -> float:
	return (k - (floors.size() - 1) * 0.5) * gap


func radius_of(k: int) -> float:
	return radius * (1.0 - taper * k)


## Sets ppu and the centre so the stack fills a box of `box` px (labels to the right of it).
func fit(box: Vector2) -> void:
	var n := maxi(floors.size(), 1)
	var c := cos(deg_to_rad(-pitch))
	var sn := sin(deg_to_rad(-pitch))
	var units := (n - 1) * gap * c + radius * sn + radius_of(n - 1) * sn + thickness + 0.6
	ppu = clampf((box.y - 30.0) / units, 28.0, 58.0)
	center = Vector2(box.x * 0.36, box.y * 0.5 + 4.0)
	label_x = center.x + radius * ppu + 30.0


func _draw() -> void:
	if floors.is_empty():
		return
	var t := _yaw()
	var cam := Vector2(sin(t), cos(t))
	var f := Kit.font("mono_bold")
	var fm := Kit.font("mono")
	var fw := Kit.font("wide_black")
	var ink := INK if not muted else Color(INK, 0.45)
	# The spine: a hairline axis through every plate.
	var ytop := slot_y(floors.size() - 1) + 1.0
	var ybot := slot_y(0) - 1.0
	_dashed(project(Vector3(0, ybot, 0)), project(Vector3(0, ytop, 0)), Color(ink, 0.45), 1.0, 5.0, 4.0)
	for k in floors.size():
		var fl: Dictionary = floors[k]
		var state := str(fl.get("state", "locked"))
		var boss := bool(fl.get("boss", false))
		var y := slot_y(k)
		var rk := radius_of(k)
		var top := _ring(y + thickness * 0.5, rk)
		var bot := _ring(y - thickness * 0.5, rk)
		# Side faces facing the camera.
		for i in SIDES:
			var a := TAU * (i + 1.0) / SIDES
			var n := Vector2(cos(a), sin(a))
			# Faces turned away (or edge-on: a sliver would not triangulate) are skipped.
			if n.x * cam.x + n.y * cam.y <= 0.03:
				continue
			var j := (i + 1) % SIDES
			var quad := PackedVector2Array([top[i], top[j], bot[j], bot[i]])
			var light := 0.5 + 0.5 * (n.x * 0.6 - n.y * 0.8)
			var fill: Color
			match state:
				"next":
					fill = (SIGNAL * lerpf(1.25, 1.7, light)) if not muted else Color(SIGNAL, 0.5)
				"cleared":
					fill = Color("141517").lerp(Color("2a2c30"), light)
				_:
					fill = PAPER.darkened(0.04 + 0.1 * (1.0 - light))
			fill.a = 1.0
			draw_colored_polygon(quad, fill)
			if state == "locked" or muted:
				# Strata lines on the paper sides.
				for s in [0.33, 0.66]:
					draw_line(quad[0].lerp(quad[3], s), quad[1].lerp(quad[2], s), Color(ink, 0.35), 1.0, true)
			if boss:
				draw_line(quad[0].lerp(quad[3], 0.5), quad[1].lerp(quad[2], 0.5), SIGNAL if state != "next" else PAPER, 2.0, true)
			quad.append(quad[0])
			draw_polyline(quad, ink, 1.2, true)
		# The top: paper, outline, an inner ring, the floor number printed in perspective.
		draw_colored_polygon(top, PAPER)
		var tl := top.duplicate()
		tl.append(top[0])
		draw_polyline(tl, ink, 1.6 if state == "next" else 1.3, true)
		var inner := _ring(y + thickness * 0.5, rk * 0.8)
		inner.append(inner[0])
		draw_polyline(inner, Color(ink, 0.5), 1.0, true)
		if boss:
			var outer := _ring(y + thickness * 0.5, rk * 1.14)
			outer.append(outer[0])
			draw_polyline(outer, Color(SIGNAL, 0.9), 1.4, true)
		_print_on_top(y + thickness * 0.5, rk, "%03d" % int(fl.get("floor", 0)), fw, SIGNAL if state == "next" else ink)
		# Leader to the label column.
		var right := project(Vector3(0, y, 0))
		var edge := right
		for p in top:
			if p.x > edge.x:
				edge = p
		var lc := SIGNAL if state == "next" else ink
		var ly := edge.y
		draw_circle(edge, 2.5, lc)
		draw_line(edge, Vector2(label_x - 8.0, ly), Color(lc, 0.7), 1.0, true)
		draw_line(Vector2(label_x - 8.0, ly - 5), Vector2(label_x - 8.0, ly + 5), lc, 1.0, true)
		draw_string(f, Vector2(label_x, ly - 1.0), str(fl.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lc)
		var sub := str(fl.get("sub", ""))
		if sub != "":
			draw_string(fm, Vector2(label_x, ly + 13.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(lc, 0.75))


## Prints the floor number on a plate's top face, toward its front edge (clear of the plate
## above): an affine map of the plate's plane (exact for an orthographic view), so the number lies
## flat on the plate, turned to read along the view.
func _print_on_top(y: float, r: float, text: String, font: Font, col: Color) -> void:
	var o := project(Vector3(0, y, 0))
	var ex := (project(Vector3(1, y, 0)) - o) / ppu
	var ez := (project(Vector3(0, y, 1)) - o) / ppu
	var t := _yaw()
	var ax := ex * cos(t) - ez * sin(t)
	var az := ex * sin(t) + ez * cos(t)
	draw_set_transform_matrix(Transform2D(ax, az, o))
	var fs := int(r * ppu * 0.42)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(-w * 0.5, r * ppu * 0.45 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.92))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _dashed(a: Vector2, b: Vector2, c: Color, w: float, on: float, off: float) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var d := (b - a) / len
	var s := 0.0
	while s < len:
		draw_line(a + d * s, a + d * minf(s + on, len), c, w, true)
		s += on + off
