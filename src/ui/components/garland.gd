extends Control
## Cut-paper decorations on a thread across the Lobby poster on a real day that has them
## (data/calendar.json "decor", CalendarRules.decor; the pieces are Cycles renders from
## tools/blender/holiday_objects.py + finish_holiday.py in assets/art/ui/holiday/). The thread is
## taped at both ends and sags between; each piece hangs from it on a short drop and swings, a
## pendulum that leans with the phone's tilt, stirred by a faint draught and brushed by a passing
## thumb (any touch moving near it; the touch is never taken, so it still reaches what is under it).
## Its shadow falls on the paper below and to the right of it (the UI's key light is top left) and
## slides as it swings. The first time a day's decorations go up that year, the thread is strung
## across and the pieces drop onto it one by one; after that they are simply there.
## Reduce motion: hung, still, no brushing.

const DIR := "res://assets/art/ui/holiday/"
## Each set: the pieces along the thread, left to right: [name, scale, drop px, flipped].
const SETS := {
	"halloween": [["bat_p", 0.74, 12.0, false], ["bat_a", 0.92, 34.0, true], ["bat_b", 0.7, 16.0, false]],
	"christmas": [["snow_a", 0.78, 14.0, false], ["snow_c", 0.9, 30.0, false], ["snow_b", 0.72, 18.0, true]],
	"newyear": [["star_a", 0.82, 16.0, false], ["star_b", 0.7, 34.0, true], ["star_a", 0.66, 12.0, true]],
	"valentine": [["heart_a", 0.86, 14.0, false], ["heart_b", 0.92, 32.0, false], ["heart_a", 0.7, 18.0, true]],
}
const INK := SignalKit.INK
const TAPE := Color(0.93, 0.9, 0.8, 0.9)
## The key light is top left: shadows fall down and to the right, further for what hangs lower.
const SHADOW := Vector2(5.0, 9.0)

static var _manifest: Dictionary = {}

var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _sag := 40.0
var _pieces: Array[Dictionary] = []
var _t := 0.0
## The stringing-up (seconds since it started; < 0: not yet). -1 when it is simply hung.
var _hang_t := -1.0
var _rustle_at := -10.0
var _still := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## The set to hang (SETS key), the thread's two taped ends (local px) and its sag; animate strings
## it up (the first time this year) instead of showing it hung.
func setup(decor: String, a: Vector2, b: Vector2, sag: float, animate: bool) -> bool:
	if not SETS.has(decor):
		return false
	var man := _load_manifest()
	_a = a
	_b = b
	_sag = sag
	_still = not Kit.motion_ok()
	var list: Array = SETS[decor]
	var n := list.size()
	for i in n:
		var spec: Array = list[i]
		var name_s := str(spec[0])
		var info: Dictionary = man.get("pieces", {}).get(name_s, {})
		var tex: Texture2D = load(DIR + name_s + ".png") as Texture2D
		var sh: Texture2D = load(DIR + name_s + "_shadow.png") as Texture2D
		if tex == null or info.is_empty():
			continue
		var hp: Array = info.get("point", [tex.get_width() * 0.5, 0])
		var u := (i + 0.5) / n
		_pieces.append({"tex": tex, "shadow": sh, "pad": float(man.get("pad", 14)), "u": u,
			"hang": Vector2(float(hp[0]), float(hp[1])), "s": float(spec[1]), "drop": float(spec[2]),
			"flip": bool(spec[3]), "th": 0.0, "w": 0.0, "fall": 1.0, "fall_v": 0.0,
			"phase": float(i) * 1.7 + 0.4, "k": 38.0 + float(i % 3) * 9.0, "dropped": 1.0})
	if _pieces.is_empty():
		return false
	if animate and not _still:
		_hang_t = -0.25
		for p in _pieces:
			p.fall = 0.0
			p.dropped = 0.0
	return true


## Where the thread is at u (0..1 from end a to end b).
func thread_at(u: float) -> Vector2:
	return _a.lerp(_b, u) + Vector2(0.0, 4.0 * _sag * u * (1.0 - u))


func _process(delta: float) -> void:
	if _pieces.is_empty():
		return
	if _hang_t != -1.0:
		var ui := Kit.autoload("UI")
		if ui != null and bool(ui.get("hold_intro")):
			queue_redraw()
			return
		_hang_t += minf(delta, 1.0 / 30.0)
		_drop_in()
	if _still:
		return
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	var tilt := Kit.tilt
	for p in _pieces:
		# Gravity leans with the phone (tilted right, they hang toward the right); a faint draught.
		var rest := -tilt.x * 0.55
		var air := sin(_t * 0.9 + float(p.phase)) * 0.35 + sin(_t * 2.3 + float(p.phase) * 2.0) * 0.15
		var acc := -float(p.k) * (float(p.th) - rest) - 1.1 * float(p.w) + air
		p.w = float(p.w) + acc * dt
		p.th = clampf(float(p.th) + float(p.w) * dt, -0.9, 0.9)
		if float(p.dropped) > 0.0 and (absf(float(p.fall) - 1.0) > 0.001 or absf(float(p.fall_v)) > 0.01):
			# A dropped piece bounces on its drop: a stiff spring toward its full length.
			var fa := -260.0 * (float(p.fall) - 1.0) - 11.0 * float(p.fall_v)
			p.fall_v = float(p.fall_v) + fa * dt
			p.fall = maxf(0.0, float(p.fall) + float(p.fall_v) * dt)
	queue_redraw()


## The stringing-up: the thread runs from end a to end b over 0.45 s, then each piece drops onto it
## in turn (a small paper rustle each) and bounces on its drop.
func _drop_in() -> void:
	for i in _pieces.size():
		var p: Dictionary = _pieces[i]
		var at := 0.55 + i * 0.16
		if _hang_t >= at and float(p.dropped) == 0.0:
			p.dropped = 1.0
			p.fall = 0.15
			p.fall_v = 3.2
			p.w = (0.9 if i % 2 == 0 else -0.9) * 2.2
			if i % 2 == 0:
				Kit.sfx("rustle", 0.95 + i * 0.04)
	if _hang_t > 0.55 + _pieces.size() * 0.16 + 1.2:
		_hang_t = -1.0


func _input(event: InputEvent) -> void:
	if _still or _pieces.is_empty() or not is_visible_in_tree():
		return
	var moving := event is InputEventScreenDrag or (event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0)
	var pressed := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not moving and not pressed:
		return
	var local := make_input_local(event)
	var at: Vector2 = local.get("position")
	var vel := Vector2.ZERO
	if moving:
		vel = local.get("velocity")
	var stirred := false
	for p in _pieces:
		var c := _centre(p)
		var d := at.distance_to(c)
		if d > 70.0:
			continue
		var near := 1.0 - d / 70.0
		if moving:
			p.w = clampf(float(p.w) + vel.x * 0.0022 * near, -7.0, 7.0)
			stirred = stirred or absf(vel.x) > 300.0
		else:
			p.w = float(p.w) + (2.6 if at.x < c.x else -2.6) * near
			stirred = true
	if stirred and _t - _rustle_at > 0.35:
		_rustle_at = _t
		Kit.sfx("rustle", randf_range(0.9, 1.15))
		Kit.haptic(6, 0.25)


## A piece's middle on screen (local px), where a thumb brushes it.
func _centre(p: Dictionary) -> Vector2:
	var piv := thread_at(float(p.u))
	var tex: Texture2D = p.tex
	var s := float(p.s)
	var mid := Vector2(0.0, float(p.drop) * float(p.fall) - float(p.hang.y) * s + tex.get_height() * s * 0.5)
	return piv + mid.rotated(float(p.th))


func _draw() -> void:
	if _pieces.is_empty():
		return
	var strung := 1.0
	if _hang_t != -1.0:
		strung = clampf((_hang_t) / 0.45, 0.0, 1.0)
	var tilt := Kit.tilt
	var light := SHADOW + Vector2(-tilt.x, -tilt.y) * 10.0
	# Shadows first, on the paper: the thread's, then each piece's (further for what hangs lower).
	if strung > 0.0:
		var pts := _thread_points(strung)
		draw_polyline(_offset(pts, light * 0.45), Color(0, 0, 0, 0.1), 2.0, true)
	for p in _pieces:
		if float(p.dropped) == 0.0:
			continue
		var sh: Texture2D = p.shadow
		if sh == null:
			continue
		var s := float(p.s)
		var piv := thread_at(float(p.u))
		var depth := 1.0 + float(p.drop) * float(p.fall) / 60.0
		draw_set_transform(piv + light * depth, float(p.th), Vector2(-s if bool(p.flip) else s, s))
		var pad := float(p.pad)
		draw_texture(sh, Vector2(-float(p.hang.x) - pad, float(p.drop) * float(p.fall) / s - float(p.hang.y) - pad), Color(1, 1, 1, 0.42))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The thread and the scraps of tape holding it.
	if strung > 0.0:
		draw_polyline(_thread_points(strung), Color(INK, 0.82), 1.4, true)
	_tape(_a, -0.5)
	if strung >= 1.0:
		_tape(_b, 0.45)
	# Each piece on its drop.
	for p in _pieces:
		if float(p.dropped) == 0.0:
			continue
		var tex: Texture2D = p.tex
		var s := float(p.s)
		var piv := thread_at(float(p.u))
		var drop := float(p.drop) * float(p.fall)
		var dir := Vector2(0, 1).rotated(float(p.th))
		draw_line(piv, piv + dir * drop, Color(INK, 0.8), 1.1, true)
		draw_circle(piv, 1.6, Color(INK, 0.9))
		draw_set_transform(piv, float(p.th), Vector2(-s if bool(p.flip) else s, s))
		draw_texture(tex, Vector2(-float(p.hang.x), drop / s - float(p.hang.y)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _thread_points(upto: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var u := float(i) / n * upto
		pts.append(thread_at(u))
	return pts


func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(q + by)
	return out


## A scrap of masking tape over a thread end: a pale strip with torn ends and its faint shadow.
func _tape(at: Vector2, rot: float) -> void:
	var w := 30.0
	var h := 12.0
	var poly := PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(-w * 0.2, -h * 0.58), Vector2(w * 0.25, -h * 0.5),
		Vector2(w * 0.5, -h * 0.42), Vector2(w * 0.46, -h * 0.1), Vector2(w * 0.52, h * 0.25), Vector2(w * 0.47, h * 0.5),
		Vector2(0.0, h * 0.56), Vector2(-w * 0.48, h * 0.5), Vector2(-w * 0.53, h * 0.12), Vector2(-w * 0.47, -h * 0.2)])
	draw_set_transform(at + Vector2(1.5, 2.5), rot, Vector2.ONE)
	draw_colored_polygon(poly, Color(0, 0, 0, 0.08))
	draw_set_transform(at, rot, Vector2.ONE)
	draw_colored_polygon(poly, TAPE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _load_manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(DIR + "holiday.json", FileAccess.READ)
		if f:
			var j: Variant = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_manifest = j
	return _manifest
