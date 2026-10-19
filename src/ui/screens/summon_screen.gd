extends Control
## Screen "summon" (bottom-nav Summon tab), style v2: a full-bleed banner under the
## translucent chrome. The banner title sits top-left over its art (the three featured
## Legendaries, the centre one large, on light rays in the Legendary color); at the bottom,
## the pity meter (Legendary guaranteed within N pulls) with the Rates button, the free daily
## pull strip (or the time until the next one), and the two summon buttons: x1 (graphite) and
## x10 (orange). Prices use scrolls first, then gems; gem spending asks first; when the player
## can't pay, a strip explains it and links to the Shop.
##
## Summoning plays the full-screen sequence (src/ui/summon/summon_sequence.gd) with the chrome
## hidden: the portal charges and tells the best rarity by its color, bursts, then every hero
## gets their own splash that the player taps through (Epic and Legendary get a held beat and
## a big reveal), then the results with Summon again or Done. "Skip" jumps to the results.
##
## Shot params: rates: true (open the odds), pull: 1|10 (summon right away), skip: true
## (jump straight to the results). Without touching the save: demo: "ten" | "one" | "rare" |
## "epic" | "legendary" plays made-up results (hero: an id for the single ones), card: k
## starts at hero k's reveal, summary: true shows the results, hold: t freezes the clock at
## t seconds (of the charge, or of hero k's reveal with card), autotap: s taps every s
## seconds. frames: "<abs dir>" saves `count` (default 40) PNG frames `every` (default 0.1)
## seconds apart, starting `after` seconds in, for checking motion.

const Roster := preload("res://src/ui/screens/heroes_screen.gd")
const Sequence := preload("res://src/ui/summon/summon_sequence.gd")

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

# Summon sequence (the e2e scripts read _phase, _cards, _showcase and _results).
var _seq: Sequence
var _results: Array = []
## "" (banner), "charge", "reveal" or "results".
var _phase: String:
	get:
		return _seq.phase if _seq != null and is_instance_valid(_seq) else ""
## The result cards once the sequence shows the results.
var _cards: Array:
	get:
		return _seq.cards if _seq != null and is_instance_valid(_seq) else []
## The Legendary being revealed (its big showcase), else null.
var _showcase: Control:
	get:
		return _seq.showcase if _seq != null and is_instance_valid(_seq) else null


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
	if params.has("demo"):
		_shot_demo.call_deferred(params)
	elif params.has("pull"):
		_shot_pull.call_deferred(int(params["pull"]), bool(params.get("skip", false)))
	if params.has("frames"):
		_capture_frames.call_deferred(str(params["frames"]), float(params.get("every", 0.1)), int(params.get("count", 40)), float(params.get("after", 0.0)))


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _shot_pull(count: int, skip: bool) -> void:
	await get_tree().process_frame
	_do_summon(count, count == 1 and Game.free_pull_available())
	if skip and _seq:
		_seq.skip_all()


## Screenshots without touching the save: plays made-up results (see the header).
func _shot_demo(params: Dictionary) -> void:
	await get_tree().process_frame
	_results = _demo_results(str(params.get("demo", "ten")), str(params.get("hero", "")))
	_start_sequence()
	if bool(params.get("summary", false)):
		_seq.skip_all()
	elif params.has("card"):
		_seq.start_at(int(params["card"]), float(params.get("hold", -1.0)))
	elif params.has("hold"):
		_seq.charge_hold = float(params["hold"])
	if params.has("autotap"):
		_autotap(float(params["autotap"]))


## Screenshots: taps the sequence every `every` seconds until the results.
func _autotap(every: float) -> void:
	while _seq != null and is_instance_valid(_seq) and _phase in ["charge", "reveal"]:
		await get_tree().create_timer(every).timeout
		if _seq != null and is_instance_valid(_seq):
			_seq.tap()


static func _demo_results(kind: String, hero: String) -> Array:
	var picks: Array = []
	match kind:
		"ten":
			picks = [["uriela", true], ["kessa", false], ["cassiel", true], ["ashra", false], ["seraphiel", true],
				["imra", false], ["vesper", false], ["nuriel", true], ["lucen", false], ["sable", false]]
		"legendary":
			picks = [[hero if hero != "" else "seraphiel", true]]
		"epic":
			picks = [[hero if hero != "" else "vesper", true]]
		_:
			picks = [[hero if hero != "" else "uriela", false]]
	var out: Array = []
	for p: Array in picks:
		var id := str(p[0])
		var rarity := str(Game.hero_def(id).get("rarity", "rare"))
		var is_new := bool(p[1])
		var shards := 0 if is_new else Progression.dupe_shards(rarity)
		out.append({"hero_id": id, "rarity": rarity, "is_new": is_new, "shards": shards, "dust": 0, "pity": 0})
	return out


## Saves `count` PNG frames of the window, one every `every` seconds, starting `after`
## seconds in (motion checks).
func _capture_frames(dir: String, every: float, count: int, after: float) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if after > 0.0:
		await get_tree().create_timer(after).timeout
	for i in count:
		await get_tree().create_timer(every).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [dir, i])


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
	_start_sequence()


func _start_sequence() -> void:
	UI.set_chrome(false, false)
	var replacing := _seq != null and is_instance_valid(_seq)
	if replacing:
		_seq.queue_free()
	_seq = Sequence.new()
	_seq.name = "SummonSequence"
	add_child(_seq)
	var pity_max := int(_banner.get("pity_legendary", 60))
	_seq.setup(_results, _price, pity_max - Game.pity_count())
	_seq.done.connect(_finish)
	_seq.again.connect(_again)
	_main.visible = false
	_seq.start(not replacing)


## Overlay taps (the e2e scripts call this with simulated releases too).
func _on_overlay_input(ev: InputEvent) -> void:
	if _seq != null and is_instance_valid(_seq):
		_seq.handle_input(ev)


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
	if _seq != null and is_instance_valid(_seq):
		_seq.close()
	_seq = null
	_results.clear()
	UI.set_chrome(true, true)
	_main.visible = true
	_refresh()
	_layout.call_deferred()
