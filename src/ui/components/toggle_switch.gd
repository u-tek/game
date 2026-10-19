extends CheckButton
## Animated on/off switch (Kit.toggle), Aero look: a glossy pill track (aqua when on, pale
## frosted grey when off) and a white knob that slides over with a small spring and
## stretches while held, like a native phone switch. It stays a CheckButton, so
## button_pressed, toggled and set_pressed_no_signal work as usual (the knob follows any of
## them).

const KitBox := preload("res://src/ui/components/kit_box.gd")

const TRACK := Vector2(98, 54)
const ON_TOP := Color("3fdcf7")
const ON_BOT := Color("0b97e0")
const OFF_TOP := Color("c3ceda")
const OFF_BOT := Color("dbe3ea")

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
	var ci := get_canvas_item()
	var x0 := size.x - TRACK.x - 6.0
	var y0 := (size.y - TRACK.y) * 0.5
	var track := Rect2(x0, y0, TRACK.x, TRACK.y)
	var kc := clampf(_k, 0.0, 1.0)
	var pill := KitBox.shape_points(track, TRACK.y * 0.5, 0.0, 0, 0.0, 10)
	var dim := 0.5 if disabled else 1.0
	KitBox.fill_poly(ci, pill, Color(OFF_TOP.lerp(ON_TOP, kc), dim), Color(OFF_BOT.lerp(ON_BOT, kc), dim))
	# Glass gloss on the upper half, stronger when lit.
	var gl := Rect2(track.position + Vector2(6, 3), Vector2(track.size.x - 12, track.size.y * 0.42))
	var gp := KitBox.shape_points(gl, gl.size.y * 0.5, 0.0, 0, 0.0, 6)
	var ga := (0.18 + 0.3 * kc) * dim
	var gcols := PackedColorArray()
	for p in gp:
		gcols.append(Color(1, 1, 1, ga * (1.0 - clampf((p.y - gl.position.y) / gl.size.y, 0.0, 1.0))))
	KitBox._fan(ci, gp, gcols, gl.get_center(), Color(1, 1, 1, ga * 0.5))
	KitBox.stroke_poly(ci, KitBox.offset_poly(pill, -0.75), Color(Color("a7b4c2").lerp(Color("8fe6ff"), kc), dim), 1.5)
	# Knob: a white bead that stretches toward the middle while held.
	var r := TRACK.y * 0.5 - 4.0
	var stretch := 9.0 * _hold
	var left := x0 + 4.0 + r
	var right := x0 + TRACK.x - 4.0 - r
	var cx := lerpf(left, right, _k)
	var kr := Rect2(cx - r - stretch * (1.0 - kc), y0 + 4.0, r * 2.0 + stretch, r * 2.0)
	kr.position.x = clampf(kr.position.x, x0 + 3.0, x0 + TRACK.x - 3.0 - kr.size.x)
	var knob := KitBox.shape_points(kr, r, 0.0, 0, 0.0, 8)
	KitBox.soft_shadow(ci, knob, Color(0, 0.08, 0.18, 0.35 * dim), 4.0, Vector2(0, 2))
	KitBox.fill_poly(ci, knob, Color(1, 1, 1, dim), Color(Color("e4ebf1"), dim))
	KitBox.stroke_poly(ci, KitBox.offset_poly(knob, -0.5), Color(1, 1, 1, 0.9 * dim), 1.0)
