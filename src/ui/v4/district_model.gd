extends Control
## The district as an architect's maquette (the district screen's plan): the eight buildings of
## data/district.json in white clay on a paper ground slab with its street grid and the souls' road,
## rendered in Blender (tools/blender/district_models.py, assets/art/ui/district/), stacked back to
## front. Built buildings stand in clay; a kept one takes its keeper's mark (her side's ink in
## halftone when she doubles it, gold for the Halo Quarter, signal for the Horn); unbuilt ones are
## frosted placeholders with their soul price, the next one warmed in signal. Drawn over them: each
## building's number on a paper tag, the prices, and a leader up from each kept roof (the screen
## hangs the keeper's portrait at its end, roof_point()).
##   dist  the Game.district() dictionary (side, buildings [{i, open, keeper, doubled, souls}], next)

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

var _layout: Dictionary = {}
var _overlay: Control
var _made: Array[Node] = []      ## the ground and buildings (the screen adds the keepers' portraits)


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


## The middle of a building's roof in local px (for the keeper portraits' leaders).
func roof_point(i: int) -> Vector2:
	var b := _info(i)
	if b.is_empty():
		return size * 0.5
	var r: Array = b.roof
	return Vector2(float(r[0]) * size.x, float(r[1]) * size.y)


func _info(i: int) -> Dictionary:
	if i < 0 or i >= IDS.size():
		return {}
	return ((_layout.get("buildings", {}) as Dictionary).get(IDS[i], {}) as Dictionary)


func _rebuild() -> void:
	for c in _made:
		if is_instance_valid(c):
			c.queue_free()
	_made.clear()
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
	var bl: Array = dist.get("buildings", [])
	var tint := GOLD if str(dist.get("side", "")) == "heaven" else SIG
	var next_souls := int((dist.get("next", {}) as Dictionary).get("souls", -1))
	var order: Array = range(mini(bl.size(), IDS.size()))
	order.sort_custom(func(a: int, b: int) -> bool: return float(_info(a).get("depth", 0)) < float(_info(b).get("depth", 0)))
	for i: int in order:
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
		tr.position = Vector2(float(rc[0]) * size.x, float(rc[1]) * size.y)
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
		m.set_shader_parameter("offset_px", tr.position)
		tr.material = m
		tr.set_meta("state", st)
		add_child(tr)
		move_child(tr, _made.size())
		_made.append(tr)
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = Control.new()
		_overlay.name = "Labels"
		_overlay.mouse_filter = MOUSE_FILTER_IGNORE
		_overlay.draw.connect(_draw_labels)
		add_child(_overlay)
	_overlay.size = size
	move_child(_overlay, _made.size())
	_overlay.queue_redraw()


func _draw_labels() -> void:
	var bl: Array = dist.get("buildings", [])
	var f := Kit.font("mono_bold")
	var next_souls := int((dist.get("next", {}) as Dictionary).get("souls", -1))
	for i in mini(bl.size(), IDS.size()):
		var bd: Dictionary = bl[i]
		var info := _info(i)
		if info.is_empty():
			continue
		var roof := roof_point(i)
		var open := bool(bd.open)
		var kept := open and str(bd.keeper) != ""
		var ft: Array = info.foot
		var foot := Vector2(float(ft[0]) * size.x, float(ft[1]) * size.y)
		# The number on a small paper tag at the building's foot, toward the viewer.
		var tag := Rect2(foot + Vector2(-14, 10), Vector2(28, 16))
		_overlay.draw_rect(tag, Color(PAPER, 0.95) if open else Color(PAPER, 0.6))
		_overlay.draw_rect(tag, Color(INK, 0.6) if open else Color(INK, 0.25), false, 1.0)
		_overlay.draw_string(f, tag.position + Vector2(0, 12), "%02d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 10,
			INK if open else Color(INK, 0.45))
		if not open:
			var nx := int(bd.souls) == next_souls
			var lab := "%s SOULS" % Kit.format_num(int(bd.souls))
			var col := SIG if nx else Color(INK, 0.5)
			_overlay.draw_string(f, roof + Vector2(-60, -8), lab, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, col)
		elif kept:
			_overlay.draw_line(roof + Vector2(0, -4), roof + Vector2(0, -40), SIG if bool(bd.doubled) else INK, 1.5, true)
