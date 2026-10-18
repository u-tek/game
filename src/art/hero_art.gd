class_name HeroArt
## Art access API used by screens. Contract: docs/dev/architecture.md section 6.
## Heroes are HaloRig characters (docs/dev/halorig.md): assets/art/heroes/<id>/ holds the
## SVG source, built part PNGs, <id>.rig.json, <id>_still.png and <id>_portrait.png.
## Heroes without built art fall back to a faction-tinted silhouette (rig, still, portrait).
## Skins (data/skins.json, docs/dev/skins.md): every call takes an optional skin id; its art lives
## in assets/art/heroes/<id>/skins/<art>/ with the same layout. A skin whose art is not built
## falls back to the base look, and "" always means the base look.

const FACTION_COLORS := {
	"celestial": Color("f2c14e"),
	"infernal": Color("d9412b"),
	"fallen": Color("8e6ce0"),
}
const FALLBACK := "_silhouette"

static var _tinted := {}


## True if the hero has its own built art (warp or cutout rig), not the silhouette fallback.
static func has_art(hero_id: String) -> bool:
	return RigData.exists(hero_id)


## True if the skin belongs to the hero and its art is built into the game.
static func has_skin_art(hero_id: String, skin_id: String) -> bool:
	var art := _skin_art(hero_id, skin_id)
	return art != "" and RigData.exists(hero_id, art)


## The art folder name of a skin of this hero, or "" (unknown skin, another hero's, or none).
static func _skin_art(hero_id: String, skin_id: String) -> String:
	if skin_id == "":
		return ""
	var sd := SkinData.get_def(skin_id)
	if sd.is_empty() or sd.hero != hero_id:
		return ""
	return str(sd.art)


## The built art folder to use: the skin's if its rig exists, else "" (base look).
static func _built_art(hero_id: String, skin_id: String) -> String:
	var art := _skin_art(hero_id, skin_id)
	return art if art != "" and RigData.exists(hero_id, art) else ""


## Full-body still (the painted image for warp rigs: ~1024x2048, feet near the bottom).
static func texture(hero_id: String, skin_id: String = "") -> Texture2D:
	var art := _built_art(hero_id, skin_id)
	if art != "" or has_art(hero_id):
		var r := RigData.load_rig(hero_id, art)
		if r != null and ResourceLoader.exists(r.still_path):
			return load(r.still_path)
	return _fallback_tex(hero_id, "still")


## Region of texture(hero_id, skin_id) that frames the head and shoulders, for portraits.
static func portrait_region(hero_id: String, skin_id: String = "") -> Rect2:
	var art := _built_art(hero_id, skin_id)
	var r := RigData.load_rig(hero_id, art) if art != "" else RigData.load_rig(hero_id if has_art(hero_id) else FALLBACK)
	var t := texture(hero_id, skin_id)
	if r == null or r.portrait_rect.size.x <= 0.0:
		var w := t.get_width()
		return Rect2(w * 0.25, w * 0.05, w * 0.5, w * 0.5)
	var k := float(t.get_width()) / maxf(r.canvas.x, 1.0)
	return Rect2(r.portrait_rect.position * k, r.portrait_rect.size * k)


## Animated battle/stage sprite (HeroSprite: feet at origin, battle size at scale 1).
static func make_sprite(hero_id: String, skin_id: String = "") -> Node2D:
	var s := HeroSprite.new()
	s.setup(hero_id, _built_art(hero_id, skin_id))
	return s


## Square head-and-shoulders portrait (transparent background) of the given size.
static func make_portrait(hero_id: String, size: float, skin_id: String = "") -> Control:
	var tr := TextureRect.new()
	tr.texture = _portrait_tex(hero_id, skin_id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.custom_minimum_size = Vector2(size, size)
	tr.size = Vector2(size, size)
	return tr


static func _portrait_tex(hero_id: String, skin_id: String = "") -> Texture2D:
	var art := _built_art(hero_id, skin_id)
	if art != "":
		var sp := RigData.art_dir(hero_id, art) + art + "_portrait.png"
		if ResourceLoader.exists(sp):
			return load(sp)
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
	for ext in ["png", "jpg"]:      # painted backdrops are JPEGs (assets/art/backgrounds/)
		path = "res://assets/art/backgrounds/%s.%s" % [kind, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


static func faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, Color.WHITE)
