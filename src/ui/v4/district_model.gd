extends Control
## The district as an architect's maquette (the district screen's plan): the eight buildings of
## data/district.json in white clay on a paper ground slab with its street grid and the souls' road,
## rendered in Blender (tools/blender/district_models.py, assets/art/ui/district/), stacked back to
## front. Built buildings stand in clay (in the Horn Quarter, cast in black obsidian); a kept one takes
## its keeper's mark (her side's ink in halftone when she doubles it, gold for the Halo Quarter,
## signal for the Horn); unbuilt ones are frosted placeholders with their soul price, the next one
## warmed in signal. Drawn over them: each building's number on a paper tag, the prices, and a leader
## up from each kept roof (the screen hangs the keeper's portrait at its end, roof_point()).
## Arranging (arranging = true): the lots show as a faint grid; drag a building and it follows the
## finger lot by lot (the camera is orthographic, so a building on another lot is the same picture
## moved by a fixed offset), its footprint marked in ink where it fits and in signal where it doesn't;
## let go on a lot that fits and placed(i, x, y) is emitted (the screen stores it).
##   dist  the Game.district() dictionary (side, buildings [{i, open, keeper, doubled, souls, spot}], next)

signal placed(building: int, x: int, y: int)

const DIR := "res://assets/art/ui/district/"
const SHADER := preload("res://src/ui/v4/district_model.gdshader")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color(0.86, 0.66, 0.24)
## Building ids in data order (data/district.json).
const IDS: Array[String] = ["gate", "chapel", "market", "baths", "forge", "lounge", "archive", "spire"]

var dist: Dictionary = {}:
	set(v):
		dist = v
		if is_inside_tree():
			_rebuild()
var arranging := false:
	set(v):
		arranging = v
		mouse_filter = MOUSE_FILTER_STOP if v else MOUSE_FILTER_IGNORE
		_drag = -1
		if _overlay:
			_overlay.queue_redraw()
		if _lots_layer:
			_lots_layer.queue_redraw()

var _layout: Dictionary = {}
var _overlay: Control
var _lots_layer: Control         ## the lot grid and the dragged footprint, on the ground under the buildings
var _made: Array[Node] = []      ## the ground and buildings (the screen adds the keepers' portraits)
var _sprites: Dictionary = {}    ## building index -> its TextureRect
var _drag := -1                  ## the building being dragged (-1: none)
var _drag_from := Vector2.ZERO
var _drag_spot := Vector2i.ZERO  ## where it would land


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_layout = j
	_rebuild()
	resized.connect(_rebuild)


# ------------------------------------------------------------------ geometry

func _info(i: int) -> Dictionary:
	if i < 0 or i >= IDS.size():
		return {}
	return ((_layout.get("buildings", {}) as Dictionary).get(IDS[i], {}) as Dictionary)


## A ground point at lot coordinates (gx, gy), in local px.
func _ground(gx: float, gy: float) -> Vector2:
	var g: Dictionary = _layout.get("grid", {})
	if g.is_empty():
		return Vector2.ZERO
	var o: Array = g.o
	var x: Array = g.x
	var y: Array = g.y
	return Vector2((float(o[0]) + gx * float(x[0]) + gy * float(y[0])) * size.x, (float(o[1]) + gx * float(x[1]) + gy * float(y[1])) * size.y)


## Where building i stands now: the lot it is being dragged to, else its spot in dist.
func _spot(i: int) -> Vector2i:
	if i == _drag:
		return _drag_spot
	var bl: Array = dist.get("buildings", [])
	if i < bl.size():
		var s: Variant = (bl[i] as Dictionary).get("spot", null)
		if s is Array and (s as Array).size() == 2:
			return Vector2i(int(s[0]), int(s[1]))
	var d: Array = _info(i).get("spot", [0, 0])
	return Vector2i(int(d[0]), int(d[1]))


## How far building i's picture moves from where it was rendered (its data spot).
func _shift(i: int) -> Vector2:
	var d: Array = _info(i).get("spot", [0, 0])
	var s := _spot(i)
	return _ground(s.x, s.y) - _ground(float(d[0]), float(d[1]))


## The middle of a building's roof in local px (for the keeper portraits' leaders).
func roof_point(i: int) -> Vector2:
	var b := _info(i)
	if b.is_empty():
		return size * 0.5
	var r: Array = b.roof
	return Vector2(float(r[0]) * size.x, float(r[1]) * size.y) + _shift(i)


func _foot(i: int) -> Vector2:
	var ft: Array = _info(i).get("foot", [0.5, 0.5])
	return Vector2(float(ft[0]) * size.x, float(ft[1]) * size.y) + _shift(i)


func _wd(i: int) -> Vector2i:
	var b: Dictionary = DistrictRules.BUILDINGS[i]
	return Vector2i(int(b.w), int(b.d))


func _footprint(i: int, s: Vector2i) -> PackedVector2Array:
	var wd := _wd(i)
	return PackedVector2Array([_ground(s.x, s.y), _ground(s.x + wd.x, s.y), _ground(s.x + wd.x, s.y + wd.y), _ground(s.x, s.y + wd.y)])


func _current_layout() -> Dictionary:
	var lay := {}
	for i in IDS.size():
		var s := _spot(i)
		lay[str(i)] = [s.x, s.y]
	return lay


# ------------------------------------------------------------------ building

func _rebuild() -> void:
	for c in _made:
		if is_instance_valid(c):
			c.queue_free()
	_made.clear()
	_sprites.clear()
	if _layout.is_empty() or size.x <= 0.0:
		return
	var ground := TextureRect.new()
	ground.name = "Ground"
	ground.mouse_filter = MOUSE_FILTER_IGNORE
	ground.texture = load(DIR + "ground.png")
	ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ground.stretch_mode = TextureRect.STRETCH_SCALE
	ground.size = size
	ground.show_behind_parent = true
	add_child(ground)
	move_child(ground, 0)
	_made.append(ground)
	_lots_layer = Control.new()
	_lots_layer.name = "Lots"
	_lots_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_lots_layer.size = size
	_lots_layer.draw.connect(_draw_lots)
	add_child(_lots_layer)
	move_child(_lots_layer, 0)
	_made.append(_lots_layer)
	var bl: Array = dist.get("buildings", [])
	var tint := GOLD if str(dist.get("side", "")) == "heaven" else SIG
	var next_souls := int((dist.get("next", {}) as Dictionary).get("souls", -1))
	for i in mini(bl.size(), IDS.size()):
		var info := _info(i)
		if info.is_empty():
			continue
		var bd: Dictionary = bl[i]
		var rc: Array = info.rect
		var tr := TextureRect.new()
		tr.name = "B_" + IDS[i]
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = load(DIR + IDS[i] + ".png")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(float(rc[2]) * size.x, float(rc[3]) * size.y)
		var st := 0
		if not bool(bd.open):
			st = 4 if int(bd.souls) == next_souls else 3
		elif str(bd.keeper) != "":
			st = 2 if bool(bd.doubled) else 1
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("state", st)
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		m.set_shader_parameter("rect_px", tr.size)
		m.set_shader_parameter("obsidian", str(dist.get("side", "")) == "hell")
		var np := DIR + IDS[i] + "_n.png"
		if ResourceLoader.exists(np):
			m.set_shader_parameter("normal_tex", load(np))
			m.set_shader_parameter("has_normals", true)
		tr.material = m
		tr.set_meta("state", st)
		tr.set_meta("rect", rc)
		add_child(tr)
		_sprites[i] = tr
		_made.append(tr)
	_place_sprites()
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = Control.new()
		_overlay.name = "Labels"
		_overlay.mouse_filter = MOUSE_FILTER_IGNORE
		_overlay.draw.connect(_draw_labels)
		add_child(_overlay)
	_overlay.size = size
	move_child(_overlay, _made.size())
	_overlay.queue_redraw()


## Puts every building's picture on its lot and restacks them back to front.
func _place_sprites() -> void:
	var order: Array = _sprites.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa := _spot(a)
		var sb := _spot(b)
		var wa := _wd(a)
		var wb := _wd(b)
		return sa.x + sa.y + (wa.x + wa.y) * 0.5 < sb.x + sb.y + (wb.x + wb.y) * 0.5)
	var k := 2
	for i: int in order:
		var tr: TextureRect = _sprites[i]
		var rc: Array = tr.get_meta("rect")
		tr.position = Vector2(float(rc[0]) * size.x, float(rc[1]) * size.y) + _shift(i)
		(tr.material as ShaderMaterial).set_shader_parameter("offset_px", tr.position)
		move_child(tr, k)
		k += 1


# ------------------------------------------------------------------ arranging

## The building under a point (local px): the frontmost whose footprint, raised to its roof, holds it.
func _building_at(p: Vector2) -> int:
	var best := -1
	var best_depth := -1.0e9
	for i: int in _sprites:
		var fp := _footprint(i, _spot(i))
		var lift := minf(roof_point(i).y - _foot(i).y, 0.0)
		var r := Rect2(fp[0], Vector2.ZERO)
		for q in fp:
			r = r.expand(q)
			r = r.expand(q + Vector2(0, lift))
		if r.has_point(p):
			var s := _spot(i)
			var dpt := float(s.x + s.y)
			if dpt > best_depth:
				best_depth = dpt
				best = i
	return best


## The lot offset for a drag of `delta` px (the inverse of the grid's axes), rounded to whole lots.
func _lots(delta: Vector2) -> Vector2i:
	var ax := _ground(1, 0) - _ground(0, 0)
	var ay := _ground(0, 1) - _ground(0, 0)
	var det := ax.x * ay.y - ax.y * ay.x
	if absf(det) < 1e-6:
		return Vector2i.ZERO
	var gx := (delta.x * ay.y - delta.y * ay.x) / det
	var gy := (ax.x * delta.y - ax.y * delta.x) / det
	return Vector2i(roundi(gx), roundi(gy))


func _gui_input(event: InputEvent) -> void:
	if not arranging:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var i := _building_at(mb.position)
			if i >= 0:
				_drag = -1
				_drag_spot = _spot(i)
				_drag = i
				_drag_from = mb.position
				Kit.haptic(10)
				accept_event()
		elif _drag >= 0:
			var i := _drag
			var to := _drag_spot
			var ok := DistrictRules.can_place(_current_layout(), i, to.x, to.y)
			var bl: Array = dist.get("buildings", [])
			var from: Array = (bl[i] as Dictionary).get("spot", [to.x, to.y]) if i < bl.size() else [to.x, to.y]
			_drag = -1
			_lots_layer.queue_redraw()
			if ok and (int(from[0]) != to.x or int(from[1]) != to.y):
				Kit.sfx("stamp", 1.3)
				Kit.haptic(18)
				placed.emit(i, to.x, to.y)
			else:
				if not ok:
					Kit.haptic(8, 0.3)
				_place_sprites()
				_overlay.queue_redraw()
			accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _drag >= 0:
		var bl: Array = dist.get("buildings", [])
		var from: Array = (bl[_drag] as Dictionary).get("spot", [0, 0])
		var to := Vector2i(int(from[0]), int(from[1])) + _lots(mm.position - _drag_from)
		if to != _drag_spot:
			_drag_spot = to
			_place_sprites()
			_overlay.queue_redraw()
			_lots_layer.queue_redraw()
		accept_event()


# ------------------------------------------------------------------ labels

## While arranging: the lots as a faint grid on the ground and the dragged building's footprint (ink
## where it fits, signal where it doesn't), under the buildings.
func _draw_lots() -> void:
	if not arranging:
		return
	var n := DistrictRules.GRID
	for k in n + 1:
		_lots_layer.draw_line(_ground(k, 0), _ground(k, n), Color(SIG, 0.3), 1.0, true)
		_lots_layer.draw_line(_ground(0, k), _ground(n, k), Color(SIG, 0.3), 1.0, true)
	if _drag >= 0:
		var fp := _footprint(_drag, _drag_spot)
		var ok := DistrictRules.can_place(_current_layout(), _drag, _drag_spot.x, _drag_spot.y)
		_lots_layer.draw_colored_polygon(fp, Color(INK if ok else SIG, 0.22))
		_lots_layer.draw_polyline(fp + PackedVector2Array([fp[0]]), INK if ok else SIG, 2.0, true)


## Screenshots: building i held over lot (x, y), as if mid-drag.
func debug_hold(i: int, x: int, y: int) -> void:
	arranging = true
	_drag = i
	_drag_spot = Vector2i(x, y)
	_place_sprites()
	_overlay.queue_redraw()
	_lots_layer.queue_redraw()


func _draw_labels() -> void:
	var bl: Array = dist.get("buildings", [])
	var f := Kit.font("mono_bold")
	var next_souls := int((dist.get("next", {}) as Dictionary).get("souls", -1))
	for i in mini(bl.size(), IDS.size()):
		var bd: Dictionary = bl[i]
		if _info(i).is_empty():
			continue
		var roof := roof_point(i)
		var open := bool(bd.open)
		var kept := open and str(bd.keeper) != ""
		var foot := _foot(i)
		# The number on a small paper tag at the building's foot, toward the viewer.
		var tag := Rect2(foot + Vector2(-14, 10), Vector2(28, 16))
		_overlay.draw_rect(tag, Color(PAPER, 0.95) if open else Color(PAPER, 0.6))
		_overlay.draw_rect(tag, Color(INK, 0.6) if open else Color(INK, 0.25), false, 1.0)
		_overlay.draw_string(f, tag.position + Vector2(0, 12), "%02d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 10,
			INK if open else Color(INK, 0.45))
		# Its level as pips under the tag (from level 2).
		var lvl := int(bd.get("level", 1))
		if open and lvl > 1:
			var mx := int(bd.get("max_level", 5))
			var px := tag.position.x + tag.size.x * 0.5 - (mx * 6.0 - 2.0) * 0.5
			for k in mx:
				_overlay.draw_rect(Rect2(px + k * 6.0, tag.end.y + 3.0, 4.0, 4.0), SIG if k < lvl else Color(INK, 0.2))
		if arranging:
			continue
		if not open:
			var nx := int(bd.souls) == next_souls
			var lab := "%s SOULS" % Kit.format_num(int(bd.souls))
			var col := SIG if nx else Color(INK, 0.5)
			_overlay.draw_string(f, roof + Vector2(-60, -8), lab, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, col)
		elif kept:
			_overlay.draw_line(roof + Vector2(0, -4), roof + Vector2(0, -40), SIG if bool(bd.doubled) else INK, 1.5, true)
