extends Control
## Plate: a UI shape rendered as a lit physical part (style v4 "Signal", docs/dev/ui-style-v4.md).
## The control's rect is the plate body; a ColorRect child, larger by `margin`, runs plate.gdshader
## (bevel, material, screws, cast shadow, animated glow). Add content (labels, icons) as children
## after it. Kit.plate / Kit.plate_button build these.
##
##   preset   "silver" (brushed machined metal), "graphite" (matte near-black), "slate" (matte mid
##            grey), "signal" (emissive red-orange glass), "dial" (round turned metal, set circle),
##            "ink" (dark glass inset)
##   cuts     chamfer per corner [TL, TR, BR, BL] in px, or `shape` for any polygon (body px)
##   screws   positions in body px
##
## Also here: GlassBlock (thick refracting glass slab, refract_glass.gdshader) and LightStrip
## (an emissive tube that breathes and flickers, light_strip.gdshader).

const PLATE_SHADER := preload("res://src/ui/shaders/plate.gdshader")
const GLASS_SHADER := preload("res://src/ui/shaders/refract_glass.gdshader")
const STRIP_SHADER := preload("res://src/ui/shaders/light_strip.gdshader")

const PRESETS := {
	"silver": {"mat": 0, "albedo": Color("e3e6e2"), "albedo_low": Color("a9aeab"), "bevel": 5.0},
	"graphite": {"mat": 1, "albedo": Color("34383d"), "albedo_low": Color("1c1e22"), "bevel": 4.0},
	"slate": {"mat": 2, "albedo": Color("a2a8ad"), "albedo_low": Color("6c7277"), "bevel": 5.0},
	"signal": {"mat": 3, "albedo": Color("ff4b1f"), "albedo_low": Color("ff4b1f"), "bevel": 6.0},
	"dial": {"mat": 4, "albedo": Color("7d838a"), "albedo_low": Color("33373c"), "bevel": 7.0},
	"ink": {"mat": 5, "albedo": Color("0c0d0f"), "albedo_low": Color("0c0d0f"), "bevel": 3.0},
	"white": {"mat": 2, "albedo": Color("f4f4f2"), "albedo_low": Color("cfd1ce"), "bevel": 6.0},
}

var preset := "silver"
var cuts: Array = [0.0, 0.0, 0.0, 0.0]
var shape := PackedVector2Array()
var circle := false
var screws: Array[Vector2] = []
var screw_r := 4.5
var margin := 34.0
var glow := 0.0
var glow_radius := 18.0
var emit_color := Color("ff6a2a")
var emit_strength := 1.0
var pulse := 0.0
var pulse_period := 2.6
var topo := 0.0
var bevel := -1.0
var shadow_a := 0.6
var shadow_off := Vector2(3, 9)
var albedo_override := Color(0, 0, 0, 0)
## Cut into the surface (an engraved pocket or well) instead of raised.
var recess := false
## A round cut-out (body px: x, y centre, z radius; z 0 = none).
var hole := Vector3.ZERO

var _surf: ColorRect
var _mat: ShaderMaterial
var _press := 0.0
var _base_y := NAN


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	_surf = ColorRect.new()
	_surf.mouse_filter = MOUSE_FILTER_IGNORE
	_surf.show_behind_parent = true
	_mat = ShaderMaterial.new()
	_mat.shader = PLATE_SHADER
	_surf.material = _mat
	add_child(_surf)
	move_child(_surf, 0)
	add_to_group(&"plates")
	if preset == "signal":
		add_to_group(&"plate_emitters")
	resized.connect(_apply)
	_apply()


## Lights every plate with the glow of the signal plates near it (call once the layout is final;
## Kit / screens call it deferred after building).
static func relight_all(tree: SceneTree) -> void:
	var emitters := tree.get_nodes_in_group(&"plate_emitters")
	for n in tree.get_nodes_in_group(&"plates"):
		(n as Control).call("_relight", emitters)


func _relight(emitters: Array) -> void:
	if _mat == null:
		return
	var me := get_global_rect()
	var near: Array = []
	for e: Variant in emitters:
		if e == self or not is_instance_valid(e) or not (e as Control).is_visible_in_tree():
			continue
		var er: Rect2 = (e as Control).call("emitter_rect")
		var dx := maxf(0.0, maxf(er.position.x - me.end.x, me.position.x - er.end.x))
		var dy := maxf(0.0, maxf(er.position.y - me.end.y, me.position.y - er.end.y))
		var dist := Vector2(dx, dy).length()
		if dist < 140.0:
			near.append([dist, e])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var origin := global_position - Vector2(margin, margin)
	var rects: Array = []
	var cols: Array = []
	for i in 4:
		if i < near.size():
			var em := near[i][1] as Control
			var r: Rect2 = em.call("emitter_rect")
			var hs := r.size * 0.5
			if em.get("circle"):
				hs = -Vector2.ONE * minf(r.size.x, r.size.y) * 0.5
			rects.append(Vector4(r.get_center().x - origin.x, r.get_center().y - origin.y, hs.x, hs.y))
			var c: Color = em.get("emit_color")
			cols.append(Vector4(c.r, c.g, c.b, float(em.get("spill"))))
		else:
			rects.append(Vector4.ZERO)
			cols.append(Vector4.ZERO)
	_mat.set_shader_parameter("nspill", mini(near.size(), 4))
	_mat.set_shader_parameter("spill_rect", rects)
	_mat.set_shader_parameter("spill_col", cols)


## The light-emitting area (for Plate.relight_all).
func emitter_rect() -> Rect2:
	return get_global_rect()


## How strongly this plate's glow lights its neighbours.
var spill := 0.3


## Re-sends every uniform (call after changing fields once the plate is in the tree).
func _apply() -> void:
	if _surf == null:
		return
	if glow > 0.0:
		# Room for the wide halo (3x glow_radius), so the glow never ends in a hard edge.
		margin = maxf(margin, glow_radius * 3.0)
	_surf.position = Vector2(-margin, -margin)
	_surf.size = size + Vector2(margin, margin) * 2.0
	var pr: Dictionary = PRESETS.get(preset, PRESETS["silver"])
	var m := Vector2(margin, margin)
	_mat.set_shader_parameter("rect_size", _surf.size)
	if circle:
		_mat.set_shader_parameter("shape", 1)
		_mat.set_shader_parameter("circle", Vector3(m.x + size.x * 0.5, m.y + size.y * 0.5, minf(size.x, size.y) * 0.5))
	else:
		var pts := shape if shape.size() >= 3 else cut_rect(size, cuts)
		var arr := PackedVector2Array()
		for i in 16:
			arr.append(pts[i] + m if i < pts.size() else Vector2.ZERO)
		_mat.set_shader_parameter("shape", 0)
		_mat.set_shader_parameter("npts", mini(pts.size(), 16))
		_mat.set_shader_parameter("pts", arr)
	_mat.set_shader_parameter("mat", int(pr["mat"]))
	_mat.set_shader_parameter("recess", recess)
	_mat.set_shader_parameter("hole", Vector3(hole.x + margin, hole.y + margin, hole.z) if hole.z > 0.0 else Vector3.ZERO)
	var alb: Color = pr["albedo"] if albedo_override.a <= 0.0 else albedo_override
	_mat.set_shader_parameter("albedo", alb)
	_mat.set_shader_parameter("albedo_low", pr["albedo_low"] if albedo_override.a <= 0.0 else albedo_override.darkened(0.35))
	_mat.set_shader_parameter("bevel", bevel if bevel >= 0.0 else float(pr["bevel"]))
	_mat.set_shader_parameter("emit", emit_color)
	_mat.set_shader_parameter("emit_strength", emit_strength)
	_mat.set_shader_parameter("glow_radius", glow_radius)
	_mat.set_shader_parameter("glow_strength", glow)
	_mat.set_shader_parameter("pulse", pulse if Kit.motion_ok() else 0.0)
	_mat.set_shader_parameter("pulse_period", pulse_period)
	_mat.set_shader_parameter("topo", topo)
	_mat.set_shader_parameter("seed", float(get_instance_id() % 97) * 0.37)
	_mat.set_shader_parameter("shadow_a", shadow_a)
	_mat.set_shader_parameter("shadow_off", shadow_off)
	_mat.set_shader_parameter("shadow_r", 16.0)
	var sc := []
	for i in 8:
		sc.append(Vector3(screws[i].x + m.x, screws[i].y + m.y, screw_r) if i < screws.size() else Vector3.ZERO)
	_mat.set_shader_parameter("nscrews", mini(screws.size(), 8))
	_mat.set_shader_parameter("screws", sc)
	_mat.set_shader_parameter("press", _press)


## Pressed look: the plate sinks 3 px, its shadow tightens and its face brightens (tweened).
func set_pressed_look(down: bool) -> void:
	if is_nan(_base_y):
		_base_y = position.y
	var tw := create_tween().set_parallel(true)
	var to := 1.0 if down else 0.0
	var dur := 0.05 if down else 0.22
	tw.tween_method(func(v: float) -> void:
		_press = v
		if _mat:
			_mat.set_shader_parameter("press", v)
		if not get_parent() is Container:
			position.y = _base_y + 3.0 * v, _press, to, dur).set_trans(Tween.TRANS_BACK if not down else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Polygon of a rect with chamfered corners [TL, TR, BR, BL] (clockwise from the top left).
static func cut_rect(sz: Vector2, c: Array) -> PackedVector2Array:
	var tl := float(c[0]) if c.size() > 0 else 0.0
	var tr := float(c[1]) if c.size() > 1 else 0.0
	var br := float(c[2]) if c.size() > 2 else 0.0
	var bl := float(c[3]) if c.size() > 3 else 0.0
	var pts := PackedVector2Array()
	pts.append(Vector2(tl, 0))
	pts.append(Vector2(sz.x - tr, 0))
	if tr > 0.0:
		pts.append(Vector2(sz.x, tr))
	pts.append(Vector2(sz.x, sz.y - br))
	if br > 0.0:
		pts.append(Vector2(sz.x - br, sz.y))
	pts.append(Vector2(bl, sz.y))
	if bl > 0.0:
		pts.append(Vector2(0, sz.y - bl))
	if tl > 0.0:
		pts.append(Vector2(0, tl))
	return pts


## A plate whose bottom edge steps down into a tab between x0 and x1 (the OG-pass silhouette):
## chamfers c on the outer corners, 45-degree shoulders into the tab.
static func tab_bottom(sz: Vector2, c: float, x0: float, x1: float, tab: float) -> PackedVector2Array:
	var y := sz.y - tab
	return PackedVector2Array([Vector2(c, 0), Vector2(sz.x - c, 0), Vector2(sz.x, c), Vector2(sz.x, y),
		Vector2(x1 + tab, y), Vector2(x1, sz.y), Vector2(x0, sz.y), Vector2(x0 - tab, y), Vector2(0, y), Vector2(0, c)])


## A plate whose top edge steps up into a tab between x0 and x1.
static func tab_top(sz: Vector2, c: float, x0: float, x1: float, tab: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, tab), Vector2(x0 - tab, tab), Vector2(x0, 0), Vector2(x1, 0), Vector2(x1 + tab, tab),
		Vector2(sz.x, tab), Vector2(sz.x, sz.y - c), Vector2(sz.x - c, sz.y), Vector2(c, sz.y), Vector2(0, sz.y - c)])


## Thick refracting glass slab. The control's rect is the slab.
class GlassBlock:
	extends Control
	var radius := 14.0
	var margin := 26.0
	var refract_px := 26.0
	var blur_px := 14.0
	var tint := Color("d2dae2")
	var tint_amount := 0.16
	var sweep := 1.0
	var _surf: ColorRect
	var _mat: ShaderMaterial

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_surf = ColorRect.new()
		_surf.mouse_filter = MOUSE_FILTER_IGNORE
		_surf.show_behind_parent = true
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/ui/shaders/refract_glass.gdshader")
		_surf.material = _mat
		add_child(_surf)
		move_child(_surf, 0)
		resized.connect(_apply)
		_apply()

	func _apply() -> void:
		_surf.position = Vector2(-margin, -margin)
		_surf.size = size + Vector2(margin, margin) * 2.0
		_mat.set_shader_parameter("rect_size", _surf.size)
		_mat.set_shader_parameter("margin", margin)
		_mat.set_shader_parameter("radius", radius)
		_mat.set_shader_parameter("refract_px", refract_px)
		_mat.set_shader_parameter("blur_px", blur_px)
		_mat.set_shader_parameter("tint", tint)
		_mat.set_shader_parameter("tint_amount", tint_amount)
		_mat.set_shader_parameter("sweep", sweep if Kit.motion_ok() else 0.0)


## Emissive tube from `from` to `to` (local px). Size the control to cover the halo.
class LightStrip:
	extends Control
	var from := Vector2(20, 20)
	var to := Vector2(20, 180)
	var core := 3.5
	var color := Color("ff4b1f")
	var intensity := 1.0
	var halo := 16.0
	var breathe := 0.3
	var period := 3.0
	var phase := 0.0
	## Strips light the plates around them like glowing plates do (Plate.relight_all).
	var spill := 0.45
	var emit_color: Color:
		get:
			return color
	var _mat: ShaderMaterial

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func emitter_rect() -> Rect2:
		var a := global_position + Vector2(minf(from.x, to.x), minf(from.y, to.y)) - Vector2(core, core)
		return Rect2(a, (to - from).abs() + Vector2(core, core) * 2.0)

	func _ready() -> void:
		add_to_group(&"plate_emitters")
		var r := ColorRect.new()
		r.mouse_filter = MOUSE_FILTER_IGNORE
		r.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/ui/shaders/light_strip.gdshader")
		r.material = _mat
		add_child(r)
		resized.connect(_apply)
		_apply()

	func _apply() -> void:
		_mat.set_shader_parameter("rect_size", size)
		_mat.set_shader_parameter("a", from)
		_mat.set_shader_parameter("b", to)
		_mat.set_shader_parameter("core", core)
		_mat.set_shader_parameter("color", color)
		_mat.set_shader_parameter("intensity", intensity)
		_mat.set_shader_parameter("halo", halo)
		_mat.set_shader_parameter("breathe", breathe if Kit.motion_ok() else 0.0)
		_mat.set_shader_parameter("period", period)
		_mat.set_shader_parameter("flicker", 1.0 if Kit.motion_ok() else 0.0)
		_mat.set_shader_parameter("phase", phase)
