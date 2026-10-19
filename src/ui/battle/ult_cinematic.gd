extends Control
## Ultimate moment overlay: a slanted band in the caster's color sweeps in with the hero's
## portrait gliding across it, speed lines, the hero name and the skill name on a ribbon.
## Allies get the full-size band mid-screen; enemies a slimmer band near the top.
## The battle screen dims and freezes the field around it. Frees itself when done.
##   var c := UltCinematic.new(); add_child(c); c.play(hero_id, "Hymn of Judgment", true, 1.0)

var hero_id := ""
var ally := true
var dur := 1.0
var _color := Color.WHITE
var _band_k := 0.0
var _lines: Array[Vector3] = []
var _t := 0.0
var _cy := 0.0
var _bh := 240.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func play(id: String, skill_name: String, is_ally: bool, duration: float) -> void:
	hero_id = id
	ally = is_ally
	dur = maxf(duration, 0.35)
	var faction := str(Game.hero_def(id).get("faction", "celestial"))
	_color = HeroArt.faction_color(faction) if ally else Color("9a5cff").lerp(HeroArt.faction_color(faction), 0.35)
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := vs.x
	_bh = 250.0 if ally else 150.0
	_cy = vs.y * (0.44 if ally else 0.24)
	for i in 14:
		_lines.append(Vector3(randf() * w, _cy + randf_range(-_bh * 0.45, _bh * 0.45), randf_range(0.6, 1.4)))

	# Portrait: head and shoulders cut from the full-body still (allies in their equipped skin).
	var skin := Game.equipped_skin(id) if ally else ""
	var tex := HeroArt.texture(id, skin)
	var pr := HeroArt.portrait_region(id, skin)
	var at := AtlasTexture.new()
	at.atlas = tex
	var grow := pr.size.x * 0.35
	var region := Rect2(pr.position.x - grow, pr.position.y - grow * 0.4, pr.size.x + grow * 2.0, pr.size.y + grow * 1.5)
	var ts := Vector2(tex.get_width(), tex.get_height()) if tex else Vector2(1, 1)
	region = region.intersection(Rect2(Vector2.ZERO, ts))
	at.region = region
	var por := TextureRect.new()
	por.texture = at
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := _bh * 1.35
	por.size = Vector2(ph * region.size.x / maxf(region.size.y, 1.0), ph)
	por.flip_h = not ally
	if not ally:
		por.modulate = Color(0.85, 0.75, 1.0)
	add_child(por)
	var y0 := _cy + _bh * 0.5 - ph + 8.0
	var x_in := 10.0 if ally else w - por.size.x - 10.0
	var x_from := -por.size.x if ally else w
	var x_out := x_in + (50.0 if ally else -50.0)
	por.position = Vector2(x_from, y0)

	# Name and skill ribbon on the open side of the band.
	var col := Kit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var nm := Kit.label(str(Game.hero_def(id).get("name", id)).to_upper(), 26 if ally else 22, Kit.INK, "black", 6)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var rib_w := 400.0 if ally else 340.0
	var rib := Kit.ribbon(skill_name, rib_w, _color if ally else Color("7a3bd6"), Color("2a1606") if ally and _color.get_luminance() > 0.5 else Color.WHITE, 38 if ally else 30)
	col.add_child(rib)
	col.size = Vector2(rib_w, 0)
	add_child(col)
	var cs := col.get_combined_minimum_size()
	var cx := w - rib_w - 16.0 if ally else 16.0
	col.position = Vector2(cx, _cy - cs.y * 0.5 + (10.0 if ally else 0.0))
	col.pivot_offset = cs * 0.5
	col.scale = Vector2(0.6, 0.6)
	col.modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_band_k", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(por, "position:x", x_in, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(por, "position:x", x_out, maxf(dur - 0.42, 0.05)).set_delay(0.22)
	tw.tween_property(col, "modulate:a", 1.0, 0.12).set_delay(0.08)
	tw.tween_property(col, "scale", Vector2.ONE, 0.24).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var out := maxf(dur - 0.2, 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(out)
	tw.tween_property(por, "position:x", w if ally else -por.size.x, 0.2).set_delay(out).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _band_k <= 0.0:
		return
	var w := size.x
	var h := _bh * _band_k
	var skew := 46.0 if ally else 26.0
	var top_l := Vector2(0, _cy - h * 0.5 + skew)
	var top_r := Vector2(w, _cy - h * 0.5 - skew)
	var bot_r := Vector2(w, _cy + h * 0.5 - skew)
	var bot_l := Vector2(0, _cy + h * 0.5 + skew)
	var dark := Color(0.03, 0.035, 0.045, 0.92)
	var mid := Color(_color.darkened(0.55), 0.95)
	draw_polygon(PackedVector2Array([top_l, top_r, bot_r, bot_l]), PackedColorArray([mid, dark, dark, mid]))
	# Bright edges.
	draw_line(top_l, top_r, Color(_color.lightened(0.3), 0.95), 4.0, true)
	draw_line(bot_l, bot_r, Color(_color.lightened(0.3), 0.95), 4.0, true)
	draw_line(top_l + Vector2(0, 9), top_r + Vector2(0, 9), Color(_color, 0.35), 2.0, true)
	draw_line(bot_l - Vector2(0, 9), bot_r - Vector2(0, 9), Color(_color, 0.35), 2.0, true)
	# Speed lines rushing across the band.
	var dir := 1.0 if ally else -1.0
	for l in _lines:
		var x := fmod(l.x + dir * _t * 1800.0 * l.z, w + 200.0) - 100.0
		if dir < 0.0 and x < -100.0:
			x += w + 200.0
		var y := _cy + (l.y - _cy) * _band_k - (x / w - 0.5) * skew * 2.0
		draw_line(Vector2(x, y), Vector2(x - dir * 120.0 * l.z, y + dir * 12.0 * l.z), Color(1, 1, 1, 0.18 * l.z), 2.0, true)
