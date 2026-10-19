extends Control
## The campaign's survey map (style v4 "Signal", poster look; docs/dev/ui-style-v4.md), built like the
## owner's isometric-terrain reference: one chapter as a physical relief model lying on the poster.
## A real 3D slab (TerrainGen, shaped like the chapter's world) in matte dark rock lit from the upper
## left, its valleys lit warm by the stage route, which runs as a molten river (model_terrain and
## molten_river shaders: painted emissive gradients, no bloom): hot and flowing up to the furthest
## open stage, cooled to a dark crust beyond it, pouring off the slab's edge as a glowing fall.
## Blender-rendered cumulus clouds drift slowly over the model, their shadows passing over the
## relief; the model casts a soft shadow on the paper. In 2D on top: each stage as a printed mark on
## the river (cleared ink, current signal with ring waves, locked hollow, bosses as diamonds) with a
## thin leader up to its id tag, like the reference's district labels; the selected stage and the
## boss get tall leaders to name labels above the model.
##
##   var m := SurveyMap.new(); m.size = ...; add_child(m)
##   m.show_chapter(ci, faction, stages)   # stages: [{id, name, status, boss}] in order
##   m.select(j); m.stage_pressed.connect(func(j: int) -> void: ...)
##
## A drag turns the map (IsoView); a tap picks the nearest stage mark (within TAP_R px).
##
## Alive but calm (all of it still with Reduce motion): the view renders at 30 fps (IsoView) with a
## slow auto-orbit and a little tilt parallax; the model settles onto the poster on open; the melt
## flows and a bright pulse runs down the open route now and then; the clouds drift and their
## shadows move; the current mark sends out ring waves; a selected stage's leader draws on.

signal stage_pressed(index: int)

const IsoView := preload("res://src/ui/v4/survey/iso_view.gd")
const TerrainGen := preload("res://src/ui/v4/survey/terrain_gen.gd")
const TERRAIN_SHADER := preload("res://src/ui/v4/survey/model_terrain.gdshader")
const RIVER_SHADER := preload("res://src/ui/v4/survey/molten_river.gdshader")
const CLOUD_SHADER := preload("res://src/ui/v4/survey/cloud_sprite.gdshader")
const SHADOW_SHADER := preload("res://src/ui/v4/survey/contact_shadow.gdshader")
const CLOUDS_PATH := "res://assets/art/worlds/clouds.png"
const CLOUD_SHADOW_PATH := "res://assets/art/worlds/clouds_shadow.png"

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")
const TAP_R := 74.0
## Seconds for the model to settle onto the poster when a chapter opens.
const SETTLE := 0.8
const PULSE_EVERY := 5.0
const PULSE_RUN := 1.6
## How many clouds drift over the model.
const CLOUD_COUNT := 5
## The model's relief is drawn this many times as tall as TerrainGen's heights.
const RELIEF := 1.4

## The model's colours per terrain kind (rock in shadow, rock lit, the warm valley light, the hot
## melt, the cut sides), sRGB.
const PALETTE := {
	"highland": {"lo": Color("1d1a20"), "hi": Color("7a7380"), "warm": Color("ff5a22"), "hot": Color("ffb862"), "side": Color("17151a")},
	"canyons": {"lo": Color("21160f"), "hi": Color("8a6655"), "warm": Color("ff5520"), "hot": Color("ffb25a"), "side": Color("1a120e")},
	"craters": {"lo": Color("18151f"), "hi": Color("6f6880"), "warm": Color("ff4f22"), "hot": Color("ffa95a"), "side": Color("141219")},
	"ice": {"lo": Color("3b4452"), "hi": Color("d6dde5"), "warm": Color("ff6a2c"), "hot": Color("ffc178"), "side": Color("262c36")},
	"lava": {"lo": Color("0e0c0e"), "hi": Color("4a4042"), "warm": Color("ff4b1f"), "hot": Color("ffa04a"), "side": Color("0e0c0d")},
	"crystal": {"lo": Color("1a1824"), "hi": Color("7c7894"), "warm": Color("ff5126"), "hot": Color("ffb06a"), "side": Color("16141d")},
}

## Layout knobs (set before show_chapter).
var yaw := 22.0
var pitch := -30.0
var ortho_width := 15.0
var shift := Vector2(0.0, 0.0)
## Raised labels never go above this y (view px): clear of the title block.
var label_floor := 0.0
## Rects (view px) the tags and labels keep clear of (the legend printed over the map).
var avoid: Array = []
## The world height the camera centres on.
var target_y := 0.7
## The picture reaches this far above and below the map's tap area (x: top, y: bottom px).
var overscan := Vector2.ZERO

## Generated chapters, kept for the session so switching back is instant ("ci:faction:count" ->
## TerrainGen), with their slab and river meshes.
static var _terrains: Dictionary = {}
static var _meshes: Dictionary = {}
static var _river_meshes: Dictionary = {}
static var _detail_tex: NoiseTexture2D
static var _flow_tex: NoiseTexture2D

var view: IsoView
var terrain: TerrainGen
var faction := "celestial"
var stages: Array = []
var selected := -1
var _overlay: Control
var _model: Node3D
var _slab: MeshInstance3D
var _slab_mat: ShaderMaterial
var _river_mat: ShaderMaterial
var _clouds: Array[MeshInstance3D] = []
var _cloud_data: Array[Dictionary] = []
var _settle := 1.0
var _t := 0.0
## Seconds since the last selection (its leaders draw on).
var _sel_t := 99.0
var _pts := PackedVector2Array()
var _reached := -1
var _mesh_key := ""


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP


func _ready() -> void:
	clip_contents = false
	view = IsoView.new()
	view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	view.offset_top = -overscan.x
	view.offset_bottom = overscan.y
	view.yaw = yaw
	view.pitch = pitch
	view.ortho_width = ortho_width
	view.shift = shift
	view.target = Vector3(0.0, target_y, 0.0)
	# A slow orbit of a few degrees while idle, a little parallax with the phone's tilt, 30 fps.
	view.sway = 4.5
	view.sway_period = 30.0
	view.pitch_sway = 1.2
	view.pitch_period = 41.0
	view.tilt_yaw = 7.0
	view.tilt_pitch = 4.0
	view.fps_cap = 30.0
	add_child(view)
	_overlay = _Overlay.new()
	_overlay.map = self
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	view.add_child(_overlay)
	view.turned.connect(_reproject)
	view.frame.connect(_on_frame)
	resized.connect(_reproject)


## Builds chapter `ci`'s map. stages: [{id, name, status ("cleared"|"current"|"locked"), boss}].
func show_chapter(ci: int, faction_name: String, stage_list: Array) -> void:
	faction = faction_name
	stages = stage_list
	_reached = -1
	for j in stages.size():
		if str(stages[j].get("status", "locked")) != "locked":
			_reached = j
	var key := "%d:%s:%d" % [ci, faction, stages.size()]
	if not _terrains.has(key):
		var tg := TerrainGen.new(ci, faction, stages.size())
		_terrains[key] = tg
		_meshes[key] = tg.mesh()
		_river_meshes[key] = _river_mesh(tg)
	terrain = _terrains[key]
	_mesh_key = key
	for c in view.world.get_children():
		c.queue_free()
	_clouds.clear()
	_cloud_data.clear()
	# The model (slab and rivers) with its relief drawn RELIEF times as tall.
	_model = Node3D.new()
	_model.name = "ModelRoot"
	_model.scale = Vector3(1.0, RELIEF, 1.0)
	view.world.add_child(_model)
	_build_shadow()
	_build_slab()
	_build_rivers()
	_build_clouds(ci)
	_settle = 0.0 if Kit.motion_ok() else 1.0
	_place_model()
	view.request_render()
	_reproject()


func select(j: int) -> void:
	if j != selected:
		_sel_t = 0.0 if Kit.motion_ok() else 99.0
	selected = j
	_overlay.queue_redraw()


## Position of stage j's mark in this control (for placing callouts).
func stage_point(j: int) -> Vector2:
	return view.position + _pts[j] if j >= 0 and j < _pts.size() else Vector2.ZERO


## Total and open lengths of the route (world units, stage 1 to the last / furthest open stage).
func route_lengths() -> Vector2:
	if terrain == null or terrain.stage_s.is_empty():
		return Vector2.ZERO
	var s0 := terrain.stage_s[0]
	var total := terrain.stage_s[terrain.stage_s.size() - 1] - s0
	var open := terrain.stage_s[clampi(_reached, 0, terrain.stage_s.size() - 1)] - s0 if _reached >= 0 else 0.0
	return Vector2(total, open)


# ------------------------------------------------------------------ 3D

func _palette() -> Dictionary:
	return PALETTE.get(terrain.kind, PALETTE["highland"])


## A seamless noise normal map for the model's fine relief (shared).
static func _detail() -> NoiseTexture2D:
	if _detail_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 811
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.frequency = 0.03
		_detail_tex = NoiseTexture2D.new()
		_detail_tex.width = 256
		_detail_tex.height = 256
		_detail_tex.seamless = true
		_detail_tex.as_normal_map = true
		_detail_tex.bump_strength = 5.0
		_detail_tex.generate_mipmaps = true
		_detail_tex.noise = n
	return _detail_tex


## Seamless noise for the melt's streaks (shared).
static func _flow_noise() -> NoiseTexture2D:
	if _flow_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 233
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.frequency = 0.02
		_flow_tex = NoiseTexture2D.new()
		_flow_tex.width = 256
		_flow_tex.height = 128
		_flow_tex.seamless = true
		_flow_tex.noise = n
	return _flow_tex


func _build_shadow() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var ps := Vector2(TerrainGen.W + 3.0, TerrainGen.D + 3.0)
	pm.size = ps
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = SHADOW_SHADER
	m.set_shader_parameter("plane_size", ps)
	m.set_shader_parameter("slab", Vector2(TerrainGen.W, TerrainGen.D))
	m.set_shader_parameter("soft", 1.1)
	m.set_shader_parameter("strength", 0.5)
	mi.material_override = m
	mi.position = Vector3(0.35, TerrainGen.BASE * RELIEF - 0.02, 0.3)
	mi.name = "Shadow"
	view.world.add_child(mi)


func _build_slab() -> void:
	var pal := _palette()
	_slab = MeshInstance3D.new()
	_slab.mesh = _meshes[_mesh_key] if _meshes.has(_mesh_key) else terrain.mesh()
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("rock_lo", pal["lo"])
	m.set_shader_parameter("rock_hi", pal["hi"])
	m.set_shader_parameter("warm", pal["warm"])
	m.set_shader_parameter("hot", pal["hot"])
	m.set_shader_parameter("side_ink", pal["side"])
	m.set_shader_parameter("paper", PAPER)
	m.set_shader_parameter("base_y", TerrainGen.BASE * RELIEF)
	m.set_shader_parameter("detail_tex", _detail())
	# A world not reached yet: the melt has cooled and the valleys are only faintly warm.
	m.set_shader_parameter("warm_k", (1.0 if terrain.kind != "ice" else 0.75) * (1.0 if _reached >= 0 else 0.4))
	m.set_shader_parameter("melt", 1.0 if _reached >= 0 else 0.0)
	if ResourceLoader.exists(CLOUD_SHADOW_PATH):
		m.set_shader_parameter("cloud_shadow_tex", load(CLOUD_SHADOW_PATH))
	m.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)
	_slab.material_override = m
	_slab_mat = m
	_slab.name = "Model"
	_model.add_child(_slab)


## The rivers as ribbons draped over their beds: the main river (the route) wide, the tributaries
## narrow. UV.x runs along each river from its source (world units; the main river's matches
## TerrainGen.stage_s), UV.y across. Parts beyond the slab are cut off at its edge.
static func _river_mesh(tg: TerrainGen) -> ArrayMesh:
	var am := ArrayMesh.new()
	for k in tg.rivers.size():
		var poly: PackedVector2Array = tg.rivers[k]
		var w := 0.12 if k == 0 else 0.045
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var s := 0.0
		var hw := TerrainGen.W * 0.5 - 0.02
		var hd := TerrainGen.D * 0.5 - 0.02
		for i in poly.size() - 1:
			var a := poly[i]
			var b := poly[i + 1]
			var seg := a.distance_to(b)
			var s1 := s + seg
			if seg < 0.0001:
				continue
			# Cut the segment to the slab (a river leaves over the edge).
			var t0 := 0.0
			var t1 := 1.0
			for axis in 2:
				var lo := -hw if axis == 0 else -hd
				var hi := hw if axis == 0 else hd
				var pa := a[axis]
				var pb := b[axis]
				if absf(pb - pa) < 1e-6:
					if pa < lo or pa > hi:
						t0 = 2.0
					continue
				var ta := (lo - pa) / (pb - pa)
				var tb := (hi - pa) / (pb - pa)
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
			if t0 >= t1:
				s = s1
				continue
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var d := (p1 - p0).normalized()
			var n := Vector2(-d.y, d.x) * w
			var u0 := s + seg * t0
			var u1 := s + seg * t1
			var y0 := _bed(tg, p0, n) + 0.014
			var y1 := _bed(tg, p1, n) + 0.014
			var a0 := Vector3(p0.x + n.x, y0, p0.y + n.y)
			var a1 := Vector3(p0.x - n.x, y0, p0.y - n.y)
			var b0 := Vector3(p1.x + n.x, y1, p1.y + n.y)
			var b1 := Vector3(p1.x - n.x, y1, p1.y - n.y)
			verts.append_array([a0, b0, a1, b0, b1, a1])
			uvs.append_array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
			s = s1
		if verts.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## The river bed's height at p: the highest of the centre and both banks (so the ribbon is never
## buried in a bank).
static func _bed(tg: TerrainGen, p: Vector2, n: Vector2) -> float:
	return maxf(tg.height_at(p.x, p.y), maxf(tg.height_at(p.x + n.x, p.y + n.y), tg.height_at(p.x - n.x, p.y - n.y)))


func _build_rivers() -> void:
	var pal := _palette()
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = _river_meshes[_mesh_key]
	var reach := 1e5
	var from := 0.0
	if not terrain.stage_s.is_empty():
		from = terrain.stage_s[0]
		reach = terrain.stage_s[clampi(_reached, 0, terrain.stage_s.size() - 1)] if _reached >= 0 else from - 1.0
		# The melt runs on past the last cleared stage only up to the current one; a finished
		# chapter flows all the way.
		if _reached >= terrain.stage_s.size() - 1 and _all_cleared():
			reach = 1e5
	for k in (mi.mesh as ArrayMesh).get_surface_count():
		var m := ShaderMaterial.new()
		m.shader = RIVER_SHADER
		m.set_shader_parameter("warm", pal["warm"])
		m.set_shader_parameter("hot", pal["hot"])
		m.set_shader_parameter("noise_tex", _flow_noise())
		m.set_shader_parameter("reach", reach if k == 0 else (1e5 if _reached >= 0 else -1.0))
		m.set_shader_parameter("pulse_from", from if k == 0 else 1e5)
		m.set_shader_parameter("pulse_every", PULSE_EVERY)
		m.set_shader_parameter("pulse_run", PULSE_RUN)
		m.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)
		mi.set_surface_override_material(k, m)
		if k == 0:
			_river_mat = m
	_model.add_child(mi)


func _all_cleared() -> bool:
	for s: Dictionary in stages:
		if str(s.get("status", "")) != "cleared":
			return false
	return not stages.is_empty()


## Clouds: seeded per chapter, each a billboard sprite from the atlas drifting along +x, wrapping
## round past the slab's ends (fading out and in).
func _build_clouds(ci: int) -> void:
	if not ResourceLoader.exists(CLOUDS_PATH):
		return
	var atlas: Texture2D = load(CLOUDS_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5011 + ci * 131
	var cells := [0, 1, 2, 3, 4, 5]
	for k in CLOUD_COUNT:
		var cell: int = cells[(k + ci) % cells.size()]
		var sz := rng.randf_range(1.7, 2.7)
		var d := {
			"cell": cell, "size": sz,
			"x": lerpf(-TerrainGen.W * 0.5, TerrainGen.W * 0.5, (k + rng.randf_range(0.1, 0.9)) / CLOUD_COUNT),
			"z": rng.randf_range(-TerrainGen.D * 0.3, TerrainGen.D * 0.45),
			"y": rng.randf_range(1.7, 2.3),
			"speed": rng.randf_range(0.07, 0.13),
		}
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(sz, sz)
		mi.mesh = qm
		var m := ShaderMaterial.new()
		m.shader = CLOUD_SHADER
		m.set_shader_parameter("atlas", atlas)
		m.set_shader_parameter("cell", float(cell))
		mi.material_override = m
		mi.name = "Cloud%d" % k
		view.world.add_child(mi)
		_clouds.append(mi)
		_cloud_data.append(d)
	_place_clouds()


## Places the clouds (and their shadows on the model) for the current time.
func _place_clouds() -> void:
	var span := TerrainGen.W + 4.0
	var arr: Array[Vector4] = []
	for k in _clouds.size():
		var d: Dictionary = _cloud_data[k]
		var x := float(d["x"])
		if Kit.motion_ok():
			x = fposmod(x + _t * float(d["speed"]) + span * 0.5, span) - span * 0.5
		var edge := clampf((span * 0.5 - absf(x)) / 1.4, 0.0, 1.0)
		var mi := _clouds[k]
		mi.position = Vector3(x, float(d["y"]) - (1.0 - _settle_e()) * 0.6, float(d["z"]))
		var fade := edge * _settle_e()
		(mi.material_override as ShaderMaterial).set_shader_parameter("fade", fade)
		arr.append(Vector4(x, float(d["z"]), float(d["size"]) * 0.42, float(int(d["cell"]))))
	if _slab_mat:
		var packed: Array[Vector4] = arr.duplicate()
		while packed.size() < 6:
			packed.append(Vector4(1e4, 1e4, 0.1, 0.0))
		_slab_mat.set_shader_parameter("clouds", PackedVector4Array(packed))
		_slab_mat.set_shader_parameter("cloud_count", arr.size())
		_slab_mat.set_shader_parameter("cloud_k", 0.55 * _settle_e())


func _settle_e() -> float:
	return 1.0 - pow(1.0 - clampf(_settle, 0.0, 1.0), 3.0)


## A render tick of the view (IsoView.frame, 30 fps while animating): the model settles, the clouds
## drift, the selection's leaders draw on; then the overlay is placed again.
func _on_frame(dt: float) -> void:
	_t += dt
	if _settle < 1.0:
		_settle = minf(_settle + dt / SETTLE, 1.0)
		_place_model()
	_sel_t += dt
	_place_clouds()
	_reproject()


## The model drops the last few centimetres onto the poster as the chapter opens.
func _place_model() -> void:
	var e := _settle_e()
	if _model:
		_model.position.y = (1.0 - e) * 0.9
	var sh := view.world.get_node_or_null("Shadow") as MeshInstance3D
	if sh:
		(sh.material_override as ShaderMaterial).set_shader_parameter("strength", 0.5 * e)


func _reproject() -> void:
	if terrain == null or view == null or view.camera == null:
		return
	var lift := (1.0 - _settle_e()) * 0.9
	_pts.resize(0)
	for p in terrain.stages:
		_pts.append(view.project(Vector3(p.x, terrain.height_at(p.x, p.y) * RELIEF + 0.05 + lift, p.y)))
	_overlay.queue_redraw()


## The slab's top corners at height y (front-left first, clockwise as seen from above).
func slab_corners(y: float) -> PackedVector2Array:
	var hw := TerrainGen.W * 0.5
	var hd := TerrainGen.D * 0.5
	return PackedVector2Array([view.project(Vector3(-hw, y, hd)), view.project(Vector3(-hw, y, -hd)),
		view.project(Vector3(hw, y, -hd)), view.project(Vector3(hw, y, hd))])


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	var dragged := view.handle_input(event)
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed and not dragged:
		var j := nearest((event as InputEventMouseButton).position - view.position)
		if j >= 0:
			stage_pressed.emit(j)
		accept_event()


## The stage mark nearest to a point in the view (within TAP_R), or -1.
func nearest(p: Vector2) -> int:
	var best := -1
	var best_d := TAP_R
	for j in _pts.size():
		var d := _pts[j].distance_to(p)
		if d < best_d:
			best_d = d
			best = j
	return best


## The order name labels try their spots in, as [dy, slide] (view px): straight above first, then
## slid along the row a step at a time, then below. Built once.
static var _label_order: Array[Vector2] = []


static func _label_spots() -> Array[Vector2]:
	if _label_order.is_empty():
		var spots: Array[Vector3] = []
		for dy: float in [-100.0, -76.0, -124.0, -148.0, -56.0, -40.0, 52.0, 76.0, 100.0, -172.0]:
			for k in range(0, 15):
				for sd: float in ([1.0] if k == 0 else [1.0, -1.0]):
					var cost := absf(dy + 96.0) * 0.6 + k * 30.0 + (40.0 if dy > 0.0 else 0.0)
					spots.append(Vector3(dy, k * 30.0 * sd, cost))
		spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
		for q in spots:
			_label_order.append(Vector2(q.x, q.y))
	return _label_order


## A spot for a name label of text size lsz over the stage mark at p: the first in the label order
## (right of the leader, or left of it) that keeps off every rect given and inside the view. An
## empty Rect2 if none does.
func _find_label(p: Vector2, lsz: Vector2, selected_label: bool, avoid: Array, marks: Array[Rect2], placed: Array[Rect2], tags: Array[Rect2], area: Vector2) -> Rect2:
	var blocks: Array[Rect2] = []
	for q: Rect2 in avoid:
		blocks.append(q)
	blocks.append_array(marks)
	blocks.append_array(tags)
	for q in placed:
		blocks.append(q.grow(3.0))
	for spot: Vector2 in _label_spots():
		if not selected_label and spot.x > 90.0:
			continue
		var ly := maxf(p.y + spot.x, label_floor + (lsz.y - 30.0) * 0.5)
		for side in 2:
			var x := (p.x + 6.0 + spot.y) if side == 0 else (p.x - 6.0 - lsz.x + spot.y)
			if x < 4.0 or x + lsz.x > area.x - 8.0:
				continue
			var r := Rect2(x - 4.0, ly - lsz.y * 0.5, lsz.x + 8.0, lsz.y)
			if r.end.y > area.y - 4.0:
				continue
			var hit := false
			for q in blocks:
				if q.intersects(r):
					hit = true
					break
			if hit:
				continue
			# The leader (up or down from the mark, then along the label's row when slid) keeps off
			# the printed legend too, or it would vanish under it.
			var ey := ly if (p.x < r.position.x or p.x > r.end.x) else (r.end.y if ly < p.y else r.position.y)
			var lead := Rect2(p.x - 1.0, minf(p.y, ey), 2.0, absf(p.y - ey))
			var run := Rect2(minf(p.x, r.position.x), ey - 1.0, absf(clampf(p.x, r.position.x, r.end.x) - p.x), 2.0)
			for q: Rect2 in avoid:
				if q.intersects(lead) or (run.size.x > 0.0 and q.intersects(run)):
					hit = true
					break
			if not hit:
				return r
	return Rect2()


## Draws the printed overlay: the stage marks on the river, their leaders and id tags, the raised
## name labels of the selected stage and the boss.
class _Overlay:
	extends Control
	var map

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if map == null or map.terrain == null:
			return
		var pts: PackedVector2Array = map._pts
		var st: Array = map.stages
		var t: float = map._t
		var anim := Kit.motion_ok()
		var settle: float = map._settle_e()
		if settle <= 0.02:
			return
		var sel_k := 1.0 - pow(1.0 - clampf(float(map._sel_t) / 0.4, 0.0, 1.0), 3.0)
		var f := Kit.font("mono_bold")
		var fm := Kit.font("mono")
		# Id tags on short leaders (alternating heights so neighbours never touch); a tag that would
		# land on the printed legend hangs below its mark instead.
		var avoid: Array = map.avoid
		var tags: Array[Rect2] = []
		var tag_draws: Array[Callable] = []
		# Tags a name label covers (it repeats their id): not drawn.
		var hidden := {}
		var label_draws: Array[Callable] = []
		for j in pts.size():
			if j >= st.size():
				break
			var s: Dictionary = st[j]
			var p := pts[j]
			var status := str(s.get("status", "locked"))
			var lh := 30.0 if j % 2 == 0 else 46.0
			var id := str(s.get("id", ""))
			var tw := f.get_string_size(id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var top := p - Vector2(0, lh * settle)
			var tag := Rect2(top.x - tw * 0.5 - 5.0, top.y - 18.0, tw + 10.0, 17.0)
			if avoid.any(func(q: Rect2) -> bool: return q.intersects(tag)):
				top = p + Vector2(0, (lh - 8.0) * settle)
				tag = Rect2(top.x - tw * 0.5 - 5.0, top.y + 1.0, tw + 10.0, 17.0)
			tags.append(tag)
			# Drawn after the name labels' leaders, so a leader never crosses a tag's id.
			tag_draws.append(func() -> void:
				if hidden.has(j):
					return
				var lc := Color(PAPER, 0.85) if status != "current" else SIGNAL * 1.3
				draw_line(p + Vector2(0, -8 if top.y < p.y else 8), top, Color(lc, 0.9 * settle), 1.0, true)
				var fill := SIGNAL if status == "current" else (INK if status == "cleared" else Color(INK, 0.55))
				draw_rect(tag, Color(fill, settle))
				if status == "locked":
					draw_rect(tag, Color(PAPER, 0.6 * settle), false, 1.0)
				draw_string(f, Vector2(tag.position.x + 5.0, tag.end.y - 4.5), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(PAPER, settle)))
		# Leaders from the selected stage and the boss to name labels (above the mark, or below it
		# when the legend or a tag is in the way).
		var raised: Array[int] = []
		if map.selected >= 0:
			raised.append(map.selected)
		if st.size() > 0 and bool(st[st.size() - 1].get("boss", false)) and not raised.has(st.size() - 1):
			raised.append(st.size() - 1)
		var placed: Array[Rect2] = []
		var no_tags: Array[Rect2] = []
		for n in raised.size():
			var j: int = raised[n]
			if j >= pts.size():
				continue
			var p := pts[j]
			var s: Dictionary = st[j]
			var cur := str(s.get("status", "")) == "current"
			var sub := "BOSS STAGE" if bool(s.get("boss", false)) else ("NEXT" if cur else str(s.get("status", "")).to_upper())
			# The id and name; a long name breaks onto a second line (at the space nearest its middle).
			var lines: Array[String] = ["%s  %s" % [str(s.get("id", "")), str(s.get("name", "")).to_upper()]]
			if f.get_string_size(lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > 190.0:
				var words := lines[0].split(" ")
				var best := -1
				var best_d := 1e9
				var acc := 0
				for wi in words.size() - 1:
					acc += words[wi].length() + 1
					var dd := absf(acc - lines[0].length() * 0.5)
					if words[wi] != "" and dd < best_d:
						best_d = dd
						best = acc
				if best > 0:
					lines = [lines[0].substr(0, best - 1), "      " + lines[0].substr(best)]
			var tw := 0.0
			for ln in lines:
				tw = maxf(tw, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
			var lsz := Vector2(tw, 16.0 + 14.0 * lines.size())
			# A name label never covers another stage's mark; it may cover its own id tag (it
			# repeats the id).
			var marks: Array[Rect2] = []
			var others: Array[Rect2] = []
			for m in mini(pts.size(), st.size()):
				if m != j:
					marks.append(Rect2(pts[m] - Vector2(12, 12), Vector2(24, 24)))
					if m < tags.size():
						others.append(tags[m])
			# The first clear spot in the label order (_label_order: above the mark first, then slid
			# along the row, then below; an elbow on the leader reaches a slid label). Clear means off
			# the legend, the stage marks, the other label and the id tags; failing that it may cover
			# an id tag, then a mark; the selected stage's label always prints.
			var r := Rect2()
			var found := false
			for pass_i in 3:
				r = map._find_label(p, lsz, n == 0, avoid, marks if pass_i < 2 else no_tags, placed, others if pass_i == 0 else no_tags, size)
				if r.size.x > 0.0:
					found = true
					break
			if not found:
				if n > 0:
					continue
				var fx := p.x + 6.0 if p.x + 6.0 + tw <= size.x - 8.0 else p.x - 6.0 - tw
				r = Rect2(fx - 4.0, maxf(p.y - 100.0, map.label_floor + (lsz.y - 30.0) * 0.5) - lsz.y * 0.5, tw + 8.0, lsz.y)
			var x := r.position.x + 4.0
			var ly := r.get_center().y
			placed.append(r)
			if j < tags.size() and tags[j].intersects(r):
				hidden[j] = true
			var k := sel_k if n == 0 else 1.0
			var la := clampf((float(map._sel_t) - 0.3) / 0.2, 0.0, 1.0) if n == 0 else 1.0
			la *= settle
			var below := ly > p.y
			var y0 := p.y + (12.0 if below else -12.0)
			var y_edge: float = r.position.y if below else r.end.y
			var y_top := lerpf(y0, y_edge, k)
			var lc := SIGNAL if cur else INK
			# A label slid along its row: the leader turns at the label's middle and enters its side.
			var ex := clampf(p.x, r.position.x, r.end.x)
			var slid := absf(ex - p.x) > 1.0
			if slid:
				y_edge = ly
				y_top = lerpf(y0, y_edge, k)
			draw_line(Vector2(p.x, y0), Vector2(p.x, y_top), Color(PAPER if not cur else SIGNAL, 0.9 * settle), 1.0, true)
			if la <= 0.0:
				continue
			if slid:
				draw_line(Vector2(p.x, y_edge), Vector2(ex, y_edge), Color(lc, la), 1.0, true)
				draw_circle(Vector2(p.x, y_edge), 2.0, Color(lc, la))
			else:
				draw_line(Vector2(p.x - 4, y_edge), Vector2(p.x + 4, y_edge), Color(lc, la), 1.0, true)
			label_draws.append(func() -> void:
				draw_rect(r, Color(PAPER, 0.94 * la))
				draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), Color(lc, la))
				for li in lines.size():
					draw_string(f, Vector2(x + 2.0, r.position.y + 14.0 + 14.0 * li), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(lc, la))
				draw_string(fm, Vector2(x + 2.0, r.end.y - 4.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(lc, 0.8 * la)))
		for d: Callable in tag_draws:
			d.call()
		# Marks on the river.
		for j in pts.size():
			if j >= st.size():
				break
			var s: Dictionary = st[j]
			var p := pts[j]
			var status := str(s.get("status", "locked"))
			var boss := bool(s.get("boss", false))
			var r := 7.0 if not boss else 10.0
			if status == "current":
				var k := 0.5 + 0.5 * sin(t * 3.2)
				draw_arc(p, r + 6.0 + 3.0 * k, 0.0, TAU, 40, Color(SIGNAL, 0.8 - 0.4 * k), 1.4, true)
				if anim:
					for wv in 2:
						var ph := fmod(t / 2.2 + wv * 0.5, 1.0)
						var fade := (1.0 - ph) * (1.0 - ph)
						draw_arc(p, r + 6.0 + 30.0 * ph, 0.0, TAU, 48, Color(PAPER, 0.85 * fade), 1.6 - ph, true)
			if boss:
				var q := PackedVector2Array([p + Vector2(0, -r * 1.25), p + Vector2(r * 1.25, 0), p + Vector2(0, r * 1.25), p + Vector2(-r * 1.25, 0)])
				var bf := INK if status == "cleared" else (SIGNAL * 1.4 if status == "current" else PAPER)
				draw_colored_polygon(q, bf)
				q.append(q[0])
				draw_polyline(q, PAPER if status != "locked" else INK, 1.6, true)
			elif status == "cleared":
				draw_circle(p, r + 1.5, PAPER)
				draw_circle(p, r, INK)
				draw_line(p + Vector2(-3.5, 0), p + Vector2(-1, 2.6), PAPER, 1.5, true)
				draw_line(p + Vector2(-1, 2.6), p + Vector2(3.5, -2.6), PAPER, 1.5, true)
			elif status == "current":
				draw_circle(p, r + 1.5, PAPER)
				draw_circle(p, r, SIGNAL * 1.5)
				draw_circle(p, r * 0.38, PAPER)
			else:
				draw_circle(p, r, Color(INK, 0.85))
				draw_arc(p, r, 0.0, TAU, 32, PAPER, 1.4, true)
			if j == map.selected:
				var b := r + 8.0 + 12.0 * (1.0 - sel_k)
				for sx: float in [-1.0, 1.0]:
					for sy: float in [-1.0, 1.0]:
						var c0 := p + Vector2(sx * b, sy * b)
						draw_line(c0, c0 - Vector2(sx * 7.0, 0), PAPER, 2.0, true)
						draw_line(c0, c0 - Vector2(0, sy * 7.0), PAPER, 2.0, true)
		for d: Callable in label_draws:
			d.call()
