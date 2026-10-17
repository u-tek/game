extends Control
## Screen "summon" (bottom-nav Summon tab), style v2: a full-bleed banner under the
## translucent chrome. The banner title sits top-left over its art (the three featured
## Legendaries, the centre one large, on light rays in the Legendary color); at the bottom,
## the pity meter (Legendary guaranteed within N pulls) with the Rates button, the free daily
## pull strip (or the time until the next one), and the two summon buttons: x1 (graphite) and
## x10 (orange). Prices use scrolls first, then gems; gem spending asks first; when the player
## can't pay, a strip explains it and links to the Shop.
##
## Summoning plays a full-screen sequence with the chrome hidden: the portal charges (its
## color hints at the best result), a flash, then card backs flip one by one into tall
## portrait cards (tap to reveal all). Epic cards glow violet; a Legendary bursts in orange
## rays with its own sound, a haptic and a full-body showcase. Results show "N" for new
## heroes or "+N shards"; then Summon again or Done.
##
## Shot params: rates: true (open the odds), pull: 1|10 (summon right away), skip: true
## (jump straight to the results).

const Roster := preload("res://src/ui/screens/heroes_screen.gd")

const CHARGE_TIME := 1.9
const REVEAL_GAP := 0.2
const SHOWCASE_TIME := 2.4
const RARITY_ORDER := {"rare": 0, "epic": 1, "legendary": 2}
const CARD_RATIO := 1.62
const TITLE_SIZE := 54
const TITLE_W := 440.0

var _banner: Dictionary = {}
var _main: Control
var _stage: Control
var _rays: Control
var _glow: Control
var _title_box: VBoxContainer
var _feat_nodes: Array[Dictionary] = []
var _bottom: VBoxContainer
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
	UI.set_full_bleed(true)
	_build()
	resized.connect(_layout)
	Game.changed.connect(_refresh)
	_refresh()
	_layout.call_deferred()
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
	add_child(Kit.page_bg("dark"))
	_main = Control.new()
	_main.name = "Banner"
	_main.mouse_filter = MOUSE_FILTER_IGNORE
	_main.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_main)

	# The banner art: rays and a glow in the Legendary color behind the featured heroes.
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_main.add_child(_stage)
	_rays = Kit.rays(Kit.LEGENDARY, 1200.0, 16)
	_rays.modulate.a = 0.22
	_stage.add_child(_rays)
	_glow = Kit.glow(Kit.ORANGE, 760.0)
	_glow.modulate.a = 0.35
	_stage.add_child(_glow)
	var band := Kit.deco("hatch", Vector2(720, 420), Color(Kit.LEGENDARY, 0.07))
	band.name = "Band"
	band.set("spacing", 26.0)
	band.set("line_width", 8.0)
	_stage.add_child(band)
	_build_featured()
	# Shade under the bottom controls and the translucent nav.
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.texture = Kit.vgradient(Color(0, 0, 0, 0), Color(0, 0, 0, 0.82))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_main.add_child(shade)

	# Title block, top-left over the art.
	_title_box = Kit.vbox(4)
	_title_box.name = "Title"
	_title_box.mouse_filter = MOUSE_FILTER_IGNORE
	var feat := Kit.hbox(8)
	feat.mouse_filter = MOUSE_FILTER_IGNORE
	feat.add_child(Kit.rarity_badge("legendary", 20))
	feat.add_child(Kit.label("FEATURED", 20, Kit.ORANGE_HI, "cond_bold"))
	_title_box.add_child(feat)
	# Two balanced lines ("CHOIR OF THE / FALLEN SKY"), never an orphan word.
	var t := Kit.label(_balanced_title(str(_banner.get("name", "Summon")).to_upper()), TITLE_SIZE, Color.WHITE, "title")
	t.name = "TitleText"
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 3)
	t.add_theme_constant_override("shadow_outline_size", 6)
	t.add_theme_constant_override("line_spacing", -14)
	_fit_title(t, TITLE_W)
	_title_box.add_child(t)
	var sub := PanelContainer.new()
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	sub.size_flags_horizontal = SIZE_SHRINK_BEGIN
	sub.add_theme_stylebox_override("panel", Kit.box(Color("080c19c8"), Color("080c19c8"), Color(1, 1, 1, 0.1), 3, 1, 0))
	var sr := Kit.hbox(8)
	sr.mouse_filter = MOUSE_FILTER_IGNORE
	sr.add_child(Kit.deco("techline", Vector2(36, 8), Color(1, 1, 1, 0.5)))
	sr.add_child(Kit.label("STANDARD PORTAL  ·  EVERY HERO CAN ANSWER", 17, Kit.INK, "cond_bold"))
	sub.add_child(Kit.margin(sr, 10, 3))
	_title_box.add_child(sub)
	# Dark scrim from the left edge behind the title block, so it reads over any art.
	var scrim := TextureRect.new()
	scrim.name = "TitleScrim"
	scrim.mouse_filter = MOUSE_FILTER_IGNORE
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_main.add_child(scrim)
	_main.add_child(_title_box)

	# Bottom controls.
	_bottom = Kit.vbox(10)
	_bottom.name = "Bottom"
	_main.add_child(_bottom)
	var pity_row := Kit.hbox(10)
	var pity := PanelContainer.new()
	pity.name = "Pity"
	pity.mouse_filter = MOUSE_FILTER_IGNORE
	pity.add_theme_stylebox_override("panel", Kit.style("meter"))
	pity.size_flags_horizontal = SIZE_EXPAND_FILL
	var prow := Kit.hbox(12)
	prow.mouse_filter = MOUSE_FILTER_IGNORE
	prow.add_child(Kit.icon("crown", 46))
	var pv := Kit.vbox(4)
	pv.mouse_filter = MOUSE_FILTER_IGNORE
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.size_flags_horizontal = SIZE_EXPAND_FILL
	var cap := Kit.label("LEGENDARY\nGUARANTEED WITHIN", 18, Color.WHITE, "cond_bold")
	cap.add_theme_constant_override("line_spacing", -6)
	pv.add_child(cap)
	_pity_bar = Kit.progress_bar(0, 1, Kit.ACCENT, 6)
	pv.add_child(_pity_bar)
	prow.add_child(pv)
	var nv := Kit.hbox(4)
	nv.mouse_filter = MOUSE_FILTER_IGNORE
	_pity_label = Kit.label("60", 48, Kit.ACCENT_HI, "cond_bold")
	nv.add_child(_pity_label)
	var pl := Kit.label("PULLS", 18, Kit.ACCENT_HI, "cond_bold")
	pl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	pl.size_flags_vertical = SIZE_FILL
	pl.custom_minimum_size.y = 46
	nv.add_child(pl)
	prow.add_child(nv)
	pity.add_child(prow)
	pity_row.add_child(pity)
	var rates := Kit.light_button("Rates", _open_rates, "info")
	rates.name = "Rates"
	rates.custom_minimum_size = Vector2(170, Kit.BUTTON_H)
	rates.size_flags_vertical = SIZE_SHRINK_CENTER
	pity_row.add_child(rates)
	_bottom.add_child(pity_row)

	_free_slot = Kit.vbox(0)
	_bottom.add_child(_free_slot)
	_reason = Kit.notice_bar("", func() -> void: UI.go("shop"), 688.0, "shop")
	_reason.name = "Reason"
	_reason.visible = false
	_bottom.add_child(_reason)
	_buy_row = Kit.hbox(12)
	_bottom.add_child(_buy_row)


## The three featured Legendaries: the first one large in the centre, the others behind.
func _build_featured() -> void:
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	var legends: Array = pool.get("legendary", [])
	var order: Array[int] = []
	if legends.size() >= 3:
		order = [1, 2, 0]
	else:
		for i in legends.size():
			order.append(i)
	for k in order:
		var id := str(legends[k])
		var d := Game.hero_def(id)
		var art := TextureRect.new()
		art.name = "Art_" + id
		art.texture = HeroArt.texture(id)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = MOUSE_FILTER_IGNORE
		if k != 0:
			art.modulate = Color(0.62, 0.64, 0.7)
		_stage.add_child(art)
		# Name and role on a small dark glass tag (reads on pale art like a white dress).
		var plate := PanelContainer.new()
		plate.mouse_filter = MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", Kit.box(Color("080d1bc4"), Color("080d1bc4"), Color(1, 1, 1, 0.1), 4, 1, 0))
		var pv := Kit.vbox(0)
		pv.mouse_filter = MOUSE_FILTER_IGNORE
		var nr := Kit.hbox(6)
		nr.mouse_filter = MOUSE_FILTER_IGNORE
		nr.alignment = BoxContainer.ALIGNMENT_CENTER
		var chev := Kit.deco("chevrons", Vector2(22, 18), Kit.LEGENDARY)
		chev.set("count", 3)
		chev.size_flags_vertical = SIZE_SHRINK_CENTER
		nr.add_child(chev)
		var nm := Kit.label(str(d.get("name", id)).to_upper(), 28 if k == 0 else 21, Color.WHITE, "title")
		nr.add_child(nm)
		pv.add_child(nr)
		var fr := Kit.hbox(4)
		fr.alignment = BoxContainer.ALIGNMENT_CENTER
		fr.mouse_filter = MOUSE_FILTER_IGNORE
		fr.add_child(Kit.faction_icon(str(d.get("faction", "")), 20))
		fr.add_child(Kit.label(str(Kit.ROLE_NAMES.get(str(d.get("role", "")), "")).to_upper(), 15, Kit.INK_DIM, "cond_bold"))
		pv.add_child(fr)
		plate.add_child(Kit.margin(pv, 12, 2))
		_stage.add_child(plate)
		var hit := Control.new()
		hit.name = "Hit_" + id
		hit.mouse_filter = MOUSE_FILTER_PASS
		_stage.add_child(hit)
		Kit.make_tappable(hit, func() -> void: UI.go("hero_detail", {"hero_id": id}))
		_feat_nodes.append({"slot": k, "art": art, "plate": plate, "hit": hit})


## Soft dark oval for behind the title (fades out on every side, strongest top-left).
static func _scrim_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.66))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.55, Color(0, 0, 0, 0.42))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.18, 0.42)
	t.fill_to = Vector2(1.0, 0.42)
	t.width = 128
	t.height = 64
	return t


## Splits a title into two lines of similar length at a word break ("CHOIR OF THE\nFALLEN SKY").
static func _balanced_title(text: String) -> String:
	var words := text.split(" ", false)
	if words.size() < 3:
		return text
	var best := ""
	var best_d := 1 << 30
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var d := absi(a.length() - b.length())
		if d < best_d:
			best_d = d
			best = a + "\n" + b
	return best


## Shrinks the title until its longest line fits `width`.
static func _fit_title(l: Label, width: float) -> void:
	var f := Kit.font("title")
	var fs := TITLE_SIZE
	var longest := 0.0
	while fs > 34:
		longest = 0.0
		for line in l.text.split("\n"):
			longest = maxf(longest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if longest <= width:
			break
		fs -= 2
	l.add_theme_font_size_override("font_size", fs)


func _layout() -> void:
	if _main == null or size.y <= 0.0:
		return
	var w := size.x
	var top := UI.content_top()
	var bottom := size.y - UI.content_bottom()
	_bottom.position = Vector2(16, 0)
	_bottom.size = Vector2(w - 32, 0)
	var bh := _bottom.get_combined_minimum_size().y
	_bottom.position.y = bottom - 14.0 - bh
	_title_box.position = Vector2(20, top + 12)
	_title_box.size = Vector2(TITLE_W, 0)
	var scrim := _main.get_node("TitleScrim") as Control
	var th := _title_box.get_combined_minimum_size().y
	scrim.position = Vector2(-40, top - 30.0)
	scrim.size = Vector2(w * 0.95, th + 100.0)
	var shade := _main.get_node("Shade") as Control
	shade.position = Vector2(0, _bottom.position.y - 260.0)
	shade.size = Vector2(w, size.y - shade.position.y)
	# Featured heroes: the centre one fills from under the title to below the pity meter.
	var art_top := top + 96.0
	var art_bottom := _bottom.position.y + 150.0
	var fh_main := art_bottom - art_top
	var cx := w * 0.56
	for n in _feat_nodes:
		var k := int(n.slot)
		var fh := fh_main * (1.0 if k == 0 else 0.8)
		var fw := fh * 0.5
		var x := cx + (0.0 if k == 0 else (-1.0 if k == 1 else 1.0) * w * 0.33)
		var y0 := art_bottom - fh - (0.0 if k == 0 else fh_main * 0.06)
		var art := n.art as Control
		art.position = Vector2(x - fw * 0.5, y0)
		art.size = Vector2(fw, fh)
		var plate := n.plate as Control
		var ps := plate.get_combined_minimum_size()
		plate.size = ps
		plate.position = Vector2(clampf(x - ps.x * 0.5, 8.0, w - 8.0 - ps.x), _bottom.position.y - ps.y - (12.0 if k == 0 else 44.0))
		var hit := n.hit as Control
		hit.position = art.position + Vector2(fw * 0.2, fh * 0.1)
		hit.size = Vector2(fw * 0.6, maxf(10.0, _bottom.position.y - art.position.y - fh * 0.1 - 10.0))
	var mid := Vector2(cx, art_top + fh_main * 0.36)
	_rays.size = Vector2(1200, 1200)
	_rays.position = mid - _rays.size * 0.5
	_glow.size = Vector2(760, 760)
	_glow.position = mid - _glow.size * 0.5
	var band := _stage.get_node("Band") as Control
	band.position = Vector2(0, mid.y - 120.0)
	band.size = Vector2(w, 420)


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _main == null:
		return
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(Game.pity_count())
	var left := maxi(1, pity_max - pity)
	_pity_label.text = "%02d" % left
	Kit.set_progress(_pity_bar, pity, pity_max, "", false)

	for c in _free_slot.get_children():
		_free_slot.remove_child(c)
		c.queue_free()
	_free_timer_label = null
	var guide := Guide.step() == "summon"
	var free_ready := bool(Game.free_pull_available())
	if free_ready:
		var free := Kit.notice_bar("Free daily summon ready: Summon x1 is free", func() -> void: _do_summon(1, true), 688.0, "summon")
		free.name = "FreePull"
		_free_slot.add_child(free)
	else:
		var row := Kit.panel("inset", 10)
		var h := Kit.hbox(10)
		h.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(Kit.icon("timer", 30, Kit.INK_DIM))
		_free_timer_label = Kit.label("", 21, Kit.INK_DIM, "bold")
		h.add_child(_free_timer_label)
		row.add_child(h)
		_free_slot.add_child(row)
		_update_free_timer()

	for c in _buy_row.get_children():
		_buy_row.remove_child(c)
		c.queue_free()
	var p1 := _price(1)
	var p10 := _price(10)
	var b1: Button
	if free_ready:
		# The free daily pull: x1 costs nothing and never spends a scroll.
		b1 = Kit.cost_button("Summon x1", "scrolls", 0, func() -> void: _do_summon(1, true), "primary")
		p1 = {"currency": "free", "amount": 0, "ok": true}
	else:
		b1 = Kit.cost_button("Summon x1", str(p1.currency), int(p1.amount), func() -> void: _try_summon(1), "secondary", bool(p1.ok))
	var b10 := Kit.cost_button("Summon x10", str(p10.currency), int(p10.amount), func() -> void: _try_summon(10), "orange", bool(p10.ok))
	b1.name = "Summon1"
	b10.name = "Summon10"
	for b: Button in [b1, b10]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 112
		_buy_row.add_child(b)
	b1.disabled = not bool(p1.ok)
	b10.disabled = not bool(p10.ok)
	# First session: the free x1 first, then the 10-pull the starting scrolls pay for.
	Guide.mark(b1, guide and free_ready, 0)
	Guide.mark(b10, guide and not free_ready and str(p10.currency) == "scrolls", 0)
	if not bool(p1.ok) or not bool(p10.ok):
		_reason.visible = true
		var need := "Need %s gems or %d scroll%s" % [Kit.format_full(int(_banner.cost_one)), int(_banner.scroll_cost_one), "" if int(_banner.scroll_cost_one) == 1 else "s"] if not bool(p1.ok) \
			else "x10 needs %s gems or %d scrolls" % [Kit.format_full(int(_banner.cost_ten)), int(_banner.scroll_cost_ten)]
		(_reason.get_meta("text_label") as Label).text = need + ". Get more in the Shop"
	else:
		_reason.visible = false
	_layout.call_deferred()


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
	var v := Kit.vbox(14)
	v.custom_minimum_size.x = 540
	var rates: Dictionary = _banner.get("rates", {})
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	v.add_child(Kit.body("Every pull rolls a rarity first, then one hero of that rarity with equal chance.", 21, Kit.TEXT_DIM))
	for r: String in ["legendary", "epic", "rare"]:
		var card := Kit.panel("light_inset", 12)
		var cv := Kit.vbox(8)
		card.add_child(cv)
		var head := Kit.hbox(10)
		head.add_child(Kit.rarity_mark(r, 26))
		head.add_child(Kit.spacer(0, 0, true))
		head.add_child(Kit.label(_pct(float(int(rates.get(r, 0)))), 32, Kit.rarity_color(r).darkened(0.15), "cond_bold"))
		cv.add_child(head)
		var ids: Array = pool.get(r, [])
		if not ids.is_empty():
			var each := float(int(rates.get(r, 0))) / float(ids.size())
			var g := Kit.grid(2, 4)
			g.add_theme_constant_override("h_separation", 20)
			for id: Variant in ids:
				var row := Kit.hbox(6)
				row.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(Kit.faction_icon(str(Game.hero_def(str(id)).get("faction", "")), 24))
				var n := Kit.label(str(Game.hero_def(str(id)).get("name", id)), 21, Kit.TEXT, "bold")
				n.size_flags_horizontal = SIZE_EXPAND_FILL
				row.add_child(n)
				row.add_child(Kit.label(_pct(each), 20, Kit.TEXT_DIM, "cond_bold"))
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
		var rv := Kit.vbox(4)
		rv.add_child(Kit.header_bar(str(rule[0])))
		rv.add_child(Kit.body(str(rule[1]), 21, Kit.TEXT))
		v.add_child(rv)
	var sc := Kit.scroll(Kit.margin(v, 4, 4))
	var vh: float = get_viewport_rect().size.y
	sc.custom_minimum_size = Vector2(560, minf(vh * 0.62, 1000.0))
	UI.popup("Summon Rates", sc, Callable(), 640.0, true)


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
	for x: Variant in _results:
		if x is Dictionary and bool((x as Dictionary).get("is_new", false)):
			Roster.mark_new(str((x as Dictionary).get("hero_id", "")))
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
	var bg := Kit.page_bg("dark")
	_overlay.add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(dim)
	_overlay.modulate.a = 0.0
	_overlay.create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.22)

	_portal = PortalFx.new()
	_portal.target = Kit.rarity_color(_best_rarity())
	_overlay.add_child(_portal)
	_place_portal.call_deferred()

	_hint_label = Kit.label("TAP TO SKIP", 22, Kit.INK_DIM, "cond_bold", 4)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -UI.safe_bottom() - 70.0
	_hint_label.offset_bottom = -UI.safe_bottom() - 30.0
	_overlay.add_child(_hint_label)

	_flash = ColorRect.new()
	_flash.color = Color(0.92, 0.97, 1.0, 0.0)
	_flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(_flash)

	_main.visible = false
	_phase = "charge"
	_charge_t = 0.0
	UI.sfx("summon")
	UI.haptic(20)


## Vertical centre of the sequence (portal, cards).
func _focus_y() -> float:
	var st := UI.safe_top()
	return st + (_overlay.size.y - st - UI.safe_bottom()) * 0.44


func _place_portal() -> void:
	if _portal and is_instance_valid(_portal) and _overlay:
		var s := _overlay.size
		var fy := _focus_y()
		_portal.size = Vector2(s.x, s.x)
		_portal.position = Vector2(0, fy - s.x * 0.5)


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
	_hint_label.text = "TAP TO REVEAL ALL"
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
	var cols := 1 if single else 5
	var cw := 250.0 if single else floorf(minf(128.0, (area.x - 40.0 - 4 * 10.0) / 5.0))
	var ch := roundf(cw * CARD_RATIO)
	var gap := Vector2(10, 52)
	var rows := ceili(float(_results.size()) / cols)
	var total_w := cols * cw + (cols - 1) * gap.x
	var total_h := rows * ch + (rows - 1) * gap.y
	var origin := Vector2((area.x - total_w) * 0.5, _focus_y() - st - total_h * 0.5 - (40.0 if single else 10.0))
	for i in _results.size():
		var cxy := Vector2(i % cols, i / cols)
		var holder := Control.new()
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.position = origin + cxy * (Vector2(cw, ch) + gap)
		holder.size = Vector2(cw, ch)
		holder.set_meta("cw", cw)
		_grid_box.add_child(holder)
		var back := _card_back(Vector2(cw, ch))
		holder.add_child(back)
		holder.set_meta("back", back)
		_cards.append(holder)
		# Backs drop in quickly.
		back.modulate.a = 0.0
		back.position.y = -30.0
		var tw := back.create_tween().set_parallel(true)
		tw.tween_property(back, "modulate:a", 1.0, 0.18).set_delay(i * 0.03)
		tw.tween_property(back, "position:y", 0.0, 0.25).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Back of an unrevealed card, from Kit parts: graphite plate with a cyan rim, hatching,
## corner brackets, a barcode and the summon glyph in a hexagon.
func _card_back(sz: Vector2) -> Control:
	var p := Panel.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.size = sz
	p.pivot_offset = sz * 0.5
	p.add_theme_stylebox_override("panel", Kit.box(Color("1c2c4a"), Color("0c1323"), Color(Kit.ACCENT, 0.85), 4.0, 2))
	var hatch := Kit.deco("hatch", sz, Color(Kit.ACCENT, 0.08))
	hatch.set("spacing", 12.0)
	p.add_child(hatch)
	var br := Kit.deco("brackets", sz - Vector2(14, 14), Color(1, 1, 1, 0.5))
	br.position = Vector2(7, 7)
	p.add_child(br)
	var hs := sz.x * 0.46
	var hx := Kit.hex_badge("summon", hs, Color("111c31"), Kit.ACCENT_HI)
	hx.set("glow", Color(Kit.ACCENT, 0.5))
	hx.set("glow_size", hs * 0.2)
	hx.position = (sz - Vector2(hs, hs)) * 0.5
	p.add_child(hx)
	var bc := Kit.deco("barcode", Vector2(sz.x * 0.08, sz.y * 0.16), Color(1, 1, 1, 0.35))
	bc.position = Vector2(sz.x * 0.86, sz.y * 0.06)
	p.add_child(bc)
	return p


func _reveal_card(i: int, instant: bool) -> void:
	var holder := _cards[i]
	var res: Dictionary = _results[i]
	var id := str(res.get("hero_id", ""))
	var rarity := str(res.get("rarity", "rare"))
	var cw: float = holder.get_meta("cw")
	var ch := roundf(cw * CARD_RATIO)
	var back: Variant = holder.get_meta("back") if holder.has_meta("back") else null
	holder.remove_meta("back")
	var rc := Kit.rarity_color(rarity)
	var mid := Vector2(cw, ch) * 0.5
	# Glow (and rays for Legendaries) behind the card.
	if rarity != "rare":
		var gl := Kit.glow(rc, cw * (2.6 if rarity == "legendary" else 2.0))
		gl.size = gl.custom_minimum_size
		gl.position = mid - gl.size * 0.5
		gl.modulate.a = 0.9 if rarity == "legendary" else 0.7
		holder.add_child(gl)
		holder.move_child(gl, 0)
		if rarity == "legendary":
			var rays := Kit.rays(rc, cw * 3.2, 14)
			rays.position = mid - rays.size * 0.5
			rays.modulate.a = 0.55
			holder.add_child(rays)
			holder.move_child(rays, 0)
	var is_new := bool(res.get("is_new", false))
	var face := Kit.portrait_card(id, {"size": cw, "owned": true, "level": int(Game.hero(id).get("level", 1)), "new": is_new})
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.focus_mode = FOCUS_NONE
	holder.add_child(face)
	var note := ""
	if not is_new:
		note = "+%d SHARDS" % int(res.get("shards", 0))
		if int(res.get("dust", 0)) > 0:
			note = "+%d DUST" % int(res.get("dust", 0)) if int(res.get("shards", 0)) == int(res.get("dust", 0)) else note + "  +%d DUST" % int(res.get("dust", 0))
	elif cw < 200.0:
		note = "NEW HERO"
	if note != "":
		var nl := Kit.label(note, 18 if cw < 200 else 24, Kit.ORANGE_HI if is_new else Kit.ACCENT_HI, "cond_bold", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(-20, ch + 6)
		nl.size = Vector2(cw + 40, 26)
		holder.add_child(nl)
	if cw >= 200.0:
		# Single pull: rarity on top, the hero's title and badges under the card.
		var badge := Kit.rarity_mark(rarity, 30)
		holder.add_child(badge)
		badge.position = Vector2(cw * 0.5 - badge.get_combined_minimum_size().x * 0.5, -54)
		var d := Game.hero_def(id)
		var info := Kit.vbox(8)
		info.mouse_filter = MOUSE_FILTER_IGNORE
		info.position = Vector2(cw * 0.5 - 300.0, ch + (40.0 if note != "" else 14.0))
		info.size = Vector2(600, 100)
		var tl := Kit.label(str(d.get("title", "")).to_upper(), 24, Kit.INK, "cond_bold", 4)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(tl)
		var br := Kit.hbox(12)
		br.alignment = BoxContainer.ALIGNMENT_CENTER
		br.mouse_filter = MOUSE_FILTER_IGNORE
		br.add_child(Kit.faction_badge(str(d.get("faction", "")), 34))
		var rb := Kit.role_badge(str(d.get("role", "")), 30)
		rb.size_flags_vertical = SIZE_SHRINK_CENTER
		br.add_child(rb)
		info.add_child(br)
		holder.add_child(info)
	if back is Control and is_instance_valid(back):
		(back as Control).queue_free()
	if instant:
		return
	# Flip in: squeeze from the side, overshoot a little.
	face.pivot_offset = Vector2(cw, ch) * 0.5
	face.scale = Vector2(0.05, 1.08)
	var tw := face.create_tween()
	tw.tween_property(face, "scale", Vector2(1.08, 1.08), 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_property(face, "scale", Vector2.ONE, 0.14)
	_reveal_wait = REVEAL_GAP if _results.size() > 1 else 0.6
	match rarity:
		"legendary":
			UI.sfx("legendary")
			UI.haptic(70)
			_spark_burst(holder.global_position - _overlay.global_position + mid, rc, 1.4)
			Kit.shake(_grid_box, 14)
			_open_showcase(id)
		"epic":
			UI.sfx("reward")
			UI.haptic(25)
			_spark_burst(holder.global_position - _overlay.global_position + mid, rc, 0.8)
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


## A Legendary's full-body showcase: orange rays, the art sliding in, a ribbon with the name.
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
	shade.color = Color(0.02, 0.025, 0.035, 0.88)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	_showcase.add_child(shade)
	var s := _overlay.size
	var c := Vector2(s.x * 0.5, s.y * 0.42)
	var band := Kit.deco("hatch", Vector2(s.x, s.y * 0.5), Color(Kit.LEGENDARY, 0.1))
	band.set("spacing", 30.0)
	band.set("line_width", 12.0)
	band.position = Vector2(0, s.y * 0.25)
	_showcase.add_child(band)
	var rays := Kit.rays(Kit.LEGENDARY, s.x * 1.7, 18)
	rays.position = c - rays.size * 0.5
	rays.modulate.a = 0.5
	_showcase.add_child(rays)
	var glow := Kit.glow(Kit.ORANGE, s.x * 1.1)
	glow.size = glow.custom_minimum_size
	glow.position = c - glow.size * 0.5
	glow.modulate.a = 0.6
	_showcase.add_child(glow)
	var art := TextureRect.new()
	art.texture = HeroArt.texture(id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = MOUSE_FILTER_IGNORE
	var ah := minf(s.y * 0.74, s.x * 1.9)
	art.size = Vector2(ah * 0.5, ah)
	art.position = Vector2(s.x * 0.5 - ah * 0.25, UI.safe_top() + 30.0)
	_showcase.add_child(art)
	var plate := Kit.vbox(6)
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.position = Vector2(0, art.position.y + ah - 150.0)
	plate.size = Vector2(s.x, 220)
	var mark := Kit.rarity_mark("legendary", 34)
	mark.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(mark)
	var rb := Kit.ribbon(str(d.get("name", id)).to_upper(), 520.0, Kit.LEGENDARY, Color.WHITE, 48)
	rb.size_flags_horizontal = SIZE_SHRINK_CENTER
	plate.add_child(rb)
	var t := Kit.label(str(d.get("title", "")).to_upper(), 24, Kit.INK, "cond_bold", 4)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(t)
	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(Kit.faction_badge(str(d.get("faction", "")), 34))
	var rlb := Kit.role_badge(str(d.get("role", "")), 30)
	rlb.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(rlb)
	plate.add_child(row)
	_showcase.add_child(plate)
	_spark_burst(c, Kit.LEGENDARY, 2.0)
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
	var title := "SUMMON RESULTS"
	if _results.size() == 1:
		title = "NEW HERO" if bool((_results[0] as Dictionary).get("is_new", false)) else "SUMMON RESULT"
	var top := Kit.ribbon(title, 520.0, Kit.ACCENT, Color.WHITE, 40)
	top.position = Vector2(_overlay.size.x * 0.5 - 260.0, st + 24.0)
	top.size = Vector2(520, 84)
	_overlay.add_child(top)
	Kit.pop_in(top, 0.0, 0.3)
	var summary := Kit.vbox(6)
	summary.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.add_child(summary)

	_results_box = Kit.vbox(12)
	_results_box.anchor_left = 0.0
	_results_box.anchor_right = 1.0
	_results_box.anchor_top = 1.0
	_results_box.anchor_bottom = 1.0
	_results_box.offset_left = 20
	_results_box.offset_right = -20
	_results_box.offset_bottom = -sb - 20.0
	_results_box.offset_top = -sb - 20.0 - 250.0
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
		parts.append("%d NEW HERO%s" % [news, "" if news == 1 else "ES"])
	if shards > 0:
		parts.append("+%d SHARDS" % shards)
	var srow := Kit.hbox(10)
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.mouse_filter = MOUSE_FILTER_IGNORE
	srow.add_child(Kit.deco("techline", Vector2(70, 8), Color(1, 1, 1, 0.4)))
	srow.add_child(Kit.label("  ·  ".join(parts), 24, Color.WHITE, "cond_bold", 4))
	var tl2 := Kit.deco("techline", Vector2(70, 8), Color(1, 1, 1, 0.4))
	tl2.scale.x = -1
	tl2.pivot_offset = Vector2(35, 4)
	srow.add_child(tl2)
	# A single pull already shows its shards under the card.
	if _results.size() > 1 and not parts.is_empty():
		summary.add_child(srow)
	else:
		srow.free()
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pl := Kit.label("LEGENDARY GUARANTEED WITHIN %d PULLS" % maxi(1, pity_max - Game.pity_count()), 18, Kit.ACCENT_HI, "cond_bold")
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_child(pl)
	var row := Kit.hbox(12)
	var again_n := 10 if _count >= 10 else 1
	var p := _price(again_n)
	var again := Kit.cost_button("Summon x%d Again" % again_n, str(p.currency), int(p.amount), func() -> void: _again(again_n), "secondary", bool(p.ok))
	again.disabled = not bool(p.ok)
	again.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(again)
	var done := Kit.primary_button("Done", _finish, "check")
	done.name = "Done"
	done.custom_minimum_size.y = 108
	done.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(done)
	_results_box.add_child(row)
	if not bool(p.ok):
		var why := Kit.label("Not enough gems or scrolls for another x%d." % again_n, 20, Color("ff6a50"), "bold")
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_results_box.add_child(why)
	_results_box.modulate.a = 0.0
	_results_box.create_tween().tween_property(_results_box, "modulate:a", 1.0, 0.25)
	summary.modulate.a = 0.0
	summary.create_tween().tween_property(summary, "modulate:a", 1.0, 0.25)
	_stack_results(top, summary)


## Ribbon, cards and the shard / pity summary as one block, centred in the space above the
## buttons (the cards glide there from where they were revealed).
func _stack_results(ribbon: Control, summary: Control) -> void:
	if _cards.is_empty() or _grid_box == null:
		return
	var st := UI.safe_top()
	var g_top := INF
	var g_bot := -INF
	for h in _cards:
		g_top = minf(g_top, h.position.y)
		g_bot = maxf(g_bot, h.position.y + h.size.y)
	var single := _cards.size() == 1
	var above := 64.0 if single else 0.0
	var below := 160.0 if single else 40.0
	var sum_h := summary.get_combined_minimum_size().y
	var block := 84.0 + 22.0 + above + (g_bot - g_top) + below + sum_h
	var region_top := st + 16.0
	var region_bot := _overlay.size.y + _results_box.offset_bottom - _results_box.get_combined_minimum_size().y - 20.0
	var want := region_top + maxf(0.0, (region_bot - region_top - block) * 0.5)
	var dy := (want + 84.0 + 22.0 + above) - (st + g_top)
	_grid_box.create_tween().tween_property(_grid_box, "position:y", _grid_box.position.y + dy, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ribbon.position.y = want
	summary.position = Vector2(0, want + block - sum_h)
	summary.size = Vector2(_overlay.size.x, sum_h)


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
	_layout.call_deferred()


func _spark_burst(at: Vector2, color: Color, strength: float) -> void:
	var b := Sparks.new()
	b.color = color
	b.strength = strength
	b.position = at
	_overlay.add_child(b)


# ------------------------------------------------------------------ effects

## The portal charging up: spinning segmented rings, a hexagon frame, a growing core and
## motes spiralling inward. Its color drifts from cyan toward `target` (the best rarity of
## the results) as `charge` goes 0 -> 1.
class PortalFx extends Control:
	var charge := 0.0
	var target := Color("3b9cf2")
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
		var base := Kit.ACCENT
		var col := base.lerp(target, clampf((charge - 0.35) / 0.5, 0.0, 1.0))
		var r := size.x * 0.42
		var spin := _t * (1.0 + charge * 6.0)
		# Core glow.
		for i in 8:
			var rr := r * (0.15 + 0.12 * i) * (0.6 + charge * 0.7)
			draw_circle(c, rr, Color(col.lightened(0.4), 0.05 + 0.05 * charge))
		draw_circle(c, r * 0.12 * (0.5 + charge * 1.4), Color(1, 1, 1, 0.5 + 0.5 * charge))
		# Hexagon frame, turning slowly.
		var hex := PackedVector2Array()
		for i in 7:
			hex.append(c + Vector2.from_angle(-PI / 2.0 + spin * 0.15 + TAU * i / 6.0) * r * 0.98)
		draw_polyline(hex, Color(col, 0.3 + 0.4 * charge), 2.0, true)
		# Segmented rings.
		for k in 3:
			var rk := r * (0.5 + 0.2 * k)
			var dir := 1.0 if k % 2 == 0 else -1.0
			var seg := 6 + k * 3
			for i in seg:
				var a0 := spin * dir * (1.0 - k * 0.2) + TAU * i / seg
				draw_arc(c, rk, a0, a0 + TAU / seg * 0.55, 16, Color(col, 0.35 + 0.5 * charge), 3.0 + 2.0 * charge, true)
		# Motes spiralling in.
		for m in _motes:
			var life := fposmod(m.y + _t * (0.35 + charge * 0.9), 1.0)
			var dist := r * 1.25 * (1.0 - life)
			var ang := m.x + life * 3.0
			var p := c + Vector2.from_angle(ang) * dist
			draw_circle(p, m.z * (0.4 + life), Color(col.lightened(0.5), life * (0.5 + 0.5 * charge)))


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
