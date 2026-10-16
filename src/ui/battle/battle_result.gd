extends Control
## Battle result overlay. show_victory(): ribbon, stars by survivors, MVP, first-clear
## rewards, Next Stage / Home. show_defeat(): what to try next (level up, formation,
## counter faction) with shortcuts, Retry / Home. Buttons call on_action(name) with
## "home" | "next" | "retry" | "campaign" | "heroes" | "formation" | "level" (the team hero
## Guide.level_target() names). Early on, Guide highlights the suggested button.

const StageInfo := preload("res://src/ui/battle/stage_info.gd")
const DARK_INK := Color("3d2306")

var on_action: Callable
var _col: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _frame(safe_top: float, safe_bottom: float) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.06, 0.74)
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
	_col = Kit.vbox(16)
	_col.custom_minimum_size.x = 660
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(_col)


func _emit(action_name: String) -> void:
	if on_action.is_valid():
		on_action.call(action_name)


## data: stage, outcome, reward, first_clear, stars (1-3), team_size, mvp {hero_id, damage,
## share}, has_next (bool), next_text, safe_top, safe_bottom.
func show_victory(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var head := Control.new()
	head.custom_minimum_size = Vector2(660, 170)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rays := Kit.rays(Kit.GOLD, 640.0, 18)
	rays.position = Vector2(330 - 320, 85 - 320)
	head.add_child(rays)
	var glow := Kit.glow(Kit.GOLD, 460)
	glow.position = Vector2(330 - 230, 85 - 230)
	glow.modulate.a = 0.6
	head.add_child(glow)
	var rib := Kit.ribbon("Victory!", 560, Kit.GOLD, DARK_INK, 52)
	rib.position = Vector2(50, 85 - 54)
	rib.size = Vector2(560, 108)
	head.add_child(rib)
	_col.add_child(head)

	var stars := Kit.hbox(6)
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n_stars := int(data.get("stars", 3))
	var star_nodes: Array[Control] = []
	for i in 3:
		var st := Kit.icon("star" if i < n_stars else "star_empty", 96 if i == 1 else 80)
		st.size_flags_vertical = Control.SIZE_SHRINK_END if i != 1 else Control.SIZE_SHRINK_BEGIN
		stars.add_child(st)
		star_nodes.append(st)
	_col.add_child(stars)
	var out: Dictionary = data.get("outcome", {})
	var team_size := maxi(1, int(data.get("team_size", 5)))
	var sub := Kit.label("Cleared in %s  ·  %d of %d heroes standing" % [Kit.format_time(int(out.get("duration_ms", 0))), int(out.get("allies_alive", 0)), team_size], 22, Kit.INK_DIM, "bold", 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(sub)

	var panel := Kit.panel("glass", 22)
	var pv := Kit.vbox(14)
	panel.add_child(pv)
	var mvp: Dictionary = data.get("mvp", {})
	if not mvp.is_empty():
		var row := Kit.hbox(16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card := Kit.hero_card(str(mvp.hero_id), {"size": 104})
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(card)
		var mv := Kit.vbox(4)
		mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.alignment = BoxContainer.ALIGNMENT_CENTER
		var top := Kit.hbox(10)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(Kit.tag("MVP", Kit.GOLD, DARK_INK, 20))
		top.add_child(Kit.header(str(Game.hero_def(str(mvp.hero_id)).get("name", "")), 32))
		mv.add_child(top)
		mv.add_child(Kit.label("%s damage  ·  %d%% of the team's" % [Kit.format_full(int(mvp.get("damage", 0))), int(mvp.get("share", 0))], 22, Kit.INK, "bold"))
		mv.add_child(Kit.progress_bar(float(mvp.get("share", 0)), 100.0, Kit.EMBER.lerp(Kit.GOLD, 0.5), 14))
		row.add_child(mv)
		pv.add_child(row)
		pv.add_child(Kit.divider())
	var reward: Dictionary = data.get("reward", {})
	if bool(data.get("first_clear", false)) and not Kit.reward_entries(reward).is_empty():
		pv.add_child(Kit.section_header("First Clear Rewards", 26))
		var list := Kit.reward_list(reward, 96)
		for tile in list.get_children():
			(tile as Control).modulate.a = 0.0
		pv.add_child(list)
		_pop_tiles.call_deferred(list)
	else:
		var c := Kit.body("Replay complete. First-clear rewards were already claimed.", 22, Kit.INK_DIM)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(c)
	_col.add_child(panel)

	# First-session guidance: after the early wins, point at leveling up (with a shortcut to
	# the hero), at Home when something waits there, or at the next stage.
	var step := Guide.step()
	if step == "level":
		var lid := Guide.level_target()
		var lname := str(Game.hero_def(lid).get("name", "your heroes")) if lid != "" else "your heroes"
		var tip := _tip(Kit.icon("arrow_up", 52), "Level up %s" % lname, "Your rewards pay for it. Stronger heroes clear the next stages.", "level")
		_col.add_child(tip)
		Guide.mark(tip, true, 0)
	var btns := Kit.hbox(16)
	var home := Kit.secondary_button("Home", func() -> void: _emit("home"), "home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(home)
	Guide.mark(home, step in ["claim", "summon", "formation", "quests"], 0)
	if bool(data.get("has_next", false)):
		var nxt := Kit.primary_button(str(data.get("next_text", "Next Stage")), func() -> void: _emit("next"), "sword")
		nxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(nxt)
		Guide.mark(nxt, step == "battle", 0)
	else:
		var camp := Kit.primary_button("Campaign", func() -> void: _emit("campaign"), "map")
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
	var glow := Kit.glow(Color("8a2f4a"), 420)
	glow.position = Vector2(330 - 210, 70 - 210)
	glow.modulate.a = 0.55
	head.add_child(glow)
	var rib := Kit.ribbon("Defeat", 480, Color("6b4bb3"), Color.WHITE, 50)
	rib.position = Vector2(90, 70 - 52)
	rib.size = Vector2(480, 104)
	head.add_child(rib)
	_col.add_child(head)
	var st: Dictionary = data.get("stage", {})
	var out: Dictionary = data.get("outcome", {})
	var why := "Time ran out before the echoes fell." if bool(out.get("timeout", false)) else "Your team was overwhelmed."
	var l := Kit.label(why, 26, Kit.INK, "extrabold", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(l)
	var team := int(data.get("team_power", 0))
	var rec := int(st.get("recommended_power", 0))
	var prow := Kit.hbox(10)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_child(Kit.icon("power", 32))
	prow.add_child(Kit.label("Team %s" % Kit.format_full(team), 24, StageInfo.power_color(team, rec), "black", 4))
	prow.add_child(Kit.caption("vs", 22))
	prow.add_child(Kit.label("Recommended %s" % Kit.format_full(rec), 24, Kit.INK, "black", 4))
	_col.add_child(prow)

	var panel := Kit.panel("glass", 20)
	var pv := Kit.vbox(12)
	panel.add_child(pv)
	pv.add_child(Kit.section_header("How to win", 26))
	var lvl_tip := _tip(Kit.icon("arrow_up", 52), "Level up your heroes", "Spend gold and hero EXP from idle rewards.", "level")
	pv.add_child(lvl_tip)
	Guide.mark(lvl_tip, Guide.step() == "level", 0)
	pv.add_child(_tip(Kit.icon("heroes", 52), "Change your formation", "Sturdy guardians in front, damage dealers behind.", "formation"))
	var foe := StageInfo.main_faction(st)
	var ctr := StageInfo.counter_of(foe)
	if ctr != "":
		pv.add_child(_tip(Kit.faction_icon(ctr, 52), "Bring %s heroes" % str(Kit.FACTION_NAMES.get(ctr, ctr)),
			"They deal +20%% damage to %s echoes." % str(Kit.FACTION_NAMES.get(foe, foe)), "formation"))
	_col.add_child(panel)

	var btns := Kit.hbox(16)
	var home := Kit.secondary_button("Home", func() -> void: _emit("home"), "home")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(home)
	var retry := Kit.primary_button("Retry", func() -> void: _emit("retry"), "refresh")
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(retry)
	_col.add_child(btns)
	_animate_in([], 0)


func _tip(ic: Control, title_text: String, sub: String, action_name: String) -> Control:
	var card := Kit.card(14)
	var row := Kit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(title_text, 26, Kit.INK, "extrabold"))
	var s := Kit.body(sub, 21, Kit.INK_DIM)
	v.add_child(s)
	row.add_child(v)
	var chev := Kit.icon("chevron_right", 34, Kit.GOLD_LIGHT)
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
