extends Control
## Battle result overlay (style v2). show_victory(): cyan rays and a "VICTORY" ribbon, stars
## by survivors, then a white panel with the MVP and the first-clear rewards (pale item
## tiles), Lobby (light) and Next Stage (orange). show_defeat(): an ember "DEFEAT" ribbon,
## the power check and what to try next (level up, team, counter faction) as white rows,
## Lobby and Retry. Buttons call on_action(name) with "home" | "next" | "retry" | "campaign"
## | "heroes" | "formation" | "level" (the team hero Guide.level_target() names). Early on,
## Guide highlights the suggested button.

const StageInfo := preload("res://src/ui/battle/stage_info.gd")

var on_action: Callable
var _col: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _frame(safe_top: float, safe_bottom: float) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.3)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.offset_top = safe_top
	holder.offset_bottom = -safe_bottom
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_col = Kit.vbox(14)
	_col.custom_minimum_size.x = 660
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(_col)


func _emit(action_name: String) -> void:
	if on_action.is_valid():
		on_action.call(action_name)


## White result panel (reward popup look) with a technical caption at the top.
func _panel(caption: String) -> Array:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	panel.add_theme_stylebox_override("panel", UITheme.style("reward_panel"))
	var pv := Kit.vbox(14)
	panel.add_child(pv)
	var head := Kit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(Kit.deco("techline", Vector2(140, 10), Color(0, 0, 0, 0.25)))
	head.add_child(Kit.label(caption, 22, Kit.TEXT_DIM, "cond_bold"))
	var tl := Kit.deco("techline", Vector2(140, 10), Color(0, 0, 0, 0.25))
	tl.scale.x = -1
	tl.pivot_offset = Vector2(70, 5)
	head.add_child(tl)
	pv.add_child(head)
	return [panel, pv]


## data: stage, outcome, reward, first_clear, stars (1-3), team_size, mvp {hero_id, damage,
## share}, has_next (bool), next_text, safe_top, safe_bottom.
func show_victory(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var head := Control.new()
	head.custom_minimum_size = Vector2(660, 160)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rays := Kit.rays(Kit.ACCENT_HI, 640.0, 18)
	rays.position = Vector2(330 - 320, 80 - 320)
	rays.modulate.a = 0.7
	head.add_child(rays)
	var glow := Kit.glow(Kit.ACCENT, 460)
	glow.position = Vector2(330 - 230, 80 - 230)
	glow.modulate.a = 0.5
	head.add_child(glow)
	var rib := Kit.ribbon("Victory", 560, Kit.ACCENT, Color.WHITE, 56)
	rib.position = Vector2(50, 80 - 58)
	rib.size = Vector2(560, 116)
	head.add_child(rib)
	_col.add_child(head)

	var stars := Kit.hbox(6)
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n_stars := int(data.get("stars", 3))
	var star_nodes: Array[Control] = []
	for i in 3:
		var st := Kit.icon("star" if i < n_stars else "star_empty", 92 if i == 1 else 76)
		st.size_flags_vertical = Control.SIZE_SHRINK_END if i != 1 else Control.SIZE_SHRINK_BEGIN
		stars.add_child(st)
		star_nodes.append(st)
	_col.add_child(stars)
	var out: Dictionary = data.get("outcome", {})
	var team_size := maxi(1, int(data.get("team_size", 5)))
	var sub := Kit.label(("Cleared in %s  ·  %d of %d heroes standing" % [Kit.format_time(int(out.get("duration_ms", 0))), int(out.get("allies_alive", 0)), team_size]).to_upper(), 20, Kit.INK_DIM, "cond_bold")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(sub)

	var pp := _panel("RESULT")
	var panel: PanelContainer = pp[0]
	var pv: VBoxContainer = pp[1]
	var mvp: Dictionary = data.get("mvp", {})
	if not mvp.is_empty():
		var row := Kit.hbox(16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := Kit.hero_card(str(mvp.hero_id), {"size": 100})
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(card)
		var mv := Kit.vbox(4)
		mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.alignment = BoxContainer.ALIGNMENT_CENTER
		var top := Kit.hbox(10)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(Kit.tag("MVP", Kit.ORANGE, Color.WHITE, 20))
		top.add_child(Kit.label(str(Game.hero_def(str(mvp.hero_id)).get("name", "")), 32, Kit.TEXT, "title"))
		mv.add_child(top)
		mv.add_child(Kit.label("%s damage  ·  %d%% of the team's" % [Kit.format_full(int(mvp.get("damage", 0))), int(mvp.get("share", 0))], 21, Kit.TEXT_DIM, "bold"))
		mv.add_child(Kit.progress_bar(float(mvp.get("share", 0)), 100.0, Kit.ACCENT, 14, "", true))
		row.add_child(mv)
		pv.add_child(row)
	var reward: Dictionary = data.get("reward", {})
	if bool(data.get("first_clear", false)) and not Kit.reward_entries(reward).is_empty():
		pv.add_child(Kit.header_bar("First clear rewards", null, "chest"))
		var list := Kit.reward_list(reward, 96, true, true, true)
		for tile in list.get_children():
			(tile as Control).modulate.a = 0.0
		pv.add_child(list)
		_pop_tiles.call_deferred(list)
	else:
		var c := Kit.body("Replay complete. First-clear rewards were already claimed.", 21, Kit.TEXT_DIM)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(c)
	_col.add_child(panel)

	# First-session guidance: after the early wins, point at leveling up (with a shortcut to
	# the hero), at the Lobby when something waits there, or at the next stage.
	var step := Guide.step()
	if step == "level":
		var lid := Guide.level_target()
		var lname := str(Game.hero_def(lid).get("name", "your heroes")) if lid != "" else "your heroes"
		var tip := _tip("arrow_up", "Level up %s" % lname, "Your rewards pay for it. Stronger heroes clear the next stages.", "level")
		_col.add_child(tip)
		Guide.mark(tip, true, 0)
	var btns := Kit.hbox(14)
	var home := Kit.light_button("Lobby", func() -> void: _emit("home"), "home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(home)
	Guide.mark(home, step in ["claim", "summon", "formation", "quests"], 0)
	if bool(data.get("has_next", false)):
		var nxt := Kit.orange_button(str(data.get("next_text", "Next Stage")), func() -> void: _emit("next"), "sword")
		nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(nxt)
		Guide.mark(nxt, step == "battle", 0)
	else:
		var camp := Kit.primary_button(str(data.get("back_text", "Campaign")), func() -> void: _emit("campaign"), "campaign")
		camp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(camp)
	_col.add_child(btns)
	_animate_in(star_nodes, n_stars)


## data: stage, outcome, team_power, safe_top, safe_bottom.
func show_defeat(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var head := Control.new()
	head.custom_minimum_size = Vector2(660, 140)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := Kit.glow(Kit.EMBER, 420)
	glow.position = Vector2(330 - 210, 70 - 210)
	glow.modulate.a = 0.4
	head.add_child(glow)
	var rib := Kit.ribbon("Defeat", 480, Kit.EMBER, Color.WHITE, 52)
	rib.position = Vector2(90, 70 - 54)
	rib.size = Vector2(480, 108)
	head.add_child(rib)
	_col.add_child(head)
	var st: Dictionary = data.get("stage", {})
	var out: Dictionary = data.get("outcome", {})
	var why := "Time ran out before the echoes fell." if bool(out.get("timeout", false)) else "Your team was overwhelmed."
	var l := Kit.label(why, 26, Color.WHITE, "extrabold", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(l)
	var team := int(data.get("team_power", 0))
	var rec := int(st.get("recommended_power", 0))
	var prow := Kit.hbox(10)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(Kit.icon("power", 30))
	prow.add_child(Kit.label("TEAM %s" % Kit.format_full(team), 24, StageInfo.power_color(team, rec), "cond_bold"))
	prow.add_child(Kit.label("VS", 20, Kit.INK_DIM, "cond_bold"))
	prow.add_child(Kit.label("REC. %s" % Kit.format_full(rec), 24, Color.WHITE, "cond_bold"))
	_col.add_child(prow)

	var pp := _panel("HOW TO WIN")
	var panel: PanelContainer = pp[0]
	var pv: VBoxContainer = pp[1]
	var lvl_tip := _tip("arrow_up", "Level up your heroes", "Spend gold and hero EXP from the Sanctum.", "level")
	pv.add_child(lvl_tip)
	Guide.mark(lvl_tip, Guide.step() == "level", 0)
	pv.add_child(_tip("team", "Change your team", "Sturdy guardians in front, damage dealers behind.", "formation"))
	var foe := StageInfo.main_faction(st)
	var ctr := StageInfo.counter_of(foe)
	if ctr != "":
		pv.add_child(_tip("faction_" + ctr, "Bring %s heroes" % str(Kit.FACTION_NAMES.get(ctr, ctr)),
			"They deal +20%% damage to %s echoes." % str(Kit.FACTION_NAMES.get(foe, foe)), "formation"))
	_col.add_child(panel)

	var btns := Kit.hbox(14)
	var home := Kit.light_button("Lobby", func() -> void: _emit("home"), "home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(home)
	Guide.mark(home, Guide.step() in ["claim", "summon", "formation", "quests"], 0)
	var retry := Kit.primary_button("Retry", func() -> void: _emit("retry"), "refresh")
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(retry)
	_col.add_child(btns)
	_animate_in([], 0)


## A white tappable row: glyph hex, title and a line, chevron.
func _tip(icon_name: String, title_text: String, sub: String, action_name: String) -> Control:
	var card := Kit.panel("row", 12)
	var row := Kit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colored := icon_name.begins_with("faction_")
	var hx := Kit.hex_badge(icon_name, 60, Color("eef1f4") if colored else Kit.ACCENT, Color.WHITE)
	hx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hx)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(title_text, 26, Kit.TEXT, "extrabold"))
	v.add_child(Kit.body(sub, 20, Kit.TEXT_DIM))
	row.add_child(v)
	var chev := Kit.icon("chevron_right", 32, Kit.ACCENT_DEEP)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)
	card.add_child(row)
	card.custom_minimum_size.y = 96
	Kit.make_tappable(card, func() -> void: _emit(action_name))
	return card


func _animate_in(star_nodes: Array[Control], filled: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var i := 0
	for c in _col.get_children():
		if c is Control:
			Kit.pop_in(c as Control, 0.05 + i * 0.06)
		i += 1
	for k in star_nodes.size():
		var s := star_nodes[k]
		if k < filled:
			Kit.pop_in(s, 0.45 + k * 0.22, 0.4)


func _pop_tiles(list: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(list) or not list.is_inside_tree():
		return
	var i := 0
	for tile in list.get_children():
		Kit.pop_in(tile as Control, 0.7 + i * 0.07)
		i += 1
