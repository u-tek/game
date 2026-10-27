class_name PrintsScreen
extends Control
## Screen "prints": the print album (misprints; data/prints.json, Game.prints) as a poster in the house
## style (docs/dev/ui-style-v4.md section 0), with the physical pieces of the owner's 2026-10-19
## references rebuilt: every print sealed in a clear acrylic grading slab (PrintCard), the filters as
## frosted acrylic index tabs with LEDs, the title debossed into the stock.
##
## The poster: a dark band down the left with the album's best print as a red halftone and PRINTS set
## huge down it (two-tone where it crosses onto the paper); the register block (the count, a mono
## data list: misprints, holo, top grade, from Rue, pulled, the best print); the five tabs (All,
## Misprints, Holo, Top grade, From Rue); the slabs three to a row. A tap opens the print sheet (the
## specimen-sheet reference): the print big inside HUD ring arcs and ticks, "GRADING ...", the serial
## large, a barcode ring, the hero's name between browse arrows, a two-column data list (edition,
## printing, serial, banner, flaw, ink, foil, grade, pulled, source), the flaw's story and "Show on
## profile" (label tape) for the showcase.
## params: filter ("all" | "misprint" | "holo" | "top" | "rival"), open (a print uid: its sheet),
## hero (only that hero's prints, from the Heroes screen).

const Signature := preload("res://src/ui/components/signature.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

const FILTERS := [["all", "All"], ["misprint", "Misprints"], ["holo", "Holo"], ["top", "Top grade"], ["rival", "From Rue"]]
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL
const BAND_C := Kit.BAND
const SHEET := Color("e2e3e1")
const BAND := 132.0
const HEAD := 320.0
const COLS := 3
const MAX_W := 760.0

var _params: Dictionary = {}
var _filter := "all"
var _hero := ""
var _list: Array[Dictionary] = []
var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _cards: Array[Control] = []
## The album's slots in list order: {pos, i, card (null until built)}.
var _slots: Array[Dictionary] = []
var _card_size := Vector2.ZERO
## Where the grid's tap areas start among the poster's children (slabs go in just before them).
var _hits_from := 0
var _modal: Control
var _sheet_i := -1
var _built := Vector2.ZERO
var _rebuild_queued := false


func setup(params: Dictionary) -> void:
	_params = params
	_filter = str(params.get("filter", "all"))
	_hero = str(params.get("hero", ""))
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	if params.has("open"):
		var uid := str(params.open)
		_open_sheet.call_deferred(_index_of(uid))
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


## Entrance: the register drops in, the slabs are laid down one after another.
func intro() -> void:
	if not Kit.motion_ok():
		return
	for i in mini(_cards.size(), 9):
		var c := _cards[i]
		c.modulate.a = 0.0
		var y0 := c.position.y
		c.position.y = y0 - 26.0
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(0.08 + i * 0.045)
		tw.tween_property(c, "position:y", y0, 0.34).set_delay(0.08 + i * 0.045).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	_cards.clear()
	_build()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


func _query() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in Game.prints(_filter):
		if _hero == "" or str(p.get("hero", "")) == _hero:
			out.append(p)
	return out


func _index_of(uid: String) -> int:
	for i in _list.size():
		if str(_list[i].get("uid", "")) == uid:
			return i
	return -1


# ------------------------------------------------------------------ build

func _build() -> void:
	var d := _dims()
	_built = d
	_list = _query()
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	var pw := w - 32.0
	var gap := 14.0
	var cw := floorf((pw - 28.0 - gap * (COLS - 1)) / COLS)
	var ch := roundf(cw * 1.5)
	var rows := maxi(1, ceili(float(_list.size()) / COLS))
	var grid_h := rows * (ch + 22.0) + 30.0
	var ph := maxf(HEAD + 104.0 + grid_h + 90.0, d.y - 14.0 - 84.0)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
	_scroll = Kit.scroll(_page)
	_scroll.name = "Album"
	_scroll.position = Vector2.ZERO
	_scroll.size = d
	add_child(_scroll)
	var pr := Rect2(ox + 16, 14, pw, ph)
	_poster = PK.poster(_page, pr)
	_build_head(pw)
	_build_tabs(pw)
	_build_grid(pw, cw, ch, gap)
	# Engraved corners at the foot of the binder page.
	for k in 2:
		var orn := CK.Ornament.new()
		orn.size = Vector2(150, 110)
		orn.flip = Vector2(1 if k == 0 else -1, -1)
		orn.position = Vector2(8 if k == 0 else pw - 158, ph - 118)
		_poster.add_child(orn)
	_build_footer(ox, w, pr)
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))


## The head: the dark band with the best print's halftone and PRINTS down it, the register block.
func _build_head(pw: float) -> void:
	var p := _poster
	var stats: Dictionary = Game.print_stats()
	var best: Dictionary = stats.get("best", {})
	PK.rect(p, Rect2(0, 0, BAND, HEAD), BAND_C)
	var face := str(best.get("hero", ""))
	if face == "":
		face = ProfileScreen.shown_avatar()
	if face != "":
		var ht := PK.halftone_print(face, "", Vector2(BAND, HEAD * 0.62), 6.0)
		ht.position = Vector2(0, HEAD * 0.38)
		p.add_child(ht)
	Poster.vlabel(p, "©2026 HH · PRINT REGISTER · ALL EDITIONS", Vector2(24, 110), 10, Color(PAPER, 0.8))
	# PRINTS set down the band as big as the head allows, half on the band, half on the paper.
	var title := "PRINTS[color=#%s].[/color]" % SIG.to_html(false)
	var fs := 200
	while fs > 80 and PK.text_w("PRINTS.", fs) > HEAD - 118.0:
		fs -= 4
	var gx := BAND + roundf(fs * 0.5)
	PK.giant(p, title, fs, Vector2(gx, 112), Vector2(HEAD, fs * 1.3), [[Rect2(0, 0, BAND, HEAD), PAPER],
		[Rect2(BAND, 0, gx - BAND + 6.0, HEAD), INK]], 0, "compressed", true)
	# The register block, right of the giant type.
	var x0 := gx + 22.0
	var tw := pw - x0 - 18.0
	PK.at(p, PK.t("PRINT REGISTER  ·  ALBUM", 12, INK, "mono_bold"), Vector2(x0, 18))
	var no := PK.t("Nº %04d" % int(stats.get("total", 0)), 12, INK, "mono_bold")
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	no.size = Vector2(tw, 16)
	PK.at(p, no, Vector2(x0, 18))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 38))
	var kept := int(stats.get("kept", 0))
	var count_s := "%03d" % kept
	var big := CK.deboss(count_s, 96, PAPER, "compressed", 2.0)
	big.name = "Count"
	PK.at(p, big, Vector2(x0 - 2, 44))
	# The caption starts after the count, however many digits it has.
	var cw := Kit.font("compressed").get_string_size(count_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
	var cap := PK.t("PRINTS IN THE ALBUM\nKEPT FOREVER: EVERY MISPRINT,\nHOLO, TOP GRADE AND FIRST COPY", 10, Color(INK, 0.72), "mono")
	PK.at(p, cap, Vector2(x0 + cw + 18.0, 66))
	# An engraved fleuron between the count and the register (the parchment poster's ornaments).
	var fl := CK.Fleuron.new()
	fl.size = Vector2(tw, 18)
	fl.position = Vector2(x0, 146)
	p.add_child(fl)
	var dl := CK.DataList.new()
	dl.name = "Register"
	var bp := best
	# Misprints, holo, top grade and Rue's count are on the filter tabs just below (owner-approved cut).
	dl.rows = [
		["EVER PULLED", Kit.format_num(int(stats.get("total", 0))), true],
		[],
		["BEST", ("%s · %s" % [str(HeroData.get_def(str(bp.get("hero", ""))).get("name", "")).to_upper(),
			"No.%04d" % int(bp.get("serial", 0))]) if not bp.is_empty() else "--"],
		["", (PrintCard.flags_line(bp).to_upper() if not bp.is_empty() else "")],
	]
	dl.text_size = 12
	dl.row_h = 23.0
	dl.position = Vector2(x0 + 6, 172)
	dl.size = Vector2(tw - 6, 180)
	p.add_child(dl)
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


## The filter tabs: frosted acrylic index tabs with a count and an LED.
func _build_tabs(pw: float) -> void:
	var y := HEAD + 8.0
	var x := 14.0
	var w := floorf((pw - 28.0 - 4.0 * 6.0) / 5.0)
	for f: Array in FILTERS:
		var id := str(f[0])
		var n := 0
		for p: Dictionary in Game.prints(id):
			if _hero == "" or str(p.get("hero", "")) == _hero:
				n += 1
		var b := CK.acrylic_tab(str(f[1]), n, id == _filter, w, func() -> void: _set_filter(id))
		b.name = "Tab_%s" % id
		b.position = Vector2(x, y)
		_poster.add_child(b)
		x += w + 6.0
	if _hero != "":
		var hn := str(HeroData.get_def(_hero).get("name", _hero)).to_upper()
		var note := PK.t("ONLY %s  ·  TAP ALL HEROES" % hn, 11, SIG, "mono_bold")
		PK.at(_poster, note, Vector2(16, y + 92))
		CK.hit(_poster, Rect2(10, y + 80, 420, 88), func() -> void:
			_hero = ""
			_on_changed(), "AllHeroes", "All heroes")


func _set_filter(id: String) -> void:
	if id == _filter:
		return
	_filter = id
	UI.sfx("tab")
	_on_changed()


## The slabs, three to a row (an empty album says how prints arrive).
func _build_grid(pw: float, cw: float, ch: float, gap: float) -> void:
	var y0 := HEAD + 104.0 + (30.0 if _hero != "" else 0.0)
	_hits_from = _poster.get_child_count()
	if _list.is_empty():
		var msg: String = {"misprint": "No misprints yet. About 6 prints in 100 come off the press flawed.",
			"holo": "No holo foil yet. About 3 prints in 200 are foiled.",
			"top": "Nothing graded 9 or 10 yet.",
			"rival": "Nothing from Rue yet. Beat her: the first win each day takes her best print."}.get(_filter,
			"Every hero you summon arrives as a numbered print. Summon to start the album.")
		var l := PK.t(str(msg), 26, Color(INK, 0.75), "serif_italic")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = Vector2(pw - 60, 120)
		PK.at(_poster, l, Vector2(30, y0 + 20))
		return
	# Every slot gets its tap area now; the slabs themselves are built as they scroll into view (an
	# album of a few hundred prints would be thousands of nodes at once on a phone).
	_slots.clear()
	_card_size = Vector2(cw, ch)
	for i in _list.size():
		var p: Dictionary = _list[i]
		var col := i % COLS
		var row := i / COLS
		var pos := Vector2(14.0 + col * (cw + gap), y0 + row * (ch + 22.0))
		_slots.append({"pos": pos, "i": i, "card": null})
		var idx := i
		CK.hit(_poster, Rect2(pos, Vector2(cw, ch)), func() -> void: _open_sheet(idx), "Open_%s" % str(p.get("uid", i)))
	_fill_visible()
	var bar := _scroll.get_v_scroll_bar()
	if not bar.value_changed.is_connected(_on_scrolled):
		bar.value_changed.connect(_on_scrolled)


func _on_scrolled(_v: float) -> void:
	_fill_visible()


## Builds the slabs of the rows near the view (and keeps them).
func _fill_visible() -> void:
	if _slots.is_empty() or not is_instance_valid(_scroll):
		return
	var top := float(_scroll.scroll_vertical) - 14.0 - 700.0
	var bottom := float(_scroll.scroll_vertical) + _built.y + 700.0
	var shown: Array = (Game.state.get("prints", {}) as Dictionary).get("showcase", [])
	for sl: Dictionary in _slots:
		if sl.card != null:
			continue
		var pos: Vector2 = sl.pos
		if pos.y + _card_size.y < top or pos.y > bottom:
			continue
		var p: Dictionary = _list[int(sl.i)]
		var card := PrintCard.make(p, _card_size)
		card.name = "Print_%s" % str(p.get("uid", sl.i))
		card.position = pos
		card.rotation = (float(absi(hash(str(p.get("uid", "")))) % 9) - 4.0) * 0.004
		card.pivot_offset = card.size * 0.5
		_poster.add_child(card)
		# Under the tap areas (they were added first): keep the slabs behind them.
		_poster.move_child(card, mini(_hits_from, _poster.get_child_count() - 1))
		_cards.append(card)
		sl.card = card
		if shown.has(str(p.get("uid", ""))):
			var tape := PK.t(" ON PROFILE ", 10, Color("f4f3ef"), "mono_bold")
			var tb := ColorRect.new()
			tb.mouse_filter = MOUSE_FILTER_IGNORE
			tb.color = SIG
			tb.size = tape.get_minimum_size()
			tb.position = Vector2(_card_size.x - tb.size.x + 6.0, _card_size.y - 10.0)
			tb.rotation = -0.05
			tb.add_child(tape)
			card.add_child(tb)


func _build_footer(ox: float, w: float, pr: Rect2) -> void:
	var fy := pr.end.y + 12.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	if Signature.has_ink(Game.signature()):
		var sg := Signature.new()
		sg.strokes = Game.signature()
		sg.ink = INK
		sg.size = Vector2(200, 56)
		sg.position = Vector2(ox + w - 24 - 200, fy - 4)
		_page.add_child(sg)
	else:
		var sl := PK.t(ProfileScreen.player_name_raw(), 40, INK, "serif_italic")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sl.size = Vector2(330, 50)
		PK.at(_page, sl, Vector2(ox + w - 24 - 330, fy))


# ------------------------------------------------------------------ the print sheet

## Opens print i of the current list in the specimen sheet (replacing an open one).
func _open_sheet(i: int) -> void:
	if i < 0 or i >= _list.size():
		return
	_sheet_i = i
	if _modal and is_instance_valid(_modal):
		UI.close_modal(_modal)
		_modal = null
	var content := _sheet(_list[i])
	_modal = UI.modal(content, true, func() -> void: _modal = null)
	UI.sfx("pop")


func _browse(step: int) -> void:
	if _list.is_empty():
		return
	_open_sheet(posmod(_sheet_i + step, _list.size()))


## The specimen sheet: the print inside HUD rings, the serial big, name with arrows, the data list.
func _sheet(p: Dictionary) -> Control:
	var vp := get_viewport_rect().size
	var sw := minf(vp.x - 24.0, 700.0)
	var sh := minf(vp.y - UI.safe_top() - UI.safe_bottom() - 24.0, 1260.0)
	var root := Control.new()
	root.name = "PrintSheet"
	root.custom_minimum_size = Vector2(sw, sh)
	root.size = root.custom_minimum_size
	root.mouse_filter = MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHEET
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 10)
	bg.add_theme_stylebox_override("panel", sb)
	bg.size = root.size
	root.add_child(bg)
	var frame := CK.CropFrame.new()
	frame.position = Vector2(24, 24)
	frame.size = Vector2(sw - 48, sh - 48)
	root.add_child(frame)
	# Top: GRADING ..., the print's file number, the serial set big and thin.
	var hid := str(p.get("hero", ""))
	var d := HeroData.get_def(hid)
	PK.at(root, PK.t("GRADING ...  FILE %s" % str(p.get("uid", "")).to_upper(), 12, INK, "mono"), Vector2(46, 40))
	var no := PK.t("%04d" % int(p.get("serial", 0)), 64, INK, "compressed_light")
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	no.size = Vector2(240, 70)
	PK.at(root, no, Vector2(sw - 48 - 240 - 18, 30))
	PK.rect(root, Rect2(sw - 58, 44, 2, 50), INK)
	PK.at(root, PK.t("No.", 12, Color(INK, 0.6), "mono"), Vector2(sw - 48 - 240 - 10, 40))
	var of := PK.t("OF %s" % Kit.format_full(int(p.get("run", 0))), 11, Color(INK, 0.7), "mono_bold")
	of.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	of.size = Vector2(200, 14)
	PK.at(root, of, Vector2(sw - 48 - 200 - 18, 98))
	# The print, big, inside the HUD ring.
	var cw := minf(sw * 0.5, (sh - 520.0) / 1.5)
	cw = maxf(cw, 220.0)
	var chh := roundf(cw * 1.5)
	var cpos := Vector2((sw - cw) * 0.5 - 20.0, 128.0)
	var ring := CK.HudRing.new()
	ring.size = root.size
	ring.center = cpos + Vector2(cw, chh) * 0.5
	ring.radius = chh * 0.56
	root.add_child(ring)
	var card := PrintCard.make(p, Vector2(cw, chh))
	card.name = "BigPrint"
	card.position = cpos
	root.add_child(card)
	# A readout chip over the print's edge (the specimen's mass tag): grade.
	var chip := ColorRect.new()
	chip.mouse_filter = MOUSE_FILTER_IGNORE
	chip.color = Color(INK, 0.86)
	chip.position = Vector2(cpos.x - 52.0, cpos.y + chh * 0.62)
	chip.size = Vector2(196, 30)
	root.add_child(chip)
	PK.at(chip, PK.t("Grade", 12, Color("f4f3ef"), "mono_bold"), Vector2(10, 7))
	var gv := PK.t("%d.0  %s" % [int(p.get("grade", 0)), PrintRules.grade_name(int(p.get("grade", 0))).to_upper()], 12, Color("f4f3ef"), "mono")
	PK.at(chip, gv, Vector2(70, 7))
	# A vertical scale with a marker to the right of the ring.
	var vx := sw - 70.0
	PK.rect(root, Rect2(vx, cpos.y + 60, 1, chh - 120), Color(INK, 0.6))
	var gy := cpos.y + 60 + (chh - 120) * (1.0 - float(int(p.get("grade", 1)) - 1) / 9.0)
	PK.rect(root, Rect2(vx - 6, gy - 1, 13, 3), SIG)
	PK.at(root, PK.t("10", 9, Color(INK, 0.6), "mono"), Vector2(vx + 6, cpos.y + 52))
	PK.at(root, PK.t("1", 9, Color(INK, 0.6), "mono"), Vector2(vx + 6, cpos.y + chh - 68))
	# The name between browse arrows, a barcode ring beside it.
	var ny := cpos.y + chh + 34.0
	var nm := PK.t(str(d.get("name", hid)), 44, INK, "wide_black")
	Kit.fit_label(nm, sw - 300, 44, 24)
	PK.at(root, nm, Vector2(108, ny))
	var nmw := Kit.font("wide_black").get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, nm.get_theme_font_size("font_size")).x
	PK.rule(root, Vector2(108, ny + 62), Vector2(minf(nmw, 120.0), 1))
	var prev := Poster.hit(root, Rect2(30, ny - 14, 88, 88), func() -> void: _browse(-1), "Prev", "Previous print")
	var pl := PK.t("‹", 40, INK, "mono_bold")
	PK.at(prev, pl, Vector2(48, 12))
	var nxt := Poster.hit(root, Rect2(118 + nmw, ny - 14, 88, 88), func() -> void: _browse(1), "Next", "Next print")
	var nl := PK.t("›", 40, INK, "mono_bold")
	PK.at(nxt, nl, Vector2(18, 12))
	var bc := CK.BarcodeRing.new()
	bc.seed_v = int(p.get("serial", 1)) * 31 + int(p.get("v", 0))
	bc.caption = "ID %s" % str(p.get("uid", "")).to_upper()
	bc.position = Vector2(sw - 150, ny - 18)
	bc.size = Vector2(80, 80)
	root.add_child(bc)
	# The data list.
	var flaw := str(p.get("flaw", ""))
	var g := int(p.get("grade", 0))
	var ink_n := PrintRules.ink_name(str(p.get("ink", "")))
	var rows: Array = [
		["Edition", "ED.%02d · %s" % [int(p.get("edition", 1)), str(EconomyData.banner_def(str(p.get("banner", "standard"))).get("short", "")).to_upper()]],
		["Printing", PrintCard.edition_line(p).split(" · ")[1]],
		["Serial", PrintCard.serial_line(p).replace("No. ", ""), int(p.get("serial", 9999)) <= PrintRules.EARLY_SERIAL],
		["Flaw", PrintRules.flaw_name(flaw).to_upper() if flaw != "" else "NONE · A CLEAN PULL", flaw != ""],
		["Ink", ink_n.to_upper() if ink_n != "" else ("SIGNAL + KEY" if flaw != "ghost" else "KEY ONLY")],
		["Foil", "HOLOGRAPHIC" if bool(p.get("holo", false)) else "NONE", bool(p.get("holo", false))],
		["Grade", "%d · %s" % [g, PrintRules.grade_name(g).to_upper()], g >= 10],
		[],
		["Pulled", _date(int(p.get("day", 0)))],
		["From", "RUE'S BINDER · WON IN A FIGHT" if str(p.get("from", "")) == "rival" else ("SUMMON · FIRST COPY" if bool(p.get("first", false)) else "SUMMON")],
	]
	var dl := CK.DataList.new()
	dl.name = "PrintData"
	dl.rows = rows
	dl.text_size = 13
	dl.row_h = 23.0
	var dly := ny + 92.0
	dl.position = Vector2(64, dly)
	dl.size = Vector2(sw - 128, 230)
	root.add_child(dl)
	var about := ""
	if flaw != "":
		about = str(PrintRules.flaw_def(flaw).get("about", ""))
	elif bool(p.get("holo", false)):
		about = "A holographic foil laid under the inks. Tilt your phone."
	elif g >= 10:
		about = "Centred, sharp corners, perfect ink. The grader found nothing."
	else:
		about = "A clean pull from the press, numbered and graded."
	var ab := PK.t(about, 22, Color(INK, 0.8), "serif_italic")
	ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ab.size = Vector2(sw - 128, 60)
	var aby := dly + 222.0
	PK.at(root, ab, Vector2(64, aby))
	# Show on profile: label tape (signal when it is on the profile).
	var uid := str(p.get("uid", ""))
	var sc: Array = (Game.state.get("prints", {}).get("showcase", []) as Array).duplicate()
	var on := sc.has(uid)
	var tape := SignalKit.tape_button("ON YOUR PROFILE  ✓" if on else "SHOW ON PROFILE", func() -> void: _toggle_showcase(uid),
		SIG if on else INK, "Show on profile")
	tape.name = "ShowOnProfile"
	tape.position = Vector2(56, minf(aby + 64.0, sh - 128.0))
	root.add_child(tape)
	var hint := PK.t("%d / %d ON THE PROFILE" % [sc.size(), PrintRules.SHOWCASE_MAX], 11, Color(INK, 0.6), "mono_bold")
	PK.at(root, hint, Vector2(sw - 250, minf(aby + 96.0, sh - 96.0)))
	# Close (top right of the frame).
	var close := Poster.hit(root, Rect2(sw - 120, sh - 100, 96, 88), func() -> void:
		if _modal and is_instance_valid(_modal):
			UI.close_modal(_modal)
		_modal = null, "Close", "Close")
	PK.at(close, PK.t("× CLOSE", 14, INK, "mono_bold"), Vector2(8, 34))
	return root


func _toggle_showcase(uid: String) -> void:
	var sc: Array = (Game.state.get("prints", {}).get("showcase", []) as Array).duplicate()
	if sc.has(uid):
		sc.erase(uid)
	else:
		if sc.size() >= PrintRules.SHOWCASE_MAX:
			sc.pop_front()
		sc.append(uid)
	var r := Game.set_showcase(sc)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "")), "bad")
		return
	UI.toast("On your profile" if sc.has(uid) else "Taken off your profile", "good")
	_open_sheet(_sheet_i)


static func _date(day: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day * 86400)
	return "%04d.%02d.%02d" % [int(dt.year), int(dt.month), int(dt.day)]
