extends Control
## Ultimate moment overlay (style v4 poster look): a dark printed band opens across the field, turned
## a little, with paper hairlines and tick rulers along its edges, the caster's red halftone print and
## speed lines inside it; her portrait glides across in front in full colour; the skill name is set
## huge in compressed paper type (its last word in signal) under a mono kicker with her name. Allies
## get the tall band mid-screen, enemies (echo ultimates) a slimmer one near the top. The battle
## screen dims and freezes the field around it. Frees itself when done.
## The player's heroines get the close-up instead (combat v1, docs/dev/combat-v1.md): the screen cuts
## to ink with her red halftone print and speed lines, she fills it at close range (her live rig in
## her equipped skin, playing her ultimate, the camera pushing in on her face), the skill name lands
## huge across the foot, then a quick cut back to the field as the hit lands.
##   var c := UltCinematic.new(); add_child(c); c.play(hero_id, "Hymn of Judgment", true, 1.0)

const DeviceTier := preload("res://src/art/device_tier.gd")
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


## partner: the heroine whose ultimate this one chains from (Encore; she joins the close-up), chain:
## the Encore step (0 = none).
func play(id: String, skill_name: String, is_ally: bool, duration: float, partner: String = "", chain: int = 0) -> void:
	hero_id = id
	ally = is_ally
	dur = maxf(duration, 0.35)
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := vs.x
	_bh = 250.0 if ally else 150.0
	var cy := vs.y * (0.44 if ally else 0.24)
	var skin := Game.equipped_skin(id) if ally else ""
	var hero_name := str(Game.hero_def(id).get("name", id))
	if ally:
		_closeup(id, skin, hero_name, skill_name, vs, partner, chain)
		return

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


## The player's close-up: ink, her print, her live rig at close range, the skill name across the foot.
func _closeup(id: String, skin: String, hero_name: String, skill_name: String, vs: Vector2, partner: String = "", chain: int = 0) -> void:
	var w := vs.x
	var h := vs.y
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = vs
	root.modulate.a = 0.0
	add_child(root)
	BP.rect(root, Rect2(Vector2.ZERO, vs), BP.BAND)
	# Her red halftone print down the right two thirds, fading into the ink on its left edge.
	var pr := BP.halftone(id, skin, {"crop": "face", "cell": 7.0})
	pr.position = Vector2(w * 0.3, 0)
	pr.size = Vector2(w * 0.7, h)
	root.add_child(pr)
	var fade := TextureRect.new()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.texture = Kit.vgradient(BP.BAND, Color(BP.BAND, 0.0), true)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(w * 0.3 - 2.0, 0)
	fade.size = Vector2(220, h)
	root.add_child(fade)
	_bh = h
	_lines_c = Control.new()
	_lines_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_c.size = vs
	_lines_c.draw.connect(_draw_lines)
	root.add_child(_lines_c)
	for i in 26:
		_lines.append(Vector3(randf() * w, randf_range(30.0, h - 30.0), randf_range(0.6, 1.5)))

	# Her live rig, framed on her face: head and shoulders about two thirds of the screen wide (half
	# of it with an Encore partner, set right).
	var anchor := _framed_rig(root, id, skin, w * (0.5 if partner != "" else 0.64), Vector2(w * (0.7 if partner != "" else 0.47), h * (0.3 if partner != "" else 0.34)))
	anchor.scale = Vector2(1.12, 1.12)
	# Encore: the heroine she chains from leans in from the lower left, in front (wings and props of
	# the caster would hide her behind), sliding in from the edge.
	if partner != "":
		var back := _framed_rig(root, partner, Game.equipped_skin(partner), w * 0.4, Vector2(w * 0.2, h * 0.44))
		var bx := back.position.x
		back.position.x = bx - w * 0.3
		var btw := create_tween()
		btw.tween_property(back, "position:x", bx, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var sp: Node2D = anchor.get_child(0)
	if sp.has_method("play_ultimate"):
		sp.call("play_ultimate", Vector2.INF)

	# The type across the foot on an ink fade: kicker, the skill name huge (last word in signal), her line.
	var foot := TextureRect.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.texture = Kit.vgradient(Color(BP.BAND, 0.0), Color(BP.BAND, 0.92))
	foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	foot.stretch_mode = TextureRect.STRETCH_SCALE
	foot.position = Vector2(0, h * 0.56)
	foot.size = Vector2(w, h * 0.44)
	root.add_child(foot)
	var words := skill_name.to_upper().split(" ")
	var key := words[words.size() - 1]
	var bb := " ".join(words.slice(0, words.size() - 1)) + (" " if words.size() > 1 else "") + "[color=#%s]%s[/color]" % [BP.SIG.to_html(false), key]
	var fs := BP.fit(skill_name.to_upper(), w - 56.0, 120, 48)
	var kick := BP.t("ULTIMATE  ·  %s" % hero_name.to_upper(), 14, BP.SIG, "mono_bold")
	kick.position = Vector2(28, h * 0.7)
	root.add_child(kick)
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
	big.size = Vector2(w, fs * 1.3)
	big.position = Vector2(24, h * 0.7 + 18.0)
	big.pivot_offset = Vector2(0, fs * 0.6)
	big.scale = Vector2(1.25, 1.25)
	root.add_child(big)
	var fac := str(Game.hero_def(id).get("faction", ""))
	var sub := BP.t("%s  ·  %s" % [str(Kit.FACTION_NAMES.get(fac, fac)).to_upper(), str(Game.hero_def(id).get("title", "")).to_upper()], 11, Color(BP.PAPER, 0.7), "mono")
	sub.position = Vector2(28, h * 0.7 + 22.0 + fs * 1.1)
	root.add_child(sub)
	for edge: float in [14.0, h - 15.0]:
		BP.rect(root, Rect2(0, edge, w, 1), Color(BP.PAPER, 0.6))
	if chain > 0:
		# ENCORE xN stamped top right in signal, printed slightly out of register.
		var st := Control.new()
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.position = Vector2(w - 368.0, h * 0.06)
		st.size = Vector2(280, 120)
		st.pivot_offset = st.size * 0.5
		st.rotation = -0.09
		root.add_child(st)
		var ghost := BP.t("ENCORE ×%d" % (chain + 1), 58, Color(BP.PAPER, 0.35), "compressed")
		ghost.position = Vector2(5, 4)
		st.add_child(ghost)
		st.add_child(BP.t("ENCORE ×%d" % (chain + 1), 58, BP.SIG, "compressed"))
		st.add_child(BP.t("+%d%% BY HAND" % (chain * BattleSim.ENCORE_STEP_BP / 100), 13, BP.PAPER, "mono_bold"))
		(st.get_child(st.get_child_count() - 1) as Control).position = Vector2(4, 72)
		st.scale = Vector2(1.6, 1.6)
		var stw := create_tween()
		stw.tween_property(st, "scale", Vector2.ONE, 0.18).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# In fast, push in on her while she casts, the name slams down, out on the hit.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.09)
	tw.tween_property(anchor, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(anchor, "scale", Vector2(1.08, 1.08), maxf(dur - 0.3, 0.1)).set_delay(0.2)
	tw.tween_property(anchor, "position:x", anchor.position.x + 18.0, maxf(dur - 0.3, 0.1)).set_delay(0.2)
	tw.tween_property(big, "scale", Vector2.ONE, 0.16).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var out := maxf(dur - 0.16, 0.2)
	tw.tween_property(root, "modulate:a", 0.0, 0.16).set_delay(out)
	tw.tween_property(anchor, "scale", Vector2(1.22, 1.22), 0.16).set_delay(out).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


## A hero's live rig on an anchor at `at` (screen px), scaled so her head-and-shoulders frame (the
## rig's portrait rect, converted from canvas pixels to rig units) is `face_px` wide and centred there.
func _framed_rig(parent: Control, id: String, skin: String, face_px: float, at: Vector2) -> Node2D:
	var anchor := Node2D.new()
	parent.add_child(anchor)
	var sp := HeroArt.make_sprite(id, skin)
	anchor.add_child(sp)
	DeviceTier.light(sp)
	var face := Vector2(0, -1500)
	var face_w := 460.0
	var rp: Variant = sp.get("rig")
	var rd: Variant = (rp as Node).get("rig") if rp is Node else null
	if rd is RigData and (rd as RigData).portrait_rect.size.x > 0.0:
		var r := rd as RigData
		face = r.portrait_rect.get_center() - r.origin
		face_w = r.portrait_rect.size.x
	var body: Variant = sp.get("_body")
	var bs := absf((body as Node2D).scale.y) if body is Node2D else 1.0
	face *= bs
	face_w *= bs
	var k := face_px / maxf(face_w, 1.0)
	sp.scale = Vector2(k, k)
	sp.position = -face * k
	anchor.position = at
	return anchor


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
