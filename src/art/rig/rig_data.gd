class_name RigData
extends RefCounted
## A built HaloRig, loaded once and shared by every RigPlayer of that hero. Two kinds:
##   "warp"   - painted image layers on skinned grid meshes (<id>.warp.json), the default for heroes
##   "cutout" - separate part images per bone (<id>.rig.json), used by the fallback silhouette
## Formats: docs/dev/halorig.md sections 4 (cutout) and 8 (warp).

const HEROES_DIR := "res://assets/art/heroes/"

var id := ""
var kind := "cutout"
# warp only
var image: Texture2D                      ## the painted image (the base layer)
var mesh: ArrayMesh                        ## the base layer's mesh
## Warp layers, back to front: {name, z, image: Texture2D, mesh: ArrayMesh}. Format 1 rigs have one
## (the painting); format 2 rigs may add parts peeled off it (docs/dev/halorig.md section 11).
var layers: Array = []
var version := 1
## Format 2 rigs built with turn data: vertices carry depth and turn shares, influences 2-3 are
## packed (warp_skin.gdshaderinc; RigPlayer.set head/body turn).
var packed := false
var _mesh_turn := PackedVector3Array()    ## base layer, per vertex (depth, head share, body share)
var body_bone := 0
var _skin_n := 3                           ## influences per vertex in _mesh_skin (3: format 1, 4: format 2)
var _mesh_skin := PackedFloat32Array()     ## base layer, per vertex b0,w0,b1,w1,b2,w2(,b3,w3)
var _mesh_verts := PackedVector2Array()
var _grid := Vector2i.ZERO
var _grid_origin := Vector2.ZERO
var _grid_cell := Vector2.ONE
var _grid_vid := {}                         ## Vector2i -> vertex index
var dir := ""
var texel := 1.0
var canvas := Vector2(1024, 2048)        ## source canvas / image size (portrait_rect units)
## Where her soles stand on the canvas (rig space is canvas px from this point).
var origin := Vector2(512, 1990)
var look_px := Vector2(14, 8)
var meta := {}
var bounds := Rect2(-512, -1240, 1024, 1280)
var portrait_rect := Rect2()
var still_path := ""
var portrait_path := ""
var _base := ""                          ## file base this rig was loaded from (load_rig)
var _face := Vector4.ZERO                ## face_ellipse() cache
var _core := Rect2()                     ## core_rect() cache

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


## Folder of an art variant ("adult": the nude art) under the art it belongs to.
const ADULT := "adult"


## Folder of a hero's art, or of one of her skins (skin_art = the skin's "art" folder name,
## data/skins.json): assets/art/heroes/<id>/skins/<art>/, laid out like the base art with
## <art>.warp.json, <art>.png, <art>_portrait.png and overlays/. The art string names a look:
##   ""            the base look        assets/art/heroes/<id>/              files <id>.*
##   "<art>"       a skin               assets/art/heroes/<id>/skins/<art>/  files <art>.*
##   "<art>/adult" the skin's nude art  assets/art/heroes/<id>/skins/<art>/adult/  files <art>.*
##   "/adult"      the base nude art    assets/art/heroes/<id>/adult/        files <id>.*
## (rig ids in the tools: <id>, <id>@<art>, <id>@<art>@adult, <id>@@adult; docs/dev/halorig.md 8.1)
static func art_dir(hero_id: String, skin_art: String = "") -> String:
	var skin := skin_art.get_slice("/", 0)
	var variant := skin_art.substr(skin.length() + 1) if skin_art.contains("/") else ""
	var d := "%s%s/" % [HEROES_DIR, hero_id] if skin == "" else "%s%s/skins/%s/" % [HEROES_DIR, hero_id, skin]
	return d + variant + "/" if variant != "" else d


## The nude variant of a look: "<art>/adult" for a skin, "/adult" for the base look ("").
static func adult_art(skin_art: String = "") -> String:
	return skin_art + "/" + ADULT


## Path without extension of an art's files: <dir><id> for the base look, <dir><art> for a skin.
## A variant subfolder keeps the names of the art it belongs to ("<art>/adult": <art>.*,
## "/adult": <id>.*).
static func file_base(hero_id: String, skin_art: String = "") -> String:
	var skin := skin_art.get_slice("/", 0)
	return art_dir(hero_id, skin_art) + (hero_id if skin == "" else skin)


static func exists(hero_id: String, skin_art: String = "") -> bool:
	var base := file_base(hero_id, skin_art)
	return FileAccess.file_exists(base + ".warp.json") or FileAccess.file_exists(base + ".rig.json")


## Cached load (warp rig preferred, then cutout). Returns null if the hero (or that skin) has
## no built rig. A skin rig keeps id = hero_id, so per-hero animation overrides still apply.
static func load_rig(hero_id: String, skin_art: String = "") -> RigData:
	var key := hero_id if skin_art == "" else hero_id + "@" + skin_art
	if _cache.has(key):
		return _cache[key]
	var base := file_base(hero_id, skin_art)
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
	r._base = base
	_cache[key] = r
	return r


func _load(d: Dictionary, hero_id: String, art_folder: String = "") -> void:
	id = hero_id
	dir = art_folder if art_folder != "" else "%s%s/" % [HEROES_DIR, hero_id]
	texel = float(d.get("texel_scale", 1.0))
	var cv: Array = d.get("canvas", [1024, 2048])
	canvas = Vector2(cv[0], cv[1])
	var og: Array = d.get("origin", [canvas.x * 0.5, canvas.y - 58.0])
	origin = Vector2(og[0], og[1])
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
	version = int(d.get("version", 1))
	body_bone = int(bone_index.get(str(d.get("body_bone", "hips")), 0))
	var cr: Array = d.get("core", [])
	if cr.size() == 4:
		_core = Rect2(cr[0], cr[1], cr[2], cr[3])
	if version >= 2:
		for lj: Dictionary in d.get("layers", []):
			_load_layer(lj, layers.is_empty())
		layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.z) < int(b.z))
		return
	image = load(dir + str(d.get("image", id + ".png")))
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
	layers = [{"name": "image", "z": 0, "image": image, "mesh": mesh}]


## A format 2 layer: a uniform grid of `cell` px over `rect` (image px: x, y, cols, rows), the kept
## cells as one byte each and four influences per used grid point as bytes (b0 w0 b1 w1 b2 w2 b3
## w3, weights /255), both deflated and base64. Grid points are numbered row by row, skipping
## points no kept cell uses. `image_rect` places the layer's image on the canvas (default: all of
## it). The base layer also feeds skin_at() (overlay patches) and core_rect().
func _load_layer(lj: Dictionary, base: bool) -> void:
	var tex: Texture2D = load(dir + str(lj.get("image", id + ".png")))
	var m: Dictionary = lj.get("mesh", {})
	var cell := float(m.get("cell", 12))
	var r: Array = m.get("rect", [0, 0, 1, 1])
	var x0 := float(r[0])
	var y0 := float(r[1])
	var cols := int(r[2])
	var rows := int(r[3])
	var ir: Array = lj.get("image_rect", [0, 0, canvas.x, canvas.y])
	var nv := int(m.get("n", 0))
	var cells := Marshalls.base64_to_raw(str(m.get("cells", ""))).decompress(cols * rows, FileAccess.COMPRESSION_DEFLATE)
	var sk := Marshalls.base64_to_raw(str(m.get("skin", ""))).decompress(nv * 8, FileAccess.COMPRESSION_DEFLATE)
	var tn := PackedByteArray()
	if m.has("turn"):
		tn = Marshalls.base64_to_raw(str(m.turn)).decompress(nv * 4, FileAccess.COMPRESSION_DEFLATE)
		packed = tn.size() == nv * 4
	if cells.size() != cols * rows or sk.size() != nv * 8:
		push_error("RigData[%s]: bad mesh in layer %s" % [id, str(lj.get("name", ""))])
		return
	var vid := PackedInt32Array()
	vid.resize((cols + 1) * (rows + 1))
	vid.fill(-1)
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	verts.resize(nv)
	uvs.resize(nv)
	c0.resize(nv * 4)
	c1.resize(nv * 4)
	var iw := maxf(float(ir[2]), 1.0)
	var ih := maxf(float(ir[3]), 1.0)
	var n := 0
	for j in rows + 1:
		for i in cols + 1:
			var used := (j > 0 and i > 0 and cells[(j - 1) * cols + i - 1] != 0) 				or (j > 0 and i < cols and cells[(j - 1) * cols + i] != 0) 				or (j < rows and i > 0 and cells[j * cols + i - 1] != 0) 				or (j < rows and i < cols and cells[j * cols + i] != 0)
			if not used or n >= nv:
				continue
			vid[j * (cols + 1) + i] = n
			var px := x0 + i * cell
			var py := y0 + j * cell
			verts[n] = Vector2(px - origin.x, py - origin.y)
			uvs[n] = Vector2((px - float(ir[0])) / iw, (py - float(ir[1])) / ih)
			var o := n * 8
			c0[n * 4] = sk[o]
			c0[n * 4 + 1] = sk[o + 1] / 255.0
			c0[n * 4 + 2] = sk[o + 2]
			c0[n * 4 + 3] = sk[o + 3] / 255.0
			if packed:
				c1[n * 4] = sk[o + 4] + sk[o + 5] / 255.0 * 0.98
				c1[n * 4 + 1] = sk[o + 6] + sk[o + 7] / 255.0 * 0.98
				c1[n * 4 + 2] = (tn[n * 4] - 128) / 100.0
				c1[n * 4 + 3] = tn[n * 4 + 1] + tn[n * 4 + 2] / 255.0 * 0.98
			else:
				c1[n * 4] = sk[o + 4]
				c1[n * 4 + 1] = sk[o + 5] / 255.0
				c1[n * 4 + 2] = sk[o + 6]
				c1[n * 4 + 3] = sk[o + 7] / 255.0
			n += 1
	var idx := PackedInt32Array()
	for j in rows:
		for i in cols:
			if cells[j * cols + i] == 0:
				continue
			var a := vid[j * (cols + 1) + i]
			var b := vid[j * (cols + 1) + i + 1]
			var c := vid[(j + 1) * (cols + 1) + i + 1]
			var e := vid[(j + 1) * (cols + 1) + i]
			idx.append_array([a, b, c, a, c, e])
	var lm := _make_mesh(verts, uvs, idx, c0, c1)
	layers.append({"name": str(lj.get("name", "layer")), "z": int(lj.get("z", 0)), "image": tex, "mesh": lm})
	if not base:
		return
	image = tex
	mesh = lm
	_skin_n = 4
	_mesh_verts = verts
	_mesh_skin.resize(nv * 8)
	for k in nv * 8:
		_mesh_skin[k] = sk[k] if k % 2 == 0 else sk[k] / 255.0
	if packed:
		_mesh_turn.resize(nv)
		for k in nv:
			_mesh_turn[k] = Vector3((tn[k * 4] - 128) / 100.0, tn[k * 4 + 1] / 255.0, tn[k * 4 + 2] / 255.0)
	_grid = Vector2i(cols, rows)
	_grid_origin = Vector2(x0 - origin.x, y0 - origin.y)
	_grid_cell = Vector2(cell, cell)
	for jj in rows + 1:
		for ii in cols + 1:
			var v := vid[jj * (cols + 1) + ii]
			if v >= 0:
				_grid_vid[Vector2i(ii, jj)] = v


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
		var st := _skin_n * 2
		for k in _skin_n:
			var b := int(_mesh_skin[int(vi) * st + k * 2])
			var w := _mesh_skin[int(vi) * st + k * 2 + 1]
			acc[b] = float(acc.get(b, 0.0)) + w * wc
			rest -= w
		acc[body_bone] = float(acc.get(body_bone, 0.0)) + maxf(rest, 0.0) * wc
	var lst := []
	for b in acc:
		if b != body_bone:
			lst.append([b, acc[b]])
	lst.sort_custom(func(a, b2): return a[1] > b2[1])
	while lst.size() < 4:
		lst.append([body_bone, 0.0])
	return lst.slice(0, 4)


## Depth and turn shares at a rig-space point (packed rigs), bilinear from the base layer's grid.
func turn_at(p: Vector2) -> Vector3:
	if _mesh_turn.is_empty():
		return Vector3.ZERO
	var fx := (p.x - _grid_origin.x) / _grid_cell.x
	var fy := (p.y - _grid_origin.y) / _grid_cell.y
	var i0 := clampi(floori(fx), 0, _grid.x - 1)
	var j0 := clampi(floori(fy), 0, _grid.y - 1)
	var tx := clampf(fx - i0, 0.0, 1.0)
	var ty := clampf(fy - j0, 0.0, 1.0)
	var acc := Vector3.ZERO
	var wsum := 0.0
	for c in [[0, 0, (1 - tx) * (1 - ty)], [1, 0, tx * (1 - ty)], [0, 1, (1 - tx) * ty], [1, 1, tx * ty]]:
		var vi: Variant = _grid_vid.get(Vector2i(i0 + c[0], j0 + c[1]), null)
		if vi == null:
			continue
		acc += _mesh_turn[int(vi)] * float(c[2])
		wsum += float(c[2])
	return acc / wsum if wsum > 0.0 else Vector3.ZERO


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
			if packed:
				var tv := turn_at(p)
				c1.append_array([float(sk[2][0]) + clampf(sk[2][1], 0.0, 1.0) * 0.98, float(sk[3][0]) + clampf(sk[3][1], 0.0, 1.0) * 0.98,
					tv.x, floorf(tv.y * 255.0 + 0.5) + clampf(tv.z, 0.0, 1.0) * 0.98])
			else:
				c1.append_array([sk[2][0], sk[2][1], sk[3][0], sk[3][1]])
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	return _make_mesh(verts, uvs, idx, c0, c1)


func bone(name: String) -> int:
	return int(bone_index.get(name, -1))


## Her face as an ellipse in rig space: (centre x, centre y, radius x, radius y). From the warp
## source's "face" region (<base>.warp_src.json, the hand-drawn rig regions) when it has one, else
## estimated from portrait_rect (portraits are framed on the face), else around the "face" bone.
## For effects that must leave her face alone (the Legendary foil, HeroSprite.holo). Cached.
func face_ellipse() -> Vector4:
	if _face != Vector4.ZERO:
		return _face
	var src_path := _base + ".warp_src.json"
	if _base != "" and FileAccess.file_exists(src_path):
		var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(src_path))
		if src is Dictionary:
			var og: Array = (src as Dictionary).get("origin", [origin.x, origin.y])
			var k := 1.0
			if (src as Dictionary).has("image_size"):
				k = canvas.x / maxf(float(((src as Dictionary).image_size as Array)[0]), 1.0)
			for reg: Variant in (src as Dictionary).get("regions", []):
				if not (reg is Dictionary) or str((reg as Dictionary).get("name", "")) != "face":
					continue
				var rule: Dictionary = (reg as Dictionary).get("rule", {})
				if str(rule.get("type", "")) == "ellipse":
					var c: Array = rule.get("center", [0, 0])
					var rr: Array = rule.get("radius", [60, 50])
					_face = Vector4((float(c[0]) - float(og[0])) * k, (float(c[1]) - float(og[1])) * k,
						float(rr[0]) * k, float(rr[1]) * k)
					return _face
	if portrait_rect.size.x > 0.0:
		var s := portrait_rect.size.x
		var pc := portrait_rect.get_center() - origin
		_face = Vector4(pc.x, pc.y + s * 0.016, s * 0.175, s * 0.147)
		return _face
	var fb := bone("face")
	var at := setup_world[fb] if fb >= 0 else Vector2(0.0, bounds.position.y * 0.82)
	_face = Vector4(at.x, at.y + 10.0, 70.0, 60.0)
	return _face


## Which shared animation set this rig plays (RigAnim.find): "warp2" for format 2 warp rigs (their
## idle is procedural, RigPlayer._idle_drive), else the kind.
func anim_kind() -> String:
	return "warp2" if kind == "warp" and version >= 2 else kind


## Bone name prefixes of the parts a tight frame may cut off (core_rect).
const CROPPABLE := ["wing", "tail", "weapon", "cape", "ribbon"]


## Her body without the parts a tight frame may cut (wings, tail, weapon, cape, ribbons): the
## bounds, in rig space, of the warp mesh vertices whose heaviest bone is none of those. Views that
## fill the screen with her frame this and let the rest run off the edge (HeroArt.fit_sprite).
## Cutout rigs and rigs without a mesh return bounds. Cached.
func core_rect() -> Rect2:
	if _core.size != Vector2.ZERO:
		return _core
	var st := _skin_n * 2
	if kind != "warp" or _mesh_verts.is_empty() or _mesh_skin.size() < _mesh_verts.size() * st:
		_core = bounds
		return _core
	var crop := {}
	for i in bone_names.size():
		for pre: String in CROPPABLE:
			if bone_names[i].begins_with(pre):
				crop[i] = true
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in _mesh_verts.size():
		var best := body_bone
		var best_w := 1.0
		for k in _skin_n:
			best_w -= _mesh_skin[i * st + k * 2 + 1]
		for k in _skin_n:
			var w := _mesh_skin[i * st + k * 2 + 1]
			if w > best_w:
				best_w = w
				best = int(_mesh_skin[i * st + k * 2])
		if crop.has(best):
			continue
		lo = lo.min(_mesh_verts[i])
		hi = hi.max(_mesh_verts[i])
	_core = Rect2(lo, hi - lo) if lo.x <= hi.x else bounds
	return _core


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
