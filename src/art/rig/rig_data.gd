class_name RigData
extends RefCounted
## A built HaloRig (assets/art/heroes/<id>/<id>.rig.json + part PNGs), loaded once and shared
## by every RigPlayer of that hero. Format: docs/dev/halorig.md section 4.

const HEROES_DIR := "res://assets/art/heroes/"

var id := ""
var dir := ""
var texel := 1.0
var look_px := Vector2(24, 14)
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


static func exists(hero_id: String) -> bool:
	return ResourceLoader.exists("%s%s/%s.rig.json" % [HEROES_DIR, hero_id, hero_id]) \
		or FileAccess.file_exists("%s%s/%s.rig.json" % [HEROES_DIR, hero_id, hero_id])


## Cached load. Returns null if the hero has no built rig.
static func load_rig(hero_id: String) -> RigData:
	if _cache.has(hero_id):
		return _cache[hero_id]
	var path := "%s%s/%s.rig.json" % [HEROES_DIR, hero_id, hero_id]
	if not FileAccess.file_exists(path):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or str(d.get("format", "")) != "halorig":
		push_error("RigData: bad rig file %s" % path)
		return null
	var r := RigData.new()
	r._load(d, hero_id)
	_cache[hero_id] = r
	return r


func _load(d: Dictionary, hero_id: String) -> void:
	id = hero_id
	dir = "%s%s/" % [HEROES_DIR, hero_id]
	texel = float(d.get("texel_scale", 1.0))
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
	for sj in d.get("slots", []):
		var atts := {}
		for v in sj.get("attachments", {}):
			var a: Dictionary = sj.attachments[v]
			var tex: Texture2D = load(dir + str(a.texture))
			atts[v] = {"texture": tex, "rect": Rect2(a.x, a.y, a.w, a.h)}
		slot_index[str(sj.name)] = slots.size()
		slots.append({"name": str(sj.name), "bone": int(bone_index.get(str(sj.bone), 0)),
			"z": int(sj.get("z", 0)), "default": str(sj.get("default", "default")), "attachments": atts})


func bone(name: String) -> int:
	return int(bone_index.get(name, -1))


## Total pixels of part textures (memory estimate: x4 bytes, x1.33 with mipmaps).
func texture_pixels() -> int:
	var n := 0
	for s in slots:
		for v in s.attachments:
			var t: Texture2D = s.attachments[v].texture
			if t:
				n += t.get_width() * t.get_height()
	return n
