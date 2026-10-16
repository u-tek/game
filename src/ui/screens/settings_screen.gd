extends Control
## Screen "settings": audio (sound, music, vibration), battle defaults (speed, auto
## ultimates), about (version, credits with font licenses), Reset save (asks first) and the
## dev tools section (+3000 gems, +100K gold, +50K hero EXP, skip 8 hours) for testing.

const DEV_GRANTS: Array[Array] = [
	["gems", 3000, "+3,000 Gems"],
	["gold", 100000, "+100K Gold"],
	["hero_exp", 50000, "+50K Hero EXP"],
]
const SKIP_MS := 8 * 3600000
const SPEEDS: Array[int] = [1, 2, 4]

var _scroll: ScrollContainer


func setup(params: Dictionary) -> void:
	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_right = -22
	col.offset_top = 8
	add_child(col)
	col.add_child(Kit.screen_header("Settings"))
	var list := Kit.vbox(20)
	var m := Kit.margin(list, 0, 0)
	m.add_theme_constant_override("margin_bottom", 30)
	_scroll = Kit.scroll(m)
	col.add_child(_scroll)

	list.add_child(_section("Sound", [
		_toggle_row("sound_on", "Sound effects", "Taps, rewards, battle hits", "sound", true),
		_toggle_row("music", "Music", "The twilight theme", "music", true),
		_toggle_row("vibrate", "Vibration", "Haptics on phones", "haptics", true),
	]))
	list.add_child(_section("Battle", [_speed_row(), _toggle_row("auto", "Auto ultimates", "Heroes fire ultimates when ready. Turn off to time them yourself.", "auto_ultimates", true)]))
	list.add_child(_about())
	list.add_child(_data_section())
	list.add_child(_dev_section())
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))


## Shot/testing helper (params.scroll).
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


func _section(title: String, rows: Array) -> Control:
	var p := Kit.panel("glass", 20)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.section_header(title, 30))
	for i in rows.size():
		if i > 0:
			v.add_child(Kit.divider())
		v.add_child(rows[i])
	return p


func _row_head(icon_name: String, title: String, sub: String) -> HBoxContainer:
	var row := Kit.hbox(14)
	row.custom_minimum_size.y = 88
	var ic := Kit.icon(icon_name, 48)
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := Kit.vbox(0)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Kit.label(title, 28, Kit.INK, "extrabold"))
	if sub != "":
		var s := Kit.body(sub, 21, Kit.INK_DIM)
		tv.add_child(s)
	row.add_child(tv)
	return row


func _toggle_row(icon_name: String, title: String, sub: String, key: String, default_on: bool) -> Control:
	var row := _row_head(icon_name, title, sub)
	var v: Variant = Game.setting(key)
	var on: bool = default_on if v == null else bool(v)
	var t := Kit.toggle(on, func(val: bool) -> void:
		Game.set_setting(key, val)
		if key == "sound" and val:
			UI.sfx("tap")
		if key == "haptics" and val:
			UI.haptic(30))
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(t)
	return row


func _speed_row() -> Control:
	var v := Kit.vbox(10)
	v.add_child(_row_head("speed", "Default battle speed", "Battles start at this speed. You can still change it mid-fight."))
	var cur := int(Game.setting("battle_speed")) if Game.setting("battle_speed") != null else 1
	var opts: Array = []
	for s in SPEEDS:
		opts.append("%dx" % s)
	var seg := Kit.segmented(opts, maxi(0, SPEEDS.find(cur)), func(i: int) -> void:
		Game.set_setting("battle_speed", SPEEDS[i]), 80)
	v.add_child(seg)
	return v


func _about() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(12)
	p.add_child(v)
	v.add_child(Kit.section_header("About", 30))
	var t := Kit.title("Halo & Horn", 48)
	v.add_child(t)
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var vl := Kit.label("Version %s" % ver, 24, Kit.GOLD_LIGHT, "extrabold")
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(vl)
	v.add_child(Kit.divider())
	var credits: Array[Array] = [
		["Fonts", "Marcellus SC by Astigmatic and Nunito by Vernon Adams, Cyreal and Jacques Le Bailly. Both under the SIL Open Font License 1.1."],
		["Engine", "Made with the Godot Engine (MIT license)."],
		["Sound and music", "Synthesized for this game."],
		["Art", "Original characters and UI art made for Halo & Horn."],
	]
	for c in credits:
		var cv := Kit.vbox(2)
		cv.add_child(Kit.label(str(c[0]), 23, Kit.GOLD_LIGHT, "extrabold"))
		cv.add_child(Kit.body(str(c[1]), 22, Kit.INK))
		v.add_child(cv)
	return p


func _data_section() -> Control:
	var p := Kit.panel("glass", 22)
	var v := Kit.vbox(12)
	p.add_child(v)
	v.add_child(Kit.section_header("Save Data", 30))
	var info := Kit.body("Your progress is saved on this device automatically. Resetting deletes every hero, item and currency and starts a new game.", 22, Kit.INK_DIM)
	v.add_child(info)
	var b := Kit.danger_button("Reset Save", _confirm_reset, "refresh")
	v.add_child(b)
	return p


func _confirm_reset() -> void:
	UI.confirm("Delete all progress and start over? This can't be undone.", func() -> void:
		Game.reset_save()
		UI.toast("Save reset. A new journey begins.", "good")
		UI.go("home"), Callable(), "Reset", "Cancel", true)


func _dev_section() -> Control:
	var p := Kit.panel("inset", 22)
	var v := Kit.vbox(12)
	p.add_child(v)
	v.add_child(Kit.section_header("Dev Tools", 30, Kit.SKY))
	var note := Kit.body("For testing this prototype build.", 22, Kit.INK_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	var g := Kit.grid(2, 14)
	for grant in DEV_GRANTS:
		var cur := str(grant[0])
		var amt := int(grant[1])
		var text := str(grant[2])
		var b := Kit.secondary_button(text, func() -> void:
			Game.dev_add(cur, amt)
			UI.toast("%s added" % text.trim_prefix("+"), "good"), cur)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 26)
		g.add_child(b)
	var skip := Kit.secondary_button("Skip 8 hours", func() -> void:
		Game.dev_skip_time(SKIP_MS)
		UI.toast("8 hours passed. Idle rewards are waiting.", "good"), "skip")
	skip.size_flags_horizontal = SIZE_EXPAND_FILL
	skip.add_theme_font_size_override("font_size", 26)
	g.add_child(skip)
	v.add_child(g)
	return p
