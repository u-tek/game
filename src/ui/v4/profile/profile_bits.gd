extends RefCounted
## Drawn pieces for the player profile (src/ui/screens/profile_screen.gd, style v4 poster look):
## the commendation stamps and the portrait cell of the avatar picker.
##
##   var b := ProfileBits.Badge.new(); b.ring = "FIRST SUMMON"; b.value = "01"; b.earned = true
##   var c := ProfileBits.portrait_cell(hero_id, skin, Vector2(136, 168), selected, caption, tag)

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")

const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL


## A rubber-stamped commendation: a double ring with its name set around the rim (repeated so the
## letters sit close), the value in compressed type in the middle and a tick under it. Earned
## stamps print in `ink` with a little press wear; unearned ones are a faint dashed outline.
class Badge:
	extends Control
	var ring := "COMMENDATION"
	var value := "01"
	var earned := false
	var ink := SignalKit.INK

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var col := Color(ink, 0.9) if earned else Color(ink, 0.22)
		if earned:
			draw_arc(c, r - 2.0, 0.0, TAU, 64, col, 2.0, true)
			draw_arc(c, r - 17.0, 0.0, TAU, 56, col, 1.0, true)
		else:
			# A dashed outline: the stamp's place, not yet pressed.
			var n := 28
			for i in n:
				var a0 := TAU * i / n
				draw_arc(c, r - 2.0, a0, a0 + TAU / n * 0.55, 4, col, 1.2, true)
			draw_arc(c, r - 17.0, 0.0, TAU, 48, Color(col, col.a * 0.6), 1.0, true)
		# The name around the rim, repeated to fill it, reading clockwise from the top.
		var f := Kit.font("mono_bold")
		var unit := ring.to_upper() + "  ·  "
		var text := unit
		while text.length() < 26:
			text += unit
		var fs := 8
		var rr := r - 9.5
		for i in text.length():
			var a := -PI * 0.5 + TAU * i / text.length()
			var pos := c + Vector2(cos(a), sin(a)) * rr
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(f, Vector2(-2.6, 3.0), text[i], fs, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# The value in the middle, as big as the inner ring allows.
		var fv := Kit.font("compressed")
		var inner := (r - 19.0) * 2.0
		var vs := int(r * 0.66)
		while vs > 10 and fv.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x > inner * 0.86:
			vs -= 1
		var vw := fv.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x
		draw_string(fv, c + Vector2(-vw * 0.5, vs * 0.36), value, HORIZONTAL_ALIGNMENT_LEFT, -1, vs, col)
		if earned:
			# Press wear: a few paper flecks knocked out of the ink (fixed per stamp).
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(ring)
			for k in 7:
				var a := rng.randf() * TAU
				var d := rng.randf_range(r - 6.0, r - 1.0)
				draw_circle(c + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.6, 1.4), PAPER)


## A portrait cell for the avatar picker: the hero's head and shoulders in full colour inside a
## hairline frame (signal and heavier when selected), her name in mono under it and an optional
## tag (AUTO, SELECTED) stuck on the top-left corner.
static func portrait_cell(hero_id: String, skin: String, sz: Vector2, selected: bool, caption: String, tag: String = "") -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = sz + Vector2(0, 24)
	root.size = root.custom_minimum_size
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(INK, 0.06)
	bg.position = Vector2(4, 4)
	bg.size = sz - Vector2(8, 8)
	root.add_child(bg)
	var crop: Texture2D = Kit.art_crop(hero_id, (sz.x - 8.0) / maxf(sz.y - 8.0, 1.0), 1.0, skin) if hero_id != "" else null
	if crop:
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = crop
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.position = Vector2(4, 4)
		tr.size = sz - Vector2(8, 8)
		root.add_child(tr)
	var fr := PK.Frame.new()
	fr.color = SIG if selected else INK
	fr.size = sz
	root.add_child(fr)
	if selected:
		var inner := PK.Frame.new()
		inner.color = SIG
		inner.tab = 0.0
		inner.position = Vector2(2, 2)
		inner.size = sz - Vector2(4, 4)
		root.add_child(inner)
	var cap := Kit.label(caption.to_upper(), 11, SIG if selected else INK, "mono_bold")
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.clip_text = true
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.position = Vector2(2, sz.y + 4)
	cap.size = Vector2(sz.x - 4, 16)
	root.add_child(cap)
	if tag != "":
		var t := PanelContainer.new()
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = SIG if selected else INK
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		t.add_theme_stylebox_override("panel", sb)
		t.add_child(Kit.label(tag.to_upper(), 10, PAPER, "mono_bold"))
		t.position = Vector2(-4, 10)
		t.rotation = -0.04
		root.add_child(t)
	return root
