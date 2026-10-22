extends Control
## The War for Souls' map as a relief (style v4; the terrain-slab reference): the front's seven
## sectors as one slab of land, Heaven's terraced cliffs at the far end and Hell's cracked basin at
## the near end, rendered as clay in Blender (tools/blender/front_terrain.py, assets/art/ui/front/)
## and painted live by front_relief.gdshader with each sector's control. Over it, drawn here: HEAVEN
## and HELL, each sector's name down its column, its control on a paper tag at its front line, and
## the player's flag ("YOUR SOULS") on their sector; three cumulus drift over Heaven's cliffs. A tap (not a drag: the page scrolls) picks the
## sector under the finger (from the data image).
##   war   the Game.war() dictionary (sectors [{name, control}], focus)
##   grow  0..1, the lines rising from neutral (the opening animation)

signal picked(sector: int)

const DIR := "res://assets/art/ui/front/"
const SHADER := preload("res://src/ui/v4/front_relief.gdshader")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color(0.86, 0.66, 0.24)
## The campaign map's cumulus (a 3 x 2 atlas of 320 px cells), three of them over Heaven's cliffs.
const CLOUDS := "res://assets/art/worlds/clouds.png"
## [atlas cell, sector it starts over, depth t, width px, drift px/s]
const CLOUD_SET := [[0, 1.2, 0.02, 170.0, 5.0], [3, 4.4, -0.03, 140.0, 3.6], [5, 6.1, -0.05, 110.0, 6.2]]

var war: Dictionary = {}:
	set(v):
		war = v
		_sync()
var grow := 1.0:
	set(v):
		grow = v
		_sync()

var _img: TextureRect
var _mat: ShaderMaterial
var _data: Image
var _points: Array = []
var _down := Vector2.INF
var _clouds: Array[Control] = []


func _init() -> void:
	# PASS: a drag over the map still scrolls the page; only a tap (little movement) picks.
	mouse_filter = MOUSE_FILTER_PASS
	clip_contents = false


func _ready() -> void:
	_img = TextureRect.new()
	_img.name = "Relief"
	_img.mouse_filter = MOUSE_FILTER_IGNORE
	_img.texture = load(DIR + "relief.png")
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.size = size
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var dt: Texture2D = load(DIR + "data.png")
	_mat.set_shader_parameter("data_tex", dt)
	_mat.set_shader_parameter("rect_px", size)
	_img.material = _mat
	# Under this control's own drawing (the names, tags and flag).
	_img.show_behind_parent = true
	add_child(_img)
	move_child(_img, 0)
	if dt:
		_data = dt.get_image()
	var f := FileAccess.open(DIR + "points.json", FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_points = (j as Dictionary).get("points", [])
	_add_clouds()
	resized.connect(func() -> void:
		if _img:
			_img.size = size
			_mat.set_shader_parameter("rect_px", size)
		queue_redraw())
	_sync()


func _add_clouds() -> void:
	var tex: Texture2D = load(CLOUDS) if ResourceLoader.exists(CLOUDS) else null
	if tex == null or _points.is_empty():
		return
	for c: Array in CLOUD_SET:
		var at := AtlasTexture.new()
		at.atlas = tex
		var k := int(c[0])
		at.region = Rect2((k % 3) * 320, (k / 3) * 320, 320, 320)
		var tr := TextureRect.new()
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var w := float(c[3])
		tr.size = Vector2(w, w)
		var s := int(floor(float(c[1])))
		var base := _at(clampi(s, 0, 6), maxf(float(c[2]), 0.0)).lerp(_at(clampi(s + 1, 0, 6), maxf(float(c[2]), 0.0)), fmod(float(c[1]), 1.0))
		tr.position = base - Vector2(w * 0.5, w * 0.62) + Vector2(0, minf(float(c[2]), 0.0) * size.y)
		tr.set_meta("speed", float(c[4]))
		tr.modulate = Color(1, 1, 1, 0.94)
		add_child(tr)
		_clouds.append(tr)


## The clouds drift to the right over Heaven's end and come round again (still with Reduce motion).
func _process(delta: float) -> void:
	if _clouds.is_empty() or not Kit.motion_ok() or _points.is_empty():
		return
	var x0 := _at(0, 0.0).x - 90.0
	var x1 := _at(6, 0.0).x + 40.0
	for c in _clouds:
		c.position.x += float(c.get_meta("speed")) * delta
		if c.position.x > x1:
			c.position.x = x0 - c.size.x * 0.5


func _sync() -> void:
	if _mat:
		var secs: Array = war.get("sectors", [])
		var ctl := PackedFloat32Array()
		for i in 7:
			ctl.append(float(int((secs[i] as Dictionary).control)) / 10000.0 if i < secs.size() else 0.0)
		_mat.set_shader_parameter("control", ctl)
		_mat.set_shader_parameter("focus", int(war.get("focus", -1)))
		_mat.set_shader_parameter("grow", grow)
	queue_redraw()


## The sector under a point (local px), from the data image (-1 off the slab).
func sector_at(pos: Vector2) -> int:
	if _data == null or size.x <= 0.0 or size.y <= 0.0:
		return -1
	var px := Vector2i(clampi(int(pos.x / size.x * _data.get_width()), 0, _data.get_width() - 1),
		clampi(int(pos.y / size.y * _data.get_height()), 0, _data.get_height() - 1))
	var r := _data.get_pixelv(px).r
	return clampi(int(floor(r * 7.0)), 0, 6) if r > 0.02 else -1


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_down = mb.position
		return
	if _down != Vector2.INF and mb.position.distance_to(_down) < 14.0:
		var s := sector_at(mb.position)
		if s >= 0:
			picked.emit(s)
	_down = Vector2.INF


## A point on sector s's centre line at depth t (0 Heaven's end .. 1 Hell's), in local px.
func _at(s: int, t: float) -> Vector2:
	if s < 0 or s >= _points.size():
		return Vector2.ZERO
	var line: Array = _points[s]
	var k := clampf(t, 0.0, 1.0) * float(line.size() - 1)
	var i := mini(int(k), line.size() - 2)
	var a: Array = line[i]
	var b: Array = line[i + 1]
	var fr := k - float(i)
	return Vector2(lerpf(float(a[0]), float(b[0]), fr) * size.x, lerpf(float(a[1]), float(b[1]), fr) * size.y)


func _draw() -> void:
	var secs: Array = war.get("sectors", [])
	if _points.is_empty():
		return
	var f := Kit.font("mono_bold")
	var fc := Kit.font("compressed")
	draw_string(fc, Vector2(4, 38), "HEAVEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, INK)
	draw_string(f, Vector2(4, 56), "↓ HEAVEN PUSHES DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, 0.6))
	draw_string(fc, Vector2(4, size.y - 18), "HELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, SIG)
	draw_string(f, Vector2(4, size.y - 2), "↑ HELL PUSHES UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(INK, 0.6))
	var fo := int(war.get("focus", -1))
	for i in mini(secs.size(), _points.size()):
		var s: Dictionary = secs[i]
		var c := int(s.control)
		var line_t := 0.5 + float(c) / 10000.0 * 0.44 * grow
		# The name down its column from Heaven's end, outlined in paper so it reads on either side.
		var a := _at(i, 0.12)
		var b := _at(i, 0.4)
		var ang := (b - a).angle()
		draw_set_transform(a + Vector2(5, 0), ang, Vector2.ONE)
		var nm := str(s.name).to_upper()
		draw_string_outline(f, Vector2.ZERO, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(PAPER, 0.9))
		draw_string(f, Vector2.ZERO, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SIG if i == fo else INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# The control on a paper tag just below its front.
		var at := _at(i, line_t)
		var pct := "%+d%%" % roundi(float(c) / 100.0) if c != 0 else "0%"
		var tag := Rect2(at + Vector2(-25, 8), Vector2(50, 18))
		draw_rect(tag, Color(PAPER, 0.96))
		draw_rect(Rect2(tag.position, Vector2(3, tag.size.y)), GOLD if c > 0 else (SIG if c < 0 else INK))
		draw_string(f, tag.position + Vector2(6, 13), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	# The player's flag on their sector's front.
	if fo >= 0 and fo < mini(secs.size(), _points.size()):
		var lt := 0.5 + float(int((secs[fo] as Dictionary).control)) / 10000.0 * 0.44 * grow
		var base := _at(fo, lt)
		var top := base + Vector2(0, -78)
		draw_line(base + Vector2(0, -2), top, SIG, 3.0, true)
		draw_colored_polygon(PackedVector2Array([top, top + Vector2(34, 10), top + Vector2(0, 20)]), SIG)
		draw_rect(Rect2(top + Vector2(-44, -26), Vector2(88, 18)), Color(PAPER, 0.96))
		draw_string(f, top + Vector2(-44, -12), "YOUR SOULS", HORIZONTAL_ALIGNMENT_CENTER, 88, 10, SIG)
