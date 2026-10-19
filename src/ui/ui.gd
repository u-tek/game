extends Node
## Autoload "UI": navigation, feedback and modals every screen uses.
## Contract: docs/dev/architecture.md section 5.
##
##   UI.go("hero_detail", {"hero_id": "seraphiel"})  # navigate (animated, history kept)
##   UI.back()                                       # previous screen (or home)
##   UI.toast("Not enough gold", "bad")              # sliding message with an icon, top center
##   UI.show_reward("Stage cleared!", reward, on_closed)  # reward popup (queued)
##   UI.confirm("Spend 300 gems?", on_yes)           # in-game yes/no dialog
##   UI.set_chrome(show_top_bar, show_nav)           # reset to (true, true) on every go()
##   UI.safe_top() / UI.safe_bottom()                # notch / home-indicator insets (px)
##   UI.pinned_bottom_inset()                        # keep bottom-pinned bars clear of the Lobby hex
##   UI.sfx("tap")                                   # see Sfx.NAMES (tap tab pop deny coin reward ...)
##   UI.haptic(20)                                   # short vibration on phones
##   UI.busy("Preparing battle") / UI.idle()         # full-screen loading veil with a spinner
## Background music plays by itself and follows Game.setting("music").
## Extras: UI.popup(title, content) for custom dialogs, UI.modal(content) / close_modal(m),
## signal screen_changed(name), UI.current_name, UI.history.
##
## Transitions (2026-10-19): going deeper slides the new screen in from the right while the
## old one drifts left and fades (back mirrors it), bottom-nav tabs cross-fade, a battle
## zooms in behind a loading veil. The old screen leaves the tree at once (its _exit_tree
## runs as before) and is shown as a frozen "ghost" for the moment it takes to fade.
## Content then staggers in (Kit.stagger_in), or the screen runs its own intro() if it has
## one. Settings > Reduce motion swaps all of it for a short fade.
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
	"tower": "res://src/ui/screens/tower_screen.gd",
	"battle": "res://src/ui/screens/battle_screen.gd",
	"heroes": "res://src/ui/screens/heroes_screen.gd",
	"hero_detail": "res://src/ui/screens/hero_detail_screen.gd",
	"formation": "res://src/ui/screens/formation_screen.gd",
	"summon": "res://src/ui/screens/summon_screen.gd",
	"quests": "res://src/ui/screens/quests_screen.gd",
	"shop": "res://src/ui/screens/shop_screen.gd",
	"settings": "res://src/ui/screens/settings_screen.gd",
	"gear": "res://src/ui/screens/gear_screen.gd",
	"profile": "res://src/ui/screens/profile_screen.gd",
	# Widget gallery for UI work (debug builds only; not in the nav).
	"kit_demo": "res://src/ui/components/kit_demo.gd",
	# Splash card preview (loading screens, event cards; assets/art/splash/).
	"splash_view": "res://src/ui/screens/splash_view_screen.gd",
	# Style v4 Lobby mockup, the approved poster composition (debug builds only; docs/dev/ui-style-v4.md).
	"lobby_v5": "res://src/ui/screens/lobby_v5_screen.gd",
}

## Bottom-nav tabs, left to right (the centre one, "home", is the Lobby).
const NAV_TABS: Array[String] = ["heroes", "formation", "home", "gear", "summon"]
## Going to one of these resets the history (back returns home).
const NAV_ROOTS: Array[String] = ["heroes", "formation", "home", "gear", "summon", "quests", "shop"]
## Which nav tab is highlighted for non-tab screens.
const NAV_PARENT := {"campaign": "home", "tower": "home", "battle": "home", "hero_detail": "heroes", "kit_demo": "home",
	"quests": "home", "shop": "home", "settings": "home", "profile": "home"}
## Currencies shown in the top-bar resource pill per screen (default: gems, gold).
const TOP_CURRENCIES := {"summon": ["gems", "scrolls"], "heroes": ["gold", "hero_exp"],
	"hero_detail": ["gold", "hero_exp"], "gear": ["gold", "dust"]}
## Screens never kept in history (back from the next screen skips them).
const NO_HISTORY: Array[String] = ["battle"]
## Screens with their own entrance (no automatic content stagger).
const NO_STAGGER: Array[String] = ["battle", "summon", "splash_view"]
## Screens slow enough to build that a loading veil shows first (in the app, not in tests).
const HEAVY: Array[String] = ["battle"]
const FADE_TIME := 0.15
## Ambient loop (rendered by assets/art/ui/src/make_music.py). Follows Game.setting("music").
const MUSIC_PATH := "res://assets/art/ui/music_twilight.ogg"
const MUSIC_DB := -15.0
const MAX_TOASTS := 3
const TOAST_W := 540.0
const TOAST_GAP := 10.0
const TOAST_SECS := 2.4
const SFX_VOLUME_DB := {
	"tap": -10.0, "tab": -11.0, "pop": -13.0, "close": -17.0, "deny": -9.0, "toggle": -11.0,
	"coin": -13.0, "sparkle": -15.0, "hit": -6.0, "reward": -5.0, "summon": -4.0, "legendary": -3.0,
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
## While true (the boot screen is up), new screens wait to play their intro: play_intro().
var hold_intro := false

var _fade: Tween
var _heavy_pending := false
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

## Navigate to a screen by name with optional params. params "_dir" (1 / -1) picks the slide
## direction when a screen replaces itself (hero browse arrows).
func go(screen: String, params: Dictionary = {}) -> void:
	if not SCREENS.has(screen) or (screen in ["kit_demo", "lobby_v5"] and not OS.is_debug_build()):
		push_error("UI.go: unknown screen '%s'" % screen)
		toast("That screen doesn't exist yet")
		return
	if screen in HEAVY and _veil_first():
		# Show the loading veil for a moment so it is up (and spinning) before the build.
		if _heavy_pending:
			return
		_heavy_pending = true
		busy("Preparing battle" if screen == "battle" else "Loading")
		await get_tree().create_timer(0.18).timeout
		await get_tree().process_frame
		_heavy_pending = false
		if root == null or not is_instance_valid(root):
			return
	var kind := _kind_for(screen, params)
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
	_show(screen, params, kind)


## Go back to the previous screen (or home).
func back() -> void:
	if history.is_empty():
		if current_name != "home":
			_show("home", {}, "pop")
		return
	var e: Dictionary = history.pop_back()
	_show(str(e.get("name", "home")), e.get("params", {}), "pop")


## How a navigation looks: "tab" (bottom-nav cross-fade), "push" / "pop" (slide deeper /
## back), "swap" (a screen replacing itself), "zoom" (into a battle), "fade".
func _kind_for(screen: String, params: Dictionary) -> String:
	if current_name == "":
		return "first"
	if screen == "battle":
		return "zoom"
	if current_name == "battle":
		return "fade"
	if screen == current_name:
		return "swap_back" if int(params.get("_dir", 1)) < 0 else "swap"
	if screen in NAV_TABS and current_name in NAV_TABS:
		return "tab"
	if _history_index(screen) >= 0:
		return "pop"
	return "push"


## True when heavy screens should show the loading veil first: the real app (the main scene
## is running), not the test scripts that drive UI.go directly.
func _veil_first() -> bool:
	if root == null or not is_instance_valid(root) or not root.has_method("show_veil"):
		return false
	return root == get_tree().current_scene


## Full-screen loading veil (dim glass, a spinner and `text`) over everything; blocks taps.
func busy(text: String = "Loading") -> void:
	if root and is_instance_valid(root) and root.has_method("show_veil"):
		root.call("show_veil", text)


## Fades the loading veil out (no-op when it isn't up).
func idle() -> void:
	if root and is_instance_valid(root) and root.has_method("hide_veil"):
		root.call("hide_veil")


## Plays the current screen's entrance now (after the boot screen lifts).
func play_intro() -> void:
	hold_intro = false
	if current and is_instance_valid(current):
		_intro(current)


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


func _show(screen: String, params: Dictionary, kind: String = "push") -> void:
	var host := _content_host()
	if host == null:
		push_error("UI.go before UI.attach")
		return
	var script: Variant = load(SCREENS[screen])
	if not (script is Script) or not (script as Script).can_instantiate():
		push_error("UI.go: screen '%s' failed to load" % screen)
		toast("Couldn't open %s" % screen.capitalize())
		idle()
		return
	var ghost: Control = null
	if current and is_instance_valid(current):
		var old := current
		old.set_meta("_ui_rect", old.get_global_rect())
		# Leaves the tree now (its _exit_tree runs as it always did) ...
		host.remove_child(old)
		# ... and comes back as a frozen picture for the transition, if it was ever shown.
		if bool(old.get_meta("_ui_shown", false)) and Kit.motion_ok() and kind != "first":
			ghost = old
		else:
			old.queue_free()
	current = null
	full_bleed = false
	set_chrome(true, true)
	var s: Variant = (script as Script).new()
	if not (s is Control):
		push_error("UI.go: screen '%s' is not a Control" % screen)
		if s is Node:
			(s as Node).queue_free()
		if ghost:
			ghost.queue_free()
		idle()
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
		# setup() navigated somewhere else; that call already finished the job.
		if ghost:
			ghost.queue_free()
		return
	sc.set_meta("_ui_shown", true)
	if ghost:
		_retire(ghost, kind)
	_enter(sc, kind)
	screen_changed.emit(screen)
	idle()


## The new screen's entrance for a navigation `kind` (see _kind_for), then its content intro.
func _enter(sc: Control, kind: String) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = sc.create_tween().set_parallel(true)
	if not Kit.motion_ok():
		_fade.tween_property(sc, "modulate:a", 1.0, 0.12)
		return
	var w := maxf(sc.size.x, 360.0)
	sc.pivot_offset = sc.size * 0.5
	match kind:
		"push", "pop", "swap", "swap_back":
			var dir := -1.0 if kind == "pop" or kind == "swap_back" else 1.0
			sc.position.x = dir * w * (0.12 if kind.begins_with("swap") else 0.09)
			_fade.tween_property(sc, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_fade.tween_property(sc, "modulate:a", 1.0, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		"zoom":
			sc.scale = Vector2(1.08, 1.08)
			_fade.tween_property(sc, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_fade.tween_property(sc, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_:
			# Tabs, first screen, leaving a battle: a quick cross-fade with a breath of scale.
			sc.scale = Vector2(0.985, 0.985)
			_fade.tween_property(sc, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_fade.tween_property(sc, "modulate:a", 1.0, 0.16 if kind == "tab" else 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not hold_intro:
		_intro(sc)


## A screen's own intro() or the generic content stagger.
func _intro(sc: Control) -> void:
	if not Kit.motion_ok():
		return
	if sc.has_method("intro"):
		sc.call("intro")
	elif not (current_name in NO_STAGGER):
		Kit.stagger_in(sc, 0.05)


## Shows the screen that is being replaced as a frozen picture behind the new one while it
## fades away, then frees it. It no longer processes or takes input.
func _retire(ghost: Control, kind: String) -> void:
	var host := _content_host()
	if host == null:
		ghost.queue_free()
		return
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.name = "Leaving_" + String(ghost.name)
	host.add_child(ghost)
	host.move_child(ghost, 0)
	# Keep the picture exactly where it was, even if the content area changed size (the
	# full-bleed lobby leaving for a framed screen): no reflow while it fades.
	var r: Variant = ghost.get_meta("_ui_rect", null)
	if r is Rect2:
		ghost.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ghost.size = (r as Rect2).size
		ghost.global_position = (r as Rect2).position
	var x0 := ghost.position.x
	var w := maxf(ghost.size.x, 360.0)
	ghost.pivot_offset = ghost.size * 0.5
	var tw := create_tween().set_parallel(true)
	# It stays solid at first and drops out fast: the new screen is opaque by then, so the
	# change never passes through a milky half-and-half.
	match kind:
		"push", "swap":
			tw.tween_property(ghost, "position:x", x0 - w * 0.06, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(ghost, "modulate", Color(0.6, 0.62, 0.68, 0.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"pop", "swap_back":
			tw.tween_property(ghost, "position:x", x0 + w * 0.06, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(ghost, "modulate", Color(0.6, 0.62, 0.68, 0.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"zoom":
			tw.tween_property(ghost, "scale", Vector2(0.96, 0.96), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(ghost, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_:
			tw.tween_property(ghost, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var gref: WeakRef = weakref(ghost)
	tw.chain().tween_callback(func() -> void:
		var g := gref.get_ref() as Node
		if g:
			g.queue_free())


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


## Extra room a bar pinned to the bottom of the content area must leave above the nav: the
## raised Lobby hexagon pokes up this far (0 when the nav is hidden). Scrolling lists can run
## under it; fixed buttons and panels should not.
func pinned_bottom_inset() -> float:
	if not chrome_nav or root == null or not is_instance_valid(root) or not root.has_method("nav_rise"):
		return 0.0
	return float(root.call("nav_rise"))


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

## Short message at the top of the screen. kind: "info" | "good" | "bad" ("bad" also plays the
## deny sound). Style v4 print: a paper label strip stuck on a touch crooked, an ink tag (signal
## for "bad") with the glyph, a mono kicker and the message. Toasts drop in with a spring, stack
## (newest at the bottom, at most MAX_TOASTS), glide up when one above leaves, and leave by
## themselves after TOAST_SECS.
func toast(text: String, kind: String = "info") -> void:
	var box: Variant = root.get("toast_box") if root and is_instance_valid(root) else null
	if not (box is Control):
		print("[toast] ", text)
		return
	var host := box as Control
	var live := _live_toasts(host)
	while live.size() >= MAX_TOASTS:
		_toast_out(live.pop_front(), true)
	# Style v4 print: a paper label strip; at its start a tag block (ink, or signal for "bad") with the
	# glyph, then a mono kicker (NOTE / CONFIRMED / DENIED and the time) over the message.
	var p := PanelContainer.new()
	p.theme_type_variation = &"ToastPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.style("toast"))
	var row := Kit.hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Kit.ACCENT if kind == "bad" else Kit.BAND
	ts.content_margin_left = 16
	ts.content_margin_right = 16
	tag.add_theme_stylebox_override("panel", ts)
	tag.custom_minimum_size = Vector2(66, 72)
	var ic: String = {"good": "check", "bad": "close"}.get(kind, "info")
	var bubble := Kit.icon(ic, 30, Kit.MATTE)
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.add_child(bubble)
	row.add_child(tag)
	var col := Kit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tm := Time.get_time_dict_from_system()
	var word: String = {"good": "CONFIRMED", "bad": "DENIED"}.get(kind, "NOTE")
	col.add_child(Kit.print_label("%s  ·  %02d:%02d" % [word, int(tm.hour), int(tm.minute)], 11,
		Kit.ACCENT_DEEP if kind == "bad" else Color(Kit.TEXT, 0.6)))
	var l := Kit.label(text, 23, Kit.TEXT, "bold")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Every toast has the same width, so a stack lines up as one column.
	l.custom_minimum_size.x = TOAST_W - 66.0 - 16.0 - 20.0
	col.add_child(l)
	row.add_child(col)
	p.add_child(row)
	host.add_child(p)
	p.size = p.get_combined_minimum_size()
	p.position = Vector2(-p.size.x * 0.5, _toast_slot_y(host, p))
	p.pivot_offset = p.size * 0.5
	# Stuck on a touch crooked, like a label.
	p.rotation = -0.012 if host.get_child_count() % 2 == 0 else 0.01
	if kind == "bad":
		sfx("deny")
		haptic(18, 0.6)
	if Kit.motion_ok():
		p.modulate.a = 0.0
		p.scale = Vector2(0.92, 0.92)
		var y := p.position.y
		p.position.y = y - 26.0
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "modulate:a", 1.0, 0.16)
		tw.tween_property(p, "position:y", y, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bubble.pivot_offset = Vector2(15, 15)
		bubble.scale = Vector2(0.4, 0.4)
		tw.tween_property(bubble, "scale", Vector2.ONE, 0.4).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var life := p.create_tween()
	life.tween_interval(TOAST_SECS + 0.1 * text.length() / 10.0)
	life.tween_callback(func() -> void: _toast_out(p, false))


## Toasts still on screen (not leaving), oldest first.
func _live_toasts(host: Control) -> Array[Control]:
	var out: Array[Control] = []
	for c in host.get_children():
		if c is Control and not (c as Control).has_meta("leaving"):
			out.append(c)
	return out


## Y of `p`'s slot: under the live toasts before it.
func _toast_slot_y(host: Control, p: Control) -> float:
	var y := 0.0
	for c in _live_toasts(host):
		if c == p:
			break
		y += c.size.y + TOAST_GAP
	return y


func _toast_out(p: Control, fast: bool) -> void:
	if not is_instance_valid(p) or p.has_meta("leaving"):
		return
	p.set_meta("leaving", true)
	var host := p.get_parent() as Control
	var tw := p.create_tween().set_parallel(true)
	var d := 0.14 if fast else 0.26
	tw.tween_property(p, "modulate:a", 0.0, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "position:y", p.position.y - 18.0, d).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "scale", Vector2(0.95, 0.95), d)
	tw.chain().tween_callback(p.queue_free)
	if host:
		_restack_toasts(host)


## Glides the live toasts up into their slots after one leaves.
func _restack_toasts(host: Control) -> void:
	var y := 0.0
	for c in _live_toasts(host):
		if absf(c.position.y - y) > 0.5:
			var tw := c.create_tween()
			tw.tween_property(c, "position:y", y, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		y += c.size.y + TOAST_GAP


# ------------------------------------------------------------------ modals

## Opens `content` as a modal over everything (the backdrop dims in, the panel springs up
## from 80 % with a soft "pop" sound). dismissable: tapping the backdrop or Back closes it
## (calls on_closed). sound: "" for none. Returns the modal root; close it with close_modal(m).
func modal(content: Control, dismissable: bool = true, on_closed: Callable = Callable(), sound: String = "pop") -> Control:
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
	# The screen behind goes back to the paper matte (style v4: a printed sheet laid on the matte),
	# leaving a ghost of it. Chosen to read in both canvas modes: a light wash blends a little
	# stronger on the linear HDR canvas (desktop) than on the plain sRGB one (iPhone, ui_linear 0).
	var dim := ColorRect.new()
	dim.color = Color(Kit.MATTE, 0.78)
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
	m.set_meta("content", content)
	m.set_meta("dim", dim)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	content.pivot_offset = content.get_combined_minimum_size() * 0.5
	content.modulate.a = 0.0
	var tw := content.create_tween().set_parallel(true)
	if Kit.motion_ok():
		content.scale = Vector2(0.8, 0.8)
		tw.tween_property(content, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(content, "modulate:a", 1.0, 0.16)
	else:
		tw.tween_property(content, "modulate:a", 1.0, 0.12)
	content.resized.connect(func() -> void: content.pivot_offset = content.size * 0.5)
	if sound != "":
		sfx(sound)
	return m


## Closes a modal opened with modal()/popup() without calling its on_closed. It stops
## taking input at once, then shrinks and fades away.
func close_modal(m: Control) -> void:
	if m == null or not is_instance_valid(m) or m.is_queued_for_deletion() or m.has_meta("closing"):
		return
	_modals.erase(m)
	m.set_meta("closing", true)
	_ignore_input(m)
	var content: Variant = m.get_meta("content", null)
	var dim: Variant = m.get_meta("dim", null)
	var tw := m.create_tween().set_parallel(true)
	if content is Control and dim is Control and is_instance_valid(content) and Kit.motion_ok():
		var c := content as Control
		tw.tween_property(c, "scale", Vector2(0.9, 0.9), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(dim as Control, "modulate:a", 0.0, 0.2)
	else:
		tw.tween_property(m, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(m.queue_free)


func _ignore_input(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_input(c)


func _dismiss(m: Control) -> void:
	if not is_instance_valid(m) or not _modals.has(m):
		return
	var cb: Variant = m.get_meta("on_closed", Callable())
	close_modal(m)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


## Standard dialog (Kit.dialog, style v4 print): a printed sheet on the matte with a serial line, the
## title big in compressed type over a ruled line, a printed "× CLOSE" and your content in the
## body. light = true prints it on paper (build content with Kit.TEXT colours); the default dark
## band sheet suits content built with light text (Kit.INK).
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


## In-game yes/no dialog, style v4 print: a "CONFIRM" sheet with the question set in the serif, a
## signature line, then Cancel (printed outline) and the answer (the signal plate). on_yes runs on
## confirm, on_no (optional) on cancel/dismiss. danger = an ink plate ruled in signal (destructive
## actions).
func confirm(text: String, on_yes: Callable, on_no: Callable = Callable(), yes_text: String = "Confirm", no_text: String = "Cancel", danger: bool = false) -> void:
	var col := Kit.vbox(16)
	col.custom_minimum_size.x = 540
	col.add_child(Kit.print_label("Request  ·  sign to proceed" if not danger else "Warning  ·  read before you sign", 12,
		Color(Kit.ACCENT_DEEP if danger else Kit.TEXT, 0.75)))
	var l := Kit.label(text, 34, Kit.TEXT, "serif")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	col.add_child(l)
	# A signature line (print): a slanted x, the rule and a mono caption under it.
	var sig := Control.new()
	sig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sig.custom_minimum_size = Vector2(540, 46)
	var x := Kit.label("x", 30, Color(Kit.TEXT, 0.7), "serif_italic")
	x.position = Vector2(2, -4)
	sig.add_child(x)
	var rule := ColorRect.new()
	rule.color = Color(Kit.TEXT, 0.55)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2(28, 28)
	rule.size = Vector2(300, 1)
	sig.add_child(rule)
	var cap := Kit.print_label("Signature  ·  %s" % Kit._print_date(), 10, Color(Kit.TEXT, 0.55), "mono")
	cap.position = Vector2(28, 30)
	sig.add_child(cap)
	col.add_child(sig)
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


## Show a reward popup (Reward dictionary), then call `on_closed` if valid. Popups queue if one
## is already open. Style v4 print: a receipt laid on the matte (receipt number and time, the title
## big in compressed type with its last word in signal, one printed row per reward with a dotted
## leader, the item count, a barcode and a RECEIVED stamp on a silver disc, a torn edge), then OK
## (the signal plate). The rows print one after another with rising notes and the stamp comes down
## last; on close the currencies fly from their rows to the wallet.
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
	const W := 600.0
	var iw := W - 64.0
	var col := Kit.vbox(0)
	col.custom_minimum_size.x = W
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var sheet := PanelContainer.new()
	sheet.name = "RewardSheet"
	sheet.add_theme_stylebox_override("panel", UITheme.style("reward_panel"))
	# The print under it: crop marks and a red halftone ramp in the top corner (a big moment: grit).
	var prints := Control.new()
	prints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prints.clip_contents = true
	var ramp := Kit.halftone_ramp(Vector2(260, 120), Color(1.0, 0.36, 0.16, 0.55), 7.0, "right")
	ramp.anchor_left = 1.0
	ramp.anchor_right = 1.0
	ramp.offset_left = -260
	ramp.offset_right = 0
	ramp.offset_bottom = 120
	prints.add_child(ramp)
	var marks := Kit.PrintBits.CropMarks.new()
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prints.add_child(marks)
	sheet.add_child(prints)
	var inner := Kit.vbox(10)
	sheet.add_child(inner)
	var no := 100000 + absi(hash(title + str(Time.get_ticks_msec()))) % 900000
	var top := Kit.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(Kit.print_label("Receipt No.%06d" % no, 12))
	top.add_child(Kit.spacer(0, 0, true))
	var tm := Time.get_time_dict_from_system()
	top.add_child(Kit.print_label("%s  %02d:%02d" % [Kit._print_date(), int(tm.hour), int(tm.minute)], 12, Color(Kit.TEXT, 0.6), "mono"))
	inner.add_child(top)
	var head := RichTextLabel.new()
	head.name = "Title"
	head.bbcode_enabled = true
	head.fit_content = true
	head.scroll_active = false
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size.x = iw
	var words := title.to_upper().split(" ", false)
	var key := words[words.size() - 1] if not words.is_empty() else ""
	var lead := " ".join(words.slice(0, maxi(words.size() - 1, 0)))
	head.text = ("%s [color=#%s]%s[/color]" % [lead, Kit.ACCENT.to_html(false), key]).strip_edges()
	var hf := Kit.font("compressed")
	var fs := 100
	while fs > 52 and hf.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > iw:
		fs -= 4
	head.add_theme_font_override("normal_font", hf)
	head.add_theme_font_size_override("normal_font_size", fs)
	head.add_theme_color_override("default_color", Kit.TEXT)
	head.add_theme_constant_override("line_separation", -int(fs * 0.18))
	inner.add_child(head)
	inner.add_child(Kit.tick_rule(iw, Color(Kit.TEXT, 0.55), {"lead": Kit.ACCENT}))
	var entries := Kit.reward_entries(reward)
	var rows: Array[Control] = []
	var icons: Array[Control] = []
	if entries.is_empty():
		var none := Kit.empty_state("Nothing this time.", "", true)
		none.custom_minimum_size.y = 120
		inner.add_child(none)
	else:
		var receipt := Kit.reward_receipt(reward, iw, {"compact": entries.size() > 6})
		rows.assign(receipt.get_meta("rows", []))
		icons.assign(receipt.get_meta("icons", []))
		for r in rows:
			r.modulate.a = 0.0
		if entries.size() > 11:
			var sc := Kit.scroll(receipt)
			sc.custom_minimum_size = Vector2(iw, 11 * 41.0)
			inner.add_child(sc)
		else:
			inner.add_child(receipt)
	# The foot: a double rule, the item count, a barcode and the RECEIVED stamp on a silver disc.
	var dbl := Kit.vbox(3)
	dbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var hr := ColorRect.new()
		hr.color = Color(Kit.TEXT, 0.6)
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hr.custom_minimum_size = Vector2(iw, 1)
		dbl.add_child(hr)
	inner.add_child(dbl)
	var tot := Kit.hbox(8)
	tot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tot.add_child(Kit.print_label("Items", 13))
	tot.add_child(Kit.spacer(0, 0, true))
	tot.add_child(Kit.print_label("%02d" % entries.size(), 13))
	inner.add_child(tot)
	var foot := Kit.hbox(0)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.custom_minimum_size.y = 64
	var bcol := Kit.vbox(4)
	bcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bcol.size_flags_vertical = Control.SIZE_SHRINK_END
	bcol.add_child(SignalKit.barcode(Vector2(210, 34), Kit.TEXT, no % 997))
	bcol.add_child(Kit.print_label("HH-%06d  ·  Keep this receipt" % no, 10, Color(Kit.TEXT, 0.6), "mono"))
	foot.add_child(bcol)
	foot.add_child(Kit.spacer(0, 0, true))
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(128, 64)
	var disc := SignalKit.plate("silver", Vector2(0, -58), Vector2(128, 128), {"circle": true, "shadow": 0.5}, slot)
	disc.add_child(SignalKit.stamp("RECEIVED · HALO & HORN · ", "OK", 128))
	disc.pivot_offset = Vector2(64, 64)
	disc.rotation = -0.16
	foot.add_child(slot)
	inner.add_child(foot)
	col.add_child(sheet)
	var torn := Kit.PrintBits.Zigzag.new()
	torn.color = Kit.SHEET_WHITE
	torn.custom_minimum_size = Vector2(W, 14)
	col.add_child(torn)
	col.add_child(Kit.spacer(0, 30))
	var m_ref: Array[Control] = []
	var ok := Kit.primary_button("OK", func() -> void:
		if not m_ref.is_empty():
			_dismiss(m_ref[0]))
	ok.custom_minimum_size.x = 320
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ok)
	col.add_child(Kit.spacer(0, 14))
	var hint := Kit.print_label("Tap anywhere to close", 13, Color(Kit.TEXT, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	# The top-bar wallet holds its old numbers while the popup is up; on close the currencies
	# fly from their rows to the wallet and it counts up as they land.
	var hold := _hold_currency()
	var closed := func() -> void:
		_reward_open = false
		_fly_rewards(entries, icons, hold)
		if on_closed.is_valid():
			on_closed.call()
		if not _reward_queue.is_empty():
			var nxt: Array = _reward_queue.pop_front()
			show_reward.call_deferred(nxt[0], nxt[1], nxt[2])
	var m := modal(col, true, closed, "")
	m_ref.append(m)
	# Never leave the wallet frozen, however the popup goes away.
	m.tree_exited.connect(func() -> void: hold.call())
	if not Kit.motion_ok():
		for r in rows:
			r.modulate.a = 1.0
		return
	head.visible_ratio = 0.0
	head.create_tween().tween_property(head, "visible_ratio", 1.0, 0.36).set_delay(0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	disc.modulate.a = 0.0
	hint.modulate.a = 0.0
	# Rows print one after another, each with a rising note; then the stamp comes down.
	await get_tree().process_frame
	if not is_instance_valid(m):
		return
	var i := 0
	for r in rows:
		var delay := 0.18 + i * 0.08
		r.modulate.a = 1.0
		Kit.offset_in(r, Vector2(-26, 0), delay, 0.32)
		if i < 10:
			var pitch := 1.0 + 0.06 * i
			var tt := r.create_tween()
			tt.tween_interval(delay + 0.04)
			tt.tween_callback(func() -> void: sfx("sparkle", pitch))
		i += 1
	var at := 0.3 + rows.size() * 0.08
	disc.scale = Vector2(1.7, 1.7)
	var dt := disc.create_tween().set_parallel(true)
	dt.tween_property(disc, "modulate:a", 1.0, 0.12).set_delay(at)
	dt.tween_property(disc, "scale", Vector2.ONE, 0.26).set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	dt.tween_callback(func() -> void:
		sfx("pop")
		haptic(18)).set_delay(at + 0.14)
	var ht := hint.create_tween()
	ht.tween_interval(at + 0.5)
	ht.tween_property(hint, "modulate:a", 1.0, 0.4)
	ht.tween_callback(func() -> void:
		var loop := hint.create_tween().set_loops()
		loop.tween_property(hint, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		loop.tween_property(hint, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))


## Freezes the top-bar wallet (its amounts stay put while a reward popup is open). Returns
## the release callable; calling it more than once is harmless.
func _hold_currency() -> Callable:
	var r: Variant = root if root and is_instance_valid(root) else null
	if r == null or not (r as Node).has_method("hold_currency"):
		return func() -> void: pass
	(r as Node).call("hold_currency", true)
	var token := {"done": false}
	var rref: WeakRef = weakref(r)
	return func() -> void:
		if token.done:
			return
		token.done = true
		var n := rref.get_ref() as Node
		if n:
			n.call("hold_currency", false)


## On closing a reward popup: currency icons fly from their tiles to the wallet in the top
## bar (when it shows that currency), then `release` lets the wallet count up.
func _fly_rewards(entries: Array[Dictionary], tiles: Array[Control], release: Callable) -> void:
	if root == null or not is_instance_valid(root) or not root.has_method("fly_currency") or not chrome_top or not Kit.motion_ok():
		release.call()
		return
	var sources: Array[Dictionary] = []
	for i in mini(entries.size(), tiles.size()):
		var e := entries[i]
		var t := tiles[i]
		if str(e.get("kind", "")) == "currency" and is_instance_valid(t):
			sources.append({"id": str(e.get("id", "")), "from": t.get_global_rect().get_center(), "amount": int(e.get("amount", 0))})
	root.call("fly_currency", sources, release)


func _modal_layer() -> Control:
	if root == null or not is_instance_valid(root):
		return null
	var l: Variant = root.get("modal_layer")
	return l if l is Control else null


## True while any modal (popup, confirm, reward) is open.
func has_modal() -> bool:
	return not _modals.is_empty()


# ------------------------------------------------------------------ sound & haptics

## Plays a short generated sound (Sfx.NAMES: tap, tab, pop, close, deny, toggle, coin,
## sparkle, reward, summon, legendary, hit, ult, victory, defeat). pitch > 0 sets the pitch
## (taps and hits otherwise vary a little by themselves). Silent when Game.setting("sound")
## is false.
func sfx(sound_name: String, pitch: float = -1.0) -> void:
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
	if pitch > 0.0:
		p.pitch_scale = pitch
	elif sound_name in ["hit", "tap", "tab", "coin"]:
		p.pitch_scale = _sfx_rng.randf_range(0.94, 1.06)
	else:
		p.pitch_scale = 1.0
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


## Short vibration (phones only; follows the Vibration setting). amplitude 0..1 sets the
## strength (a light tick for taps, firmer for "no"); -1 = the device default.
func haptic(ms: int = 20, amplitude: float = -1.0) -> void:
	if not OS.has_feature("mobile"):
		return
	var v: Variant = Game.setting("haptics") if Game.has_method("setting") else null
	if v is bool and not v:
		return
	Input.vibrate_handheld(ms, amplitude)


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
