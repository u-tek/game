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
## Launch: when this is the running main scene, a boot screen (BootScreen) covers the first
## frames while the lobby builds, then lifts and the lobby plays its intro. Test scripts that
## add main.tscn themselves skip it.
##
## Screenshot mode (docs/dev/architecture.md section 1), args after "--":
##   --shoot=<screen> --shoot-out=<png> --shoot-params=<json> --shoot-wait=<s>
##   --safe-area-sim  (108 px top / 62 px bottom insets, like a notched iPhone)
##   --shoot=boot                 the boot screen (held), --shoot-from=<screen> opens that
##   screen first and navigates after 0.6 s (catch a transition with a short --shoot-wait),
##   --shoot-do=toast|confirm|reward|veil  opens one of those over the screen.

const Backdrop := preload("res://src/ui/components/backdrop.gd")
const NavTab := preload("res://src/ui/components/nav_tab.gd")
const BootScreen := preload("res://src/ui/components/boot_screen.gd")

## Heights of the chrome bars, not counting the safe-area insets.
const TOP_H := 104.0
const NAV_H := 120.0
## How far the raised Lobby hexagon (and its glow) pokes up above the nav bar. Bars pinned to
## the bottom of a screen's content keep this much clear (UI.pinned_bottom_inset()).
const NAV_RISE := 0.0
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
## Toasts stack here (UI.toast lays them out itself).
var toast_box: Control
## Modals are added here (UI.modal / popup / confirm / show_reward).
var modal_layer: Control
## Effects over everything (currencies flying to the wallet).
var fx_layer: Control
var backdrop: Control
var top_bar: Control
var nav_bar: Control
## > 0 while a reward popup is open: the wallet keeps its old amounts (hold_currency).
var currency_hold := 0

var _top_bg: Panel
var _nav_bg: Panel
var _top_margin: MarginContainer
var _top_row: HBoxContainer
var _avatar: Button
var _avatar_art: TextureRect
var _leader_key := "-"     ## HeroArt.art_key of the avatar art shown
var _power_chip: PanelContainer
var _power_label: Label
var _power_value := -1
var _pill: PanelContainer
var _pill_ids: Array = []
var _quests_btn: Button
var _bell_btn: Button
var _menu_btn: Button
var _tabs: Dictionary = {}
var _nav_ink: ColorRect
var _ink_tab := ""
var _shoot: Dictionary = {}
var _held_toasts: Array[String] = []
var _bleed := false
var _veil: Control
var _veil_tw: Tween
var _chrome_shown := Vector2i(-1, -1)


## Style v4 "Signal" lighting: HDR 2D bloom (WorldEnvironment glow over the canvas; emissive UI
## colours above 1.0 bloom) and the "ui_tilt" shader global the metal plates reflect their studio by.
## On a phone the tilt follows how the device moves (a high-passed gravity vector); elsewhere it
## drifts slowly so reflections stay alive.
var _tilt := Vector2.ZERO
var _grav_base := Vector3.ZERO
var _tilt_t := 0.0


## The screen as an sRGB image. With HDR 2D the viewport texture holds linear colour, so it is
## converted the way the display does it (values above 1.0 clip, as on screen).
func _capture() -> Image:
	var img := get_viewport().get_texture().get_image()
	if get_viewport().use_hdr_2d and img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		# Image.linear_to_srgb only takes 8-bit images (that would band the darks): convert the
		# float data here (a few seconds; screenshots only).
		img.convert(Image.FORMAT_RGBAF)
		var f := img.get_data().to_float32_array()
		for i in f.size():
			if i % 4 == 3:
				continue
			var c := clampf(f[i], 0.0, 1.0)
			f[i] = c * 12.92 if c < 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBAF, f.to_byte_array())
		img.convert(Image.FORMAT_RGBA8)
	return img


func _setup_light() -> void:
	# The v4 shaders work in sRGB numbers and convert to the canvas at the end: linear when HDR 2D is
	# on, as is when it is off (an LDR build or a platform override). Without HDR there is no bloom.
	var hdr := get_viewport().use_hdr_2d
	RenderingServer.global_shader_parameter_set(&"ui_linear", 1.0 if hdr else 0.0)
	if not hdr:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _process(delta: float) -> void:
	_tilt_t += delta
	var g := Input.get_gravity()
	var want := Vector2.ZERO
	if g.length_squared() > 0.01:
		if _grav_base == Vector3.ZERO:
			_grav_base = g
		_grav_base = _grav_base.lerp(g, clampf(delta * 0.6, 0.0, 1.0))
		var d := (g - _grav_base) / 9.8
		want = Vector2(d.x, -d.y) * 2.2
	elif Kit.motion_ok():
		want = Vector2(sin(_tilt_t * 0.31), cos(_tilt_t * 0.23)) * 0.12
	_tilt = _tilt.lerp(want.limit_length(0.6), clampf(delta * 6.0, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"ui_tilt", _tilt)


func _ready() -> void:
	_parse_args()
	if _shoot.has("screen"):
		_size_shot_window()
	theme = UITheme.get_theme()
	get_tree().root.theme = theme
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_setup_light()
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
	elif get_tree().current_scene == self:
		_boot()
	else:
		UI.go("home")


## Launch: the boot screen covers the first frames while caches warm up and the lobby builds,
## then fills its bar and lifts; the lobby's intro plays as it does. hold = stay up (shots).
func _boot(hold: bool = false) -> void:
	var boot := BootScreen.new()
	# Over everything, popups included, until it lifts.
	boot.z_index = 200
	add_child(boot)
	var t0 := Time.get_ticks_msec()
	UI.hold_intro = true
	boot.set_progress(0.15)
	await get_tree().process_frame
	await get_tree().process_frame
	# Warm the art and glyphs the lobby and the chrome use first.
	for id: Variant in Game.formation():
		if str(id) != "":
			Kit.art_crop(str(id), 1.0, 1.7)
	boot.set_progress(0.45)
	await get_tree().process_frame
	if UI.current_name == "":
		UI.go("home")
	boot.set_progress(0.85)
	await get_tree().process_frame
	if hold:
		return
	# Long enough to read as a deliberate splash, never a flash.
	var left := 1.25 - float(Time.get_ticks_msec() - t0) / 1000.0
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	if not is_instance_valid(boot):
		UI.play_intro()
		return
	boot.finish(func() -> void: UI.play_intro())


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
	# Draw order: screens may raise pieces inside themselves (a pass's silver plate, a card's tag), so
	# the shell's layers sit above any screen content: bars, then toasts, popups and effects.
	top_bar.z_index = 60
	nav_bar.z_index = 60

	# A zero-width column at the centre line: UI.toast places (and restacks) toasts in it.
	toast_box = Control.new()
	toast_box.name = "Toasts"
	toast_box.mouse_filter = MOUSE_FILTER_IGNORE
	toast_box.z_index = 90
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.grow_horizontal = GROW_DIRECTION_BOTH
	add_child(toast_box)

	modal_layer = Control.new()
	modal_layer.name = "Modals"
	modal_layer.z_index = 100
	modal_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	modal_layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(modal_layer)

	fx_layer = Control.new()
	fx_layer.name = "Fx"
	fx_layer.z_index = 110
	fx_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	fx_layer.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(fx_layer)


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
	# The player's avatar opens their profile (owner, 2026-10-19).
	_avatar = Kit.avatar("", 70, "", func() -> void: UI.go("profile"))
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
	cluster.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
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
	g.modulate = Color(SignalKit.INK, 0.9)
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
	var psb := StyleBoxEmpty.new()
	psb.content_margin_top = 12
	psb.content_margin_bottom = 12
	_pill.add_theme_stylebox_override("panel", psb)
	# Printed readouts: ink mono amounts, ink plus marks, hairline separators.
	var map: Dictionary = _pill.get_meta("entries", {})
	for cid: Variant in map:
		var cell := map[cid] as Control
		var amt := cell.get_meta("amount_label") as Label
		amt.add_theme_font_override("font", Kit.font("mono_bold"))
		amt.add_theme_font_size_override("font_size", 21)
		amt.add_theme_color_override("font_color", SignalKit.INK)
		var icons := cell.find_children("*", "TextureRect", true, false)
		for k in range(1, icons.size()):
			(icons[k] as CanvasItem).modulate = Color(SignalKit.INK, 0.75)
	for sep in _pill.find_children("*", "ColorRect", true, false):
		(sep as ColorRect).color = Color(SignalKit.INK, 0.18)
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
	var n := 0
	for t: Array in TABS:
		n += 1
		var tab := NavTab.new()
		var id: String = t[0]
		tab.shared_ink = true
		tab.setup(id, "%02d %s" % [n, t[1]], t[2], id == "home")
		tab.pressed.connect(func() -> void:
			if UI.current_name != id:
				UI.sfx("tab")
				UI.haptic(10, 0.35)
				UI.go(id))
		row.add_child(tab)
		_tabs[id] = tab
	# One signal underline under the active tab's label that slides from tab to tab.
	_nav_ink = ColorRect.new()
	_nav_ink.name = "Ink"
	_nav_ink.color = SignalKit.SIGNAL
	_nav_ink.mouse_filter = MOUSE_FILTER_IGNORE
	_nav_ink.size = Vector2(44, 3)
	_nav_ink.position = Vector2(0, 4.0 + 84.0)
	_nav_ink.modulate.a = 0.0
	nav_bar.add_child(_nav_ink)


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
		# Style v4: the masthead and footer strip are printed on the paper matte (the poster look),
		# with a hairline rule against the page.
		_top_bg.add_theme_stylebox_override("panel", _paper_strip(false))
		_nav_bg.add_theme_stylebox_override("panel", _paper_strip(true))
	_show_bar(top_bar, UI.chrome_top, 0)
	top_bar.offset_top = 0
	top_bar.offset_bottom = st + TOP_H
	_top_margin.add_theme_constant_override("margin_top", int(st))
	_show_bar(nav_bar, UI.chrome_nav, 1)
	nav_bar.offset_top = -(NAV_H + sb)
	nav_bar.offset_bottom = 0
	content.offset_top = (st + TOP_H) if UI.chrome_top and not bleed else 0.0
	content.offset_bottom = -(NAV_H + sb) if UI.chrome_nav and not bleed else 0.0
	# Below a sub-screen's header row (back button, title), so toasts never hide it.
	toast_box.offset_top = (st + TOP_H if UI.chrome_top else st) + TOAST_GAP
	_place_ink.call_deferred(false)


func _paper_strip(rule_on_top: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SignalKit.MATTE
	sb.border_color = Color(SignalKit.INK, 0.18)
	if rule_on_top:
		sb.border_width_top = 1
	else:
		sb.border_width_bottom = 1
	return sb


## Shows or hides a chrome bar: hiding is instant (full-screen moments), coming back fades
## it in. which: 0 top bar, 1 nav.
func _show_bar(bar: Control, on: bool, which: int) -> void:
	var was: int = _chrome_shown[which]
	_chrome_shown[which] = 1 if on else 0
	bar.visible = on
	if on and was == 0 and Kit.motion_ok():
		bar.modulate.a = 0.0
		bar.create_tween().tween_property(bar, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	elif on and was != 0:
		bar.modulate.a = 1.0


## Puts the nav's white bar over the active tab (sliding there when animate), or fades it
## out on the Lobby hexagon.
func _place_ink(animate: bool) -> void:
	if _nav_ink == null or _tabs.is_empty():
		return
	var id := _ink_tab
	var tab: Control = _tabs.get(id, null)
	if tab == null:
		_nav_ink.modulate.a = 0.0
		return
	var x := _ink_x(tab)
	Kit._kill_tween(_nav_ink, "_tw")
	if animate and Kit.motion_ok() and _nav_ink.modulate.a > 0.01:
		var tw2 := _nav_ink.create_tween().set_parallel(true)
		tw2.tween_property(_nav_ink, "position:x", x, 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_nav_ink, "modulate:a", 1.0, 0.15)
		_nav_ink.set_meta("_tw", tw2)
	else:
		_nav_ink.position.x = x
		_nav_ink.modulate.a = 1.0


func _ink_x(tab: Control) -> float:
	return tab.global_position.x - nav_bar.global_position.x + tab.size.x * 0.5 - _nav_ink.size.x * 0.5


# ------------------------------------------------------------------ refresh

## Freezes (on) or releases (off) the wallet's amounts; on the last release it counts to the
## real values. UI.show_reward holds it while a reward popup is open.
func hold_currency(on: bool) -> void:
	currency_hold = maxi(0, currency_hold + (1 if on else -1))
	if currency_hold == 0:
		_refresh()


## Currency icons fly from screen points to their wallet entries. sources: [{id, from
## (global px), amount}]. `landed` runs when the first one arrives (or at once when none can
## fly); each landing pops the entry with a ting.
func fly_currency(sources: Array[Dictionary], landed: Callable) -> void:
	var map: Dictionary = _pill.get_meta("entries", {}) if _pill else {}
	var flights: Array[Dictionary] = []
	for s: Dictionary in sources:
		var id := str(s.get("id", ""))
		if map.has(id) and top_bar.visible:
			flights.append(s)
	if flights.is_empty():
		landed.call()
		return
	var state := {"first": true, "n": 0}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var k := 0
	for s: Dictionary in flights:
		var id := str(s.id)
		var cell := map[id] as Control
		var icon_node := _cell_icon(cell)
		var to: Vector2 = (icon_node.get_global_rect().get_center() if icon_node else cell.get_global_rect().get_center())
		# The wallet may be rebuilt (another screen) before they land: hold it weakly.
		var icon_ref: WeakRef = weakref(icon_node)
		var from: Vector2 = s.from
		var count := clampi(3 + int(log(maxf(float(s.get("amount", 1)), 1.0)) / log(10.0)), 3, 7)
		for i in count:
			var ic := Kit.icon(id, 46)
			ic.size = Vector2(46, 46)
			ic.pivot_offset = Vector2(23, 23)
			ic.position = from - Vector2(23, 23)
			ic.scale = Vector2(0.5, 0.5)
			fx_layer.add_child(ic)
			var burst := from + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 90.0)
			var delay := k * 0.05
			var tw := ic.create_tween()
			tw.tween_interval(delay)
			tw.tween_property(ic, "position", burst - Vector2(23, 23), 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(ic, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(ic, "position", to - Vector2(23, 23), 0.46).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(ic, "scale", Vector2(0.62, 0.62), 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			var pitch := 1.0 + 0.05 * k
			tw.tween_callback(func() -> void:
				if state.first:
					state.first = false
					landed.call()
				state.n = int(state.n) + 1
				UI.sfx("coin", pitch)
				var target := icon_ref.get_ref() as Control if icon_ref else null
				if target:
					Kit.pulse(target, 1.3)
				ic.queue_free())
			k += 1


## The currency glyph inside a wallet entry (its first TextureRect).
func _cell_icon(cell: Control) -> Control:
	for n in cell.find_children("*", "TextureRect", true, false):
		return n as Control
	return null


## The full-screen loading veil (UI.busy / UI.idle), style v4 print (Kit.loading_veil): a dark band
## with a red halftone ramp, the caption in big compressed type and a printed rule that runs.
func show_veil(text: String) -> void:
	if _veil == null:
		_veil = Kit.loading_veil()
		_veil.name = "Veil"
		add_child(_veil)
	move_child(_veil, get_child_count() - 1)
	(_veil.find_child("Caption", true, false) as Label).text = text.to_upper()
	_veil.mouse_filter = MOUSE_FILTER_STOP
	_veil.visible = true
	if _veil_tw and _veil_tw.is_valid():
		_veil_tw.kill()
	_veil.modulate.a = 0.0
	_veil_tw = _veil.create_tween()
	_veil_tw.tween_property(_veil, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hide_veil() -> void:
	if _veil == null or not _veil.visible:
		return
	_veil.mouse_filter = MOUSE_FILTER_IGNORE
	if _veil_tw and _veil_tw.is_valid():
		_veil_tw.kill()
	_veil_tw = _veil.create_tween()
	_veil_tw.tween_interval(0.08)
	_veil_tw.tween_property(_veil, "modulate:a", 0.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_veil_tw.tween_callback(func() -> void: _veil.visible = false)


func _refresh() -> void:
	if _pill and currency_hold <= 0:
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
	# The portrait the player picked on their profile, else the team lead.
	var pick := ProfileScreen.avatar_hero()
	if pick != "":
		lead = pick
	# Keyed by what the art shows, so a new skin or the nudity toggle redraws it at once.
	var skin := Kit.hero_look(lead) if lead != "" else ""
	var key := HeroArt.art_key(lead, skin) if lead != "" else ""
	if key == _leader_key:
		return
	_leader_key = key
	_avatar_art.texture = Kit.art_crop(lead, 1.0, 1.7, skin) if lead != "" else null


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
	var moved := active != _ink_tab
	_ink_tab = active
	_place_ink(moved and nav_bar.is_visible_in_tree())
	var cur: Variant = UI.TOP_CURRENCIES.get(screen, DEFAULT_CURRENCIES)
	_rebuild_pill(cur as Array)
	_refresh()


# ------------------------------------------------------------------ screenshots

## tools/shoot on Windows opens the window where the owner parked it (override.cfg, never on the
## main monitor) and without focus. Windows shrinks a new window to fit its screen, so the
## requested --resolution is applied again here (the PNG is the viewport, not the screen).
func _size_shot_window() -> void:
	if OS.get_name() != "Windows":
		return
	var args := OS.get_cmdline_args()
	var i := args.find("--resolution")
	if i >= 0 and i + 1 < args.size():
		var p := args[i + 1].split("x")
		if p.size() == 2:
			DisplayServer.window_set_size(Vector2i(p[0].to_int(), p[1].to_int()))


## tools/shoot --place: keeps the window up so the owner can drag it where shots should open
## (another monitor) and saves its position every half second to `file` (tools/shoot reads it).
func _hold_for_placement(secs: float, file: String) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.065, 0.07, 0.86)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	fx_layer.add_child(bg)
	var note := Kit.label("", 40, Color.WHITE, "wide_black")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.add_child(note)
	var left := secs
	while left > 0.0:
		note.text = "DRAG THIS WINDOW\nwhere screenshots\nshould open\n\n%d" % ceili(left)
		if file != "":
			var f := FileAccess.open(file, FileAccess.WRITE)
			if f:
				var p := DisplayServer.window_get_position()
				f.store_string("%d,%d\n" % [p.x, p.y])
		await get_tree().create_timer(0.5).timeout
		left -= 0.5
	bg.queue_free()


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
		elif a.begins_with("--shoot-frames="):
			# motion checks: N frames, --shoot-every seconds apart, saved as <out>_0001.png ...
			_shoot["frames"] = a.substr("--shoot-frames=".length()).to_int()
		elif a.begins_with("--shoot-every="):
			_shoot["every"] = a.substr("--shoot-every=".length()).to_float()
		elif a.begins_with("--shoot-from="):
			_shoot["from"] = a.substr("--shoot-from=".length())
		elif a.begins_with("--shoot-do="):
			_shoot["do"] = a.substr("--shoot-do=".length())
		elif a.begins_with("--shoot-place="):
			_shoot["place"] = a.substr("--shoot-place=".length()).to_float()
		elif a.begins_with("--shoot-place-file="):
			_shoot["place_file"] = a.substr("--shoot-place-file=".length())
		elif a == "--ldr":
			# Render without HDR 2D (what an LDR platform shows; checks the shaders' sRGB path).
			get_viewport().use_hdr_2d = false
		elif a == "--safe-area-sim":
			UI.safe_override = Vector2(108, 62)


func _run_shoot() -> void:
	var screen: String = _shoot["screen"]
	if screen == "boot":
		_boot(true)
	elif UI.SCREENS.has(screen):
		var from := str(_shoot.get("from", ""))
		if from != "" and UI.SCREENS.has(from):
			UI.go(from)
			await get_tree().create_timer(0.6).timeout
		UI.go(screen, _shoot.get("params", {}))
	else:
		push_error("--shoot: unknown screen '%s'" % screen)
		UI.go("home")
	match str(_shoot.get("do", "")):
		"toast":
			UI.toast("Not enough gems", "bad")
			UI.toast("Quest complete: Win 3 battles", "good")
		"confirm":
			UI.confirm("Spend 300 gems to collect 2 hours of Sanctum rewards now?", Callable(), Callable(), "Spend 300")
		"reward":
			UI.show_reward("Stage Cleared!", {"gems": 300, "gold": 12500, "hero_exp": 2400, "scrolls": 1})
		"veil":
			UI.busy("Preparing battle")
		"poke", "poke4":
			await get_tree().create_timer(0.6).timeout
			if UI.current and UI.current.has_method("debug_poke"):
				UI.current.call("debug_poke", 4 if str(_shoot.get("do", "")) == "poke4" else 1)
		"shine":
			# Every glint on screen sweeps at once (to see them in a still).
			await get_tree().create_timer(0.8).timeout
			for n in find_children("Shine", "", true, false):
				if n.has_method("sweep_now"):
					n.call("sweep_now")
	if float(_shoot.get("place", 0.0)) > 0.0:
		await _hold_for_placement(float(_shoot["place"]), str(_shoot.get("place_file", "")))
	await get_tree().create_timer(float(_shoot.get("wait", 1.0))).timeout
	var out: String = _shoot.get("out", "user://shot.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var frames := int(_shoot.get("frames", 0))
	for f in frames:
		await RenderingServer.frame_post_draw
		var fi := _capture()
		fi.save_png("%s_%04d.png" % [out.get_basename(), f + 1])
		await get_tree().create_timer(float(_shoot.get("every", 0.05))).timeout
	await RenderingServer.frame_post_draw
	var img := _capture()
	var err := img.save_png(out)
	print("[shoot] %s -> %s (%dx%d) %s" % [screen, out, img.get_width(), img.get_height(), error_string(err)])
	UI.release_audio()
	# Give the audio thread a moment to drop its playbacks (else they leak at exit).
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if err == OK else 1)
