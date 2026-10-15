extends Control
## Hidden screen "kit_demo": every Kit widget on one scrolling page, for reviewing the look.
##   tools/shoot kit_demo --safe-area-sim
##   tools/shoot kit_demo --shoot-params='{"scroll": 1400}'      # scroll down (px)
##   tools/shoot kit_demo --shoot-params='{"show": "reward"}'    # reward | confirm | popup | toast

var _scroll: ScrollContainer


func setup(params: Dictionary) -> void:
	var list := Kit.vbox(22)
	_scroll = Kit.scroll(Kit.margin(list, 24, 24))
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_scroll)

	var t := Kit.title("Halo & Horn")
	list.add_child(t)
	var sub := Kit.caption("UI kit preview: every shared widget", 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(sub)

	_typography(list)
	_buttons(list)
	_currency(list)
	_progress(list)
	_badges(list)
	_heroes(list)
	_rewards(list)
	_panels(list)
	_feedback(list)
	list.add_child(Kit.spacer(0, 40))

	var show := str(params.get("show", ""))
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))
	if show != "":
		_open.call_deferred(show)


func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = px


func _open(what: String) -> void:
	match what:
		"reward":
			UI.show_reward("Stage Cleared!", {"gold": 12500, "hero_exp": 3400, "gems": 300, "scrolls": 1,
				"dust": 50, "shards": {"seraphiel": 10}, "heroes": ["vesper"]})
		"confirm":
			UI.confirm("Spend 300 gems to summon one hero?", func() -> void: UI.toast("Summoned!"))
		"popup":
			var body := Kit.vbox(14)
			body.add_child(Kit.body("Legendary 2%  -  Epic 18%  -  Rare 80%. A Legendary is guaranteed within 60 pulls.", 26, Kit.INK))
			body.add_child(Kit.progress_bar(23, 60, Kit.LEGENDARY, 26, "Pity 23 / 60"))
			UI.popup("Summon Rates", body)
		"toast":
			UI.toast("Not enough gold")
			UI.toast("Quest complete!", "good")
			UI.toast("Your team needs a Guardian", "bad")


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
	nums.add_child(Kit.number(12500, 32, Kit.GOLD_LIGHT))
	nums.add_child(Kit.number("x10", 32, Kit.GOOD))
	v.add_child(nums)
	v.add_child(Kit.caption("Caption: 2h 05m until the idle chest is full"))
	list.add_child(p)


func _buttons(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Buttons"))
	var g := Kit.grid(2, 16)
	var a := Kit.primary_button("Battle", func() -> void: UI.toast("Primary"), "speed")
	var b := Kit.secondary_button("Formation", func() -> void: UI.toast("Secondary"))
	var c := Kit.danger_button("Reset Save", func() -> void: UI.toast("Danger"))
	var d := Kit.primary_button("Claimed")
	d.disabled = true
	for x in [a, b, c, d]:
		(x as Control).size_flags_horizontal = SIZE_EXPAND_FILL
		g.add_child(x)
	list.add_child(g)
	var costs := Kit.hbox(16)
	var c1 := Kit.cost_button("Summon x1", "gems", 300, func() -> void: UI.toast("x1"), "secondary")
	var c2 := Kit.cost_button("Summon x10", "scrolls", 10, func() -> void: UI.toast("x10"))
	c1.size_flags_horizontal = SIZE_EXPAND_FILL
	c2.size_flags_horizontal = SIZE_EXPAND_FILL
	costs.add_child(c1)
	costs.add_child(c2)
	list.add_child(costs)
	var icons := Kit.hbox(6)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in ["back", "close", "settings", "speed", "auto", "skip"]:
		icons.add_child(Kit.icon_button(n, func() -> void: UI.toast(n), 88, "round"))
	list.add_child(icons)
	var icons2 := Kit.hbox(6)
	icons2.alignment = BoxContainer.ALIGNMENT_CENTER
	icons2.add_child(Kit.icon_button("plus", Callable(), 88, "gold"))
	icons2.add_child(Kit.icon_button("info", Callable(), 88, "round"))
	icons2.add_child(Kit.icon_button("lock", Callable(), 88, "bare"))
	icons2.add_child(Kit.icon_button("check", Callable(), 88, "bare"))
	var tg := Kit.toggle(true)
	icons2.add_child(tg)
	icons2.add_child(Kit.toggle(false))
	list.add_child(icons2)
	list.add_child(Kit.segmented(["All", {"text": "", "icon": "faction_celestial"}, {"text": "", "icon": "faction_infernal"}, {"text": "", "icon": "faction_fallen"}], 0))
	list.add_child(Kit.segmented(["1x", "2x", "4x"], 1))


func _currency(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Currencies"))
	var row := Kit.hbox(10)
	row.add_child(Kit.currency_chip("gold", 12500))
	row.add_child(Kit.currency_chip("gems", 1800, func() -> void: UI.toast("Shop")))
	row.add_child(Kit.currency_chip("scrolls", 10))
	list.add_child(row)
	var row2 := Kit.hbox(10)
	row2.add_child(Kit.currency_chip("hero_exp", 3400000))
	row2.add_child(Kit.currency_chip("dust", 950))
	list.add_child(row2)
	var icons := Kit.hbox(10)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in ["gold", "gems", "scrolls", "hero_exp", "dust", "shard", "power", "star", "chest", "lock"]:
		icons.add_child(Kit.icon(n, 56))
	list.add_child(icons)
	var icons2 := Kit.hbox(10)
	icons2.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in ["home", "heroes", "summon", "quests", "shop", "sword", "gift", "arrow_up", "refresh", "map"]:
		icons2.add_child(Kit.icon(n, 56))
	list.add_child(icons2)
	var icons3 := Kit.hbox(10)
	icons3.alignment = BoxContainer.ALIGNMENT_CENTER
	for n in ["stat_hp", "stat_atk", "stat_def", "stat_spd", "stat_crit", "gear_weapon", "gear_armor", "gear_helm", "gear_charm", "crown"]:
		icons3.add_child(Kit.icon(n, 56))
	list.add_child(icons3)


func _progress(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Progress"))
	var p := Kit.panel("card")
	var v := Kit.vbox(16)
	p.add_child(v)
	v.add_child(Kit.progress_bar(820, 1000, Kit.GOOD, 22))
	v.add_child(Kit.progress_bar(45, 100, Kit.SKY, 28, "EXP 45 / 100"))
	v.add_child(Kit.progress_bar(9, 12, Kit.GOLD, 36, "Idle chest 9h / 12h"))
	var stars := Kit.hbox(24)
	stars.add_child(Kit.star_row(3, 6, 36))
	stars.add_child(Kit.star_row(6, 0, 30))
	v.add_child(stars)
	list.add_child(p)


func _badges(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Factions & Roles"))
	var p := Kit.panel("card")
	var v := Kit.vbox(14)
	p.add_child(v)
	var f := Kit.hbox(26)
	for x in Kit.FACTIONS:
		f.add_child(Kit.faction_badge(x, 44))
	v.add_child(f)
	var r := Kit.flow(10)
	for x in Kit.ROLES:
		r.add_child(Kit.role_badge(x))
	v.add_child(r)
	var tags := Kit.flow(10)
	for x in ["rare", "epic", "legendary"]:
		tags.add_child(Kit.rarity_badge(x))
	tags.add_child(Kit.tag("NEW"))
	tags.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE))
	tags.add_child(Kit.tag("+20%", Kit.GOOD, Color("0d2a1e")))
	v.add_child(tags)
	list.add_child(p)


func _heroes(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Hero Cards"))
	var g := Kit.grid(4, 14)
	g.add_child(Kit.hero_card("seraphiel", {"level": 60, "stars": 6, "owned": true, "selected": true, "show_name": true}))
	g.add_child(Kit.hero_card("mordessa", {"level": 42, "stars": 4, "owned": true, "show_name": true, "dot": true}))
	g.add_child(Kit.hero_card("noctaire", {"owned": false, "show_name": true}))
	g.add_child(Kit.hero_card("cassiel", {"level": 18, "owned": true, "locked": true, "show_name": true}))
	g.add_child(Kit.hero_card("liora", {"level": 25, "stars": 3, "owned": true, "checked": true, "show_name": true}))
	g.add_child(Kit.hero_card("kessa", {"level": 7, "stars": 1, "owned": true, "tag": "NEW", "show_name": true}))
	g.add_child(Kit.hero_card("lucen", {"level": 12, "stars": 2, "owned": true, "show_name": true}))
	g.add_child(Kit.hero_card("brakka", {"level": 30, "stars": 2, "owned": true, "tag": "BOSS", "show_name": true}))
	list.add_child(Kit.center(g))
	var big := Kit.hbox(18)
	big.alignment = BoxContainer.ALIGNMENT_CENTER
	big.add_child(Kit.hero_card("seraphiel", {"size": 200, "level": 80, "stars": 5, "owned": true}))
	big.add_child(Kit.hero_card("vesper", {"size": 110, "level": 5, "owned": true}))
	big.add_child(Kit.hero_card("orrin", {"size": 88, "level": 3, "owned": true}))
	list.add_child(big)


func _rewards(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Rewards"))
	var p := Kit.panel("inset")
	p.add_child(Kit.reward_list({"gold": 12500, "hero_exp": 3400, "gems": 300, "scrolls": 2, "dust": 40,
		"shards": {"noctaire": 20}, "heroes": ["sable"]}, 104))
	list.add_child(p)


func _panels(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Panels & Rows"))
	# Quest-like rows.
	for q: Array in [["Win 3 battles", 3, 3, false], ["Summon once", 0, 1, false], ["Claim idle rewards", 1, 1, true]]:
		var row := Kit.card()
		var h := Kit.hbox(14)
		row.add_child(h)
		h.add_child(Kit.icon("quests", 60))
		var mid := Kit.vbox(6)
		mid.size_flags_horizontal = SIZE_EXPAND_FILL
		mid.add_child(Kit.label(q[0], 26, Kit.INK, "extrabold"))
		mid.add_child(Kit.progress_bar(q[1], q[2], Kit.GOOD, 20, "%d / %d" % [q[1], q[2]]))
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
	sv.add_child(Kit.stat_row("spd", 108))
	sv.add_child(Kit.stat_row("crit", "15%"))
	list.add_child(stats)
	var inset := Kit.panel("inset")
	inset.add_child(Kit.empty_state("No gear yet. Clear stages to find some.", "gear_weapon"))
	list.add_child(inset)


func _feedback(list: VBoxContainer) -> void:
	list.add_child(Kit.section_header("Feedback"))
	var g := Kit.grid(2, 16)
	for pair: Array in [["Toast", "toast"], ["Reward", "reward"], ["Confirm", "confirm"], ["Popup", "popup"]]:
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
		sb.custom_minimum_size.x = 150
		sounds.add_child(sb)
	list.add_child(sounds)
