class_name HeroArt
## Art access API (STUB - owned by the art agents). Contract: docs/dev/architecture.md.

const FACTION_COLORS := {
	"celestial": Color("f2c14e"),
	"infernal": Color("d9412b"),
	"fallen": Color("8e6ce0"),
}


## Full-body texture for a hero (assets/art/heroes/<id>.svg).
static func texture(hero_id: String) -> Texture2D:
	var path := "res://assets/art/heroes/%s.svg" % hero_id
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(256, 320, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.4, 0.7))
	return ImageTexture.create_from_image(img)


## Region of texture(hero_id) that frames the face, for portraits.
static func portrait_region(hero_id: String) -> Rect2:
	var t := texture(hero_id)
	var w := t.get_width()
	return Rect2(w * 0.1875, w * 0.078, w * 0.625, w * 0.625)


## Animated battle/stage sprite. See contract for methods.
static func make_sprite(hero_id: String) -> Node2D:
	var s := Sprite2D.new()
	s.texture = texture(hero_id)
	return s


## Square portrait control of the given size.
static func make_portrait(hero_id: String, size: float) -> Control:
	var at := AtlasTexture.new()
	at.atlas = texture(hero_id)
	at.region = portrait_region(hero_id)
	var tr := TextureRect.new()
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	return tr


## Background texture: "home", "summon", "chapter-1", "chapter-2", "chapter-3".
static func background(kind: String) -> Texture2D:
	var path := "res://assets/art/backgrounds/%s.svg" % kind
	if ResourceLoader.exists(path):
		return load(path)
	return null


static func faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, Color.WHITE)
