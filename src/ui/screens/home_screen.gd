extends Control
## Screen "home": the Lobby as a printed poster (style v4, docs/dev/ui-style-v4.md section 0; the
## approved mockup is lobby_v5). Between the shell's paper masthead and footer strip, a poster is
## mounted on a paper matte:
## - a dark band with the lobby hero as a red halftone print, the bulletin (summon banner, offers,
##   chapter; turns every 5 s) and her number with < > to switch the lobby hero ("lobby_hero");
## - her lobby line set huge in compressed type, turned on its side and cut by the poster edge, the
##   last word in signal (tap her for another line, she cheers);
## - the hero in full colour, boxed by the right-hand rule, where small vertical labels are the
##   side menu (Daily, Offers, Team, Spire, Shop, Hero, View) with status lights;
## - stuck on: a rendered coil, the Sanctum stamp on a machined disc (idle rewards: fill, level,
##   time; tap for the claim sheet), a paper label with the next objective, and the Campaign pass
##   (next stage, recommended power).
## Under the poster: the date and her signature (tap: her hero page). View hides the stuck-on
## pieces and the chrome. Refreshes on Game.changed and once a second.

const HUD := preload("res://src/ui/components/hud.gd")
const LobbyLines := preload("res://src/ui/battle/lobby_lines.gd")

## Game setting holding the hero the player picked for the lobby.
const HERO_KEY := "lobby_hero"
const BANNER_SECS := 5.0
const BAND := 248.0
const PAPER := SignalKit.PAPER
const MATTE := SignalKit.MATTE
const INK := SignalKit.INK
const SIG := SignalKit.SIGNAL
const BAND_C := Color("141517")
## Rendered collage objects (tools/blender/ui_objects.py): the object sits at PAD px inside the PNG
## (the rest is its baked paper shadow), OBJ px across.
const COIL_TEX := "res://assets/art/ui/objects/coil_ink.png"
const COIL_PAD := 46.0
const COIL_OBJ := 480.0
const DISC_TEX := "res://assets/art/ui/objects/disc.png"
const DISC_PAD := 23.0
const DISC_OBJ := 300.0
const STAMP := 140.0
const MENU := [["daily", "DAILY"], ["offers", "OFFERS"], ["team", "TEAM"], ["spire", "SPIRE"], ["shop", "SHOP"],
	["hero", "HERO"], ["view", "VIEW"]]

## Blurred red echoes of hero art, by art key (an Image resize per hero is not free).
static var _echo_cache: Dictionary = {}

var _hero_id := ""
## What the Lobby sprite shows (HeroArt.art_key: hero, skin, nude or not); a change rebuilds it.
var _hero_key := ""
var _anchor: Node2D
var _sprite: Node2D
var _line := 0
var _cheer_left := 0.0
## Taps in a row on her (HeroReact) and when the last one landed (seconds of _t).
var _tap_n := 0
var _tap_at := -10.0

var _built := Vector2.ZERO
var _pw := 0.0
var _ph := 0.0
var _page: Control
var _page_anchor := Vector2.ZERO
var _poster: Control
var _print_layer: Control
var _type_layer: Control
var _type_rts: Array[RichTextLabel] = []
var _hero_box: Control
var _hero_hit: Button
var _over: Control
var _bull_slot: Control
var _bull_page := 0
var _bull_t := 0.0
var _index_label: Label
var _total_label: Label
var _prev_btn: Button
var _next_btn: Button
var _labels: Dictionary = {}
var _leds: Dictionary = {}
var _tape: Button
var _tape_text: Label
var _tape_cb := Callable()
var _stamp_btn: Button
var _stamp_ink: Control
var _full := false
var _pass_slot: Control
var _pass_root: Control
var _pass_led: Control
var _pass_sig := "-"
var _sig_label: Label
var _viewing := false
var _restore: Button
var _sheet: Control
var _sheet_refs: Dictionary = {}
var _t := 0.0
var _tick := 0.0


## params: sheet (bool) opens the Sanctum sheet (screenshots).
func setup(params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	resized.connect(_on_resized)
	_refresh()
	if bool(params.get("sheet", false)):
		_open_sanctum.call_deferred()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	_close_sheet()


## Entrance (UI calls it after the screen appears): her line typesets down the poster, she fades
## up, the menu labels and the bulletin drop in, the label slides on, the stamp is pressed down and
## the pass rises onto the poster's edge.
func intro() -> void:
	if not Kit.motion_ok():
		return
	if _anchor:
		_anchor.modulate.a = 0.0
		_anchor.create_tween().tween_property(_anchor, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_typeset_in(0.05)
	Kit.offset_in(_bull_slot, Vector2(0, -24), 0.1, 0.45)
	var i := 0
	for m: Array in MENU:
		var b := _labels.get(m[0]) as Control
		if b:
			Kit.offset_in(b, Vector2(28, 0), 0.14 + i * 0.04, 0.45)
		i += 1
	Kit.offset_in(_tape, Vector2(-36, 0), 0.3, 0.45)
	if _stamp_btn:
		_stamp_btn.modulate.a = 0.0
		_stamp_btn.scale = Vector2(1.35, 1.35)
		var st := _stamp_btn.create_tween().set_parallel(true)
		st.tween_property(_stamp_btn, "modulate:a", 1.0, 0.18).set_delay(0.38)
		st.tween_property(_stamp_btn, "scale", Vector2.ONE, 0.32).set_delay(0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Kit.offset_in(_pass_slot, Vector2(0, 90), 0.3, 0.55)


# ------------------------------------------------------------------ build

func _build() -> void:
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var h := size.y if size.y > 0.0 else get_viewport_rect().size.y - UI.content_top() - UI.content_bottom()
	_built = Vector2(w, h)
	var matte := ColorRect.new()
	matte.name = "Matte"
	matte.color = MATTE
	matte.mouse_filter = MOUSE_FILTER_IGNORE
	matte.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(matte)

	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.size = Vector2(w, h)
	add_child(_page)

	# ---- The poster, with a soft shadow on the matte.
	var pr := Rect2(16, 14, w - 32, maxf(h - 14 - 92, 520))
	_pw = pr.size.x
	_ph = pr.size.y
	var shadow := Panel.new()
	shadow.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = PAPER
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.position = pr.position
	shadow.size = pr.size
	_page.add_child(shadow)
	_poster = Control.new()
	_poster.name = "Poster"
	_poster.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.position = pr.position
	_poster.size = pr.size
	_poster.clip_contents = true
	_page.add_child(_poster)

	var band := ColorRect.new()
	band.color = BAND_C
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.size = Vector2(BAND, _ph)
	_poster.add_child(band)
	_print_layer = _layer(_poster, "Print")
	var mark := Kit.label("HH", 34, PAPER, "wide_black")
	mark.position = Vector2(20, 18)
	_poster.add_child(mark)
	var tm := Kit.label("™", 12, PAPER, "mono")
	tm.position = Vector2(84, 20)
	_poster.add_child(tm)
	var rights := Kit.label("©2026 HH, ALL RIGHTS RESERVED.", 11, Color(PAPER, 0.8), "mono_bold")
	rights.rotation = PI * 0.5
	rights.position = Vector2(46, 90)
	_poster.add_child(rights)

	# The coil, rendered (top right of the paper, cut by the poster's top edge).
	var coil_tex := load(COIL_TEX) as Texture2D
	if coil_tex:
		var k := 250.0 / COIL_OBJ
		var coil := TextureRect.new()
		coil.texture = coil_tex
		coil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coil.stretch_mode = TextureRect.STRETCH_SCALE
		coil.mouse_filter = MOUSE_FILTER_IGNORE
		coil.size = coil_tex.get_size() * k
		coil.position = Vector2(BAND + 168, -96) - Vector2(COIL_PAD, COIL_PAD) * k
		_poster.add_child(coil)

	_type_layer = _layer(_poster, "Type")
	# The hero, full colour, in front of her line, boxed by the right-hand rule.
	_hero_box = Control.new()
	_hero_box.name = "HeroBox"
	_hero_box.clip_contents = true
	_hero_box.mouse_filter = MOUSE_FILTER_IGNORE
	_hero_box.size = Vector2(_pw - 49, _ph)
	_poster.add_child(_hero_box)
	_anchor = Node2D.new()
	_anchor.name = "LobbyHero"
	_anchor.position = Vector2(BAND + 250, _ph)
	_hero_box.add_child(_anchor)
	_hero_hit = Button.new()
	_hero_hit.name = "HeroHit"
	_hero_hit.theme_type_variation = &"BareButton"
	_hero_hit.focus_mode = FOCUS_NONE
	_hero_hit.mouse_filter = MOUSE_FILTER_PASS
	_hero_hit.position = Vector2(BAND + 60, _ph * 0.05)
	_hero_hit.size = Vector2(_pw - 49 - BAND - 100, _ph * 0.62)
	_hero_hit.pressed.connect(_on_hero_tap)
	_poster.add_child(_hero_hit)
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.55)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	rule.position = Vector2(_pw - 48, 0)
	rule.size = Vector2(1, _ph)
	_poster.add_child(rule)
	var top_mark := Kit.label("©2026 ·", 12, INK, "mono_bold")
	top_mark.rotation = PI * 0.5
	top_mark.position = Vector2(_pw - 38, 14)
	_poster.add_child(top_mark)

	# ---- Everything stuck on or printed as a control (hidden by View), over the poster, unclipped.
	_over = Control.new()
	_over.name = "LobbyUI"
	_over.mouse_filter = MOUSE_FILTER_IGNORE
	_over.position = pr.position
	_over.size = pr.size
	_page.add_child(_over)
	_bull_slot = Control.new()
	_bull_slot.name = "Bulletin"
	_bull_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_bull_slot.position = Vector2(60, 64)
	_bull_slot.size = Vector2(196, 176)
	_over.add_child(_bull_slot)
	_show_bulletin(0, false)
	_build_index()
	_build_menu()
	_build_tape()
	_build_stamp()

	# The Campaign pass, over the poster's bottom edge.
	_pass_slot = Control.new()
	_pass_slot.name = "PassSlot"
	_pass_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_pass_slot.position = Vector2(pr.position.x + _pw - 412, pr.end.y - 176)
	_pass_slot.size = Vector2(400, 176)
	_pass_slot.rotation = -0.035
	_page.add_child(_pass_slot)
	_pass_sig = "-"

	# ---- Under the poster: the date and her signature.
	var d := Time.get_date_dict_from_system()
	var date := Kit.label("%d %02d/%02d" % [int(d.year), int(d.month), int(d.day)], 26, INK, "regular")
	date.position = Vector2(20, pr.end.y + 22)
	_page.add_child(date)
	var sig_btn := Button.new()
	sig_btn.name = "Signature"
	sig_btn.theme_type_variation = &"BareButton"
	sig_btn.focus_mode = FOCUS_NONE
	sig_btn.position = Vector2(w - 24 - 330, pr.end.y)
	sig_btn.size = Vector2(330, 88)
	sig_btn.pressed.connect(_open_hero)
	_page.add_child(sig_btn)
	_sig_label = Kit.label("", 50, INK, "serif_italic")
	_sig_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sig_label.mouse_filter = MOUSE_FILTER_IGNORE
	_sig_label.size = Vector2(330, 60)
	_sig_label.position = Vector2(0, 4)
	sig_btn.add_child(_sig_label)
	var swash := ColorRect.new()
	swash.color = INK
	swash.mouse_filter = MOUSE_FILTER_IGNORE
	swash.position = Vector2(110, 66)
	swash.size = Vector2(210, 2)
	swash.rotation = -0.06
	sig_btn.add_child(swash)

	add_child(SignalKit.grain(0.06, true))


func _layer(parent: Control, layer_name: String) -> Control:
	var c := Control.new()
	c.name = layer_name
	c.mouse_filter = MOUSE_FILTER_IGNORE
	c.size = parent.size
	parent.add_child(c)
	return c


## The hero's number in the band, with < > to switch the lobby hero.
func _build_index() -> void:
	var y := _ph * 0.5 - 52.0
	var no := Kit.label("No.", 12, Color(PAPER, 0.85), "mono_bold")
	no.position = Vector2(150, y)
	_over.add_child(no)
	_index_label = Kit.label("001", 12, Color(PAPER, 0.85), "mono_bold")
	_index_label.position = Vector2(150, y + 16)
	_over.add_child(_index_label)
	_total_label = Kit.label("/ 001", 12, Color(PAPER, 0.55), "mono_bold")
	_total_label.position = Vector2(192, y + 16)
	_over.add_child(_total_label)
	_prev_btn = _chevron(-1)
	_prev_btn.position = Vector2(62, _ph * 0.5 - 10)
	_next_btn = _chevron(1)
	_next_btn.position = Vector2(152, _ph * 0.5 - 10)
	_over.add_child(_prev_btn)
	_over.add_child(_next_btn)


## A paper-white chevron in a hairline ring (88 px target). dir -1 = previous.
func _chevron(dir: int) -> Button:
	var b := Button.new()
	b.name = "Prev" if dir < 0 else "Next"
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.size = Vector2(88, 88)
	b.pressed.connect(func() -> void:
		Kit.sfx("tap")
		_switch_hero(dir))
	var ring := Panel.new()
	ring.mouse_filter = MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0, 0, 0, 0)
	rs.border_color = Color(PAPER, 0.55)
	rs.set_border_width_all(1)
	rs.set_corner_radius_all(26)
	rs.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", rs)
	ring.position = Vector2(18, 18)
	ring.size = Vector2(52, 52)
	b.add_child(ring)
	var g := Kit.icon("chevron_right", 26, Color(PAPER, 0.92))
	g.flip_h = dir < 0
	g.position = Vector2(31, 31)
	g.size = Vector2(26, 26)
	b.add_child(g)
	return b


## The side menu: small vertical labels with ticks down the right-hand rule, each an 88 px target
## with a status light.
func _build_menu() -> void:
	var y0 := 64.0
	var y1 := _ph - 200.0
	var pitch := maxf((y1 - y0) / MENU.size(), 72.0)
	var i := 0
	for m: Array in MENU:
		var id: String = m[0]
		var b := Button.new()
		b.name = "Side" + id.capitalize()
		b.theme_type_variation = &"BareButton"
		b.focus_mode = FOCUS_NONE
		b.position = Vector2(_pw - 88, y0 + i * pitch)
		b.size = Vector2(88, maxf(pitch, 88.0))
		b.pressed.connect(_on_menu.bind(id))
		var l := Kit.label(str(m[1]), 15, INK, "mono_bold")
		l.mouse_filter = MOUSE_FILTER_IGNORE
		l.rotation = PI * 0.5
		l.position = Vector2(72, 22)
		b.add_child(l)
		var tick := ColorRect.new()
		tick.color = INK
		tick.mouse_filter = MOUSE_FILTER_IGNORE
		tick.position = Vector2(36, 24)
		tick.size = Vector2(9, 1)
		b.add_child(tick)
		var led := HUD.Led.new()
		led.size = Vector2(16, 16)
		led.position = Vector2(57, 2)
		led.mode = "breathe"
		led.visible = false
		b.add_child(led)
		_over.add_child(b)
		_labels[id] = b
		_leds[id] = led
		i += 1


func _on_menu(id: String) -> void:
	Kit.sfx("tap")
	match id:
		"daily":
			UI.go("quests")
		"offers":
			UI.go("shop", {"tab": 0})
		"team":
			UI.go("formation")
		"spire":
			UI.go("tower")
		"shop":
			UI.go("shop")
		"hero":
			_open_hero()
		"view":
			_hide_ui()


## The next objective as a paper label stuck across the foot of the band.
func _build_tape() -> void:
	_tape = Button.new()
	_tape.name = "Objective"
	_tape.theme_type_variation = &"BareButton"
	_tape.focus_mode = FOCUS_NONE
	_tape.position = Vector2(10, _ph - 112)
	_tape.size = Vector2(240, 88)
	_tape.rotation = -0.03
	_tape.pressed.connect(func() -> void:
		if _tape_cb.is_valid():
			Kit.sfx("tap")
			_tape_cb.call())
	var p := PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = PAPER
	ps.shadow_color = Color(0, 0, 0, 0.35)
	ps.shadow_size = 6
	ps.shadow_offset = Vector2(0, 3)
	ps.content_margin_left = 12
	ps.content_margin_right = 12
	ps.content_margin_top = 8
	ps.content_margin_bottom = 9
	p.add_theme_stylebox_override("panel", ps)
	p.position = Vector2(0, 12)
	p.custom_minimum_size = Vector2(232, 0)
	var col := Kit.vbox(2)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(Kit.label("NEXT →", 12, SIG, "mono_bold"))
	_tape_text = Kit.label("", 14, INK, "mono_bold")
	_tape_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tape_text.custom_minimum_size.x = 208
	_tape_text.max_lines_visible = 2
	col.add_child(_tape_text)
	p.add_child(col)
	_tape.add_child(p)
	_over.add_child(_tape)


## The Sanctum stamp: printed ink on a rendered, machined disc.
func _build_stamp() -> void:
	_stamp_btn = Button.new()
	_stamp_btn.name = "Sanctum"
	_stamp_btn.theme_type_variation = &"BareButton"
	_stamp_btn.focus_mode = FOCUS_NONE
	# Across the band's edge, clear of the pass below it.
	_stamp_btn.position = Vector2(BAND - 74, _ph - 336)
	_stamp_btn.size = Vector2(STAMP, STAMP)
	_stamp_btn.pivot_offset = Vector2(STAMP, STAMP) * 0.5
	_stamp_btn.rotation = -0.12
	_stamp_btn.pressed.connect(func() -> void:
		Kit.sfx("tap")
		_open_sanctum())
	var tex := load(DISC_TEX) as Texture2D
	if tex:
		var k := STAMP / DISC_OBJ
		var disc := TextureRect.new()
		disc.texture = tex
		disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		disc.stretch_mode = TextureRect.STRETCH_SCALE
		disc.mouse_filter = MOUSE_FILTER_IGNORE
		disc.size = tex.get_size() * k
		disc.position = -Vector2(DISC_PAD, DISC_PAD) * k
		_stamp_btn.add_child(disc)
	_stamp_ink = SignalKit.stamp("SANCTUM · ", "0%", STAMP * 0.84)
	_stamp_ink.position = Vector2(STAMP, STAMP) * 0.08
	_stamp_btn.add_child(_stamp_ink)
	_over.add_child(_stamp_btn)


func _on_resized() -> void:
	if _page == null:
		return
	if _viewing:
		# The chrome went away and the screen grew: keep the poster where it was.
		_page.global_position = _page_anchor
	elif absf(size.x - _built.x) > 1.0 or absf(size.y - _built.y) > 1.0:
		_rebuild.call_deferred()
	else:
		_page.position = Vector2.ZERO


func _rebuild() -> void:
	if _viewing or (absf(size.x - _built.x) <= 1.0 and absf(size.y - _built.y) <= 1.0):
		return
	for c in get_children():
		c.queue_free()
	_labels = {}
	_leds = {}
	_hero_id = ""
	_hero_key = ""
	_sprite = null
	_type_rts = []
	_build()
	_refresh()


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _page == null:
		return
	_refresh_hero()
	_refresh_idle()
	_refresh_campaign()
	_refresh_badges()
	_refresh_guide()


## First-session guidance: the Sanctum stamp (free quick claim), the Team label and the Campaign
## pass; the Sanctum sheet marks its Quick Claim button.
func _refresh_guide() -> void:
	var step := Guide.step()
	Guide.mark(_stamp_btn, step == "claim", 0)
	Guide.mark(_labels.get("team") as Control, step == "formation", 0)
	if _pass_root and is_instance_valid(_pass_root):
		Guide.mark(_pass_root, step == "battle", 0)
	var q: Variant = _sheet_refs.get("quick", null)
	if q is Control and is_instance_valid(q):
		Guide.mark(q as Control, step == "claim", 0)


func _refresh_badges() -> void:
	_set_led("daily", int(Game.quests_ready_count()) > 0)
	var gift := false
	for o: Dictionary in Game.offers():
		if str(o.get("price_label", "")) == "Free" and bool(o.get("available", false)):
			gift = true
	_set_led("offers", gift)
	_set_led("team", Guide.formation_can_improve())
	_refresh_objective()


func _set_led(id: String, on: bool) -> void:
	var led := _leds.get(id) as Control
	if led:
		led.visible = on


## The label: the guide's next step while it is active, else the next stage.
func _refresh_objective() -> void:
	var st := Game.current_stage()
	var text := "Stage %s" % str(st.get("id", "")) if not st.is_empty() else "Every stage cleared"
	var cb := _on_campaign
	match Guide.step():
		"claim":
			# The first claim is the free Quick Claim inside the Sanctum sheet.
			var idle: Dictionary = Game.idle_status()
			var hours := int(idle.get("quick_claim_ms", 7200000)) / 3600000
			text = "Quick Claim %dh of rewards" % hours
			cb = _open_sanctum
		"summon":
			text = "Summon new heroes"
			cb = func() -> void: UI.go("summon")
		"formation":
			text = "Fill your team"
			cb = func() -> void: UI.go("formation")
		"level":
			text = "Level up heroes"
			cb = func() -> void: UI.go("heroes")
		"quests":
			text = "Claim quest rewards"
			cb = func() -> void: UI.go("quests")
	_tape_text.text = text.to_upper()
	_tape_cb = cb


# ------------------------------------------------------------------ the lobby hero

## The hero shown in the lobby: the player's pick if still owned, else the strongest team
## hero (heroes with painted art first).
func _pick_hero() -> String:
	var want: Variant = Game.setting(HERO_KEY)
	if want is String and want != "" and Game.owns(want):
		return want
	var best := ""
	var best_score := -1
	for id: String in Game.formation():
		if id == "":
			continue
		var score: int = int(Game.hero_power(id)) + (100000000 if HeroArt.has_art(id) else 0)
		if score > best_score:
			best_score = score
			best = id
	if best == "":
		var owned := Game.owned_heroes()
		if not owned.is_empty():
			best = str(owned[0].id)
	return best


## Owned heroes in lobby order: the team first (slot order), then the rest by power.
func _hero_order() -> Array[String]:
	var out: Array[String] = []
	for id: String in Game.formation():
		if id != "" and not out.has(id):
			out.append(id)
	var rest: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		var id := str(h.get("id", ""))
		if id != "" and not out.has(id):
			rest.append(id)
	rest.sort_custom(func(a: String, b: String) -> bool: return int(Game.hero_power(a)) > int(Game.hero_power(b)))
	out.append_array(rest)
	return out


func _refresh_hero() -> void:
	var id := _pick_hero()
	var order := _hero_order()
	_prev_btn.visible = order.size() > 1
	_next_btn.visible = order.size() > 1
	_index_label.text = "%03d" % (order.find(id) + 1)
	_total_label.text = "/ %03d" % order.size()
	var skin := Game.equipped_skin(id) if id != "" else ""
	var key := HeroArt.art_key(id, skin) if id != "" else ""
	if id == _hero_id and key == _hero_key:
		return
	_hero_id = id
	_hero_key = key
	if _sprite and is_instance_valid(_sprite):
		_sprite.queue_free()
	_sprite = null
	_cheer_left = 0.0
	for c in _print_layer.get_children():
		c.queue_free()
	_sig_label.text = str(Game.hero_def(id).get("name", id)) if id != "" else ""
	if id == "":
		_typeset("", false)
		return
	_build_print(id, skin, key)
	_sprite = HeroArt.make_sprite(id, skin)
	_anchor.add_child(_sprite)
	var base_h: float = _sprite.call("get_height")
	var k := _ph * 0.98 / maxf(base_h, 1.0)
	_sprite.scale = Vector2(k, k)
	var lines := LobbyLines.lines(id)
	_line = int(Time.get_unix_time_from_system() / 60.0) % lines.size()
	_typeset(lines[_line], false)


## The band's red halftone print of her (head to waist) and her blurred red echo on the paper.
func _build_print(id: String, skin: String, key: String) -> void:
	var tex := HeroArt.texture(id, skin)
	if tex == null:
		return
	var face := HeroArt.portrait_region(id, skin)
	var at := AtlasTexture.new()
	at.atlas = tex
	var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.42, face.size.y * 0.62), Vector2(face.size.x * 0.84, face.size.y * 1.9))
	at.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	var ht := TextureRect.new()
	ht.texture = at
	ht.mouse_filter = MOUSE_FILTER_IGNORE
	ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ht.position = Vector2(0, _ph * 0.24)
	ht.size = Vector2(BAND, _ph * 0.76)
	ht.material = SignalKit.halftone_material(7.0, Color(1.0, 0.36, 0.16, 0.95))
	_print_layer.add_child(ht)
	var echo_tex: Texture2D = _echo_cache.get(key)
	if echo_tex == null:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.resize(maxi(img.get_width() / 20, 8), maxi(img.get_height() / 20, 8), Image.INTERPOLATE_BILINEAR)
			echo_tex = ImageTexture.create_from_image(img)
			_echo_cache[key] = echo_tex
	if echo_tex:
		var echo := TextureRect.new()
		echo.texture = echo_tex
		echo.mouse_filter = MOUSE_FILTER_IGNORE
		echo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		echo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		echo.size = Vector2(640, 1280)
		echo.position = Vector2(150, _ph * 0.08)
		echo.modulate = Color(1.0, 0.3, 0.12, 0.38)
		_print_layer.add_child(echo)


## Sets her line huge, turned on its side: ink over the paper, paper-white over the band, the last
## word in signal. The size is the largest that fits the poster's height in at most ~420 px of
## lines.
func _typeset(line: String, animate: bool) -> void:
	for c in _type_layer.get_children():
		c.queue_free()
	_type_rts = []
	if line == "":
		return
	var text := line.to_upper()
	var words := text.split(" ")
	var key := words[words.size() - 1]
	var bb := " ".join(words.slice(0, words.size() - 1)) + " [color=#%s]%s[/color]" % [SIG.to_html(false), key]
	var length := _ph * 0.94
	var fs := _fit_size(text, length, 420.0)
	for side: Array in [[0.0, BAND, PAPER], [BAND, _pw - BAND, INK]]:
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		clip.position = Vector2(side[0], 0)
		clip.size = Vector2(side[1], _ph)
		_type_layer.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bb
		rt.fit_content = false
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.add_theme_font_override("normal_font", Kit.font("compressed"))
		rt.add_theme_font_size_override("normal_font_size", fs)
		rt.add_theme_color_override("default_color", side[2])
		rt.add_theme_constant_override("line_separation", -int(14.0 * fs / 118.0))
		rt.mouse_filter = MOUSE_FILTER_IGNORE
		rt.size = Vector2(length, 430)
		rt.rotation = PI * 0.5
		# Turned clockwise: the first line runs down the poster at x = 500, later lines to its left.
		rt.position = Vector2(500.0 - float(side[0]), _ph * 0.02)
		clip.add_child(rt)
		_type_rts.append(rt)
	if animate:
		_typeset_in(0.0)


## Types her line down the poster (both halves at once).
func _typeset_in(delay: float) -> void:
	if not Kit.motion_ok():
		return
	for rt in _type_rts:
		rt.visible_ratio = 0.0
		var tw := rt.create_tween()
		tw.tween_property(rt, "visible_ratio", 1.0, 0.6).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fit_size(text: String, length: float, depth: float) -> int:
	var f := Kit.font("compressed")
	for fs in range(124, 70, -4):
		var lh := f.get_height(fs)
		var sz := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, length, fs)
		var n := maxi(1, roundi(sz.y / lh))
		if n * (lh - 14.0 * fs / 118.0) <= depth:
			return fs
	return 72


func _on_hero_tap() -> void:
	if _hero_id == "":
		return
	var lines := LobbyLines.lines(_hero_id)
	_line = (_line + 1) % lines.size()
	_typeset(lines[_line], true)
	_misregister()
	# Her reaction (HeroReact): burst, camera punch, expression, a pose that changes tap by tap.
	_tap_n = HeroReact.next_count(_tap_n, _t - _tap_at)
	_tap_at = _t
	_react_at(_hero_hit.position + _hero_hit.get_local_mouse_position())


func _react_at(at: Vector2) -> void:
	_cheer_left = HeroReact.react(_poster, _sprite, _anchor, at, _tap_n, _poster)
	if _tap_n >= 4:
		_tap_n = 0


## Screenshots (--shoot-do=poke / poke4): taps her `times` times at her chest.
func debug_poke(times: int) -> void:
	for i in times:
		var lines := LobbyLines.lines(_hero_id)
		_line = (_line + 1) % lines.size()
		_typeset(lines[_line], true)
		_misregister()
		_tap_n = HeroReact.next_count(_tap_n, 0.1)
		_react_at(_hero_hit.position + _hero_hit.size * Vector2(0.55, 0.35))
		await get_tree().create_timer(0.12).timeout


## Her new line prints out of register and snaps into place; the halftone band flickers.
func _misregister() -> void:
	if not Kit.motion_ok():
		return
	_type_layer.position = Vector2(10, -6)
	_type_layer.create_tween().tween_property(_type_layer, "position", Vector2.ZERO, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_print_layer.modulate.a = 0.3
	_print_layer.create_tween().tween_property(_print_layer, "modulate:a", 1.0, 0.4)


func _switch_hero(dir: int) -> void:
	var order := _hero_order()
	if order.size() < 2:
		return
	var i := order.find(_hero_id)
	var nxt := order[posmod(i + dir, order.size())]
	Game.set_setting(HERO_KEY, nxt)


func _open_hero() -> void:
	if _hero_id != "":
		UI.go("hero_detail", {"hero_id": _hero_id, "browse": _hero_order()})


## Hides the stuck-on pieces, fades her line and hides the chrome to look at the hero; any tap
## brings them back.
func _hide_ui() -> void:
	_viewing = true
	_page_anchor = _page.global_position
	_over.visible = false
	_pass_slot.visible = false
	_type_layer.create_tween().tween_property(_type_layer, "modulate:a", 0.12, 0.3)
	UI.set_chrome(false, false)
	_restore = Button.new()
	_restore.name = "ShowUI"
	_restore.theme_type_variation = &"BareButton"
	_restore.focus_mode = FOCUS_NONE
	_restore.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_restore)
	_restore.pressed.connect(func() -> void:
		_restore.queue_free()
		_restore = null
		_viewing = false
		_over.visible = true
		_pass_slot.visible = true
		_type_layer.create_tween().tween_property(_type_layer, "modulate:a", 1.0, 0.3)
		UI.set_chrome(true, true))


## The hero celebrates for a moment (claims, taps).
func _cheer() -> void:
	if _sprite and is_instance_valid(_sprite) and _sprite.has_method("play_victory"):
		_sprite.call("play_victory")
		_cheer_left = 2.6


# ------------------------------------------------------------------ bulletin

## Shows bulletin page `page` (0 summon, 1 offers, 2 chapter) in the band.
func _show_bulletin(page: int, animate: bool = true) -> void:
	_bull_page = posmod(page, 3)
	_bull_t = 0.0
	var old: Array[Node] = _bull_slot.get_children()
	var b := _make_bulletin(_bull_page)
	_bull_slot.add_child(b)
	for o in old:
		if animate and o is Control:
			var tw := (o as Control).create_tween()
			tw.tween_property(o, "modulate:a", 0.0, 0.2)
			tw.tween_callback(o.queue_free)
		else:
			o.queue_free()
	if animate and Kit.motion_ok():
		b.modulate.a = 0.0
		b.position.y = 10.0
		var tw2 := b.create_tween().set_parallel(true)
		tw2.tween_property(b, "modulate:a", 1.0, 0.25)
		tw2.tween_property(b, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _make_bulletin(page: int) -> Button:
	var title := ""
	var sub := ""
	var cb := Callable()
	var lit := false
	match page:
		0:
			var bn := Game.banner()
			title = str(bn.get("name", "Summon"))
			lit = bool(Game.free_pull_available())
			sub = "FREE PULL READY →" if lit else "SUMMON NOW →"
			cb = func() -> void: UI.go("summon")
		1:
			var offer := _featured_offer()
			title = str(offer.get("name", "Offers"))
			lit = bool(offer.get("available", false)) and str(offer.get("price_label", "")) == "Free"
			sub = "FREE GIFT →" if lit else "%s →" % str(offer.get("tag", "Offer")).to_upper()
			cb = func() -> void: UI.go("shop", {"tab": 0})
		_:
			var st := Game.current_stage()
			var chs := Game.chapters()
			var ci := clampi(int(st.get("chapter", chs.size() - 1)), 0, chs.size() - 1)
			var ch: Dictionary = chs[ci]
			title = "Ch.%02d %s" % [ci + 1, str(ch.get("name", ""))]
			var first := int(ch.get("first_stage", ci * 10))
			var count := int(ch.get("stage_count", 10))
			sub = "%d / %d CLEARED →" % [clampi(Game.cleared_count() - first, 0, count), count]
			cb = _on_campaign
	var b := Button.new()
	b.name = "Banner"
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.size = _bull_slot.size
	b.pressed.connect(func() -> void:
		Kit.sfx("tap")
		cb.call())
	# A printed slip laid over her line, so the bulletin reads over the giant type.
	var slip := Panel.new()
	slip.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("1b1c1f")
	ss.border_color = Color(PAPER, 0.28)
	ss.set_border_width_all(1)
	ss.shadow_color = Color(0, 0, 0, 0.45)
	ss.shadow_size = 8
	ss.shadow_offset = Vector2(0, 3)
	slip.add_theme_stylebox_override("panel", ss)
	slip.size = b.size
	b.add_child(slip)
	var pad := 12.0
	var kick := Kit.label("BULLETIN %02d/03" % (page + 1), 11, Color(PAPER, 0.6), "mono_bold")
	kick.mouse_filter = MOUSE_FILTER_IGNORE
	kick.position = Vector2(pad, 10)
	b.add_child(kick)
	if lit:
		var led := HUD.Led.new()
		led.size = Vector2(14, 14)
		led.position = Vector2(b.size.x - pad - 14, 11)
		led.mode = "breathe"
		b.add_child(led)
	var tw := b.size.x - pad * 2
	var text := title.to_upper()
	var fs := _fit_block(text, tw, 92.0, 40, 22, 8)
	var t := Kit.label(text, fs, PAPER, "compressed")
	t.mouse_filter = MOUSE_FILTER_IGNORE
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_constant_override("line_spacing", -8)
	t.position = Vector2(pad, 28)
	t.size = Vector2(tw, 92)
	b.add_child(t)
	var s := Kit.label(sub, 12, SIG, "mono_bold")
	s.mouse_filter = MOUSE_FILTER_IGNORE
	s.position = Vector2(pad, b.size.y - 38)
	b.add_child(s)
	# Page ticks.
	for i in 3:
		var tick := ColorRect.new()
		tick.mouse_filter = MOUSE_FILTER_IGNORE
		tick.color = Color(PAPER, 0.9 if i == page else 0.3)
		tick.position = Vector2(pad + i * 22, b.size.y - 14)
		tick.size = Vector2(16, 2)
		b.add_child(tick)
	return b


## The largest compressed size (max_fs down to min_fs) at which `text` wraps into `width` and fits
## `height` (lines drawn `tighten` px closer than the font's line height).
func _fit_block(text: String, width: float, height: float, max_fs: int, min_fs: int, tighten: float) -> int:
	var f := Kit.font("compressed")
	for fs in range(max_fs, min_fs - 1, -2):
		var lh := f.get_height(fs)
		var sz := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, fs)
		var n := maxi(1, roundi(sz.y / lh))
		if n * lh - (n - 1) * tighten <= height:
			return fs
	return min_fs


## The offer worth showing: a free gift waiting, else the first offer still available.
func _featured_offer() -> Dictionary:
	var first := {}
	for o: Dictionary in Game.offers():
		if not bool(o.get("available", false)):
			continue
		if str(o.get("price_label", "")) == "Free":
			return o
		if first.is_empty():
			first = o
	return first if not first.is_empty() else {"name": "Shop", "tag": "Offers", "available": false}


# ------------------------------------------------------------------ campaign pass

func _refresh_campaign() -> void:
	var st := Game.current_stage()
	var team := int(Game.team_power())
	var rec := int(st.get("recommended_power", 0))
	var ready := not st.is_empty() and team >= rec
	var sig := "%s|%d|%d" % [str(st.get("id", "")), rec, team]
	if sig == _pass_sig:
		return
	_pass_sig = sig
	for c in _pass_slot.get_children():
		c.queue_free()
	var spec := {"width": 400.0, "icon": "flag", "action": "ENGAGE  >>>"}
	if st.is_empty():
		spec.merge({"kicker": "CAMPAIGN // COMPLETE", "title": "ALL CLEAR", "sub": "EVERY STAGE CLEARED", "action": "VIEW MAP  >>>"}, true)
	else:
		var chs := Game.chapters()
		var ci := clampi(int(st.get("chapter", 0)), 0, maxi(chs.size() - 1, 0))
		var kick := "CAMPAIGN // NEXT"
		if bool(st.get("is_boss", false)):
			kick += " · BOSS"
		var sub := "CH.%02d %s" % [ci + 1, str(st.get("name", "")).to_upper()]
		if sub.length() > 34:
			sub = sub.substr(0, 33) + "…"
		spec.merge({"kicker": kick, "title": "STAGE %s" % str(st.get("id", "")), "sub": sub,
			"info": "REC %s · YOU %s" % [Kit.format_full(rec), Kit.format_full(team)]}, true)
	_pass_root = SignalKit.pass_button(spec, _on_campaign)
	_pass_root.name = "Campaign"
	_pass_slot.add_child(_pass_root)
	_pass_led = HUD.Led.new()
	_pass_led.size = Vector2(22, 22)
	_pass_led.position = Vector2(386, -9)
	_pass_led.mode = "breathe"
	_pass_led.visible = ready
	_pass_slot.add_child(_pass_led)
	_pass_led.z_index = 2
	SignalKit.relight(self)


func _on_campaign() -> void:
	var st := Game.current_stage()
	if st.is_empty():
		UI.go("campaign")
		return
	UI.go("campaign", {"open_stage": int(st.index)})


# ------------------------------------------------------------------ sanctum (idle rewards)

func _refresh_idle() -> void:
	var st: Dictionary = Game.idle_status()
	var elapsed := int(st.get("elapsed_ms", 0))
	var cap := maxi(int(st.get("cap_ms", 1)), 1)
	var was_full := _full
	_full = bool(st.get("full", false))
	if was_full and not _full and _stamp_btn:
		_stamp_btn.scale = Vector2.ONE
	# The Sanctum grows with the campaign: its level is the number of stages cleared.
	var lv := maxi(1, Game.cleared_count())
	var tail := "FULL · CLAIM" if _full else "FULL IN %s" % Kit.format_time(cap - elapsed).to_upper()
	var label := "SANCTUM · LV %d · %s · " % [lv, tail]
	var value := "%d%%" % int(100.0 * elapsed / cap)
	if _stamp_ink and (str(_stamp_ink.get("label")) != label or str(_stamp_ink.get("value")) != value):
		_stamp_ink.set("label", label)
		_stamp_ink.set("value", value)
		_stamp_ink.set("ink", Color(SIG, 0.95) if _full else Color(0.1, 0.11, 0.12, 0.85))
		_stamp_ink.queue_redraw()
	_refresh_sheet(st)


## The Sanctum sheet (style v4 print: a printed instrument sheet). The fill dial (ticks filling in
## signal, the % in the middle, the level under it) beside a mono table of the yield per hour and
## the fill time; the pending rewards as a printed receipt under an ink band; a line in the serif;
## then Quick Claim (a printed outline, named "QuickClaim") and the Claim pass ("Claim").
func _open_sanctum() -> void:
	if _sheet and is_instance_valid(_sheet):
		return
	var st: Dictionary = Game.idle_status()
	var col := Kit.vbox(12)
	col.custom_minimum_size.x = 580
	var head := Kit.hbox(26)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var dial := Kit.fill_dial(204.0, "Sanctum fill", "LV %d" % maxi(1, Game.cleared_count()))
	dial.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(dial)
	var right := Kit.vbox(2)
	right.mouse_filter = MOUSE_FILTER_IGNORE
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(Kit.print_label("Idle yield  ·  per hour", 12, Color(Kit.TEXT, 0.6)))
	var per_hour: Dictionary = st.get("per_hour", {})
	for c: String in ["gold", "hero_exp", "gems", "dust"]:
		var n := int(per_hour.get(c, 0))
		if n <= 0:
			continue
		var r := Kit.hbox(10)
		r.mouse_filter = MOUSE_FILTER_IGNORE
		r.custom_minimum_size.y = 33
		var ic := Kit.currency_icon(c, 26)
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		r.add_child(ic)
		var nm := Kit.print_label(str(Kit.CURRENCY_SHORT.get(c, c)), 13)
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		r.add_child(nm)
		r.add_child(Kit.label("+%s" % Kit.format_full(n), 30, Kit.TEXT, "compressed"))
		right.add_child(r)
		var hr := ColorRect.new()
		hr.color = Color(Kit.TEXT, 0.16)
		hr.mouse_filter = MOUSE_FILTER_IGNORE
		hr.custom_minimum_size.y = 1
		right.add_child(hr)
	right.add_child(Kit.spacer(0, 6))
	right.add_child(Kit.print_label("Fill time", 12, Color(Kit.TEXT, 0.6)))
	var time_l := Kit.label("", 22, Kit.TEXT, "mono_bold")
	right.add_child(time_l)
	head.add_child(right)
	col.add_child(head)
	col.add_child(Kit.header_bar("Ready to collect", null, "chest"))
	var pending := Kit.vbox(0)
	pending.custom_minimum_size.y = 120
	pending.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(pending)
	var hint := Kit.label("The Sanctum fills for %s while you are away. Clearing stages raises its rate." % Kit.format_time(int(st.get("cap_ms", 0))),
		22, Color(Kit.TEXT, 0.72), "serif_italic")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 580
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var quick_slot := Kit.hbox(0)
	col.add_child(quick_slot)
	var claim_slot := Kit.hbox(0)
	col.add_child(claim_slot)
	_sheet_refs = {"pct": dial.get_meta("value_label"), "time": time_l, "bar": dial, "pending": pending, "quick_slot": quick_slot,
		"claim_slot": claim_slot, "pending_sig": "-", "quick_sig": "-"}
	_sheet = UI.popup("Sanctum", col, func() -> void:
		_sheet = null
		_sheet_refs = {}, 640.0, true)
	_refresh_sheet(st)
	_refresh_guide()


func _close_sheet() -> void:
	if _sheet and is_instance_valid(_sheet):
		UI.close_modal(_sheet)
	_sheet = null
	_sheet_refs = {}


func _refresh_sheet(st: Dictionary) -> void:
	if _sheet_refs.is_empty() or _sheet == null or not is_instance_valid(_sheet):
		return
	var elapsed := int(st.get("elapsed_ms", 0))
	var cap := maxi(int(st.get("cap_ms", 1)), 1)
	var full := bool(st.get("full", false))
	var pct := int(100.0 * elapsed / cap)
	(_sheet_refs.pct as Label).text = "%d%%" % pct
	(_sheet_refs.time as Label).text = ("FULL  ·  %s" % Kit.format_time(cap)) if full else "%s / %s" % [Kit.format_time(elapsed), Kit.format_time(cap)]
	Kit.set_dial(_sheet_refs.bar as Control, float(elapsed) / cap)
	var pending: Dictionary = st.get("pending", {})
	var sig := JSON.stringify(pending)
	if sig != str(_sheet_refs.pending_sig):
		_sheet_refs.pending_sig = sig
		var box := _sheet_refs.pending as VBoxContainer
		for c in box.get_children():
			c.queue_free()
		var n := Kit.reward_entries(pending).size()
		if n > 0:
			var receipt := Kit.reward_receipt(pending, 580.0, {"compact": true})
			if n > 4:
				var sc := Kit.scroll(receipt)
				sc.custom_minimum_size = Vector2(580, 4 * 41.0)
				box.add_child(sc)
			else:
				box.add_child(receipt)
		else:
			box.add_child(Kit.empty_state("Your heroes are gathering rewards...", "sanctum", true))
		# Claim: an ink stamp (the button family's claim), inked signal when there is something to
		# collect, a faint grey impression at rest.
		var cs := _sheet_refs.claim_slot as HBoxContainer
		for c in cs.get_children():
			c.queue_free()
		var claim := SignalKit.stamp_button({"width": 580.0, "height": 120.0, "word": "CLAIM REWARDS" if n > 0 else "FILLING",
			"kicker": "SANCTUM  //  COLLECT", "disabled": n == 0, "button_text": "Claim"}, _claim)
		claim.name = "Claim"
		cs.add_child(claim)
		_sheet_refs["claim"] = claim
	var cl: Variant = _sheet_refs.get("claim", null)
	if cl is Button and is_instance_valid(cl):
		var n2 := Kit.reward_entries(pending).size()
		((cl as Button).get_meta("sub_label") as Label).text = ("%d ITEMS WAITING  ·  %d%% FULL" % [n2, pct]) if n2 > 0 else "NOTHING YET  ·  %d%% FULL" % pct
	var cost := int(st.get("quick_claim_cost", -1))
	var left := int(st.get("quick_claims_left", 0))
	var qsig := "%d/%d" % [cost, left]
	if qsig != str(_sheet_refs.quick_sig):
		_sheet_refs.quick_sig = qsig
		var slot := _sheet_refs.quick_slot as HBoxContainer
		for c in slot.get_children():
			c.queue_free()
		var q := _make_quick_button(cost, left, int(st.get("quick_claim_ms", 7200000)))
		slot.add_child(q)
		_sheet_refs["quick"] = q
		Guide.mark(q, Guide.step() == "claim", 0)


## Quick Claim as a printed outline button: the name in heavy condensed type over a mono line (free,
## the gem price with its icon, or none left today; the price in signal when the player is short).
func _make_quick_button(cost: int, left: int, ms: int) -> Button:
	var hours := "%dH" % (ms / 3600000)
	var b := Kit.light_button("", _quick_claim if cost >= 0 and left > 0 else Callable())
	if cost < 0 or left <= 0:
		b.disabled = true
		_two_line(b, "Quick Claim", "NONE LEFT TODAY  ·  BACK TOMORROW", Color(Kit.TEXT, 0.4), Color(Kit.TEXT, 0.4))
	elif cost == 0:
		_two_line(b, "Quick Claim", "FREE  ·  %s OF REWARDS NOW  ·  %d LEFT" % [hours, left], Kit.TEXT, Kit.ACCENT_DEEP)
	else:
		var short := Kit.have("gems") < cost
		_two_line(b, "Quick Claim %s" % hours.to_lower(), "%s GEMS  ·  %s OF REWARDS NOW  ·  %d LEFT" % [Kit.format_full(cost), hours, left],
			Kit.TEXT, Kit.ACCENT_DEEP if short else Color(Kit.TEXT, 0.75), "gems")
	b.name = "QuickClaim"
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(580, 92)
	return b


## Two printed lines inside a button: line1 in heavy condensed type, line2 in mono (an optional
## currency glyph in front of it).
func _two_line(b: Button, line1: String, line2: String, c1: Color, c2: Color, icon_name: String = "") -> void:
	var v := Kit.vbox(2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := Kit.label(line1, 32, c1, "cond_black")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var row := Kit.hbox(8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if icon_name != "":
		var ic := Kit.currency_icon(icon_name, 22)
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(ic)
	var s := Kit.label(line2, 14, c2, "mono_bold")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(s)
	v.add_child(row)
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_bottom = -4
	b.add_child(v)


func _claim() -> void:
	var st: Dictionary = Game.idle_status()
	var pending: Dictionary = st.get("pending", {})
	var has_any := false
	for k: String in pending:
		if int(pending[k]) > 0:
			has_any = true
	if not has_any:
		UI.toast("Nothing to collect yet. The Sanctum fills every minute.")
		return
	_close_sheet()
	var reward: Dictionary = Game.claim_idle()
	UI.show_reward("Sanctum Rewards", reward)
	_cheer()


func _quick_claim() -> void:
	var st: Dictionary = Game.idle_status()
	var cost := int(st.get("quick_claim_cost", -1))
	var hours := int(st.get("quick_claim_ms", 7200000)) / 3600000
	if cost < 0:
		UI.toast("No quick claims left today", "bad")
		return
	if cost > Game.currency("gems"):
		UI.toast("Not enough gems", "bad")
		return
	var run := func() -> void:
		_close_sheet()
		var res: Dictionary = Game.quick_claim()
		if not bool(res.get("ok", false)):
			UI.toast(str(res.get("error", "Quick claim failed")), "bad")
			return
		UI.show_reward("Quick Claim: %dh" % hours, res.get("value", {}))
		_cheer()
	if cost == 0:
		run.call()
	else:
		UI.confirm("Spend %s gems to collect %d hours of Sanctum rewards now?" % [Kit.format_full(cost), hours], run, Callable(), "Spend %s" % Kit.format_full(cost))

# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	_t += delta
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh_idle()
	if _over and _over.visible:
		_bull_t += delta
		if _bull_t >= BANNER_SECS:
			_show_bulletin(_bull_page + 1)
	if _cheer_left > 0.0:
		_cheer_left -= delta
		if _cheer_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	# A full Sanctum's stamp breathes.
	if _stamp_btn and _full and Kit.motion_ok():
		var k := 1.0 + 0.035 * (0.5 + 0.5 * sin(_t * 3.2))
		_stamp_btn.scale = Vector2(k, k)
