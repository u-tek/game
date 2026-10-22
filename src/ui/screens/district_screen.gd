extends Control
## Screen "district": the player's quarter on their side of the front (DistrictRules, GameModel
## district; docs/dev/combat-v1.md) in the house poster style: the quarter as an architect's maquette
## (src/ui/v4/district_model.gd: eight clay buildings rendered in Blender on an isometric ground slab),
## built ones in clay, a kept one marked in her side's ink, unbuilt ones frosted with the souls they
## need, the next one warmed in signal; each keeper's portrait framed on a leader line over her
## building. Under the plan, the ledger: one row per building (name, its idle
## bonus, its keeper or "NO KEEPER"), tap a row to choose a keeper (a sheet of owned heroines, the
## side's faction first: they double the bonus). The head: the quarter's name huge on the band, the
## lifetime souls debossed, the idle bonus per currency, the next building and the souls it needs.
## params: keeper (a building index: opens its keeper sheet; screenshots).

const Signature := preload("res://src/ui/components/signature.gd")
const PosterKit := preload("res://src/ui/v4/poster_kit.gd")
const DistrictModel := preload("res://src/ui/v4/district_model.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color(0.86, 0.66, 0.24)
const BAND_C := Color("141517")
const BAND := 132.0
const HEAD := 300.0
const PLAN_H := 530.0
const ROW_H := 74.0
const MAX_W := 760.0

var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _built := Vector2.ZERO
var _rebuild_queued := false
var _sheet: Control
var _arranging := false        ## ARRANGE: buildings can be dragged to other lots
var _held_kind := ""           ## ARRANGE: the prop a tap on a free lot buys ("" = none)
const SHELF_H := 300.0          ## the props shelf under the plan while arranging


func setup(params: Dictionary) -> void:
	if str(Game.war().side) == "":
		UI.toast("Swear to a side on the front first", "info")
		UI.go("front")
		return
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	# Screenshots: arrange = true opens in ARRANGE; keeper = a building index opens its keeper sheet.
	if bool(params.get("arrange", false)):
		_arranging = true
		_held_kind = str(params.get("prop", ""))
		_on_changed()
	# hold = [i, x, y]: building i held over that lot (ARRANGE, mid-drag); move = [i, x, y] places it.
	if params.get("move") is Array:
		var mv: Array = params.move
		Game.district_place(int(mv[0]), int(mv[1]), int(mv[2]))
	if params.get("hold") is Array:
		var hv: Array = params.hold
		_arranging = true
		_on_changed()
		(func() -> void:
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			var plan := find_child("Plan", true, false)
			if plan:
				plan.call("debug_hold", int(hv[0]), int(hv[1]), int(hv[2]))).call_deferred()
	if params.has("keeper"):
		_pick_keeper.call_deferred(int(params.keeper))


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_changed):
		Game.changed.disconnect(_on_changed)
	if _sheet and is_instance_valid(_sheet):
		UI.close_modal(_sheet)


func _on_changed() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


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
	_build()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


func _build() -> void:
	var d := _dims()
	_built = d
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	var pw := w - 32.0
	var dist: Dictionary = Game.district()
	var bl: Array = dist.buildings
	var shelf := SHELF_H if _arranging else 0.0
	var ph := maxf(HEAD + 30.0 + PLAN_H + 30.0 + shelf + bl.size() * ROW_H + 60.0, d.y - 14.0 - 84.0)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
	_scroll = Kit.scroll(_page)
	_scroll.name = "District"
	_scroll.size = d
	add_child(_scroll)
	var pr := Rect2(ox + 16, 14, pw, ph)
	_poster = PK.poster(_page, pr)
	_build_head(pw, dist)
	var plan := DistrictModel.new()
	plan.name = "Plan"
	plan.position = Vector2(18, HEAD + 30.0)
	plan.size = Vector2(pw - 36, PLAN_H)
	plan.set("dist", dist)
	plan.set("arranging", _arranging)
	plan.set("hold_kind", _held_kind if _arranging else "")
	plan.connect("placed", func(i: int, x: int, y: int) -> void:
		var r: Dictionary = Game.district_place(i, x, y)
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "")), "bad"))
	plan.connect("tapped", func(i: int) -> void:
		var b: Dictionary = (Game.district().buildings as Array)[i]
		if bool(b.open):
			Kit.sfx("tap")
			_pick_keeper(i)
		else:
			UI.toast("%s opens at %s souls" % [str(b.name), Kit.format_num(int(b.souls))], "info"))
	plan.connect("decor_moved", func(k: int, x: int, y: int) -> void:
		var r: Dictionary = Game.district_decor_move(k, x, y)
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "")), "bad"))
	plan.connect("decor_removed", func(k: int) -> void:
		var r: Dictionary = Game.district_decor_remove(k)
		if bool(r.get("ok", false)):
			Kit.sfx("coin")
			UI.toast("Sold back: +%s gold" % Kit.format_num(int((r.value.reward as Dictionary).get("gold", 0))), "good"))
	plan.connect("decor_bought", func(kind: String, x: int, y: int) -> void:
		var r: Dictionary = Game.district_decor_buy(kind, x, y)
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "")), "bad")
			return
		Kit.sfx("stamp", 1.4)
		UI.haptic(16))
	_poster.add_child(plan)
	if not _arranging:
		_keeper_prints(plan, dist)
	_arrange_toggle(pw)
	if _arranging:
		_decor_shelf(pw, HEAD + 30.0 + PLAN_H + 14.0, dist)
	_build_ledger(pw, HEAD + 30.0 + PLAN_H + 30.0 + shelf, dist)
	var fy := pr.end.y + 14.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sig := PK.t("the Quarter", 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	PK.at(_page, sig, Vector2(ox + w - 24 - 300, fy - 6))
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))


func _build_head(pw: float, dist: Dictionary) -> void:
	var p := _poster
	var side := str(dist.side)
	PK.rect(p, Rect2(0, 0, BAND, HEAD), BAND_C)
	Poster.vlabel(p, "©2026 HH · THE WAR FOR SOULS · DISTRICT", Vector2(24, 110), 10, Color(PAPER, 0.8))
	var word := "HALO" if side == "heaven" else "HORN"
	var title := "%s[color=#%s].[/color]" % [word, SIG.to_html(false)]
	var fs := 200
	# Measured type runs short of the set giant; fit with room to spare so the full stop shows.
	while fs > 60 and PK.text_w(word + ".", fs) * 1.45 > HEAD - 120.0:
		fs -= 4
	var gx := BAND + roundf(fs * 0.5)
	PK.giant(p, title, fs, Vector2(gx, 104), Vector2(HEAD, fs * 1.3), [[Rect2(0, 0, BAND, HEAD), PAPER],
		[Rect2(BAND, 0, gx - BAND + 6.0, HEAD), INK]], 0, "compressed", true)
	var x0 := gx + 22.0
	var tw := pw - x0 - 18.0
	PK.at(p, PK.t(str(dist.name).to_upper(), 12, SIG, "mono_bold"), Vector2(x0, 18))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 38))
	PK.at(p, PK.t("SOULS SETTLED", 10, Color(INK, 0.7), "mono_bold"), Vector2(x0, 48))
	PK.at(p, CK.deboss(Kit.format_num(int(dist.souls)), 80, PAPER, "compressed", 2.0), Vector2(x0 - 2, 60))
	var parts: Array[String] = []
	for k: Variant in (dist.bonus as Dictionary):
		parts.append("+%s%% %s" % [_pct(int(dist.bonus[k])), str(Kit.CURRENCY_SHORT.get(str(k), str(k))).to_upper()])
	var bonus := PK.t("IDLE  " + ("  ·  ".join(parts) if not parts.is_empty() else "NO BONUS YET"), 11, INK, "mono_bold")
	bonus.size = Vector2(tw, 32)
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(p, bonus, Vector2(x0, 160))
	var nxt: Dictionary = dist.next
	var nl := ("NEXT  %s AT %s SOULS" % [str(nxt.name).to_upper(), Kit.format_num(int(nxt.souls))]) if not nxt.is_empty() else "EVERY BUILDING OPEN"
	PK.at(p, PK.t(nl, 10, Color(INK, 0.7), "mono"), Vector2(x0, 200))
	var kf := "A CELESTIAL OR FALLEN" if side == "heaven" else "AN INFERNAL OR FALLEN"
	var kl := PK.t("%s KEEPER DOUBLES A BUILDING'S BONUS." % kf, 10, Color(INK, 0.7), "mono")
	kl.size = Vector2(tw, 30)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(p, kl, Vector2(x0, 220))
	# The quarter's deed: the holder's signature from the intake form (or their name), bottom right.
	var dx := pw - 18.0 - 190.0
	PK.at(p, PK.t("DEED HOLDER", 9, Color(INK, 0.55), "mono_bold"), Vector2(dx, HEAD - 22))
	PK.rule(p, Vector2(dx + 76, HEAD - 16), Vector2(114, 1))
	if Signature.has_ink(Game.signature()):
		var sg := Signature.new()
		sg.strokes = Game.signature()
		sg.ink = INK
		sg.size = Vector2(120, 36)
		sg.position = Vector2(dx + 70, HEAD - 52)
		p.add_child(sg)
	else:
		var nm := PK.t(str(Game.state.get("player_name", "")), 22, INK, "serif_italic")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nm.size = Vector2(190, 28)
		PK.at(p, nm, Vector2(dx, HEAD - 46))
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


static func _pct(bp: int) -> String:
	return ("%d" % (bp / 100)) if bp % 100 == 0 else ("%.1f" % (bp / 100.0))


## ARRANGE (top right of the plan): a paper tag that turns the plan into a board you rearrange by
## dragging; DONE in signal while it is on, with the hint under it.
func _arrange_toggle(pw: float) -> void:
	var at := Vector2(pw - 18 - 150, HEAD + 40)
	var tag := Control.new()
	tag.name = "Arrange"
	tag.position = at
	tag.size = Vector2(150, 88)
	tag.mouse_filter = MOUSE_FILTER_PASS
	_poster.add_child(tag)
	var box := Rect2(Vector2(20, 0), Vector2(130, 30))
	PK.rect(tag, box, SIG if _arranging else Color("f5f4f0"))
	PosterKit.hairbox(tag, box, SIG if _arranging else INK)
	var l := PK.t("DONE" if _arranging else "ARRANGE", 12, Color("f5f4f0") if _arranging else INK, "mono_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(box.size.x, 16)
	PK.at(tag, l, box.position + Vector2(0, 7))
	if _arranging:
		var h := PK.t("DRAG A BUILDING
TO ANOTHER LOT", 9, SIG, "mono_bold")
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.size = Vector2(150, 30)
		PK.at(tag, h, Vector2(0, 36))
	Kit.make_tappable(tag, func() -> void:
		_arranging = not _arranging
		_held_kind = ""
		Kit.sfx("tap")
		_on_changed())


## Each keeper's portrait framed over her building, on a leader line from its roof.
## While arranging: the props shelf under the plan. Each prop a small print with its name and its
## price in gold; tap one to hold it (signal border), then tap free lots on the plan to put it down
## (each a purchase); tap it again to put it away. The count of props and how to sell one back.
func _decor_shelf(pw: float, y: float, dist: Dictionary) -> void:
	var p := _poster
	var kinds: Array = dist.get("decor_kinds", [])
	var have := (dist.get("decor", []) as Array).size()
	PK.at(p, PK.t("THE PROPS  ·  %d / %d PLACED" % [have, int(dist.get("decor_max", 24))], 11, INK, "mono_bold"), Vector2(24, y))
	var hint := PK.t("TAP ONE, THEN TAP FREE LOTS  ·  DRAG ONE OFF THE QUARTER TO SELL IT BACK FOR HALF", 9,
		Color(INK, 0.6), "mono")
	hint.size = Vector2(pw - 48, 14)
	PK.at(p, hint, Vector2(24, y + 18))
	var cw := floorf((pw - 48 - 3 * 10) / 4.0)
	var ch := 112.0
	var info: Dictionary = {}
	var f := FileAccess.open("res://assets/art/ui/district/decor.json", FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			info = j
	for n in kinds.size():
		var k: Dictionary = kinds[n]
		var kid := str(k.id)
		var at := Vector2(24 + (n % 4) * (cw + 10), y + 40 + (n / 4) * (ch + 10))
		var card := Control.new()
		card.name = "Prop_" + kid
		card.position = at
		card.size = Vector2(cw, ch)
		card.mouse_filter = MOUSE_FILTER_PASS
		p.add_child(card)
		var held := kid == _held_kind
		PK.rect(card, Rect2(Vector2.ZERO, card.size), Color("f5f4f0"))
		PosterKit.hairbox(card, Rect2(Vector2.ZERO, card.size), SIG if held else Color(INK, 0.4))
		if held:
			PosterKit.hairbox(card, Rect2(Vector2(1, 1), card.size - Vector2(2, 2)), SIG)
		var tex: Texture2D = load("res://assets/art/ui/district/decor_%s.png" % kid)
		if tex:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.mouse_filter = MOUSE_FILTER_IGNORE
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.position = Vector2(6, 4)
			pic.size = Vector2(cw - 12, ch - 44)
			card.add_child(pic)
		PK.at(card, PK.t(str(k.name).to_upper(), 10, INK, "mono_bold"), Vector2(8, ch - 36))
		PK.at(card, PK.t("%s GOLD" % Kit.format_num(int(k.gold)), 10, SIG if held else Color(INK, 0.65), "mono"), Vector2(8, ch - 20))
		Kit.make_tappable(card, func() -> void:
			_held_kind = "" if _held_kind == kid else kid
			Kit.sfx("tap")
			_on_changed())


## Each portrait clears the others: one that would cover another is lifted on a longer leader.
func _keeper_prints(plan: Control, dist: Dictionary) -> void:
	var taken: Array[Rect2] = []
	var frames: Array[Control] = []
	for b: Variant in dist.buildings:
		var bd := b as Dictionary
		var hid := str(bd.keeper)
		if hid == "" or not bool(bd.open):
			continue
		var roof: Vector2 = plan.call("roof_point", int(bd.i))
		var s := 64.0
		var at := roof + Vector2(-s * 0.5, -s - 40.0)
		var lifted := true
		while lifted:
			lifted = false
			for r in taken:
				if r.grow(6.0).intersects(Rect2(at, Vector2(s, s))):
					at.y = r.position.y - s - 10.0
					lifted = true
		taken.append(Rect2(at, Vector2(s, s)))
		var lead := ColorRect.new()
		lead.mouse_filter = MOUSE_FILTER_IGNORE
		lead.color = SIG if bool(bd.doubled) else INK
		lead.position = Vector2(roof.x - 0.75, at.y + s)
		lead.size = Vector2(1.5, maxf(roof.y - 4.0 - (at.y + s), 0.0))
		plan.add_child(lead)
		# Leaders under every portrait (a lifted one's leader passes behind the one below it).
		plan.move_child(lead, plan.get_child_count() - 1 - frames.size())
		var fr := Control.new()
		fr.mouse_filter = MOUSE_FILTER_IGNORE
		fr.position = at
		fr.size = Vector2(s, s)
		plan.add_child(fr)
		PK.rect(fr, Rect2(-2, -2, s + 4, s + 4), SIG if bool(bd.doubled) else INK)
		var pic := HeroArt.make_portrait(hid, s, Game.equipped_skin(hid))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.size = Vector2(s, s)
		fr.add_child(pic)
		frames.append(fr)


func _build_ledger(pw: float, y: float, dist: Dictionary) -> void:
	var p := _poster
	PK.at(p, PK.t("THE LEDGER  ·  TAP A BUILDING (HERE OR ON THE MODEL): ITS KEEPER, ITS LEVEL", 11, INK, "mono_bold"), Vector2(24, y - 22))
	for b: Variant in dist.buildings:
		var bd := b as Dictionary
		var open := bool(bd.open)
		var row := Control.new()
		row.name = "Building_%d" % int(bd.i)
		row.mouse_filter = MOUSE_FILTER_PASS
		row.position = Vector2(20, y)
		row.size = Vector2(pw - 40, ROW_H - 6)
		p.add_child(row)
		PK.rect(row, Rect2(Vector2.ZERO, row.size), Color("f5f4f0") if open else Color(INK, 0.04))
		PK.rect(row, Rect2(0, 0, 5, row.size.y), (SIG if bool(bd.doubled) else INK) if open else Color(INK, 0.2))
		PK.at(row, PK.t("%02d" % (int(bd.i) + 1), 24, INK if open else Color(INK, 0.35), "compressed"), Vector2(16, 14))
		var nm_t := str(bd.name).to_upper()
		PK.at(row, PK.t(nm_t, 15, INK if open else Color(INK, 0.45), "mono_bold"), Vector2(60, 12))
		if open:
			var lv_x := 60.0 + Kit.font("mono_bold").get_string_size(nm_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 10.0
			var lvl := int(bd.get("level", 1))
			PK.at(row, PK.t("LV %d" % lvl, 11, SIG if lvl >= int(bd.get("max_level", 5)) else Color(INK, 0.6), "mono_bold"), Vector2(lv_x, 15))
		var cur := str(Kit.CURRENCY_SHORT.get(str(bd.currency), str(bd.currency))).to_upper()
		var sub := ("+%s%% %s IDLE" % [_pct(int(bd.bonus_bp)), cur]) + ("  ·  DOUBLED" if bool(bd.doubled) else "") if open \
			else "OPENS AT %s SOULS  ·  +%s%% %s" % [Kit.format_num(int(bd.souls)), _pct(int(bd.bonus_bp)), cur]
		PK.at(row, PK.t(sub, 10, SIG if bool(bd.doubled) else Color(INK, 0.7), "mono"), Vector2(60, 36))
		var hid := str(bd.keeper)
		var kl := PK.t(str(Game.hero_def(hid).get("name", "")).to_upper() if hid != "" else ("NO KEEPER  ›" if open else ""), 12,
			INK if hid != "" else SIG, "mono_bold")
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kl.size = Vector2(220, 16)
		PK.at(row, kl, Vector2(row.size.x - 300, 24))
		if hid != "":
			var pic := HeroArt.make_portrait(hid, 54, Game.equipped_skin(hid))
			pic.mouse_filter = MOUSE_FILTER_IGNORE
			pic.position = Vector2(row.size.x - 64, 7)
			pic.size = Vector2(54, 54)
			row.add_child(pic)
		if open:
			var bi := int(bd.i)
			Kit.make_tappable(row, func() -> void: _pick_keeper(bi))
		y += ROW_H


## The building's level in the sheet: LEVEL 2 / 5 as filled pips, its bonus now and at the next level,
## and an UPGRADE stamp for the gold (pressed: the level rises, the sheet shows the new one).
func _level_block(building: int, b: Dictionary, modal_ref: Array[Control]) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(560, 120)
	var lvl := int(b.get("level", 1))
	var mx := int(b.get("max_level", 5))
	var cur := str(Kit.CURRENCY_SHORT.get(str(b.currency), "")).to_upper()
	PK.at(box, PK.t("LEVEL %d / %d" % [lvl, mx], 22, INK, "compressed"), Vector2(0, 4))
	for k in mx:
		var pip := ColorRect.new()
		pip.mouse_filter = MOUSE_FILTER_IGNORE
		pip.color = SIG if k < lvl else Color(INK, 0.15)
		pip.position = Vector2(k * 22.0, 40)
		pip.size = Vector2(16, 8)
		box.add_child(pip)
	var cost: Dictionary = b.get("upgrade_cost", {})
	if cost.is_empty():
		PK.at(box, PK.t("AT ITS HIGHEST  ·  +%s%% %s IDLE" % [_pct(int(b.bonus_bp)), cur], 11, SIG, "mono_bold"), Vector2(0, 62))
		return box
	PK.at(box, PK.t("+%s%%  →  +%s%% %s IDLE" % [_pct(int(b.bonus_bp)), _pct(int(b.next_bonus_bp)), cur], 11, INK, "mono_bold"),
		Vector2(0, 62))
	var gold := int(cost.get("gold", 0))
	var can := int(Game.currency("gold")) >= gold
	var st := SignalKit.stamp_button({"width": 250.0, "height": 104.0, "word": "UPGRADE", "kicker": "LEVEL %d" % (lvl + 1),
		"sub": "%s GOLD" % Kit.format_num(gold), "button_text": "Upgrade", "disabled": not can}, func() -> void:
			var r: Dictionary = Game.district_upgrade(building)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			UI.haptic(24)
			UI.toast("%s: level %d" % [str(b.name), int(r.value.level)], "good")
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0])
			_pick_keeper.call_deferred(building))
	st.name = "Upgrade"
	st.position = Vector2(560 - 250, 6)
	box.add_child(st)
	return box


## The keeper sheet: the building's level and its upgrade, then owned heroines, the side's faction
## first (they double), tap one to place her.
func _pick_keeper(building: int) -> void:
	var dist: Dictionary = Game.district()
	var side := str(dist.side)
	var b: Dictionary = (dist.buildings as Array)[building]
	var ids: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		ids.append(str(h.id))
	ids.sort_custom(func(a: String, c: String) -> bool:
		var ma := DistrictRules.kept_mult(side, str(Game.hero_def(a).get("faction", ""))) > 10000
		var mc := DistrictRules.kept_mult(side, str(Game.hero_def(c).get("faction", ""))) > 10000
		return ma and not mc if ma != mc else a < c)
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 560
	col.add_child(PK.t("%s  ·  +%s%% %s IDLE" % [str(b.name).to_upper(), _pct(int(b.bonus_bp)),
		str(Kit.CURRENCY_SHORT.get(str(b.currency), "")).to_upper()], 12, INK, "mono_bold"))
	var modal_ref: Array[Control] = []
	if bool(b.open):
		col.add_child(_level_block(building, b, modal_ref))
	col.add_child(PK.t("Heroines marked x2 double it.", 13, Color(INK, 0.7), "serif_italic"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	sc.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	if str(b.keeper) != "":
		var clear := Kit.light_button("No keeper", func() -> void:
			Game.district_set_keeper(building, "")
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0]), "close")
		col.add_child(clear)
	for id in ids:
		var card := Control.new()
		card.custom_minimum_size = Vector2(130, 166)
		card.mouse_filter = MOUSE_FILTER_PASS
		var pic := HeroArt.make_portrait(id, 130, Game.equipped_skin(id))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.size = Vector2(130, 130)
		card.add_child(pic)
		var nm := PK.t(str(Game.hero_def(id).get("name", id)).to_upper(), 10, INK, "mono_bold")
		nm.position = Vector2(0, 134)
		nm.size = Vector2(130, 14)
		nm.clip_text = true
		card.add_child(nm)
		if DistrictRules.kept_mult(side, str(Game.hero_def(id).get("faction", ""))) > 10000:
			var x2 := PK.t("x2", 14, PAPER, "mono_bold")
			var tag := ColorRect.new()
			tag.color = SIG
			tag.size = Vector2(34, 22)
			tag.mouse_filter = MOUSE_FILTER_IGNORE
			card.add_child(tag)
			x2.position = Vector2(6, 1)
			card.add_child(x2)
		if id == str(b.keeper):
			var on := ColorRect.new()
			on.color = Color(SIG, 0.25)
			on.size = Vector2(130, 130)
			on.mouse_filter = MOUSE_FILTER_IGNORE
			card.add_child(on)
		var hid := id
		Kit.make_tappable(card, func() -> void:
			var r: Dictionary = Game.district_set_keeper(building, hid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			Kit.sfx("tap")
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0]))
		grid.add_child(card)
	_sheet = UI.popup("Keeper", col, func() -> void: _sheet = null, 640.0, true)
	modal_ref.append(_sheet)
