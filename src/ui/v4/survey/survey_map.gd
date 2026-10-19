extends Control
## The campaign's printed survey map (style v4 "Signal", poster look; docs/dev/ui-style-v4.md): one
## chapter as an exploded isometric map, the owner's layered-map reference drawn as print on paper.
## A real 3D slab (TerrainGen heightmap) printed as halftone relief with ink contours and signal-red
## rivers, and above it three vellum sheets pulled apart: CONTOURS (ink), HYDROGRAPHY (signal veins
## and rivers) and the STAGE layer (survey grid). On top, in 2D: the route on the stage layer, the
## printed stage marks (cleared ink, current signal, locked hollow, bosses as diamonds), leader lines down
## to each stage's place on the terrain, stage ids, and the layer names along each sheet's edge.
##
##   var m := SurveyMap.new(); m.size = ...; add_child(m)
##   m.show_chapter(ci, faction, stages)   # stages: [{id, name, status, boss}] in order
##   m.select(j); m.stage_pressed.connect(func(j: int) -> void: ...)
##
## A drag turns the map (IsoView); a tap picks the nearest stage mark (within TAP_R px).
##
## Alive but calm (all of it off with Reduce motion, which prints the map still): the view renders
## at 30 fps (IsoView) with a slow auto-orbit and a little tilt parallax; the sheets lift off the
## terrain on open, then float apart and back out of phase; the rivers run as signal dashes along
## their ribbons; a scan band sweeps the CONTOURS sheet while its iso-lines shimmer uphill; cloud
## shadows and valley mist drift over the slab (the halftone dots grow under the clouds); the route
## draws on to the current stage, then a signal pulse runs along it now and then; the current mark
## sends out ring waves; a selected stage's leader lines draw on and its label follows.

signal stage_pressed(index: int)

const IsoView := preload("res://src/ui/v4/survey/iso_view.gd")
const TerrainGen := preload("res://src/ui/v4/survey/terrain_gen.gd")
const TERRAIN_SHADER := preload("res://src/ui/v4/survey/print_terrain.gdshader")
const LAYER_SHADER := preload("res://src/ui/v4/survey/print_layer.gdshader")
const RIVER_SHADER := preload("res://src/ui/v4/survey/print_river.gdshader")
## The sheets' float: amplitude (world units, contours / hydrography / stages) and period (s).
const FLOAT_AMP := [0.09, 0.13, 0.17]
const FLOAT_PERIOD := 7.5
## Seconds for the route to draw on (after the sheets have lifted), and the pulse's cycle.
const ROUTE_DRAW := 1.2
const PULSE_EVERY := 5.0
const PULSE_RUN := 1.6

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")
const TAP_R := 74.0
## Sheet heights above the terrain's base level (world units).
const Y_CONTOURS := 2.6
const Y_HYDRO := 4.4
const Y_STAGES := 6.2

## Layout knobs (set before show_chapter).
var yaw := 22.0
var pitch := -30.0
var ortho_width := 15.0
var shift := Vector2(0.0, 0.0)
## Raised labels never go above this y (view px): clear of the title block.
var label_floor := 0.0
## The world height the camera centres on (the middle of the stack).
var target_y := 2.65
## The picture reaches this far above and below the map's tap area (x: top, y: bottom px).
var overscan := Vector2.ZERO

## Generated chapters, kept for the session so switching back is instant ("ci:faction:count" ->
## TerrainGen), with their slab mesh and the sheets' textures (height, river field, veins).
static var _terrains: Dictionary = {}
static var _meshes: Dictionary = {}
static var _textures: Dictionary = {}
## Seamless noise for the drifting clouds and mist (shared by every chapter).
static var _cloud_tex: Texture2D

var view: IsoView
var terrain: TerrainGen
var faction := "celestial"
var stages: Array = []
var selected := -1
var _overlay: Control
var _layers: Array[MeshInstance3D] = []
var _layer_y: Array[float] = []
var _explode := 1.0
var _t := 0.0
## Route draw-on progress (0..1) and seconds since the last selection (leaders draw on).
var _route_k := 1.0
var _sel_t := 99.0
var _pts := PackedVector2Array()
var _ground := PackedVector2Array()
var _route2d := PackedVector2Array()
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
		_terrains[key] = TerrainGen.new(ci, faction, stages.size())
		_meshes[key] = (_terrains[key] as TerrainGen).mesh()
	terrain = _terrains[key]
	_mesh_key = key
	for c in view.world.get_children():
		c.queue_free()
	_layers.clear()
	_layer_y.clear()
	_build_slab()
	_build_layers()
	var anim := Kit.motion_ok()
	_explode = 0.0 if anim else 1.0
	_route_k = 0.0 if anim else 1.0
	_place_sheets()
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


# ------------------------------------------------------------------ 3D

func _palette() -> Dictionary:
	match faction:
		"infernal":
			# Two-colour print: the relief in signal red, the cut sides in ink.
			return {"dot": SIGNAL, "bias": -0.02, "ambient": 0.2, "contour": 0.12, "side": Color("141517"), "river_w": 0.07}
		"fallen":
			return {"dot": INK, "bias": -0.14, "ambient": 0.16, "contour": 0.14, "side": Color("0c0c0e"), "river_w": 0.05}
		_:
			return {"dot": Color("2a2c31"), "bias": 0.1, "ambient": 0.3, "contour": 0.1, "side": Color("1d1f23"), "river_w": 0.045}


func _build_slab() -> void:
	var pal := _palette()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[_mesh_key] if _meshes.has(_mesh_key) else terrain.mesh()
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("paper", PAPER)
	m.set_shader_parameter("ink", INK)
	m.set_shader_parameter("dot_ink", pal["dot"])
	m.set_shader_parameter("river", SIGNAL)
	m.set_shader_parameter("side_ink", pal["side"])
	m.set_shader_parameter("bias", pal["bias"])
	m.set_shader_parameter("ambient", pal["ambient"])
	m.set_shader_parameter("contour_a", pal["contour"])
	m.set_shader_parameter("river_w", pal["river_w"])
	m.set_shader_parameter("cell", 4.6 * view.render_scale())
	m.set_shader_parameter("base_y", TerrainGen.BASE)
	# Cloud shadows and valley mist drifting over the relief (still with Reduce motion).
	m.set_shader_parameter("cloud_tex", _clouds())
	m.set_shader_parameter("clouds", 1.0)
	m.set_shader_parameter("mist", 1.0 if faction != "infernal" else 0.6)
	m.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)
	mi.material_override = m
	view.world.add_child(mi)


## The shared seamless noise the clouds and the mist are cut from.
static func _clouds() -> Texture2D:
	if _cloud_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 4127
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 4
		n.frequency = 0.011
		_cloud_tex = ImageTexture.create_from_image(n.get_seamless_image(256, 256))
	return _cloud_tex


func _build_layers() -> void:
	var size2 := Vector2(TerrainGen.W, TerrainGen.D)
	if not _textures.has(_mesh_key):
		var vn := FastNoiseLite.new()
		vn.seed = terrain.seed_value + 5
		vn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		vn.fractal_type = FastNoiseLite.FRACTAL_FBM
		vn.fractal_octaves = 3
		vn.frequency = 0.012
		_textures[_mesh_key] = [terrain.height_texture(), terrain.river_texture(), ImageTexture.create_from_image(vn.get_seamless_image(256, 256))]
	var texs: Array = _textures[_mesh_key]
	var htex: Texture2D = texs[0]
	var rtex: Texture2D = texs[1]
	var vtex: Texture2D = texs[2]
	var specs := [[Y_CONTOURS, 1], [Y_HYDRO, 2], [Y_STAGES, 0]]
	for s: Array in specs:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = size2
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = LAYER_SHADER
		m.set_shader_parameter("mode", int(s[1]))
		m.set_shader_parameter("height_tex", htex)
		m.set_shader_parameter("river_tex", rtex)
		m.set_shader_parameter("vein_tex", vtex)
		m.set_shader_parameter("paper", PAPER)
		m.set_shader_parameter("ink", INK)
		m.set_shader_parameter("accent", SIGNAL)
		m.set_shader_parameter("plane_size", size2)
		m.set_shader_parameter("vellum", 0.14 if int(s[1]) != 0 else 0.3)
		m.set_shader_parameter("line_a", 1.0)
		# The contours sheet: a slow scan band and shimmering iso-lines (none with Reduce motion).
		m.set_shader_parameter("scan", 1.0 if int(s[1]) == 1 and Kit.motion_ok() else 0.0)
		m.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)
		mi.material_override = m
		mi.position.y = float(s[0])
		view.world.add_child(mi)
		_layers.append(mi)
		_layer_y.append(float(s[0]))
		if int(s[1]) == 2:
			_add_rivers(mi)


## The rivers on the hydrography sheet: flat signal ribbons just above it. UV.x runs along each
## river (world units from its source, so the dashes flow downstream at one speed), UV.y across.
func _add_rivers(sheet: MeshInstance3D) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var rivers: Array = terrain.rivers
	for k in rivers.size():
		var poly: PackedVector2Array = rivers[k]
		var w := 0.034 if k == 0 else 0.02
		# Each river starts at its own phase so the dashes don't march in step.
		var s := float(k) * 0.37
		for i in poly.size() - 1:
			var a := _clip_xz(poly[i])
			var b := _clip_xz(poly[i + 1])
			var seg := a.distance_to(b)
			if seg < 0.0001:
				continue
			var d := (b - a) / seg
			var n := Vector2(-d.y, d.x) * w
			var a0 := Vector3(a.x + n.x, 0.004, a.y + n.y)
			var a1 := Vector3(a.x - n.x, 0.004, a.y - n.y)
			var b0 := Vector3(b.x + n.x, 0.004, b.y + n.y)
			var b1 := Vector3(b.x - n.x, 0.004, b.y - n.y)
			verts.append_array([a0, b0, a1, b0, b1, a1])
			var s1 := s + seg
			uvs.append_array([Vector2(s, 0), Vector2(s1, 0), Vector2(s, 1), Vector2(s1, 0), Vector2(s1, 1), Vector2(s, 1)])
			s = s1
	if verts.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = am
	var mat := ShaderMaterial.new()
	mat.shader = RIVER_SHADER
	mat.set_shader_parameter("river", SIGNAL)
	mat.set_shader_parameter("paper", PAPER)
	mat.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)
	mi.material_override = mat
	sheet.add_child(mi)


static func _clip_xz(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -TerrainGen.W * 0.5, TerrainGen.W * 0.5), clampf(p.y, -TerrainGen.D * 0.5, TerrainGen.D * 0.5))


## A render tick of the view (IsoView.frame, 30 fps while animating): the sheets lift, then float;
## the route draws on; the selection's leaders draw on; then the overlay is placed again.
func _on_frame(dt: float) -> void:
	_t += dt
	if _explode < 1.0:
		_explode = minf(_explode + dt / 0.9, 1.0)
	else:
		_route_k = minf(_route_k + dt / ROUTE_DRAW, 1.0)
		_sel_t += dt
	_place_sheets()
	_reproject()


## Each sheet's height: lifted off the terrain in turn on open (the top one travels furthest), then
## floating apart and back, out of phase with the others.
func _place_sheets() -> void:
	var base := 1.6
	var anim := Kit.motion_ok()
	for i in _layers.size():
		var k := clampf(_explode * 1.35 - i * 0.12, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var y := lerpf(base, _layer_y[i], e)
		if anim:
			y += sin(_t * TAU / FLOAT_PERIOD + i * 1.3) * float(FLOAT_AMP[mini(i, FLOAT_AMP.size() - 1)]) * e
		_layers[i].position.y = y


## World y of the stage sheet right now (it rises while the map opens).
func _stage_y() -> float:
	return _layers[_layers.size() - 1].position.y if not _layers.is_empty() else Y_STAGES


func _reproject() -> void:
	if terrain == null or view == null or view.camera == null:
		return
	var sy := _stage_y()
	_pts.resize(0)
	_ground.resize(0)
	var sp: PackedVector2Array = terrain.stages
	for p in sp:
		_pts.append(view.project(Vector3(p.x, sy, p.y)))
		_ground.append(view.project(Vector3(p.x, terrain.height_at(p.x, p.y), p.y)))
	_route2d.resize(0)
	for p: Vector2 in terrain.route:
		_route2d.append(view.project(Vector3(p.x, sy, p.y)))
	_overlay.queue_redraw()


## The four corners of a sheet at height y (front-left first, clockwise as seen from above).
func sheet_corners(y: float) -> PackedVector2Array:
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


## Draws the printed overlay: route, leader lines, marks, ids and the sheet names.
class _Overlay:
	extends Control
	var map

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if map == null or map.terrain == null:
			return
		var pts: PackedVector2Array = map._pts
		var ground: PackedVector2Array = map._ground
		var route: PackedVector2Array = map._route2d
		var st: Array = map.stages
		var reached: int = map._reached
		var t: float = map._t
		var anim := Kit.motion_ok()
		# The selection's leaders draw on (0..1, eased).
		var sel_k := 1.0 - pow(1.0 - clampf(float(map._sel_t) / 0.4, 0.0, 1.0), 3.0)
		var f := Kit.font("mono_bold")
		var fm := Kit.font("mono")
		_sheet_labels(fm, f)
		# Leader lines: from each stage mark down to its place on the terrain.
		for j in pts.size():
			var cur := j < st.size() and str(st[j].get("status", "")) == "current"
			var c := Color(SIGNAL, 0.9) if cur else Color(INK, 0.35)
			var k := sel_k if j == map.selected else 1.0
			_dashed(pts[j], pts[j].lerp(ground[j], k), c, 1.0, 4.0, 3.0)
			if k >= 1.0:
				draw_line(ground[j] - Vector2(4, 0), ground[j] + Vector2(4, 0), Color(c, 0.9), 1.0, true)
				draw_line(ground[j] - Vector2(0, 4), ground[j] + Vector2(0, 4), Color(c, 0.9), 1.0, true)
		# The route on the stage sheet: solid ink to the furthest open stage (drawn on as the map
		# opens, then a signal pulse runs along it now and then), dashed beyond.
		if route.size() > 1:
			var per := (route.size() - 1) / maxf(float(pts.size() - 1), 1.0)
			var cut := int(round(reached * per))
			if cut > 0:
				var solid := route.slice(0, cut + 1)
				var total := _poly_len(solid)
				var rk: float = map._route_k
				if rk >= 1.0:
					draw_polyline(solid, INK, 2.2, true)
					var pk := fmod(t, PULSE_EVERY) / PULSE_RUN
					if anim and pk < 1.0:
						# A short signal run with a fading tail, from the first stage to the current one.
						var head := total * (1.0 - pow(1.0 - pk, 2.0))
						var tail := 46.0
						for q in 4:
							var a0 := head - tail * (q + 1) / 4.0
							var a1 := head - tail * q / 4.0
							var seg := _poly_cut(solid, maxf(a0, 0.0), maxf(a1, 0.0))
							if seg.size() > 1:
								draw_polyline(seg, Color(SIGNAL, 0.95 - q * 0.22), 3.0, true)
				else:
					var e := 1.0 - pow(1.0 - rk, 2.0)
					var drawn := _poly_cut(solid, 0.0, total * e)
					if drawn.size() > 1:
						draw_polyline(drawn, INK, 2.2, true)
						draw_circle(drawn[drawn.size() - 1], 3.5, SIGNAL * 1.4)
			if cut < route.size() - 1:
				_dashed_poly(route.slice(cut), Color(INK, 0.6), 1.3, 6.0, 5.0)
		# Marks.
		for j in pts.size():
			if j >= st.size():
				break
			var s: Dictionary = st[j]
			var p := pts[j]
			var status := str(s.get("status", "locked"))
			var boss := bool(s.get("boss", false))
			var r := 9.0 if not boss else 12.0
			if status == "current":
				var k := 0.5 + 0.5 * sin(t * 3.2)
				draw_circle(p, r + 9.0 + 4.0 * k, Color(SIGNAL, 0.14 * (1.0 - k) + 0.04))
				draw_arc(p, r + 6.0 + 3.0 * k, 0.0, TAU, 40, Color(SIGNAL, 0.7 - 0.4 * k), 1.2, true)
				if anim:
					# Ring waves going out from the mark, two at a time.
					for wv in 2:
						var ph := fmod(t / 2.2 + wv * 0.5, 1.0)
						var fade := (1.0 - ph) * (1.0 - ph)
						draw_arc(p, r + 6.0 + 34.0 * ph, 0.0, TAU, 48, Color(SIGNAL, 0.8 * fade), 1.8 - ph, true)
			if boss:
				var q := PackedVector2Array([p + Vector2(0, -r * 1.25), p + Vector2(r * 1.25, 0), p + Vector2(0, r * 1.25), p + Vector2(-r * 1.25, 0)])
				var fill := INK if status == "cleared" else (SIGNAL * 1.5 if status == "current" else PAPER)
				draw_colored_polygon(q, fill)
				q.append(q[0])
				draw_polyline(q, INK if status != "current" else SIGNAL, 1.6, true)
				var q2 := PackedVector2Array()
				for v in q:
					q2.append(p + (v - p) * 1.45)
				draw_polyline(q2, Color(INK, 0.8 if status != "locked" else 0.45), 1.0, true)
			elif status == "cleared":
				draw_circle(p, r, INK)
				draw_line(p + Vector2(-4, 0), p + Vector2(-1, 3), PAPER, 1.6, true)
				draw_line(p + Vector2(-1, 3), p + Vector2(4, -3), PAPER, 1.6, true)
			elif status == "current":
				draw_circle(p, r, SIGNAL * 1.6)
				draw_circle(p, r * 0.38, PAPER)
			else:
				draw_circle(p, r, PAPER)
				draw_arc(p, r, 0.0, TAU, 32, Color(INK, 0.6), 1.3, true)
			# The stage id beside the mark.
			var id := str(s.get("id", ""))
			var col := SIGNAL if status == "current" else (INK if status != "locked" else Color(INK, 0.5))
			draw_string(f, p + Vector2(r + 6.0, -r * 0.2), id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			if boss:
				draw_string(fm, p + Vector2(r + 6.0, 11.0), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
			if j == map.selected:
				# The corner brackets close in on the mark as it is selected.
				var b := r + 9.0 + 12.0 * (1.0 - sel_k)
				for sx: float in [-1.0, 1.0]:
					for sy: float in [-1.0, 1.0]:
						var c0 := p + Vector2(sx * b, sy * b)
						draw_line(c0, c0 - Vector2(sx * 7.0, 0), INK, 1.6, true)
						draw_line(c0, c0 - Vector2(0, sy * 7.0), INK, 1.6, true)
		# Tall leaders rising from the selected stage and the boss to labels above the stack.
		var top_c: PackedVector2Array = map.sheet_corners(map._stage_y())
		var top_y := INF
		for c in top_c:
			top_y = minf(top_y, c.y)
		var raised: Array[int] = []
		if map.selected >= 0:
			raised.append(map.selected)
		for j in st.size():
			if bool(st[j].get("boss", false)) and j == st.size() - 1 and not raised.has(j):
				raised.append(j)
		var placed: Array[Rect2] = []
		for n in raised.size():
			var j: int = raised[n]
			if j >= pts.size():
				continue
			var p := pts[j]
			var s: Dictionary = st[j]
			var cur := str(s.get("status", "")) == "current"
			var lc := SIGNAL if cur else INK
			var title := "%s  %s" % [str(s.get("id", "")), str(s.get("name", "")).to_upper()]
			var sub := "BOSS STAGE" if bool(s.get("boss", false)) else ("NEXT" if cur else str(s.get("status", "")).to_upper())
			var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var x := p.x + 6.0
			if x + tw > size.x - 8.0:
				x = p.x - 6.0 - tw
			# The selected stage rises above the whole stack; the boss gets a short leader. Labels
			# never overlap: a clash moves the later one up.
			var ly := maxf(top_y - 34.0, map.label_floor) if n == 0 else p.y - 52.0
			var r := Rect2(x - 3.0, ly - 15.0, tw + 6.0, 30.0)
			if placed.any(func(q: Rect2) -> bool: return q.grow(3.0).intersects(r)) or (n > 0 and ly - 15.0 < map.label_floor):
				# No room for a second callout here: the mark's own id says enough.
				continue
			placed.append(r)
			# The selected stage's leader grows up from its mark, then its label prints in.
			var k := sel_k if n == 0 else 1.0
			var la := clampf((float(map._sel_t) - 0.3) / 0.2, 0.0, 1.0) if n == 0 else 1.0
			var y_top := lerpf(p.y - 14.0, ly, k)
			draw_line(p - Vector2(0, 14), Vector2(p.x, y_top), Color(lc, 0.85), 1.0, true)
			if la <= 0.0:
				continue
			draw_line(Vector2(p.x - 4, ly), Vector2(p.x + 4, ly), Color(lc, la), 1.0, true)
			draw_rect(r, Color(PAPER, 0.92 * la))
			draw_string(f, Vector2(x, ly - 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(lc, la))
			draw_string(fm, Vector2(x, ly + 11.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(lc, 0.8 * la))

	## Each sheet's name on a paper tag along its left edge (front-left corner towards the back).
	func _sheet_labels(fm: Font, f: Font) -> void:
		var names := ["CONTOURS", "HYDROGRAPHY", "STAGES / ROUTE"]
		var layers: Array = map._layers
		for i in layers.size():
			var y: float = (layers[i] as Node3D).position.y
			var c: PackedVector2Array = map.sheet_corners(y)
			_edge_label("%02d  %s" % [i + 2, names[i]], c[0], c[1], f, 10)
		var g: PackedVector2Array = map.sheet_corners(0.0)
		_edge_label("01  TERRAIN  1:25 000", g[0], g[1], fm, 10)

	func _edge_label(text: String, a: Vector2, b: Vector2, f: Font, fs: int) -> void:
		var d := b - a
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(a + d.normalized() * 10.0, d.angle(), Vector2.ONE)
		# A paper tag just outside the edge, ink type on it.
		draw_rect(Rect2(-3.0, -fs - 9.0, tw + 6.0, fs + 5.0), PAPER)
		draw_string(f, Vector2(0.0, -7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## A dashed polyline (dashes follow the curve's length).
	func _dashed_poly(pts: PackedVector2Array, c: Color, w: float, on: float, off: float) -> void:
		var draw_on := true
		var left := on
		for k in range(1, pts.size()):
			var a := pts[k - 1]
			var b := pts[k]
			var seg := a.distance_to(b)
			var t := 0.0
			while t < seg:
				var step := minf(left, seg - t)
				if draw_on:
					draw_line(a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), c, w, true)
				t += step
				left -= step
				if left <= 0.0:
					draw_on = not draw_on
					left = on if draw_on else off

	static func _poly_len(pts: PackedVector2Array) -> float:
		var l := 0.0
		for k in range(1, pts.size()):
			l += pts[k - 1].distance_to(pts[k])
		return l

	## The part of a polyline between two lengths along it (px from its start).
	static func _poly_cut(pts: PackedVector2Array, from_len: float, to_len: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		if to_len <= from_len or pts.size() < 2:
			return out
		var acc := 0.0
		for k in range(1, pts.size()):
			var a := pts[k - 1]
			var b := pts[k]
			var seg := a.distance_to(b)
			var s0 := acc
			var s1 := acc + seg
			acc = s1
			if s1 < from_len or seg <= 0.0:
				continue
			if s0 > to_len:
				break
			if out.is_empty():
				out.append(a.lerp(b, clampf((from_len - s0) / seg, 0.0, 1.0)))
			out.append(a.lerp(b, clampf((to_len - s0) / seg, 0.0, 1.0)))
			if s1 >= to_len:
				break
		return out

	func _dashed(a: Vector2, b: Vector2, c: Color, w: float, on: float, off: float) -> void:
		var len := a.distance_to(b)
		if len < 0.5:
			return
		var d := (b - a) / len
		var s := 0.0
		while s < len:
			draw_line(a + d * s, a + d * minf(s + on, len), c, w, true)
			s += on + off
