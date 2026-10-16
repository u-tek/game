extends Node
## Autoload "UI": navigation, feedback and modals every screen uses.
## Contract: docs/dev/architecture.md section 5.
##
##   UI.go("hero_detail", {"hero_id": "seraphiel"})  # navigate (0.15 s fade, history kept)
##   UI.back()                                       # previous screen (or home)
##   UI.toast("Not enough gold")                     # stacked message, top center
##   UI.show_reward("Stage cleared!", reward, on_closed)  # reward popup (queued)
##   UI.confirm("Spend 300 gems?", on_yes)           # in-game yes/no dialog
##   UI.set_chrome(show_top_bar, show_nav)           # reset to (true, true) on every go()
##   UI.safe_top() / UI.safe_bottom()                # notch / home-indicator insets (px)
##   UI.sfx("tap")                                   # tap reward summon legendary hit ult victory defeat
##   UI.haptic(20)                                   # short vibration on phones
## Background music plays by itself and follows Game.setting("music").
## Extras: UI.popup(title, content) for custom dialogs, UI.modal(content) / close_modal(m),
## signal screen_changed(name), UI.current_name, UI.history.
##
## Screens fill the content area between the top bar and the bottom nav. A screen that hides
## the chrome (battle, summon) fills the whole window and should keep its own controls
## inside UI.safe_top() / UI.safe_bottom(). A screen that calls UI.set_full_bleed(true)
## (the lobby) also fills the whole window but keeps the chrome, which turns translucent
## over its art; it keeps its own controls inside content_top() / content_bottom().
## Style v2 (docs/dev/ui-style-v2.md): bottom nav Heroes, Team, Lobby (home), Gear, Summon.

const Sfx := preload("res://src/ui/components/sfx.gd")

signal screen_changed(screen_name: String)

const SCREENS := {
	"home": "res://src/ui/screens/home_screen.gd",
	"campaign": "res://src/ui/screens/campaign_screen.gd",
	"battle": "res://src/ui/screens/battle_screen.gd",
	"heroes": "res://src/ui/screens/heroes_screen.gd",
	"hero_detail": "res://src/ui/screens/hero_detail_screen.gd",
	"formation": "res://src/ui/screens/formation_screen.gd",
	"summon": "res://src/ui/screens/summon_screen.gd",
	"quests": "res://src/ui/screens/quests_screen.gd",
	"shop": "res://src/ui/screens/shop_screen.gd",
	"settings": "res://src/ui/screens/settings_screen.gd",
	"gear": "res://src/ui/screens/gear_screen.gd",
	# Widget gallery for UI work (debug builds only; not in the nav).
	"kit_demo": "res://src/ui/components/kit_demo.gd",
}

## Bottom-nav tabs, left to right (the centre one, "home", is the Lobby).
const NAV_TABS: Array[String] = ["heroes", "formation", "home", "gear", "summon"]
## Going to one of these resets the history (back returns home).
const NAV_ROOTS: Array[String] = ["heroes", "formation", "home", "gear", "summon", "quests", "shop"]
## Which nav tab is highlighted for non-tab screens.
const NAV_PARENT := {"campaign": "home", "battle": "home", "hero_detail": "heroes", "kit_demo": "home",
	"quests": "home", "shop": "home", "settings": "home"}
## Currencies shown in the top-bar resource pill per screen (default: gems, gold).
const TOP_CURRENCIES := {"summon": ["gems", "scrolls"], "heroes": ["gold", "hero_exp"],
	"hero_detail": ["gold", "hero_exp"], "gear": ["gold", "dust"]}
## Screens never kept in history (back from the next screen skips them).
const NO_HISTORY: Array[String] = ["battle"]
const FADE_TIME := 0.15
## Ambient loop (rendered by assets/art/ui/src/make_music.py). Follows Game.setting("music").
const MUSIC_PATH := "res://assets/art/ui/music_twilight.ogg"
const MUSIC_DB := -15.0
const MAX_TOASTS := 3
const SFX_VOLUME_DB := {
	"tap": -9.0, "hit": -6.0, "reward": -5.0, "summon": -4.0, "legendary": -3.0,
	"ult": -5.0, "victory": -4.0, "defeat": -5.0,
}

## App root (main.gd). Screens mount into root.content.
var root: Control
var current_name := ""
var current: Control
var current_params: Dictionary = {}
## Previous screens: [{name, params}], most recent last.
var history: Array[Dictionary] = []
## Safe-area override in viewport px (x = top, y = bottom); negative = use the device.
var safe_override := Vector2(-1, -1)
var chrome_top := true
var chrome_nav := true
## The current screen fills the window under translucent chrome (set_full_bleed).
var full_bleed := false

var _fade: Tween
var _modals: Array[Control] = []
var _reward_queue: Array[Array] = []
var _reward_open := false
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _streams: Dictionary = {}
var _streams_mutex := Mutex.new()
var _gen_task := -1
var _last_played: Dictionary = {}
var _sfx_rng := RandomNumberGenerator.new()
var _music: AudioStreamPlayer
var _music_tw: Tween
var _music_wanted := false
## Set by release_audio() (app is quitting): no sound or music starts again.
var _audio_released := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	# Synthesize all sounds off the main thread (takes a moment in GDScript).
	_gen_task = WorkerThreadPool.add_task(_generate_all_sounds, false, "UI sfx synth")
	_music = AudioStreamPlayer.new()
	_music.bus = &"Master"
	_music.volume_db = -60.0
	add_child(_music)
	if Game.has_signal("changed"):
		Game.changed.connect(_sync_music)
	_sync_music.call_deferred()


func _exit_tree() -> void:
	release_audio()
	if _gen_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


## Called by main.gd once the app root exists.
func attach(app_root: Control) -> void:
	root = app_root


# ------------------------------------------------------------------ navigation

## Navigate to a screen by name with optional params.
func go(screen: String, params: Dictionary = {}) -> void:
	if not SCREENS.has(screen) or (screen == "kit_demo" and not OS.is_debug_build()):
		push_error("UI.go: unknown screen '%s'" % screen)
		toast("That screen doesn't exist yet")
		return
	if screen in NAV_ROOTS:
		history.clear()
		if screen != "home":
			history.append({"name": "home", "params": {}})
	elif current_name != "" and current_name != screen:
		var idx := _history_index(screen)
		if idx >= 0:
			history.resize(idx)
		elif not (current_name in NO_HISTORY):
			history.append({"name": current_name, "params": current_params})
	_show(screen, params)


## Go back to the previous screen (or home).
func back() -> void:
	if history.is_empty():
		if current_name != "home":
			_show("home", {})
		return
	var e: Dictionary = history.pop_back()
	_show(str(e.get("name", "home")), e.get("params", {}))


## Back gesture / Escape: closes the top modal first, then navigates back.
func handle_back() -> void:
	if not _modals.is_empty():
		var m: Control = _modals.back()
		if m.get_meta("dismissable", true):
			_dismiss(m)
		return
	back()


func _history_index(screen: String) -> int:
	for i in history.size():
		if history[i].get("name", "") == screen:
			return i
	return -1


func _content_host() -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var c: Variant = root.get("content")
	return c if c is Control else root


func _show(screen: String, params: Dictionary) -> void:
	var host := _content_host()
	if host == null:
		push_error("UI.go before UI.attach")
		return
	var script: Variant = load(SCREENS[screen])
	if not (script is Script) or not (script as Script).can_instantiate():
		push_error("UI.go: screen '%s' failed to load" % screen)
		toast("Couldn't open %s" % screen.capitalize())
		return
	if current and is_instance_valid(current):
		host.remove_child(current)
		current.queue_free()
	current = null
	full_bleed = false
	set_chrome(true, true)
	var s: Variant = (script as Script).new()
	if not (s is Control):
		push_error("UI.go: screen '%s' is not a Control" % screen)
		if s is Node:
			(s as Node).queue_free()
		return
	var sc := s as Control
	sc.name = screen.to_pascal_case() + "Screen"
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.modulate.a = 0.0
	host.add_child(sc)
	current = sc
	current_name = screen
	current_params = params
	if sc.has_method("setup"):
		sc.setup(params)
	if current != sc:
		return # setup() navigated somewhere else; that call already finished the job
	if _fade and _fade.is_valid():
		_fade.kill()
	if is_instance_valid(sc):
		var y0 := sc.position.y
		sc.position.y = y0 + 12.0
		_fade = sc.create_tween().set_parallel(true)
		_fade.tween_property(sc, "modulate:a", 1.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
		_fade.tween_property(sc, "position:y", y0, FADE_TIME + 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	screen_changed.emit(screen)


## Which bottom-nav tab is highlighted for `screen` ("" = none).
func nav_tab_for(screen: String) -> String:
	if screen in NAV_TABS:
		return screen
	return str(NAV_PARENT.get(screen, ""))


# ------------------------------------------------------------------ chrome & safe area

## Show/hide the top bar (currencies) and bottom nav. Reset to visible on every go().
func set_chrome(show_top_bar: bool, show_nav: bool) -> void:
	chrome_top = show_top_bar
	chrome_nav = show_nav
	if root and is_instance_valid(root) and root.has_method("apply_chrome"):
		root.apply_chrome(show_top_bar, show_nav)


## Lets the current screen fill the whole window under the (translucent) top bar and nav,
## for full-screen art like the lobby. Reset to false on every go(). Keep tappable
## controls between content_top() and content_bottom().
func set_full_bleed(on: bool) -> void:
	full_bleed = on
	if root and is_instance_valid(root) and root.has_method("apply_chrome"):
		root.apply_chrome(chrome_top, chrome_nav)


## Y of the bottom edge of the top bar (window px): where a full-bleed screen's own
## controls may start. Equals safe_top() when the top bar is hidden.
func content_top() -> float:
	var h := _bar_heights()
	return safe_top() + (h.x if chrome_top else 0.0)


## Height from the window bottom to the top edge of the nav (window px).
func content_bottom() -> float:
	var h := _bar_heights()
	return safe_bottom() + (h.y if chrome_nav else 0.0)


func _bar_heights() -> Vector2:
	if root and is_instance_valid(root) and root.has_method("bar_heights"):
		return root.call("bar_heights")
	return Vector2.ZERO


## Top inset (notch / status bar) in viewport px.
func safe_top() -> float:
	if safe_override.x >= 0.0:
		return safe_override.x
	return _device_insets().x


## Bottom inset (home indicator) in viewport px.
func safe_bottom() -> float:
	if safe_override.y >= 0.0:
		return safe_override.y
	return _device_insets().y


func _device_insets() -> Vector2:
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var visible := vp.get_visible_rect().size
	var win_size := DisplayServer.window_get_size()
	if visible.y <= 0.0 or win_size.y <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var win_pos := DisplayServer.window_get_position()
	var k := float(win_size.y) / visible.y
	var top := maxf(0.0, float(safe.position.y - win_pos.y)) / k
	var bottom := maxf(0.0, float((win_pos.y + win_size.y) - safe.end.y)) / k
	return Vector2(top, bottom)


# ------------------------------------------------------------------ toasts

## Short message at the top of the screen. kind: "info" | "good" | "bad" (icon + accent).
## Style v2: a dark glass bar with a colored left edge, white text.
func toast(text: String, kind: String = "info") -> void:
	var box: Variant = root.get("toast_box") if root and is_instance_valid(root) else null
	if not (box is Container):
		print("[toast] ", text)
		return
	var host := box as Container
	while host.get_child_count() >= MAX_TOASTS:
		var old := host.get_child(0)
		host.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	p.theme_type_variation = &"ToastPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var accent: Color = {"good": Kit.GOOD, "bad": Kit.EMBER}.get(kind, Kit.ACCENT)
	var sb := UITheme.style("toast")
	sb.set("accent_color", accent)
	p.add_theme_stylebox_override("panel", sb)
	var row := Kit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic: String = {"good": "check", "bad": "info"}.get(kind, "")
	if ic != "":
		row.add_child(Kit.icon(ic, 32, accent.lightened(0.2)))
	var l := Kit.label(text, Kit.SIZE_BODY, Color.WHITE, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := Kit.font("bold")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Kit.SIZE_BODY).x
	l.custom_minimum_size.x = minf(w + 4.0, 560.0)
	row.add_child(l)
	p.add_child(row)
	host.add_child(p)
	p.modulate.a = 0.0
	p.position.y -= 8.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ modals

## Opens `content` as a modal over everything (dim backdrop, centered, pop-in).
## dismissable: tapping the backdrop or Back closes it (calls on_closed).
## Returns the modal root; close it with close_modal(m).
func modal(content: Control, dismissable: bool = true, on_closed: Callable = Callable()) -> Control:
	var layer := _modal_layer()
	if layer == null:
		push_warning("UI.modal before UI.attach")
		return null
	var m := Control.new()
	m.name = "Modal"
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.set_meta("dismissable", dismissable)
	m.set_meta("on_closed", on_closed)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if dismissable and mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_dismiss(m))
	m.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.offset_top = safe_top()
	holder.offset_bottom = -safe_bottom()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(holder)
	holder.add_child(content)
	layer.add_child(m)
	_modals.append(m)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.18)
	content.pivot_offset = content.get_combined_minimum_size() * 0.5
	content.scale = Vector2(0.86, 0.86)
	content.modulate.a = 0.0
	var tw := content.create_tween().set_parallel(true)
	tw.tween_property(content, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(content, "modulate:a", 1.0, 0.14)
	content.resized.connect(func() -> void: content.pivot_offset = content.size * 0.5)
	return m


## Closes a modal opened with modal()/popup() without calling its on_closed.
func close_modal(m: Control) -> void:
	if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
		return
	_modals.erase(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in m.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := m.create_tween()
	tw.tween_property(m, "modulate:a", 0.0, 0.12)
	tw.tween_callback(m.queue_free)


func _dismiss(m: Control) -> void:
	if not is_instance_valid(m) or not _modals.has(m):
		return
	var cb: Variant = m.get_meta("on_closed", Callable())
	close_modal(m)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


## Standard dialog (Kit.dialog): blue header with the title and a close X, your content
## in the body. light = true gives the white v2 body (build content with Kit.TEXT colors);
## the default graphite body suits content built with light text (Kit.INK).
## Returns the modal root (close with close_modal).
func popup(title: String, content: Control, on_closed: Callable = Callable(), width: float = 640.0, light: bool = false) -> Control:
	var panel := Kit.dialog(title, content, width, light)
	var m_ref: Array[Control] = []
	var close := panel.get_meta("close_button") as Button
	Kit._connect_pressed(close, func() -> void:
		if not m_ref.is_empty():
			_dismiss(m_ref[0]))
	var m := modal(panel, true, on_closed)
	m_ref.append(m)
	return m


## In-game yes/no dialog (white v2 dialog). on_yes runs on confirm, on_no (optional) on
## cancel/dismiss. danger = red confirm button (destructive actions).
func confirm(text: String, on_yes: Callable, on_no: Callable = Callable(), yes_text: String = "Confirm", no_text: String = "Cancel", danger: bool = false) -> void:
	var col := Kit.vbox(28)
	var l := Kit.body(text, 28, Kit.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 500
	col.add_child(Kit.spacer(0, 4))
	col.add_child(l)
	var row := Kit.hbox(16)
	var m_ref: Array[Control] = []
	var no_btn := Kit.light_button(no_text, func() -> void:
		if not m_ref.is_empty():
			_dismiss(m_ref[0]))
	var yes_cb := func() -> void:
		if not m_ref.is_empty():
			close_modal(m_ref[0])
		if on_yes.is_valid():
			on_yes.call()
	var yes_btn := Kit.danger_button(yes_text, yes_cb) if danger else Kit.primary_button(yes_text, yes_cb)
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no_btn)
	row.add_child(yes_btn)
	col.add_child(row)
	var panel := Kit.dialog("Confirm", col, 600.0, true, "info")
	var close := panel.get_meta("close_button") as Button
	Kit._connect_pressed(close, func() -> void:
		if not m_ref.is_empty():
			_dismiss(m_ref[0]))
	var m := modal(panel, true, on_no)
	m_ref.append(m)


## Show a reward popup (Reward dictionary), then call `on_closed` if valid.
## Popups queue if one is already open.
func show_reward(title: String, reward: Dictionary, on_closed: Callable = Callable()) -> void:
	if _modal_layer() == null:
		print("[reward] ", title, " ", reward)
		if on_closed.is_valid():
			on_closed.call()
		return
	if _reward_open:
		_reward_queue.append([title, reward, on_closed])
		return
	_reward_open = true
	sfx("reward")
	haptic(25)
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 660
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# Title plate with slow cyan rays behind it.
	var title_box := Control.new()
	title_box.custom_minimum_size = Vector2(660, 150)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rays := Kit.rays(Kit.ACCENT_HI, 600.0, 18)
	rays.position = Vector2(330 - 300, 75 - 300)
	rays.modulate.a = 0.7
	title_box.add_child(rays)
	var glow := Kit.glow(Kit.ACCENT, 440)
	glow.position = Vector2(330 - 220, 75 - 220)
	glow.modulate.a = 0.45
	title_box.add_child(glow)
	var banner := Kit.ribbon(title, 580.0, Kit.ACCENT)
	banner.position = Vector2(330 - 290, 75 - 46)
	banner.size = Vector2(580, 92)
	title_box.add_child(banner)
	col.add_child(title_box)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	panel.add_theme_stylebox_override("panel", UITheme.style("reward_panel"))
	var inner := Kit.vbox(24)
	panel.add_child(inner)
	var head := Kit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(Kit.deco("techline", Vector2(120, 10), Color(0, 0, 0, 0.25)))
	head.add_child(Kit.label("REWARD", 22, Kit.TEXT_DIM, "cond_bold"))
	var tl := Kit.deco("techline", Vector2(120, 10), Color(0, 0, 0, 0.25))
	tl.scale.x = -1
	tl.pivot_offset = Vector2(60, 5)
	head.add_child(tl)
	inner.add_child(head)
	var entries := Kit.reward_entries(reward)
	if entries.is_empty():
		var none := Kit.body("Nothing this time.", Kit.SIZE_BODY, Kit.TEXT_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(none)
	else:
		var list := Kit.reward_list(reward, 112.0 if entries.size() <= 8 else 96.0, true, true, true)
		list.custom_minimum_size.x = 580
		for tile in list.get_children():
			(tile as Control).modulate.a = 0.0
		inner.add_child(list)
	var m_ref: Array[Control] = []
	var ok := Kit.primary_button("OK", func() -> void:
		if not m_ref.is_empty():
			_dismiss(m_ref[0]))
	ok.custom_minimum_size.x = 320
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(ok)
	col.add_child(panel)
	var hint := Kit.caption("Tap anywhere to close", 20, Color(1, 1, 1, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var closed := func() -> void:
		_reward_open = false
		if on_closed.is_valid():
			on_closed.call()
		if not _reward_queue.is_empty():
			var nxt: Array = _reward_queue.pop_front()
			show_reward.call_deferred(nxt[0], nxt[1], nxt[2])
	var m := modal(col, true, closed)
	m_ref.append(m)
	# Tiles pop in one after another.
	await get_tree().process_frame
	if not is_instance_valid(m):
		return
	var list_node: Control = null
	for c in inner.get_children():
		if c is HFlowContainer:
			list_node = c
	if list_node:
		var i := 0
		for tile in list_node.get_children():
			Kit.pop_in(tile as Control, 0.12 + i * 0.06)
			i += 1


func _modal_layer() -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var l: Variant = root.get("modal_layer")
	return l if l is Control else null


## True while any modal (popup, confirm, reward) is open.
func has_modal() -> bool:
	return not _modals.is_empty()


# ------------------------------------------------------------------ sound & haptics

## Plays a short generated sound: tap, reward, summon, legendary, hit, ult, victory, defeat.
## Silent when Game.setting("sound") is false.
func sfx(sound_name: String) -> void:
	if _audio_released or not _sound_on():
		return
	# The same sound within 45 ms only gets louder, not better (fast battles): skip it.
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound_name, -1000)) < 45:
		return
	_last_played[sound_name] = now
	var stream := _stream(sound_name)
	if stream == null or _players.is_empty():
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.volume_db = float(SFX_VOLUME_DB.get(sound_name, -6.0))
	p.pitch_scale = _sfx_rng.randf_range(0.92, 1.08) if sound_name == "hit" or sound_name == "tap" else 1.0
	p.play()


## Stops the music and every sound player and drops their streams. Call (then wait a frame)
## before quitting, so the audio thread lets go of its playbacks and nothing leaks at exit.
func release_audio() -> void:
	if _music_tw and _music_tw.is_valid():
		_music_tw.kill()
	if _music:
		_music.stop()
		_music.stream = null
	_music_wanted = false
	_audio_released = true
	for p in _players:
		p.stop()
		p.stream = null


## Short vibration (phones only).
func haptic(ms: int = 20) -> void:
	if not OS.has_feature("mobile"):
		return
	var v: Variant = Game.setting("haptics") if Game.has_method("setting") else null
	if v is bool and not v:
		return
	Input.vibrate_handheld(ms)


## Starts/stops the ambient music to match Game.setting("music") (null = on).
func _sync_music() -> void:
	if _audio_released:
		return
	var v: Variant = Game.setting("music") if Game.has_method("setting") else null
	var want: bool = not (v is bool and v == false)
	if DisplayServer.get_name() == "headless":
		want = false
	if want == _music_wanted:
		return
	_music_wanted = want
	if _music_tw and _music_tw.is_valid():
		_music_tw.kill()
	if want:
		if _music.stream == null:
			if not ResourceLoader.exists(MUSIC_PATH):
				return
			var st: Variant = load(MUSIC_PATH)
			if st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = true
			_music.stream = st
		if not _music.playing:
			_music.volume_db = -50.0
			_music.play()
		_music_tw = create_tween()
		_music_tw.tween_property(_music, "volume_db", MUSIC_DB, 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_music_tw = create_tween()
		_music_tw.tween_property(_music, "volume_db", -60.0, 0.6)
		_music_tw.tween_callback(_music.stop)


func _sound_on() -> bool:
	if not Game.has_method("setting"):
		return true
	var v: Variant = Game.setting("sound")
	return not (v is bool and v == false)


func _stream(sound_name: String) -> AudioStreamWAV:
	_streams_mutex.lock()
	var s: Variant = _streams.get(sound_name, null)
	_streams_mutex.unlock()
	if s is AudioStreamWAV:
		return s
	# Not generated yet (very early tap): make it now.
	var made := Sfx.make(sound_name)
	if made:
		_streams_mutex.lock()
		_streams[sound_name] = made
		_streams_mutex.unlock()
	return made


func _generate_all_sounds() -> void:
	for n in Sfx.NAMES:
		_streams_mutex.lock()
		var have := _streams.has(n)
		_streams_mutex.unlock()
		if have:
			continue
		var w := Sfx.make(n)
		_streams_mutex.lock()
		_streams[n] = w
		_streams_mutex.unlock()
