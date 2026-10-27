extends Control
## Screen "gallery": the heroines full screen, nothing in front of them (the owner, 2026-10-22: "i want
## the artwork to be front and center ... people are buying the skins for the sexual value").
## Ink stage, the live rig fitted to the screen in the look chosen, her red print faint behind.
##   swipe left / right   the next or previous heroine (owned ones, roster order)
##   the look strip       her base look and every skin; owned looks wear at once ("WEAR" sets it as
##                        her look everywhere), a skin she doesn't own yet shows as a PREVIEW with
##                        its price and BUY (gems); skins whose art isn't in the build are skipped
##   double tap           zoom in (2.2x) where tapped / back out; pinch zooms (two fingers), a drag
##                        pans while zoomed; she always stays on screen (_clamp_pan)
##   a single tap on her  she reacts (HeroReact)
##   hide                 the type and strip fade out (tap anywhere to bring them back)
## Mono type in the poster style: her name, title, the look's name and pack, "07 / 40".
## params: hero_id (start on her), skin (start on that look).

const DeviceTier := preload("res://src/art/device_tier.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL
const STRIP_H := 156.0
const ZOOM_IN := 2.2
const SWIPE_MIN := 90.0

var _ids: Array[String] = []
var _i := 0
var _looks: Array[Dictionary] = []
var _look := 0
var _stage: Control
## Her name and lines, printed behind her (between the print and the figure, like the posters).
var _type: Control
var _print: TextureRect
var _anchor: Node2D
var _punch: Node2D
var _sprite: Node2D
var _ui: Control
var _strip: HBoxContainer
var _name_l: Label
var _title_l: Label
var _look_l: Label
var _count_l: Label
var _buy: Control
var _zoom := 1.0
var _pan := Vector2.ZERO
var _fit_k := 1.0
var _feet := Vector2.ZERO
var _down := Vector2.INF
var _down_t := 0
var _last_tap := 0
var _last_tap_at := Vector2.ZERO
var _moved := false
var _touches := {}
var _pinch0 := 0.0
var _zoom0 := 1.0
var _tap_n := 0
var _tap_at := 0.0
var _react_left := 0.0
var _hidden := false


func setup(params: Dictionary) -> void:
	UI.set_chrome(false, false)
	for h: Dictionary in Game.owned_heroes():
		_ids.append(str(h.id))
	# Legendaries first, then Epics, then Rares; by name inside each.
	var rank := {"legendary": 0, "epic": 1, "rare": 2}
	_ids.sort_custom(func(a: String, b: String) -> bool:
		var ra := int(rank.get(str(Game.hero_def(a).get("rarity", "")), 3))
		var rb := int(rank.get(str(Game.hero_def(b).get("rarity", "")), 3))
		return ra < rb if ra != rb else a < b)
	if _ids.is_empty():
		UI.toast("Summon a heroine first", "info")
		UI.go("summon")
		return
	var want := str(params.get("hero_id", ""))
	# A heroine not yet recruited can still be looked at (the shop's wardrobe opens her looks here).
	if want != "" and not _ids.has(want) and not Game.hero_def(want).is_empty():
		_ids.insert(0, want)
	_i = maxi(0, _ids.find(want))
	_build()
	_show_hero(_i, str(params.get("skin", "*")))
	# Screenshots (debug): zoom = 2.2 and pan = [x, y] (the clamp keeps her on screen).
	if OS.is_debug_build() and params.has("zoom"):
		(func() -> void:
			await get_tree().process_frame
			await get_tree().process_frame
			_zoom = float(params.zoom)
			var pp: Variant = params.get("pan", [0, 0])
			_pan = Vector2(float(pp[0]), float(pp[1]))
			_apply_zoom()).call_deferred()
	resized.connect(_layout)


func _exit_tree() -> void:
	UI.set_chrome(true, true)


func _build() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = INK
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_stage.clip_contents = true
	add_child(_stage)
	_type = Control.new()
	_type.name = "Type"
	_type.mouse_filter = MOUSE_FILTER_IGNORE
	_type.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_stage.add_child(_type)
	_ui = Control.new()
	_ui.name = "UI"
	_ui.mouse_filter = MOUSE_FILTER_IGNORE
	_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_ui)
	var top := UI.safe_top() + 14.0
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.name = "Back"
	back.position = Vector2(12, top - 6.0)
	_ui.add_child(back)
	_count_l = PK.t("", 12, Color(PAPER, 0.7), "mono_bold")
	_count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(_count_l)
	_name_l = PK.t("", 64, PAPER, "compressed")
	_type.add_child(_name_l)
	_title_l = PK.t("", 11, Color(PAPER, 0.75), "mono")
	_type.add_child(_title_l)
	_look_l = PK.t("", 12, SIG, "mono_bold")
	_type.add_child(_look_l)
	var hide := PK.t("HIDE  ·  TAP TO SHOW", 10, Color(PAPER, 0.6), "mono_bold")
	hide.name = "HideLabel"
	_ui.add_child(hide)
	var hb := Button.new()
	hb.name = "Hide"
	hb.theme_type_variation = &"BareButton"
	hb.focus_mode = FOCUS_NONE
	hb.size = Vector2(150, 88)
	_ui.add_child(hb)
	hb.pressed.connect(_toggle_ui)
	var sc := ScrollContainer.new()
	sc.name = "Looks"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	sc.mouse_filter = MOUSE_FILTER_PASS
	_ui.add_child(sc)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 10)
	sc.add_child(_strip)
	_layout()


func _layout() -> void:
	if _ui == null:
		return
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var top := UI.safe_top() + 14.0
	var bot := vs.y - UI.safe_bottom()
	_count_l.size = Vector2(200, 16)
	_count_l.position = Vector2(vs.x - 220, top + 8)
	_name_l.position = Vector2(22, top + 66)
	_name_l.size = Vector2(vs.x - 40, 80)
	_title_l.position = Vector2(24, top + 138)
	_look_l.position = Vector2(24, top + 156)
	var hide := _ui.get_node("HideLabel") as Label
	hide.position = Vector2(vs.x - 172, top + 30)
	(_ui.get_node("Hide") as Control).position = Vector2(vs.x - 170, top)
	var sc := _ui.get_node("Looks") as Control
	sc.position = Vector2(14, bot - STRIP_H - 10)
	sc.size = Vector2(vs.x - 28, STRIP_H)
	if _buy and is_instance_valid(_buy):
		# Small, at the right above the strip: her figure stays clear.
		_buy.scale = Vector2(0.72, 0.72)
		_buy.position = Vector2(vs.x - _buy.size.x * 0.72 - 10.0, bot - STRIP_H - 150.0)
	_fit()


## Her looks: the base and every skin whose art is in the build. In 18+ mode skins are off (every
## heroine shows her nude look; the shop and hero page hide the wardrobe) except those whose own 18+
## look is current (data/adult_skins.json): those show, owned or as a preview.
func _looks_for(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": "", "name": "Original", "line": "", "owned": true, "price_gems": 0}]
	for s: Dictionary in Game.skins_for(id):
		if not bool(s.get("installed", false)):
			continue
		if HeroArt.nudity and not HeroArt.adult_skin_current(id, str(SkinData.get_def(str(s.id)).get("art", ""))):
			continue
		out.append(s)
	return out


func _show_hero(i: int, skin: String = "*") -> void:
	_i = posmod(i, _ids.size())
	var id := _ids[_i]
	_looks = _looks_for(id)
	var want := Game.equipped_skin(id) if skin == "*" else skin
	_look = 0
	for k in _looks.size():
		if str(_looks[k].id) == want:
			_look = k
	_zoom = 1.0
	_pan = Vector2.ZERO
	_build_strip()
	_show_look()


func _show_look() -> void:
	var id := _ids[_i]
	var lk: Dictionary = _looks[_look]
	var skin := str(lk.id)
	if _print and is_instance_valid(_print):
		_print.queue_free()
	if _anchor and is_instance_valid(_anchor):
		_anchor.queue_free()
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	_print = PK.halftone_print(id, skin, Vector2(vs.x * 0.9, vs.y * 0.7), 8.0, Color(PK.PRINT, 0.22))
	_print.position = Vector2(vs.x * 0.1, vs.y * 0.1)
	_stage.add_child(_print)
	_stage.move_child(_print, 0)
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	_stage.add_child(_anchor)
	# The tap reaction's camera punch scales this, inside the anchor that carries the zoom, so a
	# reaction never springs the zoom back.
	_punch = Node2D.new()
	_punch.name = "Punch"
	_anchor.add_child(_punch)
	_sprite = HeroArt.make_sprite(id, skin)
	_punch.add_child(_sprite)
	DeviceTier.light(_sprite)
	var d := Game.hero_def(id)
	_name_l.text = str(d.get("name", id)).to_upper()
	_title_l.text = "%s  ·  %s  ·  %s" % [str(d.get("title", "")).to_upper(), str(Kit.FACTION_NAMES.get(str(d.get("faction", "")), "")).to_upper(),
		str(Kit.RARITY_NAMES.get(str(d.get("rarity", "")), "")).to_upper()]
	var line := str(lk.get("line", "")).replace("_", " ").to_upper()
	_look_l.text = str(lk.name).to_upper() + (("  ·  " + line) if line != "" else "") + ("" if bool(lk.owned) else "  ·  PREVIEW")
	_count_l.text = "%02d / %02d" % [_i + 1, _ids.size()]
	_mark_strip()
	_build_buy()
	_fit()
	if Kit.motion_ok():
		_sprite.modulate.a = 0.0
		_sprite.create_tween().tween_property(_sprite, "modulate:a", 1.0, 0.25)


## Fits her to the stage between the type and the strip, then applies the zoom and pan.
func _fit() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var top := UI.safe_top() + 60.0
	var bot := vs.y - UI.safe_bottom() - STRIP_H - 16.0
	var box := Rect2(10, top, vs.x - 20, bot - top)
	_fit_k = HeroArt.fit_sprite(_sprite, _anchor, box, vs.x * 0.5)
	_feet = _anchor.position
	_apply_zoom()


func _apply_zoom() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var c := vs * 0.5
	_clamp_pan(vs)
	_anchor.scale = Vector2(_zoom, _zoom)
	_anchor.position = c + (_feet - c) * _zoom + _pan


## Keeps her on screen while zoomed (owner, 2026-10-23: "fix the character view mode so that the
## heroes don't go off the screen when you're zooming in"): along each axis, if her zoomed body (the
## core figure: wings and props may run past it) is bigger than the view it always covers the view,
## else it is centred on it.
func _clamp_pan(vs: Vector2) -> void:
	if _zoom <= 1.001:
		_pan = Vector2.ZERO
		return
	if _sprite == null or not is_instance_valid(_sprite) or not _sprite.has_method("figure_rect"):
		return
	# (figure_rect is already in the anchor's units: it includes the sprite's fitted scale)
	var fr: Rect2 = _sprite.call("figure_rect", true)
	var fig := Rect2(_feet + fr.position, fr.size)
	var c := vs * 0.5
	# Her figure at this zoom without pan.
	var z0 := Rect2(c + (fig.position - c) * _zoom, fig.size * _zoom)
	var view := Rect2(Vector2.ZERO, vs)
	for ax in 2:
		var lo := z0.position[ax]
		var hi := z0.end[ax]
		if hi - lo >= view.size[ax]:
			# Pan within [view.end - hi, view.position - lo].
			_pan[ax] = clampf(_pan[ax], view.end[ax] - hi, view.position[ax] - lo)
		else:
			_pan[ax] = (view.position[ax] + view.end[ax]) * 0.5 - (lo + hi) * 0.5


func _build_strip() -> void:
	# Out of the strip now, not at the end of the frame: _mark_strip counts the cards right after.
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	var id := _ids[_i]
	for k in _looks.size():
		var lk: Dictionary = _looks[k]
		var card := Control.new()
		card.name = "Look_%d" % k
		card.custom_minimum_size = Vector2(108, STRIP_H)
		card.mouse_filter = MOUSE_FILTER_PASS
		_strip.add_child(card)
		var bg := ColorRect.new()
		bg.color = Color(PAPER, 0.08)
		bg.size = Vector2(108, 118)
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(bg)
		var pic := HeroArt.make_portrait(id, 104, str(lk.id))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.position = Vector2(2, 2)
		pic.size = Vector2(104, 114)
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if not bool(lk.owned):
			pic.modulate = Color(0.55, 0.55, 0.6)
		card.add_child(pic)
		var nm := PK.t(str(lk.name).to_upper(), 9, PAPER, "mono_bold")
		nm.size = Vector2(108, 13)
		nm.clip_text = true
		nm.position = Vector2(0, 122)
		card.add_child(nm)
		var sub := PK.t("OWNED" if bool(lk.owned) else "%d GEMS" % int(lk.get("price_gems", 0)), 9, Color(PAPER, 0.6) if bool(lk.owned) else SIG, "mono")
		sub.position = Vector2(0, 136)
		card.add_child(sub)
		var kk := k
		Kit.make_tappable(card, func() -> void:
			_look = kk
			_zoom = 1.0
			_pan = Vector2.ZERO
			_show_look())


func _mark_strip() -> void:
	for k in _strip.get_child_count():
		var card := _strip.get_child(k) as Control
		var bg := card.get_child(0) as ColorRect
		if bg:
			bg.color = SIG if k == _look else Color(PAPER, 0.08)


## WEAR for an owned look she isn't wearing; BUY for a preview.
func _build_buy() -> void:
	if _buy and is_instance_valid(_buy):
		_buy.queue_free()
	_buy = null
	var id := _ids[_i]
	var lk: Dictionary = _looks[_look]
	var sid := str(lk.id)
	var spec := {}
	var cb := Callable()
	if not bool(lk.owned):
		var sale := bool(lk.get("sale", false))
		spec = {"width": 380.0, "kicker": "HER BIRTHDAY  //  ON SALE" if sale else "WARDROBE  //  PREVIEW", "title": "BUY",
			"sub": ("%d GEMS  (WAS %d)" % [int(lk.get("price_gems", 0)), int(lk.get("full_price_gems", 0))]) if sale else "%d GEMS" % int(lk.get("price_gems", 0)),
			"action": "MAKE IT HERS  >>>", "icon": "gems"}
		cb = func() -> void:
			var r: Dictionary = Game.buy_skin(sid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			Game.equip_skin(id, sid)
			UI.toast("%s is hers" % str(lk.name), "good")
			_looks = _looks_for(id)
			_build_strip()
			_show_look()
	elif Game.equipped_skin(id) != sid:
		spec = {"width": 330.0, "kicker": "WARDROBE", "title": "WEAR", "sub": "HER LOOK EVERYWHERE", "action": "SET  >>>", "icon": "check"}
		cb = func() -> void:
			Game.equip_skin(id, sid)
			Kit.sfx("tap")
			_build_buy()
	if spec.is_empty():
		return
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.size = Vector2(float(spec.width), 110)
	_ui.add_child(holder)
	holder.add_child(SignalKit.pass_button(spec, cb))
	_buy = holder
	_layout()


## Hide shows her alone: everything but the Hide control fades out and leaves play (hidden, so no
## button in it, however deep, takes a tap); showing puts it all back as it was.
func _toggle_ui() -> void:
	_hidden = not _hidden
	var tw := _ui.create_tween()
	if not _hidden:
		_set_ui_shown(true)
	tw.tween_property(_ui, "modulate:a", 0.0 if _hidden else 1.0, 0.2)
	if _hidden:
		tw.tween_callback(_set_ui_shown.bind(false))


## (A hide's fade that finishes after a quick show again leaves everything shown.)
func _set_ui_shown(on: bool) -> void:
	for c in _ui.get_children():
		if c is CanvasItem and c.name != "Hide":
			(c as CanvasItem).visible = on or not _hidden


# ------------------------------------------------------------------ touch

func _gui_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st:
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			var p: Array = _touches.values()
			_pinch0 = (p[0] as Vector2).distance_to(p[1])
			_zoom0 = _zoom
		return
	var sd := event as InputEventScreenDrag
	if sd:
		_touches[sd.index] = sd.position
		if _touches.size() == 2 and _pinch0 > 0.0:
			var p: Array = _touches.values()
			_zoom = clampf(_zoom0 * (p[0] as Vector2).distance_to(p[1]) / _pinch0, 1.0, 3.5)
			_moved = true
			_apply_zoom()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
		_zoom = clampf(_zoom * (1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.9), 1.0, 3.5)
		if _zoom <= 1.001:
			_pan = Vector2.ZERO
		_apply_zoom()
		return
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_down = mb.position
			_down_t = Time.get_ticks_msec()
			_moved = false
		else:
			_release(mb.position)
		return
	var mm := event as InputEventMouseMotion
	if mm and _down != Vector2.INF and _touches.size() < 2:
		if mm.position.distance_to(_down) > 14.0:
			_moved = true
		if _moved and _zoom > 1.001:
			_pan += mm.relative
			_apply_zoom()


func _release(p: Vector2) -> void:
	if _down == Vector2.INF:
		return
	var d := p - _down
	var quick := Time.get_ticks_msec() - _down_t < 600
	_down = Vector2.INF
	if _touches.size() >= 1 and _pinch0 > 0.0:
		_pinch0 = 0.0
		return
	if _hidden:
		_toggle_ui()
		return
	# A sideways swipe (not zoomed): the next or previous heroine.
	if _zoom <= 1.001 and quick and absf(d.x) > SWIPE_MIN and absf(d.x) > absf(d.y) * 1.4:
		Kit.sfx("tap")
		_show_hero(_i + (1 if d.x < 0.0 else -1))
		return
	if _moved:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap < 320 and p.distance_to(_last_tap_at) < 60.0:
		# Double tap: zoom in where tapped, or back out.
		_last_tap = 0
		if _zoom > 1.001:
			_zoom = 1.0
			_pan = Vector2.ZERO
		else:
			var vs := size if size.x > 0.0 else get_viewport_rect().size
			_zoom = ZOOM_IN
			_pan = (vs * 0.5 - p) * (ZOOM_IN - 1.0)
		if Kit.motion_ok():
			var z := _zoom
			var pn := _pan
			_zoom = 1.0 if z > 1.0 else ZOOM_IN
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void:
				_zoom = lerpf(_zoom, z, v)
				_pan = _pan.lerp(pn, v)
				_apply_zoom(), 0.0, 1.0, 0.22)
		else:
			_apply_zoom()
		return
	_last_tap = now
	_last_tap_at = p
	# A single tap on her: she reacts.
	if _sprite and is_instance_valid(_sprite):
		var t := now / 1000.0
		_tap_n = HeroReact.next_count(_tap_n, t - _tap_at)
		_tap_at = t
		_react_left = HeroReact.react(self, _sprite, _punch, p, _tap_n, _stage)
		if _tap_n >= 4:
			_tap_n = 0


func _process(delta: float) -> void:
	if _react_left > 0.0:
		_react_left -= delta
		if _react_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
