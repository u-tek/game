class_name RigData
extends RefCounted
## A built HaloRig, loaded once and shared by every RigPlayer of that hero. Two kinds:
##   "warp"   - one painted image on a skinned grid mesh (<id>.warp.json), the default for heroes
##   "cutout" - separate part images per bone (<id>.rig.json), used by the fallback silhouette
## Formats: docs/dev/halorig.md sections 4 (cutout) and 8 (warp).

const HEROES_DIR := "res://assets/art/heroes/"

var id := ""
var kind := "cutout"
# warp only
var image: Texture2D
var mesh: ArrayMesh
var body_bone := 0
var _mesh_skin := PackedFloat32Array()     ## per vertex b0,w0,b1,w1,b2,w2
var _mesh_verts := PackedVector2Array()
var _grid := Vector2i.ZERO
var _grid_origin := Vector2.ZERO
var _grid_cell := Vector2.ONE
var _grid_vid := {}                         ## Vector2i -> vertex index
var dir := ""
var texel := 1.0
var canvas := Vector2(1024, 2048)        ## source canvas / image size (portrait_rect units)
var look_px := Vector2(14, 8)
var meta := {}
var bounds := Rect2(-512, -1240, 1024, 1280)
var portrait_rect := Rect2()
var still_path := ""
var portrait_path := ""

# Bones, parents before children.
var bone_names := PackedStringArray()
var bone_index := {}
var parent := PackedInt32Array()
var local := PackedVector2Array()      ## setup offset from the parent pivot (rig units)
var setup_world := PackedVector2Array()## setup pivot in rig space (feet = 0,0)
var axis := PackedVector2Array()       ## rest direction pivot -> art (unit, rig space)
var length := PackedFloat32Array()
var look := PackedVector2Array()       ## head-turn parallax factors
var spring: Array = []                 ## Dictionary or null per bone
var bend := PackedFloat32Array()       ## static bend share for non-spring bend parts
var tip: Array = []                    ## Vector2 (bone space) or null

# Slots in draw order (back to front).
## {name, bone (int), z, default, attachments {variant: {texture: Texture2D, rect: Rect2}}}
var slots: Array = []
var slot_index := {}

static var _cache := {}


## Folder of a hero's art, or of one of her skins (skin_art = the skin's "art" folder name,
## data/skins.json): assets/art/heroes/<id>/skins/<art>/, laid out like the base art with
## <art>.warp.json, <art>.png, <art>_portrait.png and overlays/.
static func art_dir(hero_id: String, skin_art: String = "") -> String:
	if skin_art == "":
		return "%s%s/" % [HEROES_DIR, hero_id]
	return "%s%s/skins/%s/" % [HEROES_DIR, hero_id, skin_art]


static func exists(hero_id: String, skin_art: String = "") -> bool:
	var base := art_dir(hero_id, skin_art) + (hero_id if skin_art == "" else skin_art)
	return FileAccess.file_exists(base + ".warp.json") or FileAccess.file_exists(base + ".rig.json")


## Cached load (warp rig preferred, then cutout). Returns null if the hero (or that skin) has
## no built rig. A skin rig keeps id = hero_id, so per-hero animation overrides still apply.
static func load_rig(hero_id: String, skin_art: String = "") -> RigData:
	var key := hero_id if skin_art == "" else hero_id + "@" + skin_art
	if _cache.has(key):
		return _cache[key]
	var base := art_dir(hero_id, skin_art) + (hero_id if skin_art == "" else skin_art)
	var path := base + ".warp.json"
	if not FileAccess.file_exists(path):
		path = base + ".rig.json"
		if not FileAccess.file_exists(path):
			return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (str(d.get("format", "")) in ["halorig", "halowarp"]):
		push_error("RigData: bad rig file %s" % path)
		return null
	var r := RigData.new()
	r._load(d, hero_id, art_dir(hero_id, skin_art))
	_cache[key] = r
	return r


func _load(d: Dictionary, hero_id: String, art_folder: String = "") -> void:
	id = hero_id
	dir = art_folder if art_folder != "" else "%s%s/" % [HEROES_DIR, hero_id]
	texel = float(d.get("texel_scale", 1.0))
	var cv: Array = d.get("canvas", [1024, 2048])
	canvas = Vector2(cv[0], cv[1])
	var lp: Array = d.get("look_px", [24, 14])
	look_px = Vector2(lp[0], lp[1])
	meta = d.get("meta", {})
	if d.has("bounds"):
		var b: Array = d.bounds
		bounds = Rect2(b[0], b[1], b[2], b[3])
	var pr: Array = d.get("portrait_rect", [])
	if pr.size() == 4:
		portrait_rect = Rect2(pr[0], pr[1], pr[2], pr[3])
	still_path = dir + str(d.get("still", ""))
	portrait_path = dir + str(d.get("portrait", ""))
	for bj in d.get("bones", []):
		var i := bone_names.size()
		bone_names.append(str(bj.name))
		bone_index[str(bj.name)] = i
		var p := str(bj.get("parent", ""))
		parent.append(bone_index.get(p, -1))
		local.append(Vector2(float(bj.get("lx", 0.0)), float(bj.get("ly", 0.0))))
		setup_world.append(Vector2(float(bj.get("x", 0.0)), float(bj.get("y", 0.0))))
		var ax: Array = bj.get("axis", [0, 1])
		axis.append(Vector2(ax[0], ax[1]))
		length.append(float(bj.get("length", 0.0)))
		var lk: Array = bj.get("look", [0, 0])
		look.append(Vector2(lk[0], lk[1]))
		spring.append(bj.get("spring", null))
		bend.append(float(bj.get("bend", 0.0)))
		var tp: Variant = bj.get("tip", null)
		tip.append(Vector2(tp[0], tp[1]) if tp is Array else null)
	kind = "warp" if str(d.get("format", "")) == "halowarp" else "cutout"
	if kind == "warp":
		_load_warp(d)
	for sj in d.get("slots", []):
		var atts := {}
		for v in sj.get("attachments", {}):
			var a: Dictionary = sj.attachments[v]
			if not a.has("texture"):
				atts[v] = {"texture": null, "rect": Rect2()}     # warp: the base image already shows it
				continue
			var tex: Texture2D = load(dir + str(a.texture))
			atts[v] = {"texture": tex, "rect": Rect2(a.x, a.y, a.w, a.h)}
			if kind == "warp":
				atts[v]["mesh"] = _patch_mesh(Rect2(a.x, a.y, a.w, a.h))
		slot_index[str(sj.name)] = slots.size()
		slots.append({"name": str(sj.name), "bone": int(bone_index.get(str(sj.bone), 0)),
			"z": int(sj.get("z", 0)), "default": str(sj.get("default", "default")), "attachments": atts})


func _load_warp(d: Dictionary) -> void:
	image = load(dir + str(d.get("image", id + ".png")))
	body_bone = int(bone_index.get(str(d.get("body_bone", "hips")), 0))
	var m: Dictionary = d.get("mesh", {})
	var v: Array = m.get("vertices", [])
	var uv: Array = m.get("uvs", [])
	var sk: Array = m.get("skin", [])
	var tri: Array = m.get("triangles", [])
	var nv := v.size() / 2
	_mesh_verts.resize(nv)
	var uvs := PackedVector2Array()
	uvs.resize(nv)
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	c0.resize(nv * 4)
	c1.resize(nv * 4)
	_mesh_skin = PackedFloat32Array(sk)
	for i in nv:
		_mesh_verts[i] = Vector2(v[i * 2], v[i * 2 + 1])
		uvs[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
		c0[i * 4] = sk[i * 6]
		c0[i * 4 + 1] = sk[i * 6 + 1]
		c0[i * 4 + 2] = sk[i * 6 + 2]
		c0[i * 4 + 3] = sk[i * 6 + 3]
		c1[i * 4] = sk[i * 6 + 4]
		c1[i * 4 + 1] = sk[i * 6 + 5]
	mesh = _make_mesh(_mesh_verts, uvs, PackedInt32Array(tri), c0, c1)
	# grid lookup for interpolating skin weights under overlay patches
	var g: Array = m.get("grid", [24, 48])
	_grid = Vector2i(int(g[0]), int(g[1]))
	_grid_origin = bounds.position
	_grid_cell = Vector2(bounds.size.x / _grid.x, bounds.size.y / _grid.y)
	for i in nv:
		var gi := Vector2i(roundi((_mesh_verts[i].x - _grid_origin.x) / _grid_cell.x), roundi((_mesh_verts[i].y - _grid_origin.y) / _grid_cell.y))
		_grid_vid[gi] = i


static func _make_mesh(verts: PackedVector2Array, uvs: PackedVector2Array, idx: PackedInt32Array, c0: PackedFloat32Array, c1: PackedFloat32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	return m


## Skin influences at a rig-space point, bilinearly interpolated from the warp grid.
func skin_at(p: Vector2) -> Array:
	var fx := (p.x - _grid_origin.x) / _grid_cell.x
	var fy := (p.y - _grid_origin.y) / _grid_cell.y
	var i0 := clampi(floori(fx), 0, _grid.x - 1)
	var j0 := clampi(floori(fy), 0, _grid.y - 1)
	var tx := clampf(fx - i0, 0.0, 1.0)
	var ty := clampf(fy - j0, 0.0, 1.0)
	var acc := {}
	for c in [[0, 0, (1 - tx) * (1 - ty)], [1, 0, tx * (1 - ty)], [0, 1, (1 - tx) * ty], [1, 1, tx * ty]]:
		var vi: Variant = _grid_vid.get(Vector2i(i0 + c[0], j0 + c[1]), null)
		var wc: float = c[2]
		if vi == null or wc <= 0.0:
			continue
		var rest := 1.0
		for k in 3:
			var b := int(_mesh_skin[int(vi) * 6 + k * 2])
			var w := _mesh_skin[int(vi) * 6 + k * 2 + 1]
			acc[b] = float(acc.get(b, 0.0)) + w * wc
			rest -= w
		acc[body_bone] = float(acc.get(body_bone, 0.0)) + maxf(rest, 0.0) * wc
	var lst := []
	for b in acc:
		if b != body_bone:
			lst.append([b, acc[b]])
	lst.sort_custom(func(a, b2): return a[1] > b2[1])
	while lst.size() < 3:
		lst.append([body_bone, 0.0])
	return lst.slice(0, 3)


## Small skinned grid for an overlay patch (deforms exactly like the image under it).
func _patch_mesh(r: Rect2) -> ArrayMesh:
	var n := 4
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var p := r.position + Vector2(r.size.x * i / n, r.size.y * j / n)
			verts.append(p)
			uvs.append(Vector2(float(i) / n, float(j) / n))
			var sk := skin_at(p)
			c0.append_array([sk[0][0], sk[0][1], sk[1][0], sk[1][1]])
			c1.append_array([sk[2][0], sk[2][1], 0.0, 0.0])
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	return _make_mesh(verts, uvs, idx, c0, c1)


func bone(name: String) -> int:
	return int(bone_index.get(name, -1))


## Total pixels of part textures (memory estimate: x4 bytes, x1.33 with mipmaps).
func texture_pixels() -> int:
	var n := 0
	if image:
		n += image.get_width() * image.get_height()
	for s in slots:
		for v in s.attachments:
			var t: Texture2D = s.attachments[v].texture
			if t:
				n += t.get_width() * t.get_height()
	return n
