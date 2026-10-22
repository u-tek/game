class_name ProfileScreen
extends Control
## Screen "profile" (style v4 "Signal", the approved poster look; docs/dev/ui-style-v4.md section
## 0): the player's ID card printed as a registry poster on the paper matte. The top-bar avatar
## opens it.
##
## The poster: a dark band down the left with the chosen portrait as a red halftone print, BACK at
## its top and the registry micro type; the player's call sign set huge down the poster in compressed
## type, paper over the band and ink where it crosses onto the paper, with a signal full stop. Top
## right, the ID block: serial, the call sign in wide black (tap: rename), the player ID (derived
## from the save's seed), the date of enlistment, the rank (account level = stages cleared) with a
## meter to the next rank. The portrait in full colour boxed by a hairline with a soft red echo (tap:
## the avatar picker) and the RANK stamp on a machined disc stuck over its corner; beside it the
## avatar's name, days in service and allegiance, and a barcode. Below, 01 SERVICE RECORD (a two
## column mono table with dotted leaders: team power, heroes, legendaries, stages, Spire best,
## summons, quests, skins, battles won, level ups) and 02 COMMENDATIONS (ten rubber stamps derived
## from the counters; unearned ones are dashed outlines; tap one for what it takes). Down the
## right-hand rule, the menu as vertical labels: AVATAR, NAME, TEAM, SETTINGS. 03 PRINT SHOWCASE: up
## to three prints the player chose in the album (Game.showcase(); misprints, data/prints.json) in
## their acrylic slabs, empty slots as crop marks; a tap opens the album (or that print's sheet).
## Under the poster, the date and the player's signature (tap: rename).
##
## Settings it owns: "avatar_hero" (a hero id the player owns; "" = the team lead, the default) and
## the call sign (Game.set_setting("player_name"), kept in state.player_name, 16 characters).
## main.gd shows ProfileScreen.avatar_hero() in the top bar when it is set.
## params: sheet "avatar" | "name" opens that sheet, scroll (px) scrolls the page (screenshots).

const Signature := preload("res://src/ui/components/signature.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const Bits := preload("res://src/ui/v4/profile/profile_bits.gd")
const PrintBits := preload("res://src/ui/components/print_bits.gd")

## Game setting: the hero whose portrait the player chose ("" = the team lead).
const AVATAR_KEY := "avatar_hero"
## Game setting: the day each commendation was first seen earned ({id: day}); its stamp carries the
## date. Missing until the first check, which dates everything already earned quietly.
const COMMEND_KEY := "commend_days"
## Game setting for the call sign (the model keeps it in state.player_name).
const NAME_KEY := "player_name"
const DEFAULT_NAME := "ENVOY"
const NAME_MAX := 16
## Poster geometry (poster px): the dark band, the right-hand rule's inset, the content column.
const BAND := 150.0
const RULE_IN := 48.0
const X0 := 212.0
const FOOT := 84.0
## The poster is never shorter than this (short windows scroll the page).
const MIN_PH := 930.0
## The print showcase under the commendations (added to the poster's height).
const SHOW_H := 290.0
## 04 THE RECORD under the showcase (added to the poster's height): up to LOG_N dated lines.
const LOG_N := 6
const LOG_H := 64.0 + LOG_N * 30.0 + 30.0
const MAX_W := 760.0
const PORTRAIT := Vector2(220, 260)
const STAMP := 74.0
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const BAND_C := Color("141517")
## Account ranks: [from level, title]. Level = stages cleared (the Sanctum's LV).
const RANKS := [[1, "INITIATE"], [5, "ACOLYTE"], [10, "WARDEN"], [20, "VANGUARD"], [30, "ARBITER"], [40, "EXARCH"],
	[50, "ASCENDANT"]]

var _params: Dictionary = {}
var _built := Vector2.ZERO
var _rebuild_queued := false
var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _pr := Rect2()
var _tw := 416.0
## Vertical layout (poster px): the portrait's top and height, the record's and the badges' tops.
var _y_portrait := 170.0
var _port_h := 260.0
var _y_record := 506.0
var _y_badges := 724.0
var _modal: Control
var _name_edit: LineEdit
# Pieces the entrance animates.
var _title_box: Control
var _portrait_box: Control
var _data_box: Control
var _rows: Array[Control] = []
var _stamps: Array[Control] = []
var _rank_disc: Control


# ------------------------------------------------------------------ helpers (static)

## The hero the player chose as their portrait, if they still own her; "" means the team lead
## (what the top bar shows by default).
static func avatar_hero() -> String:
	var g := Kit.autoload("Game")
	if g == null or not g.has_method("setting"):
		return ""
	var v: Variant = g.call("setting", AVATAR_KEY)
	if not (v is String or v is StringName):
		return ""
	var id := str(v)
	if id != "" and bool(g.call("owns", id)):
		return id
	return ""


## The team lead: the first filled formation slot, else the strongest owned hero ("" with none).
static func lead_hero() -> String:
	var g := Kit.autoload("Game")
	if g == null:
		return ""
	var f: Variant = g.call("formation")
	if f is Array:
		for id: Variant in f:
			if str(id) != "":
				return str(id)
	var owned: Variant = g.call("owned_heroes")
	if owned is Array and not (owned as Array).is_empty():
		return str(((owned as Array)[0] as Dictionary).get("id", ""))
	return ""


## The portrait the profile shows: the chosen avatar, else the team lead.
static func shown_avatar() -> String:
	var a := avatar_hero()
	return a if a != "" else lead_hero()


## The call sign as the player typed it ("Envoy" in a new save).
static func player_name_raw() -> String:
	var g := Kit.autoload("Game")
	if g:
		var v: Variant = g.call("setting", NAME_KEY) if g.has_method("setting") else null
		if v is String and str(v).strip_edges() != "":
			return str(v).strip_edges().left(NAME_MAX)
		var st: Variant = g.get("state")
		if st is Dictionary:
			var n := str((st as Dictionary).get("player_name", "")).strip_edges()
			if n != "":
				return n.left(NAME_MAX)
	return DEFAULT_NAME.capitalize()


## The call sign as printed (upper case).
static func player_name() -> String:
	return player_name_raw().to_upper()


## The player's ID, fixed for a save: "HH-0412-7731", from the save's own seed (never random).
static func player_id() -> String:
	var g := Kit.autoload("Game")
	var seed_v := 0
	if g:
		var st: Variant = g.get("state")
		if st is Dictionary:
			seed_v = int((st as Dictionary).get("rng_seed", 0))
			if seed_v == 0:
				seed_v = int((st as Dictionary).get("created_at", 0))
	# Spread the bits so nearby seeds read differently (integer math, deterministic).
	var v := absi((seed_v * 2654435761) ^ (seed_v >> 13)) % 100000000
	return "HH-%04d-%04d" % [v / 10000, v % 10000]


## Account level: stages cleared (at least 1), the same number the Sanctum prints as LV.
static func level() -> int:
	var g := Kit.autoload("Game")
	return maxi(1, int(g.call("cleared_count"))) if g else 1


## Rank index into RANKS for a level.
static func rank_index(lv: int) -> int:
	var k := 0
	for i in RANKS.size():
		if lv >= int(RANKS[i][0]):
			k = i
	return k


# ------------------------------------------------------------------ screen

func setup(params: Dictionary) -> void:
	_params = params
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	match str(params.get("sheet", "")):
		"avatar":
			_open_avatar_sheet.call_deferred()
		"name":
			_open_name_sheet.call_deferred()
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


## Entrance (UI calls it): the ID block drops in, the portrait slides on from the band, the data
## and the record rows follow, the rank stamp and the earned commendations are pressed down.
func intro() -> void:
	if not Kit.motion_ok():
		return
	Kit.offset_in(_title_box, Vector2(0, -18), 0.03, 0.45)
	Kit.offset_in(_portrait_box, Vector2(-30, 0), 0.08, 0.5)
	Kit.offset_in(_data_box, Vector2(26, 0), 0.12, 0.45)
	for i in _rows.size():
		Kit.offset_in(_rows[i], Vector2(0, 14), 0.18 + i * 0.025, 0.4)
	_press_in(_rank_disc, 0.36)
	var k := 0
	for s in _stamps:
		if bool(s.get_meta("earned", false)):
			_press_in(s, 0.5 + k * 0.06)
			k += 1


## A stamp coming down onto the paper: big and clear, then pressed flat with a little bounce.
func _press_in(c: Control, delay: float) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	var s0 := c.scale
	c.scale = s0 * 1.45
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(delay)
	tw.tween_property(c, "scale", s0, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()
	_stamps.clear()
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
	var ph := maxf(d.y - 14.0 - FOOT, MIN_PH)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + SHOW_H + LOG_H + FOOT)
	_scroll = Kit.scroll(_page)
	_scroll.name = "IdCard"
	_scroll.position = Vector2.ZERO
	_scroll.size = d
	add_child(_scroll)
	_pr = Rect2(ox + 16, 14, w - 32, ph + SHOW_H + LOG_H)
	_poster = PK.poster(_page, _pr)
	_tw = _pr.size.x - RULE_IN - 12.0 - X0
	# A taller poster (a 19.5:9 phone) gives the portrait more height first, then opens the gaps.
	var spare := ph - MIN_PH
	_port_h = PORTRAIT.y + minf(spare * 0.5, 120.0)
	var gap := (spare - (_port_h - PORTRAIT.y)) / 3.0
	_y_portrait = 170.0 + gap
	_y_record = _y_portrait + _port_h + 76.0 + gap
	_y_badges = _y_record + 218.0 + gap
	var av := shown_avatar()
	var skin := Kit.hero_look(av) if av != "" else ""
	_build_band(av, skin)
	_build_title()
	_build_portrait(av, skin)
	_build_record()
	_build_badges()
	_build_showcase()
	_build_log()
	_build_menu()
	_build_footer(ox, w)
	# BACK at the top of the band, over everything printed there.
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.06, true))
	SignalKit.relight(self)


## The dark band: the portrait as a red halftone print, the registry micro type and the call sign
## set huge down the poster (paper over the band, ink where it crosses onto the paper).
func _build_band(av: String, skin: String) -> void:
	var p := _poster
	var ph := _pr.size.y
	PK.rect(p, Rect2(0, 0, BAND, ph), BAND_C)
	if av != "":
		var ht := PK.halftone_print(av, skin, Vector2(BAND, ph * 0.58), 6.5)
		ht.name = "BandPrint"
		ht.position = Vector2(0, ph * 0.42)
		p.add_child(ht)
	Poster.vlabel(p, "©2026 HH, PLAYER REGISTRY. ALL RIGHTS RESERVED.", Vector2(26, 112), 10, Color(PAPER, 0.8))
	var nm := player_name().replace("[", "(").replace("]", ")")
	var bb := nm + "[color=#%s].[/color]" % SIG.to_html(false)
	PK.giant(p, bb, 190, Vector2(230, 112), Vector2(ph * 2.0, 250), [[Rect2(0, 0, BAND, ph), PAPER],
		[Rect2(BAND, 0, X0 - BAND - 6.0, ph), INK]], 0, "compressed", true)


## The ID block: serial, the call sign (tap to rename), the player ID and enlistment date, the rank
## and its meter.
func _build_title() -> void:
	var p := _poster
	var tw := _tw
	_title_box = Control.new()
	_title_box.name = "IdBlock"
	_title_box.mouse_filter = MOUSE_FILTER_IGNORE
	_title_box.position = Vector2(X0, 16)
	_title_box.size = Vector2(tw, 140)
	p.add_child(_title_box)
	var tb := _title_box
	var pid := player_id()
	PK.at(tb, PK.t("PLAYER REGISTRY  ·  ID CARD", 12, INK, "mono_bold"), Vector2(0, 0))
	var no := PK.t("No.%s" % pid.right(4), 12, INK, "mono_bold")
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	no.size = Vector2(tw, 16)
	PK.at(tb, no, Vector2(0, 0))
	var rule := Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG})
	PK.at(tb, rule, Vector2(0, 20))
	var nm := PK.t(player_name(), 44, INK, "wide_black")
	nm.name = "CallSign"
	Kit.fit_label(nm, tw, 44, 20)
	PK.at(tb, nm, Vector2(-2, 36))
	PK.at(tb, PK.t("ID  %s" % pid, 12, Color(INK, 0.8), "mono"), Vector2(0, 90))
	var since := PK.t("ENLISTED %s" % _created_date(), 12, Color(INK, 0.8), "mono")
	since.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	since.size = Vector2(tw, 16)
	PK.at(tb, since, Vector2(0, 90))
	# Rank: number and level in ink, the title in signal (the poster's one keyword).
	var lv := level()
	var ri := rank_index(lv)
	var rank_row := Kit.hbox(0)
	rank_row.mouse_filter = MOUSE_FILTER_IGNORE
	rank_row.add_child(PK.t("RANK %02d  ·  " % (ri + 1), 12, INK, "mono_bold"))
	rank_row.add_child(PK.t(str(RANKS[ri][1]), 12, SIG, "mono_bold"))
	rank_row.add_child(PK.t("  ·  LV %d" % lv, 12, INK, "mono_bold"))
	PK.at(tb, rank_row, Vector2(0, 110))
	var nxt := ri + 1 < RANKS.size()
	var lo := int(RANKS[ri][0])
	var hi := int(RANKS[ri + 1][0]) if nxt else lo
	var hint := PK.t(("NEXT: %s AT LV %d" % [str(RANKS[ri + 1][1]), hi]) if nxt else "HIGHEST RANK", 10, Color(INK, 0.6), "mono")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size = Vector2(tw, 14)
	PK.at(tb, hint, Vector2(0, 112))
	var frac := 1.0 if not nxt else clampf(float(lv - lo) / maxf(float(hi - lo), 1.0), 0.0, 1.0)
	var meter := Kit.tick_rule(tw, Color(INK, 0.55), {"filled": frac, "step": 8.0})
	meter.name = "RankMeter"
	PK.at(tb, meter, Vector2(0, 130))
	_hit(p, Rect2(X0 - 6, 44, tw + 12, 56), _open_name_sheet, "Rename", "Rename")


## The portrait (tap: the avatar picker) with its red echo, the RANK stamp over its corner, and
## the data column beside it: avatar, days in service, allegiance, a barcode with the ID.
func _build_portrait(av: String, skin: String) -> void:
	var p := _poster
	var y0 := _y_portrait
	var ps := Vector2(PORTRAIT.x, _port_h)
	_portrait_box = Control.new()
	_portrait_box.name = "Portrait"
	_portrait_box.mouse_filter = MOUSE_FILTER_IGNORE
	_portrait_box.position = Vector2(X0, y0)
	_portrait_box.size = ps
	p.add_child(_portrait_box)
	var box := _portrait_box
	var crop: Texture2D = Kit.art_crop(av, ps.x / ps.y, 1.0, skin) if av != "" else null
	if crop:
		# A soft red echo printed a little off register behind her.
		var echo := TextureRect.new()
		echo.name = "Echo"
		echo.mouse_filter = MOUSE_FILTER_IGNORE
		echo.texture = crop
		echo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		echo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		echo.position = Vector2(14, -12)
		echo.size = ps
		var m := ShaderMaterial.new()
		m.shader = PK.ECHO
		m.set_shader_parameter("tint", Color(1.0, 0.3, 0.12, 0.42))
		m.set_shader_parameter("lod", 3.5)
		echo.material = m
		box.add_child(echo)
	PK.rect(box, Rect2(Vector2.ZERO, ps), PAPER)
	PK.rect(box, Rect2(Vector2(4, 4), ps - Vector2(8, 8)), Color(INK, 0.07))
	if crop:
		var tr := TextureRect.new()
		tr.name = "Art"
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = crop
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.position = Vector2(4, 4)
		tr.size = ps - Vector2(8, 8)
		box.add_child(tr)
	var fr := PK.Frame.new()
	fr.size = ps
	box.add_child(fr)
	# A paper label stuck across the foot of the portrait: what a tap does.
	var tag := PanelContainer.new()
	tag.mouse_filter = MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = PAPER
	ts.shadow_color = Color(0, 0, 0, 0.3)
	ts.shadow_size = 5
	ts.shadow_offset = Vector2(0, 2)
	ts.content_margin_left = 9
	ts.content_margin_right = 9
	ts.content_margin_top = 3
	ts.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", ts)
	tag.add_child(PK.t("PORTRAIT  ›  CHANGE", 11, INK, "mono_bold"))
	tag.position = Vector2(-12, ps.y - 34)
	tag.rotation = -0.035
	box.add_child(tag)
	_hit(p, Rect2(X0, y0, ps.x, ps.y), _open_avatar_sheet, "ChangeAvatar", "Avatar")

	# The data column.
	var dx := X0 + PORTRAIT.x + 18.0
	var dw := _pr.size.x - RULE_IN - 12.0 - dx
	_data_box = Control.new()
	_data_box.name = "Data"
	_data_box.mouse_filter = MOUSE_FILTER_IGNORE
	_data_box.position = Vector2(dx, y0)
	_data_box.size = Vector2(dw, ps.y)
	p.add_child(_data_box)
	var db := _data_box
	var chosen := avatar_hero() != ""
	PK.at(db, PK.t("AVATAR", 10, Color(INK, 0.6), "mono_bold"), Vector2(0, 0))
	var an := PK.t(str(Game.hero_def(av).get("name", "NONE")).to_upper() if av != "" else "NONE", 22, INK, "wide_black")
	Kit.fit_label(an, dw, 22, 12)
	PK.at(db, an, Vector2(-1, 14))
	PK.at(db, PK.t("CHOSEN BY YOU" if chosen else "TEAM LEAD  ·  AUTO", 10, Color(INK, 0.7), "mono"), Vector2(0, 42))
	PK.rect(db, Rect2(0, 62, dw, 1), Color(INK, 0.4))
	PK.at(db, PK.t("IN SERVICE", 10, Color(INK, 0.6), "mono_bold"), Vector2(0, 70))
	var days := _days()
	PK.at(db, PK.t("%03d" % mini(days, 999), 56, INK, "compressed"), Vector2(-2, 84))
	PK.at(db, PK.t("DAY%s SINCE ENLISTING" % ("" if days == 1 else "S"), 10, Color(INK, 0.7), "mono"), Vector2(0, 150))
	PK.rect(db, Rect2(0, 168, dw, 1), Color(INK, 0.4))
	PK.at(db, PK.t("ALLEGIANCE", 10, Color(INK, 0.6), "mono_bold"), Vector2(0, 174))
	var al := _allegiance()
	var al_l := PK.t(str(al[0]), 13, INK, "mono_bold")
	al_l.clip_text = true
	al_l.size = Vector2(dw, 18)
	PK.at(db, al_l, Vector2(0, 188))
	PK.at(db, PK.t(str(al[1]), 10, Color(INK, 0.7), "mono"), Vector2(0, 206))

	# The RANK stamp on a machined disc, stuck at the foot of the data column (under the allegiance,
	# clear of the portrait and the lines above it).
	var lv := level()
	var title := str(RANKS[rank_index(lv)][1])
	var dpos := Vector2(dx + dw - 108.0, y0 + ps.y - 34.0)
	_rank_disc = SignalKit.plate("silver", dpos, Vector2(104, 104), {"circle": true, "shadow": 0.5}, p)
	_rank_disc.add_child(SignalKit.stamp("RANK · %s · LEVEL · " % title, "%02d" % lv, 104.0))
	_rank_disc.rotation = -0.12
	_rank_disc.pivot_offset = Vector2(52, 52)
	var rb := _hit(p, Rect2(dpos - Vector2(8, 8), Vector2(120, 120)), _on_rank, "Rank", "Rank")
	var disc := _rank_disc
	rb.button_down.connect(func() -> void: disc.call("set_pressed_look", true))
	rb.button_up.connect(func() -> void: disc.call("set_pressed_look", false))


## The rank stamp: what the rank is and what the next one takes.
func _on_rank() -> void:
	var lv := level()
	var ri := rank_index(lv)
	var title := str(RANKS[ri][1]).capitalize()
	if ri + 1 < RANKS.size():
		UI.toast("%s, level %d. %s at level %d: clear more stages." % [title, lv, str(RANKS[ri + 1][1]).capitalize(), int(RANKS[ri + 1][0])])
	else:
		UI.toast("%s, level %d: the highest rank." % [title, lv])


## 01 SERVICE RECORD: two columns of printed rows (mono label, dotted leader, the value in
## compressed type), a hairline under each.
func _build_record() -> void:
	var p := _poster
	var y := _y_record
	var tw := _tw
	PK.at(p, PK.t("01  SERVICE RECORD", 12, INK, "mono_bold"), Vector2(X0, y))
	var asof := PK.t("AS OF %s" % Poster.date_long(), 10, Color(INK, 0.6), "mono")
	asof.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	asof.size = Vector2(tw, 14)
	PK.at(p, asof, Vector2(X0, y + 2))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(X0, y + 20))
	var stats := _stats()
	var cw := (tw - 20.0) * 0.5
	var row_h := 34.0
	for i in stats.size():
		var col := i / 5
		var r := i % 5
		var e: Array = stats[i]
		var row := Control.new()
		row.name = "Row_%s" % str(e[0]).to_pascal_case()
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.position = Vector2(X0 + col * (cw + 20.0), y + 38.0 + r * row_h)
		row.size = Vector2(cw, row_h)
		p.add_child(row)
		var l := PK.t(str(e[0]), 11, Color(INK, 0.75), "mono_bold")
		l.position = Vector2(0, 12)
		row.add_child(l)
		var v := PK.t(str(e[1]), 26, INK, "compressed")
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.position = Vector2(cw - 72.0, 0)
		v.size = Vector2(72, 32)
		row.add_child(v)
		var lead := PrintBits.Leader.new()
		var lx := minf(l.get_minimum_size().x + 6.0, cw - 110.0)
		lead.position = Vector2(lx, 12)
		lead.size = Vector2(maxf(cw - 70.0 - lx, 4.0), 12)
		row.add_child(lead)
		PK.rect(row, Rect2(0, row_h - 1.0, cw, 1), Color(INK, 0.16))
		_rows.append(row)


## The record's rows: [label, value], first column then second.
func _stats() -> Array:
	var owned := Game.owned_heroes()
	var legend := 0
	for h: Dictionary in owned:
		if str(Game.hero_def(str(h.get("id", ""))).get("rarity", "")) == "legendary":
			legend += 1
	var st: Dictionary = Game.state
	var pulls := maxi(Game.counter("summons"), int((st.get("summon", {}) as Dictionary).get("total_pulls", 0)))
	var skins: Variant = (st.get("skins", {}) as Dictionary).get("owned", [])
	var spire := Game.tower_best()
	return [
		["TEAM POWER", Kit.format_num(int(Game.team_power()))],
		["HEROES", "%d/%d" % [owned.size(), Game.all_hero_defs().size()]],
		["LEGENDARIES", "%d" % legend],
		["STAGES CLEARED", "%d" % Game.cleared_count()],
		["SPIRE BEST", ("F%02d" % spire) if spire > 0 else "--"],
		["SUMMONS", Kit.format_num(pulls)],
		["QUESTS DONE", Kit.format_num(Game.counter("daily_quests_done"))],
		["SKINS OWNED", "%d" % ((skins as Array).size() if skins is Array else 0)],
		["BATTLES WON", Kit.format_num(Game.counter("battles_won"))],
		["LEVEL UPS", Kit.format_num(Game.counter("level_ups"))],
	]


## 02 COMMENDATIONS: ten stamps in two rows; earned ones pressed in ink (the big three in signal)
## at a slight angle, the rest as dashed outlines. Tap one for what it takes.
func _build_badges() -> void:
	var p := _poster
	var y := _y_badges
	var tw := _tw
	var list := badges()
	var days: Variant = Game.setting(COMMEND_KEY)
	var earned := 0
	for b: Dictionary in list:
		if bool(b.earned):
			earned += 1
	PK.at(p, PK.t("02  COMMENDATIONS", 12, INK, "mono_bold"), Vector2(X0, y))
	var cnt := PK.t("%02d / %02d EARNED" % [earned, list.size()], 12, SIG if earned == list.size() else INK, "mono_bold")
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.size = Vector2(tw, 16)
	PK.at(p, cnt, Vector2(X0, y))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(X0, y + 20))
	var per_row := 5
	var gap := (tw - per_row * STAMP) / float(per_row - 1)
	for i in list.size():
		var b: Dictionary = list[i]
		var cx := X0 + (i % per_row) * (STAMP + gap)
		var cy := y + 40.0 + (i / per_row) * (STAMP + 10.0)
		var holder := Control.new()
		holder.name = "Badge_%s" % str(b.id)
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.position = Vector2(cx, cy)
		holder.size = Vector2(STAMP, STAMP)
		holder.pivot_offset = holder.size * 0.5
		var on := bool(b.earned)
		holder.set_meta("earned", on)
		if on:
			holder.rotation = float(absi(hash(str(b.id))) % 21 - 10) * 0.013
		var st := Bits.Badge.new()
		var when := ""
		if on and days is Dictionary and (days as Dictionary).has(str(b.id)):
			when = _ddmmyy(int(days[str(b.id)]))
		st.ring = str(b.ring) + ("  ·  " + when if when != "" else "")
		st.value = str(b.value)
		st.earned = on
		st.ink = SIG if on and bool(b.get("big", false)) else INK
		st.size = holder.size
		holder.add_child(st)
		p.add_child(holder)
		_stamps.append(holder)
		# 88 px targets, tiled over the row.
		var hx := X0 + tw * 0.5 - per_row * 44.0 + (i % per_row) * 88.0
		var msg := ("%s: earned%s." % [str(b.ring).capitalize(), " " + when if when != "" else ""]) if on \
			else ("%s: %s." % [str(b.ring).capitalize(), str(b.how)])
		_hit(p, Rect2(hx, cy - 7.0, 88, 88), func() -> void: UI.toast(msg, "good" if on else "info"), "Commendation_%s" % str(b.id))


## A day number as DD.MM.YY.
static func _ddmmyy(day: int) -> String:
	var c := CalendarRules.civil(day)
	return "%02d.%02d.%02d" % [c[2], c[1], c[0] % 100]


## Dates the commendations earned since the last check (COMMEND_KEY) and returns them. The first
## check ever dates what is already earned and returns nothing (no burst of news on an old save).
## main.gd calls it on every change; it writes only when something is new.
static func note_commendations() -> Array[Dictionary]:
	var cur: Variant = Game.setting(COMMEND_KEY)
	var first := not (cur is Dictionary)
	var d: Dictionary = (cur as Dictionary).duplicate() if cur is Dictionary else {}
	var fresh: Array[Dictionary] = []
	for b: Dictionary in badges():
		if bool(b.earned) and not d.has(str(b.id)):
			d[str(b.id)] = Game.today()
			if not first:
				fresh.append(b)
	if first or not fresh.is_empty():
		Game.set_setting(COMMEND_KEY, d)
	return fresh


## The commendations, in rough order of difficulty: {id, ring, value, earned, how, big}.
static func badges() -> Array[Dictionary]:
	var st: Dictionary = Game.state
	var cleared := Game.cleared_count()
	var chs := Game.chapters()
	var chapter_end := func(k: int) -> int:
		if k < 0 or k >= chs.size():
			return 1 << 30
		return int(chs[k].get("first_stage", 0)) + int(chs[k].get("stage_count", 10))
	var owned := Game.owned_heroes()
	var legend := false
	for h: Dictionary in owned:
		if str(Game.hero_def(str(h.get("id", ""))).get("rarity", "")) == "legendary":
			legend = true
	var pulls := maxi(Game.counter("summons"), int((st.get("summon", {}) as Dictionary).get("total_pulls", 0)))
	var skins: Variant = (st.get("skins", {}) as Dictionary).get("owned", [])
	var n_skins := (skins as Array).size() if skins is Array else 0
	var total := Game.all_hero_defs().size()
	var out: Array[Dictionary] = [
		{"id": "first_summon", "ring": "FIRST SUMMON", "value": "01", "earned": pulls >= 1, "how": "summon a hero"},
		{"id": "chapter_1", "ring": "CHAPTER 01 CLEARED", "value": "CH1", "earned": cleared >= int(chapter_end.call(0)),
			"how": "clear every stage of chapter 1"},
		{"id": "legendary", "ring": "FIRST LEGENDARY", "value": "LGD", "earned": legend, "how": "recruit a Legendary hero", "big": true},
		{"id": "spire_10", "ring": "SPIRE FLOOR 10", "value": "F10", "earned": Game.tower_best() >= 10, "how": "reach floor 10 of the Spire"},
		{"id": "quests_10", "ring": "TEN DAILY QUESTS", "value": "Q10", "earned": Game.counter("daily_quests_done") >= 10,
			"how": "claim 10 daily quests"},
		{"id": "chapter_3", "ring": "CHAPTER 03 CLEARED", "value": "CH3", "earned": cleared >= int(chapter_end.call(2)),
			"how": "clear every stage of chapter 3"},
		{"id": "summons_100", "ring": "ONE HUNDRED SUMMONS", "value": "100", "earned": pulls >= 100, "how": "summon 100 times"},
		{"id": "wardrobe", "ring": "FIRST SKIN", "value": "S01", "earned": n_skins >= 1, "how": "add a skin to the wardrobe"},
		{"id": "full_roster", "ring": "FULL ROSTER", "value": "%d" % total, "earned": total > 0 and owned.size() >= total,
			"how": "recruit all %d heroes" % total, "big": true},
		{"id": "campaign", "ring": "CAMPAIGN COMPLETE", "value": "ALL", "earned": cleared >= Game.stages().size(),
			"how": "clear the whole campaign", "big": true},
	]
	return out


## 03 PRINT SHOWCASE: the chosen prints in their slabs (three slots), OPEN ALBUM in signal.
func _build_showcase() -> void:
	var p := _poster
	var y := _y_badges + 40.0 + 2.0 * (STAMP + 10.0) + 26.0
	var tw := _tw
	var stats := Game.print_stats()
	PK.at(p, PK.t("03  PRINT SHOWCASE", 12, INK, "mono_bold"), Vector2(X0, y))
	var open := PK.t("%d PRINTS  ·  OPEN ALBUM ›" % int(stats.get("kept", 0)), 12, SIG, "mono_bold")
	open.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	open.size = Vector2(tw, 16)
	PK.at(p, open, Vector2(X0, y))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(X0, y + 20))
	var sc := Game.showcase()
	var gap := 12.0
	var cw := floorf((tw - gap * 2.0) / 3.0)
	var ch := roundf(cw * 1.5)
	for i in 3:
		var pos := Vector2(X0 + i * (cw + gap), y + 40.0)
		if i < sc.size():
			var pd: Dictionary = sc[i]
			var card := PrintCard.make(pd, Vector2(cw, ch))
			card.name = "Showcase_%d" % i
			card.position = pos
			card.rotation = (i - 1) * 0.025
			card.pivot_offset = card.size * 0.5
			p.add_child(card)
			var uid := str(pd.get("uid", ""))
			_hit(p, Rect2(pos, Vector2(cw, ch)), func() -> void: UI.go("prints", {"open": uid}), "ShowcasePrint_%d" % i)
		else:
			var slot := PrintBits.CropMarks.new()
			slot.position = pos
			slot.size = Vector2(cw, ch)
			slot.mouse_filter = MOUSE_FILTER_IGNORE
			p.add_child(slot)
			var el := PK.t("EMPTY SLOT" + char(10) + char(10) + "PICK A PRINT" + char(10) + "IN THE ALBUM", 10, Color(INK, 0.55), "mono_bold")
			el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			el.size = Vector2(cw, 80)
			PK.at(p, el, pos + Vector2(0, ch * 0.5 - 40.0))
			_hit(p, Rect2(pos, Vector2(cw, ch)), func() -> void: UI.go("prints"), "ShowcaseEmpty_%d" % i)
	_hit(p, Rect2(X0 + tw - 280, y - 34, 280, 88), func() -> void: UI.go("prints"), "OpenAlbum", "Open album")


## 04 THE RECORD: what the game has noted, dated, most recent first: the day the form was signed,
## each commendation (setting commend_days), each real day stamped (state.calendar.claimed). Up to
## LOG_N lines; older ones counted.
func _build_log() -> void:
	var p := _poster
	var tw := _tw
	var cw := floorf((tw - 24.0) / 3.0)
	var y := _y_badges + 40.0 + 2.0 * (STAMP + 10.0) + 26.0 + 40.0 + roundf(cw * 1.5) + 34.0
	var lines := record_lines()
	PK.at(p, PK.t("04  THE RECORD", 12, INK, "mono_bold"), Vector2(X0, y))
	var kept := PK.t("KEPT BY THE GAME", 12, Color(INK, 0.5), "mono_bold")
	kept.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kept.size = Vector2(tw, 16)
	PK.at(p, kept, Vector2(X0, y))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(X0, y + 20))
	var ly := y + 40.0
	for i in mini(lines.size(), LOG_N):
		var e: Array = lines[i]
		PK.at(p, PK.t(_ddmmyy(int(e[0])), 11, SIG if i == 0 else INK, "mono_bold"), Vector2(X0, ly + 6))
		var t := PK.t(str(e[1]), 19, INK, "serif_italic")
		t.size = Vector2(tw - 92, 26)
		t.clip_text = true
		PK.at(p, t, Vector2(X0 + 92, ly))
		PK.rule(p, Vector2(X0, ly + 28), Vector2(tw, 1), Color(INK, 0.15))
		ly += 30.0
	if lines.size() > LOG_N:
		PK.at(p, PK.t("+%d EARLIER" % (lines.size() - LOG_N), 10, Color(INK, 0.55), "mono_bold"), Vector2(X0, ly + 6))


## The record's lines: [day, text], newest first (same day: the order they were noted).
static func record_lines() -> Array:
	var out: Array = []
	var created := int(Game.state.get("created_at", 0))
	if created > 0:
		out.append([Game.day_of(created), "Signed the intake form." if Game.onboarded() else "Arrived at the front.", 0])
	var names := {}
	var rank := {}
	var bl := badges()
	for k in bl.size():
		names[str(bl[k].id)] = str(bl[k].ring).capitalize()
		rank[str(bl[k].id)] = k
	var cd: Variant = Game.setting(COMMEND_KEY)
	if cd is Dictionary:
		for id: Variant in cd:
			# Same day: the harder commendation (later in the list) reads as the newer.
			out.append([int(cd[id]), "Commended: %s." % str(names.get(str(id), str(id))), 1.0 + 0.01 * float(rank.get(str(id), 0))])
	var cal: Variant = (Game.state.get("calendar", {}) as Dictionary).get("claimed", {})
	if cal is Dictionary:
		for key: Variant in cal:
			out.append([int(cal[key]), _calendar_line(str(key)), 2])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) if int(a[0]) != int(b[0]) else float(a[2]) > float(b[2]))
	return out


## A stamped day as the record says it: "you-2026" (the player's birthday), "bday-<hero>-<year>",
## or "<holiday id>-<year>".
static func _calendar_line(key: String) -> String:
	if key.begins_with("you-"):
		return "Your birthday. She remembered."
	if key.begins_with("bday-"):
		var hid := key.trim_prefix("bday-").rsplit("-", true, 1)[0]
		return "%s's birthday, stamped." % str(Game.hero_def(hid).get("name", hid))
	var hol := key.rsplit("-", true, 1)[0]
	return "%s, stamped." % str(CalendarRules.holiday(hol).get("name", hol))


## The menu down the right-hand rule: AVATAR, NAME, TEAM, SETTINGS.
func _build_menu() -> void:
	var p := _poster
	var rx := _pr.size.x - RULE_IN
	Poster.vline(p, rx, 0, _pr.size.y, Color(INK, 0.55))
	Poster.vlabel(p, "©2026 ·", Vector2(rx + 34, 12), 12, INK)
	_side_menu(p, rx, 170.0, 112.0, [
		{"text": "AVATAR", "name": "SideAvatar", "on_pressed": _open_avatar_sheet},
		{"text": "NAME", "name": "SideName", "on_pressed": _open_name_sheet},
		{"text": "TEAM", "name": "SideTeam", "on_pressed": func() -> void: UI.go("formation")},
		{"text": "SETTINGS", "name": "SideSettings", "on_pressed": func() -> void: UI.go("settings")},
	])


## Under the poster: the date and the player's signature (tap: rename).
func _build_footer(ox: float, w: float) -> void:
	var fy := _pr.end.y + 12.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sig_btn := Button.new()
	sig_btn.name = "Signature"
	sig_btn.theme_type_variation = &"BareButton"
	sig_btn.focus_mode = FOCUS_NONE
	sig_btn.position = Vector2(ox + w - 24 - 330, fy - 10)
	sig_btn.size = Vector2(330, 88)
	_drag_guard(sig_btn, _open_name_sheet)
	_page.add_child(sig_btn)
	if Signature.has_ink(Game.signature()):
		# Her own hand from the intake form, right-aligned over the swash.
		var sg := Signature.new()
		sg.strokes = Game.signature()
		sg.ink = INK
		sg.size = Vector2(200, 58)
		sg.position = Vector2(126, 2)
		sig_btn.add_child(sg)
	else:
		var sl := PK.t(player_name_raw(), 40, INK, "serif_italic")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sl.mouse_filter = MOUSE_FILTER_IGNORE
		sl.clip_text = true
		sl.size = Vector2(330, 50)
		sl.position = Vector2(0, 8)
		sig_btn.add_child(sl)
	var swash := ColorRect.new()
	swash.color = INK
	swash.mouse_filter = MOUSE_FILTER_IGNORE
	swash.position = Vector2(120, 60)
	swash.size = Vector2(200, 2)
	swash.rotation = -0.05
	sig_btn.add_child(swash)


## The menu down the right-hand rule as vertical labels with ticks (Poster.side_menu's look, with
## drag-friendly hit areas). items: [{text, name, on_pressed}].
func _side_menu(p: Control, x: float, y0: float, step: float, items: Array) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var y := y0 + i * step
		Poster.vlabel(p, str(it.get("text", "")), Vector2(x + 32, y), 14, INK)
		Poster.rect(p, Rect2(x - 4, y + 2, 9, 1), INK)
		_hit(p, Rect2(x - 40, y - 12, 88, maxf(step, 88.0)), it.get("on_pressed", Callable()), str(it.get("name", "")), str(it.get("text", "")))


## An invisible tap area on the page. It lets drags through to the page's ScrollContainer (a finger
## can scroll from anywhere) and ignores a press that turned into a scroll. text: its words for
## tests (drawn invisible).
func _hit(parent: Control, r: Rect2, on_pressed: Callable, node_name: String, text: String = "") -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.flat = true
	b.position = r.position
	b.size = r.size
	b.name = node_name
	if text != "":
		b.text = text
		for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(0, 0, 0, 0))
	_drag_guard(b, on_pressed)
	parent.add_child(b)
	return b


## Makes a button inside the scrolling page drag-friendly: mouse_filter PASS (a drag reaches the
## ScrollContainer on a phone) and `pressed` only fires for a tap, not for a scroll (Kit's guard).
func _drag_guard(b: BaseButton, on_pressed: Callable) -> void:
	b.mouse_filter = MOUSE_FILTER_PASS
	b.button_down.connect(func() -> void: b.set_meta("_down_at", b.get_global_mouse_position()))
	Kit._connect_pressed(b, on_pressed)


# ------------------------------------------------------------------ data

## Days since the save was created (day 1 = the first day).
func _days() -> int:
	var created := int(Game.state.get("created_at", Game.now_ms()))
	return maxi(1, Game.today() - Game.day_of(created) + 1)


func _created_date() -> String:
	var created := int(Game.state.get("created_at", Game.now_ms()))
	var d := Time.get_datetime_dict_from_unix_time(created / 1000)
	return "%04d.%02d.%02d" % [int(d.year), int(d.month), int(d.day)]


## [faction name, "N OF M HEROES"] for the faction most of the player's heroes belong to.
func _allegiance() -> Array:
	var counts := {}
	var owned := Game.owned_heroes()
	for h: Dictionary in owned:
		var f := str(Game.hero_def(str(h.get("id", ""))).get("faction", ""))
		if f != "":
			counts[f] = int(counts.get(f, 0)) + 1
	var best := ""
	for f: String in counts:
		if best == "" or int(counts[f]) > int(counts[best]):
			best = f
	if best == "":
		return ["UNSWORN", "NO HEROES YET"]
	return [str(Kit.FACTION_NAMES.get(best, best)).to_upper(), "%d OF %d HEROES" % [int(counts[best]), owned.size()]]


# ------------------------------------------------------------------ sheets

## The avatar picker: every owned hero's framed portrait (the team lead first, as AUTO); a tap
## makes her the portrait on the ID card and in the top bar.
func _open_avatar_sheet() -> void:
	if _modal and is_instance_valid(_modal):
		return
	var owned := Game.owned_heroes()
	var col := Kit.vbox(12)
	col.custom_minimum_size.x = 584
	col.add_child(Kit.print_label("Choose your portrait  ·  %d on file" % owned.size(), 12, Color(Kit.TEXT, 0.7)))
	var grid := GridContainer.new()
	grid.name = "Portraits"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 13)
	grid.add_theme_constant_override("v_separation", 10)
	var cur := avatar_hero()
	var lead := lead_hero()
	var cell := Vector2(136, 168)
	grid.add_child(_avatar_cell("", lead, "Team lead", "AUTO", cur == "", cell))
	for h: Dictionary in owned:
		var id := str(h.get("id", ""))
		grid.add_child(_avatar_cell(id, id, str(Game.hero_def(id).get("name", id)), "SELECTED" if cur == id else "", cur == id, cell))
	var rows := ceili((owned.size() + 1) / 4.0)
	if rows > 3:
		var sc := Kit.scroll(grid)
		sc.custom_minimum_size = Vector2(584, 3.0 * (cell.y + 24.0) + 2.0 * 10.0 + 30.0)
		col.add_child(sc)
	else:
		col.add_child(grid)
	var note := Kit.label("Your portrait is printed on your ID card and shown in the top bar. AUTO follows your team lead.",
		20, Color(Kit.TEXT, 0.72), "serif_italic")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 584
	col.add_child(note)
	_modal = UI.popup("Portrait", col, func() -> void: _modal = null, 640.0, true)


func _avatar_cell(value: String, art_id: String, caption: String, tag: String, selected: bool, cell: Vector2) -> Button:
	var b := Button.new()
	b.name = "Avatar_%s" % (value if value != "" else "auto")
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = cell + Vector2(0, 24)
	var pc := Bits.portrait_cell(art_id, Kit.hero_look(art_id) if art_id != "" else "", cell, selected, caption, tag)
	b.add_child(pc)
	b.button_down.connect(func() -> void: pc.modulate = Color(0.85, 0.85, 0.85))
	b.button_up.connect(func() -> void: pc.modulate = Color.WHITE)
	_drag_guard(b, func() -> void: _pick_avatar(value))
	return b


func _pick_avatar(id: String) -> void:
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null
	var prev: Variant = Game.setting(AVATAR_KEY)
	if (str(prev) if prev is String else "") == id:
		return
	Game.set_setting(AVATAR_KEY, id)
	UI.toast("Portrait: %s" % (str(Game.hero_def(id).get("name", id)) if id != "" else "your team lead"), "good")


## The call sign sheet: a printed field (big compressed type on a ruled line), a letter count,
## and the Save pass.
func _open_name_sheet() -> void:
	if _modal and is_instance_valid(_modal):
		return
	var col := Kit.vbox(14)
	col.custom_minimum_size.x = 584
	col.add_child(Kit.print_label("Call sign  ·  printed on your ID card and signature", 12, Color(Kit.TEXT, 0.7)))
	var le := LineEdit.new()
	le.name = "NameField"
	le.max_length = NAME_MAX
	le.text = player_name_raw()
	le.placeholder_text = DEFAULT_NAME
	le.select_all_on_focus = true
	le.caret_blink = true
	le.context_menu_enabled = false
	le.custom_minimum_size = Vector2(584, 100)
	le.add_theme_font_override("font", Kit.font("compressed"))
	le.add_theme_font_size_override("font_size", 72)
	le.add_theme_color_override("font_color", INK)
	le.add_theme_color_override("font_placeholder_color", Color(INK, 0.25))
	le.add_theme_color_override("caret_color", SIG)
	le.add_theme_color_override("selection_color", Color(SIG, 0.3))
	le.add_theme_constant_override("caret_width", 3)
	for k: String in ["normal", "focus", "read_only"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = SIG if k == "focus" else INK
		sb.border_width_bottom = 2
		sb.content_margin_left = 2
		sb.content_margin_right = 2
		sb.content_margin_top = 4
		sb.content_margin_bottom = 6
		le.add_theme_stylebox_override(k, sb)
	col.add_child(le)
	var info := Kit.hbox(8)
	info.mouse_filter = MOUSE_FILTER_IGNORE
	var hint := Kit.print_label("%d characters at most" % NAME_MAX, 10, Color(Kit.TEXT, 0.6), "mono")
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_child(hint)
	var count := Kit.label("", 12, INK, "mono_bold")
	info.add_child(count)
	col.add_child(info)
	var upd := func(t: String) -> void:
		count.text = "%02d / %02d" % [t.length(), NAME_MAX]
		count.add_theme_color_override("font_color", SIG if t.length() >= NAME_MAX else INK)
	upd.call(le.text)
	le.text_changed.connect(upd)
	le.text_submitted.connect(func(t: String) -> void: _save_name(t))
	col.add_child(Kit.spacer(0, 4))
	var save := Kit.sheet_pass({"width": 584.0, "kicker": "REGISTRY  //  SIGN", "title": "SAVE CALL SIGN", "action": "SIGN  >>>",
		"icon": "check", "text": "Save", "info": "SHOWN ON YOUR ID CARD AND YOUR SIGNATURE"}, func() -> void: _save_name(le.text))
	save.name = "SaveName"
	col.add_child(save)
	_name_edit = le
	_modal = UI.popup("Call sign", col, func() -> void:
		_modal = null
		_name_edit = null, 640.0, true)
	le.grab_focus.call_deferred()


func _save_name(text: String) -> void:
	var n := text.strip_edges().replace("[", "(").replace("]", ")").left(NAME_MAX)
	if n.is_empty():
		if _name_edit and is_instance_valid(_name_edit):
			Kit.deny(_name_edit)
		UI.toast("Type a call sign first", "bad")
		return
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
	_modal = null
	_name_edit = null
	if n == player_name_raw():
		return
	Game.set_setting(NAME_KEY, n)
	UI.toast("Call sign saved: %s" % n.to_upper(), "good")
