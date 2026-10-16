extends Control
## Screen "summon": the gacha portal. Shows the banner with its three featured Legendaries,
## the pity counter, a Rates panel (exact odds from Game.banner(), pity, 10-pull and duplicate
## rules), the free daily pull and x1 / x10 summons (scrolls first, then gems; disabled with a
## reason when unaffordable; gem spending asks first).
##
## Summoning plays a full-screen sequence with the chrome hidden: the portal charges up (its
## color hints at the best result), a flash, then cards flip one by one (tap to reveal all).
## Epic cards glow violet; a Legendary bursts in gold with its own sound, a haptic and a
## full-body showcase. Results show NEW or "+N shards"; then Summon again or Done.
##
## Shot params: rates: true (open the odds), pull: 1|10 (summon right away), skip: true
## (jump straight to the results).

const CHARGE_TIME := 1.9
const REVEAL_GAP := 0.2
const SHOWCASE_TIME := 2.4
const DARK_INK := Color("3d2306")
const SHORT_RED := Color("ff6a50")
const RARITY_ORDER := {"rare": 0, "epic": 1, "legendary": 2}

var _banner: Dictionary = {}
var _backdrop: SummonBackdrop
var _main: VBoxContainer
var _featured: Control
var _feat_nodes: Array[Dictionary] = []
var _pity_label: Label
var _pity_bar: ProgressBar
var _free_slot: VBoxContainer
var _buy_row: HBoxContainer
var _reason: Button
var _free_timer_label: Label
var _tick := 0.0

# Summon sequence state.
var _overlay: Control
var _phase := ""
var _count := 1
var _results: Array = []
var _portal: PortalFx
var _charge_t := 0.0
var _flash: ColorRect
var _cards: Array[Control] = []
var _revealed := 0
var _reveal_wait := 0.0
var _showcase: Control
var _showcase_left := 0.0
var _skip_all := false
var _grid_box: Control
var _results_box: VBoxContainer
var _hint_label: Label


func setup(params: Dictionary) -> void:
	_banner = Game.banner()
	_build()
	Game.changed.connect(_refresh)
	_refresh()
	if bool(params.get("rates", false)):
		_open_rates.call_deferred()
	if params.has("pull"):
		_shot_pull.call_deferred(int(params["pull"]), bool(params.get("skip", false)))


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _shot_pull(count: int, skip: bool) -> void:
	await get_tree().process_frame
	_do_summon(count, count == 1 and Game.free_pull_available())
	if skip and _phase != "":
		_start_reveal()
		_reveal_everything()


# ------------------------------------------------------------------ build

func _build() -> void:
	_backdrop = SummonBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)

	_main = Kit.vbox(12)
	_main.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_main.offset_left = 20
	_main.offset_right = -20
	_main.offset_top = 10
	_main.offset_bottom = -14
	add_child(_main)

	var title := Kit.title(str(_banner.get("name", "Summon")), 44)
	_main.add_child(title)
	var sub := Kit.label("Standard Portal  ·  every hero can answer", 22, Kit.INK, "bold", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main.add_child(sub)

	_featured = Control.new()
	_featured.size_flags_vertical = SIZE_EXPAND_FILL
	_featured.custom_minimum_size.y = 260
	_featured.mouse_filter = MOUSE_FILTER_IGNORE
	_featured.resized.connect(_layout_featured)
	_main.add_child(_featured)
	_build_featured()

	# Pity + rates.
	var pity := Kit.panel("glass", 16)
	var prow := Kit.hbox(14)
	pity.add_child(prow)
	var pv := Kit.vbox(6)
	pv.size_flags_horizontal = SIZE_EXPAND_FILL
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_pity_label = Kit.label("", 24, Kit.GOLD_LIGHT, "extrabold")
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_pity_label)
	_pity_bar = Kit.progress_bar(0, 1, Kit.LEGENDARY, 22, "")
	pv.add_child(_pity_bar)
	prow.add_child(pv)
	var rates := Kit.secondary_button("Rates", _open_rates, "info")
	rates.custom_minimum_size = Vector2(170, 88)
	rates.size_flags_vertical = SIZE_SHRINK_CENTER
	prow.add_child(rates)
	_main.add_child(pity)

	_free_slot = Kit.vbox(0)
	_main.add_child(_free_slot)
	_buy_row = Kit.hbox(14)
	_main.add_child(_buy_row)
	_reason = Button.new()
	_reason.theme_type_variation = &"BareButton"
	_reason.focus_mode = FOCUS_NONE
	_reason.mouse_filter = MOUSE_FILTER_PASS
	_reason.custom_minimum_size.y = 88
	_reason.add_theme_font_override("font", Kit.font("extrabold"))
	_reason.add_theme_font_size_override("font_size", 22)
	_reason.add_theme_color_override("font_color", SHORT_RED)
	_reason.add_theme_color_override("font_hover_color", SHORT_RED)
	_reason.add_theme_color_override("font_pressed_color", SHORT_RED)
	_reason.pressed.connect(func() -> void:
		UI.sfx("tap")
		UI.go("shop"))
	_reason.visible = false
	_main.add_child(_reason)


func _build_featured() -> void:
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	var legends: Array = pool.get("legendary", [])
	# Draw order: sides first, the centre hero in front.
	var order: Array[int] = []
	if legends.size() >= 3:
		order = [1, 2, 0]
	else:
		for i in legends.size():
			order.append(i)
	for k in order:
		var id := str(legends[k])
		var d := Game.hero_def(id)
		var fc := HeroArt.faction_color(str(d.get("faction", "celestial")))
		var glow := Kit.glow(fc, 300)
		glow.modulate.a = 0.5
		_featured.add_child(glow)
		var art := TextureRect.new()
		art.texture = HeroArt.texture(id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = MOUSE_FILTER_IGNORE
		if k != 0:
			art.modulate = Color(0.82, 0.8, 0.9)
		_featured.add_child(art)
		var plate := Kit.vbox(0)
		plate.mouse_filter = MOUSE_FILTER_IGNORE
		var nm := Kit.label(str(d.get("name", id)), 30 if k == 0 else 25, Kit.GOLD_LIGHT, "title", 6)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plate.add_child(nm)
		var fr := Kit.hbox(4)
		fr.alignment = BoxContainer.ALIGNMENT_CENTER
		fr.mouse_filter = MOUSE_FILTER_IGNORE
		fr.add_child(Kit.faction_icon(str(d.get("faction", "")), 26))
		fr.add_child(Kit.label(str(Kit.ROLE_NAMES.get(str(d.get("role", "")), "")), 19, Kit.INK, "extrabold", 4))
		plate.add_child(fr)
		_featured.add_child(plate)
		var hit := Control.new()
		hit.mouse_filter = MOUSE_FILTER_PASS
		_featured.add_child(hit)
		Kit.make_tappable(hit, func() -> void: UI.go("hero_detail", {"hero_id": id}))
		_feat_nodes.append({"slot": k, "glow": glow, "art": art, "plate": plate, "hit": hit})
	var tg := Kit.tag("FEATURED LEGENDARIES", Kit.LEGENDARY, DARK_INK, 20)
	tg.name = "FeaturedTag"
	_featured.add_child(tg)


func _layout_featured() -> void:
	var w := _featured.size.x
	var h := _featured.size.y
	if h <= 0.0:
		return
	var cx := w * 0.5
	for n in _feat_nodes:
		var k := int(n.slot)
		var fh := (h - 34.0) * (1.0 if k == 0 else 0.84)
		var fw := fh * 0.5
		var x := cx + (0.0 if k == 0 else (-1.0 if k == 1 else 1.0) * w * 0.3)
		var top := h - fh - (0.0 if k == 0 else h * 0.02)
		var art := n.art as Control
		art.position = Vector2(x - fw * 0.5, top)
		art.size = Vector2(fw, fh)
		var glow := n.glow as Control
		var gs := fh * 0.75
		glow.size = Vector2(gs, gs)
		glow.position = Vector2(x - gs * 0.5, top + fh * 0.12)
		var plate := n.plate as Control
		var pw := 230.0
		plate.size = Vector2(pw, 64)
		plate.position = Vector2(x - pw * 0.5, h - 66.0 + (0.0 if k == 0 else -h * 0.03))
		var hit := n.hit as Control
		hit.position = art.position + Vector2(fw * 0.15, fh * 0.05)
		hit.size = Vector2(fw * 0.7, fh * 0.9)
	var tg := _featured.get_node_or_null("FeaturedTag") as Control
	if tg:
		var ts := tg.get_combined_minimum_size()
		tg.position = Vector2(cx - ts.x * 0.5, 4)
	_backdrop.portal_center = Vector2(cx, _featured.position.y + h * 0.5) + _main.position
	_backdrop.queue_redraw()


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _main == null:
		return
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(Game.pity_count())
	var left := maxi(1, pity_max - pity)
	_pity_label.text = "Legendary guaranteed within %d pull%s" % [left, "" if left == 1 else "s"]
	Kit.set_progress(_pity_bar, pity, pity_max, "%d / %d" % [pity, pity_max], false)

	for c in _free_slot.get_children():
		c.queue_free()
	_free_timer_label = null
	var guide := Guide.step() == "summon"
	if Game.free_pull_available():
		var free := Kit.primary_button("Free Daily Summon", func() -> void: _do_summon(1, true), "gift")
		free.custom_minimum_size.y = 96
		Kit.set_dot(free, true, 26, Vector2(12, 12))
		_free_slot.add_child(free)
		Guide.mark(free, guide)
		guide = false
	else:
		var row := Kit.card(12)
		var h := Kit.hbox(10)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(Kit.icon("gift", 34, Color(1, 1, 1, 0.6)))
		_free_timer_label = Kit.label("", 22, Kit.INK_DIM, "extrabold")
		h.add_child(_free_timer_label)
		row.add_child(h)
		_free_slot.add_child(row)
		_update_free_timer()

	for c in _buy_row.get_children():
		c.queue_free()
	var p1 := _price(1)
	var p10 := _price(10)
	var b1 := Kit.cost_button("Summon x1", str(p1.currency), int(p1.amount), func() -> void: _try_summon(1), "secondary", bool(p1.ok))
	var b10 := Kit.cost_button("Summon x10", str(p10.currency), int(p10.amount), func() -> void: _try_summon(10), "primary", bool(p10.ok))
	for b: Button in [b1, b10]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 108
		_buy_row.add_child(b)
	b1.disabled = not bool(p1.ok)
	b10.disabled = not bool(p10.ok)
	# After the free pull, point at the 10-pull the starting scrolls pay for.
	Guide.mark(b10, guide and str(p10.currency) == "scrolls", 0)
	if not bool(p1.ok) or not bool(p10.ok):
		_reason.visible = true
		var need := "Need %s gems or %d scroll%s" % [Kit.format_full(int(_banner.cost_one)), int(_banner.scroll_cost_one), "" if int(_banner.scroll_cost_one) == 1 else "s"] if not bool(p1.ok) \
			else "x10 needs %s gems or %d scrolls" % [Kit.format_full(int(_banner.cost_ten)), int(_banner.scroll_cost_ten)]
		_reason.text = need + ".  Get more in the Shop  >"
	else:
		_reason.visible = false


## Price of a summon: scrolls when the player has enough, else gems. ok = affordable.
func _price(count: int) -> Dictionary:
	var sc := int(_banner.scroll_cost_one if count == 1 else _banner.scroll_cost_ten)
	var gc := int(_banner.cost_one if count == 1 else _banner.cost_ten)
	if Game.currency("scrolls") >= sc:
		return {"currency": "scrolls", "amount": sc, "ok": true}
	return {"currency": "gems", "amount": gc, "ok": Game.currency("gems") >= gc}


func _update_free_timer() -> void:
	if _free_timer_label and is_instance_valid(_free_timer_label):
		_free_timer_label.text = "Free summon used today. Next in %s" % Kit.format_time(Game.ms_until_reset())


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_free_timer()
		if _phase == "" and _free_timer_label != null and Game.free_pull_available():
			_refresh()
	_step_sequence(delta)


# ------------------------------------------------------------------ rates

func _open_rates() -> void:
	var v := Kit.vbox(16)
	v.custom_minimum_size.x = 560
	var rates: Dictionary = _banner.get("rates", {})
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	v.add_child(Kit.body("Every pull rolls a rarity first, then one hero of that rarity with equal chance.", 22, Kit.INK_DIM))
	for r: String in ["legendary", "epic", "rare"]:
		var card := Kit.panel("inset", 14)
		var cv := Kit.vbox(8)
		card.add_child(cv)
		var head := Kit.hbox(10)
		head.add_child(Kit.rarity_badge(r, 22))
		var sp := Kit.spacer(0, 0, true)
		head.add_child(sp)
		head.add_child(Kit.label(_pct(float(int(rates.get(r, 0)))), 30, Kit.rarity_color(r).lightened(0.2), "black", 4))
		cv.add_child(head)
		var ids: Array = pool.get(r, [])
		if not ids.is_empty():
			var each := float(int(rates.get(r, 0))) / float(ids.size())
			var g := Kit.grid(2, 6)
			g.add_theme_constant_override("h_separation", 24)
			for id: Variant in ids:
				var row := Kit.hbox(6)
				row.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(Kit.faction_icon(str(Game.hero_def(str(id)).get("faction", "")), 26))
				var n := Kit.label(str(Game.hero_def(str(id)).get("name", id)), 22, Kit.INK, "bold")
				n.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(n)
				row.add_child(Kit.label(_pct(each), 22, Kit.INK_DIM, "extrabold"))
				g.add_child(row)
			cv.add_child(g)
		v.add_child(card)
	var pity_max := int(_banner.get("pity_legendary", 60))
	var guarantee := str(_banner.get("ten_pull_guarantee", "epic"))
	var dupes := ""
	var dust := ""
	for r: String in ["rare", "epic", "legendary"]:
		dupes += ("%s %d" % [str(Kit.RARITY_NAMES[r]), Progression.dupe_shards(r)]) + (", " if r != "legendary" else "")
		dust += ("%d" % Progression.dust_per_excess_shard(r)) + (" / " if r != "legendary" else "")
	var rules: Array[Array] = [
		["Pity", "If none of your last %d pulls was Legendary, the next pull is a guaranteed Legendary. Your counter: %d / %d. It carries over between summons and resets when you get any Legendary." % [pity_max - 1, Game.pity_count(), pity_max]],
		["10-pull bonus", "Every 10-pull includes at least one %s or better hero." % str(Kit.RARITY_NAMES.get(guarantee, guarantee.capitalize()))],
		["Duplicates", "A hero you already own turns into shards of that hero: %s shards. Shards raise stars, up to %d. Shards a fully starred hero can't use become dust (Rare / Epic / Legendary: %s per shard)." % [dupes, Kit.MAX_STARS, dust]],
		["Costs", "1 pull: %d scroll or %s gems. 10 pulls: %d scrolls or %s gems. Scrolls are always used first. The free daily summon uses the same rates." % [int(_banner.scroll_cost_one), Kit.format_full(int(_banner.cost_one)), int(_banner.scroll_cost_ten), Kit.format_full(int(_banner.cost_ten))]],
	]
	for rule in rules:
		var rv := Kit.vbox(2)
		rv.add_child(Kit.label(str(rule[0]), 24, Kit.GOLD_LIGHT, "extrabold"))
		rv.add_child(Kit.body(str(rule[1]), 22, Kit.INK))
		v.add_child(rv)
	var sc := Kit.scroll(Kit.margin(v, 6, 4))
	var vh: float = get_viewport_rect().size.y
	sc.custom_minimum_size = Vector2(590, minf(vh * 0.62, 1000.0))
	UI.popup("Summon Rates", sc, Callable(), 660.0)


## Basis points (may be fractional) as a percentage with up to 3 decimals: 200 -> "2%",
## 66.67 -> "0.667%".
static func _pct(bp: float) -> String:
	var s := "%.3f" % (bp / 100.0)
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s + "%"


# ------------------------------------------------------------------ summoning

func _try_summon(count: int) -> void:
	if _phase != "":
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gems or scrolls", "bad")
		return
	if str(p.currency) == "gems":
		var rates: Dictionary = _banner.get("rates", {})
		UI.confirm("Spend %s gems on %s?\nRates: Legendary %s, Epic %s, Rare %s." % [
			Kit.format_full(int(p.amount)), "1 summon" if count == 1 else "%d summons" % count,
			_pct(float(int(rates.get("legendary", 0)))), _pct(float(int(rates.get("epic", 0)))), _pct(float(int(rates.get("rare", 0))))],
			func() -> void: _do_summon(count, false), Callable(), "Summon")
	else:
		_do_summon(count, false)


func _do_summon(count: int, free: bool) -> void:
	if _phase != "" and _phase != "results":
		return
	var r := Game.summon(count, free)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "The portal didn't answer")), "bad")
		_refresh()
		return
	_results = r.get("value", [])
	if _results.is_empty():
		return
	_count = _results.size()
	_start_sequence()


func _best_rarity() -> String:
	var best := "rare"
	for x: Variant in _results:
		var rr := str((x as Dictionary).get("rarity", "rare"))
		if int(RARITY_ORDER.get(rr, 0)) > int(RARITY_ORDER.get(best, 0)):
			best = rr
	return best


func _start_sequence() -> void:
	UI.set_chrome(false, false)
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_cards.clear()
	_revealed = 0
	_skip_all = false
	_showcase = null
	_overlay = Control.new()
	_overlay.name = "SummonSequence"
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_overlay.mouse_filter = MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_input)
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.25)
	var bd := SummonBackdrop.new()
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bd.stars_only = true
	_overlay.add_child(bd)

	_portal = PortalFx.new()
	_portal.target = Kit.rarity_color(_best_rarity())
	_overlay.add_child(_portal)
	_place_portal.call_deferred()

	_hint_label = Kit.label("Tap to skip", 24, Kit.INK_DIM, "extrabold", 4)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -UI.safe_bottom() - 70.0
	_hint_label.offset_bottom = -UI.safe_bottom() - 30.0
	_overlay.add_child(_hint_label)

	_flash = ColorRect.new()
	_flash.color = Color(1, 0.97, 0.9, 0.0)
	_flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(_flash)

	_main.visible = false
	_phase = "charge"
	_charge_t = 0.0
	UI.sfx("summon")
	UI.haptic(20)


## Vertical centre of the sequence (portal, cards); the backdrop's rune ring follows it.
func _focus_y() -> float:
	var st := UI.safe_top()
	return st + (_overlay.size.y - st - UI.safe_bottom()) * 0.42


func _place_portal() -> void:
	if _portal and is_instance_valid(_portal) and _overlay:
		var s := _overlay.size
		var fy := _focus_y()
		_portal.size = Vector2(s.x, s.x)
		_portal.position = Vector2(0, fy - s.x * 0.5)
		_backdrop.portal_center = Vector2(s.x * 0.5, fy)
		_backdrop.queue_redraw()


func _on_overlay_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	match _phase:
		"charge":
			_start_reveal()
		"reveal":
			if _showcase and is_instance_valid(_showcase):
				_close_showcase()
			else:
				_reveal_everything()


func _step_sequence(delta: float) -> void:
	match _phase:
		"charge":
			_charge_t += delta
			if _portal and is_instance_valid(_portal):
				_portal.charge = clampf(_charge_t / CHARGE_TIME, 0.0, 1.0)
			if _charge_t >= CHARGE_TIME:
				_start_reveal()
		"reveal":
			if _showcase and is_instance_valid(_showcase):
				_showcase_left -= delta
				if _showcase_left <= 0.0:
					_close_showcase()
				return
			_reveal_wait -= delta
			if _reveal_wait <= 0.0:
				if _revealed < _cards.size():
					_reveal_card(_revealed, false)
					_revealed += 1
				else:
					_show_results()


func _start_reveal() -> void:
	if _phase != "charge":
		return
	_phase = "reveal"
	_reveal_wait = 0.35
	if _flash:
		_flash.color.a = 1.0
		_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	if _portal and is_instance_valid(_portal):
		var tw := _portal.create_tween()
		tw.tween_property(_portal, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_portal.queue_free)
	_portal = null
	_hint_label.text = "Tap to reveal all"
	_build_card_backs()


func _build_card_backs() -> void:
	var st := UI.safe_top()
	_grid_box = Control.new()
	_grid_box.mouse_filter = MOUSE_FILTER_IGNORE
	_grid_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_grid_box.offset_top = st
	_grid_box.offset_bottom = -UI.safe_bottom()
	_overlay.add_child(_grid_box)
	_overlay.move_child(_flash, -1)
	var area := _overlay.size - Vector2(0, st + UI.safe_bottom())
	var single := _results.size() == 1
	var cs := 300.0 if single else 124.0
	var cols := 1 if single else 5
	var gap := Vector2(10, 64)
	var rows := ceili(float(_results.size()) / cols)
	var total_w := cols * cs + (cols - 1) * gap.x
	var total_h := rows * cs + (rows - 1) * gap.y
	var origin := Vector2((area.x - total_w) * 0.5, _focus_y() - st - total_h * 0.5 - (30.0 if single else 0.0))
	for i in _results.size():
		var cxy := Vector2(i % cols, i / cols)
		var holder := Control.new()
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.position = origin + cxy * (Vector2(cs, cs) + gap)
		holder.size = Vector2(cs, cs)
		holder.set_meta("cs", cs)
		_grid_box.add_child(holder)
		var back := CardBack.new()
		back.size = Vector2(cs, cs)
		back.pivot_offset = Vector2(cs, cs) * 0.5
		holder.add_child(back)
		holder.set_meta("back", back)
		_cards.append(holder)
		# Backs drop in quickly.
		back.modulate.a = 0.0
		back.position.y = -30.0
		var tw := back.create_tween().set_parallel(true)
		tw.tween_property(back, "modulate:a", 1.0, 0.18).set_delay(i * 0.03)
		tw.tween_property(back, "position:y", 0.0, 0.25).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reveal_card(i: int, instant: bool) -> void:
	var holder := _cards[i]
	var res: Dictionary = _results[i]
	var id := str(res.get("hero_id", ""))
	var rarity := str(res.get("rarity", "rare"))
	var cs: float = holder.get_meta("cs")
	var back: Variant = holder.get_meta("back") if holder.has_meta("back") else null
	holder.remove_meta("back")
	var rc := Kit.rarity_color(rarity)
	# Glow (and rays for Legendaries) behind the card.
	if rarity != "rare":
		var gl := Kit.glow(rc, cs * (2.2 if rarity == "legendary" else 1.7))
		gl.position = Vector2(cs, cs) * 0.5 - gl.custom_minimum_size * 0.5
		gl.size = gl.custom_minimum_size
		gl.modulate.a = 0.9 if rarity == "legendary" else 0.7
		holder.add_child(gl)
		holder.move_child(gl, 0)
		if rarity == "legendary":
			var rays := Kit.rays(rc, cs * 2.6, 14)
			rays.position = Vector2(cs, cs) * 0.5 - rays.size * 0.5
			rays.modulate.a = 0.55
			holder.add_child(rays)
			holder.move_child(rays, 0)
	var opts := {"size": cs, "show_name": true, "owned": true, "tag": "NEW" if bool(res.get("is_new", false)) else ""}
	var lv := int(Game.hero(id).get("level", 1))
	opts["level"] = lv
	var face := Kit.hero_card(id, opts)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.focus_mode = FOCUS_NONE
	holder.add_child(face)
	var note := ""
	if not bool(res.get("is_new", false)):
		note = "+%d shards" % int(res.get("shards", 0))
		if int(res.get("dust", 0)) > 0:
			note = "+%d dust" % int(res.get("dust", 0)) if int(res.get("shards", 0)) == int(res.get("dust", 0)) else note + ", +%d dust" % int(res.get("dust", 0))
	if note != "":
		var nl := Kit.label(note, 20 if cs < 200 else 26, Kit.SKY.lightened(0.3), "black", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(-20, cs + cs * 0.15 + 8)
		nl.size = Vector2(cs + 40, 28)
		holder.add_child(nl)
	if cs >= 200.0:
		var badge := Kit.rarity_badge(rarity, 24)
		holder.add_child(badge)
		badge.position = Vector2(cs * 0.5 - badge.get_combined_minimum_size().x * 0.5, -48)
		# Single pull: the hero's title and badges under the card.
		var d := Game.hero_def(id)
		var info := Kit.vbox(8)
		info.mouse_filter = MOUSE_FILTER_IGNORE
		info.position = Vector2(cs * 0.5 - 300.0, cs + cs * 0.15 + (44.0 if note != "" else 12.0))
		info.size = Vector2(600, 100)
		var tl := Kit.label(str(d.get("title", "")), 28, Kit.INK, "bold", 5)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(tl)
		var br := Kit.hbox(12)
		br.alignment = BoxContainer.ALIGNMENT_CENTER
		br.mouse_filter = MOUSE_FILTER_IGNORE
		br.add_child(Kit.faction_badge(str(d.get("faction", "")), 38))
		var rb := Kit.role_badge(str(d.get("role", "")), 32)
		rb.size_flags_vertical = SIZE_SHRINK_CENTER
		br.add_child(rb)
		info.add_child(br)
		holder.add_child(info)
	if back is Control and is_instance_valid(back):
		(back as Control).queue_free()
	if instant:
		return
	# Flip in: squeeze from the side, overshoot a little.
	face.pivot_offset = Vector2(cs, cs) * 0.5
	face.scale = Vector2(0.05, 1.08)
	var tw := face.create_tween()
	tw.tween_property(face, "scale", Vector2(1.08, 1.08), 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_property(face, "scale", Vector2.ONE, 0.14)
	_reveal_wait = REVEAL_GAP if _results.size() > 1 else 0.6
	match rarity:
		"legendary":
			UI.sfx("legendary")
			UI.haptic(70)
			_spark_burst(holder.global_position - _overlay.global_position + Vector2(cs, cs) * 0.5, rc, 1.4)
			Kit.shake(_grid_box, 14)
			_open_showcase(id)
		"epic":
			UI.sfx("reward")
			UI.haptic(25)
			_spark_burst(holder.global_position - _overlay.global_position + Vector2(cs, cs) * 0.5, rc, 0.8)
			_reveal_wait += 0.15
		_:
			UI.sfx("tap")


func _reveal_everything() -> void:
	if _phase != "reveal":
		return
	_skip_all = true
	if _showcase and is_instance_valid(_showcase):
		_showcase.queue_free()
	_showcase = null
	while _revealed < _cards.size():
		_reveal_card(_revealed, true)
		_revealed += 1
	if _best_rarity() == "legendary":
		UI.sfx("legendary")
		UI.haptic(60)
	_show_results()


func _open_showcase(id: String) -> void:
	if _skip_all:
		return
	var d := Game.hero_def(id)
	_showcase = Control.new()
	_showcase.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_showcase.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(_showcase)
	_overlay.move_child(_flash, -1)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.02, 0.08, 0.86)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	_showcase.add_child(shade)
	var s := _overlay.size
	var rays := Kit.rays(Kit.LEGENDARY, s.x * 1.6, 18)
	rays.position = Vector2(s.x * 0.5, s.y * 0.42) - rays.size * 0.5
	rays.modulate.a = 0.5
	_showcase.add_child(rays)
	var glow := Kit.glow(HeroArt.faction_color(str(d.get("faction", ""))), s.x * 1.1)
	glow.size = glow.custom_minimum_size
	glow.position = Vector2(s.x * 0.5, s.y * 0.42) - glow.size * 0.5
	_showcase.add_child(glow)
	var art := TextureRect.new()
	art.texture = HeroArt.texture(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = MOUSE_FILTER_IGNORE
	var ah := minf(s.y * 0.72, s.x * 1.9)
	art.size = Vector2(ah * 0.5, ah)
	art.position = Vector2(s.x * 0.5 - ah * 0.25, UI.safe_top() + 30.0)
	_showcase.add_child(art)
	var plate := Kit.vbox(6)
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.position = Vector2(0, art.position.y + ah - 150.0)
	plate.size = Vector2(s.x, 220)
	var rb := Kit.ribbon(str(d.get("name", id)), 520.0, Kit.LEGENDARY, DARK_INK, 48)
	rb.size_flags_horizontal = SIZE_SHRINK_CENTER
	plate.add_child(rb)
	var t := Kit.label(str(d.get("title", "")), 28, Kit.INK, "bold", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(t)
	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var rbg := Kit.rarity_badge("legendary", 24)
	rbg.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(rbg)
	row.add_child(Kit.faction_badge(str(d.get("faction", "")), 38))
	plate.add_child(row)
	_showcase.add_child(plate)
	_spark_burst(Vector2(s.x * 0.5, s.y * 0.42), Kit.LEGENDARY, 2.0)
	# Slide in.
	art.modulate.a = 0.0
	var ax := art.position.x
	art.position.x = ax + 120.0
	var tw := art.create_tween().set_parallel(true)
	tw.tween_property(art, "modulate:a", 1.0, 0.3)
	tw.tween_property(art, "position:x", ax, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Kit.pop_in(rb, 0.15, 0.4)
	_showcase_left = SHOWCASE_TIME


func _close_showcase() -> void:
	if _showcase and is_instance_valid(_showcase):
		var sc := _showcase
		var tw := sc.create_tween()
		tw.tween_property(sc, "modulate:a", 0.0, 0.2)
		tw.tween_callback(sc.queue_free)
	_showcase = null
	_reveal_wait = 0.25


func _show_results() -> void:
	_phase = "results"
	if _hint_label:
		_hint_label.visible = false
	var st := UI.safe_top()
	var sb := UI.safe_bottom()
	var top := Kit.ribbon("Summon Results" if _results.size() > 1 else "You Summoned", 520.0, Kit.GOLD, DARK_INK, 40)
	top.position = Vector2(_overlay.size.x * 0.5 - 260.0, st + 24.0)
	top.size = Vector2(520, 84)
	_overlay.add_child(top)
	Kit.pop_in(top, 0.0, 0.3)

	_results_box = Kit.vbox(14)
	_results_box.anchor_left = 0.0
	_results_box.anchor_right = 1.0
	_results_box.anchor_top = 1.0
	_results_box.anchor_bottom = 1.0
	_results_box.offset_left = 24
	_results_box.offset_right = -24
	_results_box.offset_bottom = -sb - 24.0
	_results_box.offset_top = -sb - 24.0 - 250.0
	_results_box.alignment = BoxContainer.ALIGNMENT_END
	_overlay.add_child(_results_box)
	var news := 0
	var shards := 0
	for x: Variant in _results:
		var d := x as Dictionary
		if bool(d.get("is_new", false)):
			news += 1
		shards += int(d.get("shards", 0))
	var parts: Array[String] = []
	if news > 0:
		parts.append("%d new hero%s" % [news, "" if news == 1 else "es"])
	if shards > 0:
		parts.append("+%d shards" % shards)
	var summary := Kit.label("  ·  ".join(parts), 26, Kit.GOLD_LIGHT, "extrabold", 4)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_box.add_child(summary)
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pl := Kit.caption("Legendary guaranteed within %d pulls" % maxi(1, pity_max - Game.pity_count()), 22)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_box.add_child(pl)
	var row := Kit.hbox(14)
	var again_n := 10 if _count >= 10 else 1
	var p := _price(again_n)
	var again := Kit.cost_button("Summon x%d again" % again_n, str(p.currency), int(p.amount), func() -> void: _again(again_n), "secondary", bool(p.ok))
	again.disabled = not bool(p.ok)
	again.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(again)
	var done := Kit.primary_button("Done", _finish, "check")
	done.custom_minimum_size.y = 104
	done.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(done)
	_results_box.add_child(row)
	if not bool(p.ok):
		var why := Kit.caption("Not enough gems or scrolls for another x%d." % again_n, 22, SHORT_RED)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_results_box.add_child(why)
	_results_box.modulate.a = 0.0
	_results_box.create_tween().tween_property(_results_box, "modulate:a", 1.0, 0.25)


func _again(count: int) -> void:
	if _phase != "results":
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gems or scrolls", "bad")
		return
	if str(p.currency) == "gems":
		UI.confirm("Spend %s gems on %s?" % [Kit.format_full(int(p.amount)), "1 summon" if count == 1 else "%d summons" % count],
			func() -> void: _do_summon(count, false), Callable(), "Summon")
	else:
		_do_summon(count, false)


func _finish() -> void:
	_phase = ""
	if _overlay and is_instance_valid(_overlay):
		var o := _overlay
		var tw := o.create_tween()
		tw.tween_property(o, "modulate:a", 0.0, 0.2)
		tw.tween_callback(o.queue_free)
	_overlay = null
	_cards.clear()
	_results.clear()
	UI.set_chrome(true, true)
	_main.visible = true
	_refresh()
	_layout_featured.call_deferred()


func _spark_burst(at: Vector2, color: Color, strength: float) -> void:
	var b := Sparks.new()
	b.color = color
	b.strength = strength
	b.position = at
	_overlay.add_child(b)


# ------------------------------------------------------------------ drawing helpers

## Night sky with a rune circle behind the featured heroes (the portal at rest).
class SummonBackdrop extends Control:
	var portal_center := Vector2(360, 480)
	var stars_only := false
	var _stars: Array[Vector3] = []
	var _ring: Control
	var _tex: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not stars_only:
			_tex = HeroArt.background("summon")
		var rng := RandomNumberGenerator.new()
		rng.seed = 909
		for i in 90:
			_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf()))
		if not stars_only:
			_ring = RuneRing.new()
			_ring.speed = 0.06
			add_child(_ring)
		resized.connect(queue_redraw)

	func _process(_delta: float) -> void:
		if _ring:
			var r := minf(size.x * 0.48, 340.0)
			_ring.size = Vector2(r * 2.0, r * 2.0)
			_ring.position = portal_center - Vector2(r, r)
			_ring.pivot_offset = Vector2(r, r)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if _tex:
			# Painted summon art when the art team ships it: scale to cover.
			var ts := _tex.get_size()
			var k := maxf(w / maxf(ts.x, 1.0), h / maxf(ts.y, 1.0))
			var d := ts * k
			draw_texture_rect(_tex, Rect2((Vector2(w, h) - d) * 0.5, d), false)
			draw_rect(Rect2(0, 0, w, h), Color(0.07, 0.05, 0.14, 0.35))
		elif not stars_only:
			var top := Color("0a0720")
			var mid := Color("2a1658")
			var low := Color("120e24")
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.5), Vector2(0, h * 0.5)]), PackedColorArray([top, top, mid, mid]))
			draw_polygon(PackedVector2Array([Vector2(0, h * 0.5), Vector2(w, h * 0.5), Vector2(w, h), Vector2(0, h)]), PackedColorArray([mid, mid, low, low]))
		for s in _stars:
			var a := 0.25 + 0.6 * s.z
			draw_circle(Vector2(s.x * w, s.y * h), 0.8 + 1.6 * s.z, Color(1, 0.95, 0.85, a))
		if not stars_only:
			# Soft portal glow and a floor of light.
			for i in 6:
				var r := 360.0 - i * 50.0
				draw_circle(portal_center, r, Color(0.56, 0.42, 0.88, 0.035))
			var fy := portal_center.y + minf(size.x * 0.48, 340.0) * 0.95
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				pts.append(Vector2(w * 0.5 + cos(a) * w * 0.45, fy + sin(a) * 34.0))
			draw_colored_polygon(pts, Color(0.95, 0.75, 0.35, 0.08))


## Rotating circle of runes (drawn once, rotated by its node rotation).
class RuneRing extends Control:
	var speed := 0.1
	var color := Color(0.95, 0.8, 0.5, 0.32)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		rotation += speed * delta

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		draw_arc(c, r * 0.98, 0, TAU, 96, color, 3.0, true)
		draw_arc(c, r * 0.9, 0, TAU, 96, Color(color, color.a * 0.6), 1.5, true)
		draw_arc(c, r * 0.62, 0, TAU, 72, Color(color, color.a * 0.5), 2.0, true)
		for i in 24:
			var a := TAU * i / 24.0
			var p1 := c + Vector2.from_angle(a) * r * 0.9
			var p2 := c + Vector2.from_angle(a) * r * (0.98 if i % 2 == 0 else 0.94)
			draw_line(p1, p2, color, 2.0, true)
			if i % 3 == 0:
				var pm := c + Vector2.from_angle(a + TAU / 48.0) * r * 0.76
				_rune(pm, a, r * 0.05)
		# Hexagram.
		for k in 2:
			var pts := PackedVector2Array()
			for i in 4:
				pts.append(c + Vector2.from_angle(-PI / 2.0 + k * PI / 3.0 + TAU * i / 3.0) * r * 0.62)
			draw_polyline(pts, Color(color, color.a * 0.55), 2.0, true)

	func _rune(p: Vector2, a: float, s: float) -> void:
		var d := Vector2.from_angle(a)
		var n := Vector2(-d.y, d.x)
		draw_line(p - n * s, p + n * s, color, 2.0, true)
		draw_line(p + n * s, p + d * s * 0.8, color, 2.0, true)
		draw_circle(p - d * s * 0.5, s * 0.25, color)


## The portal charging up: spinning rings, a growing core and motes spiralling inward. Its
## color drifts toward `target` (the best rarity of the results) as `charge` goes 0 -> 1.
class PortalFx extends Control:
	var charge := 0.0
	var target := Color("4fa3e0")
	var _t := 0.0
	var _motes: Array[Vector3] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 70:
			_motes.append(Vector3(randf() * TAU, randf(), randf_range(2.0, 5.0)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var base := Color("8e6ce0")
		var col := base.lerp(target, clampf((charge - 0.35) / 0.5, 0.0, 1.0))
		var r := size.x * 0.42
		var spin := _t * (1.0 + charge * 6.0)
		# Core glow.
		for i in 8:
			var rr := r * (0.15 + 0.12 * i) * (0.6 + charge * 0.7)
			draw_circle(c, rr, Color(col.lightened(0.4), 0.06 + 0.05 * charge))
		draw_circle(c, r * 0.12 * (0.5 + charge * 1.4), Color(1, 1, 1, 0.5 + 0.5 * charge))
		# Rings.
		for k in 3:
			var rk := r * (0.55 + 0.22 * k)
			var dir := 1.0 if k % 2 == 0 else -1.0
			var seg := 6 + k * 3
			for i in seg:
				var a0 := spin * dir * (1.0 - k * 0.2) + TAU * i / seg
				draw_arc(c, rk, a0, a0 + TAU / seg * 0.6, 16, Color(col, 0.35 + 0.5 * charge), 3.0 + 2.0 * charge, true)
		# Motes spiralling in.
		for m in _motes:
			var life := fposmod(m.y + _t * (0.35 + charge * 0.9), 1.0)
			var dist := r * 1.25 * (1.0 - life)
			var ang := m.x + life * 3.0
			var p := c + Vector2.from_angle(ang) * dist
			draw_circle(p, m.z * (0.4 + life), Color(col.lightened(0.5), life * (0.5 + 0.5 * charge)))


## Back of an unrevealed summon card: dark plate, gold frame, a winged sigil.
class CardBack extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		var sb := Kit.box(Color("2a2150"), Color("0e0a1c"), Color("e8c36a"), maxf(10.0, s.x * 0.08), maxi(2, int(s.x * 0.025)))
		draw_style_box(sb, Rect2(Vector2.ZERO, s))
		var c := s * 0.5
		var r := s.x * 0.26
		var gold := Color(0.95, 0.78, 0.4, 0.85)
		draw_arc(c, r, 0, TAU, 48, gold, maxf(2.0, s.x * 0.02), true)
		draw_arc(c, r * 0.7, 0, TAU, 48, Color(gold, 0.5), maxf(1.5, s.x * 0.012), true)
		var star := PackedVector2Array()
		for i in 9:
			var a := -PI / 2.0 + TAU * i / 8.0
			var rr := r * (0.62 if i % 2 == 0 else 0.26)
			star.append(c + Vector2.from_angle(a) * rr)
		draw_colored_polygon(star, Color(gold, 0.75))
		for side in [-1.0, 1.0]:
			var wing := PackedVector2Array([c + Vector2(side * r * 1.05, -r * 0.1), c + Vector2(side * r * 1.75, -r * 0.55),
				c + Vector2(side * r * 1.55, 0.0), c + Vector2(side * r * 1.75, r * 0.35)])
			draw_polyline(wing, Color(gold, 0.6), maxf(1.5, s.x * 0.012), true)


## Sparks flying out from a point (frees itself).
class Sparks extends Control:
	var color := Color.WHITE
	var strength := 1.0
	var _t := 0.0
	var _dur := 1.0
	var _s: Array[Vector3] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in int(14 + 16 * strength):
			_s.append(Vector3(randf() * TAU, randf_range(120.0, 360.0) * strength, randf_range(3.0, 7.0)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t >= _dur:
			queue_free()

	func _draw() -> void:
		var k := clampf(_t / _dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_arc(Vector2.ZERO, 20.0 + 200.0 * strength * e, 0, TAU, 64, Color(color, 0.8 * (1.0 - k)), 2.0 + 6.0 * (1.0 - k), true)
		for sp in _s:
			var dir := Vector2.from_angle(sp.x)
			draw_line(dir * sp.y * maxf(0.0, e - 0.1), dir * sp.y * e, Color(color.lightened(0.35), 1.0 - k), sp.z * (1.0 - k * 0.6), true)
