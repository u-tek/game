extends RefCounted
## Procedural chapter terrain for the v4 campaign survey map (src/ui/v4/survey/survey_map.gd), and the
## quests sheet's contours. A heightmap slab per chapter from a fixed seed, shaped like the chapter's
## world (its planet on the dossier: highland terraces, canyon mesas, crater fields, an ice shelf
## with cracks, volcanic ridges, crystal spikes), with the ten stage positions laid out as a
## serpentine route over it. The route IS the main river: it rises beyond the front edge, runs
## through every stage in order (meandering between them) and leaves past the boss over the back
## edge; tributaries join it from the sides and the valleys are carved along them. Pure data plus
## mesh building; nothing here touches Game.
##
##   var t := TerrainGen.new(chapter_index, "infernal")
##   t.mesh()            # ArrayMesh: the lit top surface and the cut sides of the slab
##   t.height_at(x, z)   # world height
##   t.stages            # PackedVector2Array of world (x, z), stage order
##   t.rivers[0]         # the main river (world (x, z)), stage_s[j]: stage j's distance along it
##
## World units: the slab spans x in [-W/2, W/2], z in [-D/2, D/2] (+z is the front edge, nearest
## the camera); heights run from 0 to about 1.5 above the slab's base at BASE.

const W := 11.0
const D := 7.0
## Grid cell size (world units).
const CELL := 0.1
const BASE := -0.9
## The six terrain kinds, one per chapter (they match the worlds in data/worlds.json).
const KINDS := ["highland", "canyons", "craters", "ice", "lava", "crystal"]
## Samples of the river curve per stage-to-stage span.
const STEPS := 14

var chapter := 0
var faction := "celestial"
var kind := "highland"
var seed_value := 0
var nx := 0
var nz := 0
## Heights (nx * nz, row-major by z).
var heights := PackedFloat32Array()
## Distance to the nearest river (world units, capped at RIVER_REACH).
var river_d := PackedFloat32Array()
## Rivers as world (x, z) polylines; the main river (the route) first.
var rivers: Array[PackedVector2Array] = []
## Stage positions, world (x, z), in stage order.
var stages := PackedVector2Array()
## The route through the stages: the main river from stage 1 to the last stage.
var route := PackedVector2Array()
## Each stage's distance along rivers[0] (world units), and the main river's length.
var stage_s := PackedFloat32Array()
var river_len := 0.0
var h_min := 0.0
var h_max := 1.0

const RIVER_REACH := 1.2


func _init(chapter_index: int = 0, faction_name: String = "celestial", stage_count: int = 10) -> void:
	chapter = chapter_index
	faction = faction_name
	kind = KINDS[posmod(chapter_index, KINDS.size())]
	seed_value = 7919 * (chapter_index + 3) + 101
	nx = int(round(W / CELL)) + 1
	nz = int(round(D / CELL)) + 1
	_layout_stages(stage_count)
	_make_rivers()
	_river_field()
	_make_heights()


# ------------------------------------------------------------------ layout

## Stage positions: a serpentine over three rows from the front edge to the boss at the back.
## The point set is spaced for the map's camera (yaw +22, pitch -30: at least ~74 px apart on a
## 540 px sheet); odd chapters run it the other way round, and a little seeded jitter makes each
## chapter its own place.
func _layout_stages(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rows: Array = [[0.12, 0.38, 0.64, 0.9], [0.74, 0.44, 0.14], [0.86, 0.56, 0.26]]
	var vs := [0.1, 0.5, 0.9]
	var uv := PackedVector2Array()
	for r in rows.size():
		for u: float in rows[r]:
			uv.append(Vector2(u + rng.randf_range(-0.015, 0.015), float(vs[r]) + rng.randf_range(-0.02, 0.02)))
	if chapter % 2 == 1:
		# The same marks, walked from the other side.
		var flipped := PackedVector2Array()
		var row_sizes := [4, 3, 3]
		var k := 0
		for r in row_sizes.size():
			var seg := uv.slice(k, k + int(row_sizes[r]))
			seg.reverse()
			flipped.append_array(seg)
			k += int(row_sizes[r])
		uv = flipped
	stages = PackedVector2Array()
	for i in mini(count, uv.size()):
		stages.append(_to_world(uv[i]))
	while stages.size() < count:
		stages.append(_to_world(Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))))


static func _to_world(uv: Vector2) -> Vector2:
	return Vector2((uv.x - 0.5) * W, (0.5 - uv.y) * D)


## A smooth curve through pts (cubic Hermite with slack tangents, so the serpentine's turns
## bend without looping), `steps` samples per span.
static func catmull(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	var tan := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		tan.append((b - a) * 0.32)
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var m0 := tan[i]
		var m1 := tan[i + 1]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append((2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1)
	out.append(pts[pts.size() - 1])
	return out


# ------------------------------------------------------------------ rivers

func _make_rivers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 17
	rivers.clear()
	# The main river is the route: from beyond the front edge, through every stage, out over the
	# back edge; between stages it meanders (a sideways bow that is zero at each stage).
	var n := stages.size()
	var pts := PackedVector2Array()
	var s0 := stages[0]
	var s_last := stages[n - 1]
	pts.append(Vector2(clampf(s0.x + (s0.x - stages[mini(1, n - 1)].x) * 0.18, -W * 0.45, W * 0.45), D * 0.5 + 0.9))
	pts.append_array(stages)
	pts.append(Vector2(clampf(s_last.x + (s_last.x - stages[maxi(n - 2, 0)].x) * 0.18, -W * 0.45, W * 0.45), -D * 0.5 - 0.9))
	var curve := catmull(pts, STEPS)
	var main := PackedVector2Array()
	for i in curve.size():
		var span := i / STEPS
		var t := float(i % STEPS) / STEPS
		var a := curve[maxi(i - 1, 0)]
		var b := curve[mini(i + 1, curve.size() - 1)]
		var dir := (b - a).normalized()
		var bow := sin(PI * t) * (0.22 + 0.12 * sin(float(span) * 2.3 + float(seed_value % 7))) * (1.0 if span % 2 == 0 else -1.0)
		bow += sin(TAU * t) * 0.07
		main.append(curve[i] + Vector2(-dir.y, dir.x) * bow)
	rivers.append(main)
	stage_s = PackedFloat32Array()
	var acc := 0.0
	for i in main.size():
		if i > 0:
			acc += main[i - 1].distance_to(main[i])
		if i % STEPS == 0 and i / STEPS >= 1 and i / STEPS <= n:
			stage_s.append(acc)
	river_len = acc
	route = main.slice(STEPS, STEPS * n + 1)
	# Tributaries: from points near the side edges, bending into the main river.
	for k in 4:
		var join_i := int(main.size() * rng.randf_range(0.2, 0.85))
		var join := main[join_i]
		var from_left := k % 2 == 0
		var start := _to_world(Vector2(-0.04 if from_left else 1.04, rng.randf_range(0.08, 0.95)))
		var mid := (start + join) * 0.5 + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var trib := PackedVector2Array()
		var m := 36
		for j in m + 1:
			var s := float(j) / m
			var pa := start.lerp(mid, s)
			var pb := mid.lerp(join, s)
			var p := pa.lerp(pb, s)
			# A little wobble so it reads as a stream, not a curve.
			var w := sin(s * 17.0 + k * 2.1) * 0.12 * (1.0 - s)
			var d2 := (pb - pa).normalized()
			trib.append(p + Vector2(-d2.y, d2.x) * w)
		rivers.append(trib)


## Distance to the nearest river per grid point, by stamping discs along the rivers.
func _river_field() -> void:
	river_d = PackedFloat32Array()
	river_d.resize(nx * nz)
	river_d.fill(RIVER_REACH)
	var r_cells := int(ceil(RIVER_REACH / CELL))
	for poly in rivers:
		for i in poly.size() - 1:
			var a := poly[i]
			var b := poly[i + 1]
			var seg := a.distance_to(b)
			var steps := maxi(1, int(ceil(seg / (CELL * 1.2))))
			for s in steps:
				var p := a.lerp(b, float(s) / steps)
				var gx := int(round((p.x + W * 0.5) / CELL))
				var gz := int(round((p.y + D * 0.5) / CELL))
				if gx < -r_cells or gx > nx + r_cells or gz < -r_cells or gz > nz + r_cells:
					continue
				for z in range(maxi(gz - r_cells, 0), mini(gz + r_cells + 1, nz)):
					var wz := z * CELL - D * 0.5
					var dz := wz - p.y
					var row := z * nx
					for x in range(maxi(gx - r_cells, 0), mini(gx + r_cells + 1, nx)):
						var dx := x * CELL - W * 0.5 - p.x
						var d := sqrt(dx * dx + dz * dz)
						if d < river_d[row + x]:
							river_d[row + x] = d


# ------------------------------------------------------------------ heights

func _make_heights() -> void:
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 5
	fn.frequency = 0.16
	var ridge := FastNoiseLite.new()
	ridge.seed = seed_value + 3
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.frequency = 0.13
	var fine := FastNoiseLite.new()
	fine.seed = seed_value + 9
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fine.fractal_type = FastNoiseLite.FRACTAL_FBM
	fine.fractal_octaves = 3
	fine.frequency = 0.9
	var cell := FastNoiseLite.new()
	cell.seed = seed_value + 21
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	cell.frequency = 1.1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 29
	# A few peaks (volcanoes for the lava world, spires of rock for the others) and craters.
	var peaks: Array[Vector3] = []
	for k in 3:
		peaks.append(Vector3(rng.randf_range(-W * 0.4, W * 0.4), rng.randf_range(-D * 0.45, D * 0.1), rng.randf_range(0.7, 1.3)))
	var craters: Array[Vector3] = []
	for k in 9:
		craters.append(Vector3(rng.randf_range(-W * 0.48, W * 0.48), rng.randf_range(-D * 0.48, D * 0.48), rng.randf_range(0.28, 0.95)))
	heights = PackedFloat32Array()
	heights.resize(nx * nz)
	h_min = 1e9
	h_max = -1e9
	for z in nz:
		var wz := z * CELL - D * 0.5
		# Higher ground towards the back (the far edge), lowlands at the front.
		var back := clampf((-wz / D) + 0.5, 0.0, 1.0)
		for x in nx:
			var wx := x * CELL - W * 0.5
			var i := z * nx + x
			var base := fn.get_noise_2d(wx, wz) * 0.5 + 0.5
			var r := ridge.get_noise_2d(wx, wz) * 0.5 + 0.5
			var h := 0.0
			match kind:
				"canyons":
					# Mesas in strata: flat tops, stepped walls.
					var m := smoothstep(0.4, 0.6, base * 0.85 + back * 0.25)
					h = 0.22 + m * 0.8 + r * 0.12
					var s := h * 9.0
					h = lerpf(h, (floorf(s) + smoothstep(0.65, 0.95, s - floorf(s))) / 9.0, 0.6)
				"craters":
					h = 0.32 + base * 0.45 + back * 0.22 + r * 0.08
					for c in craters:
						var d := Vector2(wx - c.x, wz - c.y).length() / c.z
						if d < 1.6:
							h += ((d * d - 1.0) * 0.42 if d < 1.0 else 0.0) * c.z + exp(-pow((d - 1.0) / 0.26, 2.0)) * 0.24 * c.z
				"ice":
					# A smooth shelf split by cracks with pressure ridges along them.
					h = 0.3 + base * 0.32 + back * 0.28
					var crest := smoothstep(0.86, 0.97, r)
					h += smoothstep(0.7, 0.86, r) * 0.06 - crest * 0.1
				"lava":
					h = 0.25 + base * 0.35 + pow(r, 2.2) * 0.75 * (0.45 + back * 0.7)
					for p in peaks:
						var d := Vector2(wx - p.x, wz - p.y).length()
						var cone := maxf(0.0, 1.0 - d / (1.6 * p.z))
						h += pow(cone, 1.6) * 0.9 * p.z
						# The crater.
						h -= maxf(0.0, 1.0 - d / (0.32 * p.z)) * 0.35 * p.z
				"crystal":
					# Dust plains broken by fields of crystal spikes.
					h = 0.3 + base * 0.3 + back * 0.22
					var field := smoothstep(0.44, 0.58, base + back * 0.1)
					var cd := clampf(cell.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
					h += pow(clampf(1.0 - cd * 1.5, 0.0, 1.0), 1.2) * 0.85 * field
				_:
					# Highland: broken terraces (a shattered sanctum of plateaus).
					var t := (base * 0.9 + back * 0.45) * 5.0
					var step := floorf(t)
					var f := t - step
					h = (step + smoothstep(0.62, 0.92, f)) / 5.0 * 1.2 + 0.08 + r * 0.06
			# Fine relief everywhere (the model's grain), calmer in the valleys.
			h += (fine.get_noise_2d(wx, wz)) * 0.035
			# Carve the river valleys (the main river's widest).
			var rd := river_d[i]
			var valley := smoothstep(0.0, 1.0, rd)
			var floor_h := 0.06
			h = lerpf(floor_h, h, 0.32 + 0.68 * valley) if rd < 1.0 else h
			heights[i] = h
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
	# The river bed itself, a touch lower and flat.
	for i in heights.size():
		if river_d[i] < 0.16:
			heights[i] = minf(heights[i], h_min + 0.02)


func height_at(wx: float, wz: float) -> float:
	var gx := clampf((wx + W * 0.5) / CELL, 0.0, nx - 1.001)
	var gz := clampf((wz + D * 0.5) / CELL, 0.0, nz - 1.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var a := heights[z0 * nx + x0]
	var b := heights[z0 * nx + x0 + 1]
	var c := heights[(z0 + 1) * nx + x0]
	var d := heights[(z0 + 1) * nx + x0 + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


## River distance at a world point (bilinear over the grid).
func river_at(wx: float, wz: float) -> float:
	var gx := clampf((wx + W * 0.5) / CELL, 0.0, nx - 1.001)
	var gz := clampf((wz + D * 0.5) / CELL, 0.0, nz - 1.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var a := river_d[z0 * nx + x0]
	var b := river_d[z0 * nx + x0 + 1]
	var c := river_d[(z0 + 1) * nx + x0]
	var d := river_d[(z0 + 1) * nx + x0 + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


# ------------------------------------------------------------------ textures

## Heights as a float texture (0..1 over h_min..h_max), for the contour layer.
func height_texture() -> ImageTexture:
	var img := Image.create_empty(nx, nz, false, Image.FORMAT_RF)
	var span := maxf(h_max - h_min, 0.001)
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for i in heights.size():
		data[i] = (heights[i] - h_min) / span
	img.set_data(nx, nz, false, Image.FORMAT_RF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


## River distance as a float texture (0..1 over 0..RIVER_REACH), for the hydrography layer.
func river_texture() -> ImageTexture:
	var img := Image.create_empty(nx, nz, false, Image.FORMAT_RF)
	var data := PackedFloat32Array()
	data.resize(nx * nz)
	for i in river_d.size():
		data[i] = river_d[i] / RIVER_REACH
	img.set_data(nx, nz, false, Image.FORMAT_RF, data.to_byte_array())
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ mesh

## The slab: the lit top surface (UV = map 0..1, UV2 = (height 0..1, river distance 0..1), COLOR.r =
## cavity) and the four cut sides down to BASE (UV2.y = -1 marks them; their UV2.x is the river
## distance at that edge, so a river leaving the slab can pour down its side).
func mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var span := maxf(h_max - h_min, 0.001)
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	uvs.resize(nx * nz)
	uv2s.resize(nx * nz)
	cols.resize(nx * nz)
	for z in nz:
		for x in nx:
			var i := z * nx + x
			var h := heights[i]
			verts[i] = Vector3(x * CELL - W * 0.5, h, z * CELL - D * 0.5)
			var hl := heights[z * nx + maxi(x - 1, 0)]
			var hr := heights[z * nx + mini(x + 1, nx - 1)]
			var hd := heights[maxi(z - 1, 0) * nx + x]
			var hu := heights[mini(z + 1, nz - 1) * nx + x]
			norms[i] = Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			uvs[i] = Vector2(float(x) / (nx - 1), float(z) / (nz - 1))
			uv2s[i] = Vector2((h - h_min) / span, river_d[i] / RIVER_REACH)
			# Cavity: lower than the neighbourhood (4 cells away) darkens (cheap ambient occlusion).
			var ring := (heights[z * nx + maxi(x - 4, 0)] + heights[z * nx + mini(x + 4, nx - 1)] +
				heights[maxi(z - 4, 0) * nx + x] + heights[mini(z + 4, nz - 1) * nx + x]) * 0.25
			cols[i] = Color(clampf(0.5 + (ring - h) * 2.2, 0.0, 1.0), 0.0, 0.0, 1.0)
	for z in nz - 1:
		for x in nx - 1:
			var a := z * nx + x
			var b := a + 1
			var c := a + nx
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# Sides: front (z max), back (z min), left (x min), right (x max).
	var edges := [
		[range(nx), func(k: int) -> int: return (nz - 1) * nx + k, Vector3(0, 0, 1)],
		[range(nx - 1, -1, -1), func(k: int) -> int: return k, Vector3(0, 0, -1)],
		[range(nz - 1, -1, -1), func(k: int) -> int: return k * nx, Vector3(-1, 0, 0)],
		[range(nz), func(k: int) -> int: return k * nx + nx - 1, Vector3(1, 0, 0)],
	]
	for e: Array in edges:
		var ks: Array = e[0]
		var at: Callable = e[1]
		var nrm: Vector3 = e[2]
		var start := verts.size()
		var cnt := 0
		for k: int in ks:
			var vi: int = at.call(k)
			var top: Vector3 = verts[vi]
			verts.append(top)
			verts.append(Vector3(top.x, BASE, top.z))
			for _j in 2:
				norms.append(nrm)
				cols.append(Color(0.5, 0, 0, 1))
			uvs.append(Vector2(float(cnt), top.y))
			uvs.append(Vector2(float(cnt), BASE))
			var rd := river_d[vi] / RIVER_REACH
			uv2s.append(Vector2(rd, -1.0))
			uv2s.append(Vector2(rd, -1.0))
			cnt += 1
		for j in cnt - 1:
			var t0 := start + j * 2
			var b0 := t0 + 1
			var t1 := t0 + 2
			var b1 := t0 + 3
			idx.append_array([t0, t1, b0, t1, b1, b0])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
