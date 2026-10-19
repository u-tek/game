extends Control
## Screen "settings" (from the top-bar Menu), style v2: a dark header with Back and the
## SETTINGS tab, then white panels on a light page, each under a dark header bar: SOUND
## (effects, music, vibration), BATTLE (default speed, auto ultimates), ADULT CONTENT (Toggle
## nudity, with an 18+ confirm and a big "NUDITY MODE ENABLED / DISABLED" notice), SAVE DATA (Reset Save
## asks first), DEV TOOLS (+3,000 gems, +100K gold, +50K hero EXP, skip 8 hours) and ABOUT
## (version and credits with the font licenses).

const DEV_GRANTS: Array[Array] = [
	["gems", 3000, "+3,000 Gems"],
	["gold", 100000, "+100K Gold"],
	["hero_exp", 50000, "+50K Hero EXP"],
]
const SKIP_MS := 8 * 3600000
const SPEEDS: Array[int] = [1, 2, 4]

var _scroll: ScrollContainer


func setup(params: Dictionary) -> void:
	var head := Kit.hbox(10)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Settings", "icon": "settings"}], 0, Callable(), 240.0))
	head.add_child(Kit.spacer(0, 0, true))
	var back := Kit.icon_button("back", func() -> void: UI.back(), Kit.BUTTON_H, "round")
	back.name = "Back"
	head.add_child(back)
	add_child(head)

	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)

	var list := Kit.vbox(16)
	var m := Kit.margin(list, 16, 0)
	m.add_theme_constant_override("margin_top", 16)
	m.add_theme_constant_override("margin_bottom", 30)
	_scroll = Kit.scroll(m)
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_scroll.offset_top = 10 + Kit.BUTTON_H
	add_child(_scroll)

	list.add_child(_section("Sound", "sound_on", [
		_toggle_row("sound_on", "Sound effects", "Taps, rewards, battle hits", "sound", true),
		_toggle_row("music", "Music", "The lobby theme", "music", true),
		_toggle_row("vibrate", "Vibration", "Haptics on phones", "haptics", true),
	]))
	list.add_child(_section("Battle", "sword", [
		_speed_row(),
		_toggle_row("auto", "Auto ultimates", "Heroes fire ultimates when ready. Turn off to time them yourself.", "auto_ultimates", true),
	]))
	list.add_child(_section("Adult content", "eye_off", [_nudity_row()]))
	list.add_child(_data_section())
	list.add_child(_dev_section())
	list.add_child(_about())
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))
	if params.has("notice"):        # shot/testing helper: show the nudity notice (true = enabled)
		_nudity_notice.call_deferred(bool(params["notice"]))


## Shot/testing helper (params.scroll).
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


## A white panel under a dark header bar, its rows on alternating white / grey strips.
func _section(title: String, icon_name: String, rows: Array) -> Control:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(6)
	p.add_child(v)
	v.add_child(Kit.header_bar(title, null, icon_name))
	for i in rows.size():
		var rp := Kit.panel("row" if i % 2 == 0 else "light_inset", 0)
		rp.add_child(Kit.margin(rows[i], 12, 4))
		v.add_child(rp)
	return p


func _row_head(icon_name: String, title: String, sub: String) -> HBoxContainer:
	var row := Kit.hbox(14)
	row.custom_minimum_size.y = Kit.BUTTON_H
	var ic := Kit.icon(icon_name, 40, Kit.TEXT)
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := Kit.vbox(0)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Kit.label(title, 26, Kit.TEXT, "extrabold"))
	if sub != "":
		tv.add_child(Kit.body(sub, 20, Kit.TEXT_DIM))
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
	t.name = "Toggle_" + key
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(t)
	return row


## "Toggle nudity": every hero (base look and skins) shows her nude art where it is installed.
## Turning it on asks for an 18+ confirmation; cancelling leaves it off. Either way a big notice
## says what happened ("NUDITY MODE ENABLED" / "DISABLED") and the row shows the state; the art on
## screen follows at once (Game.changed: the top-bar avatar, cards and sprites key on
## HeroArt.art_key).
func _nudity_row() -> Control:
	var v := Kit.vbox(4)
	var row := _row_head("eye_off", "Toggle nudity", "Every hero shows her nude art where it is installed (18+ only).")
	v.add_child(row)
	var state := Kit.label("", 20, Kit.TEXT_DIM, "cond_bold")
	state.name = "NudityState"
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(state)
	_show_nudity_state(state)
	var t := Kit.toggle(Game.setting("nudity") == true)
	t.name = "Toggle_nudity"
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	t.toggled.connect(func(val: bool) -> void:
		if not val:
			if Game.setting("nudity") == true:
				_set_nudity(false, state)
			return
		if Game.setting("nudity") == true:
			return
		UI.confirm("Nude art is for adults (18+) only. Show it?",
			func() -> void: _set_nudity(true, state),
			func() -> void: t.set_pressed_no_signal(false),
			"I'm 18+", "Cancel"))
	row.add_child(t)
	return v


func _set_nudity(on: bool, state: Label) -> void:
	Game.set_setting("nudity", on)
	if is_instance_valid(state):
		_show_nudity_state(state)
	_nudity_notice(on)


## "NUDITY MODE ON" in the accent color, plus how much nude art the build has (skins with adult
## art, heroes with an adult base look), so it is clear what the mode covers.
func _show_nudity_state(state: Label) -> void:
	var on: bool = Game.setting("nudity") == true
	var skins := 0
	for s: Dictionary in SkinData.all():
		if HeroArt.has_adult_art(str(s["hero"]), str(s["id"])):
			skins += 1
	var bases := 0
	var ids := HeroData.ids()
	for id in ids:
		if HeroArt.has_adult_art(str(id)):
			bases += 1
	state.text = "%s  ·  NUDE ART: %d SKINS, %d OF %d BASE LOOKS" % [
		"NUDITY MODE ON" if on else "NUDITY MODE OFF", skins, bases, ids.size()]
	state.add_theme_color_override("font_color", Kit.EMBER if on else Kit.TEXT_DIM)


## A big notice over everything for a moment (it never blocks taps and outlives a screen change):
## the ribbon "NUDITY MODE ENABLED" / "NUDITY MODE DISABLED" and a line under it.
func _nudity_notice(on: bool) -> void:
	var host: Control = UI.root if UI.root and is_instance_valid(UI.root) else self
	var old := host.get_node_or_null("NudityNotice")
	if old:
		host.remove_child(old)
		old.queue_free()
	var n := Control.new()
	n.name = "NudityNotice"
	n.set_meta("on", on)
	n.mouse_filter = MOUSE_FILTER_IGNORE
	n.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	n.z_index = 50
	var dim := ColorRect.new()
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	dim.color = Color(0.02, 0.03, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	n.add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	n.add_child(center)
	var col := Kit.vbox(14)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var ic := Kit.hex_badge("check" if on else "eye_off", 96, Kit.EMBER if on else Color("1b2a47"), Color.WHITE)
	ic.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(ic)
	var title := "NUDITY MODE ENABLED" if on else "NUDITY MODE DISABLED"
	var rb := Kit.ribbon(title, 660.0, Kit.EMBER if on else Kit.ACCENT_DEEP, Color.WHITE, 46)
	rb.name = "Title"
	rb.set_meta("text", title)
	col.add_child(rb)
	var sub := Kit.label("Every hero now shows her nude art wherever it is installed." if on
		else "Every hero is back in her normal art.", 26, Color.WHITE, "bold", 6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 600
	col.add_child(sub)
	host.add_child(n)
	n.modulate.a = 0.0
	col.pivot_offset = col.get_combined_minimum_size() * 0.5
	col.scale = Vector2(0.8, 0.8)
	var tw := n.create_tween()
	tw.tween_property(n, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(col, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_property(n, "modulate:a", 0.0, 0.4)
	tw.tween_callback(n.queue_free)
	UI.sfx("reward" if on else "tap")
	UI.haptic(40)


func _speed_row() -> Control:
	var v := Kit.vbox(6)
	v.add_child(_row_head("speed", "Default battle speed", "Battles start at this speed. You can still change it mid-fight."))
	var cur := int(Game.setting("battle_speed")) if Game.setting("battle_speed") != null else 1
	var opts: Array = []
	for s in SPEEDS:
		opts.append("%dx" % s)
	var seg := Kit.segmented(opts, maxi(0, SPEEDS.find(cur)), func(i: int) -> void:
		Game.set_setting("battle_speed", SPEEDS[i]), Kit.BUTTON_H)
	v.add_child(seg)
	v.add_child(Kit.spacer(0, 6))
	return v


func _data_section() -> Control:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.header_bar("Save Data", null, "lock"))
	var info := Kit.body("Your progress is saved on this device automatically. Resetting deletes every hero, item and currency and starts a new game.", 21, Kit.TEXT_DIM)
	v.add_child(Kit.margin(info, 8, 2))
	var b := Kit.danger_button("Reset Save", _confirm_reset, "refresh")
	b.name = "ResetSave"
	v.add_child(b)
	return p


func _confirm_reset() -> void:
	UI.confirm("Delete all progress and start over? This can't be undone.", func() -> void:
		Game.reset_save()
		UI.toast("Save reset. A new journey begins.", "good")
		UI.go("home"), Callable(), "Reset", "Cancel", true)


func _dev_section() -> Control:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.header_bar("Dev Tools", Kit.tag("TEST BUILD", Kit.ORANGE, Color.WHITE, 16), "settings"))
	var note := Kit.label("For testing this prototype build.", 20, Kit.TEXT_DIM, "bold")
	v.add_child(Kit.margin(note, 8, 0))
	var g := Kit.grid(2, 10)
	for grant in DEV_GRANTS:
		var cur := str(grant[0])
		var amt := int(grant[1])
		var text := str(grant[2])
		var b := Kit.light_button(text, func() -> void:
			Game.dev_add(cur, amt)
			UI.toast("%s added" % text.trim_prefix("+"), "good"))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 24)
		g.add_child(b)
	var skip := Kit.light_button("Skip 8 hours", func() -> void:
		Game.dev_skip_time(SKIP_MS)
		UI.toast("8 hours passed. The Sanctum is filling.", "good"), "skip")
	skip.size_flags_horizontal = SIZE_EXPAND_FILL
	skip.add_theme_font_size_override("font_size", 24)
	g.add_child(skip)
	v.add_child(g)
	return p


func _about() -> Control:
	var p := Kit.info_panel(10)
	var v := Kit.vbox(10)
	p.add_child(v)
	v.add_child(Kit.header_bar("About", null, "info"))
	var t := Kit.label("HALO & HORN", 48, Kit.TEXT, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var vl := Kit.label("VERSION %s" % ver, 20, Kit.ACCENT_DEEP, "cond_bold")
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(vl)
	v.add_child(Kit.divider(0, true))
	var credits: Array[Array] = [
		["Fonts", "Barlow and Barlow Condensed by Jeremy Tribby, under the SIL Open Font License 1.1."],
		["Engine", "Made with the Godot Engine (MIT license)."],
		["Sound and music", "Synthesized for this game."],
		["Art", "Original characters and UI art made for Halo & Horn."],
	]
	for c in credits:
		var cv := Kit.vbox(0)
		cv.add_child(Kit.label(str(c[0]).to_upper(), 18, Kit.TEXT, "cond_bold"))
		cv.add_child(Kit.body(str(c[1]), 20, Kit.TEXT_DIM))
		v.add_child(Kit.margin(cv, 8, 0))
	return p
