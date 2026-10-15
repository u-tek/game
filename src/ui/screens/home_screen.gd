extends Control
## Screen "home": the hub. The team leader idles on a glowing dais over the home scene, the
## idle chest fills while the player is away (claim / quick claim), and a big Battle button
## leads to the next campaign stage. Shortcuts: Campaign, Formation. Refreshes on
## Game.changed and once a second (idle timer).

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const Dais := preload("res://src/ui/battle/dais.gd")

const SHORT_RED := Color("ff6a50")
const DARK_INK := Color("3d2306")

var _backdrop: Control
var _stage: Control
var _dais: Control
var _rays: Control
var _back_glow: Control
var _anchor: Node2D
var _sprite: Node2D
var _leader_id := ""
var _name_plate: VBoxContainer
var _leader_name: Label
var _leader_title: Label
var _leader_stars: HBoxContainer

var _chapter_title: Label
var _chapter_caption: Label
var _chapter_bar: ProgressBar

var _chest_box: Control
var _chest_glow: Control
var _chest_icon: Control
var _chest_tag: Control
var _idle_bar: ProgressBar
var _rate_label: Label
var _pending_row: HBoxContainer
var _quick_slot: HBoxContainer
var _claim_btn: Button
var _quick_sig := ""
var _pending_sig := ""
var _full := false

var _power_row: HBoxContainer
var _battle_btn: Button
var _battle_title: Label
var _battle_sub: Label
var _battle_ready := false

var _t := 0.0
var _tick := 0.0
var _cheer_left := 0.0


func setup(_params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


# ------------------------------------------------------------------ build

func _build() -> void:
	_backdrop = SceneBackdrop.new()
	_backdrop.kind = "home"
	_backdrop.horizon = 0.52
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)

	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 14
	col.offset_bottom = -14
	add_child(col)

	col.add_child(_build_chapter_card())

	_stage = Control.new()
	_stage.name = "Stage"
	_stage.size_flags_vertical = SIZE_EXPAND_FILL
	_stage.custom_minimum_size.y = 300
	_stage.mouse_filter = MOUSE_FILTER_PASS
	_stage.resized.connect(_place_leader)
	col.add_child(_stage)
	_build_stage()

	col.add_child(_build_idle_panel())
	col.add_child(_build_battle_cta())


func _build_chapter_card() -> Control:
	var card := Kit.card(0)
	card.custom_minimum_size.y = 96
	var m := Kit.margin(null, 20, 10)
	card.add_child(m)
	var row := Kit.hbox(14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	m.add_child(row)
	var ic := Kit.icon("map", 56)
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var info := Kit.vbox(2)
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_chapter_caption = Kit.caption("", 21)
	_chapter_title = Kit.header("", 32)
	_chapter_title.clip_text = true
	_chapter_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_chapter_caption)
	info.add_child(_chapter_title)
	row.add_child(info)
	var right := Kit.vbox(6)
	right.mouse_filter = MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 170
	_chapter_bar = Kit.progress_bar(0, 10, Kit.GOLD, 26, "")
	right.add_child(_chapter_bar)
	var go := Kit.hbox(4)
	go.mouse_filter = MOUSE_FILTER_IGNORE
	go.alignment = BoxContainer.ALIGNMENT_END
	go.add_child(Kit.caption("Campaign", 21, Kit.GOLD_LIGHT))
	go.add_child(Kit.icon("chevron_right", 24, Kit.GOLD_LIGHT))
	right.add_child(go)
	row.add_child(right)
	Kit.make_tappable(card, func() -> void: UI.go("campaign"))
	return card


func _build_stage() -> void:
	# Backlight: slow rays and a soft glow behind the leader.
	_rays = Kit.rays(Kit.GOLD, 620.0, 16)
	_rays.modulate.a = 0.22
	_stage.add_child(_rays)
	_back_glow = Kit.glow(Kit.GOLD, 520)
	_back_glow.modulate.a = 0.3
	_stage.add_child(_back_glow)
	_dais = Dais.new()
	_dais.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(_dais)

	_anchor = Node2D.new()
	_anchor.name = "LeaderAnchor"
	_stage.add_child(_anchor)

	# Tap the leader to open their page.
	var hit := Button.new()
	hit.name = "LeaderHit"
	hit.theme_type_variation = &"BareButton"
	hit.focus_mode = FOCUS_NONE
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.anchor_left = 0.27
	hit.anchor_right = 0.73
	hit.anchor_top = 0.05
	hit.anchor_bottom = 1.0
	hit.pressed.connect(func() -> void:
		if _leader_id != "":
			UI.sfx("tap")
			UI.go("hero_detail", {"hero_id": _leader_id}))
	_stage.add_child(hit)

	_name_plate = Kit.vbox(0)
	_name_plate.mouse_filter = MOUSE_FILTER_IGNORE
	_name_plate.alignment = BoxContainer.ALIGNMENT_END
	_name_plate.anchor_left = 0.0
	_name_plate.anchor_right = 1.0
	_name_plate.anchor_top = 1.0
	_name_plate.anchor_bottom = 1.0
	_name_plate.offset_top = -86
	_name_plate.offset_bottom = -4
	_leader_name = Kit.title("", 44)
	_leader_stars = Kit.hbox(10)
	_leader_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	_leader_stars.mouse_filter = MOUSE_FILTER_IGNORE
	_leader_title = Kit.label("", 22, Kit.INK, "bold", 5)
	_name_plate.add_child(_leader_name)
	_name_plate.add_child(_leader_stars)
	_stage.add_child(_name_plate)

	_stage.add_child(_side_button("map", "Campaign", Vector2(0, 0), func() -> void: UI.go("campaign")))
	_stage.add_child(_side_button("heroes", "Formation", Vector2(1, 0), func() -> void: UI.go("formation")))


## Round shortcut button with a caption, pinned to a top corner of the stage area.
func _side_button(icon_name: String, text: String, corner: Vector2, cb: Callable) -> Control:
	var box := Kit.vbox(2)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(120, 0)
	var b := Kit.icon_button(icon_name, cb, 96, "round")
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	box.add_child(b)
	var l := Kit.label(text, 22, Kit.GOLD_LIGHT, "extrabold", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.anchor_left = corner.x
	box.anchor_right = corner.x
	box.anchor_top = corner.y
	box.anchor_bottom = corner.y
	box.grow_horizontal = GROW_DIRECTION_BEGIN if corner.x > 0.5 else GROW_DIRECTION_END
	box.offset_left = -120.0 if corner.x > 0.5 else 0.0
	box.offset_right = 0.0 if corner.x > 0.5 else 120.0
	box.offset_top = 8
	return box


func _build_idle_panel() -> Control:
	var panel := Kit.panel("glass", 18)
	var v := Kit.vbox(12)
	panel.add_child(v)
	var top := Kit.hbox(16)
	v.add_child(top)

	_chest_box = Control.new()
	_chest_box.custom_minimum_size = Vector2(128, 128)
	_chest_box.mouse_filter = MOUSE_FILTER_PASS
	_chest_glow = Kit.glow(Kit.GOLD, 190)
	_chest_glow.position = Vector2(64 - 95, 64 - 95)
	_chest_glow.size = Vector2(190, 190)
	_chest_glow.modulate.a = 0.35
	_chest_box.add_child(_chest_glow)
	_chest_icon = Kit.icon("chest", 116)
	_chest_icon.position = Vector2(6, 8)
	_chest_icon.size = Vector2(116, 116)
	_chest_icon.pivot_offset = Vector2(58, 100)
	_chest_box.add_child(_chest_icon)
	_chest_tag = Kit.tag("FULL", Kit.EMBER, Color.WHITE, 20)
	_chest_tag.position = Vector2(30, -6)
	_chest_tag.visible = false
	_chest_box.add_child(_chest_tag)
	Kit.make_tappable(_chest_box, _claim)
	top.add_child(_chest_box)

	var info := Kit.vbox(8)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := Kit.hbox(8)
	var h := Kit.header("Idle Rewards", 32)
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(h)
	head.add_child(Kit.currency_icon("gold", 30))
	_rate_label = Kit.label("", 22, Kit.GOLD_LIGHT, "black", 4)
	head.add_child(_rate_label)
	info.add_child(head)
	_idle_bar = Kit.progress_bar(0, 1, Kit.GOLD, 32, "")
	info.add_child(_idle_bar)
	_pending_row = Kit.hbox(14)
	_pending_row.custom_minimum_size.y = 40
	info.add_child(_pending_row)
	top.add_child(info)

	var buttons := Kit.hbox(14)
	_quick_slot = Kit.hbox(0)
	_quick_slot.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(_quick_slot)
	_claim_btn = Kit.primary_button("Claim", _claim, "chest")
	_claim_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_claim_btn.custom_minimum_size.y = 96
	buttons.add_child(_claim_btn)
	v.add_child(buttons)
	return panel


func _build_battle_cta() -> Control:
	var v := Kit.vbox(8)
	_power_row = Kit.hbox(10)
	_power_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_power_row.custom_minimum_size.y = 40
	v.add_child(_power_row)
	_battle_btn = Kit.primary_button("", _on_battle)
	_battle_btn.custom_minimum_size.y = 124
	var row := Kit.hbox(18)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_bottom = -8
	var ic := Kit.icon("sword", 64)
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := Kit.vbox(0)
	tv.mouse_filter = MOUSE_FILTER_IGNORE
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	_battle_title = Kit.label("Battle", 42, DARK_INK, "title")
	_battle_sub = Kit.label("", 24, Color("5a3a0e"), "extrabold")
	tv.add_child(_battle_title)
	tv.add_child(_battle_sub)
	row.add_child(tv)
	_battle_btn.add_child(row)
	v.add_child(_battle_btn)
	return v


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_chapter()
	_refresh_leader()
	_refresh_idle()
	_refresh_battle()


func _refresh_chapter() -> void:
	var cleared := Game.cleared_count()
	var total := Game.stages().size()
	var chs := Game.chapters()
	var ci := mini(cleared / 10, chs.size() - 1)
	if chs.is_empty():
		return
	var ch: Dictionary = chs[ci]
	var in_ch := clampi(cleared - int(ch.get("first_stage", ci * 10)), 0, int(ch.get("stage_count", 10)))
	_chapter_caption.text = "Chapter %d of %d" % [ci + 1, chs.size()] if cleared < total else "Campaign complete"
	_chapter_title.text = str(ch.get("name", ""))
	Kit.set_progress(_chapter_bar, in_ch, int(ch.get("stage_count", 10)), "%d / %d" % [in_ch, int(ch.get("stage_count", 10))], false)


func _pick_leader() -> String:
	var best := ""
	var best_score := -1
	for id: String in Game.formation():
		if id == "":
			continue
		var score: int = int(Game.hero_power(id)) + (100000000 if HeroArt.has_art(id) else 0)
		if score > best_score:
			best_score = score
			best = id
	if best == "":
		var owned := Game.owned_heroes()
		if not owned.is_empty():
			best = str(owned[0].id)
	return best


func _refresh_leader() -> void:
	var id := _pick_leader()
	if id != _leader_id:
		_leader_id = id
		if _sprite and is_instance_valid(_sprite):
			_sprite.queue_free()
		_sprite = null
		if id != "":
			_sprite = HeroArt.make_sprite(id)
			_anchor.add_child(_sprite)
			_dais.set("color", HeroArt.faction_color(str(Game.hero_def(id).get("faction", "celestial"))))
			_place_leader()
	if id == "":
		_name_plate.visible = false
		return
	_name_plate.visible = true
	var d := Game.hero_def(id)
	var h := Game.hero(id)
	_leader_name.text = str(d.get("name", id))
	_leader_title.text = "%s  ·  Lv.%d" % [str(d.get("title", "")), int(h.get("level", 1))]
	for c in _leader_stars.get_children():
		if c != _leader_title:
			c.queue_free()
	if _leader_title.get_parent() == null:
		_leader_stars.add_child(_leader_title)
	_leader_stars.add_child(Kit.star_row(int(h.get("stars", 1)), 0, 24))
	var fc := HeroArt.faction_color(str(d.get("faction", "celestial")))
	_rays.set("color", fc)
	_rays.queue_redraw()
	_back_glow.modulate = Color(fc, 0.3)


func _place_leader() -> void:
	if _stage == null or _anchor == null or _dais == null:
		return
	var sz := _stage.size
	var feet := Vector2(sz.x * 0.5, sz.y - 84.0)
	_anchor.position = feet
	var want := clampf(sz.y - 100.0, 220.0, 560.0)
	var mid := Vector2(feet.x, feet.y - want * 0.62)
	_rays.position = mid - _rays.size * 0.5
	_back_glow.position = mid - _back_glow.size * 0.5
	_dais.size = Vector2(sz.x * 0.86, 120)
	_dais.position = Vector2(feet.x - _dais.size.x * 0.5, feet.y - 60)
	if _sprite and is_instance_valid(_sprite):
		_sprite.scale = Vector2.ONE
		var hgt: float = _sprite.call("get_height")
		var k := want / maxf(hgt, 1.0)
		_sprite.scale = Vector2(k, k)


func _refresh_idle() -> void:
	var st: Dictionary = Game.idle_status()
	var elapsed := int(st.get("elapsed_ms", 0))
	var cap := int(st.get("cap_ms", 1))
	_full = bool(st.get("full", false))
	var txt := "%s / %s" % [Kit.format_time(elapsed), Kit.format_time(cap)]
	if _full:
		txt = "Full! %s" % Kit.format_time(cap)
	Kit.set_progress(_idle_bar, elapsed, cap, txt, false)
	_chest_tag.visible = _full
	var per_hour: Dictionary = st.get("per_hour", {})
	_rate_label.text = "+%s/h" % Kit.format_num(int(per_hour.get("gold", 0)))
	# Pending rewards (rebuilt only when the numbers change).
	var pending: Dictionary = st.get("pending", {})
	var sig := JSON.stringify(pending)
	if sig != _pending_sig:
		_pending_sig = sig
		for c in _pending_row.get_children():
			c.queue_free()
		var any := false
		for cur: String in ["gold", "hero_exp", "dust", "gems"]:
			var n := int(pending.get(cur, 0))
			if n <= 0:
				continue
			any = true
			_pending_row.add_child(_pending_pair(Kit.currency_icon(cur, 34), Kit.format_num(n)))
		var gear_n := int(pending.get("gear_count", 0))
		if gear_n > 0:
			any = true
			_pending_row.add_child(_pending_pair(Kit.icon("gear_weapon", 34), "x%d" % gear_n))
		if not any:
			_pending_row.add_child(Kit.caption("Your heroes are gathering rewards...", 22))
	# Quick claim button (rebuilt when its price changes).
	var cost := int(st.get("quick_claim_cost", -1))
	var left := int(st.get("quick_claims_left", 0))
	var qsig := "%d/%d" % [cost, left]
	if qsig != _quick_sig:
		_quick_sig = qsig
		for c in _quick_slot.get_children():
			c.queue_free()
		_quick_slot.add_child(_make_quick_button(cost, left, int(st.get("quick_claim_ms", 7200000))))


func _pending_pair(ic: Control, text: String) -> Control:
	var p := Kit.hbox(4)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(ic)
	p.add_child(Kit.label(text, 24, Kit.INK, "black", 4))
	return p


func _make_quick_button(cost: int, left: int, ms: int) -> Button:
	var hours := "%dh" % (ms / 3600000)
	var b: Button
	if cost < 0 or left <= 0:
		b = Kit.secondary_button("")
		b.disabled = true
		_two_line(b, "Quick Claim", "None left today", Kit.INK_DIM, Kit.INK_DIM)
	elif cost == 0:
		b = Kit.secondary_button("", _quick_claim)
		_two_line(b, "Quick Claim", "Free  ·  %s now" % hours, Kit.INK, Kit.GOOD)
	else:
		b = Kit.cost_button("Quick Claim %s" % hours, "gems", cost, _quick_claim, "secondary")
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 96)
	return b


func _two_line(b: Button, line1: String, line2: String, c1: Color, c2: Color) -> void:
	var v := Kit.vbox(0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := Kit.label(line1, 30, c1, "extrabold")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := Kit.label(line2, 22, c2, "black")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	v.add_child(s)
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_bottom = -6
	b.add_child(v)


func _refresh_battle() -> void:
	for c in _power_row.get_children():
		c.queue_free()
	var st := Game.current_stage()
	var team := int(Game.team_power())
	if st.is_empty():
		_battle_title.text = "Campaign"
		_battle_sub.text = "Every stage cleared. Replay any stage."
		_power_row.add_child(Kit.icon("power", 32))
		_power_row.add_child(Kit.label("Team power %s" % Kit.format_full(team), 24, Kit.GOLD_LIGHT, "black", 4))
		_battle_ready = false
		return
	_battle_title.text = "Battle  %s" % str(st.id)
	_battle_sub.text = str(st.name) + ("  ·  Boss" if bool(st.get("is_boss", false)) else "")
	var rec := int(st.get("recommended_power", 0))
	var col := Kit.GOOD if team >= rec else (Kit.GOLD if team * 100 >= rec * 85 else SHORT_RED)
	_battle_ready = team >= rec
	_power_row.add_child(Kit.icon("power", 32))
	_power_row.add_child(Kit.label("Team %s" % Kit.format_full(team), 24, col, "black", 4))
	_power_row.add_child(Kit.caption("vs", 22))
	_power_row.add_child(Kit.label("Recommended %s" % Kit.format_full(rec), 24, Kit.INK, "black", 4))
	if team < rec:
		_power_row.add_child(Kit.tag("Tough", Color("c0392b") if col == SHORT_RED else Kit.GOLD, Color.WHITE if col == SHORT_RED else DARK_INK, 18))


# ------------------------------------------------------------------ actions

func _claim() -> void:
	var st: Dictionary = Game.idle_status()
	var pending: Dictionary = st.get("pending", {})
	var has_any := false
	for k: String in pending:
		if int(pending[k]) > 0:
			has_any = true
	if not has_any:
		UI.toast("Nothing to claim yet. Rewards build up every minute.")
		Kit.shake(_chest_box, 8)
		return
	var reward: Dictionary = Game.claim_idle()
	UI.show_reward("Idle Rewards", reward)
	_cheer()


func _quick_claim() -> void:
	var st: Dictionary = Game.idle_status()
	var cost := int(st.get("quick_claim_cost", -1))
	var hours := int(st.get("quick_claim_ms", 7200000)) / 3600000
	if cost < 0:
		UI.toast("No quick claims left today", "bad")
		return
	if cost > Game.currency("gems"):
		UI.toast("Not enough gems", "bad")
		return
	var run := func() -> void:
		var res: Dictionary = Game.quick_claim()
		if not bool(res.get("ok", false)):
			UI.toast(str(res.get("error", "Quick claim failed")), "bad")
			return
		UI.show_reward("Quick Claim: %dh" % hours, res.get("value", {}))
		_cheer()
	if cost == 0:
		run.call()
	else:
		UI.confirm("Spend %s gems to collect %d hours of idle rewards now?" % [Kit.format_full(cost), hours], run, Callable(), "Spend %s" % Kit.format_full(cost))


func _on_battle() -> void:
	var st := Game.current_stage()
	if st.is_empty():
		UI.go("campaign")
		return
	UI.go("campaign", {"open_stage": int(st.index)})


## The leader celebrates for a moment after a claim.
func _cheer() -> void:
	if _sprite and is_instance_valid(_sprite) and _sprite.has_method("play_victory"):
		_sprite.call("play_victory")
		_cheer_left = 2.6


# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	_t += delta
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh_idle()
	if _cheer_left > 0.0:
		_cheer_left -= delta
		if _cheer_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	# Chest: breathing glow, stronger and with a wiggle when full.
	var k := 0.5 + 0.5 * sin(_t * (3.2 if _full else 1.6))
	_chest_glow.modulate.a = (0.55 + 0.4 * k) if _full else (0.22 + 0.16 * k)
	_chest_glow.scale = Vector2.ONE * (1.0 + 0.08 * k)
	_chest_glow.pivot_offset = _chest_glow.size * 0.5
	var wig := 0.0
	var cyc := fmod(_t, 2.4 if _full else 5.0)
	if cyc < 0.5 and _pending_sig != "{}":
		wig = sin(cyc * TAU * 4.0) * (1.0 - cyc * 2.0) * (0.12 if _full else 0.06)
	_chest_icon.rotation = wig
	# Battle button: a gentle "ready" breath.
	if _battle_ready:
		var b := 1.0 + 0.015 * sin(_t * 2.4)
		_battle_btn.pivot_offset = _battle_btn.size * 0.5
		if not _battle_btn.is_pressed():
			_battle_btn.scale = Vector2(b, b)
