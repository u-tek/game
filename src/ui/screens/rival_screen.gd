class_name RivalScreen
extends Control
## Screen "rival": Rue, the other summoner (Game.rival(), RivalRules; data/rival.json). Her poster is
## the house poster (docs/dev/ui-style-v4.md section 0) printed on her own stock: grey pressed felt
## with the type debossed into it, overgrown with black chrome thorns (blue crystal, white tufts), a
## glossy red dome stuck on as the haul light, a red push button in a knurled silver bezel, tiny LEDs
## set into the felt and an orange acrylic record card with a dot grid and a round cut-out (the owner's
## 2026-10-19 references, rebuilt: Blender renders in assets/art/ui/objects/, felt and acrylic shaders).
##
## Top to bottom: the face of the poster (a dark band with her ace's red halftone, RUE set huge down it,
## two-tone where it leaves the band and debossed on the felt, her ace in full colour with a red echo,
## the haul dome with its label, the LEDs (haul, wire, tag), her line on a paper slip); the Fight pass
## (mode "rival" in the battle screen) beside the knurled button (push: another line from her); her
## team today as five small prints with leader lines (and the counter-pick sticker once she has read
## your main faction); the acrylic record card (W-L, fights, her code) beside her data list (power vs
## yours, pulls, today's banner, campaign, Spire); THE WIRE, her feed as a printed ticker list with
## dates; her binder (her best prints as slabs; the one a win today takes is marked). After you beat
## her, your marker tag is scrawled over her poster. Her first visit plays the intro (rival_meet).
## Locked (campaign below unlock_cleared): the poster sealed with the stage that opens it.
## params: intro (true replays the intro sheet), scroll (px: screenshots of the lower page).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const PKS := preload("res://src/ui/v4/poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")
const FELT_SHADER := preload("res://src/ui/shaders/felt.gdshader")
const ACRYLIC := preload("res://src/ui/shaders/acrylic_card.gdshader")
const THORN_CORNER := "res://assets/art/ui/objects/thorns_corner.png"
const THORN_VINE := "res://assets/art/ui/objects/thorns_vine.png"
const DOME := "res://assets/art/ui/objects/dome.png"
const BUTTON := "res://assets/art/ui/objects/button.png"
const SEAL := "res://assets/art/ui/objects/seal.png"

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const CARD := Color("f4f3ef")
const SIG := Color("ff4b1f")
const BAND_C := Color("141517")
const FELT := Color(0.55, 0.553, 0.565)
const BAND := 150.0
const FACE := 700.0
const MAX_W := 760.0
const KIND_TAGS := {"featured_first": ["FIRST!", "sig"], "legendary": ["LEGENDARY", "ink"], "misprint": ["MISPRINT", "sig"],
	"holo": ["HOLO", "ink"]}

var _params: Dictionary = {}
var _v: Dictionary = {}
var _fresh := 0
var _seen_before := 0
var _built := Vector2.ZERO
var _rebuild_queued := false
var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _pw := 0.0
var _ph := 0.0
var _anchor: Node2D
var _line_label: Label
var _line_n := 0
var _modal: Control
var _fade: Array[Control] = []


func setup(params: Dictionary) -> void:
	_params = params
	var rs: Dictionary = Game.state.get("rival", {})
	_seen_before = int(rs.get("seen", 0))
	_v = Game.rival()
	_fresh = int(_v.get("new_feed", 0))
	if bool(_v.get("unlocked", false)):
		Game.rival_seen()
		_v = Game.rival()
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	if bool(_v.get("unlocked", false)) and (not bool(_v.get("met", true)) or bool(params.get("intro", false))):
		_play_intro.call_deferred()
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params.scroll))


func _scroll_to(y: int) -> void:
	for i in 6:
		await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_changed):
		Game.changed.disconnect(_on_changed)
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null


func intro() -> void:
	if not Kit.motion_ok():
		return
	if _anchor:
		_anchor.modulate.a = 0.0
		_anchor.create_tween().tween_property(_anchor, "modulate:a", 1.0, 0.5).set_delay(0.1)
	for i in _fade.size():
		Kit.offset_in(_fade[i], Vector2(0, 18), 0.08 + i * 0.05, 0.4)


func _on_changed() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


func _on_resized() -> void:
	if _scroll == null or size.x <= 0.0:
		return
	var d := _dims()
	if absf(d.x - _built.x) > 2.0 or absf(d.y - _built.y) > 2.0:
		_on_changed()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var keep := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
	_v = Game.rival()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_fade.clear()
	_build()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


# ------------------------------------------------------------------ build

func _build() -> void:
	var d := _dims()
	_built = d
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	_pw = w - 32.0
	var unlocked := bool(_v.get("unlocked", false))
	var feed_n := mini((_v.get("feed", []) as Array).size(), 6)
	_ph = d.y - 14.0 - 84.0 if not unlocked else FACE + 170.0 + 400.0 + 270.0 + (110.0 + maxi(feed_n, 1) * 64.0) + 480.0
	_ph = maxf(_ph, d.y - 14.0 - 84.0)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + _ph + 84.0)
	_scroll = Kit.scroll(_page)
	_scroll.name = "RivalPage"
	_scroll.position = Vector2.ZERO
	_scroll.size = d
	add_child(_scroll)
	var pr := Rect2(ox + 16, 14, _pw, _ph)
	_poster = PK.poster(_page, pr, 22, FELT)
	var felt := ColorRect.new()
	felt.name = "Felt"
	felt.mouse_filter = MOUSE_FILTER_IGNORE
	felt.size = pr.size
	var fm := ShaderMaterial.new()
	fm.shader = FELT_SHADER
	fm.set_shader_parameter("size", pr.size)
	felt.material = fm
	_poster.add_child(felt)
	if unlocked:
		_build_face()
		var y := FACE
		y = _build_fight(y)
		y = _build_team(y)
		y = _build_record(y)
		y = _build_wire(y)
		var wire_end := y
		_build_binder(y)
		_build_thorns(wire_end)
		_build_tags()
	else:
		_build_locked()
	_build_footer(ox, w, pr)
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))
	SignalKit.relight(self)


## A texture from the objects folder (null when missing: the poster still works without it).
static func _obj(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## A collage object stuck on at pos, w px wide (aspect kept), turned and optionally mirrored.
func _stick(parent: Control, path: String, pos: Vector2, w: float, rot: float = 0.0, flip: bool = false) -> TextureRect:
	var tex := _obj(path)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
	tr.position = pos
	tr.pivot_offset = tr.size * 0.5
	tr.rotation = rot
	tr.flip_h = flip
	if path.find("thorns") >= 0:
		tr.modulate = Color(0.86, 0.87, 0.9)
	parent.add_child(tr)
	# Alive: the thorns grow out over her poster and sway; the red caps catch the light.
	if path.find("thorns") >= 0:
		PhysicalKit.come_alive(tr)
	elif path == DOME:
		PhysicalKit.sheen(tr, Vector2(0.48, 0.47), Vector2(0.43, 0.41), 0.12)
	elif path == BUTTON:
		PhysicalKit.sheen(tr, Vector2(0.47, 0.415), Vector2(0.35, 0.27), 0.1)
	return tr


## The giant type down the poster: paper on the band, debossed into the felt beside it.
func _giant(text_bb: String, fs: int, x_top: float, y0: float, length: float, band_x: float, band_w: float, h: float = FACE) -> void:
	var p := _poster
	var block := Vector2(length, fs * 1.3)
	PK.giant(p, text_bb, fs, Vector2(x_top, y0), block, [[Rect2(band_x, 0, band_w, h), CARD]], 0, "compressed", true)
	var felt_r := Rect2(band_x + band_w, 0, _pw - band_x - band_w, h)
	var plain := text_bb.replace("[color=#%s]" % SIG.to_html(false), "").replace("[/color]", "")
	PK.giant(p, plain, fs, Vector2(x_top, y0 + 2.5), block, [[felt_r, Color(FELT.lightened(0.55), 0.95)]], 0, "compressed", true)
	PK.giant(p, plain, fs, Vector2(x_top - 2.0, y0 - 2.5), block, [[felt_r, Color(FELT.darkened(0.7), 0.9)]], 0, "compressed", true)
	PK.giant(p, text_bb, fs, Vector2(x_top, y0), block, [[felt_r, FELT.darkened(0.3)]], 0, "compressed", true)


func _build_face() -> void:
	var p := _poster
	var ace := str(_v.get("ace", ""))
	var skin := Kit.hero_look(ace) if ace != "" else ""
	PK.rect(p, Rect2(0, 0, BAND, FACE), BAND_C)
	if ace != "":
		var ht := PK.halftone_print(ace, skin, Vector2(BAND, FACE * 0.6), 6.5)
		ht.position = Vector2(0, FACE * 0.36)
		p.add_child(ht)
	Poster.vlabel(p, "©2026 HH · RIVAL FILE · THE OTHER SUMMONER", Vector2(24, 112), 10, Color(PAPER, 0.8))
	# RUE, as big as the face allows, half on the band.
	var fs := 420
	while fs > 160 and PK.text_w("RUE.", fs) > FACE - 140.0:
		fs -= 10
	var gx := BAND + roundf(fs * 0.72)
	_giant("RUE[color=#%s].[/color]" % SIG.to_html(false), fs, gx, 118.0, FACE, 0.0, BAND)
	# Her ace in full colour, with a soft red echo, standing on the foot of the face.
	var box := Control.new()
	box.name = "Ace"
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.clip_contents = true
	box.position = Vector2(BAND, 0)
	box.size = Vector2(_pw - BAND, FACE)
	p.add_child(box)
	if ace != "":
		var fig_h := FACE * 0.8
		var cx := (_pw - BAND) * 0.64
		var echo := PK.echo(ace, skin, fig_h * 1.02, 0.42)
		echo.position = Vector2(cx - echo.size.x * 0.5 + 26.0, FACE - 4.0 - echo.size.y + 6.0)
		box.add_child(echo)
		_anchor = PKS.hero_fig(box, ace, skin, Vector2(cx, FACE - 8.0), fig_h)
	# Her file block, top right above her head.
	var x0 := _pw - 360.0
	var head := Kit.vbox(1)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	head.position = Vector2(x0, 20)
	head.add_child(PK.t("RIVAL FILE  ·  Nº 01", 11, INK, "mono_bold"))
	head.add_child(PK.t(str(_v.get("title", "")).to_upper(), 17, INK, "wide_black"))
	head.add_child(PK.t("LV %d  ·  FALLEN  ·  PULLS DAILY" % int(_v.get("level", 1)), 10, Color(INK, 0.8), "mono"))
	p.add_child(head)
	_fade.append(head)
	# The haul dome in the top-right corner (lit while today's haul waits), its LEDs under it.
	var ready := bool(_v.get("haul_ready", false))
	var dome := _stick(p, DOME, Vector2(_pw - 132, 16), 112.0, -0.12)
	if dome:
		dome.modulate = Color(1, 1, 1) if ready else Color(0.5, 0.46, 0.46)
		dome.name = "HaulDome"
	var hl := PK.t("HAUL READY" if ready else "HAUL TAKEN", 10, INK if ready else Color(INK, 0.55), "mono_bold")
	hl.position = Vector2(_pw - 124, 100)
	p.add_child(hl)
	# LEDs set into the felt: haul, wire, tag.
	var tags: Dictionary = _v.get("tags", {})
	var leds := [["HAUL", ready, Color(0.3, 1.0, 0.45)], ["WIRE", _fresh > 0, Color(1.0, 0.62, 0.1)], ["TAG", bool(tags.get("you", false)), SIG]]
	for i in leds.size():
		var e: Array = leds[i]
		var led := CK.HUDLed.new()
		led.on = bool(e[1])
		led.color = e[2]
		led.size = Vector2(9, 9)
		led.position = Vector2(_pw - 124, 126 + i * 22)
		p.add_child(led)
		PK.at(p, PK.t(str(e[0]), 9, Color(INK, 0.8), "mono_bold"), Vector2(_pw - 108, 122 + i * 22))
	# Her line on a paper slip stuck across the foot of the face (tap: she says something else).
	_build_line_slip(str(_v.get("line", "")))


func _haul_text() -> String:
	var h: Dictionary = _v.get("haul", {})
	var s := "%d GEMS · %s GOLD · %d DUST" % [int(h.get("gems", 0)), Kit.format_num(int(h.get("gold", 0))), int(h.get("dust", 0))]
	if not (_v.get("haul_print", {}) as Dictionary).is_empty():
		s += " · 1 PRINT"
	return s


func _build_line_slip(text: String) -> void:
	var p := _poster
	var slip := PanelContainer.new()
	slip.name = "LineSlip"
	slip.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(1, 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	slip.add_theme_stylebox_override("panel", sb)
	var v := Kit.vbox(2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(PK.t("RUE  ·  %s" % _kind_word(str(_v.get("line_kind", "idle"))), 10, SIG, "mono_bold"))
	_line_label = PK.t("“%s”" % text, 24, INK, "serif_italic")
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(minf(_pw - 140.0, 470.0), 0)
	v.add_child(_line_label)
	slip.add_child(v)
	slip.position = Vector2(BAND - 40.0, FACE - 150.0)
	slip.rotation = -0.025
	# Over her figure (the rig draws raised): her line was hidden behind her body.
	slip.z_index = 2
	p.add_child(slip)
	_fade.append(slip)
	CK.hit(p, Rect2(BAND - 40.0, FACE - 156.0, minf(_pw - 100.0, 520.0), 110.0), _next_line, "Line", "Talk")


static func _kind_word(kind: String) -> String:
	return {"intro": "HELLO", "idle": "TODAY", "win": "AFTER BEATING YOU", "lose": "AFTER LOSING", "counter": "COUNTER-PICKING",
		"featured_first": "GLOATING", "legendary": "GLOATING", "misprint": "SHOWING OFF", "holo": "SHOWING OFF"}.get(kind, "TODAY")


## The push button: another of her lines (cycles her idle and counter lines; no rules involved).
func _next_line() -> void:
	_line_n += 1
	var rs: Dictionary = Game.state.get("rival", {})
	var kinds := ["idle", "idle", "counter"] if str((_v.get("counter", {}) as Dictionary).get("faction", "")) != "" else ["idle"]
	var kind: String = kinds[_line_n % kinds.size()]
	var c: Dictionary = _v.get("counter", {})
	var ln := RivalRules.line(kind, int(rs.get("seed", 0)) + _line_n * 7, Game.today(), _line_n,
		{"you": ProfileScreen.player_name_raw(), "faction": str(c.get("faction", "")).capitalize(), "main": str(c.get("main", "")).capitalize()})
	if _line_label and is_instance_valid(_line_label):
		_line_label.text = "“%s”" % ln
		if Kit.motion_ok():
			_line_label.visible_ratio = 0.0
			_line_label.create_tween().tween_property(_line_label, "visible_ratio", 1.0, 0.5)
	UI.sfx("pop")


## The Fight pass and the knurled push button.
func _build_fight(y: float) -> float:
	var p := _poster
	var ready := bool(_v.get("haul_ready", false))
	var ac: Dictionary = {}
	for e: Dictionary in _v.get("team", []):
		if str(e.hero_id) == str(_v.get("ace", "")):
			ac = e
	var spec := {"width": 420.0, "kicker": "RIVAL // CHALLENGE", "title": "FIGHT RUE",
		"sub": "HER LV %d  ·  POWER %s" % [int(_v.get("level", 1)), Kit.format_num(int(_v.get("power", 0)))],
		"action": "FIGHT  >>>", "icon": "flag",
		"info": ("%d GEMS · %.1fK GOLD%s" % [int((_v.get("haul", {}) as Dictionary).get("gems", 0)),
			float((_v.get("haul", {}) as Dictionary).get("gold", 0)) / 1000.0,
			" · 1 PRINT" if not (_v.get("haul_print", {}) as Dictionary).is_empty() else ""]) if ready else "REMATCH FOR PRIDE"}
	var pass_root := Poster.pass_on(p, spec, Vector2(_pw - 440.0, y + 20.0), func() -> void: UI.go("battle", {"mode": "rival"}), "Fight", "Fight")
	_fade.append(pass_root)
	# The push button (talk) in its knurled bezel, with a printed label.
	var btn := _stick(p, BUTTON, Vector2(26, y + 26), 120.0)
	if btn:
		btn.name = "TalkButton"
	PK.at(p, PK.t("PUSH · TALK", 11, INK, "mono_bold"), Vector2(36, y + 128))
	var b := CK.hit(p, Rect2(16, y + 14, 140, 140), _next_line, "Talk", "Talk to Rue")
	if btn:
		b.button_down.connect(func() -> void: btn.scale = Vector2(0.94, 0.94))
		b.button_up.connect(func() -> void: btn.scale = Vector2.ONE)
	PK.rule(p, Vector2(16, y + 168), Vector2(_pw - 32, 1), Color(INK, 0.35))
	return y + 170.0


## Her team today: five small prints with leader lines, the counter-pick sticker.
func _build_team(y: float) -> float:
	var p := _poster
	PK.at(p, PK.t("01  HER TEAM TODAY", 12, INK, "mono_bold"), Vector2(24, y + 16))
	var team: Array = _v.get("team", [])
	var cap := PK.t("LV %d  ·  HER FIVE BEST" % int(_v.get("level", 1)), 11, Color(INK, 0.75), "mono")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.size = Vector2(300, 14)
	PK.at(p, cap, Vector2(_pw - 324, y + 17))
	var c: Dictionary = _v.get("counter", {})
	if str(c.get("faction", "")) != "":
		var st := PKS.sticker([["COUNTER-PICK", 10, "mono_bold"], ["%s  vs  YOUR %s" % [str(c.faction).to_upper(), str(c.main).to_upper()], 14, "mono_bold"]],
			{"fill": "signal", "rotation": 0.03, "pad": 10})
		st.position = Vector2(22, y + 42)
		p.add_child(st)
		_fade.append(st)
	var n := maxi(team.size(), 1)
	var gap := 12.0
	var cw := floorf((_pw - 48.0 - gap * (n - 1)) / n)
	var chh := roundf(cw * 1.18)
	var ty := y + 112.0
	var ace := str(_v.get("ace", ""))
	for i in team.size():
		var e: Dictionary = team[i]
		var hid := str(e.hero_id)
		var x := 24.0 + i * (cw + gap)
		var card := Control.new()
		card.name = "Team_%s" % hid
		card.mouse_filter = MOUSE_FILTER_IGNORE
		card.position = Vector2(x, ty)
		card.size = Vector2(cw, chh + 52)
		p.add_child(card)
		var bg := PK.rect(card, Rect2(0, 0, cw, chh), CARD)
		bg.name = "Paper"
		var art := TextureRect.new()
		art.mouse_filter = MOUSE_FILTER_IGNORE
		art.texture = Kit.art_crop(hid, (cw - 8.0) / (chh - 8.0), 1.0, Kit.hero_look(hid))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.position = Vector2(4, 4)
		art.size = Vector2(cw - 8, chh - 8)
		card.add_child(art)
		var fr := PK.Frame.new()
		fr.size = Vector2(cw, chh)
		card.add_child(fr)
		var nm := PK.t(str(HeroData.get_def(hid).get("name", hid)).to_upper(), 22, INK, "compressed")
		Kit.fit_label(nm, cw, 22, 12)
		nm.position = Vector2(0, chh + 2)
		card.add_child(nm)
		var stars := PK.t("LV %d  %s" % [int(e.level), "★".repeat(int(e.stars))], 9, Color(INK, 0.85), "mono_bold")
		stars.clip_text = true
		stars.size = Vector2(cw, 12)
		stars.position = Vector2(0, chh + 30)
		card.add_child(stars)
		if int(e.slot) < 2:
			var fl := PK.t("FRONT", 9, CARD, "mono_bold")
			var fb := ColorRect.new()
			fb.mouse_filter = MOUSE_FILTER_IGNORE
			fb.color = INK
			fb.size = fl.get_minimum_size() + Vector2(8, 0)
			fb.position = Vector2(4, 4)
			fl.position = Vector2(4, 0)
			fb.add_child(fl)
			card.add_child(fb)
		_fade.append(card)
		if hid == ace:
			var tab := ColorRect.new()
			tab.mouse_filter = MOUSE_FILTER_IGNORE
			tab.color = SIG
			tab.size = Vector2(cw, 4)
			card.add_child(tab)
			var ld := CK.Leader.new()
			ld.size = Vector2(_pw, 90)
			ld.position = Vector2(0, ty + chh + 40)
			var right := x < _pw * 0.6
			ld.from = Vector2(x + cw * 0.5, 4)
			ld.to = Vector2(x + cw * 0.5 + (46.0 if right else -46.0), 44)
			ld.run = 120.0
			ld.text = "HER ACE"
			ld.sub = "POWER %s" % Kit.format_num(int(e.get("power", 0)))
			p.add_child(ld)
	return ty + chh + 132.0


## The acrylic record card and her data list.
func _build_record(y: float) -> float:
	var p := _poster
	PK.at(p, PK.t("02  THE RECORD", 12, INK, "mono_bold"), Vector2(24, y + 10))
	var rec: Dictionary = _v.get("record", {})
	var cs := Vector2(316, 200)
	var card := ColorRect.new()
	card.name = "RecordCard"
	card.mouse_filter = MOUSE_FILTER_IGNORE
	card.size = cs
	card.position = Vector2(20, y + 40)
	card.rotation = -0.02
	var am := ShaderMaterial.new()
	am.shader = ACRYLIC
	am.set_shader_parameter("size", cs)
	am.set_shader_parameter("hole", Vector2(cs.x - 50.0, cs.y - 48.0))
	am.set_shader_parameter("hole_r", 28.0)
	am.set_shader_parameter("grid_from", cs.x * 0.56)
	card.material = am
	# A soft shadow under the acrylic (it stands a little off the felt).
	var sh := Panel.new()
	sh.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0)
	ss.set_corner_radius_all(14)
	ss.shadow_color = Color(0, 0, 0, 0.3)
	ss.shadow_size = 12
	ss.shadow_offset = Vector2(3, 8)
	sh.add_theme_stylebox_override("panel", ss)
	sh.size = cs
	sh.position = card.position
	sh.rotation = card.rotation
	p.add_child(sh)
	p.add_child(card)
	_fade.append(card)
	var w := int(rec.get("wins", 0))
	var l := int(rec.get("losses", 0))
	PK.at(card, PK.t("RECORD  ·  YOU vs RUE", 11, CARD, "mono_bold"), Vector2(18, 16))
	var big := PK.t("%02d—%02d" % [w, l], 84, CARD, "compressed")
	PK.at(card, big, Vector2(16, 30))
	PK.at(card, PK.t("WINS   ·   LOSSES", 10, Color(CARD, 0.9), "mono_bold"), Vector2(20, 128))
	PK.at(card, PK.t("FIGHTS %02d  ·  CODE RUE-%04d" % [int(rec.get("fights", 0)), int((Game.state.get("rival", {}) as Dictionary).get("seed", 0)) % 10000],
		10, Color(CARD, 0.85), "mono"), Vector2(20, 164))
	# A LED seen through the cut-out (lit when you hold the last win).
	var tags: Dictionary = _v.get("tags", {})
	var led := CK.HUDLed.new()
	led.on = bool(tags.get("her", false))
	led.color = Color(0.3, 1.0, 0.45)
	led.size = Vector2(12, 12)
	led.position = card.position + Vector2(cs.x - 56.0, cs.y - 54.0)
	p.add_child(led)
	# Her data, printed on the felt beside the card.
	var dl := CK.DataList.new()
	dl.name = "RivalData"
	var your := int(_v.get("your_power", 0))
	var hers := int(_v.get("power", 0))
	var cl := int(_v.get("cleared", 0))
	var stage_id := str(Game.stage(maxi(cl - 1, 0)).get("id", "--")) if cl > 0 else "--"
	var b := Game.banner(str(_v.get("banner", "standard")))
	dl.rows = [
		["POWER", Kit.format_num(hers), hers > your],
		["YOURS", Kit.format_num(your), your >= hers],
		[],
		["PULLS", Kit.format_num(int(_v.get("pulls", 0)))],
		["BANNER TODAY", str(b.get("short", "")).to_upper()],
		["CAMPAIGN", stage_id],
		["SPIRE", ("F%02d" % int(_v.get("tower_best", 0))) if int(_v.get("tower_best", 0)) > 0 else "--"],
		["HEROES", "%d" % (_v.get("roster", []) as Array).size()],
	]
	dl.text_size = 12
	dl.row_h = 23.0
	dl.bar = Color(1, 1, 1, 0.35)
	dl.position = Vector2(370, y + 44)
	dl.size = Vector2(_pw - 394, 190)
	p.add_child(dl)
	return y + 270.0


## THE WIRE: her feed as a printed ticker list on a paper sheet taped to the felt.
func _build_wire(y: float) -> float:
	var p := _poster
	var feed: Array = _v.get("feed", [])
	var rows := mini(feed.size(), 6)
	var sh := 96.0 + maxi(rows, 1) * 64.0
	var sheet := PK.poster(p, Rect2(20, y + 10, _pw - 40, sh), 10, CARD)
	sheet.name = "Wire"
	# The paper (PK.poster's shadow panel, right under the sheet) and the sheet go on top.
	var paper := p.get_child(sheet.get_index() - 1) as Control
	paper.name = "WirePaper"
	p.move_child(paper, p.get_child_count() - 1)
	p.move_child(sheet, p.get_child_count() - 1)
	var sw := _pw - 40.0
	PK.at(sheet, PK.t("03  THE WIRE  ·  RUE'S FEED", 12, INK, "mono_bold"), Vector2(18, 16))
	var nl := PK.t("%d NEW" % _fresh if _fresh > 0 else "ALL READ", 11, SIG if _fresh > 0 else Color(INK, 0.6), "mono_bold")
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nl.size = Vector2(200, 14)
	PK.at(sheet, nl, Vector2(sw - 218, 17))
	PK.at(sheet, Kit.tick_rule(sw - 36, Color(INK, 0.55), {"lead": SIG}), Vector2(18, 38))
	PK.at(sheet, PK.t("DATE", 9, Color(INK, 0.6), "mono_bold"), Vector2(18, 50))
	PK.at(sheet, PK.t("EVENT", 9, Color(INK, 0.6), "mono_bold"), Vector2(84, 50))
	PK.at(sheet, PK.t("WHAT SHE SAID", 9, Color(INK, 0.6), "mono_bold"), Vector2(190, 50))
	if feed.is_empty():
		var e := PK.t("Nothing on the wire yet. She pulls every morning.", 20, Color(INK, 0.7), "serif_italic")
		PK.at(sheet, e, Vector2(18, 74))
	var newest_seen := _seen_before
	for i in rows:
		var e: Dictionary = feed[i]
		var ry := 70.0 + i * 64.0
		var fresh := int(e.get("n", 0)) > newest_seen
		PK.at(sheet, PK.t(_date(int(e.get("day", 0))), 12, INK, "mono_bold"), Vector2(18, ry + 4))
		if fresh:
			var dot := CK.HUDLed.new()
			dot.on = true
			dot.size = Vector2(7, 7)
			dot.position = Vector2(18, ry + 26)
			sheet.add_child(dot)
			PK.at(sheet, PK.t("NEW", 8, SIG, "mono_bold"), Vector2(30, ry + 22))
		var kt: Array = KIND_TAGS.get(str(e.get("type", "")), ["NEWS", "ink"])
		var tl := PK.t(str(kt[0]), 10, CARD, "mono_bold")
		var tb := ColorRect.new()
		tb.mouse_filter = MOUSE_FILTER_IGNORE
		tb.color = SIG if str(kt[1]) == "sig" else INK
		tb.size = tl.get_minimum_size() + Vector2(10, 2)
		tb.position = Vector2(84, ry + 4)
		tl.position = Vector2(5, 1)
		tb.add_child(tl)
		sheet.add_child(tb)
		var hn := str(HeroData.get_def(str(e.get("hero", ""))).get("name", "")).to_upper()
		PK.at(sheet, PK.t(hn, 9, Color(INK, 0.75), "mono"), Vector2(84, ry + 26))
		var lt := PK.t(str(e.get("line", "")), 14, INK, "mono")
		lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lt.max_lines_visible = 2
		lt.size = Vector2(sw - 210, 40)
		PK.at(sheet, lt, Vector2(190, ry + 2))
		PK.rule(sheet, Vector2(18, ry + 56), Vector2(sw - 36, 1), Color(INK, 0.16))
	# Tape across the top corners.
	for tx: float in [-8.0, sw - 64.0]:
		var tape := ColorRect.new()
		tape.mouse_filter = MOUSE_FILTER_IGNORE
		tape.color = Color(0.93, 0.9, 0.82, 0.72)
		tape.size = Vector2(72, 22)
		tape.position = Vector2(20 + tx, y + 2)
		tape.rotation = -0.18 if tx < 0 else 0.16
		p.add_child(tape)
	return y + sh + 40.0


## Her binder: her best prints in slabs; taken ones stamped, the one a win today takes marked.
func _build_binder(y: float) -> void:
	var p := _poster
	PK.at(p, PK.t("04  HER BINDER  ·  BEST PRINTS", 12, INK, "mono_bold"), Vector2(24, y))
	var prints: Array = _v.get("prints", [])
	var hp: Dictionary = _v.get("haul_print", {})
	var ready := bool(_v.get("haul_ready", false))
	var hint := PK.t(("WIN TODAY: THE MARKED PRINT IS YOURS" if ready else "ONE PRINT A DAY TO THE WINNER") if not hp.is_empty() else "NOTHING LEFT TO TAKE", 11,
		INK if ready and not hp.is_empty() else Color(INK, 0.7), "mono_bold")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size = Vector2(380, 14)
	PK.at(p, hint, Vector2(_pw - 404, y + 1))
	if prints.is_empty():
		PK.at(p, PK.t("Her binder is empty. Give her a day.", 22, Color(INK, 0.75), "serif_italic"), Vector2(24, y + 40))
		return
	var n := mini(prints.size(), 3)
	var gap := 18.0
	var cw := floorf((_pw - 48.0 - gap * 2) / 3.0)
	var chh := roundf(cw * 1.5)
	for i in n:
		var pd: Dictionary = prints[i]
		var c := PrintCard.make(pd, Vector2(cw, chh))
		c.name = "RuePrint_%s" % str(pd.get("uid", i))
		c.position = Vector2(24 + i * (cw + gap), y + 30)
		c.rotation = (i - 1) * 0.02
		c.pivot_offset = c.size * 0.5
		p.add_child(c)
		_fade.append(c)
		if bool(pd.get("taken", false)):
			var st := PrintCard.Stamp.new()
			st.text = "TAKEN"
			st.sub = "BY %s" % ProfileScreen.player_name()
			st.color = INK
			st.size = Vector2(cw * 0.8, cw * 0.28)
			st.position = Vector2(cw * 0.1, chh * 0.45)
			st.pivot_offset = st.size * 0.5
			st.rotation = 0.2
			c.add_child(st)
		elif str(pd.get("uid", "")) == str(hp.get("uid", "-")) and ready:
			var tag := PKS.sticker([["WIN →", 11, "mono_bold"], ["IT'S YOURS", 13, "mono_bold"]], {"fill": "signal", "rotation": -0.06, "pad": 8})
			tag.position = Vector2(-12, -18)
			c.add_child(tag)


## Thorns overgrowing her poster: a corner growth over the face's foot on the band, a vine down
## the right edge beside the wire and a corner turned into the poster's foot.
func _build_thorns(wire_end: float) -> void:
	var p := _poster
	var a := _stick(p, THORN_CORNER, Vector2(-120, FACE - 330), 420.0, 0.0)
	if a:
		a.name = "ThornsFace"
		# Under her line's paper slip (and your tag), never over the words.
		var slip := p.get_node_or_null("LineSlip") as Control
		if slip:
			p.move_child(a, slip.get_index())
	var wire := p.get_node_or_null("Wire") as Control
	var vy := (wire.position.y - 90.0) if wire else wire_end - 340.0
	var v := _stick(p, THORN_VINE, Vector2(_pw - 96, vy), 230.0, 0.12, true)
	if v:
		v.name = "ThornsVine"
		var paper := p.get_node_or_null("WirePaper") as Control
		if paper:
			p.move_child(v, paper.get_index())
	var c := _stick(p, THORN_CORNER, Vector2(_pw - 290, _ph - 210), 340.0, PI)
	if c:
		c.name = "ThornsFoot"


## Your tag on her poster once you beat her: your call sign scrawled in marker across RUE, and a
## sticker.
func _build_tags() -> void:
	var tags: Dictionary = _v.get("tags", {})
	if not bool(tags.get("her", false)):
		return
	var p := _poster
	var who := ProfileScreen.player_name()
	var txt := "%s WAS HERE" % who
	var sc := CK.Scrawl.new()
	sc.name = "YourTag"
	sc.text = txt
	sc.color = Color("1a1b1e")
	sc.stroke = 8.0
	sc.seed_v = int(tags.get("v", 3))
	var h := 58.0
	sc.size = Vector2(CK.Scrawl.width_for(txt, h, 8.0), h)
	var s := minf(1.0, (FACE - 200.0) / sc.size.x)
	sc.scale = Vector2(s, s)
	# Up the side of her name, reading bottom to top, clear of her face.
	sc.rotation = -PI * 0.5 + 0.08
	sc.position = Vector2(BAND + 56.0, FACE - 190.0)
	p.add_child(sc)
	var st := CK.Sticker.new()
	st.name = "BeatenSticker"
	st.lines = ["BEATEN", "BY %s" % who]
	st.fill = Color("f7f6f2")
	st.ink = INK
	st.round = false
	st.size = Vector2(200, 64)
	st.position = Vector2(20, FACE - 250)
	st.rotation = -0.14
	p.add_child(st)


## Locked: the felt poster sealed (a red jelly seal over the note), with the stage that opens it.
func _build_locked() -> void:
	var p := _poster
	var face := _ph
	PK.rect(p, Rect2(0, 0, BAND, face), BAND_C)
	var fs := 360
	_giant("RUE", fs, BAND + 200, 130, face, 0.0, BAND, face)
	var need := int(_v.get("unlock_cleared", RivalRules.UNLOCK_CLEARED))
	var sid := str(Game.stage(need - 1).get("id", "1-%d" % need))
	var st := PKS.sticker([["SEALED", 12, "mono_bold"], ["Someone else is summoning here.", 22, "serif_italic"],
		["SHE SHOWS UP AFTER STAGE %s  ·  YOU: %d / %d CLEARED" % [sid, Game.cleared_count(), need], 12, "mono_bold"]],
		{"fill": "white", "rotation": -0.03, "pad": 16})
	st.position = Vector2(BAND + 30, face * 0.5)
	p.add_child(st)
	# Sealed with a blob of red jelly gone to moss, two LEDs set in it.
	var seal := _stick(p, SEAL, Vector2(_pw - 168, face * 0.5 - 132), 170.0, 0.1)
	if seal:
		seal.name = "Seal"
	_stick(p, THORN_CORNER, Vector2(_pw - 330, -60), 380.0, 0.0, true)
	_stick(p, DOME, Vector2(_pw - 170, face - 220), 120.0, 0.1)


func _build_footer(ox: float, w: float, pr: Rect2) -> void:
	var fy := pr.end.y + 12.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sl := PK.t("Rue", 44, INK, "serif_italic")
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.size = Vector2(330, 54)
	PK.at(_page, sl, Vector2(ox + w - 24 - 330, fy - 4))
	PK.rule(_page, Vector2(ox + w - 220, fy + 56), Vector2(196, 2), INK).rotation = -0.05


static func _date(day: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day * 86400)
	return "%02d.%02d" % [int(dt.day), int(dt.month)]


# ------------------------------------------------------------------ the first visit

## Her introduction (first visit): a paper slip with her line typed out, her signature and a MET
## stamp. Tap to close.
func _play_intro() -> void:
	var r := Game.rival_meet()
	var ln := str((r.get("value", {}) as Dictionary).get("line", "")) if bool(r.get("ok", false)) else str(_v.get("line", ""))
	var root := Control.new()
	root.name = "RueIntro"
	root.custom_minimum_size = Vector2(minf(get_viewport_rect().size.x - 40.0, 660.0), 520)
	root.size = root.custom_minimum_size
	root.mouse_filter = MOUSE_FILTER_STOP
	var sheet := PK.poster(root, Rect2(Vector2.ZERO, root.size), 18, CARD)
	PK.rect(sheet, Rect2(0, 0, 18, root.size.y), BAND_C)
	PK.at(sheet, PK.t("A NEW FILE  ·  RIVAL Nº 01", 12, SIG, "mono_bold"), Vector2(44, 30))
	PK.at(sheet, PK.t("RUE", 120, INK, "compressed"), Vector2(40, 46))
	PK.at(sheet, PK.t("THE OTHER SUMMONER  ·  FALLEN", 12, Color(INK, 0.75), "mono"), Vector2(44, 184))
	var l := PK.t("“%s”" % ln, 32, INK, "serif_italic")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(root.size.x - 90, 160)
	PK.at(sheet, l, Vector2(44, 222))
	if Kit.motion_ok():
		l.visible_ratio = 0.0
		l.create_tween().tween_property(l, "visible_ratio", 1.0, 1.2).set_delay(0.3)
	PK.at(sheet, PK.t("Rue", 46, INK, "serif_italic"), Vector2(root.size.x - 170, 396))
	PK.at(sheet, PK.t("SHE PULLS EVERY MORNING. BEAT HER FOR HER HAUL.\nLOSING COSTS NOTHING. TAP TO CLOSE.", 11, Color(INK, 0.72), "mono_bold"), Vector2(44, 460))
	var stp := PK.t("MET %s" % Poster.date_short(), 16, SIG, "wide_black")
	var sb := PanelContainer.new()
	sb.mouse_filter = MOUSE_FILTER_IGNORE
	var sbs := StyleBoxFlat.new()
	sbs.bg_color = Color(0, 0, 0, 0)
	sbs.border_color = SIG
	sbs.set_border_width_all(3)
	sbs.content_margin_left = 10
	sbs.content_margin_right = 10
	sb.add_theme_stylebox_override("panel", sbs)
	sb.add_child(stp)
	sb.position = Vector2(root.size.x - 260, 60)
	sb.rotation = 0.14
	sheet.add_child(sb)
	var close := CK.hit(root, Rect2(Vector2.ZERO, root.size), func() -> void:
		if _modal and is_instance_valid(_modal):
			UI.close_modal(_modal)
		_modal = null, "Close", "OK")
	close.mouse_filter = MOUSE_FILTER_STOP
	_modal = UI.modal(root, true, func() -> void: _modal = null)
	UI.sfx("reveal")
