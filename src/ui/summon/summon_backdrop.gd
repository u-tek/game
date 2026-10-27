extends Control
## Summon backdrop (style v4 "Signal", the poster look): the paper matte of the print room, with
## registration marks in the corners, a printer's colour bar and press micro type along the edges.
## Its mood follows `target_tint` (a faint wash of the rarity's ink) and `target_darken` (the room
## dims to ink during a held beat before a big reveal); both ease toward their targets every frame.
## (focus, focus_glow, floor_y, floor_glow and bubble_speed are kept for the sequence's API; the
## speed shakes the registration marks during the press run.)

const MATTE := SignalKit.MATTE
const INK := SignalKit.INK
const SIGNAL := SignalKit.SIGNAL

## Mood colour and how strongly it washes the page (0..1); eased toward each frame.
var target_tint := INK
var target_amount := 0.0
## Extra darkness 0..1 (held beat before a Legendary).
var target_darken := 0.0
var focus := Vector2(360, 600)
var focus_glow := 0.0
var floor_y := -1.0
var floor_glow := 0.0
## The press speed (the charge raises it): the marks jitter with it.
var bubble_speed := 1.0
## Insets kept clear for the HUD (safe area).
var inset_top := 0.0
var inset_bottom := 0.0

var _tint := INK
var _amount := 0.0
var _darken := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## How dark the room is right now (0..1): the HUD's type turns paper-coloured on the dark.
func darkness() -> float:
	return _darken


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
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# The page: matte, washed by the mood ink, dimmed toward ink in a held beat.
	var page := MATTE.lerp(_tint, _amount * 0.12).lerp(Color("1a1b1e"), _darken * 0.92)
	draw_rect(Rect2(0, 0, w, h), page)
	var ink := INK.lerp(MATTE, _darken * 0.85)
	ink.a = 0.7
	var j := Vector2(sin(_t * 31.0), cos(_t * 27.0)) * clampf(bubble_speed - 1.0, 0.0, 6.0) * 0.5
	# Registration marks in the corners.
	var y0 := inset_top + 10.0
	var y1 := h - inset_bottom - 10.0
	for c: Vector2 in [Vector2(22, y0 + 12), Vector2(w - 22, y0 + 12), Vector2(22, y1 - 12), Vector2(w - 22, y1 - 12)]:
		var p := c + j
		draw_arc(p, 7.0, 0.0, TAU, 24, ink, 1.0, true)
		draw_line(p - Vector2(12, 0), p + Vector2(12, 0), ink, 1.0)
		draw_line(p - Vector2(0, 12), p + Vector2(0, 12), ink, 1.0)
	# The printer's colour bar along the bottom edge.
	var bar_y := y1 - 4.0
	var x := 48.0
	var patches := [INK, Color(INK, 0.6), Color(INK, 0.3), Color(INK, 0.12), SIGNAL, Color(SIGNAL, 0.55), Color(SIGNAL, 0.25), Color("e9e8e2")]
	for i in patches.size():
		var pc: Color = patches[i]
		pc = pc.lerp(Color("1a1b1e"), _darken * 0.6)
		draw_rect(Rect2(x + i * 16.0, bar_y - 10.0, 14, 10), pc)
	var f := Kit.font("mono")
	draw_string(f, Vector2(w - 250, bar_y), "HALO & HORN · PRESS ROOM · ©2026", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
