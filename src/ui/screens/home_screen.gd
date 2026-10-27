extends Control
## Screen "home": the Lobby as a printed poster (style v4, docs/dev/ui-style-v4.md section 0; the
## approved mockup is lobby_v5). Between the shell's paper masthead and footer strip, a poster is
## mounted on a paper matte:
## - a dark band with the lobby hero as a red halftone print, the bulletin (summon banner, offers,
##   chapter; turns every 5 s) and her number with < > to switch the lobby hero ("lobby_hero");
## - her lobby line set huge in compressed type, turned on its side and cut by the poster edge, the
##   last word in signal (tap her for another line, she cheers);
## - the hero in full colour, boxed by the right-hand rule, where small vertical labels are the
##   side menu (Daily, Offers, Spire, Rival, Shop, View) with status lights; Heroes and Team live
##   only in the bottom nav (owner, 2026-10-20: "no need to have them twice");
## - stuck on: the Sanctum stamp on a machined disc (idle rewards: fill, level, time; tap for the
##   claim sheet), a paper label with the next objective, and the Campaign pass (next stage,
##   recommended power). (The rendered coil is gone: owner, 2026-10-20, "useless".)
## Under the poster: the date and her signature (tap: her hero page). View hides the stuck-on
## pieces and the chrome. Refreshes on Game.changed and once a second.
## Physical (PhysicalKit, the owner's references 23 / 24): the poster is real paper (grain lit by the
## tilting light, her line pressed into it), a growth by her faction crawls over two corners (chrome
## thorns with blue crystal: Celestial; jelly and moss: Infernal; black thorns with red jelly:
## Fallen), clear of her face and of every touch target (the second one comes out from under the
## pass); the menu's status lights are real LEDs; the bulletin's index is a clear frosted acrylic tab
## clipped over the band's edge (tap it: the next bulletin).

const DeviceTier := preload("res://src/art/device_tier.gd")
const DayStamp := preload("res://src/ui/components/day_stamp.gd")
const Garland := preload("res://src/ui/components/garland.gd")
const Heartbeat := preload("res://src/ui/components/heartbeat.gd")
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
const BAND_C := Kit.BAND
## Rendered collage object (tools/blender/ui_objects.py): the object sits at PAD px inside the PNG
## (the rest is its baked paper shadow), OBJ px across.
const DISC_TEX := "res://assets/art/ui/objects/disc.png"
const DISC_PAD := 23.0
const DISC_OBJ := 300.0
const STAMP := 140.0
## The side menu. Heroes and Team are only in the bottom nav (her hero page: tap her signature).
## (DAILY left the side menu 2026-10-23: the top bar's quests button opens the same screen, and the
## labels needed the room to grow.)
const MENU := [["front", "FRONT"], ["district", "DISTRICT"], ["spire", "SPIRE"], ["rival", "RIVAL"], ["bag", "BAG"],
	["view", "VIEW"]]
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

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
## Debug shots: a forced hero and look ("base" = no skin).
var _force_hero := ""
var _force_skin := ""
var _tap_at := -10.0

var _built := Vector2.ZERO
var _pw := 0.0
var _ph := 0.0
var _page: Control
var _poster: Control
var _print_layer: Control
var _type_layer: Control
var _type_rts: Array[RichTextLabel] = []
var _hero_box: Control
var _hero_hit: Button
var _over: Control
var _bull_slot: Control
var _bull_tab: Button
var _bull_tab_text: Label
var _growth_layer: Control
var _growth_for := "-"
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
var _day_layer: Control        ## the calendar's stamps and line beside the date (_refresh_days)
var _day_sig := "-"
var _day_key := ""             ## the day still waiting to be stamped ("" when none)
var _visit_seen := -1         ## Game.visit_n when her line was last set (a new visit speaks again)
var _press_key := ""           ## the day being stamped right now: its stamp comes down (_stamp_day)
var _built_day := -1           ## the day the poster was printed for: a new day reprints it
var _decor_layer: Control      ## a holiday's cut-paper decorations hang here (_refresh_decor)
var _decor_for := "-"
var _age_override := -1        ## debug: the poster's age in days (shot param "age")
## debug: a layout take to pitch to the owner (shot param "take"): "quiet" leaves out the bulletin
## card and its tab, the hero arrows and counter, and the NEXT label.
var _take := ""
var _quiet_stamp := false      ## debug: the calendar stamp without its receipt (motion captures)
## The heartbeat (hold a thumb on her): how long the press has lasted (-1: none), where it landed,
## the monitor strip once it starts, and whether the release was a hold (not a tap).
var _press_t := -1.0
var _press_at := Vector2.ZERO
var _pulse: Control
var _press_was_hold := false
var _pulses := 0
var _sheet: Control
var _sheet_refs: Dictionary = {}
var _t := 0.0
var _tick := 0.0
## Rue's graffiti over the poster while she holds the last win (tag_you), else null.
var _rue_tag: Control


## params: sheet (bool) opens the Sanctum sheet, bulletin (page) shows that bulletin, stamp (true, or a
## delay in seconds) stamps today's waiting real day (screenshots);
## debug builds: hero / skin show a
## given hero and look (framing checks).
func setup(params: Dictionary) -> void:
	if OS.is_debug_build():
		_force_hero = str(params.get("hero", ""))
		_force_skin = str(params.get("skin", ""))
		_age_override = int(params.get("age", -1))
		_take = str(params.get("take", ""))
	_build()
	Game.changed.connect(_refresh)
	resized.connect(_on_resized)
	_refresh()
	if _take == "quiet":
		_quiet_take.call_deferred()
	if bool(params.get("sheet", false)):
		_open_sanctum.call_deferred()
	if params.has("bulletin"):
		_show_bulletin.call_deferred(int(params.bulletin), false)
	var sp: Variant = params.get("stamp", false)
	if (sp is bool and sp) or sp is float or sp is int:
		# true: now; a number: after that many seconds (motion captures).
		var delay := 0.0 if sp is bool else float(sp)
		_quiet_stamp = OS.is_debug_build() and bool(params.get("no_receipt", false))
		get_tree().create_timer(maxf(delay, 0.0)).timeout.connect(_stamp_day)
	if OS.is_debug_build() and params.has("pulse"):
		debug_pulse.call_deferred(float(params.pulse))


## The "quiet" take (debug shots, a pitch): the poster without the bulletin card and its tab, the hero
## arrows and counter, or the NEXT label: her line, her, the side labels, the stamp and the pass.
func _quiet_take() -> void:
	for c: Variant in [_bull_slot, _bull_tab, _prev_btn, _next_btn, _index_label, _total_label, _tape]:
		if c is CanvasItem and is_instance_valid(c):
			(c as CanvasItem).visible = false
	var idx := _over.find_child("IndexNo", true, false) if _over else null
	if idx is CanvasItem:
		(idx as CanvasItem).visible = false


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
	Kit.offset_in(_bull_tab, Vector2(-30, 0), 0.16, 0.45)
	# The growths grow out of their corners on their own (PhysicalKit.come_alive).
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
	# Real paper: the relief overlay goes in by hand below (under her, over her line).
	_poster = PhysicalKit.sheet(_page, pr, PAPER, 0.28, {"manual_relief": true})

	var band := ColorRect.new()
	band.color = BAND_C
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.size = Vector2(BAND, _ph)
	_poster.add_child(band)
	_print_layer = _layer(_poster, "Print")
	# (The maker's mark "HH" gave its corner to the growth; the rights line below still carries it.)
	var rights := Kit.label("©2026 HH, ALL RIGHTS RESERVED.", 11, Color(PAPER, 0.8), "mono_bold")
	rights.rotation = PI * 0.5
	# Below the bulletin's acrylic tab (52-248), which used to cut its first letters.
	rights.position = Vector2(46, 262)
	_poster.add_child(rights)

	# The paper's grain re-lights the print under it (her line sits on top: it is pressed in). The
	# poster ages with the account: folds, sun and pin holes over months (paper_relief.gdshader).
	var rel := PhysicalKit.relief(_poster)
	if rel and rel.material is ShaderMaterial:
		(rel.material as ShaderMaterial).set_shader_parameter("age_days", float(_poster_age()))

	_type_layer = _layer(_poster, "Type")
	# The hero, full colour, in front of her line, boxed by the right-hand rule.
	_hero_box = Control.new()
	_hero_box.name = "HeroBox"
	_hero_box.clip_contents = true
	_hero_box.mouse_filter = MOUSE_FILTER_IGNORE
	_hero_box.size = Vector2(_pw - 49, _ph)
	_poster.add_child(_hero_box)
	# A holiday's paper decorations on their thread: in front of the paper (out of its relief pass,
	# which would print them flat), behind her (_refresh_decor).
	_decor_layer = _layer(_hero_box, "Decor")
	_decor_for = "-"
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
	_hero_hit.button_down.connect(_on_hero_down)
	_hero_hit.button_up.connect(_on_hero_up)
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

	# ---- Growths crawling over two of the poster's corners (by her faction; _refresh_hero).
	_growth_layer = Control.new()
	_growth_layer.name = "Growth"
	_growth_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_growth_layer.position = pr.position
	_growth_layer.size = pr.size
	_page.add_child(_growth_layer)
	_growth_for = "-"

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
	_build_bulletin_tab()
	_build_index()
	_build_menu()
	_build_tape()
	_build_stamp()
	_build_team()

	# The Campaign pass, over the poster's bottom edge.
	_pass_slot = Control.new()
	_pass_slot.name = "PassSlot"
	_pass_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_pass_slot.position = Vector2(pr.position.x + _pw - 412, pr.end.y - 176)
	_pass_slot.size = Vector2(400, 176)
	_pass_slot.rotation = -0.035
	_page.add_child(_pass_slot)
	_pass_sig = "-"

	# ---- Under the poster: the date and her signature. On a real day (the calendar) the date is
	# where it is stamped: tap it.
	_built_day = Game.today()
	var d := CalendarRules.civil(_built_day)
	var date := Kit.label("%d %02d/%02d" % [d[0], d[1], d[2]], 26, INK, "regular")
	date.position = Vector2(20, pr.end.y + 22)
	_page.add_child(date)
	_day_layer = Control.new()
	_day_layer.name = "Days"
	_day_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_day_layer.position = Vector2(0, pr.end.y)
	_day_layer.size = Vector2(380, 88)
	_page.add_child(_day_layer)
	_day_sig = "-"
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
	no.name = "IndexNo"
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


## The bulletin's index: a clear frosted acrylic tab clipped over the band's left edge beside the
## bulletin, "BULLETIN" and the page printed on it in paper white; tap it for the next bulletin.
func _build_bulletin_tab() -> void:
	_bull_tab = Button.new()
	_bull_tab.name = "BulletinTab"
	_bull_tab.theme_type_variation = &"BareButton"
	_bull_tab.focus_mode = FOCUS_NONE
	_bull_tab.position = Vector2(-14, 52)
	_bull_tab.size = Vector2(88, 196)
	_bull_tab.pressed.connect(func() -> void:
		Kit.sfx("tap")
		Kit.haptic(10)
		_show_bulletin(_bull_page + 1))
	var tab := PhysicalKit.Acrylic.new("tab", 64.0)
	tab.name = "Acrylic"
	tab.position = Vector2(4, 6)
	tab.rotation = -0.025
	_bull_tab.add_child(tab)
	var word := Kit.label("BULLETIN", 10, Color(PAPER, 0.95), "mono_bold")
	word.mouse_filter = MOUSE_FILTER_IGNORE
	word.rotation = PI * 0.5
	word.position = Vector2(42, 8)
	tab.add_child(word)
	_bull_tab_text = Kit.label("%02d/%02d" % [_bull_page + 1, _bull_pages()], 11, Color(SIG, 0.98), "mono_bold")
	_bull_tab_text.mouse_filter = MOUSE_FILTER_IGNORE
	_bull_tab_text.rotation = PI * 0.5
	_bull_tab_text.position = Vector2(43, 66)
	tab.add_child(_bull_tab_text)
	_over.add_child(_bull_tab)


## The growths for her faction, over the band's two left corners: the top one clear of the bulletin
## (its acrylic tab sits on it), the bottom one under the objective label.
func _build_growth(faction: String) -> void:
	if faction == _growth_for or _growth_layer == null:
		return
	_growth_for = faction
	# The old faction's growth shrinks back into its corner as the new one grows out.
	for c in _growth_layer.get_children():
		PhysicalKit.wither(c)
	if faction == "":
		return
	# Under the stuck-on pieces (bulletin, its tab, the label): it runs beneath them, never over.
	var ppu := clampf(_pw / 9.4, 50.0, 76.0)
	var inset := ppu * 0.4
	PhysicalKit.growth(faction, "tl", _growth_layer, Vector2(inset, inset), ppu)
	PhysicalKit.growth(faction, "bl", _growth_layer, Vector2(inset * 0.6, _ph - inset), ppu)


## The side menu: vertical labels with ticks down the right-hand rule (owner, 2026-10-23: "make the
## poster navigation buttons bigger"), each a full-pitch target with a status light.
func _build_menu() -> void:
	var y0 := 52.0
	var y1 := _ph - 196.0
	# One size for every label, in the poster's compressed type: the largest at which every label,
	# each in a slot as long as it is (and never under an 88 px target), fits down the rule.
	var f := Kit.font("compressed")
	var gap := 30.0
	var fs := 40
	while fs > 18:
		var total := 0.0
		for m: Array in MENU:
			total += maxf(f.get_string_size(str(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap, 88.0)
		if total <= y1 - y0:
			break
		fs -= 1
	var y := y0
	var i := 0
	for m: Array in MENU:
		var id: String = m[0]
		var slot := maxf(f.get_string_size(str(m[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap, 88.0)
		var b := Button.new()
		b.name = "Side" + id.capitalize()
		b.theme_type_variation = &"BareButton"
		b.focus_mode = FOCUS_NONE
		b.position = Vector2(_pw - 100, y)
		b.size = Vector2(100, slot)
		y += slot
		b.pressed.connect(_on_menu.bind(id))
		var l := Kit.label(str(m[1]), fs, INK, "compressed")
		l.mouse_filter = MOUSE_FILTER_IGNORE
		l.rotation = PI * 0.5
		l.position = Vector2(94, 20)
		b.add_child(l)
		var tick := ColorRect.new()
		tick.color = INK
		tick.mouse_filter = MOUSE_FILTER_IGNORE
		tick.position = Vector2(40, 22)
		tick.size = Vector2(12, 1.5)
		b.add_child(tick)
		# The status light beside the tick, clear of the label.
		var led := PhysicalKit.Led.new("red", "breathe", 17.0)
		led.position = Vector2(16, 14)
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
		"spire":
			UI.go("tower")
		"rival":
			UI.go("rival")
		"bag":
			UI.go("bag")
		"front":
			if Game.war_unlocked():
				UI.go("front")
			else:
				UI.toast("The front opens after stage %s" % str(Game.stage(WarRules.UNLOCK_CLEARED - 1).get("id", "")), "info")
		"district":
			if not Game.war_unlocked():
				UI.toast("Your district opens with the front, after stage %s" % str(Game.stage(WarRules.UNLOCK_CLEARED - 1).get("id", "")), "info")
			elif str(Game.war().side) == "":
				UI.toast("Swear to a side on the front: your district is on that side", "info")
				UI.go("front")
			else:
				UI.go("district")
		"view":
			# The gallery: her (and everyone) full screen, every look.
			UI.go("gallery", {"hero_id": _hero_id})


## The next objective as a paper label stuck across the foot of the band.
func _build_tape() -> void:
	_tape = Button.new()
	_tape.name = "Objective"
	_tape.theme_type_variation = &"BareButton"
	_tape.focus_mode = FOCUS_NONE
	# Above the TEAM plate at the band's foot.
	_tape.position = Vector2(10, _ph - 228)
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


## TEAM (owner, 2026-10-23: a Lobby button near the battle button, "do not make it look out of
## place"): a machined silver plate like the campaign pass's, at the band's foot left of it, with the
## formation's five faces in small frames and the team's power; tap: the formation.
const TEAM_W := 252.0
const TEAM_H := 104.0
var _team_btn: Control
var _team_faces: Control
var _team_sig := "-"


func _build_team() -> void:
	var root := Control.new()
	root.name = "TeamPlate"
	root.mouse_filter = MOUSE_FILTER_IGNORE
	root.position = Vector2(12, _ph - TEAM_H - 18)
	root.size = Vector2(TEAM_W, TEAM_H)
	root.rotation = 0.03
	root.pivot_offset = root.size * 0.5
	var silver := SignalKit.plate("silver", Vector2.ZERO, root.size, {"topo": 0.5, "cuts": [12, 0, 0, 12],
		"screws": [Vector2(12, 12), Vector2(TEAM_W - 12, 12), Vector2(12, TEAM_H - 12), Vector2(TEAM_W - 12, TEAM_H - 12)]}, root)
	var kick := SignalKit.etch("TEAM  //  FORMATION", 10, "mono_bold")
	kick.position = Vector2(24, 10)
	silver.add_child(kick)
	_team_faces = Control.new()
	_team_faces.mouse_filter = MOUSE_FILTER_IGNORE
	_team_faces.position = Vector2(22, 30)
	_team_faces.size = Vector2(TEAM_W - 44, 60)
	silver.add_child(_team_faces)
	var hit := Button.new()
	hit.name = "Team"
	hit.text = "Team"
	hit.add_theme_color_override("font_color", Color.TRANSPARENT)
	hit.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	hit.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	hit.theme_type_variation = &"BareButton"
	hit.focus_mode = FOCUS_NONE
	hit.position = Vector2(-4, -4)
	hit.size = root.size + Vector2(8, 8)
	hit.button_down.connect(func() -> void:
		(silver as SignalKit.Plate).set_pressed_look(true)
		Kit.haptic(12))
	hit.button_up.connect(func() -> void: (silver as SignalKit.Plate).set_pressed_look(false))
	hit.pressed.connect(func() -> void:
		Kit.sfx("tap")
		UI.go("formation"))
	root.add_child(hit)
	_team_btn = root
	_over.add_child(root)


## The plate's faces and power, rebuilt when the formation changes.
func _refresh_team() -> void:
	if _team_faces == null or not is_instance_valid(_team_faces):
		return
	var f: Array = Game.formation()
	var sig := "%s|%d" % [str(f), int(Game.team_power())]
	if sig == _team_sig:
		return
	_team_sig = sig
	for c in _team_faces.get_children():
		c.queue_free()
	var side := 34.0
	for k in 5:
		var id := str(f[k]) if k < f.size() else ""
		var at := Vector2(k * (side + 6.0), 0)
		var frame := ColorRect.new()
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		frame.color = Color(INK, 0.85) if id != "" else Color(INK, 0.18)
		frame.position = at - Vector2(1.5, 1.5)
		frame.size = Vector2(side + 3, side + 3)
		_team_faces.add_child(frame)
		if id != "":
			var pic := HeroArt.make_portrait(id, side, Kit.hero_look(id))
			pic.mouse_filter = MOUSE_FILTER_IGNORE
			pic.position = at
			pic.size = Vector2(side, side)
			_team_faces.add_child(pic)
	var pw := SignalKit.etch("PWR %s" % Kit.format_num(int(Game.team_power())), 12, "mono_bold")
	pw.position = Vector2(0, side + 6)
	_team_faces.add_child(pw)


## The Sanctum stamp: printed ink on a rendered, machined disc.
func _build_stamp() -> void:
	_stamp_btn = Button.new()
	_stamp_btn.name = "Sanctum"
	_stamp_btn.theme_type_variation = &"BareButton"
	_stamp_btn.focus_mode = FOCUS_NONE
	# Across the band's edge, clear of the pass below it.
	_stamp_btn.position = Vector2(BAND - 74, _ph - 372)
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
	if absf(size.x - _built.x) > 1.0 or absf(size.y - _built.y) > 1.0:
		_rebuild.call_deferred()
	else:
		_page.position = Vector2.ZERO


func _rebuild() -> void:
	if absf(size.x - _built.x) <= 1.0 and absf(size.y - _built.y) <= 1.0:
		return
	for c in get_children():
		c.queue_free()
	_labels = {}
	_leds = {}
	_rue_tag = null
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
	# Back to an open Lobby (a new visit, no rebuild): what she noticed is said now, not later.
	if _hero_id != "" and Game.visit_n != _visit_seen:
		_visit_seen = Game.visit_n
		var back := _welcome_back()
		if back != "":
			_typeset(back, true)
	_refresh_idle()
	_refresh_campaign()
	_refresh_badges()
	_refresh_guide()
	_refresh_days()


## First-session guidance: the Sanctum stamp (free quick claim) and the Campaign pass; the Sanctum
## sheet marks its Quick Claim button. Filling the team is pointed at on the nav's Team tab (main.gd).
func _refresh_guide() -> void:
	var step := Guide.step()
	Guide.mark(_stamp_btn, step == "claim", 0)
	if _pass_root and is_instance_valid(_pass_root):
		Guide.mark(_pass_root, step == "battle", 0)
	if _team_btn and is_instance_valid(_team_btn):
		Guide.mark(_team_btn, step == "formation", 0)
	var q: Variant = _sheet_refs.get("quick", null)
	if q is Control and is_instance_valid(q):
		Guide.mark(q as Control, step == "claim", 0)


func _refresh_badges() -> void:
	_set_led("daily", int(Game.quests_ready_count()) > 0)
	var gift := false
	for o: Dictionary in Game.offers():
		if str(o.get("price_label", "")) == "Free" and bool(o.get("available", false)):
			gift = true
	# The district: a building opened since the last visit is waiting to rise.
	var dist_new := false
	if Game.war_unlocked() and str(Game.war().side) != "":
		var seen: Variant = Game.setting("district_seen")
		var open_n := 0
		for b: Variant in Game.district().buildings:
			if bool((b as Dictionary).open):
				open_n += 1
		dist_new = seen is Array and (seen as Array).size() < open_n
	_set_led("district", dist_new)
	_refresh_team()
	_set_led("rival", Game.rival_alert())
	var war: Dictionary = Game.war() if Game.war_unlocked() else {}
	_set_led("front", not war.is_empty() and (str(war.side) == "" or not (war.claim as Dictionary).is_empty()))
	_refresh_objective()
	_refresh_rue_tag()


func _set_led(id: String, on: bool) -> void:
	var led := _leds.get(id) as Control
	if led:
		led.visible = on


## Rue's tag while she holds the last win (a loss to her costs nothing; she only signs your poster):
## "RUE WAS HERE" in white marker up the band, a horned sticker and a pill sticker, never over the
## hero. A tap goes to her poster; beating her cleans it off.
func _refresh_rue_tag() -> void:
	var rs: Dictionary = Game.state.get("rival", {})
	var on := Game.rival_unlocked() and bool(rs.get("tag_you", false))
	if not on:
		if _rue_tag and is_instance_valid(_rue_tag):
			_rue_tag.queue_free()
		_rue_tag = null
		return
	if _rue_tag and is_instance_valid(_rue_tag):
		return
	_rue_tag = Control.new()
	_rue_tag.name = "RueTag"
	_rue_tag.mouse_filter = MOUSE_FILTER_IGNORE
	_rue_tag.size = Vector2(_pw, _ph)
	_over.add_child(_rue_tag)
	_over.move_child(_rue_tag, 0)
	var v := int(rs.get("tag_v", 3))
	var txt := "RUE WAS HERE"
	var h := 56.0
	var w := CK.Scrawl.width_for(txt, h, 8.0)
	var room := _ph - 360.0
	var k := minf(1.0, room / w)
	for layer: Array in [[Color(0.06, 0.06, 0.07, 0.6), Vector2(3, 3)], [Color("f7f6f2"), Vector2.ZERO]]:
		var sc := CK.Scrawl.new()
		sc.text = txt
		sc.color = layer[0]
		sc.stroke = 8.0
		sc.seed_v = v
		sc.size = Vector2(w, h)
		sc.scale = Vector2(k, k)
		sc.rotation = -PI * 0.5 + 0.1
		sc.position = Vector2(BAND * 0.5 - h * 0.5 * k, _ph - 150.0) + layer[1]
		_rue_tag.add_child(sc)
	var horn := CK.Sticker.new()
	horn.name = "RueSticker"
	horn.lines = ["RUE", "WAS HERE"]
	horn.fill = Color("101113")
	horn.ink = SIG
	horn.horns = true
	horn.size = Vector2(96, 96)
	horn.position = Vector2(BAND - 44, _ph * 0.3)
	horn.rotation = 0.18
	_rue_tag.add_child(horn)
	var pill := CK.Sticker.new()
	pill.name = "RuePill"
	pill.lines = ["BEAT ME TO CLEAN THIS"]
	pill.fill = SIG
	pill.ink = Color("f7f6f2")
	pill.round = false
	pill.size = Vector2(230, 42)
	pill.position = Vector2(14, _ph - 176)
	pill.rotation = -0.07
	_rue_tag.add_child(pill)
	var hit := Button.new()
	hit.name = "RueTagHit"
	hit.theme_type_variation = &"BareButton"
	hit.focus_mode = FOCUS_NONE
	hit.flat = true
	hit.position = Vector2(0, _ph * 0.3 - 10)
	hit.size = Vector2(BAND + 40, _ph * 0.7 - 190)
	hit.pressed.connect(func() -> void:
		Kit.sfx("tap")
		UI.go("rival"))
	_rue_tag.add_child(hit)
	if Kit.motion_ok():
		for c in _rue_tag.get_children():
			if c is CK.Scrawl:
				(c as CK.Scrawl).reveal = 0.0
				var sc2 := c as CK.Scrawl
				sc2.create_tween().tween_method(func(x: float) -> void:
					sc2.reveal = x
					sc2.queue_redraw(), 0.0, 1.0, 0.9).set_delay(0.3)


## The label: the guide's next step while it is active (hidden otherwise: the Campaign pass shows
## the next stage).
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
	_tape.visible = Guide.step() in ["claim", "summon", "formation", "level", "quests"]


# ------------------------------------------------------------------ the lobby hero

## The hero shown in the lobby: the player's pick if still owned, else the strongest team
## hero (heroes with painted art first).
func _pick_hero() -> String:
	if _force_hero != "":
		return _force_hero
	return lobby_hero()


## The Lobby's hero (the boot screen prints and preloads the same one).
static func lobby_hero() -> String:
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
	if _force_skin != "":
		skin = "" if _force_skin == "base" else _force_skin
	var key := HeroArt.art_key(id, skin) if id != "" else ""
	if id == _hero_id and key == _hero_key:
		return
	_hero_id = id
	_hero_key = key
	_build_growth(str(Game.hero_def(id).get("faction", "celestial")) if id != "" else "")
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
	DeviceTier.light(_sprite)
	# Framed by her body as tall as the poster (owner 2026-10-20: "take up the whole screen ... her
	# wings can be off screen"): wings, weapon, tail and cape may run past the band and the rule.
	HeroArt.fit_sprite(_sprite, _anchor, Rect2(BAND - 140.0, _ph * 0.02, _pw - (BAND - 140.0), _ph * 0.98), BAND + 250.0, true)
	var lines := LobbyLines.lines(id)
	_line = int(Time.get_unix_time_from_system() / 60.0) % lines.size()
	_visit_seen = Game.visit_n
	var back := _welcome_back()
	if back == "":
		back = _day_line(id)
	if back == "":
		back = _team_line(id)
	_typeset(back if back != "" else lines[_line], false)


## How many days the poster has been on the wall: since the account began (a shot param "age"
## overrides it in debug builds).
func _poster_age() -> int:
	if OS.is_debug_build() and _age_override >= 0:
		return _age_override
	var created := int(Game.state.get("created_at", 0))
	if created <= 0:
		return 0
	return maxi(0, (Game.now_ms() - created) / Game.DAY_MS)


# ------------------------------------------------------------------ the calendar

## Real days (CalendarRules): each day already stamped is a red rubber stamp on the date; the first
## still waiting gets a red line beside the date ("HALLOWEEN · STAMP IT"), and tapping the date
## brings the stamp down, then the gift. Rebuilt only when what it shows changes.
func _refresh_days(pressed_key: String = "") -> void:
	_refresh_decor()
	if _day_layer == null or not is_instance_valid(_day_layer):
		return
	var evs: Array = Game.calendar_today()
	var parts: Array[String] = []
	for e: Dictionary in evs:
		parts.append("%s:%s" % [str(e.key), str(e.claimed)])
	var sig := ",".join(parts)
	if sig == _day_sig:
		return
	_day_sig = sig
	# The claim's own `changed` usually lands here first: the stamp being pressed still comes down.
	if pressed_key == "":
		pressed_key = _press_key
	_press_key = ""
	for c in _day_layer.get_children():
		c.queue_free()
	_day_key = ""
	var d := CalendarRules.civil(Game.today())
	var n := 0
	var waiting: Dictionary = {}
	for e: Dictionary in evs:
		if not bool(e.claimed):
			if waiting.is_empty():
				waiting = e
			continue
		var st := DayStamp.new()
		st.name = "Stamp_" + str(e.key)
		st.setup(_day_word(e), d[1], d[2], _day_ink(e))
		st.position = Vector2(166 + n * 70, -12 - (n % 2) * 6)
		_day_layer.add_child(st)
		var rot := -0.14 + n * 0.22
		if str(e.key) == pressed_key:
			st.press(rot)
		else:
			st.pivot_offset = st.size * 0.5
			st.rotation = rot
		n += 1
	if waiting.is_empty():
		return
	_day_key = str(waiting.key)
	var x := 168.0 + n * 80.0
	var ink := _day_ink(waiting)
	var dot := Kit.dot(14, Color(ink, 1.0))
	dot.position = Vector2(x, 34)
	_day_layer.add_child(dot)
	var cap := Kit.label("%s  ·  STAMP IT" % _day_word(waiting), 12, Color(ink, 1.0), "mono_bold")
	cap.mouse_filter = MOUSE_FILTER_IGNORE
	cap.position = Vector2(x + 22, 31)
	_day_layer.add_child(cap)
	var b := Button.new()
	b.name = "StampDay"
	b.text = "Stamp " + _day_key
	b.add_theme_color_override("font_color", Color.TRANSPARENT)
	b.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	b.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.size = Vector2(maxf(cap.position.x + cap.get_minimum_size().x + 12.0, 300.0), 88)
	b.pressed.connect(_stamp_day)
	_day_layer.add_child(b)


## On a holiday with decorations (CalendarRules.decor) the print shop strings them across the top of
## the poster, behind her: strung up in front of the player the first time that year (setting
## "decor_hung"), simply hanging after that. Rebuilt when the day's set changes.
func _refresh_decor() -> void:
	if _decor_layer == null or not is_instance_valid(_decor_layer):
		return
	var decor := CalendarRules.decor(Game.today())
	if decor == _decor_for:
		return
	_decor_for = decor
	for c in _decor_layer.get_children():
		c.queue_free()
	if decor == "":
		return
	var mark := "%s:%d" % [decor, CalendarRules.civil(Game.today())[0]]
	var fresh := str(Game.setting("decor_hung")) != mark
	var g := Garland.new()
	g.name = "Garland"
	g.size = _decor_layer.size
	if g.setup(decor, Vector2(BAND + 18, 12), Vector2(_pw - 66, 18), 30.0, fresh):
		_decor_layer.add_child(g)
		if fresh:
			Game.set_setting("decor_hung", mark)
	else:
		g.free()


## A day's ink: a holiday with its own (calendar.json "ink", the band's that day) stamps in it,
## pressed a shade darker the way a stamp pad prints; every other day the stamp red.
func _day_ink(e: Dictionary) -> Color:
	if str(e.get("kind", "")) == "day":
		var hx := str(CalendarRules.holiday(str(e.id)).get("ink", ""))
		if hx != "":
			return Color(hx).darkened(0.14)
	return SIG


## The word on a day's stamp: the holiday's, or the birthday heroine's name.
func _day_word(e: Dictionary) -> String:
	if str(e.kind) == "player":
		return CalendarRules.stamp(e)
	if str(e.kind) == "birthday":
		return "%s'S BIRTHDAY" % str(Game.hero_def(str(e.id)).get("name", e.id)).to_upper()
	return CalendarRules.stamp(e)


func _stamp_day() -> void:
	var key := _day_key
	if key == "":
		return
	_press_key = key
	var r: Dictionary = Game.claim_calendar(key)
	if not bool(r.get("ok", false)):
		_press_key = ""
		UI.toast(str(r.get("error", "")), "bad")
		return
	Kit.haptic(28, 0.9)
	Kit.sfx("stamp")
	_refresh_days()
	var e: Dictionary = r.value.event
	var title := str(CalendarRules.holiday(str(e.id)).get("name", "A gift"))
	if str(e.kind) == "birthday":
		title = "%s's birthday" % str(Game.hero_def(str(e.id)).get("name", e.id))
	elif str(e.kind) == "player":
		title = "Happy birthday" 
	var reward: Dictionary = r.value.reward
	if _quiet_stamp:
		return
	# The gift's receipt prints in the day's ink; a day with decorations tapes its first piece on.
	var opts := {}
	if str(e.kind) == "day" and str(CalendarRules.holiday(str(e.id)).get("ink", "")) != "":
		opts["ink"] = _day_ink(e)
	var dec := str(CalendarRules.holiday(str(e.id)).get("decor", "")) if str(e.kind) == "day" else ""
	if dec != "" and Garland.SETS.has(dec):
		opts["sticker"] = Garland.DIR + str((Garland.SETS[dec] as Array)[0][0]) + ".png"
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		UI.show_reward(title, reward, Callable(), opts))


## Now and then (one minute in four) she says where she stands in the team: leading it or left out.
func _team_line(id: String) -> String:
	if int(Time.get_unix_time_from_system() / 60.0) % 4 != 0 or not Game.owns(id):
		return ""
	var f: Variant = Game.formation()
	if not (f is Array) or (f as Array).is_empty():
		return ""
	var fac := str(Game.hero_def(id).get("faction", ""))
	if str((f as Array)[0]) == id:
		return LobbyLines.team("lead", fac)
	if not (f as Array).has(id):
		return LobbyLines.team("benched", fac)
	return ""


## Her line on a real day: the player's birthday first, then her own, else the first of today's.
func _day_line(id: String) -> String:
	var evs: Array = Game.calendar_today()
	if evs.is_empty():
		return ""
	var ev: Dictionary = evs[0]
	if str(ev.kind) != "player":
		for e: Dictionary in evs:
			if str(e.kind) == "birthday" and str(e.id) == id:
				ev = e
	var def := Game.hero_def(id)
	var who := str(Game.state.get("player_name", "")) if str(ev.kind) == "player" else str(Game.hero_def(str(ev.id)).get("name", ev.id))
	return CalendarRules.line(ev, id, str(def.get("faction", "")), who)


## Days since the intake form when she remembers it, once each, and what she says.
const MILESTONES := {
	7: "A week since you signed. I still have the form.",
	30: "A month today. I had your signature framed.",
	100: "One hundred days. Most of them answer once and never come back.",
	365: "A year since you answered. I never thought you would stay.",
}


## After a long absence (8 h or more) her line notices it, once: how long, roughly, in her words. On
## the days that matter since the intake form (a week, a month, a hundred days, a year) she remembers
## that instead, once each (setting "milestone_seen"). She also notices, once each: a change of time
## zone, the small hours (01-05), an early start (05-07) and a tenth visit in a day (Game.notices).
func _welcome_back() -> String:
	var created := int(Game.state.get("created_at", 0))
	if created > 0 and Game.onboarded():
		var days := int((Time.get_unix_time_from_system() * 1000.0 - created) / 86400000.0)
		var seen := int(Game.setting("milestone_seen") if Game.setting("milestone_seen") != null else 0)
		for d: int in [365, 100, 30, 7]:
			if days >= d and days < d + 3 and seen < d:
				Game.set_setting("milestone_seen", d)
				return str(MILESTONES[d])
	# She notices a time zone change first (it is rare), then a long absence, then the hour, then
	# a tenth visit today (Game.notices; each once).
	var tz: Variant = Game.take_notice("tz")
	if tz != null:
		return LobbyLines.notice(("tz_ahead" if int(tz) > 0 else "tz_behind") + ("_1" if absi(int(tz)) == 1 else ""), {"h": absi(int(tz))})
	var away := int(Game.get("last_away_ms"))
	if away >= 8 * 3600000 and not bool(Game.get("away_noticed")):
		Game.set("away_noticed", true)
		var h := away / 3600000
		if h >= 72:
			return "%d days. I stopped counting the hours after the second one." % (h / 24)
		if h >= 24:
			return "A whole day and then some. I kept your seat warm."
		return "%d hours. Not that I was counting." % h
	var late: Variant = Game.take_notice("late")
	if late != null:
		return LobbyLines.notice("late", {"hour": int(late)})
	if Game.take_notice("early") != null:
		return LobbyLines.notice("early")
	if Game.take_notice("visits") != null:
		return LobbyLines.notice("visits")
	return ""


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
	# On a holiday with its own ink (data/calendar.json) the print shop runs that ink instead.
	var hol := CalendarRules.ink(Game.today())
	var ink := Color(hol) if hol != "" else Color(1.0, 0.36, 0.16)
	ht.material = SignalKit.halftone_material(7.0, Color(ink, 0.95))
	_print_layer.add_child(ht)
	var echo_tex := echo_texture(key, tex)
	if echo_tex:
		var echo := TextureRect.new()
		echo.texture = echo_tex
		echo.mouse_filter = MOUSE_FILTER_IGNORE
		echo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		echo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		echo.size = Vector2(640, 1280)
		echo.position = Vector2(150, _ph * 0.08)
		echo.modulate = Color(ink.r, ink.g * 0.85, ink.b * 0.75, 0.38)
		_print_layer.add_child(echo)


## Her blurred red echo: the art shrunk 20x (cached by art key; an Image resize is not free, so the
## boot screen makes the Lobby hero's while it loads).
static func echo_texture(key: String, tex: Texture2D) -> Texture2D:
	var echo_tex: Texture2D = _echo_cache.get(key)
	if echo_tex == null and tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.resize(maxi(img.get_width() / 20, 8), maxi(img.get_height() / 20, 8), Image.INTERPOLATE_BILINEAR)
			echo_tex = ImageTexture.create_from_image(img)
			_echo_cache[key] = echo_tex
	return echo_tex


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
	# Pressed into the paper (both halves in one group: the cut runs across the band's edge).
	var cut := PhysicalKit.deboss(_type_layer, clampf(fs * 0.032, 2.5, 4.5))
	for side: Array in [[0.0, BAND, PAPER], [BAND, _pw - BAND, INK]]:
		var clip := Control.new()
		clip.clip_contents = true
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		clip.position = Vector2(side[0], 0)
		clip.size = Vector2(side[1], _ph)
		cut.add_child(clip)
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
	if _press_was_hold:
		_press_was_hold = false
		return
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


# ------------------------------------------------------------------ the heartbeat

## Hold a thumb on her (0.6 s, without sliding) and the phone beats with her heart (Heartbeat): a
## printed monitor strip by the thumb, the count climbing the longer it stays, her face following
## it (a smile past 92, eyes closed past 106). A long hold (6 s or more) earns a line when it lifts.
const PULSE_AFTER := 0.6
const PULSE_SLIDE := 26.0


func _on_hero_down() -> void:
	if _hero_id == "" or _sprite == null:
		return
	_press_t = 0.0
	_press_at = _hero_hit.get_local_mouse_position()
	_press_was_hold = false


func _on_hero_up() -> void:
	_press_t = -1.0
	if _pulse == null or not is_instance_valid(_pulse):
		_pulse = null
		return
	var held: float = _pulse.call("held_seconds")
	_pulse.call("release")
	_pulse = null
	_press_was_hold = true
	var wr: WeakRef = weakref(_sprite)
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		var s: Variant = wr.get_ref()
		if s:
			(s as Node2D).call("set_expression", "eyes", "")
			(s as Node2D).call("set_expression", "mouth", ""))
	if held >= 6.0:
		var pl := LobbyLines.pulse_lines()
		_typeset(pl[(_hero_id.hash() + _pulses) % pl.size()], true)
		_misregister()
		_pulses += 1


func _tick_pulse(delta: float) -> void:
	if _press_t < 0.0:
		return
	_press_t += delta
	if _pulse == null:
		if _hero_hit.get_local_mouse_position().distance_to(_press_at) > PULSE_SLIDE:
			_press_t = -1.0
			return
		if _press_t >= PULSE_AFTER:
			_start_pulse()
		return
	if not is_instance_valid(_pulse):
		_pulse = null
		return
	_pulse.call("hold", delta)


func _start_pulse() -> void:
	var hb := Heartbeat.new()
	hb.name = "Heartbeat"
	hb.seed_value = _hero_id.hash() & 0xffff
	# Beside the thumb, at its height (above it would sit on her face): left of it, or right when
	# there is no room on the left.
	var thumb := _hero_hit.position + _press_at
	var at := thumb + Vector2(-hb.size.x - 56.0, -hb.size.y * 0.5 - 24.0)
	if at.x < 12.0:
		at.x = thumb.x + 56.0
	hb.position = at.clamp(Vector2(12, 12), _poster.size - hb.size - Vector2(12, 12))
	hb.beat.connect(_on_pulse_beat)
	_poster.add_child(hb)
	_pulse = hb
	_press_was_hold = true
	if Kit.motion_ok():
		hb.modulate.a = 0.0
		hb.create_tween().tween_property(hb, "modulate:a", 1.0, 0.25)


func _on_pulse_beat(bpm: int) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	Kit.sfx("pulse")
	if bpm >= 106:
		_sprite.call("set_expression", "eyes", "closed")
		_sprite.call("set_expression", "mouth", "smile")
	elif bpm >= 92:
		_sprite.call("set_expression", "eyes", "smile")
	# A breath of a pulse in her: the figure swells by a hair on the beat.
	if Kit.motion_ok() and _anchor and is_instance_valid(_anchor):
		if not _anchor.has_meta("react_base"):
			_anchor.set_meta("react_base", _anchor.scale)
		var base: Vector2 = _anchor.get_meta("react_base")
		_anchor.scale = base * 1.006
		_anchor.create_tween().tween_property(_anchor, "scale", base, 0.22).set_trans(Tween.TRANS_SINE)


## Screenshots: a held thumb on her chest for `seconds` (the strip, her face), still held.
func debug_pulse(seconds: float) -> void:
	_press_t = 0.0
	_press_at = _hero_hit.size * Vector2(0.55, 0.35)
	_start_pulse()
	var steps := int(seconds * 30.0)
	for i in steps:
		_pulse.call("hold", 1.0 / 30.0)


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




## The hero celebrates for a moment (claims, taps).
func _cheer() -> void:
	if _sprite and is_instance_valid(_sprite) and _sprite.has_method("play_victory"):
		_sprite.call("play_victory")
		_cheer_left = 2.6


# ------------------------------------------------------------------ bulletin

## How many bulletin pages there are: summon, offers, chapter, and the front once it is open.
func _bull_pages() -> int:
	return 4 if Game.war_unlocked() else 3


## Shows bulletin page `page` (0 summon, 1 offers, 2 chapter, 3 the front) in the band.
func _show_bulletin(page: int, animate: bool = true) -> void:
	_bull_page = posmod(page, _bull_pages())
	_bull_t = 0.0
	var old: Array[Node] = _bull_slot.get_children()
	if _bull_tab_text and is_instance_valid(_bull_tab_text):
		_bull_tab_text.text = "%02d/%02d" % [_bull_page + 1, _bull_pages()]
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


## A heroine whose birthday it is and who has looks on sale ("" when none).
func _birthday_sale_hero() -> String:
	# In 18+ mode skins are off and the shop has no wardrobe: no sale to announce.
	if HeroArt.nudity:
		return ""
	for id in HeroData.ids():
		if CalendarRules.skin_discount_bp(Game.today(), id) > 0:
			for sk: Dictionary in Game.skins_for(id):
				if bool(sk.get("installed", false)) and not bool(sk.owned):
					return id
	return ""


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
			var bday := _birthday_sale_hero()
			if bday != "":
				# Her birthday: her looks are on sale today (CalendarRules.skin_price).
				title = "%s's birthday" % str(Game.hero_def(bday).get("name", bday))
				sub = "HER LOOKS −%d%% TODAY →" % (CalendarRules.skin_discount_bp(Game.today(), bday) / 100)
				lit = true
				cb = func() -> void: UI.go("shop", {"tab": 2})
			else:
				var offer := _featured_offer()
				title = str(offer.get("name", "Offers"))
				lit = bool(offer.get("available", false)) and str(offer.get("price_label", "")) == "Free"
				sub = "FREE GIFT →" if lit else "%s →" % str(offer.get("tag", "Offer")).to_upper()
				cb = func() -> void: UI.go("shop", {"tab": 0})
		3:
			# The front: the standing, or the oath still to swear; a claim or the champion lights it.
			var war: Dictionary = Game.war()
			if str(war.side) == "":
				title = "The War for Souls"
				sub = "SWEAR TO A SIDE →"
				lit = true
			else:
				var st0: Dictionary = war.standing
				title = "Heaven %d · %d Hell" % [int(st0.heaven), int(st0.hell)]
				var ch: Dictionary = war.get("champion", {})
				lit = not (war.claim as Dictionary).is_empty()
				if lit:
					sub = "LAST WEEK'S REWARD →"
				elif not ch.is_empty() and int(ch.tries_left) > 0:
					sub = "CHAMPION %s · %d%% →" % [str(ch.name).to_upper(), int(ch.pct)]
				else:
					sub = "THE FRONT · %d SOULS TODAY →" % int(war.souls_today)
			cb = func() -> void: UI.go("front")
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
	var kick := Kit.label("BULLETIN %02d/%02d" % [page + 1, _bull_pages()], 11, Color(PAPER, 0.6), "mono_bold")
	kick.mouse_filter = MOUSE_FILTER_IGNORE
	kick.position = Vector2(pad, 10)
	b.add_child(kick)
	if lit:
		var led := PhysicalKit.Led.new("red", "breathe", 15.0)
		led.position = Vector2(b.size.x - pad - 15, 9)
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
	for i in _bull_pages():
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
	var words := text.split(" ", false)
	for fs in range(max_fs, min_fs - 1, -2):
		# No word may be wider than the block (it would break mid-word).
		var fits := true
		for w in words:
			if f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				fits = false
				break
		if not fits:
			continue
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
	_pass_led = PhysicalKit.Led.new("green", "breathe", 22.0)
	_pass_led.position = Vector2(384, -11)
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
		# Past midnight (or back from a night away) the poster is reprinted for the new day: the
		# date, a holiday's ink and decorations, her line for the day.
		if _built_day >= 0 and Game.today() != _built_day:
			_built = Vector2.ZERO
			_rebuild.call_deferred()
	if _over and _over.visible:
		_bull_t += delta
		if _bull_t >= BANNER_SECS:
			_show_bulletin(_bull_page + 1)
	if _cheer_left > 0.0:
		_cheer_left -= delta
		if _cheer_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	_tick_pulse(delta)
	# A full Sanctum's stamp breathes.
	if _stamp_btn and _full and Kit.motion_ok():
		var k := 1.0 + 0.035 * (0.5 + 0.5 * sin(_t * 3.2))
		_stamp_btn.scale = Vector2(k, k)
