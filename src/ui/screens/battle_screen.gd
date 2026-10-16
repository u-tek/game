extends Control
## Screen "battle": plays a campaign stage. params: stage_index (int); skip (bool, for
## screenshots: skips to the result right away).
##
## The BattleSim runs a little ahead of what the player sees (SIM_LEAD_MS of battle time).
## Every event is scheduled on a display clock so animations line up with their results:
## an attack starts its swing early enough that the impact frame lands exactly when its
## damage shows, ranged attacks launch a bolt that arrives on time, and an ultimate holds
## the clock for a short cinematic (dim, portrait sweep, skill name, shake) while the
## caster winds up. Battle speed (1x/2x/4x) scales the display clock and the rigs.
## Game.complete_stage is called exactly once per battle: on the result, on Retreat, or
## (as a defeat) if the player leaves mid-fight.

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const UnitView := preload("res://src/ui/battle/unit_view.gd")
const BattleFx := preload("res://src/ui/battle/battle_fx.gd")
const UltCinematic := preload("res://src/ui/battle/ult_cinematic.gd")
const AllyPortrait := preload("res://src/ui/battle/ally_portrait.gd")
const BattleResult := preload("res://src/ui/battle/battle_result.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

const TICK_MS := 100
## How far (battle ms) the sim runs ahead of the display clock. Must exceed the longest lead.
const SIM_LEAD_MS := 760.0
## Battle ms from the start of each attack animation to its impact frame (fallbacks when
## a rig's animation has no "hit" / "release" event; UnitView reads the real timing).
const HIT_LEAD := {"attack_melee": 330.0, "attack_thrust": 320.0, "attack_ranged": 400.0}
## Bolt flight time (battle ms) for ranged attacks; the bolt leaves at the release frame.
const BOLT_MS := 240.0
## Impact frame of the shared "ultimate" animation (seconds at speed 1).
const ULT_HIT_S := 0.98
const TOP_H := 112.0
const BOSS_H := 58.0
const BOTTOM_H := 196.0
## Width of an ally card on the bottom rail.
const PORTRAIT_W := 120.0
const END_DELAY := 1.4
const INTRO_TIME := 1.25
const FRONT_X := [0.31, 0.69]
const BACK_X := [0.16, 0.5, 0.84]
const STATUS_TEXT := {
	"stun": ["Stunned", Color("ffe066")], "burn": ["Burn", Color("ff8a4a")], "regen": ["Regen", Color("5cd6a0")],
	"taunt": ["Taunt", Color("f2c14e")], "atk_up": ["ATK Up", Color("5cd6a0")], "atk_down": ["ATK Down", Color("ff6a6a")],
	"def_up": ["DEF Up", Color("5cd6a0")], "def_down": ["DEF Down", Color("ff6a6a")], "spd_up": ["Haste", Color("6fc3e8")],
}

var _index := -1
var _stage: Dictionary = {}
var _setup: Dictionary = {}
var _sim: BattleSim
var _views: Dictionary = {}
var _portraits: Dictionary = {}
var _queue: Array[Dictionary] = []
var _seq := 0
var _display_ms := 0.0
var _speed := 1
var _hold := 0.0
var _hold_view: Node2D
var _phase := "intro"
var _phase_t := 0.0
var _completed := false
var _team_size := 0
var _boss_uid := ""

var _world: Control
var _units: Node2D
var _dim: ColorRect
var _bars: Node2D
var _fx: Node2D
var _numbers: Control
var _hud: Control
var _bottom: Control
var _overlay: Control
var _timer_label: Label
var _auto_slot: Control
var _speed_label: Label
var _boss_bar: ProgressBar
var _shake_t := 0.0
var _shake_amp := 0.0
var _dim_target := 0.0
var _manual_hint: Control
var _num_stack: Dictionary = {}
var _shown_secs := -1


func setup(params: Dictionary) -> void:
	UI.set_chrome(false, false)
	_index = int(params.get("stage_index", Game.cleared_count()))
	_stage = Game.stage(_index)
	if _stage.is_empty() or Game.stage_status(_index) == "locked":
		_completed = true
		UI.toast("That stage is locked", "bad")
		UI.go("campaign")
		return
	_setup = Game.stage_battle_setup(_index)
	if (_setup.get("allies", []) as Array).is_empty():
		_completed = true
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	_team_size = (_setup.allies as Array).size()
	_sim = BattleSim.new(_setup)
	_sim.auto_ultimates = Game.setting("auto_ultimates") != false
	var sp: Variant = Game.setting("battle_speed")
	_speed = int(sp) if (sp is int or sp is float) and [1, 2, 4].has(int(sp)) else 1
	for u: Dictionary in _sim.units:
		if u.side == "enemy" and bool(u.is_boss):
			_boss_uid = str(u.uid)
	_build()
	_layout_units()
	_start_intro()
	# Screenshots: jump to the result (params skip = true).
	if bool(params.get("skip", false)):
		get_tree().create_timer(0.4).timeout.connect(_skip)


func _exit_tree() -> void:
	# Leaving mid-fight (back gesture) counts as a defeat, so the battle is still
	# reported exactly once.
	if not _completed and _index >= 0 and _sim != null:
		_completed = true
		Game.complete_stage.call_deferred(_index, {"victory": false, "winner": "enemy", "retreat": true})


# ------------------------------------------------------------------ build

func _build() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.mouse_filter = MOUSE_FILTER_IGNORE
	_world.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_world)
	var bd := SceneBackdrop.new()
	bd.kind = str(_setup.get("background", _stage.get("background", "chapter-1")))
	bd.floor_shade = 0.0
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_world.add_child(bd)
	# Horizon and battle ring follow the field layout.
	var f := _field_rect()
	bd.horizon = clampf((f.position.y + f.size.y * 0.12) / maxf(size.y, 1.0), 0.12, 0.4) if size.y > 0.0 else 0.22
	bd.sigil_y = (f.position.y + f.size.y * 0.5) / maxf(size.y, 1.0) if size.y > 0.0 else 0.5

	_units = Node2D.new()
	_units.name = "Units"
	_world.add_child(_units)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.025, 0.035, 1.0)
	_dim.modulate.a = 0.0
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	_dim.size = Vector2(4000, 4000)
	_dim.position = Vector2(-1000, -1000)
	_units.add_child(_dim)
	_bars = Node2D.new()
	_bars.name = "Bars"
	_world.add_child(_bars)
	_fx = Node2D.new()
	_fx.name = "Fx"
	_world.add_child(_fx)
	_numbers = Control.new()
	_numbers.name = "Numbers"
	_numbers.mouse_filter = MOUSE_FILTER_IGNORE
	_numbers.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_world.add_child(_numbers)

	for u: Dictionary in _sim.units:
		var v: Node2D = UnitView.new()
		_units.add_child(v)
		v.call("setup", u, 1.0, 1 if u.side == "ally" else -1, u.side == "enemy", _bars)
		_views[str(u.uid)] = v
		var spr: Node2D = v.get("sprite")
		if spr and spr.has_signal("vfx_requested"):
			spr.connect("vfx_requested", _on_vfx.bind(v))

	_build_hud()
	_build_bottom()
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_overlay)
	resized.connect(_on_resized)


func _on_resized() -> void:
	_layout_units()
	var bd := _world.get_child(0)
	var f := _field_rect()
	if bd and size.y > 0.0:
		bd.set("horizon", clampf((f.position.y + f.size.y * 0.12) / size.y, 0.12, 0.4))
		bd.set("sigil_y", (f.position.y + f.size.y * 0.5) / size.y)
		(bd as CanvasItem).queue_redraw()


## Field area between the HUD and the portrait bar.
func _field_rect() -> Rect2:
	var top := UI.safe_top() + TOP_H + (BOSS_H if _boss_uid != "" else 0.0)
	var bottom := size.y - UI.safe_bottom() - BOTTOM_H
	return Rect2(0, top, size.x, maxf(bottom - top, 200.0))


func _layout_units() -> void:
	if _units == null or size.y <= 0.0:
		return
	var f := _field_rect()
	var fh := f.size.y
	var d := fh * 0.14
	var g := fh * 0.05
	var unit_h := (fh - 18.0 - 2.0 * d - g) * 0.5
	var k := clampf((unit_h - 44.0) / 300.0, 0.62, 1.0)
	var rows := {
		"enemy_back": [f.position.y + unit_h, 0.9],
		"enemy_front": [f.position.y + unit_h + d, 0.95],
		"ally_front": [f.position.y + unit_h * 2.0 + d + g, 1.0],
		"ally_back": [f.position.y + unit_h * 2.0 + 2.0 * d + g, 1.04],
	}
	var order: Array = []
	for uid: String in _views:
		var v: Node2D = _views[uid]
		var side: String = v.get("side")
		var slot: int = v.get("slot")
		var back := slot >= 2
		var key := side + ("_back" if back else "_front")
		var row: Array = rows[key]
		var x: float = f.size.x * (float(BACK_X[clampi(slot - 2, 0, 2)]) if back else float(FRONT_X[clampi(slot, 0, 1)]))
		var y: float = row[0]
		var depth: float = row[1]
		var kk := k * depth
		var sprite: Node2D = v.get("sprite")
		var boss: bool = v.get("is_boss")
		if boss and side == "enemy":
			# Bosses are 30% bigger: keep the crown on screen.
			y = maxf(y, f.position.y + 300.0 * kk * 1.3 + 30.0)
		v.position = Vector2(x, y)
		sprite.scale = Vector2(kk, kk)
		v.set("depth_scale", depth)
		v.set("_head_h", float(sprite.call("get_height")))
		order.append(v)
	# Draw order: further up the screen is further away.
	order.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
	for i in order.size():
		_units.move_child(order[i], i)
	_units.move_child(_dim, -1)


## Top HUD (style v2): exit, the stage plate (cyan stage tag, timer, name) on dark glass,
## then Auto / speed / Skip on the right; a boss plate with its HP bar under it.
func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.mouse_filter = MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_hud)
	var top := UI.safe_top()
	# Top shade so the controls read on any backdrop.
	var shade := TextureRect.new()
	shade.texture = Kit.vgradient(Color(Kit.CHROME, 0.88), Color(Kit.CHROME, 0.0))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.anchor_right = 1.0
	shade.offset_bottom = top + TOP_H + 40.0
	_hud.add_child(shade)

	var row := Kit.hbox(6)
	row.anchor_right = 1.0
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = top + 8
	row.offset_bottom = top + 8 + 96
	_hud.add_child(row)
	var back := _hud_button("exit", "Exit", _ask_retreat)
	row.add_child(back)
	var plate := PanelContainer.new()
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", Kit.style("notice"))
	plate.size_flags_horizontal = SIZE_EXPAND_FILL
	plate.size_flags_vertical = SIZE_SHRINK_CENTER
	var info := Kit.vbox(0)
	info.mouse_filter = MOUSE_FILTER_IGNORE
	var t1 := Kit.hbox(10)
	t1.mouse_filter = MOUSE_FILTER_IGNORE
	t1.add_child(Kit.tag(str(_stage.get("id", "")), Kit.ACCENT, Color.WHITE, 24))
	_timer_label = Kit.label("1:30", 30, Color.WHITE, "cond_bold")
	t1.add_child(Kit.icon("timer", 24, Kit.INK_DIM))
	t1.add_child(_timer_label)
	info.add_child(t1)
	var nm := Kit.label(str(_stage.get("name", "")).to_upper(), 18, Kit.INK_DIM, "cond_bold")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 120
	info.add_child(nm)
	plate.add_child(Kit.margin(info, 14, 8))
	row.add_child(plate)
	_auto_slot = Control.new()
	_auto_slot.custom_minimum_size = Vector2(84, 96)
	row.add_child(_auto_slot)
	_rebuild_auto()
	var spd := _hud_button("speed", "", _toggle_speed)
	_speed_label = spd.get_meta("caption")
	_speed_label.text = "%dx" % _speed
	row.add_child(spd)
	row.add_child(_hud_button("skip", "Skip", _skip))

	if _boss_uid != "":
		var bv: Node2D = _views[_boss_uid]
		var bp := PanelContainer.new()
		bp.mouse_filter = MOUSE_FILTER_IGNORE
		bp.add_theme_stylebox_override("panel", Kit.style("notice"))
		bp.anchor_left = 0.5
		bp.anchor_right = 0.5
		bp.offset_left = -260
		bp.offset_right = 260
		bp.offset_top = top + TOP_H - 2
		bp.offset_bottom = top + TOP_H + BOSS_H - 6
		var box := Kit.vbox(2)
		box.mouse_filter = MOUSE_FILTER_IGNORE
		var nrow := Kit.hbox(8)
		nrow.mouse_filter = MOUSE_FILTER_IGNORE
		nrow.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 16))
		var bn := Kit.label(str(Game.hero_def(str(bv.get("hero_id"))).get("name", "")).to_upper(), 20, Color.WHITE, "cond_bold")
		bn.size_flags_horizontal = SIZE_EXPAND_FILL
		nrow.add_child(bn)
		nrow.add_child(Kit.deco("barcode", Vector2(60, 14), Color(1, 1, 1, 0.35)))
		box.add_child(nrow)
		_boss_bar = Kit.progress_bar(1.0, 1.0, Kit.EMBER, 14)
		box.add_child(_boss_bar)
		bp.add_child(Kit.margin(box, 12, 5))
		_hud.add_child(bp)


## HUD button: an 76 px glass (or cyan) tile with an uppercase caption under it. The
## caption Label is in meta "caption" (its text keeps its case; it displays uppercase).
func _hud_button(icon_name: String, caption: String, cb: Callable, look: String = "round") -> Control:
	var b := Kit.icon_button(icon_name, cb, 76, look)
	b.name = "Hud_" + (caption if caption != "" else icon_name).to_pascal_case()
	b.custom_minimum_size = Vector2(80, 96)
	var l := Kit.label(caption, 17, Color.WHITE, "cond_bold")
	l.uppercase = true
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_top = -22
	l.offset_bottom = 2
	b.add_child(l)
	b.set_meta("caption", l)
	return b


func _rebuild_auto() -> void:
	for c in _auto_slot.get_children():
		c.queue_free()
	var on := _sim.auto_ultimates
	var b := _hud_button("auto", "Auto" if on else "Manual", _toggle_auto, "accent" if on else "round")
	b.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_auto_slot.add_child(b)


## Bottom rail (style v2): the five ally cards on a dark glass band with a technical top
## line; the faction bonus tag above its left end; the manual-mode hint above its centre.
func _build_bottom() -> void:
	_bottom = Control.new()
	_bottom.name = "Bottom"
	_bottom.mouse_filter = MOUSE_FILTER_IGNORE
	_bottom.anchor_top = 1.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_top = -(BOTTOM_H + UI.safe_bottom())
	add_child(_bottom)
	var bg := TextureRect.new()
	bg.texture = Kit.vgradient(Color(Kit.CHROME, 0.0), Color(Kit.CHROME, 0.94))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.offset_top = -50
	_bottom.add_child(bg)
	var rail := Panel.new()
	rail.mouse_filter = MOUSE_FILTER_IGNORE
	rail.add_theme_stylebox_override("panel", Kit.box(Color(0.06, 0.065, 0.075, 0.72), Color(0.03, 0.035, 0.04, 0.85), Color.TRANSPARENT, 0))
	rail.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	rail.offset_top = 8
	_bottom.add_child(rail)
	var line := Kit.deco("techline", Vector2(720, 10), Color(1, 1, 1, 0.35))
	line.anchor_right = 1.0
	line.offset_top = 3
	line.offset_bottom = 13
	_bottom.add_child(line)
	var row := Kit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.anchor_right = 1.0
	row.offset_top = 26
	row.offset_bottom = 26 + 164
	_bottom.add_child(row)
	var by_slot := {}
	for u: Dictionary in _sim.units:
		if u.side == "ally":
			by_slot[int(u.slot)] = u
	for s in 5:
		if not by_slot.has(s):
			var e := Control.new()
			e.custom_minimum_size = Vector2(PORTRAIT_W, 150)
			e.mouse_filter = MOUSE_FILTER_IGNORE
			var ph := Kit.empty_slot(PORTRAIT_W)
			ph.mouse_filter = MOUSE_FILTER_IGNORE
			ph.modulate.a = 0.55
			e.add_child(ph)
			row.add_child(e)
			continue
		var u: Dictionary = by_slot[s]
		var p: Button = AllyPortrait.new()
		p.call("setup", u, PORTRAIT_W)
		p.set("manual", not _sim.auto_ultimates)
		var uid := str(u.uid)
		p.pressed.connect(func() -> void: _on_portrait(uid))
		row.add_child(p)
		_portraits[uid] = p
	# Faction bonus tag.
	var fb := _sim.faction_bonus("ally")
	if not fb.is_empty():
		var chip := PanelContainer.new()
		chip.mouse_filter = MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", Kit.style("notice"))
		var r2 := Kit.hbox(6)
		r2.mouse_filter = MOUSE_FILTER_IGNORE
		r2.add_child(Kit.faction_icon(str(fb.faction), 26))
		r2.add_child(Kit.label("x%d  +%d%% HP & ATK" % [int(fb.count), int(fb.bonus_bp) / 100], 19, Kit.GOOD, "cond_bold"))
		chip.add_child(Kit.margin(r2, 10, 2))
		chip.position = Vector2(12, -36)
		_bottom.add_child(chip)
	var hint := PanelContainer.new()
	hint.mouse_filter = MOUSE_FILTER_IGNORE
	hint.add_theme_stylebox_override("panel", Kit.box(Color("0c0d10e6"), Color("0c0d10e6"), Kit.ACCENT, 6, 2, 0))
	var hl := Kit.label("Manual: tap a glowing card to cast", 20, Color.WHITE, "extrabold")
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_child(Kit.margin(hl, 18, 4))
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.grow_horizontal = GROW_DIRECTION_BOTH
	hint.offset_top = -44
	hint.offset_bottom = -8
	hint.visible = false
	_bottom.add_child(hint)
	_manual_hint = hint


## Shows the manual-mode hint for a few seconds.
func _flash_hint() -> void:
	if _manual_hint == null:
		return
	_manual_hint.visible = true
	_manual_hint.modulate.a = 1.0
	var tw := _manual_hint.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_manual_hint, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _manual_hint.visible = false)


# ------------------------------------------------------------------ intro

func _start_intro() -> void:
	_phase = "intro"
	_phase_t = 0.0
	for uid: String in _views:
		var v: Node2D = _views[uid]
		var sprite: Node2D = v.get("sprite")
		sprite.modulate.a = 0.0
		var dy := 26.0 if v.get("side") == "ally" else -26.0
		sprite.position.y = dy
		var tw := sprite.create_tween().set_parallel(true)
		var delay := randf_range(0.0, 0.25)
		tw.tween_property(sprite, "modulate:a", 1.0, 0.35).set_delay(delay)
		tw.tween_property(sprite, "position:y", 0.0, 0.45).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		v.call("set_speed", float(_speed))
	var banner := Kit.vbox(4)
	banner.mouse_filter = MOUSE_FILTER_IGNORE
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	var rib := Kit.ribbon("Stage %s" % str(_stage.get("id", "")), 440, Kit.ACCENT, Color.WHITE, 40)
	banner.add_child(rib)
	var nm := Kit.label(str(_stage.get("name", "")).to_upper(), 30, Color.WHITE, "cond_bold", 6)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(nm)
	banner.set_anchors_and_offsets_preset(PRESET_CENTER)
	banner.offset_left = -240
	banner.offset_right = 240
	banner.offset_top = -80
	banner.offset_bottom = 40
	_overlay.add_child(banner)
	banner.pivot_offset = Vector2(240, 60)
	Kit.pop_in(banner, 0.05, 0.35)
	var tw2 := banner.create_tween()
	tw2.tween_interval(0.85)
	tw2.tween_property(banner, "modulate:a", 0.0, 0.2)
	tw2.tween_callback(banner.queue_free)
	var fight := Kit.title("FIGHT", 96, Color.WHITE)
	fight.add_theme_color_override("font_outline_color", Kit.ACCENT_DEEP)
	fight.add_theme_constant_override("outline_size", 10)
	fight.add_theme_color_override("font_shadow_color", Color(Kit.ACCENT, 0.6))
	fight.set_anchors_and_offsets_preset(PRESET_CENTER)
	fight.offset_left = -260
	fight.offset_right = 260
	fight.offset_top = -60
	fight.offset_bottom = 60
	fight.pivot_offset = Vector2(260, 60)
	fight.modulate.a = 0.0
	_overlay.add_child(fight)
	var tw3 := fight.create_tween()
	tw3.tween_interval(0.95)
	tw3.tween_callback(func() -> void:
		fight.modulate.a = 1.0
		fight.scale = Vector2(1.6, 1.6)
		UI.sfx("hit"))
	tw3.tween_property(fight, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw3.tween_interval(0.25)
	tw3.tween_property(fight, "modulate:a", 0.0, 0.2)
	tw3.tween_callback(fight.queue_free)
	if not _sim.auto_ultimates:
		_flash_hint()


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if _sim == null:
		return
	_update_shake(delta)
	_dim.modulate.a = move_toward(_dim.modulate.a, _dim_target, delta * 4.0)
	match _phase:
		"intro":
			_phase_t += delta
			if _phase_t >= INTRO_TIME:
				_phase = "fight"
		"fight":
			_step_display(delta)
		"ending":
			_phase_t += delta
			if _phase_t >= END_DELAY:
				_finish(_sim.outcome())
	_update_hud()


func _step_display(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		if _hold > 0.0:
			return
		_end_hold()
	_display_ms += delta * 1000.0 * _speed
	while not _sim.is_over() and float(_sim.t_ms) < _display_ms + SIM_LEAD_MS:
		_ingest(_sim.step())
	while not _queue.is_empty() and float(_queue[0].at) <= _display_ms:
		var item: Dictionary = _queue.pop_front()
		_apply(item.ev)
		if _hold > 0.0 or _phase != "fight":
			break
	for uid: String in _views:
		_views[uid].call("tick_statuses", _display_ms)


func _ingest(events: Array) -> void:
	for ev: Dictionary in events:
		var t := float(ev.get("t", _sim.t_ms))
		match str(ev.type):
			"attack":
				var v: Node2D = _views.get(str(ev.src))
				var anim := str(v.call("attack_anim")) if v else "attack_melee"
				if anim == "attack_ranged":
					var rel: float = float(v.get("release_ms")) if v and float(v.get("release_ms")) > 0.0 else float(HIT_LEAD.attack_ranged)
					_push(t - rel - BOLT_MS, ev)
					_push(t - BOLT_MS, {"type": "_bolt", "src": ev.src, "target": ev.target, "t": t})
				else:
					var hit: float = float(v.get("hit_ms")) if v and float(v.get("hit_ms")) > 0.0 else float(HIT_LEAD.get(anim, 330.0))
					_push(t - hit, ev)
			"end":
				_push(t + 350.0, ev)
			_:
				_push(t, ev)


func _push(at: float, ev: Dictionary) -> void:
	_seq += 1
	var item := {"at": maxf(at, _display_ms), "seq": _seq, "ev": ev}
	var i := _queue.bsearch_custom(item, func(a: Dictionary, b: Dictionary) -> bool:
		return a.at < b.at or (a.at == b.at and a.seq < b.seq), false)
	_queue.insert(i, item)


func _apply(ev: Dictionary) -> void:
	match str(ev.type):
		"attack":
			var src: Node2D = _views.get(str(ev.src))
			var dst: Node2D = _views.get(str(ev.target))
			if src and dst and not src.get("dead"):
				src.call("play_attack", _lunge_point(src, dst))
		"_bolt":
			var s2: Node2D = _views.get(str(ev.src))
			var d2: Node2D = _views.get(str(ev.target))
			if s2 and d2 and not s2.get("dead"):
				var col := _fx_color(s2)
				BattleFx.projectile(_fx, _fx.to_local(s2.call("hand_global")), _fx.to_local(d2.call("chest_global")), BOLT_MS / 1000.0 / _speed, col)
		"damage":
			_on_damage(ev)
		"heal":
			var hv: Node2D = _views.get(str(ev.target))
			if hv:
				hv.call("set_hp", int(ev.hp_after), int(hv.get("shield")))
				BattleFx.number(_numbers, _num_pos(hv), "+%s" % Kit.format_num(int(ev.amount)), Color("6ff0b0"), 28, 60.0, 0.0, _life())
				BattleFx.burst(_fx, _fx.to_local(hv.call("chest_global")), Color("5cd6a0"), 46.0, 6)
				_sync_portrait(hv)
		"shield":
			var sv: Node2D = _views.get(str(ev.target))
			if sv:
				sv.call("set_hp", int(sv.get("hp")), int(ev.shield_after))
				BattleFx.number(_numbers, _num_pos(sv) + Vector2(0, 26), "+%s" % Kit.format_num(int(ev.amount)), Color("a8e2ff"), 24, 50.0, 0.0, _life())
				BattleFx.burst(_fx, _fx.to_local(sv.call("chest_global")), Color("8fd3ff"), 60.0, 0)
		"status":
			var tv: Node2D = _views.get(str(ev.target))
			if tv and not tv.get("dead"):
				var st := str(ev.status)
				tv.call("add_status", st, _display_ms + float(ev.duration_ms))
				var info: Array = STATUS_TEXT.get(st, [st.capitalize(), Kit.INK])
				BattleFx.number(_numbers, _num_pos(tv) + Vector2(0, -34), str(info[0]), info[1], 22, 40.0, 0.08, _life())
		"ultimate":
			_start_ult(ev)
		"energy":
			var ev_v: Node2D = _views.get(str(ev.unit))
			if ev_v:
				ev_v.call("set_energy", int(ev.energy))
				var p: Node = _portraits.get(str(ev.unit))
				if p:
					p.call("set_energy", int(ev.energy))
		"death":
			var dv: Node2D = _views.get(str(ev.unit))
			if dv:
				dv.call("die")
				var dp: Node = _portraits.get(str(ev.unit))
				if dp:
					dp.call("set_dead")
				if str(ev.unit) == _boss_uid and _boss_bar:
					Kit.set_progress(_boss_bar, 0.0)
		"end":
			_on_end(str(ev.winner))


func _on_damage(ev: Dictionary) -> void:
	var dst: Node2D = _views.get(str(ev.target))
	if dst == null:
		return
	var src: Node2D = _views.get(str(ev.src))
	dst.call("set_hp", int(ev.hp_after), int(ev.shield_after))
	_sync_portrait(dst)
	var amount := int(ev.amount)
	var crit := bool(ev.get("crit", false))
	var adv := bool(ev.get("advantage", false))
	var ult := bool(ev.get("from_ultimate", false))
	var dot := bool(ev.get("dot", false))
	var on_ally := str(dst.get("side")) == "ally"
	var col := Color("fff3e0")
	var fs := 30
	var text := Kit.format_num(amount)
	if dot:
		col = Color("ff9a5a")
		fs = 22
	elif bool(ev.get("execute", false)):
		col = Color("ff5a4a")
		fs = 38
		text = "EXECUTE"
	else:
		if on_ally:
			col = Color("ff8a7a")
		elif adv:
			col = Color("ffb04a")
		if crit:
			col = Color("ffd84a") if not on_ally else Color("ff5a4a")
			fs = 42
			text += "!"
		if ult:
			fs += 4
	BattleFx.number(_numbers, _num_pos(dst) + Vector2(randf_range(-26.0, 26.0), 0), text, col, fs, 70.0 if not dot else 44.0, 0.0, _life())
	if not dot:
		dst.call("play_hit")
		var at: Vector2 = _fx.to_local(dst.call("chest_global"))
		if ult:
			BattleFx.burst(_fx, at, _fx_color(src) if src else Kit.ACCENT_HI, 80.0, 10)
		elif src and str(src.call("attack_anim")) != "attack_ranged" and not bool(src.get("has_swing_vfx")):
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), str(src.get("side")) == "enemy", 64.0 * float(dst.get("depth_scale")))
		UI.sfx("hit")
		if crit:
			_shake(5.0)
	if str(ev.target) == _boss_uid and _boss_bar:
		Kit.set_progress(_boss_bar, float(ev.hp_after) / float(maxi(1, int(dst.get("max_hp")))), 1.0)


## Effects the hero animations ask for (animation events named "vfx_<kind>").
func _on_vfx(kind: String, pos: Vector2, facing: int, v: Node2D) -> void:
	var at := _fx.to_local(pos)
	var col := _fx_color(v)
	var k := float(v.get("depth_scale"))
	match kind:
		"slash":
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), facing < 0, 62.0 * k)
		"thrust":
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), facing < 0, 44.0 * k)
		"bolt":
			BattleFx.burst(_fx, at, col, 26.0 * k, 4)
		"burst":
			BattleFx.burst(_fx, at, col, 72.0 * k, 10)
		"charge":
			BattleFx.burst(_fx, at, col, 44.0 * k, 6)
		"sparkle":
			BattleFx.burst(_fx, at, Kit.GOLD_LIGHT, 34.0 * k, 6)
		"dissolve":
			BattleFx.burst(_fx, at, Color("b48cff"), 80.0 * k, 12)


## Floating-number lifetime factor for the current battle speed.
func _life() -> float:
	return 1.0 / sqrt(float(_speed))


func _sync_portrait(v: Node2D) -> void:
	var p: Node = _portraits.get(str(v.get("uid")))
	if p:
		p.call("set_hp", int(v.get("hp")))


## Where a melee lunge should stop: just short of the target, along the line between them.
func _lunge_point(src: Node2D, dst: Node2D) -> Vector2:
	var a := src.global_position
	var b := dst.global_position
	var dist := a.distance_to(b)
	if dist < 1.0:
		return b
	return b + (a - b) / dist * minf(110.0, dist * 0.5)


## Spawn point for a floating number over a unit. Numbers that land on the same unit in
## quick succession stack upward instead of overlapping.
func _num_pos(v: Node2D) -> Vector2:
	var uid := str(v.get("uid"))
	var now := Time.get_ticks_msec()
	var st: Array = _num_stack.get(uid, [0, 0])
	var n := int(st[1]) + 1 if now - int(st[0]) < 320 else 0
	_num_stack[uid] = [now, n % 4]
	return v.call("head_global") - _numbers.global_position + Vector2(0, -10 - (n % 4) * 30)


func _fx_color(v: Node2D) -> Color:
	if v == null:
		return Kit.ACCENT_HI
	if str(v.get("side")) == "enemy":
		return Color("b48cff")
	return HeroArt.faction_color(str(v.get("faction"))).lightened(0.3)


# ------------------------------------------------------------------ ultimates

func _start_ult(ev: Dictionary) -> void:
	var v: Node2D = _views.get(str(ev.src))
	if v == null or v.get("dead"):
		return
	var ally := str(v.get("side")) == "ally"
	# The caster's wind-up plays during the hold; enemy ultimates wind up faster so the
	# player's own heroes get the longer, bigger moment.
	var cs := minf(float(_speed), 2.0) * (1.0 if ally else 1.6)
	var hit_s: float = float(v.get("ult_hit_s"))
	var d := (hit_s if hit_s > 0.0 else ULT_HIT_S) / cs
	_hold = d
	_hold_view = v
	for uid: String in _views:
		var u: Node2D = _views[uid]
		u.call("set_speed", cs if u == v else 0.0)
		u.call("bars_visible", u == v)
	var target := Vector2.INF
	var targets: Array = ev.get("targets", [])
	if not targets.is_empty():
		var tv: Node2D = _views.get(str(targets[0]))
		if tv and str(tv.get("side")) != str(v.get("side")):
			target = _lunge_point(v, tv)
	v.call("play_ultimate", target)
	_units.move_child(v, -1)
	_dim_target = 0.62 if ally else 0.4
	var c: Control = UltCinematic.new()
	_overlay.add_child(c)
	c.call("play", str(v.get("hero_id")), str(ev.get("skill_name", "Ultimate")), ally, d + 0.12)
	UI.sfx("ult")
	UI.haptic(40 if ally else 20)
	_shake(4.0)
	var p: Node = _portraits.get(str(ev.src))
	if p:
		p.set("queued", false)


func _end_hold() -> void:
	_hold = 0.0
	_dim_target = 0.0
	for uid: String in _views:
		var u: Node2D = _views[uid]
		u.call("set_speed", float(_speed))
		u.call("bars_visible", true)
	if _hold_view and is_instance_valid(_hold_view):
		var ally := str(_hold_view.get("side")) == "ally"
		_shake(12.0 if ally else 8.0)
	_hold_view = null
	_layout_order()


## Restores depth order after a caster was raised above the dim.
func _layout_order() -> void:
	var order: Array = []
	for uid: String in _views:
		order.append(_views[uid])
	order.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
	for i in order.size():
		_units.move_child(order[i], i)
	_units.move_child(_dim, -1)


func _on_portrait(uid: String) -> void:
	if _phase != "fight" and _phase != "intro":
		return
	var p: Node = _portraits.get(uid)
	var v: Node2D = _views.get(uid)
	if p == null or v == null or v.get("dead"):
		return
	if int(v.get("energy")) < 1000:
		UI.toast("%s is still charging" % str(Game.hero_def(str(v.get("hero_id"))).get("name", "")))
		return
	if _sim.request_ultimate(uid):
		UI.sfx("tap")
		p.call("mark_queued")
	elif _sim.auto_ultimates or bool(p.get("queued")):
		p.call("mark_queued")
	elif (_sim.unit(uid).get("statuses", {}) as Dictionary).has("stun"):
		UI.toast("%s is stunned" % str(Game.hero_def(str(v.get("hero_id"))).get("name", "")), "bad")


# ------------------------------------------------------------------ controls

func _toggle_auto() -> void:
	var on := not _sim.auto_ultimates
	_sim.auto_ultimates = on
	Game.set_setting("auto_ultimates", on)
	_rebuild_auto()
	for uid: String in _portraits:
		var p: Node = _portraits[uid]
		p.set("manual", not on)
		(p as CanvasItem).queue_redraw()
	if not on and _phase != "result":
		_flash_hint()
	else:
		_manual_hint.visible = false
	UI.toast("Auto ultimates on" if on else "Manual ultimates")


func _toggle_speed() -> void:
	_speed = {1: 2, 2: 4, 4: 1}.get(_speed, 1)
	Game.set_setting("battle_speed", _speed)
	_speed_label.text = "%dx" % _speed
	if _hold <= 0.0:
		for uid: String in _views:
			_views[uid].call("set_speed", float(_speed))


func _skip() -> void:
	if _phase == "result" or _completed:
		return
	var out := _sim.run_to_end()
	_queue.clear()
	_hold = 0.0
	_dim_target = 0.0
	for c in _overlay.get_children():
		c.queue_free()
	for u: Dictionary in _sim.units:
		var v: Node2D = _views.get(str(u.uid))
		if v == null:
			continue
		v.call("set_speed", float(_speed))
		v.call("bars_visible", true)
		v.call("snap_to", u)
		var p: Node = _portraits.get(str(u.uid))
		if p:
			if bool(u.alive):
				p.call("set_hp", int(u.hp))
				p.call("set_energy", int(u.energy))
			else:
				p.call("set_dead")
	if _boss_bar and _boss_uid != "":
		var bu := _sim.unit(_boss_uid)
		Kit.set_progress(_boss_bar, float(bu.get("hp", 0)) / float(maxi(1, int(bu.get("max_hp", 1)))), 1.0)
	_display_ms = float(_sim.t_ms)
	_on_end(str(out.get("winner", "enemy")))
	_phase_t = END_DELAY - 0.5


func _ask_retreat() -> void:
	if _completed:
		UI.go("campaign")
		return
	UI.confirm("Retreat from this battle? It counts as a defeat.", func() -> void:
		if _completed:
			return
		_completed = true
		Game.complete_stage(_index, {"victory": false, "winner": "enemy", "retreat": true})
		UI.go("campaign"), Callable(), "Retreat", "Keep fighting", true)


# ------------------------------------------------------------------ end

func _on_end(winner: String) -> void:
	if _phase == "ending" or _phase == "result":
		return
	_phase = "ending"
	_phase_t = 0.0
	_manual_hint.visible = false
	for uid: String in _views:
		var v: Node2D = _views[uid]
		if not v.get("dead") and (str(v.get("side")) == "ally") == (winner == "ally"):
			var sprite: Node2D = v.get("sprite")
			sprite.call("set_facing", int(v.get("home_facing")))
			sprite.call("play_victory")


func _finish(outcome: Dictionary) -> void:
	if _completed:
		return
	_completed = true
	_phase = "result"
	var res := Game.complete_stage(_index, outcome)
	var val: Dictionary = res.get("value", {}) if res.get("value") is Dictionary else {}
	var r: Control = BattleResult.new()
	r.set("on_action", _on_result_action)
	_overlay.add_child(r)
	if bool(outcome.get("victory", false)):
		UI.sfx("victory")
		UI.haptic(30)
		var nxt := _index + 1
		var has_next := nxt < Game.stages().size() and Game.stage_status(nxt) != "locked"
		var new_chapter := has_next and int(Game.stage(nxt).get("chapter", 0)) != int(_stage.get("chapter", 0))
		r.call("show_victory", {
			"stage": _stage, "outcome": outcome, "reward": val.get("reward", {}),
			"first_clear": bool(val.get("first_clear", false)), "stars": _stars(outcome),
			"team_size": _team_size, "mvp": _mvp(outcome), "has_next": has_next,
			"next_text": "Next Chapter" if new_chapter else "Next Stage",
			"safe_top": UI.safe_top(), "safe_bottom": UI.safe_bottom(),
		})
	else:
		UI.sfx("defeat")
		r.call("show_defeat", {
			"stage": _stage, "outcome": outcome, "team_power": int(Game.team_power()),
			"safe_top": UI.safe_top(), "safe_bottom": UI.safe_bottom(),
		})


## 3 stars with nobody lost, 2 with at least half the team standing, else 1.
func _stars(outcome: Dictionary) -> int:
	var alive := int(outcome.get("allies_alive", 0))
	if alive >= _team_size:
		return 3
	if alive * 2 >= _team_size:
		return 2
	return 1


func _mvp(outcome: Dictionary) -> Dictionary:
	var dmg: Dictionary = outcome.get("damage_dealt", {})
	var best := ""
	var best_n := -1
	var total := 0
	for uid: String in dmg:
		if not uid.begins_with("a"):
			continue
		var n := int(dmg[uid])
		total += n
		if n > best_n:
			best_n = n
			best = uid
	if best == "" or not _views.has(best):
		return {}
	return {"hero_id": str(_views[best].get("hero_id")), "damage": best_n, "share": (best_n * 100 / maxi(1, total))}


func _on_result_action(action_name: String) -> void:
	match action_name:
		"home":
			UI.go("home")
		"next":
			var nxt := _index + 1
			if int(Game.stage(nxt).get("chapter", 0)) != int(_stage.get("chapter", 0)):
				UI.go("campaign", {"open_stage": nxt})
			else:
				UI.go("battle", {"stage_index": nxt})
		"retry":
			UI.go("battle", {"stage_index": _index})
		"campaign":
			UI.go("campaign")
		"heroes":
			UI.go("heroes")
		"level":
			# Straight to the team hero who most needs a level (else the hero list).
			var lid := Guide.level_target()
			if lid != "":
				UI.go("hero_detail", {"hero_id": lid, "browse": Game.formation().filter(func(x: Variant) -> bool: return str(x) != "")})
			else:
				UI.go("heroes")
		"formation":
			UI.go("formation")


# ------------------------------------------------------------------ hud & feel

func _update_hud() -> void:
	if _timer_label == null:
		return
	var secs := maxi(0, int(BattleSim.MAX_MS - _display_ms)) / 1000
	if secs == _shown_secs:
		return
	_shown_secs = secs
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	if secs <= 10:
		_timer_label.add_theme_color_override("font_color", Color("ff6a50"))


func _shake(amount: float) -> void:
	_shake_amp = maxf(_shake_amp, amount)
	_shake_t = 0.28


func _update_shake(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := maxf(_shake_t, 0.0) / 0.28
		_world.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp * k
		if _shake_t <= 0.0:
			_shake_amp = 0.0
			_world.position = Vector2.ZERO
