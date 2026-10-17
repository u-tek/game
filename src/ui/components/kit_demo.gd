extends Control
## Hidden screen "kit_demo": every Kit widget on one scrolling page, plus reference mocks of
## the v2 screen layouts (docs/dev/ui-style-v2.md) built only from Kit builders. Screen
## owners can lift the mock code; the UI director shoots them for style reviews.
##   tools/shoot kit_demo --rich --safe-area-sim
##   tools/shoot kit_demo --rich --shoot-params='{"scroll": 1400}'      # scroll down (px)
##   tools/shoot kit_demo --rich --shoot-params='{"mock": "lobby"}'     # lobby | roster | detail
##   tools/shoot kit_demo --rich --shoot-params='{"show": "reward"}'
##       show: reward | confirm | popup | dialog | toast | notices | menu

var _scroll: ScrollContainer


func setup(params: Dictionary) -> void:
	var mock := str(params.get("mock", ""))
	match mock:
		"lobby":
			_mock_lobby()
		"roster":
			_mock_roster()
		"detail":
			_mock_detail(str(params.get("hero_id", "seraphiel")))
		_:
			_gallery(params)
	var show := str(params.get("show", ""))
	if show != "":
		_open.call_deferred(show)


# ------------------------------------------------------------------ gallery

func _gallery(params: Dictionary) -> void:
	var list := Kit.vbox(22)
	_scroll = Kit.scroll(Kit.margin(list, 24, 24))
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_scroll)

	list.add_child(Kit.screen_header("Kit Preview", func() -> void: UI.go("home"), Kit.icon_button("info", func() -> void: _open("popup"), 88)))
	_typography(list)
	_buttons(list)
	_chips(list)
	_currency(list)
	_lobby_widgets(list)
	_cards(list)
	_info(list)
	_progress(list)
	_rewards(list)
	_rows(list)
	_feedback(list)
	list.add_child(Kit.spacer(0, 40))
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))


func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = px


func _open(what: String) -> void:
	match what:
		"reward":
			UI.show_reward("Stage Cleared", {"gold": 12500, "hero_exp": 3400, "gems": 300, "scrolls": 1,
				"dust": 50, "shards": {"seraphiel": 10}, "heroes": ["vesper"]})
		"confirm":
			UI.confirm("Spend 300 gems to summon one hero?", func() -> void: UI.toast("Summoned!"))
		"popup":
			var body := Kit.vbox(14)
			body.add_child(Kit.body("Legendary 2%  -  Epic 18%  -  Rare 80%. A Legendary is guaranteed within 60 pulls.", 26, Kit.INK))
			body.add_child(Kit.progress_bar(23, 60, Kit.LEGENDARY, 26, "Pity 23 / 60"))
			UI.popup("Summon Rates", body)
		"dialog":
			_dialog_demo()
		"toast":
			UI.toast("Not enough gold")
			UI.toast("Quest complete!", "good")
			UI.toast("Your team needs a Guardian", "bad")
		"notices", "menu":
			var b := UI.root.find_child("Top_" + ("Bell" if what == "notices" else "Menu"), true, false) as Button
			if b:
				b.pressed.emit()


## A light v2 dialog like a level reset: hero tiles, a cost strip, materials, the action.
func _dialog_demo() -> void:
	var col := Kit.vbox(16)
	col.custom_minimum_size.x = 560
	var owned := Kit.hbox(6)
	owned.alignment = BoxContainer.ALIGNMENT_END
	owned.add_child(Kit.label("Owned", 20, Kit.TEXT_DIM, "bold"))
	owned.add_child(Kit.currency_icon("dust", 28))
	owned.add_child(Kit.label("1,430", 22, Kit.TEXT, "black"))
	col.add_child(owned)
	var q := Kit.label("Raise Vesper to 3 stars?", 28, Kit.TEXT, "extrabold")
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(q)
	var pair := Kit.hbox(26)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_child(Kit.hero_card("vesper", {"size": 120, "level": 30, "stars": 2, "owned": true}))
	pair.add_child(Kit.icon("arrow_right", 34, Kit.ACCENT))
	pair.add_child(Kit.hero_card("vesper", {"size": 120, "level": 30, "stars": 3, "owned": true}))
	col.add_child(pair)
	var strip := Kit.panel("light_inset", 8)
	var sr := Kit.hbox(8)
	sr.add_child(Kit.label("STAR UP COST", 20, Kit.ACCENT_DEEP, "cond_bold"))
	sr.add_child(Kit.spacer(0, 0, true))
	sr.add_child(Kit.cost_row({"dust": 600}, 22, Kit.TEXT, false))
	strip.add_child(sr)
	col.add_child(strip)
	var note := Kit.body("Stars raise every stat and unlock passives at 3 and 5 stars.", 22, Kit.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	var mats := Kit.panel("light_inset", 12)
	mats.add_child(Kit.reward_list({"dust": 600, "shards": {"vesper": 20}}, 96, false, true, true))
	col.add_child(mats)
	var go := Kit.cost_button("Star Up", "dust", 600, func() -> void: UI.toast("Starred up"))
	go.custom_minimum_size.x = 360
	go.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(go)
	UI.popup("Star Up", col, Callable(), 620.0, true)


func _typography(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Typography"))
	var p := Kit.panel()
	var v := Kit.vbox(10)
	p.add_child(v)
	var name_row := Kit.hbox(14)
	name_row.add_child(Kit.title("Seraphiel", 56))
	name_row.add_child(Kit.rarity_badge("legendary"))
	v.add_child(name_row)
	v.add_child(Kit.header("Chapter 1: Ashen Gate"))
	v.add_child(Kit.body("The last seraph who still sings the hymn that once held the sky together. Every note is a sunrise."))
	var nums := Kit.hbox(24)
	nums.add_child(Kit.number(1234567))
	nums.add_child(Kit.number(12500, 32, Kit.ACCENT_HI))
	nums.add_child(Kit.number("x10", 32, Kit.ORANGE_HI))
	nums.add_child(Kit.label("LV.", 22, Kit.INK, "cond"))
	nums.add_child(Kit.label("01", 52, Kit.INK, "cond_light"))
	v.add_child(nums)
	v.add_child(Kit.caption("Caption: 2h 05m until the Sanctum is full"))
	list.add_child(p)
	list.add_child(Kit.ribbon("Victory"))
	list.add_child(Kit.ribbon("Defeat", 420.0, Kit.EMBER, Color.WHITE, 40))


func _buttons(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Buttons"))
	var g := Kit.grid(2, 14)
	var a := Kit.primary_button("Battle", func() -> void: UI.toast("Primary"), "sword")
	var b := Kit.secondary_button("Formation", func() -> void: UI.toast("Secondary"), "team")
	var c := Kit.orange_button("Campaign", func() -> void: UI.toast("Orange"), "campaign")
	var e := Kit.light_button("Auto-fill", func() -> void: UI.toast("Light"), "refresh")
	var d := Kit.danger_button("Reset Save", func() -> void: UI.toast("Danger"))
	var f := Kit.primary_button("Claimed")
	f.disabled = true
	for x in [a, b, c, e, d, f]:
		(x as Control).size_flags_horizontal = SIZE_EXPAND_FILL
		g.add_child(x)
	list.add_child(g)
	var costs := Kit.hbox(14)
	var c1 := Kit.cost_button("Summon x1", "gems", 300, func() -> void: UI.toast("x1"), "secondary")
	var c2 := Kit.cost_button("Summon x10", "scrolls", 10, func() -> void: UI.toast("x10"))
	c1.size_flags_horizontal = SIZE_EXPAND_FILL
	c2.size_flags_horizontal = SIZE_EXPAND_FILL
	costs.add_child(c1)
	costs.add_child(c2)
	list.add_child(costs)
	var lvl := Kit.hbox(14)
	var l1 := Kit.costs_button("Level Up", {"gold": 1200, "hero_exp": 300})
	var l2 := Kit.costs_button("Star Up", {"dust": 999999}, Callable(), "light")
	l1.size_flags_horizontal = SIZE_EXPAND_FILL
	l2.size_flags_horizontal = SIZE_EXPAND_FILL
	lvl.add_child(l1)
	lvl.add_child(l2)
	list.add_child(lvl)
	var icons := Kit.hbox(4)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in ["back", "close", "settings", "speed", "auto", "skip"]:
		icons.add_child(Kit.icon_button(n, func() -> void: UI.toast(n), 88, "round"))
	list.add_child(icons)
	var icons2 := Kit.hbox(4)
	icons2.alignment = BoxContainer.ALIGNMENT_CENTER
	icons2.add_child(Kit.icon_button("plus", Callable(), 88, "accent"))
	icons2.add_child(Kit.icon_button("info", Callable(), 88, "light"))
	icons2.add_child(Kit.icon_button("lock", Callable(), 88, "bare"))
	icons2.add_child(Kit.toggle(true))
	icons2.add_child(Kit.toggle(false))
	list.add_child(icons2)
	list.add_child(Kit.back_bar(func() -> void: UI.toast("Back"), func() -> void: UI.toast("Home")))


func _chips(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Tabs & Filters"))
	list.add_child(Kit.tab_strip([{"text": "Heroes", "icon": "heroes"}, {"text": "Codex", "icon": "scrolls"}], 0))
	var row := Kit.hbox(8)
	var opts: Array = ["ALL"]
	for r in Kit.ROLES:
		opts.append({"icon": "role_" + r})
	row.add_child(Kit.filter_chips(opts, 0))
	list.add_child(row)
	var row2 := Kit.hbox(8)
	row2.add_child(Kit.filter_chips(["ALL", "I", "II", "III"], 2))
	row2.add_child(Kit.spacer(0, 0, true))
	var sort := Kit.secondary_button("RARITY", Callable(), "sort")
	sort.custom_minimum_size.x = 200
	row2.add_child(sort)
	list.add_child(row2)
	list.add_child(Kit.segmented(["All", {"text": "", "icon": "faction_celestial"}, {"text": "", "icon": "faction_infernal"}, {"text": "", "icon": "faction_fallen"}], 0))
	list.add_child(Kit.segmented(["1x", "2x", "4x"], 1))


func _currency(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Resources"))
	list.add_child(Kit.resource_pill([{"id": "gems", "amount": 30367, "on_plus": func() -> void: UI.toast("Shop")},
		{"id": "gold", "amount": 5881000, "on_plus": func() -> void: UI.toast("Shop")}], 200.0))
	var row := Kit.hbox(10)
	row.add_child(Kit.currency_chip("gold", 12500))
	row.add_child(Kit.currency_chip("gems", 1800, func() -> void: UI.toast("Shop")))
	row.add_child(Kit.currency_chip("scrolls", 10))
	list.add_child(row)
	for names: Array in [["gold", "gems", "scrolls", "hero_exp", "dust", "shard", "power", "star", "star_empty", "crown"],
			["home", "heroes", "team", "summon", "quests", "shop", "sanctum", "campaign", "gift", "mail"],
			["nav_heroes", "nav_team", "nav_lobby", "nav_gear", "nav_summon", "bell", "menu", "eye_off", "timer", "trophy"],
			["stat_hp", "stat_atk", "stat_def", "stat_spd", "stat_crit", "gear_weapon", "gear_armor", "gear_helm", "gear_charm", "skill"],
			["role_guardian", "role_striker", "role_caster", "role_support", "role_assassin", "faction_celestial", "faction_infernal", "faction_fallen", "lock", "upgrade"]]:
		var icons := Kit.hbox(8)
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		for n: String in names:
			icons.add_child(Kit.icon(n, 56))
		list.add_child(icons)


func _lobby_widgets(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Lobby"))
	var stage := Panel.new()
	stage.custom_minimum_size = Vector2(0, 760)
	stage.add_theme_stylebox_override("panel", Kit.box(Color("2a3140"), Color("0d1425"), Color.TRANSPARENT, 4))
	list.add_child(stage)
	var sides := Kit.hbox(4)
	sides.position = Vector2(8, 10)
	sides.add_child(Kit.side_button("gift", "Offers", Callable(), "orange", "N"))
	sides.add_child(Kit.side_button("settings", "Settings", Callable(), "dark"))
	sides.add_child(Kit.side_button("quests", "Daily", Callable(), "accent", "dot"))
	sides.add_child(Kit.side_button("team", "Team", Callable(), "diamond"))
	sides.add_child(Kit.side_button("eye_off", "View", Callable(), "diamond", "N"))
	stage.add_child(sides)
	var sp := Kit.speech_bubble("Seraphiel", "The sky holds as long as we do. Shall we go?", 600)
	sp.position = Vector2(36, 150)
	stage.add_child(sp)
	var bn := Kit.banner_card("Choir of the Fallen Sky", "Summon now", Callable(), {"hero_id": "seraphiel", "pages": 4, "page": 1})
	bn.position = Vector2(10, 290)
	stage.add_child(bn)
	var nb := Kit.notice_bar("Next: Stage 1-3", Callable(), 320)
	nb.position = Vector2(350, 300)
	stage.add_child(nb)
	var meter := Kit.percent_meter("Fill", 31.0, "sanctum")
	var s1 := Kit.shortcut("Shop", "shop", "blue", Callable(), {"size": Vector2(320, 128)})
	s1.position = Vector2(4, 470)
	stage.add_child(s1)
	var s2 := Kit.shortcut("Sanctum", "sanctum", "dark", Callable(), {"size": Vector2(330, 150), "sub": meter, "badge": "N"})
	s2.position = Vector2(4, 600)
	stage.add_child(s2)
	var s3 := Kit.shortcut("Quests", "quests", "white", Callable(), {"size": Vector2(320, 128), "side": "right", "badge": "dot"})
	s3.position = Vector2(348, 470)
	stage.add_child(s3)
	var s4 := Kit.shortcut("Campaign", "campaign", "orange", Callable(), {"size": Vector2(330, 150), "side": "right", "badge": "!"})
	s4.position = Vector2(338, 600)
	stage.add_child(s4)


func _cards(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Hero Cards"))
	var g := Kit.grid(4, 10)
	g.add_child(Kit.portrait_card("seraphiel", {"size": 158, "level": 60, "stars": 6, "owned": true}))
	g.add_child(Kit.portrait_card("mordessa", {"size": 158, "level": 42, "stars": 4, "owned": true, "dot": true}))
	g.add_child(Kit.portrait_card("cassiel", {"size": 158, "level": 18, "owned": true, "selected": true}))
	g.add_child(Kit.portrait_card("noctaire", {"size": 158, "owned": false}))
	g.add_child(Kit.portrait_card("kessa", {"size": 158, "level": 7, "stars": 1, "owned": true, "new": true}))
	g.add_child(Kit.portrait_card("liora", {"size": 158, "level": 25, "stars": 3, "owned": true, "checked": true}))
	g.add_child(Kit.portrait_card("lucen", {"size": 158, "level": 12, "stars": 2, "owned": true, "locked": true}))
	g.add_child(Kit.portrait_card("brakka", {"size": 158, "level": 30, "stars": 2, "owned": true, "tag": "BOSS"}))
	var page := Panel.new()
	page.add_theme_stylebox_override("panel", Kit.style("paper", 14))
	var pm := Kit.margin(g, 12, 14)
	page.add_child(pm)
	page.custom_minimum_size = Vector2(0, 600)
	list.add_child(page)
	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Kit.hero_card("seraphiel", {"size": 132, "level": 80, "stars": 5, "owned": true, "show_name": true}))
	row.add_child(Kit.hero_card("vesper", {"size": 132, "level": 5, "owned": true, "tag": "N", "show_name": true}))
	row.add_child(Kit.hero_card("orrin", {"size": 132, "level": 3, "owned": false, "show_name": true}))
	row.add_child(Kit.empty_slot(132, "Front"))
	list.add_child(row)
	var badges := Kit.hbox(14)
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	badges.add_child(Kit.hex_badge("role_caster", 56, Color("ffffff"), Color("111c31")))
	badges.add_child(Kit.hex_badge("", 56, Color("182640"), Color.WHITE, "III"))
	badges.add_child(Kit.hex_badge("skill", 56, Kit.ACCENT, Color.WHITE))
	badges.add_child(Kit.hex_badge("faction_infernal", 56, Color("182640")))
	badges.add_child(Kit.new_badge(34))
	var bang := Kit.new_badge(34, "!")
	bang.set("round", true)
	bang.set("color", Kit.ACCENT)
	badges.add_child(bang)
	badges.add_child(Kit.dot(24))
	list.add_child(badges)
	var tags := Kit.flow(10, true)
	for x in ["rare", "epic", "legendary"]:
		tags.add_child(Kit.rarity_badge(x))
	tags.add_child(Kit.tag("NEW", Kit.NEW_RED))
	tags.add_child(Kit.tag("BOSS", Kit.EMBER))
	tags.add_child(Kit.tag("+20%", Kit.GOOD, Kit.TEXT))
	for r in ["guardian", "caster"]:
		tags.add_child(Kit.role_badge(r, 32))
	for f in Kit.FACTIONS:
		tags.add_child(Kit.faction_badge(f, 36))
	list.add_child(tags)


func _info(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Info Panel"))
	var p := Kit.info_panel()
	var v := Kit.vbox(12)
	p.add_child(v)
	v.add_child(Kit.rarity_mark("legendary", 40))
	v.add_child(Kit.name_plate(60, 80, "Seraphiel"))
	var pw := Kit.hbox(12)
	pw.add_child(Kit.hex_badge("", 64, Color("182640"), Color.WHITE, "III"))
	var pv := Kit.vbox(0)
	pv.add_child(Kit.label("POWER", 18, Kit.TEXT_DIM, "cond_bold"))
	pv.add_child(Kit.label("12,924", 48, Kit.TEXT, "title"))
	pw.add_child(pv)
	v.add_child(pw)
	v.add_child(Kit.header_bar("Status"))
	var i := 0
	for s: Array in [["hp", 18930, 320], ["atk", 4034, 41], ["def", 668, null], ["spd", 108, null], ["crit", "15%", null]]:
		var rp := Kit.panel("row" if i % 2 == 0 else "light_inset", 0)
		var rm := Kit.margin(Kit.stat_row(s[0], s[1], s[2], "", true), 12, 0)
		rp.add_child(rm)
		v.add_child(rp)
		i += 1
	v.add_child(Kit.header_bar("Equip"))
	var eq := Kit.grid(2, 10)
	eq.add_child(Kit.equip_slot("weapon", {"slot": "weapon", "tier": 4}, 150))
	eq.add_child(Kit.equip_slot("armor", {"slot": "armor", "tier": 2}, 150))
	eq.add_child(Kit.equip_slot("helm", {}, 150))
	eq.add_child(Kit.equip_slot("charm", {"slot": "charm", "tier": 5}, 150))
	v.add_child(Kit.center(eq))
	list.add_child(p)


func _progress(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Progress"))
	var p := Kit.panel("card")
	var v := Kit.vbox(16)
	p.add_child(v)
	v.add_child(Kit.progress_bar(820, 1000, Kit.GOOD, 14))
	v.add_child(Kit.progress_bar(45, 100, Kit.ACCENT, 26, "EXP 45 / 100"))
	v.add_child(Kit.progress_bar(9, 12, Kit.ORANGE, 32, "Sanctum 9h / 12h"))
	var stars := Kit.hbox(24)
	stars.add_child(Kit.star_row(3, 6, 34))
	stars.add_child(Kit.star_row(6, 0, 28))
	v.add_child(stars)
	list.add_child(p)
	var lp := Kit.info_panel()
	lp.add_child(Kit.progress_bar(23, 60, Kit.LEGENDARY, 24, "Pity 23 / 60", true))
	list.add_child(lp)


func _rewards(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Rewards"))
	var p := Kit.panel("inset")
	p.add_child(Kit.reward_list({"gold": 12500, "hero_exp": 3400, "gems": 300, "scrolls": 2, "dust": 40,
		"shards": {"noctaire": 20}, "heroes": ["sable"]}, 104))
	list.add_child(p)


func _rows(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Rows & Panels"))
	for q: Array in [["Win 3 battles", 3, 3, false], ["Summon once", 0, 1, false], ["Claim the Sanctum", 1, 1, true]]:
		var row := Kit.card()
		var h := Kit.hbox(14)
		row.add_child(h)
		h.add_child(Kit.hex_badge("quests", 64, Kit.ACCENT if q[1] >= q[2] else Color("1b2a47")))
		var mid := Kit.vbox(6)
		mid.size_flags_horizontal = SIZE_EXPAND_FILL
		mid.add_child(Kit.label(q[0], 26, Kit.INK, "extrabold"))
		mid.add_child(Kit.progress_bar(q[1], q[2], Kit.ACCENT, 18, "%d / %d" % [q[1], q[2]]))
		h.add_child(mid)
		var done: bool = q[1] >= q[2]
		var btn: Button
		if q[3]:
			btn = Kit.secondary_button("Done")
			btn.disabled = true
		elif done:
			btn = Kit.primary_button("Claim", func() -> void: UI.show_reward("Quest Complete", {"gems": 50}))
		else:
			btn = Kit.secondary_button("Go")
		btn.custom_minimum_size.x = 150
		h.add_child(btn)
		if done and not q[3]:
			Kit.set_dot(btn, true)
		list.add_child(row)
	var stats := Kit.panel("glass")
	var sv := Kit.vbox(4)
	stats.add_child(sv)
	sv.add_child(Kit.stat_row("hp", 12840, 320))
	sv.add_child(Kit.stat_row("atk", 1532, 41))
	sv.add_child(Kit.stat_row("def", 612))
	list.add_child(stats)
	var inset := Kit.panel("light_inset")
	inset.add_child(Kit.empty_state("No gear yet. Clear stages to find some.", "gear_weapon", true))
	list.add_child(inset)


func _feedback(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Feedback"))
	var g := Kit.grid(2, 14)
	for pair: Array in [["Toast", "toast"], ["Reward", "reward"], ["Confirm", "confirm"], ["Dialog", "dialog"], ["Popup", "popup"], ["Notices", "notices"]]:
		var what: String = pair[1]
		var b := Kit.secondary_button(pair[0], func() -> void: _open(what))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		g.add_child(b)
	list.add_child(g)
	var sounds := Kit.flow(10, true)
	for s in ["tap", "reward", "summon", "legendary", "hit", "ult", "victory", "defeat"]:
		var sb := Kit.segmented([s], -1)
		var snd: String = s
		(sb.get_child(0) as Button).toggle_mode = false
		(sb.get_child(0) as Button).pressed.connect(func() -> void: UI.sfx(snd))
		sb.custom_minimum_size.x = 160
		sounds.add_child(sb)
	list.add_child(sounds)


# ------------------------------------------------------------------ mock: lobby

## The v2 lobby: full-bleed art under translucent chrome, a speech line, side buttons and
## the four big shortcut plates.
func _mock_lobby() -> void:
	UI.set_full_bleed(true)
	var hero := "seraphiel"
	add_child(Kit.art_background(HeroArt.background("home"), 0.0))
	var art := TextureRect.new()
	art.name = "LobbyHero"
	art.texture = HeroArt.texture(hero)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(art)
	var shade := TextureRect.new()
	shade.texture = Kit.vgradient(Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.anchor_top = 0.55
	shade.anchor_right = 1.0
	shade.anchor_bottom = 1.0
	add_child(shade)

	var ui := Control.new()
	ui.name = "LobbyUI"
	ui.mouse_filter = MOUSE_FILTER_IGNORE
	ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(ui)
	var top := UI.content_top() + 10.0
	var bottom := UI.content_bottom()
	var vh := get_viewport_rect().size.y
	var w := get_viewport_rect().size.x
	# Hero: full body, feet just behind the nav.
	var ah := vh - top + 40.0
	art.position = Vector2((w - ah * 0.5) * 0.5, top - 60.0)
	art.size = Vector2(ah * 0.5, ah)

	var banner := Kit.banner_card(str(Game.banner().get("name", "Summon")), "Summon now", func() -> void: UI.go("summon"),
		{"hero_id": "noctaire", "pages": 4, "page": 0, "size": Vector2(330, 132)})
	banner.position = Vector2(14, top)
	ui.add_child(banner)
	var st: Dictionary = Game.current_stage()
	var nb := Kit.notice_bar("Next: Stage %s" % str(st.get("id", "1-1")), func() -> void: UI.go("campaign"), 340)
	nb.position = Vector2(w - 340 - 10, top + 12)
	ui.add_child(nb)

	var lx := 6.0
	var ly := top + 176.0
	var s1 := Kit.side_button("gift", "Offers", func() -> void: UI.go("shop"), "orange", "N")
	s1.position = Vector2(lx, ly)
	ui.add_child(s1)
	var s2 := Kit.side_button("quests", "Daily", func() -> void: UI.go("quests"), "dark", "dot")
	s2.position = Vector2(lx, ly + 128)
	ui.add_child(s2)
	var rx := w - 104.0 - 6.0
	var r1 := Kit.side_button("team", "Team", func() -> void: UI.go("formation"), "dark", "dot")
	r1.position = Vector2(rx, ly)
	ui.add_child(r1)
	var r2 := Kit.side_button("eye_off", "View", Callable(), "dark")
	r2.position = Vector2(rx, ly + 128)
	ui.add_child(r2)
	r2.pressed.connect(func() -> void:
		ui.visible = false
		UI.set_chrome(false, false)
		var back := Button.new()
		back.theme_type_variation = &"BareButton"
		back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(back)
		back.pressed.connect(func() -> void:
			back.queue_free()
			ui.visible = true
			UI.set_chrome(true, true)))

	# Character switch arrows.
	for side: int in [-1, 1]:
		var ar := Kit.icon("chevron_right", 44, Color(1, 1, 1, 0.75))
		ar.flip_h = side < 0
		ar.position = Vector2(8 if side < 0 else w - 52, vh * 0.5 - 22)
		ui.add_child(ar)

	var speech := Kit.speech_bubble(str(Game.hero_def(hero).get("name", hero)), "The sky holds as long as we do. Shall we go?", 400)
	speech.position = Vector2(84, vh * 0.5 - 40)
	ui.add_child(speech)

	# Shortcut plates, bottom-left and bottom-right.
	var by := vh - bottom - 302.0
	var idle: Dictionary = Game.idle_status()
	var pct := 100.0 * float(idle.get("elapsed_ms", 0)) / maxf(float(idle.get("cap_ms", 1)), 1.0)
	var meter := Kit.percent_meter("Fill", pct, "sanctum")
	var shop := Kit.shortcut("Shop", "shop", "blue", func() -> void: UI.go("shop"), {"size": Vector2(268, 116)})
	shop.position = Vector2(8, by)
	ui.add_child(shop)
	var sanctum := Kit.shortcut("Sanctum", "sanctum", "dark", func() -> void: UI.go("home"), {"size": Vector2(304, 150), "sub": meter, "badge": "N" if bool(idle.get("full", false)) else ""})
	sanctum.position = Vector2(8, by + 124)
	sanctum.call("set_title_tag", "LV %d" % (Game.cleared_count() + 1))
	ui.add_child(sanctum)
	var quests := Kit.shortcut("Quests", "quests", "white", func() -> void: UI.go("quests"), {"size": Vector2(268, 116), "side": "right", "badge": "dot" if Game.quests_ready_count() > 0 else ""})
	quests.position = Vector2(w - 268 - 8, by)
	ui.add_child(quests)
	var boss := ""
	for e: Variant in st.get("enemies", []):
		if e is Dictionary and bool((e as Dictionary).get("is_boss", false)):
			boss = str((e as Dictionary).get("hero_id", ""))
	if boss == "" and not (st.get("enemies", []) as Array).is_empty():
		boss = str(((st.get("enemies", []) as Array)[0] as Dictionary).get("hero_id", ""))
	var camp := Kit.shortcut("Campaign", "campaign", "orange", func() -> void: UI.go("campaign"), {"size": Vector2(304, 150), "side": "right", "badge": "!",
		"art": Kit.art_crop(boss, 2.2, 1.4) if boss != "" else null, "art_caption": "STAGE %s" % str(st.get("id", "1-1"))})
	camp.position = Vector2(w - 304 - 8, by + 124)
	ui.add_child(camp)


# ------------------------------------------------------------------ mock: roster

## The v2 roster: page tab and buttons on the dark header, then a light hatched page with
## filter chips, a hint line and the 4-column portrait-card grid.
func _mock_roster() -> void:
	var head := Kit.hbox(10)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Heroes", "icon": "heroes"}], 0, Callable(), 230.0))
	head.add_child(Kit.spacer(0, 0, true))
	var team := Kit.secondary_button("Team", func() -> void: UI.go("formation"), "team")
	team.custom_minimum_size.x = 176
	head.add_child(team)
	var codex := Kit.secondary_button("Codex", Callable(), "codex")
	codex.custom_minimum_size.x = 176
	head.add_child(codex)
	add_child(head)
	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)
	var col := Kit.vbox(10)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = 10 + Kit.BUTTON_H + 18
	col.offset_left = 18
	col.offset_right = -18
	add_child(col)
	var chips := Kit.hbox(6)
	var opts: Array = ["ALL"]
	for r in ["guardian", "striker", "caster", "support"]:
		opts.append({"icon": "role_" + r})
	chips.add_child(Kit.filter_chips(opts, 0))
	chips.add_child(Kit.spacer(0, 0, true))
	var sort := Kit.secondary_button("RARITY", Callable(), "sort")
	sort.custom_minimum_size.x = 180
	sort.add_theme_font_override("font", Kit.font("cond_bold"))
	chips.add_child(sort)
	col.add_child(chips)
	col.add_child(Kit.caption("Heroes you can place in your team.", 20, Kit.TEXT_DIM))
	var g := Kit.grid(4, 12)
	var ids: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		ids.append(str(h.id))
	for d: Dictionary in Game.all_hero_defs():
		if not ids.has(str(d.id)):
			ids.append(str(d.id))
	var i := 0
	for id in ids:
		g.add_child(Kit.portrait_card(id, {"size": 160, "new": i == 2, "dot": i == 1,
			"on_pressed": func() -> void: UI.go("hero_detail", {"hero_id": id})}))
		i += 1
	col.add_child(Kit.scroll(Kit.margin(g, 2, 6)))


# ------------------------------------------------------------------ mock: hero detail

## The v2 hero detail: big art centre-left on a light page with a faction-colored stripe
## band, the white info column on the right, side tabs, back/home bottom-left.
func _mock_detail(hero: String) -> void:
	UI.set_chrome(true, false)
	var def := Game.hero_def(hero)
	var h: Dictionary = Game.hero(hero)
	var owned := not h.is_empty()
	var lv := int(h.get("level", 1))
	var faction := str(def.get("faction", "celestial"))
	add_child(Kit.page_bg("light"))
	var stripes := Kit.deco("hatch", Vector2(720, 520), Color(Kit.faction_color(faction), 0.22))
	stripes.set("spacing", 46.0)
	stripes.set("line_width", 18.0)
	stripes.anchor_top = 1.0
	stripes.anchor_bottom = 1.0
	stripes.offset_top = -520
	stripes.offset_right = 720
	add_child(stripes)
	var vh := size.y if size.y > 0.0 else get_viewport_rect().size.y - UI.content_top()
	var art := TextureRect.new()
	art.texture = HeroArt.texture(hero)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = MOUSE_FILTER_IGNORE
	var ah := vh * 1.02
	art.size = Vector2(ah * 0.5, ah)
	art.position = Vector2(-60, 10)
	add_child(art)
	# Left technical caption.
	var cap := Kit.vbox(2)
	cap.position = Vector2(20, 14)
	cap.add_child(Kit.hex_badge("role_" + str(def.get("role", "")), 64, Color("182640")))
	cap.add_child(Kit.label("HERO\nINFORMATION", 16, Kit.TEXT_DIM, "cond_bold"))
	cap.add_child(Kit.deco("techline", Vector2(120, 10), Color(0, 0, 0, 0.3)))
	add_child(cap)

	var colw := 352.0
	var compact := vh < 1250.0
	var slot_sz := 128.0 if compact else 150.0
	var info := Kit.vbox(8 if compact else 10)
	info.position = Vector2(720 - colw - 14, 96.0 if compact else 150.0)
	info.custom_minimum_size.x = colw
	add_child(info)
	var rr := Kit.hbox(8)
	rr.add_child(Kit.rarity_mark(str(def.get("rarity", "rare")), 34))
	rr.add_child(Kit.spacer(0, 0, true))
	rr.add_child(Kit.deco("pips", Vector2(80, 14), Color("ffd25a")))
	info.add_child(rr)
	info.add_child(Kit.name_plate(lv, int(Game.max_level(hero)), str(def.get("name", hero)), 30))
	var pw := Kit.hbox(12)
	pw.add_child(Kit.hex_badge("", 66, Color("182640"), Color.WHITE, str(Kit.RARITY_TIER.get(str(def.get("rarity", "rare")), "I"))))
	var pv := Kit.vbox(0)
	pv.add_child(Kit.label("POWER", 18, Kit.TEXT_DIM, "cond_bold"))
	pv.add_child(Kit.label(Kit.format_full(int(Game.hero_power(hero))), 50, Kit.TEXT, "title"))
	pw.add_child(pv)
	info.add_child(pw)
	var panel := Kit.info_panel(12)
	var pvb := Kit.vbox(4)
	panel.add_child(pvb)
	pvb.add_child(Kit.header_bar("Status"))
	var stats: Dictionary = Game.hero_stats(hero) if owned else def.get("base_stats", {})
	var i := 0
	for s in ["hp", "atk", "def", "spd"]:
		var rp := Kit.panel("row" if i % 2 == 0 else "light_inset", 0)
		rp.add_child(Kit.margin(Kit.stat_row(s, int(stats.get(s, 0)), null, "", true), 10, 0))
		pvb.add_child(rp)
		i += 1
	var btns := Kit.hbox(8)
	var up := Kit.light_button("Level Up")
	up.size_flags_horizontal = SIZE_EXPAND_FILL
	up.add_theme_font_size_override("font_size", 26)
	var star := Kit.primary_button("Star Up")
	star.size_flags_horizontal = SIZE_EXPAND_FILL
	star.add_theme_font_size_override("font_size", 26)
	btns.add_child(up)
	btns.add_child(star)
	pvb.add_child(Kit.spacer(0, 4))
	pvb.add_child(btns)
	info.add_child(panel)
	var skills := Kit.hbox(8)
	skills.alignment = BoxContainer.ALIGNMENT_CENTER
	skills.add_child(Kit.hex_badge("skill", 74, Kit.EMBER))
	for k in 3:
		skills.add_child(Kit.hex_badge("lock" if k > 0 else "skill", 74, Color("ffffff"), Color("1b2b48")))
	info.add_child(skills)
	var eqp := Kit.info_panel(12)
	var ev := Kit.vbox(8)
	eqp.add_child(ev)
	ev.add_child(Kit.header_bar("Equip"))
	var eg := Kit.grid(2, 10)
	for slot in ["weapon", "armor", "helm", "charm"]:
		var item := {}
		for it: Dictionary in Game.gear_items():
			if str(it.get("equipped_by", "")) == hero and str(it.slot) == slot:
				item = it
		eg.add_child(Kit.equip_slot(slot, item, slot_sz))
	ev.add_child(Kit.center(eg))
	info.add_child(eqp)
	# Side tabs (Equip / Skills), left of the info column.
	var tabs := Kit.vbox(8)
	tabs.position = Vector2(720 - colw - 14 - 96, 600.0 if compact else 690.0)
	tabs.add_child(Kit.side_button("equip", "Equip", Callable(), "accent"))
	tabs.add_child(Kit.side_button("skill", "Skills", Callable(), "dark"))
	add_child(tabs)
	var bb := Kit.back_bar()
	bb.anchor_top = 1.0
	bb.anchor_bottom = 1.0
	bb.offset_left = 14
	bb.offset_top = -Kit.BUTTON_H - 14 - UI.safe_bottom()
	bb.offset_bottom = -14 - UI.safe_bottom()
	add_child(bb)
	# Previous-hero chevron (the next one sits under the info column's right edge).
	var ar := Kit.icon("chevron_right", 44, Color(0, 0, 0, 0.35))
	ar.flip_h = true
	ar.position = Vector2(4, vh * 0.45)
	add_child(ar)
