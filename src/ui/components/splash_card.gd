extends Control
## SplashCard: an animated splash card (loading screens, event banners, promo) built from the layers
## tools/comfy/splash.py writes: assets/art/splash/<name>/ with layout.json, plate.png and one
## hero_<n>_<id>.png per hero (each a full-card RGBA layer). The plate drifts slowly, each hero
## breathes on its own phase and a soft light sweep crosses the card, so a still painting feels alive.
## Fills its rect (cover), keeping the card's aspect.
## Nudity mode (HeroArt.nudity, the "nudity" setting): a card may carry a nude version in
## assets/art/splash/<name>/adult/ (its own layout.json and/or any of the layer files, same names);
## with nudity on each file is read from adult/ when it is there, else from the card's folder, so a
## card without adult art shows its normal layers.
##   var c := SplashCard.make("celestial_trio")   # null if the card is not installed
##   add_child(c); c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

const DIR := "res://assets/art/splash/"

var card := ""
## True when at least one layer (or the layout) came from the card's adult/ folder.
var adult := false
var _plate: TextureRect
var _heroes: Array[TextureRect] = []
var _sweep: ColorRect
var _t := 0.0
var _size := Vector2(1920, 1080)


## Card names installed under assets/art/splash/ (folders with a layout.json).
static func installed() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_directories():
		if FileAccess.file_exists(DIR + f + "/layout.json"):
			out.append(f)
	return out


static func make(name: String) -> Control:
	var p := DIR + name + "/layout.json"
	if not FileAccess.file_exists(p):
		return null
	var c: Control = load("res://src/ui/components/splash_card.gd").new()
	c.call("_load", name)
	return c


## Where a card's file is read from: <name>/adult/<file> when nudity is on and that file exists
## (a resource or plain file), else <name>/<file>.
static func file_path(card_name: String, file: String) -> String:
	var a := DIR + card_name + "/adult/" + file
	if HeroArt.nudity and (ResourceLoader.exists(a) or FileAccess.file_exists(a)):
		return a
	return DIR + card_name + "/" + file


func _load(name: String) -> void:
	card = name
	clip_contents = true
	mouse_filter = MOUSE_FILTER_IGNORE
	var lp := file_path(name, "layout.json")
	adult = lp.contains("/adult/")
	var lj: Variant = JSON.parse_string(FileAccess.get_file_as_string(lp))
	if not (lj is Dictionary):
		push_error("SplashCard: bad layout for %s" % name)
		return
	var sz: Array = lj.get("size", [1920, 1080])
	_size = Vector2(sz[0], sz[1])
	_plate = _layer(file_path(name, str(lj.get("plate", "plate.png"))))
	for h: Dictionary in lj.get("heroes", []):
		_heroes.append(_layer(file_path(name, str(h.file))))
	_sweep = ColorRect.new()
	_sweep.mouse_filter = MOUSE_FILTER_IGNORE
	_sweep.color = Color(1, 1, 1, 0.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sweep.material = mat
	add_child(_sweep)
	resized.connect(_fit)


func _layer(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	adult = adult or path.contains("/adult/")
	add_child(tr)
	return tr


## Cover-fit every layer (a little oversized so the drift never shows an edge).
func _fit() -> void:
	var k := maxf(size.x / _size.x, size.y / _size.y) * 1.04
	var s := _size * k
	var off := (size - s) * 0.5
	for tr in [_plate] + _heroes:
		if tr:
			tr.size = s
			tr.position = off
			tr.pivot_offset = s * Vector2(0.5, 1.0)
	_sweep.size = Vector2(s.x * 0.18, s.y * 1.4)
	_sweep.position.y = off.y - s.y * 0.2
	_sweep.rotation = 0.35


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _plate == null:
		return
	_t += delta
	var k := maxf(size.x / _size.x, size.y / _size.y)
	# The plate drifts slowly; heroes drift a little the other way (parallax) and breathe.
	_plate.position.x = (size.x - _plate.size.x) * 0.5 + sin(_t * 0.18) * 14.0 * k
	for i in _heroes.size():
		var h := _heroes[i]
		h.position.x = (size.x - h.size.x) * 0.5 - sin(_t * 0.18) * (6.0 + 3.0 * i) * k
		var b := 1.0 + 0.008 * sin(_t * 1.3 + i * 1.7)
		h.scale = Vector2(b, b)
	# A light sweep every ~7 s.
	var ph := fmod(_t, 7.0) / 7.0
	_sweep.position.x = lerpf(-_sweep.size.x * 2.0, size.x + _sweep.size.x, ph)
	_sweep.color = Color(1, 1, 1, 0.07 * sin(ph * PI))
