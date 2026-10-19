extends Control
## Screen "shop", style v2: prototype offers on a light page. A dark header with the page
## tabs (OFFERS: the daily gift, packs and the Moonlit Pass; GEMS: gem packs in a 2-column
## grid). Offer cards are white panels with a dark art band (glyph, name, tag) over the
## rewards, the limit and the price button. Every paid button reads "Test purchase: no
## charge" because this build has no real payments: buying calls Game.buy_offer and shows
## the reward popup. Limits ("Once per account", "2 of 3 left", "Claimed today") and the
## Moonlit Pass days left are shown on each card; the free daily gift is the orange button.
## WARDROBE: cosmetic hero skins (data/skins.json, docs/dev/skins.md), one card per hero with
## her skins: Buy (gems, confirmed), Wear, Equipped, or Coming soon while the skin's art is
## not built into the game yet.

const TAG_COLORS := {
	"best value": Kit.ORANGE, "monthly": Kit.ACCENT, "limited": Kit.EMBER,
	"popular": Kit.EPIC, "free": Kit.GOOD,
}
## Big glyph per offer (falls back to its main reward currency).
const OFFER_ICONS := {
	"daily_gift": "gift", "starter_pack": "chest", "monthly_card": "crown", "scroll_bundle": "scrolls",
}

static var _tab := 0

var _pages: Array[Control] = []
var _offers_list: VBoxContainer
var _gems_grid: GridContainer
var _wardrobe_list: VBoxContainer
var _scrolls: Array[ScrollContainer] = []
var _sig := ""
var _tick := 0.0
var _reset_labels: Array[Label] = []


func setup(params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()
	if params.has("tab"):
		_select_tab(int(params["tab"]))
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))


## Shot/testing helper (params.scroll).
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sc := _scrolls[_tab] if _tab < _scrolls.size() else null
	if is_instance_valid(sc):
		sc.scroll_vertical = px


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _build() -> void:
	var head := Kit.hbox(10)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	var tabs := Kit.tab_strip([{"text": "Offers", "icon": "gift"}, {"text": "Gems", "icon": "gems"},
			{"text": "Wardrobe", "icon": "star"}], _tab, func(i: int) -> void:
		_tab = i
		_show_page(), 164.0)
	head.add_child(tabs)
	head.add_child(Kit.spacer(0, 0, true))
	var tb := Kit.vbox(-4)
	tb.mouse_filter = MOUSE_FILTER_IGNORE
	tb.alignment = BoxContainer.ALIGNMENT_CENTER
	tb.add_child(Kit.label("PROTOTYPE", 16, Kit.INK_DIM, "cond_bold"))
	tb.add_child(Kit.label("TEST SHOP", 26, Kit.GOOD, "cond_bold"))
	head.add_child(tb)
	add_child(head)

	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)

	var col := Kit.vbox(10)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = 10 + Kit.BUTTON_H + 14
	col.offset_left = 16
	col.offset_right = -16
	add_child(col)
	var note := Kit.panel("light_inset", 10)
	var nr := Kit.hbox(10)
	nr.mouse_filter = MOUSE_FILTER_IGNORE
	nr.add_child(Kit.icon("info", 30, Kit.ACCENT_DEEP))
	var nl := Kit.label("Prototype build: every purchase is a free test purchase.", 20, Kit.TEXT_DIM, "bold")
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = SIZE_EXPAND_FILL
	nr.add_child(nl)
	note.add_child(nr)
	col.add_child(note)

	var stack := Control.new()
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(stack)
	_offers_list = Kit.vbox(16)
	_gems_grid = Kit.grid(2, 14)
	_wardrobe_list = Kit.vbox(14)
	for content: Control in [_offers_list, _gems_grid, _wardrobe_list]:
		var m := Kit.margin(content, 2, 0)
		m.add_theme_constant_override("margin_top", 4)
		m.add_theme_constant_override("margin_bottom", 26)
		var sc := Kit.scroll(m)
		sc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		stack.add_child(sc)
		_scrolls.append(sc)
		_pages.append(sc)
	_show_page()


func _show_page() -> void:
	for i in _pages.size():
		_pages[i].visible = i == _tab


func _select_tab(i: int) -> void:
	var tabs := find_child("TabStrip", true, false) as HBoxContainer
	if tabs and i >= 0 and i < tabs.get_child_count():
		(tabs.get_child(i) as Button).button_pressed = true


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		for l in _reset_labels:
			if is_instance_valid(l):
				l.text = "Back in %s" % Kit.format_time(Game.ms_until_reset())


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _offers_list == null:
		return
	var offers := Game.offers()
	var sig := JSON.stringify(offers) + str(Game.monthly_card_days_left()) \
		+ JSON.stringify(Game.state.get("skins", {})) + str(Game.currency("gems"))
	if sig == _sig:
		return
	_sig = sig
	var keep: Array[int] = []
	for sc in _scrolls:
		keep.append(sc.scroll_vertical)
	for box: Control in [_offers_list, _gems_grid, _wardrobe_list]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_reset_labels.clear()
	for o in offers:
		if _is_gem_pack(o):
			_gems_grid.add_child(_pack_tile(o))
		else:
			_offers_list.add_child(_offer_card(o))
	var lines := SkinData.lines()
	for h in HeroData.all():
		if not SkinData.for_hero(str(h.id)).is_empty():
			_wardrobe_list.add_child(_wardrobe_card(h, lines))
	_restore.call_deferred(keep)


func _restore(ys: Array[int]) -> void:
	for i in mini(ys.size(), _scrolls.size()):
		if is_instance_valid(_scrolls[i]):
			_scrolls[i].scroll_vertical = ys[i]


## A plain gems-for-money pack (only gems in the reward, not the pass or a free gift).
static func _is_gem_pack(o: Dictionary) -> bool:
	var r: Dictionary = o.get("reward", {})
	return r.size() == 1 and r.has("gems") and str(o.id) != "monthly_card" and str(o.get("price_label", "")) != "Free"


func _offer_card(o: Dictionary) -> Control:
	var id := str(o.id)
	var tag := str(o.get("tag", ""))
	var accent: Color = TAG_COLORS.get(tag, Kit.ACCENT)
	var available := bool(o.get("available", true))
	var card := Kit.info_panel(0)
	card.name = "Offer_" + id
	var v := Kit.vbox(0)
	card.add_child(v)
	v.add_child(_art_band(str(o.name), tag, accent, str(OFFER_ICONS.get(id, _main_currency(o)))))
	var body := Kit.vbox(10)
	v.add_child(Kit.margin(body, 18, 14))
	var d := Kit.body(str(o.get("description", "")), 21, Kit.TEXT_DIM)
	body.add_child(d)
	body.add_child(Kit.reward_list(o.get("reward", {}), 84.0, true, false, true))
	var bottom := Kit.hbox(12)
	var status := Kit.vbox(4)
	status.size_flags_horizontal = SIZE_EXPAND_FILL
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	var lim := Kit.label(_limit_text(o).to_upper(), 19, Kit.TEXT, "cond_bold")
	lim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(lim)
	if id == "monthly_card":
		var days := int(o.get("days_left", Game.monthly_card_days_left()))
		status.add_child(Kit.label("ACTIVE: %d DAYS LEFT" % days if days > 0 else "NOT ACTIVE YET", 19, Kit.ACCENT_DEEP if days > 0 else Kit.TEXT_DIM, "cond_bold"))
	if not available and str(o.get("period", "")) == "day":
		var rl := Kit.label("Back in %s" % Kit.format_time(Game.ms_until_reset()), 19, Kit.TEXT_DIM, "bold")
		_reset_labels.append(rl)
		status.add_child(rl)
	bottom.add_child(status)
	var bb := _buy_button(o, 300.0)
	bottom.add_child(bb)
	body.add_child(bottom)
	if not available:
		card.modulate = Color(1, 1, 1, 0.78)
	return card


## Dark art band at the top of an offer card: hatching in the tag color, the glyph in a
## glow, the name in condensed caps and the tag.
func _art_band(title: String, tag: String, accent: Color, icon_name: String) -> Control:
	var band := PanelContainer.new()
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", Kit.box(Color("182640"), Color("0b1222"), Color.TRANSPARENT, 6.0, 0, 0))
	band.custom_minimum_size.y = 132
	band.clip_contents = true
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	band.add_child(layer)
	var hatch := Kit.deco("hatch", Vector2(700, 132), Color(accent, 0.16))
	hatch.set("spacing", 12.0)
	hatch.position = Vector2(300, 0)
	layer.add_child(hatch)
	var gl := Kit.glow(accent, 220)
	gl.position = Vector2(-20, -44)
	gl.size = Vector2(220, 220)
	gl.modulate.a = 0.55
	layer.add_child(gl)
	var ic := Kit.icon(icon_name, 104)
	ic.position = Vector2(38, 14)
	ic.size = Vector2(104, 104)
	layer.add_child(ic)
	var tv := Kit.vbox(4)
	tv.mouse_filter = MOUSE_FILTER_IGNORE
	tv.position = Vector2(170, 0)
	tv.size = Vector2(470, 132)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	if tag != "":
		var tg := Kit.tag(tag.to_upper(), accent, Color.WHITE, 18)
		tg.size_flags_horizontal = SIZE_SHRINK_BEGIN
		tv.add_child(tg)
	var n := Kit.label(title.to_upper(), 36, Color.WHITE, "title")
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_constant_override("line_spacing", -8)
	tv.add_child(n)
	tv.add_child(Kit.deco("techline", Vector2(160, 8), Color(1, 1, 1, 0.35)))
	layer.add_child(tv)
	return band


func _pack_tile(o: Dictionary) -> Control:
	var tag := str(o.get("tag", ""))
	var card := Kit.info_panel(12)
	card.name = "Pack_" + str(o.id)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var v := Kit.vbox(6)
	card.add_child(v)
	var art := Panel.new()
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.custom_minimum_size = Vector2(0, 130)
	art.add_theme_stylebox_override("panel", Kit.style("slot"))
	var gems := int(o.get("reward", {}).get("gems", 0))
	var count := 1 if gems < 1000 else (2 if gems < 3000 else 3)
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(PRESET_CENTER)
	art.add_child(holder)
	var gl := Kit.glow(Kit.ACCENT, 170)
	gl.position = Vector2(-85, -85)
	gl.size = Vector2(170, 170)
	gl.modulate.a = 0.4
	holder.add_child(gl)
	for i in count:
		var sz := 84.0 - i * 10.0
		var ic := Kit.icon("gems", sz)
		ic.size = Vector2(sz, sz)
		ic.position = Vector2(-sz * 0.5 + (i - (count - 1) * 0.5) * 34.0, -sz * 0.5 + (8.0 if i > 0 else 0.0))
		holder.add_child(ic)
	if tag != "":
		var tg := Kit.tag(tag.to_upper(), TAG_COLORS.get(tag, Kit.ACCENT), Color.WHITE, 16)
		tg.position = Vector2(8, 8)
		art.add_child(tg)
	v.add_child(art)
	var amt := Kit.hbox(6)
	amt.alignment = BoxContainer.ALIGNMENT_CENTER
	amt.add_child(Kit.label(Kit.format_full(gems), 40, Kit.TEXT, "title"))
	var gl2 := Kit.label("GEMS", 18, Kit.TEXT_DIM, "cond_bold")
	gl2.size_flags_vertical = SIZE_SHRINK_END
	gl2.custom_minimum_size.y = 34
	amt.add_child(gl2)
	v.add_child(amt)
	var nm := Kit.label(str(o.name), 19, Kit.TEXT_DIM, "bold")
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var b := _buy_button(o, 0.0)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_child(b)
	return card


func _buy_button(o: Dictionary, width: float) -> Button:
	var id := str(o.id)
	var available := bool(o.get("available", true))
	var free := not bool(o.get("test_purchase", true))
	var b: Button
	if not available:
		b = Kit.light_button("")
		b.disabled = true
	elif free:
		b = Kit.orange_button("", func() -> void: _buy(id))
	else:
		b = Kit.primary_button("", func() -> void: _buy(id))
	b.name = "Buy_" + id
	b.custom_minimum_size = Vector2(width, 100)
	var v := Kit.vbox(0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_bottom = -4
	var line1 := ""
	var line2 := ""
	if not available:
		line1 = "Claimed" if str(o.get("period", "")) == "day" else "Sold Out"
		line2 = "Come back tomorrow" if str(o.get("period", "")) == "day" else "Limit reached"
	elif free:
		line1 = "Claim Free"
		line2 = "Daily gift"
	else:
		line1 = "Buy  %s" % str(o.get("price_label", ""))
		line2 = "Test purchase: no charge"
	var c1 := Color("9aa1aa") if not available else Color.WHITE
	var a := Kit.label(line1, 28, c1, "extrabold")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var s := Kit.label(line2, 17, Color("9aa1aa") if not available else Color(1, 1, 1, 0.88), "cond_bold")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	b.add_child(v)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	return b


func _limit_text(o: Dictionary) -> String:
	var limit := int(o.get("limit", 0))
	var bought := int(o.get("purchased", 0))
	var period := str(o.get("period", "once"))
	if limit <= 0:
		return "No limit" + ("  ·  bought %d" % bought if bought > 0 else "")
	if period == "day":
		return "%d per day" % limit if limit > 1 else "Once a day"
	if limit == 1:
		return "Once per account" + ("  ·  purchased" if bought >= 1 else "")
	return "%d of %d left" % [maxi(0, limit - bought), limit]


static func _main_currency(o: Dictionary) -> String:
	var r: Dictionary = o.get("reward", {})
	for c: String in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
		if r.has(c):
			return c
	return "gift"


# ------------------------------------------------------------------ wardrobe (skins)

## One hero: her portrait, name and her skins, each with its button.
func _wardrobe_card(h: Dictionary, lines: Dictionary) -> Control:
	var hid := str(h.id)
	var card := Kit.info_panel(12)
	card.name = "Wardrobe_" + hid
	var row := Kit.hbox(14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(row)
	var pic := TextureRect.new()
	pic.texture = Kit.art_crop(hid, 0.75, 1.5, Game.equipped_skin(hid))
	pic.custom_minimum_size = Vector2(120, 160)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size_flags_vertical = SIZE_SHRINK_BEGIN
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var col := Kit.vbox(10)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(Kit.label(str(h.name).to_upper(), 28, Kit.TEXT, "title"))
	for s in Game.skins_for(hid):
		col.add_child(_skin_row(s, lines))
	return card


func _skin_row(s: Dictionary, lines: Dictionary) -> Control:
	var r := Kit.hbox(10)
	r.name = "Skin_" + str(s.id)
	if bool(s.get("installed", false)):
		var pic := HeroArt.make_portrait(str(s.hero), 96, str(s.id))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.size_flags_vertical = SIZE_SHRINK_CENTER
		r.add_child(pic)
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.add_child(Kit.label(str(s.name), 23, Kit.TEXT, "extrabold"))
	info.add_child(Kit.label(("%s  ·  %s" % [lines.get(str(s.line), str(s.line)), SkinData.tier_name(str(s.tier))]).to_upper(),
		16, Kit.ACCENT_DEEP, "cond_bold"))
	info.add_child(Kit.body(str(s.description), 17, Kit.TEXT_DIM))
	r.add_child(info)
	r.add_child(_skin_button(s))
	return r


func _skin_button(s: Dictionary) -> Button:
	var sid := str(s.id)
	var hid := str(s.hero)
	var price := int(s.price_gems)
	var b: Button
	if bool(s.equipped):
		b = Kit.light_button("Equipped")
		b.disabled = true
	elif bool(s.owned):
		b = Kit.secondary_button("Wear", func() -> void: _wear_skin(hid, sid))
	elif not bool(s.get("installed", false)):
		b = Kit.light_button("Coming soon")
		b.disabled = true
	else:
		b = Kit.cost_button("Buy", "gems", price, func() -> void: _buy_skin(sid), "primary",
			Game.currency("gems") >= price)
	b.name = "SkinBtn_" + sid
	b.custom_minimum_size = Vector2(196, 88)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	return b


func _buy_skin(sid: String) -> void:
	var sd := SkinData.get_def(sid)
	if sd.is_empty():
		return
	UI.confirm("Buy %s for %s gems? Skins are cosmetic: no stat changes." % [sd.name, Kit.format_full(int(sd.price_gems))],
		func() -> void:
			var r := Game.buy_skin(sid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "Purchase failed")), "bad")
				return
			UI.toast("%s unlocked. Tap Wear to put it on." % sd.name, "good"),
		Callable(), "Buy")


func _wear_skin(hid: String, sid: String) -> void:
	var r := Game.equip_skin(hid, sid)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Could not equip")), "bad")
		return
	UI.toast("%s now wears %s." % [HeroData.get_def(hid).get("name", hid), SkinData.get_def(sid).get("name", sid)], "good")


func _buy(id: String) -> void:
	var name_s := id
	for o: Dictionary in Game.offers():
		if str(o.id) == id:
			name_s = str(o.name)
	var r := Game.buy_offer(id)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Purchase failed")), "bad")
		return
	UI.show_reward(name_s, r.get("value", {}))
