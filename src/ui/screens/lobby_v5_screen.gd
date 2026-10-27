extends Control
## Screen "lobby_v5" (debug builds): the Lobby composed as a printed poster (owner, 2026-10-19: "mix
## them per screen"; the Lobby follows the mint poster reference). The screen is a poster mounted on a
## paper matte: a dark band with the hero as a red halftone print, the hero's line set huge in
## compressed type and turned on its side behind her, small vertical labels down the right edge as
## the menu, a coil, a Campaign pass (the OG-pass card) and a Sanctum stamp stuck on, and under the
## poster the date, the five sections and her signature. Sample values for stage and Sanctum.
##   tools/shoot lobby_v5 --rich --safe-area-sim

const HUD := preload("res://src/ui/components/hud.gd")
const Plate := preload("res://src/ui/components/plate.gd")
const LobbyLines := preload("res://src/ui/battle/lobby_lines.gd")

const W := 720.0
const BAND := 248.0
const PAPER := SignalKit.PAPER
const MATTE := SignalKit.MATTE
const INKC := Color("101113")
const SIG := SignalKit.SIGNAL

var _hero_id := ""
var _anchor: Node2D
var _sprite: Node2D


func setup(_params: Dictionary) -> void:
	UI.set_chrome(false, false)
	_hero_id = _pick_hero()
	_build()


func _pick_hero() -> String:
	var want: Variant = Game.setting("lobby_hero")
	if want is String and want != "" and Game.owns(want):
		return want
	for id: String in Game.formation():
		if id != "" and HeroArt.has_art(id):
			return id
	return "noctaire"


func _build() -> void:
	var vh := get_viewport_rect().size.y
	var top := UI.safe_top()
	var bottom := UI.safe_bottom()
	var def := Game.hero_def(_hero_id)
	var name_txt := str(def.get("name", _hero_id))
	var lines := LobbyLines.lines(_hero_id)
	var line := lines[0] if not lines.is_empty() else str(def.get("bio", ""))

	# ---- The matte.
	var matte := ColorRect.new()
	matte.color = MATTE
	matte.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(matte)
	_at(self, _t("HALO & HORN  ©2026", 13, INKC, "mono_bold"), Vector2(20, top + 10))
	var res := _t("PWR %s   ·   GEMS %s   ·   GOLD %s" % [Kit.format_full(Game.team_power()), Kit.format_full(Kit.have("gems")),
		Kit.format_full(Kit.have("gold"))], 12, Color(INKC, 0.7), "mono")
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res.size = Vector2(460, 16)
	_at(self, res, Vector2(W - 20 - 460, top + 11))

	# ---- The poster, with a soft shadow on the matte.
	var pr := Rect2(18, top + 42, W - 36, vh - bottom - 156 - (top + 42))
	var shadow := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = PAPER
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.position = pr.position
	shadow.size = pr.size
	add_child(shadow)
	var poster := Control.new()
	poster.position = pr.position
	poster.size = pr.size
	poster.clip_contents = true
	add_child(poster)
	var ph := pr.size.y
	var pw := pr.size.x

	# Dark band with the hero as a red halftone print (head to waist, cover-cropped).
	var band := ColorRect.new()
	band.color = Color("141517")
	band.size = Vector2(BAND, ph)
	poster.add_child(band)
	var tex := HeroArt.texture(_hero_id, Game.equipped_skin(_hero_id))
	var face := HeroArt.portrait_region(_hero_id, Game.equipped_skin(_hero_id))
	if tex:
		var at := AtlasTexture.new()
		at.atlas = tex
		var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.42, face.size.y * 0.62), Vector2(face.size.x * 0.84, face.size.y * 1.9))
		at.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
		var ht := TextureRect.new()
		ht.texture = at
		ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		ht.position = Vector2(0, ph * 0.18)
		ht.size = Vector2(BAND, ph * 0.82)
		var hm := ShaderMaterial.new()
		hm.shader = load("res://src/ui/shaders/halftone.gdshader")
		hm.set_shader_parameter("cell", 7.0)
		hm.set_shader_parameter("ink", Color(1.0, 0.36, 0.16, 0.95))
		hm.set_shader_parameter("gain", 1.25)
		ht.material = hm
		poster.add_child(ht)
		# A soft, blurred red echo of her in the light area (the reference's out-of-focus figure).
		var img := tex.get_image()
		if img:
			img.resize(maxi(img.get_width() / 20, 8), maxi(img.get_height() / 20, 8), Image.INTERPOLATE_BILINEAR)
			var echo := TextureRect.new()
			echo.texture = ImageTexture.create_from_image(img)
			echo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			echo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			echo.size = Vector2(640, 1280)
			echo.position = Vector2(150, ph * 0.08)
			echo.modulate = Color(1.0, 0.3, 0.12, 0.38)
			poster.add_child(echo)
	_at(poster, _t("HH", 34, PAPER, "wide_black"), Vector2(20, 18))
	_at(poster, _t("™", 12, PAPER, "mono"), Vector2(84, 20))
	var rights := _t("©2026 HH, ALL RIGHTS RESERVED.", 11, Color(PAPER, 0.8), "mono_bold")
	rights.rotation = PI * 0.5
	rights.position = Vector2(46, 90)
	poster.add_child(rights)
	_at(poster, _t("No.\n007", 12, Color(PAPER, 0.85), "mono_bold"), Vector2(150, ph * 0.5))
	_at(poster, _t("19.10.26", 12, Color(PAPER, 0.85), "mono_bold"), Vector2(196, ph * 0.5 + 6))

	# The coil (top right of the light area).
	var coil := _Coil.new()
	coil.position = Vector2(BAND + 150, -36)
	coil.size = Vector2(240, ph * 0.62)
	poster.add_child(coil)

	# Her line, set huge and turned on its side: black over the paper, paper-white over the band.
	var text := line.to_upper()
	var words := text.split(" ")
	var key := words[words.size() - 1] if words.size() > 0 else ""
	var bb := " ".join(words.slice(0, words.size() - 1)) + " [color=#%s]%s[/color]" % [SIG.to_html(false), key]
	for side in [[0.0, BAND, PAPER], [BAND, pw - BAND, INKC]]:
		var clip := Control.new()
		clip.clip_contents = true
		clip.position = Vector2(side[0], 0)
		clip.size = Vector2(side[1], ph)
		poster.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bb
		rt.fit_content = false
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.add_theme_font_override("normal_font", Kit.font("compressed"))
		rt.add_theme_font_size_override("normal_font_size", 118)
		rt.add_theme_color_override("default_color", side[2])
		rt.add_theme_constant_override("line_separation", -14)
		rt.mouse_filter = MOUSE_FILTER_IGNORE
		rt.size = Vector2(ph * 0.94, 420)
		rt.rotation = PI * 0.5
		# Turned clockwise: the block's first line runs down the poster at x = 500, later lines to its left.
		rt.position = Vector2(500.0 - float(side[0]), ph * 0.02)
		clip.add_child(rt)

	# The hero, full colour, in front of her line, boxed by the right-hand rule.
	var box := Control.new()
	box.clip_contents = true
	box.size = Vector2(pw - 49, ph)
	poster.add_child(box)
	_anchor = Node2D.new()
	box.add_child(_anchor)
	var fig_h := ph * 0.98
	_anchor.position = Vector2(BAND + 250, ph * 1.0)
	if _hero_id != "":
		_sprite = HeroArt.make_sprite(_hero_id, Game.equipped_skin(_hero_id))
		_anchor.add_child(_sprite)
		var base_h: float = _sprite.call("get_height")
		var k := fig_h / maxf(base_h, 1.0)
		_sprite.scale = Vector2(k, k)

	# Right edge: a hairline and the menu as small vertical labels.
	var rule := ColorRect.new()
	rule.color = Color(INKC, 0.55)
	rule.position = Vector2(pw - 48, 0)
	rule.size = Vector2(1, ph)
	poster.add_child(rule)
	_at(poster, _t("©2026 ·", 12, INKC, "mono_bold"), Vector2(pw - 38, 14)).rotation = PI * 0.5
	var labels := [["DAILY", 0.2], ["OFFERS", 0.36], ["SPIRE", 0.52], ["SHOP", 0.68]]
	for l in labels:
		var b := _t(l[0], 15, INKC, "mono_bold")
		b.rotation = PI * 0.5
		b.position = Vector2(pw - 16, ph * float(l[1]))
		poster.add_child(b)
		var tick := ColorRect.new()
		tick.color = INKC
		tick.position = Vector2(pw - 52, ph * float(l[1]) + 2)
		tick.size = Vector2(9, 1)
		poster.add_child(tick)
	var led := HUD.Led.new()
	led.size = Vector2(16, 16)
	led.position = Vector2(pw - 31, ph * 0.2 - 22)
	led.mode = "breathe"
	poster.add_child(led)

	# The Sanctum stamp, stuck on the lower left of the paper.
	var stamp := _plate("silver", Vector2(BAND + 14, ph - 250), Vector2(112, 112), {"circle": true, "shadow": 0.5}, poster)
	var st := _Stamp.new()
	st.size = Vector2(112, 112)
	st.label = "SANCTUM · LV 12 · FULL IN 7H 05M · "
	st.value = "41%"
	stamp.add_child(st)
	stamp.rotation = -0.12

	# The Campaign pass (OG-pass build), placed over the poster's bottom edge.
	var pass_root := Control.new()
	pass_root.position = Vector2(pr.position.x + pw - 412, pr.end.y - 176)
	pass_root.rotation = -0.035
	add_child(pass_root)
	_pass(pass_root)

	# ---- Under the poster: the five sections, then the date and her signature.
	var nav_y := pr.end.y + 18.0
	var items := ["HEROES", "TEAM", "LOBBY", "GEAR", "SUMMON"]
	var cw := (W - 40) / items.size()
	for i in items.size():
		var on := i == 2
		var l2 := _t("%02d %s" % [i + 1, items[i]], 14, SIG if on else INKC, "mono_bold")
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.size = Vector2(cw, 18)
		_at(self, l2, Vector2(20 + i * cw, nav_y))
		if on:
			var u := ColorRect.new()
			u.color = SIG
			u.position = Vector2(20 + i * cw + cw * 0.5 - 22, nav_y + 24)
			u.size = Vector2(44, 3)
			add_child(u)
		if i < items.size() - 1:
			_at(self, _t("/", 14, Color(INKC, 0.35), "mono"), Vector2(20 + (i + 1) * cw - 5, nav_y))
	_at(self, _t("2026 10/19", 26, INKC, "regular"), Vector2(20, nav_y + 46))
	var sig := _t(name_txt, 54, INKC, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 60)
	_at(self, sig, Vector2(W - 24 - 300, nav_y + 26))
	var swash := ColorRect.new()
	swash.color = INKC
	swash.position = Vector2(W - 250, nav_y + 86)
	swash.size = Vector2(220, 2)
	swash.rotation = -0.06
	add_child(swash)

	# Paper grain over everything (multiplied, like ink on stock).
	var grain := ColorRect.new()
	grain.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	grain.mouse_filter = MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = load("res://src/ui/shaders/grain.gdshader")
	gm.set_shader_parameter("amount", 0.06)
	gm.set_shader_parameter("still", true)
	grain.material = gm
	add_child(grain)
	_relight.call_deferred()


func _relight() -> void:
	await get_tree().process_frame
	Plate.relight_all(get_tree())


## The Campaign pass: a brushed silver plate (code, stage, knob) over a glowing signal plate.
func _pass(root: Control) -> void:
	var sig := _plate("signal", Vector2(8, 74), Vector2(386, 96), {"cuts": [0, 12, 18, 0], "glow": 0.4, "glow_radius": 14.0,
		"pulse": 0.5, "topo": 0.6}, root)
	var top_sz := Vector2(400, 92)
	var silver := _plate("silver", Vector2.ZERO, top_sz, {"shape": Plate.tab_bottom(top_sz, 14, 132, 260, 14), "topo": 0.5,
		"screws": [Vector2(13, 13), Vector2(top_sz.x - 13, 13), Vector2(13, 64), Vector2(top_sz.x - 13, 64)]}, root)
	silver.z_index = 1
	var code := _Matrix.new()
	code.position = Vector2(26, 12)
	code.size = Vector2(58, 58)
	silver.add_child(code)
	_at(silver, _etch("CAMPAIGN // NEXT", 10, "mono_bold"), Vector2(98, 12))
	_at(silver, _etch("STAGE 2-3", 30, "wide_black"), Vector2(96, 26))
	_at(silver, _etch("CH.02 EMBER WASTES", 10, "mono"), Vector2(98, 64))
	var d := _plate("dial", Vector2(318, 18), Vector2(50, 50), {"circle": true, "shadow": 0.5}, silver)
	var fl := Kit.icon("flag", 22, Color(1, 1, 1, 0.95))
	fl.position = Vector2(14, 14)
	d.add_child(fl)
	var pill := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.1)
	ps.border_color = Color(1, 1, 1, 0.9)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(30)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 2
	ps.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", ps)
	pill.add_child(_t("ENGAGE  >>>", 20, Color.WHITE, "wide_black"))
	pill.position = Vector2(18, 32)
	sig.add_child(pill)
	_at(sig, _t("REC PWR 9,608", 10, Color(1, 1, 1, 0.85), "mono"), Vector2(230, 44))


# ------------------------------------------------------------------ helpers

func _plate(preset: String, pos: Vector2, sz: Vector2, opts: Dictionary = {}, parent: Node = null) -> Control:
	var p := Plate.new()
	p.preset = preset
	p.position = pos
	p.size = sz
	if opts.has("cuts"):
		p.cuts = opts["cuts"]
	if opts.has("shape"):
		p.shape = opts["shape"]
	p.circle = opts.get("circle", false)
	if opts.has("screws"):
		for s: Vector2 in opts["screws"]:
			p.screws.append(s)
	p.glow = opts.get("glow", 0.0)
	p.glow_radius = opts.get("glow_radius", 18.0)
	p.pulse = opts.get("pulse", 0.0)
	p.topo = opts.get("topo", 0.0)
	p.shadow_a = opts.get("shadow", 0.6)
	p.recess = opts.get("recess", false)
	(parent if parent else self).add_child(p)
	return p


func _t(text: String, size: int, color: Color, weight: String) -> Label:
	return Kit.label(text, size, color, weight)


## Text cut into silver: a light lip below, a dark wall above.
func _etch(text: String, size: int, weight: String) -> Control:
	var box := Control.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	for layer in [[Color(1, 1, 1, 0.7), Vector2(0, 1)], [Color(0, 0, 0, 0.45), Vector2(0, -1)], [Color("131416"), Vector2.ZERO]]:
		var l := Kit.label(text, size, layer[0], weight)
		l.position = layer[1]
		box.add_child(l)
	return box


func _at(parent: Node, c: Control, pos: Vector2) -> Control:
	c.position = pos
	parent.add_child(c)
	return c


## A coil spring seen end-on in perspective, drawn in heavy ink (the reference's spiral).
class _Coil:
	extends Control

	func _draw() -> void:
		var n := 30
		var y := 40.0
		for i in n:
			var k := float(i) / n
			var rx := lerpf(92.0, 16.0, pow(k, 0.8))
			var ry := rx * lerpf(0.55, 0.2, k)
			var cx := size.x * 0.5 + sin(k * 5.0) * 10.0 * (1.0 - k)
			var w := lerpf(7.0, 1.5, k)
			draw_arc(Vector2(cx, y), rx, 0.0, TAU, 64, Color(0.06, 0.065, 0.07, lerpf(0.95, 0.6, k)), w, true)
			y += lerpf(26.0, 8.0, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Round inspection stamp with text around the rim and a big value in the middle.
class _Stamp:
	extends Control
	var label := "SANCTUM · "
	var value := "41%"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var ink := Color(0.1, 0.11, 0.12, 0.85)
		draw_arc(c, r - 6.0, 0.0, TAU, 64, ink, 1.5, true)
		draw_arc(c, r - 22.0, 0.0, TAU, 64, ink, 1.0, true)
		var f := Kit.font("mono_bold")
		for i in label.length():
			var a := -PI * 0.5 + TAU * i / label.length()
			var pos := c + Vector2(cos(a), sin(a)) * (r - 14.0)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(f, Vector2(-3.0, 3.5), label[i], 9, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var fb := Kit.font("wide_black")
		var w := fb.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(fb, c + Vector2(-w * 0.5, 9), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)


## Decorative matrix code with three finder squares (not a scannable code).
class _Matrix:
	extends Control

	func _draw() -> void:
		var n := 21
		var c := size.x / n
		var rng := RandomNumberGenerator.new()
		rng.seed = 2044
		var ink := Color("1e2023")
		for y in n:
			for x in n:
				var finder := (x < 7 and y < 7) or (x >= n - 7 and y < 7) or (x < 7 and y >= n - 7)
				if finder:
					continue
				if rng.randf() < 0.48:
					draw_rect(Rect2(x * c, y * c, c, c), ink)
		for f: Vector2 in [Vector2(0, 0), Vector2(n - 7, 0), Vector2(0, n - 7)]:
			draw_rect(Rect2(f * c, Vector2(7, 7) * c), ink)
			draw_rect(Rect2((f + Vector2(1, 1)) * c, Vector2(5, 5) * c), Color("d8dbd7"))
			draw_rect(Rect2((f + Vector2(2, 2)) * c, Vector2(3, 3) * c), ink)
