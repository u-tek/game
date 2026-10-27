extends Control
## The district as an architect's maquette (the district screen's plan): the eight buildings of
## data/district.json in white clay on a paper ground slab with its street grid and the souls' road,
## rendered in Blender (tools/blender/district_models.py, assets/art/ui/district/), stacked back to
## front. Built buildings stand in clay (in the Horn Quarter, cast in black obsidian); a kept one takes
## its keeper's mark (her side's ink in halftone when she doubles it, gold for the Halo Quarter,
## signal for the Horn); unbuilt ones are frosted placeholders with their soul price, the next one
## warmed in signal. Drawn over them: each building's number on a paper tag and the prices; each
## kept roof's point is roof_point() (the screen hangs the keeper's portrait and its leader there).
## Arranging (arranging = true): the lots show as a faint grid; drag a building and it follows the
## finger lot by lot (the camera is orthographic, so a building on another lot is the same picture
## moved by a fixed offset), its footprint marked in ink where it fits and in signal where it doesn't;
## let go on a lot that fits and placed(i, x, y) is emitted (the screen stores it). Props (decor, the
## same clay, rendered on lot 0, 0 and shifted) stand among the buildings; while arranging they drag
## the same way (decor_moved), dragged off the quarter they are sold back (decor_removed), and with
## hold_kind set a tap on a free lot buys that prop there (decor_bought).
##   dist  the Game.district() dictionary (side, buildings [{i, open, keeper, doubled, souls, spot}], next)

signal placed(building: int, x: int, y: int)
## Not arranging: a tap (not a drag: the page scrolls) on a building.
signal tapped(building: int)
signal decor_moved(index: int, x: int, y: int)
signal decor_removed(index: int)
signal decor_bought(kind: String, x: int, y: int)

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
		mouse_filter = MOUSE_FILTER_STOP if v else MOUSE_FILTER_PASS
		_drag = -1
		if _overlay:
			_overlay.queue_redraw()
		if _lots_layer:
			_lots_layer.queue_redraw()

var _layout: Dictionary = {}
var _overlay: Control
var _lots_layer: Control         ## the lot grid and the dragged footprint, on the ground under the buildings
var _souls_layer: Control        ## souls drifting in along the road (under the buildings)
var _t := 0.0
## Souls on the road: how many, and how fast they drift (lots a second).
const SOULS := 9
const SOUL_SPEED := 0.22
var _made: Array[Node] = []      ## the ground and buildings (the screen adds the keepers' portraits)
var _sprites: Dictionary = {}    ## building index -> its TextureRect
var _drag := -1                  ## the building being dragged (-1: none)
var _drag_from := Vector2.ZERO
var _drag_spot := Vector2i.ZERO  ## where it would land
var _decor_info: Dictionary = {}  ## decor.json: kind -> {rect, foot} at lot 0, 0
var _props: Dictionary = {}      ## decor index -> its TextureRect
## The building index being dragged is _drag; a dragged prop is DECOR_BASE + its index.
const DECOR_BASE := 1000
## A miniature (the War screen's link): no tags, no souls, no taps.
var mini := false
## While arranging: the prop kind a tap on a free lot buys ("" = none).
var hold_kind := "":
	set(v):
		hold_kind = v
		if _lots_layer:
			_lots_layer.queue_redraw()


var _tap_down := Vector2.INF
## Where a press with a prop in hand went down (it buys on release, if that was a tap).
var _buy_down := Vector2.INF
## Buildings to raise out of the ground when the model is first shown (newly opened ones).
var rise: Array = []
## Debug (shots): the lamps lit whatever the hour.
var _lamps_on := OS.is_debug_build() and OS.get_cmdline_user_args().has("--lamp")


func _init() -> void:
	mouse_filter = MOUSE_FILTER_PASS


func _ready() -> void:
	var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_layout = j
	var fd := FileAccess.open(DIR + "decor.json", FileAccess.READ)
	if fd:
		var jd: Variant = JSON.parse_string(fd.get_as_text())
		if jd is Dictionary:
			_decor_info = jd
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


## A prop's lot (index k): the lot it is being dragged to, else its place in dist.
func _decor_spot(k: int) -> Vector2i:
	if _drag == DECOR_BASE + k:
		return _drag_spot
	var dc: Array = dist.get("decor", [])
	if k < dc.size():
		return Vector2i(int(dc[k].x), int(dc[k].y))
	return Vector2i.ZERO


func _decor_layout() -> Array:
	var out: Array = []
	var dc: Array = dist.get("decor", [])
	for k in dc.size():
		var s := _decor_spot(k)
		out.append([str(dc[k].kind), s.x, s.y])
	return out


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
	_props.clear()
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
	_souls_layer = Control.new()
	_souls_layer.name = "Souls"
	_souls_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_souls_layer.size = size
	_souls_layer.draw.connect(_draw_souls)
	add_child(_souls_layer)
	move_child(_souls_layer, 1)
	_made.append(_souls_layer)
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
	var dc: Array = dist.get("decor", [])
	for k in dc.size():
		var kind := str(dc[k].kind)
		var di: Dictionary = _decor_info.get(kind, {})
		if di.is_empty():
			continue
		var rc: Array = di.rect
		var tr := TextureRect.new()
		tr.name = "D_%d" % k
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = load(DIR + "decor_%s.png" % kind)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(float(rc[2]) * size.x, float(rc[3]) * size.y)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("state", 0)
		m.set_shader_parameter("rect_px", tr.size)
		m.set_shader_parameter("obsidian", str(dist.get("side", "")) == "hell")
		var np := DIR + "decor_%s_n.png" % kind
		if ResourceLoader.exists(np):
			m.set_shader_parameter("normal_tex", load(np))
			m.set_shader_parameter("has_normals", true)
		tr.material = m
		tr.set_meta("rect", rc)
		add_child(tr)
		_props[k] = tr
		_made.append(tr)
	_place_sprites()
	if not rise.is_empty():
		_raise.call_deferred(rise.duplicate())
		rise = []
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = Control.new()
		_overlay.name = "Labels"
		_overlay.mouse_filter = MOUSE_FILTER_IGNORE
		_overlay.draw.connect(_draw_labels)
		add_child(_overlay)
	_overlay.size = size
	_overlay.visible = not mini
	if mini:
		mouse_filter = MOUSE_FILTER_IGNORE
		_souls_layer.visible = false
	move_child(_overlay, _made.size())
	_overlay.queue_redraw()


## Newly opened buildings rise out of the ground, one after another, with a thud and a little dust.
func _raise(which: Array) -> void:
	var k := 0
	for i: Variant in which:
		var tr: TextureRect = _sprites.get(int(i))
		if tr == null:
			continue
		tr.pivot_offset = _foot(int(i)) - tr.position
		if not Kit.motion_ok():
			continue
		tr.scale = Vector2(1.0, 0.02)
		var tw := tr.create_tween()
		tw.tween_interval(0.35 + 0.45 * k)
		tw.tween_callback(func() -> void:
			Kit.sfx("stamp", 0.8)
			Kit.haptic(22))
		tw.tween_property(tr, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var dust := _Dust.new()
		dust.at = _foot(int(i))
		dust.size = size
		dust.mouse_filter = MOUSE_FILTER_IGNORE
		dust.modulate.a = 0.0
		add_child(dust)
		move_child(dust, tr.get_index())
		var dt := dust.create_tween()
		dt.tween_interval(0.35 + 0.45 * k)
		dt.tween_property(dust, "modulate:a", 1.0, 0.05)
		dt.tween_property(dust, "t", 1.0, 0.9).set_ease(Tween.EASE_OUT)
		dt.tween_callback(dust.queue_free)
		k += 1


## A puff of paper dust round a building's foot as it rises (t 0 -> 1: spreads and fades).
class _Dust:
	extends Control
	var at := Vector2.ZERO
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		for k in 14:
			var a := TAU * k / 14.0 + 0.3
			var r := 18.0 + 46.0 * t
			var p := at + Vector2(cos(a) * r, sin(a) * r * 0.55)
			draw_circle(p, 5.0 * (1.0 - t) + 1.0, Color(0.55, 0.53, 0.5, 0.45 * (1.0 - t)))


## Where a thing stands, back to front: buildings by their lots' middle, props by their lot's.
func _depth(key: int) -> float:
	if key >= DECOR_BASE:
		var s := _decor_spot(key - DECOR_BASE)
		return s.x + s.y + 1.0
	var sp := _spot(key)
	var wd := _wd(key)
	return sp.x + sp.y + (wd.x + wd.y) * 0.5


## Puts every building's and prop's picture on its lot and restacks them back to front.
func _place_sprites() -> void:
	var order: Array = _sprites.keys()
	for k: int in _props:
		order.append(DECOR_BASE + k)
	order.sort_custom(func(a: int, b: int) -> bool: return _depth(a) < _depth(b))
	var n := 3
	for key: int in order:
		var tr: TextureRect
		var shift: Vector2
		if key >= DECOR_BASE:
			tr = _props[key - DECOR_BASE]
			var s := _decor_spot(key - DECOR_BASE)
			shift = _ground(s.x, s.y) - _ground(0, 0)
			tr.modulate.a = 0.45 if _drag == key and not _lot_in_quarter(_drag_spot) else 1.0
		else:
			tr = _sprites[key]
			shift = _shift(key)
		var rc: Array = tr.get_meta("rect")
		tr.position = Vector2(float(rc[0]) * size.x, float(rc[1]) * size.y) + shift
		(tr.material as ShaderMaterial).set_shader_parameter("offset_px", tr.position)
		move_child(tr, n)
		n += 1


func _lot_in_quarter(s: Vector2i) -> bool:
	return s.x >= 0 and s.y >= 0 and s.x < DistrictRules.GRID and s.y < DistrictRules.GRID


# ------------------------------------------------------------------ arranging

## The building or prop under a point (local px): the frontmost whose picture is solid there.
func _building_at(p: Vector2) -> int:
	var keys: Array = _sprites.keys()
	for k: int in _props:
		keys.append(DECOR_BASE + k)
	keys.sort_custom(func(a: int, b: int) -> bool: return _depth(a) > _depth(b))
	for key: int in keys:
		var tr: TextureRect = _props[key - DECOR_BASE] if key >= DECOR_BASE else _sprites[key]
		if _solid_at(tr, p):
			return key
	return -1


## Whether a building's or prop's picture is solid at a point (local px): opaque and not its shadow.
func _solid_at(tr: TextureRect, p: Vector2) -> bool:
	if not Rect2(tr.position, tr.size).has_point(p) or tr.texture == null:
		return false
	var img: Image = tr.get_meta("img") if tr.has_meta("img") else null
	if img == null:
		img = tr.texture.get_image()
		if img == null:
			return false
		if img.is_compressed():
			img.decompress()
		tr.set_meta("img", img)
	var uv := (p - tr.position) / tr.size
	var c := img.get_pixel(clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1))
	return c.a > 0.5 and maxf(c.r, maxf(c.g, c.b)) > 0.08


func _process(delta: float) -> void:
	if _souls_layer and Kit.motion_ok():
		_t += delta
		_souls_layer.queue_redraw()


## Souls arriving from the front: small glowing wisps drifting down the souls' road, bobbing a
## little, gold in the Halo Quarter and ember in the Horn; they fade in at one end and out at the
## other.
func _draw_souls() -> void:
	# After dark (19:00 to 06:00 local) the lamps are lit: a warm pool on the ground round each one.
	if _lamps_lit():
		for d: Variant in dist.get("decor", []):
			if str((d as Dictionary).kind) != "lamp":
				continue
			var c := _ground(float(d.x) + 0.5, float(d.y) + 0.5)
			var flick := 1.0 + sin(_t * 7.0 + float(d.x) * 3.1) * 0.03
			for k in 6:
				var r := (54.0 - k * 8.0) * flick
				var pts := PackedVector2Array()
				for q in 24:
					var a := TAU * q / 24.0
					pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.58))
				_souls_layer.draw_colored_polygon(pts, Color(1.0, 0.76, 0.34, 0.11))
	var road := float(DistrictRules.ROAD_ROW) + 0.5
	var n := float(DistrictRules.GRID)
	var hell := str(dist.get("side", "")) == "hell"
	var col := Color(1.0, 0.45, 0.16) if hell else Color(1.0, 0.82, 0.42)
	for k in SOULS:
		var u := fposmod(_t * SOUL_SPEED + float(k) * (n + 1.0) / float(SOULS), n + 1.0) - 0.5
		var sway := sin(_t * 0.9 + float(k) * 2.1) * 0.14
		var bob := 7.0 + sin(_t * 2.3 + float(k) * 1.7) * 2.5
		var p := _ground(u, road + sway) + Vector2(0, -bob)
		var fade := clampf(minf(u + 0.5, n + 0.5 - u) / 0.8, 0.0, 1.0)
		_souls_layer.draw_circle(p, 6.0, Color(col, 0.16 * fade))
		_souls_layer.draw_circle(p, 3.2, Color(col, 0.35 * fade))
		_souls_layer.draw_circle(p, 1.6, Color(1.0, 0.97, 0.9, 0.95 * fade))


## The lot under a point on the ground (local px).
func _lot_at(p: Vector2) -> Vector2i:
	var g0 := _ground(0, 0)
	var ax := _ground(1, 0) - g0
	var ay := _ground(0, 1) - g0
	var det := ax.x * ay.y - ax.y * ay.x
	if absf(det) < 1e-6:
		return Vector2i(-1, -1)
	var d := p - g0
	return Vector2i(floori((d.x * ay.y - d.y * ay.x) / det), floori((ax.x * d.y - ax.y * d.x) / det))


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
		var tb := event as InputEventMouseButton
		if tb and tb.button_index == MOUSE_BUTTON_LEFT:
			if tb.pressed:
				_tap_down = tb.position
			elif _tap_down != Vector2.INF and tb.position.distance_to(_tap_down) < 14.0:
				var hit := _building_at(tb.position)
				if hit >= 0 and hit < DECOR_BASE:
					tapped.emit(hit)
				_tap_down = Vector2.INF
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if hold_kind != "":
				# A prop is bought on a tap (press and release on the same lot, hardly moving), never on
				# the press alone: a swipe across the plan spends nothing.
				_buy_down = mb.position
				accept_event()
				return
			var i := _building_at(mb.position)
			if i >= 0:
				_drag = -1
				_drag_spot = _decor_spot(i - DECOR_BASE) if i >= DECOR_BASE else _spot(i)
				_drag = i
				_drag_from = mb.position
				Kit.haptic(10)
				accept_event()
		elif _buy_down != Vector2.INF:
			var lot := _lot_at(mb.position)
			var tap := mb.position.distance_to(_buy_down) < 14.0 and lot == _lot_at(_buy_down)
			_buy_down = Vector2.INF
			if tap and hold_kind != "":
				if DistrictRules.can_decorate(_current_layout(), _decor_layout(), lot.x, lot.y):
					decor_bought.emit(hold_kind, lot.x, lot.y)
				else:
					Kit.haptic(8, 0.3)
			accept_event()
		elif _drag >= DECOR_BASE:
			var k := _drag - DECOR_BASE
			var to := _drag_spot
			var dc: Array = dist.get("decor", [])
			var from := Vector2i(int(dc[k].x), int(dc[k].y))
			_drag = -1
			_lots_layer.queue_redraw()
			if not _lot_in_quarter(to):
				decor_removed.emit(k)
			elif to != from and DistrictRules.can_decorate(_current_layout(), _decor_layout(), to.x, to.y, k):
				Kit.sfx("stamp", 1.5)
				Kit.haptic(14)
				decor_moved.emit(k, to.x, to.y)
			else:
				_place_sprites()
				_overlay.queue_redraw()
			accept_event()
		elif _drag >= 0:
			var i := _drag
			var to := _drag_spot
			var ok := DistrictRules.can_place(_current_layout(), i, to.x, to.y, _decor_layout())
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
		var to: Vector2i
		if _drag >= DECOR_BASE:
			var dc: Array = dist.get("decor", [])
			var dk: Dictionary = dc[_drag - DECOR_BASE]
			to = Vector2i(int(dk.x), int(dk.y)) + _lots(mm.position - _drag_from)
		else:
			var bl: Array = dist.get("buildings", [])
			var from: Array = (bl[_drag] as Dictionary).get("spot", [0, 0])
			to = Vector2i(int(from[0]), int(from[1])) + _lots(mm.position - _drag_from)
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
	if _drag >= DECOR_BASE:
		var s := _drag_spot
		if _lot_in_quarter(s):
			var fp := PackedVector2Array([_ground(s.x, s.y), _ground(s.x + 1, s.y), _ground(s.x + 1, s.y + 1), _ground(s.x, s.y + 1)])
			var ok := DistrictRules.can_decorate(_current_layout(), _decor_layout(), s.x, s.y, _drag - DECOR_BASE)
			_lots_layer.draw_colored_polygon(fp, Color(INK if ok else SIG, 0.22))
			_lots_layer.draw_polyline(fp + PackedVector2Array([fp[0]]), INK if ok else SIG, 2.0, true)
	elif _drag >= 0:
		var fp := _footprint(_drag, _drag_spot)
		var ok := DistrictRules.can_place(_current_layout(), _drag, _drag_spot.x, _drag_spot.y, _decor_layout())
		_lots_layer.draw_colored_polygon(fp, Color(INK if ok else SIG, 0.22))
		_lots_layer.draw_polyline(fp + PackedVector2Array([fp[0]]), INK if ok else SIG, 2.0, true)
	elif hold_kind != "":
		# Holding a prop to put down: every free lot gets a small ink dot.
		var lay := _current_layout()
		var dl := _decor_layout()
		for y in n:
			for x in n:
				if DistrictRules.can_decorate(lay, dl, x, y):
					_lots_layer.draw_circle((_ground(x, y) + _ground(x + 1, y + 1)) * 0.5, 2.5, Color(INK, 0.55))


## Screenshots: building i held over lot (x, y), as if mid-drag.
func debug_hold(i: int, x: int, y: int) -> void:
	arranging = true
	_drag_spot = Vector2i(x, y)
	_drag = i
	_drag_spot = Vector2i(x, y)
	_place_sprites()
	_overlay.queue_redraw()
	_lots_layer.queue_redraw()


## After dark: each lamp's head lit (over its prop).
func _lamps_lit() -> bool:
	var hour := int(Time.get_datetime_dict_from_system().hour)
	return (hour >= 19 or hour < 6 or _lamps_on) and not arranging


func _draw_labels() -> void:
	if _lamps_lit():
		var dc: Array = dist.get("decor", [])
		for k: int in _props:
			if k < dc.size() and str(dc[k].kind) == "lamp":
				var tr: TextureRect = _props[k]
				var head := Vector2(_ground(float(dc[k].x) + 0.5, float(dc[k].y) + 0.5).x, tr.position.y + 9.0)
				_overlay.draw_circle(head, 14.0, Color(1.0, 0.8, 0.4, 0.18))
				_overlay.draw_circle(head, 7.0, Color(1.0, 0.85, 0.5, 0.45))
				_overlay.draw_circle(head, 3.0, Color(1.0, 0.97, 0.85, 0.95))
	var bl: Array = dist.get("buildings", [])
	var f := Kit.font("mono_bold")
	var next_souls := int((dist.get("next", {}) as Dictionary).get("souls", -1))
	for i in mini(bl.size(), IDS.size()):
		var bd: Dictionary = bl[i]
		if _info(i).is_empty():
			continue
		var roof := roof_point(i)
		var open := bool(bd.open)
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

