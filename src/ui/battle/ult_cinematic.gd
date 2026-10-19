extends Control
## Ultimate moment overlay (style v4 poster look): a dark printed band opens across the field, turned
## a little, with paper hairlines and tick rulers along its edges, the caster's red halftone print and
## speed lines inside it; her portrait glides across in front in full colour; the skill name is set
## huge in compressed paper type (its last word in signal) under a mono kicker with her name. Allies
## get the tall band mid-screen, enemies (echo ultimates) a slimmer one near the top. The battle
## screen dims and freezes the field around it. Frees itself when done.
##   var c := UltCinematic.new(); add_child(c); c.play(hero_id, "Hymn of Judgment", true, 1.0)

const BP := preload("res://src/ui/v4/battle/battle_print.gd")

var hero_id := ""
var ally := true
var dur := 1.0
var _band: Control
var _lines_c: Control
var _lines: Array[Vector3] = []
var _t := 0.0
var _bh := 240.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func play(id: String, skill_name: String, is_ally: bool, duration: float) -> void:
	hero_id = id
	ally = is_ally
	dur = maxf(duration, 0.35)
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := vs.x
	_bh = 250.0 if ally else 150.0
	var cy := vs.y * (0.44 if ally else 0.24)
	var skin := Game.equipped_skin(id) if ally else ""
	var hero_name := str(Game.hero_def(id).get("name", id))

	# The band: dark, turned a little, the red print on the open side, hairlines and ticks.
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.size = Vector2(w + 240.0, _bh)
	_band.position = Vector2(-120.0, cy - _bh * 0.5)
	_band.pivot_offset = _band.size * 0.5
	_band.rotation = -0.05 if ally else 0.035
	_band.scale = Vector2(1.0, 0.0)
	add_child(_band)
	BP.rect(_band, Rect2(Vector2.ZERO, _band.size), BP.BAND)
	var pw := w * 0.62
	var px := 120.0 + (w - pw if ally else 0.0)
	var pr := BP.halftone(id, skin, {"crop": "face", "cell": 6.0})
	pr.position = Vector2(px, 0)
	pr.size = Vector2(pw, _bh)
	_band.add_child(pr)
	var fade := TextureRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.texture = Kit.vgradient(BP.BAND, Color(BP.BAND, 0.0), true)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.size = Vector2(150, _bh)
	if ally:
		fade.position = Vector2(px - 2, 0)
	else:
		fade.flip_h = true
		fade.position = Vector2(px + pw - 148, 0)
	_band.add_child(fade)
	_lines_c = Control.new()
	_lines_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_c.size = _band.size
	_lines_c.draw.connect(_draw_lines)
	_band.add_child(_lines_c)
	for edge: float in [8.0, _bh - 9.0]:
		BP.rect(_band, Rect2(0, edge, _band.size.x, 1), Color(BP.PAPER, 0.75))
		var tk := BP.Ticks.new()
		tk.count = int(_band.size.x / 12.0)
		tk.major = 5
		tk.color = Color(BP.PAPER, 0.5)
		tk.from_top = edge < _bh * 0.5
		tk.position = Vector2(0, edge + 1.0 if edge < _bh * 0.5 else edge - 7.0)
		tk.size = Vector2(_band.size.x, 7)
		_band.add_child(tk)
	for i in 14:
		_lines.append(Vector3(randf() * _band.size.x, randf_range(18.0, _bh - 18.0), randf_range(0.6, 1.4)))

	# Portrait: head and shoulders cut from the full-body still (allies in their equipped skin).
	var tex := HeroArt.texture(id, skin)
	var prr := HeroArt.portrait_region(id, skin)
	var at := AtlasTexture.new()
	at.atlas = tex
	var grow := prr.size.x * 0.35
	var region := Rect2(prr.position.x - grow, prr.position.y - grow * 0.4, prr.size.x + grow * 2.0, prr.size.y + grow * 1.5)
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
	var y0 := cy + _bh * 0.5 - ph + 8.0
	var x_in := 10.0 if ally else w - por.size.x - 10.0
	var x_from := -por.size.x if ally else w
	var x_out := x_in + (50.0 if ally else -50.0)
	por.position = Vector2(x_from, y0)

	# The type on the band's open side: kicker, the skill name huge, her name.
	var room := w - por.size.x - 40.0
	var words := skill_name.to_upper().split(" ")
	var key := words[words.size() - 1]
	var bb := " ".join(words.slice(0, words.size() - 1)) + (" " if words.size() > 1 else "") + "[color=#%s]%s[/color]" % [BP.SIG.to_html(false), key]
	var fs := BP.fit(skill_name.to_upper(), room, 76 if ally else 50, 26)
	var col := Control.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kick := BP.t(("ULTIMATE  ·  %s" if ally else "ECHO ULTIMATE  ·  %s") % hero_name.to_upper(), 12 if ally else 11, BP.SIG if ally else BP.PAPER, "mono_bold")
	col.add_child(kick)
	var big := RichTextLabel.new()
	big.bbcode_enabled = true
	big.text = bb
	big.scroll_active = false
	big.fit_content = true
	big.autowrap_mode = TextServer.AUTOWRAP_OFF
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.add_theme_font_override("normal_font", Kit.font("compressed"))
	big.add_theme_font_size_override("normal_font_size", fs)
	big.add_theme_color_override("default_color", BP.PAPER)
	var tw_text := Kit.font("compressed").get_string_size(skill_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	big.size = Vector2(tw_text, fs * 1.25)
	big.position = Vector2(-2, 14)
	col.add_child(big)
	var fac := str(Game.hero_def(id).get("faction", ""))
	var sub := BP.t("%s  ·  No.%02d" % [str(Kit.FACTION_NAMES.get(fac, fac)).to_upper(), absi(hash(skill_name)) % 100], 10, Color(BP.PAPER, 0.7), "mono")
	sub.position = Vector2(0, 14 + fs * 1.1)
	col.add_child(sub)
	var cs := Vector2(maxf(tw_text, kick.get_minimum_size().x), 14 + fs * 1.1 + 16)
	col.size = cs
	add_child(col)
	var cx := w - cs.x - 20.0 if ally else 20.0
	col.position = Vector2(cx, cy - cs.y * 0.5 + (6.0 if ally else 0.0))
	col.pivot_offset = cs * 0.5
	col.rotation = _band.rotation
	col.scale = Vector2(0.85, 0.85)
	col.modulate.a = 0.0

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_band, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(por, "position:x", x_in, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(por, "position:x", x_out, maxf(dur - 0.42, 0.05)).set_delay(0.22)
	tw.tween_property(col, "modulate:a", 1.0, 0.1).set_delay(0.08)
	tw.tween_property(col, "scale", Vector2.ONE, 0.22).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var out := maxf(dur - 0.2, 0.15)
	tw.tween_property(self, "modulate:a", 0.0, 0.2).set_delay(out)
	tw.tween_property(por, "position:x", w if ally else -por.size.x, 0.2).set_delay(out).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


func _process(delta: float) -> void:
	_t += delta
	if _lines_c:
		_lines_c.queue_redraw()


## Speed lines rushing along the band (paper, faint).
func _draw_lines() -> void:
	var w := _lines_c.size.x
	var dir := 1.0 if ally else -1.0
	for l in _lines:
		var x := fmod(l.x + dir * _t * 1800.0 * l.z, w + 200.0) - 100.0
		if dir < 0.0 and x < -100.0:
			x += w + 200.0
		_lines_c.draw_line(Vector2(x, l.y), Vector2(x - dir * 120.0 * l.z, l.y), Color(BP.PAPER, 0.16 * l.z), 2.0, true)
