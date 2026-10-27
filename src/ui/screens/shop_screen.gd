extends Control
## Screen "shop", style v4 "Signal": a printed catalogue in the approved Lobby poster's look
## (docs/dev/ui-style-v4.md). On the paper matte, under the house line and a printed index (01 OFFERS
## / 02 GEMS / 03 WARDROBE), a wall of posters, one per offer: a dark band with a hero as a red
## halftone print, the offer's name set huge in compressed type and two-tone where it crosses the
## band (its tag word in signal), the description and the rewards as a bracketed mono table, the
## limit as micro type, and the buy button as an OG pass stuck over the poster's bottom edge. Every
## paid pass reads "Test purchase: no charge" because this build has no real payments: buying calls
## Game.buy_offer and shows the reward popup. Limits ("Once per account", "2 of 3 left", "Claimed
## today") and the Moonlit Pass days left are printed on each poster (the days as a stamp); the free
## daily gift is a "Claim free" pass. GEMS: the gem packs as smaller posters, two to a row, the
## amount set huge. WARDROBE: cosmetic hero skins (data/skins.json, docs/dev/skins.md), one poster per
## hero with her skins as framed full-colour prints: Buy (gems, confirmed), Wear, Equipped, or Coming
## soon while the skin's art is not built into the game yet.

const PK := preload("res://src/ui/v4/poster_kit.gd")

const INK := PK.INK
const PAPER := PK.PAPER
const SIG := PK.SIGNAL
const TABS: Array[String] = ["Offers", "Gems", "Wardrobe"]
## Glyph on each offer's pass knob (falls back to its main reward currency).
const OFFER_ICONS := {
	"daily_gift": "gift", "starter_pack": "chest", "monthly_card": "crown", "scroll_bundle": "scrolls",
}
## The hero printed on each offer's band (the catalogue's models); others take one by position.
const OFFER_MODELS := {
	"daily_gift": "uriela", "starter_pack": "cassiel", "monthly_card": "noctaire", "scroll_bundle": "mordessa",
	"gems_s": "liora", "gems_m": "vesper", "gems_l": "seraphiel",
}
const MODELS: Array[String] = ["kessa", "imra", "ashra", "sable", "nuriel", "lucen", "brakka", "orrin"]
## What each offer is, as a real object (owner, 2026-10-23: "make the shop more exciting and have
## actual icons"): rendered in Blender (tools/blender/currency_objects.py shop, assets/art/ui/shop/).
const SHOP_OBJECTS := {
	"daily_gift": "gift", "starter_pack": "crate", "monthly_card": "moon", "scroll_bundle": "satchel",
	"gems_s": "pouch", "gems_m": "chest", "gems_l": "reliquary",
}

static var _tab := 0

var _pages: Array[Control] = []
var _offers_list: VBoxContainer
var _gems_grid: GridContainer
var _wardrobe_list: VBoxContainer
var _scrolls: Array[ScrollContainer] = []
var _tabs_box: Control
var _sig := ""
var _tick := 0.0
var _reset_labels: Array[Label] = []
var _w := 720.0


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
	_w = get_viewport_rect().size.x
	PK.matte(self)
	PK.at(self, PK.t("HALO & HORN  ©2026  ·  CATALOGUE Nº 03", 13, INK, "mono_bold"), Vector2(20, 12))
	var proto := PK.t("PROTOTYPE · EVERY PURCHASE IS A FREE TEST PURCHASE", 10, SIG, "mono_bold")
	proto.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	proto.size = Vector2(_w - 40, 14)
	PK.at(self, proto, Vector2(20, 32))
	_tabs_box = Control.new()
	_tabs_box.name = "TabStrip"
	_tabs_box.mouse_filter = MOUSE_FILTER_IGNORE
	_tabs_box.position = Vector2(18, 44)
	_tabs_box.size = Vector2(_w - 36, Kit.BUTTON_H)
	add_child(_tabs_box)
	_build_tabs()
	PK.rule(self, Rect2(18, 44 + Kit.BUTTON_H, _w - 36, 1), Color(INK, 0.55))

	var stack := Control.new()
	stack.mouse_filter = MOUSE_FILTER_PASS
	stack.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stack.offset_top = 44 + Kit.BUTTON_H + 2
	add_child(stack)
	_offers_list = Kit.vbox(46)
	_gems_grid = Kit.grid(2, 14)
	_gems_grid.add_theme_constant_override("v_separation", 40)
	_wardrobe_list = Kit.vbox(40)
	for content: Control in [_offers_list, _gems_grid, _wardrobe_list]:
		var m := Kit.margin(content, 18, 0)
		m.add_theme_constant_override("margin_top", 26)
		m.add_theme_constant_override("margin_bottom", 60 + int(UI.pinned_bottom_inset()))
		var sc := Kit.scroll(m)
		sc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		stack.add_child(sc)
		_scrolls.append(sc)
		_pages.append(sc)
	_show_page()
	PK.grain(self, 0.06)


func _build_tabs() -> void:
	for c in _tabs_box.get_children():
		_tabs_box.remove_child(c)
		c.queue_free()
	if _tab >= _tab_names().size():
		_tab = 0
	var row := PK.index_tabs(_tab_names(), _tab, func(i: int) -> void:
		_tab = i
		_build_tabs.call_deferred()
		_show_page(), _w - 36)
	_tabs_box.add_child(row)


func _show_page() -> void:
	for i in _pages.size():
		_pages[i].visible = i == _tab


## The tabs on show: 18+ mode (nudity) has no Wardrobe, since every hero shows her nude look and
## skins are off (owner, 2026-10-22).
func _tab_names() -> Array[String]:
	return TABS.slice(0, 2) if HeroArt.nudity else TABS


func _select_tab(i: int) -> void:
	if i < 0 or i >= _tab_names().size():
		return
	_tab = i
	_build_tabs()
	_show_page()


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		for l in _reset_labels:
			if is_instance_valid(l):
				l.text = "%s%s" % [str(l.get_meta("prefix", "BACK IN ")), Kit.format_time(Game.ms_until_reset()).to_upper()]
		# Past midnight: today's look, a birthday's prices (the signature carries the day).
		_refresh()


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _offers_list == null:
		return
	var offers := Game.offers()
	var sig := JSON.stringify(offers) + str(Game.monthly_card_days_left()) \
		+ JSON.stringify(Game.state.get("skins", {})) + str(Game.currency("gems")) + str(Game.today())
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
	var n := 0
	var g := 0
	for o in offers:
		if _is_gem_pack(o):
			_gems_grid.add_child(_pack_tile(o, g))
			g += 1
		else:
			n += 1
			_offers_list.add_child(_offer_card(o, n))
	if not HeroArt.nudity:
		var fl := _featured_look()
		if fl:
			_offers_list.add_child(fl)
			_offers_list.move_child(fl, 0)
	var lines := SkinData.lines()
	var k := 0
	for h in HeroData.all():
		if not SkinData.for_hero(str(h.id)).is_empty():
			k += 1
			_wardrobe_list.add_child(_wardrobe_card(h, lines, k))
	_restore.call_deferred(keep)


func _restore(ys: Array[int]) -> void:
	for i in mini(ys.size(), _scrolls.size()):
		if is_instance_valid(_scrolls[i]):
			_scrolls[i].scroll_vertical = ys[i]


## A plain gems-for-money pack (only gems in the reward, not the pass or a free gift).
static func _is_gem_pack(o: Dictionary) -> bool:
	var r: Dictionary = o.get("reward", {})
	return r.size() == 1 and r.has("gems") and str(o.id) != "monthly_card" and str(o.get("price_label", "")) != "Free"


## The hero printed on an offer's band.
static func _model(id: String, n: int) -> String:
	var m := str(OFFER_MODELS.get(id, MODELS[n % MODELS.size()]))
	return m if HeroArt.has_art(m) else ""


# ------------------------------------------------------------------ offers

## One offer as a poster: band with a model's halftone, the name huge and two-tone (its last word in
## signal), the tag and the limit as micro type, the description, the rewards as a bracketed table,
## and the pass stuck over the bottom edge. Heights follow the measured type.
func _offer_card(o: Dictionary, n: int) -> Control:
	var id := str(o.id)
	var tag := str(o.get("tag", ""))
	var available := bool(o.get("available", true))
	var pw := _w - 36
	var bw := 168.0
	var nx := 96.0
	var x := bw + 20
	# The name: as big as fits in two lines across the paper.
	var nm := str(o.name).to_upper()
	var f := Kit.font("compressed")
	var fs := 112
	var lines: Array[String] = PK.wrap_lines(nm, f, fs, pw - nx - 14)
	while fs > 56 and lines.size() > 2:
		fs -= 4
		lines = PK.wrap_lines(nm, f, fs, pw - nx - 14)
	var sep := -int(fs * 0.3)
	var cp := PK.caps(f, fs)
	var name_h := cp.y + (lines.size() - 1) * (f.get_height(fs) + sep)
	# Rewards table rows.
	var rows: Array = []
	var reward: Dictionary = o.get("reward", {})
	for c: String in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
		if reward.has(c):
			rows.append([str(Kit.CURRENCY_NAMES.get(c, c)).to_upper(), Kit.format_full(int(reward[c]))])
	for c: Variant in reward:
		if not str(c) in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
			rows.append([str(c).to_upper(), str(reward[c])])
	if id == "monthly_card":
		rows.append(["THEN EACH DAY", "+100 GEMS"])
	if not rows.is_empty():
		rows[0] = [rows[0][0], rows[0][1], true]
	# A fifth of the type size more: the giant's last line sat on the tag and limit line.
	var y_info := 10.0 + name_h + 14.0 + fs * 0.2
	var y_desc := y_info + 30.0
	var y_tab := y_desc + 46.0
	var tab_end := y_tab + rows.size() * ROW_H
	var ph := maxf(330.0, tab_end + 132.0)
	var wrap := Control.new()
	wrap.name = "Offer_" + id
	wrap.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = Vector2(pw, ph + 52)
	var p := PK.poster(wrap, Rect2(0, 0, pw, ph))
	var band := PK.band(p, Rect2(0, 0, bw, ph), _model(id, n), "", {"from": 0.3, "cell": 6.0, "crop": "portrait"})
	PK.at(band, PK.t("Nº %02d" % n, 12, Color(PAPER, 0.9), "mono_bold"), Vector2(14, 14))
	PK.vt(band, "©2026 HH · OFFER", 10, Color(PAPER, 0.7), Vector2(bw - 8, name_h + 24))
	var last := lines[lines.size() - 1].split(" ")
	var key := last[last.size() - 1]
	last.remove_at(last.size() - 1)
	lines[lines.size() - 1] = (" ".join(last) + " " if not last.is_empty() else "") + "[color=#%s]%s[/color]" % [SIG.to_html(false), key]
	PK.giant(p, "\n".join(lines), fs, [[0.0, bw, PAPER], [bw, pw - bw, INK]], Vector2(nx, 10.0 - cp.x), Vector2(pw + 200, name_h + 80), 0.0, "compressed", sep)
	# Tag and limit, the description, the rewards.
	var ix := x
	if tag != "":
		var tp := SignalKit.pill(tag.to_upper(), 13, SIG, "mono_bold")
		PK.at(p, tp, Vector2(ix, y_info - 2))
		# Measured from the type (the pill's minimum size isn't known yet): the limit line overlapped it.
		ix += Kit.font("mono_bold").get_string_size(tag.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 36.0 + 14.0
	var lim_txt := _limit_text(o).to_upper()
	var days := int(o.get("days_left", Game.monthly_card_days_left()))
	if id == "monthly_card":
		lim_txt += "  ·  " + ("ACTIVE: %d DAYS LEFT" % days if days > 0 else "NOT ACTIVE YET")
	var lim := PK.t(lim_txt, 11, INK, "mono_bold")
	PK.at(p, lim, Vector2(ix, y_info + 2))
	# What it is, as a real object, on the paper's right (clear of the pass below).
	var obj_side := clampf(ph - 120.0 - y_info, 120.0, 190.0)
	var obj := _object(id, obj_side)
	if obj:
		obj.position = Vector2(pw - obj_side - 14.0, y_info - 6.0)
		p.add_child(obj)
	var d := PK.t(str(o.get("description", "")), 12, INK, "mono")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size = Vector2(pw - x - 20 - (obj_side if obj else 0.0), 40)
	d.custom_minimum_size.x = d.size.x
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	PK.at(p, d, Vector2(x, y_desc))
	_reward_rows(p, reward, Vector2(x, y_tab), 270.0, id == "monthly_card")
	if id == "monthly_card":
		var st := PK.stamp_disc(wrap, Vector2(bw - 70, ph - 150), 112, "MOONLIT · PASS · DAYS · ", "%d" % days if days > 0 else "—", 0.1)
		st.name = "Days"
	if not available and str(o.get("period", "")) == "day":
		var rl := PK.t("BACK IN %s" % Kit.format_time(Game.ms_until_reset()).to_upper(), 11, SIG, "mono_bold")
		_reset_labels.append(rl)
		PK.at(p, rl, Vector2(x, ph - 26))
	# The pass, stuck over the poster's bottom edge (its top clears the table).
	var bb2 := _buy_button(o, 330.0)
	bb2.position = Vector2(pw - 330 - 6, ph - 120)
	bb2.rotation = -0.02 if n % 2 == 0 else 0.015
	wrap.add_child(bb2)
	if not available:
		p.modulate = Color(1, 1, 1, 0.82)
	return wrap


const ROW_H := 34.0


## An offer's contents: each currency's real object, its name and the amount, on ruled lines.
func _reward_rows(p: Control, reward: Dictionary, at: Vector2, width: float, monthly: bool) -> void:
	var y := at.y
	var first := true
	for c: String in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
		if not reward.has(c):
			continue
		var ic := Kit.currency_icon(c, 30)
		ic.position = Vector2(at.x, y)
		ic.size = Vector2(30, 30)
		p.add_child(ic)
		PK.at(p, PK.t(str(Kit.CURRENCY_NAMES.get(c, c)).to_upper(), 11, Color(INK, 0.7), "mono_bold"), Vector2(at.x + 38, y + 8))
		var amt := PK.t("+%s" % Kit.format_full(int(reward[c])), 18 if first else 15, SIG if first else INK, "mono_bold")
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amt.size = Vector2(120, 24)
		PK.at(p, amt, Vector2(at.x + width - 120, y + 3))
		PK.rule(p, Rect2(at.x, y + ROW_H - 3, width, 1), Color(INK, 0.15))
		y += ROW_H
		first = false
	if monthly:
		PK.at(p, PK.t("THEN EACH DAY  ·  +100 GEMS FOR 30 DAYS", 11, SIG, "mono_bold"), Vector2(at.x, y + 6))


## An offer's real object (or null): a TextureRect `side` px square.
static func _object(id: String, side: float) -> TextureRect:
	var path := "res://assets/art/ui/shop/%s.png" % str(SHOP_OBJECTS.get(id, ""))
	if not SHOP_OBJECTS.has(id) or not ResourceLoader.exists(path):
		return null
	var t := TextureRect.new()
	t.name = "Object"
	t.texture = load(path)
	t.mouse_filter = MOUSE_FILTER_IGNORE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = Vector2(side, side)
	return t


## The buy pass (named Buy_<id>): "Claim free" for the daily gift, the price and "Test purchase:
## no charge" for paid offers, a dead pass when claimed or sold out.
func _buy_button(o: Dictionary, width: float) -> Button:
	var id := str(o.id)
	var available := bool(o.get("available", true))
	var free := not bool(o.get("test_purchase", true))
	# Buying is a price tag (the button family); the daily gift is an ink stamp tag in signal.
	var spec := {"width": width, "height": 150.0, "horizontal": true}
	if not available:
		var daily := str(o.get("period", "")) == "day"
		spec.merge({"kicker": "DAILY // CLAIMED" if daily else "OFFER // SOLD OUT", "price": "CLAIMED" if daily else "SOLD OUT",
			"note": "Come back tomorrow" if daily else "Limit reached", "action": "DONE", "disabled": true})
	elif free:
		spec.merge({"kicker": "FROM THE CHOIR", "price": "FREE", "note": "Daily gift", "action": "CLAIM",
			"fill": "signal", "button_text": "Claim free"})
	else:
		spec.merge({"kicker": "BUY // %s" % str(o.name).to_upper(), "price": str(o.get("price_label", "")),
			"note": "Test purchase: no charge", "action": "BUY", "info": "TEST BUILD · NO PAYMENT"})
	var b := SignalKit.tag_button(spec, func() -> void: _buy(id))
	b.name = "Buy_" + id
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


# ------------------------------------------------------------------ today's look

## TODAY'S LOOK, the first poster in the offers: one heroine in a look the player doesn't own yet
## (installed art), a new one each day, in full colour across the poster; her name huge, the look's
## line and tier, its price (her birthday sale when it applies) and the time it stays; a tap opens
## her in that look full screen (the gallery, where BUY is).
func _featured_look() -> Control:
	var pool: Array = []
	for h in HeroData.all():
		for s: Dictionary in Game.skins_for(str(h.id)):
			if bool(s.get("installed", false)) and not bool(s.owned):
				pool.append(s)
	if pool.is_empty():
		return null
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var s: Dictionary = pool[posmod(Game.today() * 7, pool.size())]
	var hid := str(s.hero)
	var sid := str(s.id)
	var pw := _w - 36
	var ph := 560.0
	var wrap := Control.new()
	wrap.name = "TodaysLook"
	wrap.mouse_filter = MOUSE_FILTER_PASS
	wrap.custom_minimum_size = Vector2(pw, ph + 60)
	var p := PK.poster(wrap, Rect2(0, 0, pw, ph))
	var bw := 168.0
	var band := PK.band(p, Rect2(0, 0, bw, ph), hid, sid, {"from": 0.2, "cell": 6.0, "crop": "portrait"})
	PK.at(band, PK.t("TODAY'S\nLOOK", 22, PAPER, "compressed"), Vector2(14, 14))
	# (Down the band's left edge: her name crosses its right edge.)
	PK.vt(band, "©2026 HH · WARDROBE · ONE DAY ONLY", 10, Color(PAPER, 0.7), Vector2(24, 96))
	var name_up := str(Game.hero_def(hid).get("name", hid)).to_upper()
	var f := Kit.font("compressed")
	var fs := 120
	while fs > 60 and f.get_string_size(name_up, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > pw - bw - 30.0:
		fs -= 4
	var cp := PK.caps(f, fs)
	# Her name huge behind her (two-tone across the band).
	PK.giant(p, name_up, fs, [[0.0, bw, PAPER], [bw, pw - bw, INK]], Vector2(bw - 50, 70.0 - cp.x), Vector2(pw + 100, fs * 1.4), 0.0)
	# Her, full colour, big on the paper's right, in front of her name.
	# (her live figure, the rig, as on her page: she breathes)
	var box := Control.new()
	box.name = "Figure"
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.clip_contents = true
	box.position = Vector2(bw, 0)
	box.size = Vector2(pw - bw, ph)
	p.add_child(box)
	var anchor := Node2D.new()
	box.add_child(anchor)
	var sprite := HeroArt.make_sprite(hid, sid)
	anchor.add_child(sprite)
	HeroArt.fit_sprite(sprite, anchor, Rect2(pw * 0.46 - bw, 40.0, pw - pw * 0.46, ph * 0.96), pw * 0.77 - bw, true)
	# The look, its line, its description, down the left column under her name.
	var x := bw + 18.0
	var col_w := 220.0
	var y := 70.0 + (cp.y - cp.x) + 18.0
	var ln := PK.t(str(s.name).to_upper(), 22, INK, "wide_black")
	Kit.fit_label(ln, col_w, 22, 14)
	PK.at(p, ln, Vector2(x, y))
	var line_name := str(SkinData.lines().get(str(s.line), str(s.line)))
	PK.at(p, PK.t(("%s  ·  %s" % [line_name, SkinData.tier_name(str(s.tier))]).to_upper(), 11, SIG, "mono_bold"), Vector2(x, y + 34))
	# The description fills the room down to the price and no further: a long one sets smaller, then
	# loses its last lines.
	var avail := (ph - 254.0) - (y + 58.0)
	var mf := Kit.font("mono")
	var dfs := 12
	while dfs > 10 and mf.get_multiline_string_size(str(s.description), HORIZONTAL_ALIGNMENT_LEFT, col_w, dfs).y > avail:
		dfs -= 1
	var d := PK.t(str(s.description), dfs, INK, "mono")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size = Vector2(col_w, avail)
	d.custom_minimum_size.x = col_w
	d.max_lines_visible = maxi(1, int(avail / (mf.get_height(dfs) + 1.0)))
	d.clip_text = true
	PK.at(p, d, Vector2(x, y + 58))
	# The price (her birthday sale when it applies) and how long the look stays.
	var price := int(s.price_gems)
	var gi := Kit.currency_icon("gems", 44)
	gi.position = Vector2(x, ph - 236)
	gi.size = Vector2(44, 44)
	p.add_child(gi)
	PK.at(p, PK.t(Kit.format_full(price), 46, INK, "compressed"), Vector2(x + 50, ph - 246))
	if bool(s.get("sale", false)):
		PK.at(p, PK.t("HER BIRTHDAY  ·  WAS %s" % Kit.format_full(int(s.full_price_gems)), 11, SIG, "mono_bold"), Vector2(x, ph - 186))
	var rl := PK.t("CHANGES IN %s" % Kit.format_time(Game.ms_until_reset()).to_upper(), 11, Color(INK, 0.7), "mono_bold")
	_reset_labels.append(rl)
	rl.set_meta("prefix", "CHANGES IN ")
	PK.at(p, rl, Vector2(x, ph - 168))
	var spec := {"width": 330.0, "kicker": "TODAY'S LOOK", "title": "VIEW", "sub": "FULL SCREEN · BUY",
		"action": "SEE HER  >>>", "icon": "gems"}
	var look_pass := SignalKit.pass_button(spec, func() -> void: UI.go("gallery", {"hero_id": hid, "skin": sid}))
	look_pass.name = "LookPass"
	look_pass.position = Vector2(bw - 8, ph - 136)
	look_pass.rotation = -0.02
	wrap.add_child(look_pass)
	# The whole poster opens her too.
	var hit := Button.new()
	hit.name = "LookHit"
	hit.theme_type_variation = &"BareButton"
	hit.focus_mode = FOCUS_NONE
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.position = Vector2(pw * 0.48, 0)
	hit.size = Vector2(pw * 0.52, ph)
	hit.pressed.connect(func() -> void:
		Kit.sfx("tap")
		UI.go("gallery", {"hero_id": hid, "skin": sid}))
	wrap.add_child(hit)
	return wrap


# ------------------------------------------------------------------ gems

## A gem pack as a small poster: a narrow band with a model's halftone, the amount set huge and
## two-tone, the pack's name and tag, the pass under it.
func _pack_tile(o: Dictionary, n: int) -> Control:
	var id := str(o.id)
	var tag := str(o.get("tag", ""))
	var gems := int(o.get("reward", {}).get("gems", 0))
	var pw := floorf((_w - 36 - 14) * 0.5)
	var ph := 430.0
	var bw := 74.0
	var wrap := Control.new()
	wrap.name = "Pack_" + id
	wrap.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = Vector2(pw, ph + 126)
	wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	var p := PK.poster(wrap, Rect2(0, 0, pw, ph))
	var band := PK.band(p, Rect2(0, 0, bw, ph), _model(id, n + 4), "", {"from": 0.0, "cell": 5.0, "crop": "portrait"})
	var amount := Kit.format_full(gems)
	var f := Kit.font("compressed")
	var fs := 120
	while fs > 60 and f.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > pw - 40:
		fs -= 4
	var cp := PK.caps(f, fs)
	PK.giant(p, amount, fs, [[0.0, bw, PAPER], [bw, pw - bw, INK]], Vector2(40, 18.0 - cp.x), Vector2(pw + 100, fs * 1.4), 0.0)
	var y := 18.0 + (cp.y - cp.x) + 16.0
	PK.vt(band, "©2026 HH · GEMS Nº %02d" % (n + 1), 10, Color(PAPER, 0.8), Vector2(bw - 10, y))
	PK.at(p, PK.t("GEMS", 30, SIG, "wide_black"), Vector2(bw + 14, y))
	PK.at(p, PK.t(str(o.name).to_upper(), 11, INK, "mono_bold"), Vector2(bw + 14, y + 42))
	PK.at(p, PK.t(_limit_text(o).to_upper(), 10, Color(INK, 0.7), "mono"), Vector2(bw + 14, y + 60))
	if tag != "":
		PK.at(p, SignalKit.pill(tag.to_upper(), 12, SIG, "mono_bold"), Vector2(bw + 14, y + 82))
	# The pack itself (a pouch, a chest, a reliquary), bigger as the pack grows.
	var side := minf(pw - bw - 10.0, ph - 52.0 - (y + 112.0))
	var obj := _object(id, side)
	if obj:
		obj.position = Vector2(bw + (pw - bw - side) * 0.5, y + 108.0)
		p.add_child(obj)
	var b := _buy_button(o, pw - 4)
	b.position = Vector2(2, ph - 52)
	b.rotation = 0.012 if n % 2 == 0 else -0.012
	wrap.add_child(b)
	return wrap


# ------------------------------------------------------------------ wardrobe (skins)

## One hero's wardrobe as a poster: a band with her halftone (in the look she wears), her name huge
## and two-tone, and her skins as framed prints with their buttons.
func _wardrobe_card(h: Dictionary, lines: Dictionary, n: int) -> Control:
	var hid := str(h.id)
	var skins: Array = Game.skins_for(hid)
	var pw := _w - 36
	var bw := 128.0
	var row_h := 150.0
	var head := 14.0 + PK.caps(Kit.font("compressed"), 118).y - PK.caps(Kit.font("compressed"), 118).x + 44.0
	var ph := head + skins.size() * row_h + 14.0
	var wrap := Control.new()
	wrap.name = "Wardrobe_" + hid
	wrap.mouse_filter = MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = Vector2(pw, ph + 8)
	var p := PK.poster(wrap, Rect2(0, 0, pw, ph))
	var band := PK.band(p, Rect2(0, 0, bw, ph), hid, Game.equipped_skin(hid), {"from": 0.12, "cell": 6.0, "crop": "portrait"})
	PK.at(band, PK.t("Nº %02d" % n, 12, Color(PAPER, 0.9), "mono_bold"), Vector2(12, 12))
	var sig := PK.t(str(h.name), 34, PAPER, "serif_italic")
	Kit.fit_label(sig, bw - 20, 34, 18)
	PK.at(band, sig, Vector2(10, ph - 50))
	var nm := str(h.name).to_upper()
	var cp := PK.caps(Kit.font("compressed"), 118)
	PK.giant(p, "%s [color=#%s]·[/color]" % [nm, SIG.to_html(false)], 118, [[0.0, bw, PAPER], [bw, pw - bw, INK]], Vector2(70, 14.0 - cp.x), Vector2(pw + 200, 160), 0.0)
	PK.at(p, PK.t("WARDROBE  ·  %d LOOK%s  ·  COSMETIC, NO STAT CHANGES" % [skins.size(), "" if skins.size() == 1 else "S"], 10, INK, "mono_bold"), Vector2(bw + 16, head - 24))
	PK.rule(p, Rect2(bw + 16, head - 6, pw - bw - 32, 1), Color(INK, 0.5))
	var y := head
	for s: Dictionary in skins:
		p.add_child(_skin_row(s, lines, Rect2(bw + 16, y, pw - bw - 32, row_h - 10)))
		y += row_h
	return wrap


## One skin: its framed full-colour print (or a "not printed yet" frame), name, line and tier,
## description and its button.
func _skin_row(s: Dictionary, lines: Dictionary, r: Rect2) -> Control:
	var row := Control.new()
	row.name = "Skin_" + str(s.id)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.position = r.position
	row.size = r.size
	var fr := Rect2(0, 6, 112, r.size.y - 12)
	var bg := ColorRect.new()
	bg.color = Color("dcdbd4")
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.position = fr.position
	bg.size = fr.size
	row.add_child(bg)
	if bool(s.get("installed", false)):
		# The skin's own portrait print (small files: the wall holds every skin).
		var pic := HeroArt.make_portrait(str(s.hero), fr.size.x, str(s.id)) as TextureRect
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.position = fr.position
		pic.size = fr.size
		row.add_child(pic)
		# Tap the print: her in this look, full screen in the gallery (zoom, swipe, buy).
		var view := PK.t("VIEW", 9, PAPER, "mono_bold")
		var vt := ColorRect.new()
		vt.color = Color(INK, 0.85)
		vt.mouse_filter = MOUSE_FILTER_IGNORE
		vt.position = fr.position + Vector2(0, fr.size.y - 16)
		vt.size = Vector2(40, 16)
		row.add_child(vt)
		view.position = vt.position + Vector2(7, 1)
		row.add_child(view)
		var hit := Button.new()
		hit.name = "View_" + str(s.id)
		hit.theme_type_variation = &"BareButton"
		hit.focus_mode = FOCUS_NONE
		hit.mouse_filter = MOUSE_FILTER_PASS
		hit.position = fr.position
		hit.size = fr.size
		var hid := str(s.hero)
		var sid := str(s.id)
		hit.pressed.connect(func() -> void:
			Kit.sfx("tap")
			UI.go("gallery", {"hero_id": hid, "skin": sid}))
		row.add_child(hit)
	else:
		var np := PK.t("NOT\nPRINTED\nYET", 11, Color(INK, 0.55), "mono_bold")
		np.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		np.position = fr.position
		np.size = fr.size
		row.add_child(np)
	PK.hairbox(row, fr, Color(INK, 0.7))
	var x := fr.end.x + 14
	var bwid := 168.0
	var tw := r.size.x - x - bwid - 8
	var nl := PK.t(str(s.name).to_upper(), 18, INK, "wide_black")
	Kit.fit_label(nl, tw, 18, 11)
	PK.at(row, nl, Vector2(x, 8))
	PK.at(row, PK.t(("%s  ·  %s" % [lines.get(str(s.line), str(s.line)), SkinData.tier_name(str(s.tier))]).to_upper(), 10, SIG, "mono_bold"), Vector2(x, 34))
	var d := PK.t(str(s.description), 11, INK, "mono")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size = Vector2(tw, r.size.y - 60)
	d.custom_minimum_size.x = tw
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	d.clip_text = true
	PK.at(row, d, Vector2(x, 54))
	var b := _skin_button(s, bwid)
	b.position = Vector2(r.size.x - bwid, (r.size.y - b.size.y) * 0.5)
	row.add_child(b)
	return row


func _skin_button(s: Dictionary, width: float) -> Button:
	var sid := str(s.id)
	var hid := str(s.hero)
	var price := int(s.price_gems)
	var b: Button
	var sz := Vector2(width, 96)
	if bool(s.equipped):
		b = PK.plate_button("Equipped", Callable(), {"size": sz, "kicker": "WORN NOW", "text_size": 18, "disabled": true})
	elif bool(s.owned):
		b = PK.plate_button("Wear", func() -> void: _wear_skin(hid, sid), {"size": sz, "kicker": "OWNED", "text_size": 22, "screws": true})
	elif not bool(s.get("installed", false)):
		b = PK.plate_button("Coming soon", Callable(), {"size": sz, "kicker": "NOT PRINTED", "text_size": 15, "disabled": true})
	else:
		var ok := Game.currency("gems") >= price
		var kick := "BIRTHDAY  −%d%%" % roundi(100.0 - 100.0 * price / maxf(float(s.get("full_price_gems", price)), 1.0)) if bool(s.get("sale", false)) else "GEMS"
		b = PK.plate_button("Buy %s" % Kit.format_full(price), func() -> void: _buy_skin(sid), {"size": sz, "preset": "signal",
			"kicker": kick, "icon": "gems", "text_size": 18, "disabled": not ok})
	b.name = "SkinBtn_" + sid
	return b


func _buy_skin(sid: String) -> void:
	var sd := SkinData.get_def(sid)
	if sd.is_empty():
		return
	UI.confirm("Buy %s for %s gems? Skins are cosmetic: no stat changes." % [sd.name, Kit.format_full(Game.skin_price(sid))],
		func() -> void:
			var r := Game.buy_skin(sid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "Purchase failed")), "bad")
				return
			UI.unveil(str(sd.get("hero", "")), sid, func() -> void: UI.toast("%s is yours. Tap Wear to put it on." % sd.name, "good")),
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
