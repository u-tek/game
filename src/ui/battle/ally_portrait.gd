extends Button
## Battle bottom-strip card for one ally (style v4 poster look): a framed print card on the paper
## strip. Her head and shoulders in full colour inside a hairline frame (slot number, faction glyph,
## a small tab on the corner), a signal fill rising behind her as her energy charges (the frame is
## full when the ultimate is ready), a READY light over the frame, her name and level in mono, an
## ink HP readout with a tick ruler and a mono status line (ULT %, READY / TAP TO CAST, QUEUED).
## A fallen hero turns grey under an ink veil with a DOWN stamp. The battle screen calls set_hp /
## set_energy / set_dead / mark_queued and reads energy, dead, queued; manual = manual-ultimate mode.

const BP := preload("res://src/ui/v4/battle/battle_print.gd")
const HUD := preload("res://src/ui/components/hud.gd")

## Frame top (the slot row is above it) and height.
const TOP := 16.0
const FRAME_H := 104.0
const HEIGHT := 172.0

var uid := ""
var hero_id := ""
var max_hp := 1
var hp := 1
var energy := 0
var dead := false
var manual := false:
	set(v):
		manual = v
		_refresh_status()
var queued := false
var _w := 120.0
var _art: TextureRect
var _over: Control
var _hp_bar: Control
var _status: Label
var _led: Control
var _t := 0.0
var _flash := 0.0
var _shown_status := ""


func setup(u: Dictionary, w: float) -> void:
	uid = str(u.uid)
	hero_id = str(u.hero_id)
	max_hp = maxi(1, int(u.max_hp))
	hp = int(u.hp)
	energy = int(u.get("energy", 0))
	_w = w
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(w, HEIGHT)
	var def := Game.hero_def(hero_id)
	# The portrait, full colour, clipped to the frame (the energy fill shows behind her cut-out).
	var clip := Control.new()
	clip.mouse_filter = MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = Vector2(1, TOP + 1)
	clip.size = Vector2(w - 2, FRAME_H - 2)
	add_child(clip)
	_art = TextureRect.new()
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	_art.texture = Kit.art_crop(hero_id, w / FRAME_H, 1.05, Game.equipped_skin(hero_id))
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.position = Vector2(-1, 2)
	_art.size = Vector2(w, FRAME_H)
	clip.add_child(_art)
	_over = Control.new()
	_over.mouse_filter = MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_over.draw.connect(_draw_over)
	add_child(_over)
	# Slot row: number and faction glyph; the READY light at the right.
	var no := BP.t("%02d" % (int(u.get("slot", 0)) + 1), 11, BP.INK, "mono_bold")
	no.position = Vector2(0, -1)
	add_child(no)
	var fg := Kit.icon("faction_" + str(def.get("faction", "celestial")), 13, BP.INK)
	fg.mouse_filter = MOUSE_FILTER_IGNORE
	fg.position = Vector2(22, 1)
	add_child(fg)
	var led := HUD.Led.new()
	led.mode = "breathe"
	led.size = Vector2(18, 18)
	led.position = Vector2(w - 18, -2)
	led.visible = false
	add_child(led)
	_led = led
	# Name and level, the HP readout, the status line.
	var y := TOP + FRAME_H + 4.0
	var nm := BP.t(str(def.get("name", hero_id)).to_upper(), 11, BP.INK, "mono_bold")
	nm.clip_text = true
	nm.position = Vector2(0, y)
	nm.size = Vector2(w - 34, 16)
	add_child(nm)
	var lv := BP.t("LV%d" % int(u.get("level", 1)) if u.has("level") else "", 10, Color(BP.INK, 0.7), "mono")
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.position = Vector2(w - 40, y + 1)
	lv.size = Vector2(40, 16)
	add_child(lv)
	_hp_bar = BP.Readout.new()
	_hp_bar.position = Vector2(0, y + 19)
	_hp_bar.size = Vector2(w, 12)
	_hp_bar.set("bar_h", 7.0)
	_hp_bar.set("tick_h", 4.0)
	add_child(_hp_bar)
	_hp_bar.call("set_value", float(hp) / float(max_hp), true)
	_status = BP.t("", 10, Color(BP.INK, 0.75), "mono_bold")
	_status.position = Vector2(0, y + 33)
	_status.size = Vector2(w, 16)
	add_child(_status)
	_refresh_status()
	Kit.add_press_fx(self)


func set_hp(v: int) -> void:
	hp = clampi(v, 0, max_hp)
	if _hp_bar:
		_hp_bar.call("set_value", float(hp) / float(max_hp))


func set_energy(v: int) -> void:
	var was_full := energy >= 1000
	energy = clampi(v, 0, 1000)
	if energy < 1000:
		queued = false
	if energy >= 1000 and not was_full:
		_flash = 1.0
		Kit.pulse(self, 1.06)
	_refresh_status()
	queue_redraw()
	_over.queue_redraw()


func set_dead() -> void:
	dead = true
	hp = 0
	energy = 0
	queued = false
	_art.material = Kit.grayscale_material()
	if _hp_bar:
		_hp_bar.call("set_value", 0.0, true)
	_refresh_status()
	queue_redraw()
	_over.queue_redraw()


## Visual feedback for a tap that queued the ultimate.
func mark_queued() -> void:
	queued = true
	_flash = 1.0
	Kit.pulse(self, 1.08)
	_refresh_status()
	_over.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
	if (energy >= 1000 and not dead) or _flash > 0.0:
		queue_redraw()
		_over.queue_redraw()


func _refresh_status() -> void:
	if _status == null:
		return
	var ready := energy >= 1000 and not dead
	var text := "ULT %d%%" % (energy / 10)
	var col := Color(BP.INK, 0.75)
	if dead:
		text = "DOWN"
		col = Color(BP.INK, 0.5)
	elif queued and ready:
		text = "QUEUED"
		col = BP.SIG
	elif ready:
		text = "TAP TO CAST" if manual else "READY"
		col = BP.SIG
	if text != _shown_status:
		_shown_status = text
		_status.text = text
		_status.add_theme_color_override("font_color", col)
	if _led:
		_led.visible = ready
		_led.set("mode", "steady" if queued else "breathe")


## Inside the frame, behind her: the paper and the energy fill rising in signal.
func _draw() -> void:
	var fr := Rect2(0, TOP, _w, FRAME_H)
	draw_rect(fr, BP.PAPER_DIM)
	if dead:
		return
	var ef := float(energy) / 1000.0
	var ready := ef >= 1.0
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var col := BP.SIG if not ready else BP.SIG.lerp(BP.SIG_HI, 0.45 * pulse)
	var fh := FRAME_H * ef
	draw_rect(Rect2(0, TOP + FRAME_H - fh, _w, fh), col)
	if manual and not ready:
		# Manual mode: the charge scale reads like an instrument (a tick every 25%).
		for q in range(1, 4):
			var y := TOP + FRAME_H * (1.0 - q / 4.0)
			draw_line(Vector2(0, y), Vector2(7, y), Color(BP.INK, 0.45), 1.0)


## Over her: the frame and its tab, scale ticks, and the fallen veil and stamp.
func _draw_over() -> void:
	var fr := Rect2(0, TOP, _w, FRAME_H)
	var ready := energy >= 1000 and not dead
	if dead:
		_over.draw_rect(fr, Color(0.06, 0.065, 0.075, 0.42))
		var f := Kit.font("wide_black")
		var c := fr.get_center()
		_over.draw_set_transform(c, -0.14, Vector2.ONE)
		var tw := f.get_string_size("DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_over.draw_rect(Rect2(-tw * 0.5 - 8, -16, tw + 16, 30), Color(BP.PAPER, 0.92), false, 2.0)
		_over.draw_string(f, Vector2(-tw * 0.5, 8), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BP.PAPER)
		_over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var frame_col := BP.INK
	var width := 1.5
	if ready:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		width = 2.0 + pulse
	_over.draw_rect(fr, frame_col, false, width)
	# The corner tab (the dossier's pixel squares).
	_over.draw_rect(Rect2(_w - 5, TOP - 3, 7, 7), BP.SIG if ready else BP.INK)
	# Energy scale ticks down the frame's right edge.
	for q in range(1, 4):
		var y := TOP + FRAME_H * (1.0 - q / 4.0)
		_over.draw_line(Vector2(_w - 6, y), Vector2(_w, y), Color(BP.INK, 0.7), 1.0)
	if _flash > 0.0:
		_over.draw_rect(fr.grow(3.0 + (1.0 - _flash) * 9.0), Color(BP.SIG, _flash * 0.9), false, 2.0)
