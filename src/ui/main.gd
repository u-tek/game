extends Control
## App root: background, top bar (team power, gold/gems/scrolls, settings), the content
## area where screens mount, bottom nav (Home, Heroes, Summon, Quests, Shop), toast and
## modal layers. Registers itself with the UI autoload and refreshes on Game.changed.
##
## Screenshot mode (docs/dev/architecture.md section 1), args after "--":
##   --shoot=<screen> --shoot-out=<png> --shoot-params=<json> --shoot-wait=<s>
##   --safe-area-sim  (108 px top / 62 px bottom insets, like a notched iPhone)

const Backdrop := preload("res://src/ui/components/backdrop.gd")
const NavTab := preload("res://src/ui/components/nav_tab.gd")

## Heights of the chrome bars, not counting the safe-area insets.
const TOP_H := 92.0
const NAV_H := 116.0
## Toasts start this far below the top of the content area (clear of screen headers).
const TOAST_GAP := 112.0
const TABS := [
	["home", "Home"], ["heroes", "Heroes"], ["summon", "Summon"], ["quests", "Quests"], ["shop", "Shop"],
]

## Where screens are mounted (UI.go adds them here).
var content: Control
## Toasts stack here (UI.toast).
var toast_box: VBoxContainer
## Modals are added here (UI.modal / popup / confirm / show_reward).
var modal_layer: Control
var backdrop: Control
var top_bar: Control
var nav_bar: Control

var _top_margin: MarginContainer
var _power_chip: PanelContainer
var _power_label: Label
var _power_value := -1
var _chips: Dictionary = {}
var _tabs: Dictionary = {}
var _shoot: Dictionary = {}
var _held_toasts: Array[String] = []


func _ready() -> void:
	_parse_args()
	theme = UITheme.get_theme()
	get_tree().root.theme = theme
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()
	UI.attach(self)
	UI.screen_changed.connect(_on_screen_changed)
	if Game.has_signal("changed"):
		Game.changed.connect(_refresh)
	if Game.has_signal("notify"):
		Game.notify.connect(_on_notify)
	get_viewport().size_changed.connect(_layout)
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_refresh_dots)
	add_child(timer)
	_layout()
	_refresh()
	if _shoot.has("screen"):
		_run_shoot()
	else:
		UI.go("home")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		UI.handle_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		UI.handle_back()


# ------------------------------------------------------------------ build

func _build() -> void:
	backdrop = Backdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(backdrop)

	content = Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	content.clip_contents = true
	add_child(content)

	_build_top_bar()
	_build_nav()

	toast_box = VBoxContainer.new()
	toast_box.name = "Toasts"
	toast_box.mouse_filter = MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 10)
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.grow_horizontal = GROW_DIRECTION_BOTH
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(toast_box)

	modal_layer = Control.new()
	modal_layer.name = "Modals"
	modal_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	modal_layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(modal_layer)


func _build_top_bar() -> void:
	top_bar = Control.new()
	top_bar.name = "TopBar"
	top_bar.mouse_filter = MOUSE_FILTER_STOP
	top_bar.anchor_right = 1.0
	add_child(top_bar)
	var bg := Panel.new()
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UITheme.style("topbar"))
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.offset_left = -4
	bg.offset_right = 4
	bg.offset_top = -4
	top_bar.add_child(bg)

	_top_margin = MarginContainer.new()
	_top_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_top_margin.add_theme_constant_override("margin_left", 10)
	_top_margin.add_theme_constant_override("margin_right", 6)
	_top_margin.add_theme_constant_override("margin_bottom", 2)
	top_bar.add_child(_top_margin)
	var row := Kit.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_margin.add_child(row)

	# Team power: tap to open the formation.
	_power_chip = PanelContainer.new()
	_power_chip.theme_type_variation = &"ChipPanel"
	_power_chip.add_theme_stylebox_override("panel", _tall_chip_style())
	_power_chip.custom_minimum_size = Vector2(136, 88)
	_power_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	var prow := Kit.hbox(4)
	prow.mouse_filter = MOUSE_FILTER_IGNORE
	prow.add_child(Kit.icon("power", 44))
	_power_label = Kit.label("0", 26, Kit.GOLD_LIGHT, "black", 5)
	_power_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prow.add_child(_power_label)
	_power_chip.add_child(prow)
	Kit.make_tappable(_power_chip, func() -> void: UI.go("formation"))
	row.add_child(_power_chip)

	var actions := {
		"gold": Callable(),
		"gems": func() -> void: UI.go("shop"),
		"scrolls": func() -> void: UI.go("summon"),
	}
	for id: String in ["gold", "gems", "scrolls"]:
		var chip := Kit.currency_chip(id, 0, actions[id])
		chip.size_flags_horizontal = SIZE_EXPAND_FILL
		chip.size_flags_vertical = SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("panel", _tall_chip_style())
		chip.custom_minimum_size.y = 88
		row.add_child(chip)
		_chips[id] = chip

	var settings := Kit.icon_button("settings", func() -> void: UI.go("settings"), 84, "round")
	settings.custom_minimum_size = Vector2(74, 88)
	settings.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(settings)


## Chip look (54 px pill) on an 88 px tall touch target.
func _tall_chip_style() -> StyleBox:
	var sb := UITheme.style("chip")
	var inset := (88.0 - 54.0) * 0.5
	sb.set("draw_inset", Vector2(0, inset))
	sb.content_margin_top += inset
	sb.content_margin_bottom += inset
	return sb


func _build_nav() -> void:
	nav_bar = Control.new()
	nav_bar.name = "NavBar"
	nav_bar.mouse_filter = MOUSE_FILTER_STOP
	nav_bar.anchor_top = 1.0
	nav_bar.anchor_right = 1.0
	nav_bar.anchor_bottom = 1.0
	add_child(nav_bar)
	var bg := Panel.new()
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UITheme.style("navbar"))
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.offset_left = -4
	bg.offset_right = 4
	bg.offset_bottom = 4
	nav_bar.add_child(bg)
	var row := Kit.hbox(0)
	row.anchor_right = 1.0
	row.offset_left = 6
	row.offset_right = -6
	row.offset_top = 2
	row.offset_bottom = NAV_H
	nav_bar.add_child(row)
	for t: Array in TABS:
		var tab := NavTab.new()
		var id: String = t[0]
		tab.setup(id, t[1], id)
		tab.pressed.connect(func() -> void:
			if UI.current_name != id:
				UI.sfx("tap")
				UI.go(id))
		row.add_child(tab)
		_tabs[id] = tab


# ------------------------------------------------------------------ layout

## Called by UI.set_chrome.
func apply_chrome(_show_top: bool, _show_nav: bool) -> void:
	_layout()
	# Deferred: go() shows the chrome before a full-screen screen hides it again.
	_flush_held_toasts.call_deferred()


func _layout() -> void:
	if top_bar == null:
		return
	var st := UI.safe_top()
	var sb := UI.safe_bottom()
	top_bar.visible = UI.chrome_top
	top_bar.offset_top = 0
	top_bar.offset_bottom = st + TOP_H
	_top_margin.add_theme_constant_override("margin_top", int(st))
	nav_bar.visible = UI.chrome_nav
	nav_bar.offset_top = -(NAV_H + sb)
	nav_bar.offset_bottom = 0
	content.offset_top = (st + TOP_H) if UI.chrome_top else 0.0
	content.offset_bottom = -(NAV_H + sb) if UI.chrome_nav else 0.0
	# Below a sub-screen's header row (back button, title), so toasts never hide it.
	toast_box.offset_top = (st + TOP_H if UI.chrome_top else st) + TOAST_GAP


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	for id: String in _chips:
		Kit.set_chip_amount(_chips[id], int(Game.currency(id)))
	var p := int(Game.team_power())
	if p != _power_value:
		if _power_value >= 0 and _power_label.is_inside_tree():
			Kit.count_to(_power_label, _power_value, p, 0.6)
			Kit.pulse(_power_chip, 1.06)
		else:
			_power_label.text = Kit.format_num(p)
		_power_value = p
	_refresh_dots()


func _refresh_dots() -> void:
	if _tabs.is_empty():
		return
	var quest_ready := false
	var qs: Variant = Game.quests()
	if qs is Array:
		for q: Variant in qs:
			if q is Dictionary and not bool(q.get("claimed", false)) and int(q.get("progress", 0)) >= int(q.get("goal", 1)):
				quest_ready = true
				break
	(_tabs["quests"] as NavTab).set_dot(quest_ready)
	(_tabs["summon"] as NavTab).set_dot(bool(Game.free_pull_available()))
	var idle: Variant = Game.idle_status()
	(_tabs["home"] as NavTab).set_dot(idle is Dictionary and bool((idle as Dictionary).get("full", false)))
	_refresh_guide()


## First-session guidance on the nav: point at the tab that leads to the suggested step,
## unless the player is already on a screen that shows it.
func _refresh_guide() -> void:
	var step := Guide.step()
	var here := UI.current_name
	var tab := ""
	match step:
		"claim":
			tab = "" if here == "home" else "home"
		"summon":
			tab = "" if here == "summon" else "summon"
		"formation":
			tab = "" if here in ["home", "heroes", "formation"] else "heroes"
		"level":
			tab = "" if here in ["heroes", "hero_detail"] else "heroes"
		"quests":
			tab = "" if here == "quests" else "quests"
		"battle":
			tab = "" if here in ["home", "campaign", "battle"] else "home"
	# Ring only: an arrow above the nav would cover the screen's bottom buttons.
	for id: String in _tabs:
		Guide.mark(_tabs[id] as Control, id == tab, 0)


## Global feedback for one-shot Game events that can happen on any screen. During full-screen
## moments (chrome hidden: battle, summon reveal) the toast waits until the chrome is back, so
## it never covers a Victory banner or summon results.
func _on_notify(event: Dictionary) -> void:
	var msg := ""
	match str(event.get("type", "")):
		"quest_ready":
			msg = "Quest complete: %s" % str(event.get("title", ""))
		"monthly_card":
			msg = "Monthly Card: +%s gems" % Kit.format_full(int(event.get("gems", 0)))
	if msg != "":
		# Deferred: an action that starts a full-screen moment (a summon) hides the chrome
		# right after the Game call that produced this event.
		_toast_or_hold.call_deferred(msg)
	_refresh_dots()


func _toast_or_hold(msg: String) -> void:
	if UI.chrome_top:
		UI.toast(msg, "good")
	elif not _held_toasts.has(msg):
		_held_toasts.append(msg)


func _flush_held_toasts() -> void:
	if not UI.chrome_top or _held_toasts.is_empty():
		return
	for msg in _held_toasts:
		UI.toast(msg, "good")
	_held_toasts.clear()


func _on_screen_changed(screen: String) -> void:
	var active := UI.nav_tab_for(screen)
	for id: String in _tabs:
		(_tabs[id] as NavTab).set_active(id == active)
	_refresh_dots()


# ------------------------------------------------------------------ screenshots

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for a in args:
		if a.begins_with("--shoot="):
			_shoot["screen"] = a.substr("--shoot=".length())
		elif a.begins_with("--shoot-out="):
			_shoot["out"] = a.substr("--shoot-out=".length())
		elif a.begins_with("--shoot-params="):
			var j: Variant = JSON.parse_string(a.substr("--shoot-params=".length()))
			if j is Dictionary:
				_shoot["params"] = j
			else:
				push_warning("--shoot-params is not a JSON object: " + a)
		elif a.begins_with("--shoot-wait="):
			_shoot["wait"] = a.substr("--shoot-wait=".length()).to_float()
		elif a == "--safe-area-sim":
			UI.safe_override = Vector2(108, 62)


func _run_shoot() -> void:
	var screen: String = _shoot["screen"]
	if UI.SCREENS.has(screen):
		UI.go(screen, _shoot.get("params", {}))
	else:
		push_error("--shoot: unknown screen '%s'" % screen)
		UI.go("home")
	await get_tree().create_timer(float(_shoot.get("wait", 1.0))).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out: String = _shoot.get("out", "user://shot.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	print("[shoot] %s -> %s (%dx%d) %s" % [screen, out, img.get_width(), img.get_height(), error_string(err)])
	UI.release_audio()
	# Give the audio thread a moment to drop its playbacks (else they leak at exit).
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if err == OK else 1)
