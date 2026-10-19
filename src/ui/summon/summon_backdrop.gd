extends Control
## Summon backdrop (Aero Y2K): a deep ocean-navy gradient, slow underwater light shafts from
## the top, glossy bubbles drifting up, a glow at the focus point and a soft floor glow. Its
## mood follows `target_tint` (the portal's or the revealed hero's rarity color) and `darken`
## (held beats before a big reveal); both ease toward their targets every frame.

const Fx := preload("res://src/ui/summon/summon_fx.gd")

const TOP := Color("0c2a55")
const MID := Color("071a38")
const BOTTOM := Color("020814")
const BUBBLES := 30
const SHAFTS := 6

## Mood color and how strongly it tints the scene (0..1); eased toward each frame.
var target_tint := Color("18c3e8")
var target_amount := 0.35
## Extra darkness 0..1 (held beat before a Legendary).
var target_darken := 0.0
## Where the light gathers (portal centre or the hero's chest), and the floor glow line.
var focus := Vector2(360, 600)
var focus_glow := 0.6
var floor_y := -1.0
var floor_glow := 0.0
## Bubble speed multiplier (the portal charge speeds them up).
var bubble_speed := 1.0

var _tint := Color("18c3e8")
var _amount := 0.35
var _darken := 0.0
var _t := 0.0
# Bubbles: x (0..1), y (px), radius, speed (px/s), wobble phase.
var _b := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _quad := PackedVector2Array()
var _cols := PackedColorArray()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_rng.seed = 7
	_quad.resize(4)
	_cols.resize(4)
	_b.resize(BUBBLES * 5)
	for i in BUBBLES:
		_b[i * 5] = _rng.randf()
		_b[i * 5 + 1] = _rng.randf_range(0.0, 1600.0)
		_b[i * 5 + 2] = _rng.randf_range(4.0, 26.0) * (1.6 if i % 9 == 0 else 1.0)
		_b[i * 5 + 3] = _rng.randf_range(18.0, 60.0)
		_b[i * 5 + 4] = _rng.randf() * TAU


## Jumps straight to the targets (no easing), e.g. when the sequence opens.
func snap() -> void:
	_tint = target_tint
	_amount = target_amount
	_darken = target_darken


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-delta * 5.0)
	_tint = _tint.lerp(target_tint, k)
	_amount = lerpf(_amount, target_amount, k)
	_darken = lerpf(_darken, target_darken, 1.0 - exp(-delta * 7.0))
	var h := maxf(size.y, 1.0)
	for i in BUBBLES:
		var y := _b[i * 5 + 1] - _b[i * 5 + 3] * delta * bubble_speed
		if y < -40.0:
			y = h + 40.0
			_b[i * 5] = _rng.randf()
		_b[i * 5 + 1] = y
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var dk := 1.0 - _darken * 0.8
	# Stays ocean navy; the mood color mostly lives in the glow around the focus.
	var top := TOP.lerp(_tint.darkened(0.5), _amount * 0.3) * dk
	var mid := MID.lerp(_tint.darkened(0.7), _amount * 0.25) * dk
	var bot := BOTTOM * dk
	top.a = 1.0
	mid.a = 1.0
	bot.a = 1.0
	# Two-band vertical gradient.
	_quad[0] = Vector2(0, 0)
	_quad[1] = Vector2(w, 0)
	_quad[2] = Vector2(w, h * 0.55)
	_quad[3] = Vector2(0, h * 0.55)
	_cols[0] = top
	_cols[1] = top
	_cols[2] = mid
	_cols[3] = mid
	draw_polygon(_quad, _cols)
	_quad[0] = Vector2(0, h * 0.55)
	_quad[1] = Vector2(w, h * 0.55)
	_quad[2] = Vector2(w, h)
	_quad[3] = Vector2(0, h)
	_cols[0] = mid
	_cols[1] = mid
	_cols[2] = bot
	_cols[3] = bot
	draw_polygon(_quad, _cols)
	var soft := Fx.soft_dot()
	# Glow where the light gathers.
	var gr := w * 1.05
	var gc := _tint.lerp(Color.WHITE, 0.1)
	draw_texture_rect(soft, Rect2(focus - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(gc, focus_glow * (0.35 + 0.5 * _amount) * dk))
	# Light shafts from the surface, swaying slowly.
	var shaft := Color(0.55, 0.9, 1.0).lerp(_tint.lightened(0.3), 0.4)
	for i in SHAFTS:
		var fi := float(i)
		var x0 := w * (0.08 + 0.17 * fi) + sin(_t * 0.23 + fi * 1.7) * 26.0
		var sw := 34.0 + 46.0 * fmod(fi * 0.61, 1.0)
		var lean := 120.0 + 40.0 * sin(fi * 2.1)
		var a := (0.05 + 0.03 * sin(_t * 0.5 + fi)) * dk
		_quad[0] = Vector2(x0, -10)
		_quad[1] = Vector2(x0 + sw, -10)
		_quad[2] = Vector2(x0 + sw * 2.2 + lean, h * 0.78)
		_quad[3] = Vector2(x0 + lean, h * 0.78)
		_cols[0] = Color(shaft, a)
		_cols[1] = Color(shaft, a)
		_cols[2] = Color(shaft, 0.0)
		_cols[3] = Color(shaft, 0.0)
		draw_polygon(_quad, _cols)
	# Floor glow (the hero stands on it).
	if floor_y > 0.0 and floor_glow > 0.01:
		var fw := w * 0.95
		draw_texture_rect(soft, Rect2(Vector2(w * 0.5 - fw * 0.5, floor_y - fw * 0.09), Vector2(fw, fw * 0.18)), false, Color(_tint.lightened(0.2), 0.55 * floor_glow * dk))
		draw_texture_rect(soft, Rect2(Vector2(w * 0.5 - fw * 0.25, floor_y - fw * 0.035), Vector2(fw * 0.5, fw * 0.07)), false, Color(1, 1, 1, 0.35 * floor_glow * dk))
	# Glossy bubbles (Aero): faint body, rim, a bright highlight and a little bounce light.
	for i in BUBBLES:
		var r := _b[i * 5 + 2]
		var x := _b[i * 5] * w + sin(_t * 0.9 + _b[i * 5 + 4]) * (6.0 + r * 0.4)
		var c := Vector2(x, _b[i * 5 + 1])
		var depth := clampf(r / 26.0, 0.25, 1.0)
		var bc := Color(0.75, 0.95, 1.0).lerp(_tint.lightened(0.4), 0.3)
		draw_circle(c, r, Color(bc, 0.035 * depth * dk))
		draw_arc(c, r, 0.0, TAU, 24, Color(bc, 0.2 * depth * dk), 1.4, true)
		draw_arc(c, r * 0.82, 0.2, 1.4, 8, Color(bc, 0.22 * depth * dk), 1.4, true)
		draw_circle(c + Vector2(-0.38, -0.4) * r, r * 0.24, Color(1, 1, 1, 0.45 * depth * dk))
