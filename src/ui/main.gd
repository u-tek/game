extends Control
## App root (style v2, docs/dev/ui-style-v2.md): backdrop, top bar (leader avatar with the
## team power chip, the resource pill, quests / notices / menu), the content area where
## screens mount, the bottom nav (Heroes, Team, Lobby as a raised hexagon, Gear, Summon),
## toast and modal layers. Registers itself with the UI autoload and refreshes on
## Game.changed.
##
## Chrome: solid dark bars around normal screens; when a screen calls
## UI.set_full_bleed(true) (the lobby) it fills the window and the bars turn into
## translucent gradients over its art. UI.set_chrome() hides either bar (battle, summon).
##
## Screenshot mode (docs/dev/architecture.md section 1), args after "--":
##   --shoot=<screen> --shoot-out=<png> --shoot-params=<json> --shoot-wait=<s>
##   --safe-area-sim  (108 px top / 62 px bottom insets, like a notched iPhone)

const Backdrop := preload("res://src/ui/components/backdrop.gd")
const NavTab := preload("res://src/ui/components/nav_tab.gd")

## Heights of the chrome bars, not counting the safe-area insets.
const TOP_H := 104.0
const NAV_H := 120.0
## How far the raised Lobby hexagon (and its glow) pokes up above the nav bar. Bars pinned to
## the bottom of a screen's content keep this much clear (UI.pinned_bottom_inset()).
const NAV_RISE := 26.0
## Toasts start this far below the top of the content area (clear of screen headers).
const TOAST_GAP := 112.0
## [screen id, label, icon]; the middle one is the raised Lobby hexagon.
const TABS := [
	["heroes", "Heroes", "nav_heroes"], ["formation", "Team", "nav_team"], ["home", "Lobby", "nav_lobby"],
	["gear", "Gear", "nav_gear"], ["summon", "Summon", "nav_summon"],
]
const DEFAULT_CURRENCIES: Array[String] = ["gems", "gold"]

## Where screens are mounted (UI.go adds them here).
var content: Control
## Toasts stack here (UI.toast).
var toast_box: VBoxContainer
## Modals are added here (UI.modal / popup / confirm / show_reward).
var modal_layer: Control
var backdrop: Control
var top_bar: Control
var nav_bar: Control

var _top_bg: Panel
var _nav_bg: Panel
var _top_margin: MarginContainer
var _top_row: HBoxContainer
var _avatar: Button
var _avatar_art: TextureRect
var _leader_id := "-"
var _power_chip: PanelContainer
var _power_label: Label
var _power_value := -1
var _pill: PanelContainer
var _pill_ids: Array = []
var _quests_btn: Button
var _bell_btn: Button
var _menu_btn: Button
var _tabs: Dictionary = {}
var _shoot: Dictionary = {}
var _held_toasts: Array[String] = []
var _bleed := false


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


## Chrome bar heights (x = top bar, y = nav) without the safe-area insets (UI.content_top).
func bar_heights() -> Vector2:
	return Vector2(TOP_H, NAV_H)


## Height of the Lobby hexagon above the nav bar (see UI.pinned_bottom_inset).
func nav_rise() -> float:
	return NAV_RISE


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
	top_bar.mouse_filter = MOUSE_FILTER_IGNORE
	top_bar.anchor_right = 1.0
	add_child(top_bar)
	_top_bg = Panel.new()
	_top_bg.name = "Bg"
	_top_bg.mouse_filter = MOUSE_FILTER_IGNORE
	_top_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_top_bg.offset_left = -4
	_top_bg.offset_right = 4
	_top_bg.offset_top = -4
	top_bar.add_child(_top_bg)

	_top_margin = MarginContainer.new()
	_top_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_top_margin.mouse_filter = MOUSE_FILTER_IGNORE
	_top_margin.add_theme_constant_override("margin_left", 10)
	_top_margin.add_theme_constant_override("margin_right", 10)
	_top_margin.add_theme_constant_override("margin_bottom", 4)
	top_bar.add_child(_top_margin)
	_top_row = Kit.hbox(8)
	_top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_row.mouse_filter = MOUSE_FILTER_IGNORE
	_top_margin.add_child(_top_row)

	# Leader avatar with the team power chip: tap to open the team.
	_avatar = Kit.avatar("", 70, "", func() -> void: UI.go("formation"))
	_avatar.name = "Avatar"
	_avatar.size_flags_vertical = SIZE_SHRINK_CENTER
	_avatar.custom_minimum_size = Vector2(88, 96)
	var frame := _avatar.get_meta("frame") as Control
	_avatar_art = TextureRect.new()
	_avatar_art.name = "Art"
	_avatar_art.mouse_filter = MOUSE_FILTER_IGNORE
	_avatar_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_avatar_art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_avatar_art.offset_left = 3
	_avatar_art.offset_top = 3
	_avatar_art.offset_right = -3
	_avatar_art.offset_bottom = -3
	frame.add_child(_avatar_art)
	_power_chip = PanelContainer.new()
	_power_chip.name = "Power"
	_power_chip.mouse_filter = MOUSE_FILTER_IGNORE
	_power_chip.add_theme_stylebox_override("panel", UITheme.style("power_chip"))
	var prow := Kit.hbox(2)
	prow.mouse_filter = MOUSE_FILTER_IGNORE
	prow.add_child(Kit.icon("power", 20))
	_power_label = Kit.label("0", 19, Color.WHITE, "cond_bold")
	prow.add_child(_power_label)
	_power_chip.add_child(prow)
	_power_chip.anchor_left = 0.5
	_power_chip.anchor_right = 0.5
	_power_chip.grow_horizontal = GROW_DIRECTION_BOTH
	_power_chip.offset_top = 62
	(_avatar.get_node("Face") as Control).add_child(_power_chip)
	_top_row.add_child(_avatar)

	_rebuild_pill(DEFAULT_CURRENCIES)

	# Right cluster: quests, notices, menu in one dark glass box.
	var cluster := PanelContainer.new()
	cluster.name = "Cluster"
	cluster.mouse_filter = MOUSE_FILTER_PASS
	var csb := UITheme.style("chip")
	csb.set("draw_inset", Vector2(0, 12))
	csb.content_margin_left = 0
	csb.content_margin_right = 0
	csb.content_margin_top = 0
	csb.content_margin_bottom = 0
	cluster.add_theme_stylebox_override("panel", csb)
	cluster.size_flags_vertical = SIZE_SHRINK_CENTER
	var crow := Kit.hbox(0)
	_quests_btn = _cluster_button("quests", func() -> void: UI.go("quests"))
	_bell_btn = _cluster_button("bell", _open_notices)
	_menu_btn = _cluster_button("menu", _open_menu)
	Kit.add(crow, [_quests_btn, _bell_btn, _menu_btn])
	cluster.add_child(crow)
	_top_row.add_child(cluster)


func _cluster_button(icon_name: String, cb: Callable) -> Button:
	var b := Kit.icon_button(icon_name, cb, 76, "bare")
	b.name = "Top_" + icon_name.capitalize()
	b.custom_minimum_size = Vector2(Kit.BUTTON_H, Kit.BUTTON_H)
	var g := b.get_node("Glyph") as Control
	g.modulate = Color(1, 1, 1, 0.92)
	return b


## (Re)builds the resource pill for a list of currency ids.
func _rebuild_pill(ids: Array) -> void:
	if ids == _pill_ids and _pill and is_instance_valid(_pill):
		return
	var at := -1
	if _pill and is_instance_valid(_pill):
		at = _pill.get_index()
		_pill.queue_free()
		_top_row.remove_child(_pill)
	_pill_ids = ids.duplicate()
	var entries: Array = []
	for id: Variant in ids:
		var sid := str(id)
		var cb := Callable()
		match sid:
			"gems", "gold":
				cb = func() -> void: UI.go("shop")
			"scrolls":
				cb = func() -> void: UI.go("summon")
		entries.append({"id": sid, "amount": int(Game.currency(sid)), "on_plus": cb})
	_pill = Kit.resource_pill(entries, 120.0)
	_pill.size_flags_horizontal = SIZE_EXPAND_FILL
	_pill.size_flags_vertical = SIZE_SHRINK_CENTER
	var psb := UITheme.style("chip")
	psb.set("draw_inset", Vector2(0, 12))
	psb.content_margin_top += 12
	psb.content_margin_bottom += 12
	_pill.add_theme_stylebox_override("panel", psb)
	_pill.custom_minimum_size.y = Kit.BUTTON_H
	_top_row.add_child(_pill)
	_top_row.move_child(_pill, at if at >= 0 else 1)


func _build_nav() -> void:
	nav_bar = Control.new()
	nav_bar.name = "NavBar"
	nav_bar.mouse_filter = MOUSE_FILTER_IGNORE
	nav_bar.anchor_top = 1.0
	nav_bar.anchor_right = 1.0
	nav_bar.anchor_bottom = 1.0
	add_child(nav_bar)
	_nav_bg = Panel.new()
	_nav_bg.name = "Bg"
	_nav_bg.mouse_filter = MOUSE_FILTER_STOP
	_nav_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_nav_bg.offset_left = -4
	_nav_bg.offset_right = 4
	_nav_bg.offset_bottom = 4
	nav_bar.add_child(_nav_bg)
	var row := Kit.hbox(0)
	row.name = "Tabs"
	row.anchor_right = 1.0
	row.offset_left = 4
	row.offset_right = -4
	row.offset_top = 4
	row.offset_bottom = NAV_H
	nav_bar.add_child(row)
	for t: Array in TABS:
		var tab := NavTab.new()
		var id: String = t[0]
		tab.setup(id, t[1], t[2], id == "home")
		tab.pressed.connect(func() -> void:
			if UI.current_name != id:
				UI.sfx("tap")
				UI.go(id))
		row.add_child(tab)
		_tabs[id] = tab


# ------------------------------------------------------------------ layout

## Called by UI.set_chrome / UI.set_full_bleed.
func apply_chrome(_show_top: bool, _show_nav: bool) -> void:
	_layout()
	# Deferred: go() shows the chrome before a full-screen screen hides it again.
	_flush_held_toasts.call_deferred()


func _layout() -> void:
	if top_bar == null:
		return
	var st := UI.safe_top()
	var sb := UI.safe_bottom()
	var bleed := UI.full_bleed
	if bleed != _bleed or not _top_bg.has_theme_stylebox_override("panel"):
		_bleed = bleed
		_top_bg.add_theme_stylebox_override("panel", UITheme.style("topbar_clear" if bleed else "topbar"))
		_nav_bg.add_theme_stylebox_override("panel", UITheme.style("navbar_clear" if bleed else "navbar"))
	top_bar.visible = UI.chrome_top
	top_bar.offset_top = 0
	top_bar.offset_bottom = st + TOP_H
	_top_margin.add_theme_constant_override("margin_top", int(st))
	nav_bar.visible = UI.chrome_nav
	nav_bar.offset_top = -(NAV_H + sb)
	nav_bar.offset_bottom = 0
	content.offset_top = (st + TOP_H) if UI.chrome_top and not bleed else 0.0
	content.offset_bottom = -(NAV_H + sb) if UI.chrome_nav and not bleed else 0.0
	# Below a sub-screen's header row (back button, title), so toasts never hide it.
	toast_box.offset_top = (st + TOP_H if UI.chrome_top else st) + TOAST_GAP


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if _pill:
		var map: Dictionary = _pill.get_meta("entries", {})
		for id: Variant in map:
			Kit.set_chip_amount(map[id], int(Game.currency(str(id))))
	var p := int(Game.team_power())
	if p != _power_value:
		if _power_value >= 0 and _power_label.is_inside_tree():
			Kit.count_to(_power_label, _power_value, p, 0.6)
			Kit.pulse(_power_chip, 1.08)
		else:
			_power_label.text = Kit.format_num(p)
		_power_value = p
	_refresh_avatar()
	_refresh_dots()


func _refresh_avatar() -> void:
	var lead := ""
	var f: Variant = Game.formation()
	if f is Array:
		for id: Variant in f:
			if str(id) != "":
				lead = str(id)
				break
	if lead == "":
		var owned: Variant = Game.owned_heroes()
		if owned is Array and not (owned as Array).is_empty():
			lead = str(((owned as Array)[0] as Dictionary).get("id", ""))
	if lead == _leader_id:
		return
	_leader_id = lead
	_avatar_art.texture = Kit.art_crop(lead, 1.0, 1.7) if lead != "" else null


func _refresh_dots() -> void:
	if _tabs.is_empty():
		return
	(_tabs["summon"] as NavTab).set_dot(bool(Game.free_pull_available()))
	var idle: Variant = Game.idle_status()
	(_tabs["home"] as NavTab).set_dot(idle is Dictionary and bool((idle as Dictionary).get("full", false)))
	var lvl := false
	for id: Variant in Game.formation():
		if str(id) != "" and bool(Game.upgrade_ready(str(id))):
			lvl = true
			break
	(_tabs["heroes"] as NavTab).set_dot(lvl)
	(_tabs["formation"] as NavTab).set_dot(Guide.formation_can_improve())
	Kit.set_dot(_quests_btn, int(Game.quests_ready_count()) > 0, 18.0, Vector2(12, 14))
	Kit.set_dot(_bell_btn, not _notices().is_empty(), 18.0, Vector2(12, 14))
	_refresh_guide()


## First-session guidance on the chrome: point at the nav tab (or the top-bar quests
## button) that leads to the suggested step, unless the player is already on a screen
## that shows it.
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
			tab = "" if here in ["home", "formation"] else "formation"
		"level":
			tab = "" if here in ["heroes", "hero_detail"] else "heroes"
		"battle":
			tab = "" if here in ["home", "campaign", "battle"] else "home"
	# Ring only: an arrow above the nav would cover the screen's bottom buttons.
	for id: String in _tabs:
		Guide.mark(_tabs[id] as Control, id == tab, 0)
	Guide.mark(_quests_btn, step == "quests" and here != "quests", 0)


## Things worth a tap right now (the bell): [{text, icon, screen}].
func _notices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var qn := int(Game.quests_ready_count())
	if qn > 0:
		out.append({"text": "%d quest reward%s to claim" % [qn, "" if qn == 1 else "s"], "icon": "quests", "screen": "quests"})
	if bool(Game.free_pull_available()):
		out.append({"text": "Your free daily summon is ready", "icon": "summon", "screen": "summon"})
	var idle: Variant = Game.idle_status()
	if idle is Dictionary and bool((idle as Dictionary).get("full", false)):
		out.append({"text": "The Sanctum is full: collect it", "icon": "sanctum", "screen": "home"})
	if Guide.formation_can_improve():
		out.append({"text": "Your team can be stronger", "icon": "team", "screen": "formation"})
	for id: Variant in Game.formation():
		if str(id) != "" and bool(Game.upgrade_ready(str(id))):
			out.append({"text": "A team hero can level up", "icon": "upgrade", "screen": "heroes"})
			break
	return out


func _open_notices() -> void:
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 560
	var items := _notices()
	var m_ref: Array[Control] = []
	if items.is_empty():
		col.add_child(Kit.empty_state("All caught up.", "check", true))
	for n: Dictionary in items:
		var row := Kit.panel("row", 10)
		var h := Kit.hbox(14)
		h.mouse_filter = MOUSE_FILTER_IGNORE
		h.add_child(Kit.hex_badge(str(n.icon), 52, Kit.ACCENT, Color.WHITE))
		var l := Kit.label(str(n.text), 25, Kit.TEXT, "bold")
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(Kit.icon("chevron_right", 30, Kit.TEXT_DIM))
		row.add_child(h)
		row.custom_minimum_size.y = Kit.BUTTON_H
		var screen := str(n.screen)
		Kit.make_tappable(row, func() -> void:
			if not m_ref.is_empty():
				UI.close_modal(m_ref[0])
			UI.go(screen))
		col.add_child(row)
	m_ref.append(UI.popup("Notices", col, Callable(), 620.0, true))


func _open_menu() -> void:
	var g := Kit.grid(2, 12)
	g.custom_minimum_size.x = 560
	var entries := [
		["Campaign", "campaign", "campaign"], ["Quests", "quests", "quests"], ["Shop", "shop", "shop"],
		["Settings", "settings", "settings"], ["Heroes", "heroes", "heroes"], ["Team", "team", "formation"],
		["Gear", "gear", "gear"], ["Summon", "summon", "summon"],
	]
	if OS.is_debug_build():
		entries.append(["Kit Preview", "info", "kit_demo"])
	var m_ref: Array[Control] = []
	for e: Array in entries:
		var screen: String = e[2]
		var b := Kit.light_button(e[0], func() -> void:
			if not m_ref.is_empty():
				UI.close_modal(m_ref[0])
			UI.go(screen), e[1])
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		g.add_child(b)
	m_ref.append(UI.popup("Menu", g, Callable(), 620.0, true))


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
	var cur: Variant = UI.TOP_CURRENCIES.get(screen, DEFAULT_CURRENCIES)
	_rebuild_pill(cur as Array)
	_refresh()


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
