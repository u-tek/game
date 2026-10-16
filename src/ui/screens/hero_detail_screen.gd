extends Control
## Screen "hero_detail" (params: hero_id, optional browse: [hero ids] for the prev/next arrows).
## The hero stands large over a faction-tinted cathedral backdrop (animated HeroSprite with its
## idle motion; tap them for a reaction). The info sheet scrolls up over the art: name plate,
## power and stats, Level Up (cost shown, hold to repeat, Max), Star Up (shard bar with the
## dust fallback), ultimate and passives (locked ones greyed with their unlock star), four gear
## slots with a picker and Auto-equip, and the bio. Unowned heroes get a preview with a link
## to the Summon portal. Level and star ups are celebrated with a burst, a sound and a
## floating caption.

const HOLD_DELAY := 0.42
const HOLD_START := 0.16
const HOLD_MIN := 0.045
const STAT_ORDER: Array[String] = ["hp", "atk", "def", "spd", "crit"]
const DARK_INK := Color("3d2306")
const SHORT_RED := Color("ff6a50")

var _id := ""
var _def: Dictionary = {}
var _owned := false
var _plate_name: Label
var _plate_sub: Label
var _back_btn: Button
var _browse: Array[String] = []
var _faction_col := Kit.GOLD

var _backdrop: DetailBackdrop
var _stage: Control
var _rays: Control
var _glow: Control
var _anchor: Node2D
var _sprite: Node2D
var _scroll: ScrollContainer
var _top_spacer: Control
var _fx: Control
var _arrows: Array[Control] = []
var _top_bar: Control
var _stage_h := 600.0

var _plate_stars: HBoxContainer
var _team_tag: Control
var _power_label: Label
var _power_value := -1
var _stats_grid: GridContainer
var _stats_caption: Label
var _level_label: Label
var _level_bar: ProgressBar
var _lvl_btn: Button
var _lvl_inner: VBoxContainer
var _max_btn: Button
var _level_note: Label
var _star_row: HBoxContainer
var _shard_bar: ProgressBar
var _star_note: Label
var _star_slot: HBoxContainer
var _passives_box: VBoxContainer
var _gear_row: HBoxContainer
var _auto_btn_slot: HBoxContainer
var _gear_modal: Control

var _passives_sig := -1
var _gear_sig := ""
var _holding := false
var _hold_t := 0.0
var _hold_next := 0.0
var _hold_count := 0
var _hold_gained := 0
var _victory_left := 0.0


func setup(params: Dictionary) -> void:
	_id = str(params.get("hero_id", ""))
	_def = Game.hero_def(_id)
	var b: Variant = params.get("browse", [])
	if b is Array:
		for x: Variant in b:
			_browse.append(str(x))
	if _def.is_empty():
		_build_missing()
		return
	_faction_col = HeroArt.faction_color(str(_def.faction))
	_owned = Game.owns(_id)
	if _browse.is_empty() or not _browse.has(_id):
		_browse.clear()
		for h: Dictionary in Game.owned_heroes():
			_browse.append(str(h.id))
		if not _browse.has(_id):
			_browse = [_id]
	_build()
	resized.connect(_layout)
	Game.changed.connect(_refresh)
	_refresh()
	_layout.call_deferred()
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))
	if str(params.get("show", "")) != "":
		_open_gear_picker.call_deferred(str(params["show"]))


## Screenshot/testing helper (params.scroll): scroll the sheet once laid out.
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	if _gear_modal and is_instance_valid(_gear_modal):
		UI.close_modal(_gear_modal)


func _build_missing() -> void:
	var col := Kit.vbox(24)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_right = -24
	col.offset_top = 14
	add_child(col)
	col.add_child(Kit.screen_header("Hero"))
	col.add_child(Kit.empty_state("This hero could not be found.", "heroes"))


# ------------------------------------------------------------------ build

func _build() -> void:
	_backdrop = DetailBackdrop.new()
	_backdrop.color = _faction_col
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)

	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_stage)
	_rays = Kit.rays(_faction_col, 980.0, 18)
	_rays.modulate.a = 0.16
	_stage.add_child(_rays)
	_glow = Kit.glow(_faction_col, 760)
	_glow.modulate.a = 0.42
	_stage.add_child(_glow)
	var motes := Motes.new()
	motes.color = _faction_col.lightened(0.35)
	motes.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_stage.add_child(motes)
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	_stage.add_child(_anchor)
	_sprite = HeroArt.make_sprite(_id)
	_anchor.add_child(_sprite)
	if not _owned:
		_sprite.modulate = Color(0.55, 0.52, 0.66)

	var sheet := Kit.vbox(18)
	_top_spacer = Control.new()
	_top_spacer.mouse_filter = MOUSE_FILTER_PASS
	_top_spacer.custom_minimum_size.y = 420
	sheet.add_child(_top_spacer)
	Kit.make_tappable(_top_spacer, _poke_hero)
	sheet.add_child(_build_plate())
	var body := Kit.vbox(18)
	sheet.add_child(Kit.margin(body, 20, 0))
	# Owned heroes: Level Up comes first so it is on screen without scrolling.
	if _owned:
		body.add_child(_build_level_panel())
		body.add_child(_build_stats_panel())
		body.add_child(_build_star_panel())
	else:
		body.add_child(_build_stats_panel())
		body.add_child(_build_unowned_panel())
	body.add_child(_build_skills_panel())
	if _owned:
		body.add_child(_build_gear_panel())
	body.add_child(_build_bio_panel())
	body.add_child(Kit.spacer(0, 24))
	_scroll = Kit.scroll(sheet)
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	add_child(_scroll)

	_fx = Control.new()
	_fx.name = "Fx"
	_fx.mouse_filter = MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_fx)

	# Sticky bar: fades in once the name plate scrolls away, so the back button never floats
	# over text.
	_top_bar = Control.new()
	_top_bar.mouse_filter = MOUSE_FILTER_IGNORE
	_top_bar.anchor_right = 1.0
	_top_bar.offset_bottom = 104
	_top_bar.modulate.a = 0.0
	var bar_bg := ColorRect.new()
	bar_bg.mouse_filter = MOUSE_FILTER_IGNORE
	bar_bg.color = Kit.BG
	bar_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_top_bar.add_child(bar_bg)
	var bar_name := Kit.header(str(_def.name), 38)
	bar_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_name.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_top_bar.add_child(bar_name)
	var line := Kit.divider()
	line.anchor_right = 1.0
	line.anchor_top = 1.0
	line.anchor_bottom = 1.0
	line.offset_top = -8
	line.offset_bottom = 4
	_top_bar.add_child(line)
	add_child(_top_bar)
	var back := Kit.icon_button("back", func() -> void: UI.back(), 88, "round")
	back.position = Vector2(12, 8)
	add_child(back)
	_back_btn = back
	if _browse.size() > 1:
		for dir: int in [-1, 1]:
			var d := dir
			var arrow := Kit.icon_button("chevron_right", func() -> void: _browse_step(d), 96, "bare")
			arrow.modulate = Kit.GOLD_LIGHT
			if dir < 0:
				for c in arrow.get_children():
					if c is TextureRect:
						(c as TextureRect).flip_h = true
			add_child(arrow)
			_arrows.append(arrow)


func _build_plate() -> Control:
	var plate := PanelContainer.new()
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", Kit.box(Color(Kit.BG, 0.0), Color(Kit.BG, 0.82), Color.TRANSPARENT, 0.0, 0, 0))
	var v := Kit.vbox(6)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_END
	plate.add_child(v)
	var name_l := Kit.title(str(_def.name), Kit.SIZE_HERO)
	v.add_child(name_l)
	var sub := Kit.label(str(_def.title), 26, Kit.INK, "bold", 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_plate_name = name_l
	_plate_sub = sub
	_plate_stars = Kit.hbox(8)
	_plate_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_plate_stars.mouse_filter = MOUSE_FILTER_IGNORE
	_plate_stars.custom_minimum_size.y = 40
	v.add_child(_plate_stars)
	var badges := Kit.hbox(14)
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	badges.mouse_filter = MOUSE_FILTER_IGNORE
	var rb := Kit.rarity_badge(str(_def.rarity), 22)
	rb.size_flags_vertical = SIZE_SHRINK_CENTER
	badges.add_child(rb)
	var fb := Kit.faction_badge(str(_def.faction), 40)
	badges.add_child(fb)
	var ro := Kit.role_badge(str(_def.role), 34)
	ro.size_flags_vertical = SIZE_SHRINK_CENTER
	badges.add_child(ro)
	v.add_child(badges)
	v.add_child(Kit.spacer(0, 6))
	return plate


func _build_stats_panel() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(12)
	p.add_child(v)
	var top := Kit.hbox(12)
	top.add_child(Kit.icon("power", 52))
	var pv := Kit.vbox(0)
	pv.size_flags_horizontal = SIZE_EXPAND_FILL
	pv.add_child(Kit.caption("Power", 22))
	_power_label = Kit.number(0, 40, Kit.GOLD_LIGHT)
	pv.add_child(_power_label)
	top.add_child(pv)
	_team_tag = Kit.tag("In Team", Kit.GOOD, Color("0d2a1d"), 22)
	_team_tag.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(_team_tag)
	v.add_child(top)
	v.add_child(Kit.divider())
	_stats_caption = Kit.caption("", 22)
	v.add_child(_stats_caption)
	_stats_grid = Kit.grid(2, 10)
	_stats_grid.add_theme_constant_override("h_separation", 28)
	v.add_child(_stats_grid)
	return p


func _build_level_panel() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(14)
	p.add_child(v)
	var head := Kit.hbox(12)
	var h := Kit.header("Level", 32)
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(h)
	_level_label = Kit.label("", 30, Kit.INK, "black", 4)
	head.add_child(_level_label)
	v.add_child(head)
	_level_bar = Kit.progress_bar(1, 1, Kit.SKY, 22, "")
	v.add_child(_level_bar)
	var row := Kit.hbox(14)
	_lvl_btn = Kit.primary_button("", _on_level_tap)
	_lvl_btn.custom_minimum_size = Vector2(0, 108)
	_lvl_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_lvl_btn.button_down.connect(_on_level_down)
	_lvl_btn.button_up.connect(func() -> void: _end_hold())
	_lvl_inner = Kit.vbox(2)
	_lvl_inner.mouse_filter = MOUSE_FILTER_IGNORE
	_lvl_inner.alignment = BoxContainer.ALIGNMENT_CENTER
	_lvl_inner.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_lvl_inner.offset_bottom = -6
	_lvl_btn.add_child(_lvl_inner)
	row.add_child(_lvl_btn)
	_max_btn = Kit.secondary_button("", _on_level_max)
	_max_btn.custom_minimum_size = Vector2(176, 108)
	row.add_child(_max_btn)
	v.add_child(row)
	_level_note = Kit.caption("", 22)
	_level_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_level_note)
	return p


func _build_star_panel() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(14)
	p.add_child(v)
	var head := Kit.hbox(12)
	var h := Kit.header("Stars", 32)
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(h)
	_star_row = Kit.hbox(0)
	_star_row.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(_star_row)
	v.add_child(head)
	var shards := Kit.hbox(10)
	shards.add_child(Kit.icon("shard", 44))
	_shard_bar = Kit.progress_bar(0, 1, Kit.rarity_color(str(_def.rarity)), 30, "")
	shards.add_child(_shard_bar)
	v.add_child(shards)
	_star_note = Kit.body("", 23, Kit.INK_DIM)
	_star_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_star_note)
	_star_slot = Kit.hbox(0)
	v.add_child(_star_slot)
	return p


func _build_unowned_panel() -> Control:
	var p := Kit.panel("glass", 26)
	var v := Kit.vbox(16)
	p.add_child(v)
	var h := Kit.header("Not yet summoned", 34)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var t := Kit.body("%s answers the call of the Summon portal. Each pull has a chance to bring a %s hero." % [
		str(_def.name), str(Kit.RARITY_NAMES.get(str(_def.rarity), "")).to_lower()], 24, Kit.INK_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := Kit.primary_button("Go to Summon", func() -> void: UI.go("summon"), "summon")
	v.add_child(b)
	return p


func _build_skills_panel() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(14)
	p.add_child(v)
	v.add_child(Kit.section_header("Skills", 30))
	var ult: Dictionary = _def.get("ultimate", {})
	v.add_child(_skill_row("power", Kit.GOLD, str(ult.get("name", "")), "Ultimate", str(ult.get("description", "")), true, 0))
	_passives_box = Kit.vbox(12)
	v.add_child(_passives_box)
	return p


func _skill_row(icon_name: String, accent: Color, title_text: String, kind: String, desc: String, unlocked: bool, unlock_stars: int) -> Control:
	var card := Kit.panel("inset", 16)
	var row := Kit.hbox(16)
	card.add_child(row)
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(76, 76)
	disc.size_flags_vertical = SIZE_SHRINK_BEGIN
	disc.mouse_filter = MOUSE_FILTER_IGNORE
	var col := accent if unlocked else Color("5a5470")
	disc.add_theme_stylebox_override("panel", Kit.box(col.darkened(0.25), col.darkened(0.75), col.lightened(0.2), 999.0, 3))
	var ic := Kit.icon(icon_name if unlocked else "lock", 46, Color.WHITE if unlocked else Color(1, 1, 1, 0.8))
	ic.position = Vector2(15, 15)
	ic.size = Vector2(46, 46)
	disc.add_child(ic)
	row.add_child(disc)
	var tv := Kit.vbox(4)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	var head := Kit.hbox(10)
	var n := Kit.label(title_text, 28, Kit.GOLD_LIGHT if unlocked else Kit.INK_DIM, "extrabold")
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(n)
	if unlocked:
		var tg := Kit.tag(kind, accent if kind == "Ultimate" else Kit.GOOD, DARK_INK, 18)
		tg.size_flags_vertical = SIZE_SHRINK_CENTER
		head.add_child(tg)
	else:
		var lock := Kit.hbox(2)
		lock.mouse_filter = MOUSE_FILTER_IGNORE
		lock.add_child(Kit.label("Unlocks at %d" % unlock_stars, 20, Kit.INK_DIM, "black"))
		lock.add_child(Kit.icon("star", 26))
		head.add_child(lock)
	tv.add_child(head)
	var d := Kit.body(desc, 23, Kit.INK if unlocked else Kit.INK_DIM)
	tv.add_child(d)
	row.add_child(tv)
	if not unlocked:
		card.modulate = Color(1, 1, 1, 0.72)
	return card


func _build_gear_panel() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(16)
	p.add_child(v)
	v.add_child(Kit.section_header("Gear", 30))
	_gear_row = Kit.hbox(12)
	_gear_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_gear_row)
	_auto_btn_slot = Kit.hbox(0)
	v.add_child(_auto_btn_slot)
	return p


func _build_bio_panel() -> Control:
	var p := Kit.panel("glass", 24)
	var v := Kit.vbox(12)
	p.add_child(v)
	v.add_child(Kit.section_header("Story", 30))
	var b := Kit.body(str(_def.get("bio", "")), 25, Kit.INK)
	v.add_child(b)
	return p


# ------------------------------------------------------------------ layout & motion

func _layout() -> void:
	if _stage == null or size.y <= 0.0:
		return
	var w := size.x
	var h := size.y
	_stage_h = clampf(h * 0.62, 430.0, 800.0)
	var feet_y := _stage_h + 150.0
	var top_y := 36.0
	var fig_h := feet_y - top_y
	_anchor.position = Vector2(w * 0.5, feet_y)
	if _sprite and is_instance_valid(_sprite):
		_sprite.scale = Vector2.ONE
		var hgt: float = _sprite.call("get_height")
		var k := fig_h / maxf(hgt, 1.0)
		_sprite.scale = Vector2(k, k)
	var mid := Vector2(w * 0.5, top_y + fig_h * 0.34)
	_rays.size = Vector2(980, 980)
	_rays.position = mid - _rays.size * 0.5
	_glow.size = Vector2(760, 760)
	_glow.position = mid - _glow.size * 0.5
	_backdrop.feet_y = feet_y
	_backdrop.queue_redraw()
	# The info sheet starts so the name plate sits over the hero's knees.
	_top_spacer.custom_minimum_size.y = maxf(120.0, _stage_h - 190.0)
	# Browse arrows flank the hero's name.
	var ay := _top_spacer.custom_minimum_size.y + 6.0
	for i in _arrows.size():
		var a := _arrows[i]
		a.position = Vector2(4.0 if i == 0 else w - a.size.x - 4.0, ay)
	_on_scrolled(_scroll.scroll_vertical)


func _on_scrolled(v: float) -> void:
	if _stage == null:
		return
	_stage.position.y = -v * 0.35
	_stage.modulate = Color(1, 1, 1).lerp(Color(0.55, 0.52, 0.65), clampf(v / 600.0, 0.0, 1.0))
	# Large title to small title: the plate's name and title fade out as they reach the top,
	# then the sticky bar fades in (opaque before the stars and badges slide under it).
	var sp := _top_spacer.custom_minimum_size.y
	if _plate_name:
		_plate_name.modulate.a = clampf((sp - 50.0 - v) / 80.0, 0.0, 1.0)
	if _plate_sub:
		_plate_sub.modulate.a = clampf((sp - 10.0 - v) / 80.0, 0.0, 1.0)
	if _top_bar:
		_top_bar.modulate.a = clampf((v - sp + 50.0) / 80.0, 0.0, 1.0)
	var fade := clampf(1.0 - v / 160.0, 0.0, 1.0)
	for a in _arrows:
		a.modulate.a = fade
		a.position.y = _top_spacer.custom_minimum_size.y + 6.0 - v
		a.visible = fade > 0.02


func _process(delta: float) -> void:
	if _victory_left > 0.0:
		_victory_left -= delta
		if _victory_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	if not _holding:
		return
	if _lvl_btn == null or not _lvl_btn.is_pressed():
		_end_hold()
		return
	var down: Variant = _lvl_btn.get_meta("_down_at") if _lvl_btn.has_meta("_down_at") else null
	if down is Vector2 and (down as Vector2).distance_to(_lvl_btn.get_global_mouse_position()) > 36.0:
		_end_hold()
		return
	_hold_t += delta
	if _hold_t >= _hold_next:
		_hold_count += 1
		if _do_level(1, true):
			_hold_gained += 1
			_hold_next = _hold_t + maxf(HOLD_MIN, HOLD_START * pow(0.86, _hold_count))
		else:
			_end_hold()


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _stage == null:
		return
	_owned = Game.owns(_id)
	var h := Game.hero(_id)
	var stars := int(h.get("stars", Kit.RARITY_STARS.get(str(_def.rarity), 1)))
	var level := int(h.get("level", 1))
	var cap := int(Game.max_level(_id))

	for c in _plate_stars.get_children():
		c.queue_free()
	_plate_stars.add_child(Kit.star_row(stars, Kit.MAX_STARS if _owned else 0, 36))

	# Power and stats.
	var p := int(Game.hero_power(_id))
	if _power_value >= 0 and p != _power_value:
		Kit.count_to(_power_label, _power_value, p, 0.5, true)
		Kit.pulse(_power_label, 1.1)
	else:
		_power_label.text = Kit.format_full(p)
	_power_value = p
	_team_tag.visible = Game.formation().has(_id)
	var st := Game.hero_stats(_id)
	var nxt := {}
	if _owned and level < cap:
		nxt = Game.hero_stats_at(_id, level + 1, stars)
	_stats_caption.text = ("Next level adds the green numbers" if not nxt.is_empty() else "Level %d, all gear included" % level) if _owned else "Base stats at level 1"
	for c in _stats_grid.get_children():
		c.queue_free()
	for k: String in STAT_ORDER:
		var val := int(st.get(k, 0))
		var delta: Variant = null
		if not nxt.is_empty():
			var dv := int(nxt.get(k, 0)) - val
			if dv > 0:
				delta = _stat_text(k, dv)
		var row := Kit.stat_row(k, _stat_text(k, val), delta)
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		_stats_grid.add_child(row)

	if _owned:
		_refresh_level(level, cap)
		_refresh_stars(stars)
		_refresh_gear()
	_refresh_passives(stars)
	_refresh_guide()


## First-session guidance when another team hero should be leveled next: point at the browse
## arrow toward that hero, or at Back (the hero list rings them).
func _refresh_guide() -> void:
	var target := Guide.level_target() if Guide.step() == "level" else ""
	var away := target != "" and target != _id and not Guide.should_level(_id)
	var dir := 0
	if away and _browse.has(target) and _browse.has(_id) and _arrows.size() == 2:
		var n := _browse.size()
		var fwd := (_browse.find(target) - _browse.find(_id) + n) % n
		dir = 1 if fwd <= n / 2 else -1
	for i in _arrows.size():
		Guide.mark(_arrows[i], away and dir == (-1 if i == 0 else 1), 0)
	Guide.mark(_back_btn, away and dir == 0, 0)


func _stat_text(stat: String, v: int) -> String:
	if stat == "crit":
		if v % 100 == 0:
			return "%d%%" % (v / 100)
		return "%.1f%%" % (float(v) / 100.0)
	return Kit.format_full(v)


func _refresh_level(level: int, cap: int) -> void:
	_level_label.text = "Lv. %d / %d" % [level, cap]
	Kit.set_progress(_level_bar, level, cap, "", false)
	for c in _lvl_inner.get_children():
		c.queue_free()
	var cost := Game.level_up_cost(_id)
	if cost.is_empty():
		Guide.mark(_lvl_btn, false)
		_lvl_btn.disabled = true
		var t := Kit.label("Level Cap", 32, Kit.INK_DIM, "extrabold")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lvl_inner.add_child(t)
		_max_btn.disabled = true
		_max_btn.text = "Max"
		var stars_now := int(Game.hero(_id).get("stars", 1))
		_level_note.text = "Level cap reached. Star up to raise it to %d." % Progression.level_cap(stars_now + 1) if Game.star_up_cost(_id).size() > 0 else "Fully ascended: this hero is at the highest level."
		return
	_lvl_btn.disabled = false
	# First-session guidance: level up team heroes (see _refresh_guide for the others).
	Guide.mark(_lvl_btn, Guide.should_level(_id))
	var t2 := Kit.label("Level Up", 32, DARK_INK, "extrabold")
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_inner.add_child(t2)
	_lvl_inner.add_child(Kit.cost_row(cost, 23, DARK_INK, true, Color("a3200e")))
	var n := int(Game.affordable_levels(_id))
	_max_btn.disabled = n < 2
	_max_btn.text = "Max +%d" % n if n >= 2 else "Max"
	if Kit.can_afford(cost):
		_level_note.text = "Hold Level Up to level quickly."
	else:
		var short := "gold" if Kit.have("gold") < int(cost.get("gold", 0)) else "hero EXP"
		_level_note.text = "Not enough %s. Idle rewards and stages give more." % short


func _refresh_stars(stars: int) -> void:
	for c in _star_row.get_children():
		c.queue_free()
	_star_row.add_child(Kit.star_row(stars, Kit.MAX_STARS, 34))
	for c in _star_slot.get_children():
		c.queue_free()
	var c := Game.star_up_cost(_id)
	if c.is_empty():
		Kit.set_progress(_shard_bar, 1, 1, "Max stars", false)
		_star_note.text = "%s has reached the peak of ascension." % str(_def.name)
		var done := Kit.secondary_button("Max Stars")
		done.disabled = true
		done.size_flags_horizontal = SIZE_EXPAND_FILL
		_star_slot.add_child(done)
		return
	var need := int(c.shards)
	var have := int(c.shards_have)
	Kit.set_progress(_shard_bar, mini(have, need), need, "Shards %d / %d" % [have, need], false)
	var dust := int(c.dust)
	var gain := "Next star: level cap %d, stronger stats" % Progression.level_cap(stars + 1)
	for pas: Dictionary in _def.get("passives", []):
		if int(pas.unlock_stars) == stars + 1:
			gain += ", unlocks %s" % str(pas.name)
	if dust > 0:
		var missing := need - mini(have, need)
		_star_note.text = "%s.\nMissing %d shards: dust fills in at %d each." % [gain, missing, int(c.dust_per_shard)]
		var b := Kit.costs_button("Star Up", {"dust": dust}, _on_star_up)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		_star_slot.add_child(b)
	else:
		_star_note.text = gain + "."
		var b2 := Kit.primary_button("Star Up", _on_star_up, "star")
		b2.custom_minimum_size.y = 100
		b2.size_flags_horizontal = SIZE_EXPAND_FILL
		_star_slot.add_child(b2)
		Kit.set_dot(b2, true, 24, Vector2(10, 10))


func _refresh_passives(stars: int) -> void:
	if _passives_sig == stars:
		return
	_passives_sig = stars
	for c in _passives_box.get_children():
		c.queue_free()
	for pas: Dictionary in _def.get("passives", []):
		var unlocked := stars >= int(pas.unlock_stars)
		_passives_box.add_child(_skill_row("star", Kit.GOOD, str(pas.name), "Passive", str(pas.description), unlocked, int(pas.unlock_stars)))


func _refresh_gear() -> void:
	var h := Game.hero(_id)
	var hg: Dictionary = h.get("gear", {})
	var sig := JSON.stringify(hg) + "|" + JSON.stringify(Game.gear_items())
	if sig == _gear_sig:
		return
	_gear_sig = sig
	for c in _gear_row.get_children():
		c.queue_free()
	var any_better := false
	for slot: String in ["weapon", "armor", "helm", "charm"]:
		var uid := str(hg.get(slot, ""))
		var better := _better_loose(slot, uid)
		any_better = any_better or better
		_gear_row.add_child(_gear_tile(slot, uid, better))
	for c in _auto_btn_slot.get_children():
		c.queue_free()
	var b: Button
	if any_better:
		b = Kit.primary_button("Auto-equip", _on_auto_equip, "auto")
		Kit.set_dot(b, true, 24, Vector2(10, 10))
	else:
		b = Kit.secondary_button("Auto-equip", _on_auto_equip, "auto")
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	_auto_btn_slot.add_child(b)


## True when an unworn item of this slot beats what the hero wears.
func _better_loose(slot: String, worn_uid: String) -> bool:
	var cur := Game.gear_score(worn_uid) if worn_uid != "" else -1
	for it: Dictionary in Game.gear_items():
		if str(it.slot) == slot and str(it.get("equipped_by", "")) == "" and Game.gear_score(str(it.uid)) > cur:
			return true
	return false


func _gear_tile(slot: String, uid: String, better: bool) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(150, 196)
	box.mouse_filter = MOUSE_FILTER_PASS
	if uid == "":
		var e := Kit.empty_slot(140, str(Kit.GEAR_SLOT_NAMES.get(slot, slot)), func() -> void: _open_gear_picker(slot))
		e.position = Vector2(5, 0)
		box.add_child(e)
		var cap := Kit.caption("Empty", 20)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = Vector2(0, 146)
		cap.size = Vector2(150, 30)
		box.add_child(cap)
		if better:
			Kit.set_dot(e, true, 24, Vector2(-6, -6))
		return box
	var item := Game.gear_item(uid)
	var tile := Kit.reward_tile("gear", uid, 1, 140, true)
	tile.position = Vector2(5, 0)
	box.add_child(tile)
	var stat := Kit.label(_gear_stat_text(item, true), 19, Kit.GOOD, "black", 0)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.clip_text = true
	stat.position = Vector2(-4, 168)
	stat.size = Vector2(158, 26)
	box.add_child(stat)
	var hit := Control.new()
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.position = Vector2(5, 0)
	hit.size = Vector2(140, 140)
	box.add_child(hit)
	Kit.make_tappable(hit, func() -> void: _open_gear_picker(slot))
	if better:
		Kit.set_dot(hit, true, 24, Vector2(-6, -6))
	return box


## "+56 ATK", or every stat in long form ("+56 Attack  +3% Crit").
func _gear_stat_text(item: Dictionary, short: bool) -> String:
	var parts: Array[String] = []
	var st: Dictionary = item.get("stats", {})
	var abbrev := {"hp": "HP", "atk": "ATK", "def": "DEF", "spd": "SPD", "crit": "CRIT"}
	for k: String in ["atk", "hp", "def", "spd", "crit"]:
		if not st.has(k):
			continue
		var v := int(st[k])
		var name_s: String = str(abbrev[k]) if short else str(Kit.STAT_NAMES.get(k, k))
		parts.append("+%s %s" % [_stat_text(k, v), name_s])
		if short:
			break
	return "  ".join(parts)


# ------------------------------------------------------------------ actions

func _browse_step(dir: int) -> void:
	var i := _browse.find(_id)
	if i < 0 or _browse.size() < 2:
		return
	var n := _browse[(i + dir + _browse.size()) % _browse.size()]
	UI.go("hero_detail", {"hero_id": n, "browse": Array(_browse)})


func _poke_hero() -> void:
	if _sprite == null or not is_instance_valid(_sprite) or _victory_left > 0.0:
		return
	if _sprite.call("is_busy"):
		return
	_sprite.call("play", "hop" if randi() % 2 == 0 else "cast")


func _on_level_down() -> void:
	_holding = not _lvl_btn.disabled
	_hold_t = 0.0
	_hold_next = HOLD_DELAY
	_hold_count = 0
	_hold_gained = 0


func _end_hold() -> void:
	if not _holding:
		return
	_holding = false
	if _hold_gained > 0:
		UI.sfx("reward")
		_celebrate_level(_hold_gained)


func _on_level_tap() -> void:
	if _hold_count > 0:
		return # the hold already did the work
	if _do_level(1, false):
		UI.sfx("reward")
		_celebrate_level(1)


func _on_level_max() -> void:
	var n := int(Game.affordable_levels(_id))
	if n <= 0:
		UI.toast("Not enough gold or hero EXP", "bad")
		return
	var r := Game.level_up_many(_id, n)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Can't level up")), "bad")
		return
	UI.sfx("reward")
	UI.haptic(20)
	_celebrate_level(int(r.value.get("levels_gained", n)))


## One level-up attempt. quiet = part of a hold (no toast on failure, just stop).
func _do_level(n: int, quiet: bool) -> bool:
	var r := Game.level_up_many(_id, n)
	if bool(r.get("ok", false)):
		if quiet:
			UI.sfx("tap")
			_burst(0.55)
		return true
	if not quiet or _hold_gained == 0:
		UI.toast(str(r.get("error", "Can't level up")), "bad")
		Kit.shake(_lvl_btn, 8)
	return false


func _on_star_up() -> void:
	var c := Game.star_up_cost(_id)
	if c.is_empty():
		return
	if not Game.can_star_up(_id):
		UI.toast("Not enough shards or dust", "bad")
		Kit.shake(_star_slot, 8)
		return
	var run := func() -> void:
		var before := int(Game.hero(_id).get("stars", 1))
		var r := Game.star_up(_id)
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "Can't star up")), "bad")
			return
		_celebrate_star(before + 1)
	if int(c.dust) > 0:
		UI.confirm("Use %s dust to cover %d missing shards and raise %s to %d stars?" % [
			Kit.format_full(int(c.dust)), int(c.shards) - int(c.shards_used), str(_def.name), int(Game.hero(_id).get("stars", 1)) + 1],
			run, Callable(), "Star Up")
	else:
		run.call()


func _on_auto_equip() -> void:
	var before := JSON.stringify(Game.hero(_id).get("gear", {}))
	Game.auto_equip(_id)
	if JSON.stringify(Game.hero(_id).get("gear", {})) == before:
		UI.toast("Already wearing the best gear available")
	else:
		UI.sfx("reward")
		UI.toast("Equipped the best gear", "good")
		_burst(0.7)


func _open_gear_picker(slot: String) -> void:
	var items: Array[Dictionary] = []
	for it: Dictionary in Game.gear_items():
		if str(it.slot) == slot:
			items.append(it)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := Game.gear_score(str(a.uid))
		var sb := Game.gear_score(str(b.uid))
		return sa > sb if sa != sb else str(a.uid) < str(b.uid))
	var worn := str(Game.hero(_id).get("gear", {}).get(slot, ""))
	var list := Kit.vbox(12)
	if worn != "":
		list.add_child(_gear_pick_row(Game.gear_item(worn), true))
	var others := 0
	for it in items:
		if str(it.uid) == worn:
			continue
		others += 1
		list.add_child(_gear_pick_row(it, false))
	if others == 0:
		var es := Kit.empty_state("No other %s yet. Gear drops from idle rewards and campaign stages." % str(Kit.GEAR_SLOT_NAMES.get(slot, slot)).to_lower(), "gear_" + slot)
		es.custom_minimum_size.y = 220
		list.add_child(es)
	var content: Control = list
	var rows := others + (1 if worn != "" else 0)
	if rows > 4:
		var sc := Kit.scroll(list)
		sc.custom_minimum_size = Vector2(580, minf(rows * 140.0, size.y * 0.62))
		content = sc
	_gear_modal = UI.popup(str(Kit.GEAR_SLOT_NAMES.get(slot, slot)), content, Callable(), 640.0)


func _gear_pick_row(it: Dictionary, worn_here: bool) -> Control:
	var card := Kit.card(14)
	var row := Kit.hbox(14)
	card.add_child(row)
	row.add_child(Kit.reward_tile("gear", str(it.uid), 1, 100, false))
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := Kit.label(str(it.get("name", "Gear")), 26, Kit.tier_color(int(it.get("tier", 1))).lightened(0.25), "extrabold")
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(n)
	var s := Kit.label(_gear_stat_text(it, false), 21, Kit.GOOD, "black")
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(s)
	var owner := str(it.get("equipped_by", ""))
	if worn_here:
		info.add_child(Kit.caption("Worn now", 20, Kit.GOLD_LIGHT))
	elif owner != "":
		info.add_child(Kit.caption("Worn by %s" % str(Game.hero_def(owner).get("name", owner)), 20))
	row.add_child(info)
	var uid := str(it.uid)
	var slot := str(it.slot)
	var b: Button
	if worn_here:
		b = Kit.secondary_button("Remove", func() -> void:
			Game.unequip(_id, slot)
			_close_gear_modal())
	else:
		b = Kit.primary_button("Swap" if owner != "" else "Equip", func() -> void:
			var r := Game.equip(_id, uid)
			_close_gear_modal()
			if bool(r.get("ok", false)):
				UI.sfx("reward")
				_burst(0.6)
				if owner != "" and owner != _id:
					UI.toast("Taken from %s" % str(Game.hero_def(owner).get("name", owner)))
			else:
				UI.toast(str(r.get("error", "Can't equip")), "bad"))
	b.custom_minimum_size = Vector2(150, 88)
	b.add_theme_font_size_override("font_size", 28)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(b)
	return card


func _close_gear_modal() -> void:
	if _gear_modal and is_instance_valid(_gear_modal):
		UI.close_modal(_gear_modal)
	_gear_modal = null


# ------------------------------------------------------------------ celebration

func _hero_point() -> Vector2:
	if _sprite and is_instance_valid(_sprite):
		var gp: Vector2 = _sprite.call("get_point", "chest")
		var local := gp - _fx.global_position
		if local.y > 40.0 and local.y < size.y - 40.0:
			return local
	return Vector2(size.x * 0.5, minf(_stage_h * 0.5, size.y * 0.4))


func _burst(strength: float = 1.0, color: Color = Color(0, 0, 0, 0)) -> void:
	var b := Burst.new()
	b.color = color if color.a > 0.0 else _faction_col.lightened(0.2)
	b.strength = strength
	b.position = _hero_point()
	_fx.add_child(b)


func _float_text(text: String, color: Color, size_px: int = 52) -> void:
	var l := Kit.title(text, size_px, color)
	l.size = Vector2(600, size_px * 1.6)
	var p := _hero_point()
	l.position = Vector2(size.x * 0.5 - 300.0, p.y - 120.0)
	l.pivot_offset = l.size * 0.5
	_fx.add_child(l)
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.95)
	tw.chain().tween_callback(l.queue_free)


func _celebrate_level(gained: int) -> void:
	var lv := int(Game.hero(_id).get("level", 1))
	_burst(1.0)
	_float_text("Level %d" % lv if gained <= 1 else "Level %d  (+%d)" % [lv, gained], Kit.GOLD_LIGHT, 50)
	Kit.pulse(_level_label, 1.18)
	UI.haptic(15)


func _celebrate_star(stars: int) -> void:
	UI.sfx("victory")
	UI.haptic(40)
	_burst(1.4, Kit.GOLD)
	_burst(0.9, Color.WHITE)
	_float_text("%d Stars!" % stars, Kit.GOLD_LIGHT, 60)
	if _sprite and is_instance_valid(_sprite):
		_sprite.call("play_victory")
		_victory_left = 2.4
	for pas: Dictionary in _def.get("passives", []):
		if int(pas.unlock_stars) == stars:
			UI.toast("New passive unlocked: %s" % str(pas.name), "good")


# ------------------------------------------------------------------ drawing helpers

## Faction-tinted cathedral backdrop: sky gradient, a gothic window arch behind the hero,
## light shafts and a glowing floor ring at the hero's feet. Drawn once per resize.
class DetailBackdrop extends Control:
	var color := Color("f2c14e")
	var feet_y := 800.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var bg := Color("120e24")
		var top := bg.lerp(color, 0.3).darkened(0.25)
		var mid := bg.lerp(color, 0.12)
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(0, h * 0.55)])
		draw_polygon(pts, PackedColorArray([top, top, mid, mid]))
		var pts2 := PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)])
		draw_polygon(pts2, PackedColorArray([mid, mid, bg, bg]))
		# Gothic window: pointed arch with tracery, faint gold.
		var cx := w * 0.5
		var aw := w * 0.36
		var base_y := feet_y - 40.0
		var spring_y := feet_y * 0.38
		var line := Color(1.0, 0.88, 0.55, 0.16)
		var fill := Color(color, 0.07)
		var arch := _arch(cx, aw, spring_y, base_y)
		draw_colored_polygon(arch, fill)
		arch.append(arch[0])
		draw_polyline(arch, line, 3.0, true)
		var inner := _arch(cx, aw * 0.86, spring_y + aw * 0.1, base_y)
		inner.append(inner[0])
		draw_polyline(inner, Color(line, 0.1), 2.0, true)
		draw_line(Vector2(cx, spring_y - aw * 0.55), Vector2(cx, base_y), Color(line, 0.08), 2.0)
		draw_arc(Vector2(cx, spring_y + aw * 0.05), aw * 0.38, 0, TAU, 48, Color(line, 0.1), 2.0, true)
		# Light shafts from above.
		for i in 3:
			var x0 := cx + (i - 1) * w * 0.16
			var shaft := PackedVector2Array([Vector2(x0 - 24, 0), Vector2(x0 + 24, 0), Vector2(x0 + 150 + i * 30, feet_y), Vector2(x0 - 150 - i * 30, feet_y)])
			draw_colored_polygon(shaft, Color(color.lightened(0.4), 0.035))
		# Floor ring at the feet.
		for r in 4:
			var rx := w * (0.2 + r * 0.09)
			var ry := rx * 0.18
			_ellipse(Vector2(cx, feet_y), rx, ry, Color(color, 0.22 - r * 0.045), 2.5 - r * 0.4)
		_ellipse_fill(Vector2(cx, feet_y), w * 0.3, w * 0.05, Color(color, 0.12))

	func _arch(cx: float, half_w: float, spring_y: float, base_y: float) -> PackedVector2Array:
		var p := PackedVector2Array()
		p.append(Vector2(cx - half_w, base_y))
		var r := half_w * 1.6
		var steps := 24
		# Left arc: centre right of the window, from the springing line up to the apex.
		var lc := Vector2(cx - half_w + r, spring_y)
		var apex_ang := acos((r - half_w) / r)
		for i in steps + 1:
			var a := PI + (apex_ang * float(i) / steps)
			p.append(lc + Vector2(cos(a), sin(a)) * r)
		var rc := Vector2(cx + half_w - r, spring_y)
		for i in steps + 1:
			var a := (TAU - apex_ang) + (apex_ang * float(i) / steps)
			p.append(rc + Vector2(cos(a), sin(a)) * r)
		p.append(Vector2(cx + half_w, base_y))
		return p

	func _ellipse(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, maxf(width, 1.0), true)

	func _ellipse_fill(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)


## Slow drifting light motes in the faction color.
class Motes extends Control:
	var color := Color.WHITE
	var _m: Array[Vector4] = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in 26:
			_m.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(1.5, 4.0), rng.randf() * TAU))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y * 0.8
		for m in _m:
			var y := fposmod(m.y - _t * 0.018 * (m.z / 3.0), 1.0) * h
			var x := m.x * w + sin(_t * 0.6 + m.w) * 14.0
			var a := 0.25 + 0.35 * (0.5 + 0.5 * sin(_t * 1.3 + m.w))
			draw_circle(Vector2(x, y), m.z, Color(color, a))


## One-shot celebration: an expanding ring and sparks flying out (frees itself).
class Burst extends Control:
	var color := Color.WHITE
	var strength := 1.0
	var _t := 0.0
	var _dur := 0.9
	var _sparks: Array[Vector3] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count := int(10 + 14 * strength)
		for i in count:
			_sparks.append(Vector3(randf() * TAU, randf_range(140.0, 380.0) * strength, randf_range(3.0, 8.0)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
		if _t >= _dur:
			queue_free()

	func _draw() -> void:
		var k := clampf(_t / _dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_circle(Vector2.ZERO, 90.0 * strength * (1.0 - k), Color(color.lightened(0.5), 0.35 * (1.0 - k)))
		draw_arc(Vector2.ZERO, 30.0 + 230.0 * strength * e, 0, TAU, 64, Color(color, 0.85 * (1.0 - k)), 2.0 + 7.0 * (1.0 - k), true)
		for s in _sparks:
			var dir := Vector2.from_angle(s.x)
			var p := dir * s.y * e
			var tail := dir * s.y * maxf(0.0, e - 0.12)
			draw_line(tail, p, Color(color.lightened(0.3), 1.0 - k), s.z * (1.0 - k * 0.6), true)
			draw_circle(p, s.z * 0.6 * (1.0 - k * 0.5), Color(1, 1, 1, 1.0 - k))
