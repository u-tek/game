extends CheckButton
## Animated on/off switch (Kit.toggle), style v4 print (the poster house style): a box ruled in ink
## on sticker paper with "ON" and "OFF" printed in its halves, and a solid ink knob that slides over
## the word that is not true with a small spring (and stretches while held); a signal status light
## glows on the knob when on. It stays a CheckButton, so button_pressed, toggled and
## set_pressed_no_signal work as usual (the knob follows any of them).

const TRACK := Vector2(112, 50)
const PAPER := Color("f4f3ef")
const INK := Color("101113")
const LED := Color("ff3b1f")

## Drawn knob position, 0 = off, 1 = on (springs past the ends a little).
var _k := 0.0
var _shown_on := false
## 0..1 knob stretch while the finger is down.
var _hold := 0.0
var _tw: Tween
var _hold_tw: Tween

static var _blank: Texture2D


func _init() -> void:
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _blank == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_blank = ImageTexture.create_from_image(img)
	for n: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		add_theme_icon_override(n, _blank)
		add_theme_icon_override(n + "_mirrored", _blank)


func _ready() -> void:
	_shown_on = button_pressed
	_k = 1.0 if button_pressed else 0.0
	toggled.connect(func(_v: bool) -> void: _sync())
	button_down.connect(func() -> void: _set_hold(1.0))
	button_up.connect(func() -> void: _set_hold(0.0))


func _sync() -> void:
	if not is_inside_tree():
		return
	_shown_on = button_pressed
	var to := 1.0 if button_pressed else 0.0
	if _tw and _tw.is_valid():
		_tw.kill()
	if not Kit.motion_ok():
		_k = to
		queue_redraw()
		return
	_tw = create_tween()
	_tw.tween_method(_set_k, _k, to, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_k(v: float) -> void:
	_k = v
	queue_redraw()


func _set_hold(to: float) -> void:
	if _hold_tw and _hold_tw.is_valid():
		_hold_tw.kill()
	_hold_tw = create_tween()
	_hold_tw.tween_method(func(v: float) -> void:
		_hold = v
		queue_redraw(), _hold, to, 0.12 if to > 0.0 else 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if button_pressed != _shown_on:
		# set_pressed_no_signal (or a toggle before entering the tree): follow it.
		_sync.call_deferred()
	var x0 := size.x - TRACK.x - 6.0
	var y0 := (size.y - TRACK.y) * 0.5
	var track := Rect2(x0, y0, TRACK.x, TRACK.y)
	var kc := clampf(_k, 0.0, 1.0)
	var dim := 0.45 if disabled else 1.0
	# The printed box: sticker paper ruled in ink, the two words printed in its halves.
	draw_rect(Rect2(track.position + Vector2(0, 2), track.size), Color(0, 0, 0, 0.1 * dim))
	draw_rect(track, Color(PAPER, dim))
	var f := Kit.font("mono_bold")
	var half := track.size.x * 0.5
	for side in 2:
		var word := "ON" if side == 0 else "OFF"
		var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var cx := track.position.x + half * (side + 0.5)
		draw_string(f, Vector2(cx - tw * 0.5, track.position.y + track.size.y * 0.5 + 5.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(INK, 0.55 * dim))
	# The knob: a solid ink block over the word that is not true (it slides with a small spring and
	# stretches while held); a signal status light on it when on.
	var stretch := 8.0 * _hold
	var kw := half - 4.0
	var kx := lerpf(track.position.x + 3.0, track.end.x - 3.0 - kw, _k) - stretch * (1.0 - kc)
	var kr := Rect2(kx, track.position.y + 3.0, kw + stretch, track.size.y - 6.0)
	kr.position.x = clampf(kr.position.x, track.position.x + 3.0, track.end.x - 3.0 - kr.size.x)
	draw_rect(kr, Color(INK, dim))
	draw_rect(Rect2(kr.position + Vector2(3, 3), kr.size - Vector2(6, 6)), Color(1, 1, 1, 0.16 * dim), false, 1.0)
	var lc := kr.get_center()
	if kc > 0.5:
		var k := (kc - 0.5) * 2.0
		for i in 4:
			draw_circle(lc, 5.0 + i * 2.5, Color(LED, 0.1 * k * dim * (1.0 - i / 4.0)), true, -1.0, true)
		draw_circle(lc, 4.5, Color(LED.lightened(0.25), k * dim), true, -1.0, true)
	else:
		draw_circle(lc, 3.0, Color(1, 1, 1, 0.3 * dim), false, 1.0, true)
	draw_rect(track, Color(INK, dim), false, 2.0)
