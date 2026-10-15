class_name HeroArt
## Art access API used by screens. Contract: docs/dev/architecture.md section 6.
## Heroes are HaloRig characters (docs/dev/halorig.md): assets/art/heroes/<id>/ holds the
## SVG source, built part PNGs, <id>.rig.json, <id>_still.png and <id>_portrait.png.
## Heroes without built art fall back to a faction-tinted silhouette (rig, still, portrait).

const FACTION_COLORS := {
	"celestial": Color("f2c14e"),
	"infernal": Color("d9412b"),
	"fallen": Color("8e6ce0"),
}
const FALLBACK := "_silhouette"

static var _tinted := {}


## True if the hero has its own built rig art (not the silhouette fallback).
static func has_art(hero_id: String) -> bool:
	return FileAccess.file_exists("res://assets/art/heroes/%s/%s.rig.json" % [hero_id, hero_id])


## Full-body still (1024x2048 canvas at the rig's texel scale; feet near the bottom).
static func texture(hero_id: String) -> Texture2D:
	var path := "res://assets/art/heroes/%s/%s_still.png" % [hero_id, hero_id]
	if ResourceLoader.exists(path):
		return load(path)
	return _fallback_tex(hero_id, "still")


## Region of texture(hero_id) that frames the head and shoulders, for portraits.
static func portrait_region(hero_id: String) -> Rect2:
	var r := RigData.load_rig(hero_id if has_art(hero_id) else FALLBACK)
	if r == null or r.portrait_rect.size.x <= 0.0:
		var t := texture(hero_id)
		var w := t.get_width()
		return Rect2(w * 0.25, w * 0.05, w * 0.5, w * 0.5)
	return Rect2(r.portrait_rect.position * r.texel, r.portrait_rect.size * r.texel)


## Animated battle/stage sprite (HeroSprite: feet at origin, battle size at scale 1).
static func make_sprite(hero_id: String) -> Node2D:
	var s := HeroSprite.new()
	s.setup(hero_id)
	return s


## Square head-and-shoulders portrait (transparent background) of the given size.
static func make_portrait(hero_id: String, size: float) -> Control:
	var tr := TextureRect.new()
	tr.texture = _portrait_tex(hero_id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.custom_minimum_size = Vector2(size, size)
	tr.size = Vector2(size, size)
	return tr


static func _portrait_tex(hero_id: String) -> Texture2D:
	var path := "res://assets/art/heroes/%s/%s_portrait.png" % [hero_id, hero_id]
	if ResourceLoader.exists(path):
		return load(path)
	return _fallback_tex(hero_id, "portrait")


## Faction-tinted silhouette textures for heroes without art (built by tools/art_build from
## the _silhouette rig's data-tint-variants).
static func _fallback_tex(hero_id: String, kind: String) -> Texture2D:
	var faction := str(HeroData.get_def(hero_id).get("faction", "celestial"))
	var key := kind + ":" + faction
	if _tinted.has(key):
		return _tinted[key]
	var tex: Texture2D = null
	for path in ["res://assets/art/heroes/%s/%s_%s_%s.png" % [FALLBACK, FALLBACK, kind, faction],
			"res://assets/art/heroes/%s/%s_%s.png" % [FALLBACK, FALLBACK, kind]]:
		if ResourceLoader.exists(path):
			tex = load(path)
			break
	if tex == null:
		var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		im.fill(faction_color(faction).darkened(0.5))
		tex = ImageTexture.create_from_image(im)
	_tinted[key] = tex
	return tex


## Background texture: "home", "summon", "chapter-1", "chapter-2", "chapter-3".
static func background(kind: String) -> Texture2D:
	var path := "res://assets/art/backgrounds/%s.svg" % kind
	if ResourceLoader.exists(path):
		return load(path)
	path = "res://assets/art/backgrounds/%s.png" % kind
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, Color.WHITE)
