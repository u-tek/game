extends Control
## Screen "settings" (from the top-bar Menu), style v4 "Signal" in the poster house style
## (docs/dev/ui-style-v4.md: section 0, and section 3 "Settings: one device panel, switches, serial
## codes" drawn as print). One long printed control sheet on the paper matte:
## - a masthead: a dark band with a red halftone ramp and vertical serials, SETTINGS set huge in
##   compressed type across it (paper-white on the band, ink on the paper), the device serial and
##   firmware line, a printed "← BACK", and a stamp on a silver disc;
## - numbered channels, each a big index numeral, a mono title and a ruled line, its rows split by
##   hairlines: 01 SOUND (effects, music, vibration), 02 DISPLAY (Reduce motion: no slides, sweeps
##   or bounces; stored as the "reduce_motion" setting, read by Kit.motion_ok), 03 BATTLE (default
##   speed as printed segments, auto ultimates), 04 ADULT CONTENT (Toggle nudity, with an 18+
##   confirm and a big "NUDITY MODE ENABLED / DISABLED" notice), 05 SAVE DATA (Reset Save asks
##   first), 06 DEV TOOLS (+3,000 gems, +100K gold, +50K hero EXP, skip 8 hours) and 07 ABOUT
##   (version and credits with the font licenses);
## - switches are printed toggles (Kit.toggle: ON / OFF in an ink-ruled box, a signal status light);
## - a footer with a barcode, a matrix code, the date and the signature; still grain over it all.

const DeviceTier := preload("res://src/art/device_tier.gd")
const DEV_GRANTS: Array[Array] = [
	["gems", 3000, "+3,000 Gems"],
	["gold", 100000, "+100K Gold"],
	["hero_exp", 50000, "+50K Hero EXP"],
]
const SKIP_MS := 8 * 3600000
const SPEEDS: Array[int] = [1, 2, 4]
const INK := SignalKit.INK
const SIG := SignalKit.SIGNAL
const PAPER := SignalKit.PAPER
const BAND := Color("141517")
const BAND_W := 150.0
const MAST_H := 318.0

var _scroll: ScrollContainer
var _channel := 0


func setup(params: Dictionary) -> void:
	var matte := ColorRect.new()
	matte.name = "Matte"
	matte.color = SignalKit.MATTE
	matte.mouse_filter = MOUSE_FILTER_IGNORE
	matte.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(matte)
	var w := (size.x if size.x > 0.0 else get_viewport_rect().size.x) - 32.0

	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	# A PanelContainer stops touches by default: let drags through to the scroll (phones scroll by drag).
	sheet.mouse_filter = MOUSE_FILTER_PASS
	sheet.add_theme_stylebox_override("panel", Kit.style("white", 0))
	sheet.custom_minimum_size.x = w
	var col := Kit.vbox(0)
	sheet.add_child(col)
	col.add_child(_masthead(w))
	var body := Kit.vbox(30)
	body.add_child(Kit.spacer(0, 8))
	body.add_child(_section("Sound", [
		_toggle_row("sound_on", "Sound effects", "Taps, rewards, battle hits", "sound", true),
		_toggle_row("music", "Music", "The lobby theme", "music", true),
		_toggle_row("vibrate", "Vibration", "Haptics on phones", "haptics", true),
	]))
	var display: Array = [_toggle_row("refresh", "Reduce motion", "Calmer screens: no slides, sweeps or bounces.", "reduce_motion", false)]
	if DeviceTier.pro():
		# iPhone 15 Pro and newer: the heroines relit live from the phone's tilt, their shadows on the paper.
		display.append(_toggle_row("power", "Live Light", "Your phone lights the heroines as you tilt it and casts their shadows on the page.", "live_light", true))
	body.add_child(_section("Display", display))
	body.add_child(_section("Battle", [
		_speed_row(),
		_toggle_row("auto", "Auto ultimates", "Heroes fire ultimates when ready. Turn off to time them yourself.", "auto_ultimates", true),
	]))
	body.add_child(_section("Adult content", [_nudity_row()]))
	body.add_child(_data_section())
	body.add_child(_dev_section())
	body.add_child(_about())
	body.add_child(_footer(w - 56.0))
	var bm := Kit.margin(body, 28, 0)
	bm.add_theme_constant_override("margin_bottom", 26)
	col.add_child(bm)

	var m := Kit.margin(sheet, 16, 0)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 34)
	_scroll = Kit.scroll(m)
	_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_scroll)
	add_child(SignalKit.grain(0.05, true))
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


# ------------------------------------------------------------------ masthead

## The top of the sheet: the band with the halftone ramp, SETTINGS huge across it (two-tone), the
## device serials, the printed Back and a stamp on a silver disc.
func _masthead(w: float) -> Control:
	var mh := Control.new()
	mh.name = "Masthead"
	mh.mouse_filter = MOUSE_FILTER_IGNORE
	mh.clip_contents = true
	mh.custom_minimum_size = Vector2(w, MAST_H)
	var band := ColorRect.new()
	band.color = BAND
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.size = Vector2(BAND_W, MAST_H)
	mh.add_child(band)
	var ramp := Kit.halftone_ramp(Vector2(BAND_W, MAST_H * 0.62), Kit.PRINT_RED, 7.0, "down")
	ramp.position = Vector2(0, MAST_H * 0.38)
	mh.add_child(ramp)
	var mark := Kit.label("HH", 30, PAPER, "wide_black")
	mark.position = Vector2(18, 104)
	mh.add_child(mark)
	var tm := Kit.label("™", 11, PAPER, "mono")
	tm.position = Vector2(74, 106)
	mh.add_child(tm)
	var vs := Kit.label("CONTROL SHEET  ·  HH-0451  ·  ©2026 HH", 10, Color(PAPER, 0.8), "mono_bold")
	vs.rotation = PI * 0.5
	vs.position = Vector2(BAND_W - 14, 70)
	mh.add_child(vs)
	# SETTINGS, huge, cut by the right edge; paper-white where it crosses the band.
	var word := "SETTINGS"
	var f := Kit.font("compressed")
	var fs := 120
	while fs < 260 and f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 4).x < (w - 34.0) * 1.05:
		fs += 4
	for side: Array in [[0.0, BAND_W, PAPER], [BAND_W, w - BAND_W, INK]]:
		var clip := Control.new()
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.position = Vector2(float(side[0]), 0)
		clip.size = Vector2(float(side[1]), MAST_H)
		mh.add_child(clip)
		var l := Kit.label(word, fs, side[2], "compressed")
		l.position = Vector2(32.0 - float(side[0]), 50.0)
		clip.add_child(l)
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var info := Kit.vbox(2)
	info.mouse_filter = MOUSE_FILTER_IGNORE
	info.position = Vector2(BAND_W + 22, MAST_H - 76)
	info.add_child(Kit.print_label("Device No.HH-0451  ·  firmware v%s" % ver, 12))
	info.add_child(Kit.print_label("Seven channels  ·  saved on this device", 12, Color(INK, 0.6), "mono"))
	mh.add_child(info)
	# The shared big Back, printed for the dark band.
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	mh.add_child(back)
	var disc := SignalKit.plate("silver", Vector2(w - 142, MAST_H - 132), Vector2(112, 112), {"circle": true, "shadow": 0.5}, mh)
	disc.add_child(SignalKit.stamp("DEVICE · HALO & HORN · ", "v%s" % ver.get_slice(".", 0) + "." + ver.get_slice(".", 1), 112))
	disc.pivot_offset = Vector2(56, 56)
	disc.rotation = -0.14
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.55)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	rule.position = Vector2(0, MAST_H - 1)
	rule.size = Vector2(w, 1)
	mh.add_child(rule)
	return mh


# ------------------------------------------------------------------ channels

## A numbered channel: the big index numeral, the mono title over a ruled line, then its rows split
## by hairlines.
func _section(title: String, rows: Array) -> Control:
	_channel += 1
	var v := Kit.vbox(0)
	var head := Kit.hbox(14)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(Kit.label("%02d" % _channel, 58, INK, "compressed"))
	var tcol := Kit.vbox(2)
	tcol.mouse_filter = MOUSE_FILTER_IGNORE
	tcol.size_flags_horizontal = SIZE_EXPAND_FILL
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	var tr := Kit.hbox(8)
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	var tl := Kit.print_label(title, 16)
	tl.size_flags_horizontal = SIZE_EXPAND_FILL
	tr.add_child(tl)
	tr.add_child(Kit.print_label("CH.%02d / 07" % _channel, 10, Color(INK, 0.55), "mono"))
	tcol.add_child(tr)
	var rule := Kit.tick_rule(0.0, Color(INK, 0.55), {"lead": SIG if _channel == 1 else Color(0, 0, 0, 0)})
	rule.size_flags_horizontal = SIZE_EXPAND_FILL
	tcol.add_child(rule)
	head.add_child(tcol)
	v.add_child(head)
	for i in rows.size():
		v.add_child(rows[i])
		if i < rows.size() - 1:
			v.add_child(_hair())
	return v


func _hair() -> Control:
	var r := ColorRect.new()
	r.color = Color(INK, 0.15)
	r.mouse_filter = MOUSE_FILTER_IGNORE
	r.custom_minimum_size.y = 1
	return r


func _row_head(icon_name: String, title: String, sub: String) -> HBoxContainer:
	var row := Kit.hbox(16)
	row.custom_minimum_size.y = 96
	var ic := Kit.icon(icon_name, 32, Color(INK, 0.8))
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv := Kit.vbox(2)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Kit.label(title, 28, INK, "cond_black"))
	if sub != "":
		var s := Kit.label(sub, 19, Color(INK, 0.66), "regular")
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 40
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
	var state := Kit.label("", 14, Color(INK, 0.6), "mono_bold")
	state.name = "NudityState"
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.custom_minimum_size.x = 40
	v.add_child(state)
	v.add_child(Kit.spacer(0, 10))
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


## "NUDITY MODE ON" in signal, plus how many heroes have a nude look built, so it is clear what
## the mode covers (it turns skins off: every hero shows her nude look).
func _show_nudity_state(state: Label) -> void:
	var on: bool = Game.setting("nudity") == true
	var bases := 0
	var ids := HeroData.ids()
	for id in ids:
		if HeroArt.has_adult_art(str(id)):
			bases += 1
	state.text = "%s  ·  NUDE LOOKS: %d OF %d HEROES  ·  SKINS OFF" % [
		"NUDITY MODE ON" if on else "NUDITY MODE OFF", bases, ids.size()]
	state.add_theme_color_override("font_color", Kit.ACCENT_DEEP if on else Color(INK, 0.6))


## A big notice over everything for a moment (it never blocks taps and outlives a screen change):
## a printed sheet on the matte with "NUDITY MODE" huge in compressed type and ENABLED (in signal)
## or DISABLED under it, a rule and a line of mono type.
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
	dim.color = Color(SignalKit.MATTE, 0.8)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	n.add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	n.add_child(center)
	var sheet := PanelContainer.new()
	sheet.mouse_filter = MOUSE_FILTER_IGNORE
	sheet.add_theme_stylebox_override("panel", Kit.style("dialog"))
	sheet.custom_minimum_size.x = 620
	center.add_child(sheet)
	var col := Kit.vbox(6)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var cm := Kit.margin(col, 34, 30)
	cm.mouse_filter = MOUSE_FILTER_IGNORE
	sheet.add_child(cm)
	var title := "NUDITY MODE ENABLED" if on else "NUDITY MODE DISABLED"
	col.add_child(Kit.print_label("Notice  ·  adult content  ·  %s" % Kit._print_date(), 12, Color(INK, 0.65)))
	var big := RichTextLabel.new()
	big.name = "Title"
	big.set_meta("text", title)
	big.bbcode_enabled = true
	big.fit_content = true
	big.scroll_active = false
	big.autowrap_mode = TextServer.AUTOWRAP_OFF
	big.mouse_filter = MOUSE_FILTER_IGNORE
	big.custom_minimum_size.x = 552
	big.add_theme_font_override("normal_font", Kit.font("compressed"))
	big.add_theme_font_size_override("normal_font_size", 92)
	big.add_theme_color_override("default_color", INK)
	big.add_theme_constant_override("line_separation", -18)
	big.text = "NUDITY MODE\n[color=#%s]%s[/color]" % [(SIG if on else INK).to_html(false), "ENABLED" if on else "DISABLED"]
	col.add_child(big)
	col.add_child(Kit.tick_rule(552.0, Color(INK, 0.55), {"lead": SIG}))
	var sub := Kit.label("Every hero now shows her nude art wherever it is installed." if on
		else "Every hero is back in her normal art.", 30, Color(INK, 0.8), "serif_italic")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 552
	col.add_child(sub)
	host.add_child(n)
	n.modulate.a = 0.0
	sheet.pivot_offset = sheet.get_combined_minimum_size() * 0.5
	sheet.scale = Vector2(0.86, 0.86)
	sheet.rotation = -0.02
	var tw := n.create_tween()
	tw.tween_property(n, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(sheet, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	v.add_child(Kit.spacer(0, 16))
	return v


func _data_section() -> Control:
	var v := Kit.vbox(14)
	var info := Kit.label("Your progress is saved on this device automatically. Resetting deletes every hero, item and currency and starts a new game.",
		21, Color(INK, 0.72), "regular")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 40
	v.add_child(info)
	var b := Kit.danger_button("Reset Save", _confirm_reset, "refresh")
	b.name = "ResetSave"
	v.add_child(b)
	# The intake form again (your name and signature can be redone; nothing else changes).
	var rp := Kit.light_button("Replay the opening", func() -> void:
		Game.reset_intake()
		UI.go("calling"), "refresh")
	rp.name = "ReplayOpening"
	v.add_child(rp)
	return _section("Save data", [v])


func _confirm_reset() -> void:
	UI.confirm("Delete all progress and start over? This can't be undone.", func() -> void:
		Game.reset_save()
		UI.go("calling"), Callable(), "Reset", "Cancel", true)


func _dev_section() -> Control:
	var v := Kit.vbox(14)
	var top := Kit.hbox(12)
	var note := Kit.print_label("For testing this prototype build", 12, Color(INK, 0.65), "mono")
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(note)
	top.add_child(_rubber("TEST BUILD"))
	v.add_child(top)
	var g := Kit.grid(2, 12)
	for grant in DEV_GRANTS:
		var cur := str(grant[0])
		var amt := int(grant[1])
		var text := str(grant[2])
		var b := Kit.light_button(text, func() -> void:
			Game.dev_add(cur, amt)
			UI.toast("%s added" % text.trim_prefix("+"), "good"))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 26)
		g.add_child(b)
	var skip := Kit.light_button("Skip 8 hours", func() -> void:
		Game.dev_skip_time(SKIP_MS)
		UI.toast("8 hours passed. The Sanctum is filling.", "good"), "skip")
	skip.size_flags_horizontal = SIZE_EXPAND_FILL
	skip.add_theme_font_size_override("font_size", 26)
	g.add_child(skip)
	v.add_child(g)
	return _section("Dev tools", [v])


## A rubber-stamp word: outlined in signal, turned a little.
func _rubber(text: String) -> Control:
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(SIG, 0.9)
	sb.set_border_width_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(Kit.label(text, 16, Color(SIG, 0.95), "wide_black"))
	holder.add_child(p)
	holder.custom_minimum_size = p.get_combined_minimum_size() + Vector2(6, 8)
	p.position = Vector2(2, 4)
	p.rotation = -0.06
	return holder


func _about() -> Control:
	var v := Kit.vbox(12)
	var wm := Kit.hbox(10)
	wm.mouse_filter = MOUSE_FILTER_IGNORE
	wm.add_child(Kit.label("HALO", 52, INK, "wide_black"))
	wm.add_child(Kit.label("&", 52, SIG, "wide_black"))
	wm.add_child(Kit.label("HORN", 52, INK, "wide_black"))
	v.add_child(wm)
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	v.add_child(Kit.print_label("Version %s  ·  angels  ·  demons  ·  the fallen" % ver, 13))
	v.add_child(Kit.divider(0, true))
	var credits: Array[Array] = [
		["Fonts", "Archivo (the Archivo Project Authors), JetBrains Mono (the JetBrains Mono Project Authors) and Instrument Serif (the Instrument Serif Project Authors), all under the SIL Open Font License 1.1."],
		["Engine", "Made with the Godot Engine (MIT license)."],
		["Sound and music", "Synthesized for this game."],
		["Art", "Original characters and UI art made for Halo & Horn."],
	]
	for c in credits:
		var cv := Kit.vbox(2)
		cv.add_child(Kit.print_label(str(c[0]), 12))
		var bl := Kit.label(str(c[1]), 20, Color(INK, 0.72), "regular")
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size.x = 40
		cv.add_child(bl)
		v.add_child(cv)
	return _section("About", [v])


## The foot of the sheet: a barcode and a matrix code, the date and the signature.
func _footer(w: float) -> Control:
	var f := Control.new()
	f.mouse_filter = MOUSE_FILTER_IGNORE
	f.custom_minimum_size = Vector2(w, 128)
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.55)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	rule.size = Vector2(w, 1)
	f.add_child(rule)
	var code := SignalKit.matrix(Vector2(63, 63))
	code.position = Vector2(0, 22)
	f.add_child(code)
	var bc := SignalKit.barcode(Vector2(150, 30), INK, 451)
	bc.position = Vector2(80, 24)
	f.add_child(bc)
	var d := Time.get_date_dict_from_system()
	var date := Kit.label("%d %02d/%02d" % [int(d.year), int(d.month), int(d.day)], 22, INK, "regular")
	date.position = Vector2(80, 58)
	f.add_child(date)
	var sig := Kit.label("Halo & Horn", 46, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 60)
	sig.position = Vector2(w - 300, 26)
	f.add_child(sig)
	var swash := ColorRect.new()
	swash.color = INK
	swash.mouse_filter = MOUSE_FILTER_IGNORE
	swash.position = Vector2(w - 220, 88)
	swash.size = Vector2(200, 2)
	swash.rotation = -0.06
	f.add_child(swash)
	return f
