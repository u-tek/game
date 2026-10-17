extends Control
## Campaign map node for one stage (style v2): a flat-top hexagon.
##   cleared  cyan hex, white stage id, small check badge
##   current  dark hex with a glowing, pulsing orange rim
##   locked   dim graphite hex with a lock
## Bosses are bigger with a red "roof" band and the boss's face cropped into the hex.
## `selected` adds cyan corner brackets around the node. Built with setup(); the screen makes
## it tappable with Kit.make_tappable.

const KitBox := preload("res://src/ui/components/kit_box.gd")

var stage_id := ""
var status := "locked"
var is_boss := false
var tint := Color("f2c14e")
var boss_id := ""
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _t := 0.0
var _font: Font
var _check: Texture2D
var _lock: Texture2D
var _crop: AtlasTexture


func setup(id: String, st: String, boss: bool, faction_tint: Color, diameter: float, boss_hero: String = "") -> void:
	stage_id = id
	status = st
	is_boss = boss
	tint = faction_tint
	boss_id = boss_hero
	mouse_filter = MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size
	_font = Kit.font("cond_black")
	_check = Kit.icon_texture("check")
	_lock = Kit.icon_texture("lock")
	if is_boss and boss_id != "":
		var c: Variant = Kit.art_crop(boss_id, 1.0, 1.5)
		if c is AtlasTexture:
			_crop = c
	set_process(status == "current")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var ci := get_canvas_item()
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 8.0
	var hex := KitBox.hex_points(c, r, true)
	var locked := status == "locked"
	var current := status == "current"
	var cleared := status == "cleared"
	var pulse := 0.5 + 0.5 * sin(_t * 3.4)
	# Glow and shadow.
	if current:
		KitBox.soft_shadow(ci, hex, Color(1.0, 0.55, 0.1, 0.35 + 0.25 * pulse), 18.0)
	KitBox.soft_shadow(ci, hex, Color(0, 0, 0, 0.45), 8.0, Vector2(0, 4))
	# Face.
	if cleared:
		KitBox.fill_poly(ci, hex, Kit.ACCENT.lightened(0.1), Kit.ACCENT_DEEP)
	elif current:
		KitBox.fill_poly(ci, hex, Color("1b2a47"), Color("0d1425"))
	else:
		KitBox.fill_poly(ci, hex, Color("182641"), Color("0e1628"))
	# Boss face (clipped to the hex) under a red roof band.
	if is_boss and _crop and not locked:
		_draw_crop(KitBox.hex_points(c, r - 3.0, true), Color(1, 1, 1, 0.9 if not cleared else 0.55))
	if is_boss:
		var roof := KitBox.clip_convex(hex, PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, c.y - r * 0.5), Vector2(0, c.y - r * 0.5)]))
		if roof.size() >= 3:
			KitBox.fill_poly(ci, roof, Color(Kit.EMBER, 0.95 if not locked else 0.45), Color(Kit.EMBER.darkened(0.3), 0.95 if not locked else 0.45))
			_draw_text("BOSS", Vector2(c.x, c.y - r * 0.62), int(r * 0.26), Color.WHITE)
	if cleared:
		KitBox.hatch(ci, hex, Color(1, 1, 1, 0.14), 8.0, 2.0, 0.55, 1.0)
	# Rim.
	if current:
		KitBox.stroke_poly(ci, hex, Kit.ORANGE.lerp(Kit.ORANGE_HI, 0.4 * pulse), 4.0)
		KitBox.stroke_poly(ci, KitBox.offset_poly(hex, -7.0), Color(1.0, 0.7, 0.3, 0.35), 1.5)
	elif cleared:
		KitBox.stroke_poly(ci, hex, Color(1, 1, 1, 0.85), 2.0)
	else:
		KitBox.stroke_poly(ci, hex, Color(1, 1, 1, 0.22), 1.5)
	# Label or lock.
	if locked:
		if _lock:
			var ls := r * 0.72
			draw_texture_rect(_lock, Rect2(c - Vector2(ls, ls) * 0.5 + Vector2(0, r * 0.08), Vector2(ls, ls)), false, Color(1, 1, 1, 0.45))
	elif not (is_boss and _crop):
		_draw_text(stage_id, c + Vector2(0, r * 0.06), int(r * (0.58 if stage_id.length() <= 3 else 0.48)), Color.WHITE)
	else:
		# Boss: the id on a dark tab at the bottom of the hex.
		var tab := Rect2(c.x - r * 0.55, c.y + r * 0.42, r * 1.1, r * 0.4)
		draw_rect(tab, Color(0, 0, 0, 0.7))
		_draw_text(stage_id, Vector2(c.x, tab.get_center().y), int(r * 0.32), Color.WHITE)
	# Cleared badge.
	if cleared and _check:
		var bc := c + Vector2(r * 0.72, r * 0.6)
		var br := r * 0.26
		draw_circle(bc, br + 2.0, Color.WHITE, true, -1.0, true)
		draw_circle(bc, br, Color("1f9e63"), true, -1.0, true)
		draw_texture_rect(_check, Rect2(bc - Vector2(br, br) * 0.7, Vector2(br, br) * 1.4), false)
	# Selection brackets.
	if selected:
		var sr := Rect2(c - Vector2(r + 7.0, r + 7.0), Vector2(r + 7.0, r + 7.0) * 2.0)
		KitBox.corner_marks(ci, sr, Kit.ACCENT_HI, r * 0.36, 3.0)


func _draw_text(text: String, center: Vector2, fs: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(center.x - sz.x * 0.5, center.y + fs * 0.34)
	draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.55))
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Draws the boss crop clipped to `poly` (UVs map the hex's bounds onto the crop region).
func _draw_crop(poly: PackedVector2Array, col: Color) -> void:
	var atlas := _crop.atlas
	if atlas == null:
		return
	var reg := _crop.region
	var ts := Vector2(atlas.get_width(), atlas.get_height())
	var b := KitBox._bounds(poly)
	var uvs := PackedVector2Array()
	for p in poly:
		var k := (p - b.position) / b.size
		uvs.append((reg.position + k * reg.size) / ts)
	draw_colored_polygon(poly, col, uvs, atlas)
