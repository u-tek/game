extends Control
## One burst of light (additive): a hot flash core, one or two shockwave rings, a spray of
## spark streaks and (strength >= 1) a fan of light shafts. Position it at the burst point
## (it draws around its own origin) and add it; it frees itself when done.
## strength: 0.5 = a small pop (Rare), 1 = Epic, 2 = Legendary.

const Fx := preload("res://src/ui/summon/summon_fx.gd")

var color := Color.WHITE
var strength := 1.0

var _t := 0.0
var _dur := 1.0
var _rng := RandomNumberGenerator.new()
# Sparks: angle, speed, width, length.
var _sp := PackedFloat32Array()
var _n := 0
var _quad := PackedVector2Array()
var _qcol := PackedColorArray()
var _shafts := 0
var _shaft_ang := PackedFloat32Array()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	material = Fx.additive()
	_rng.randomize()
	_dur = 0.75 + 0.3 * strength
	_quad.resize(4)
	_qcol.resize(4)
	_n = int(16 + 22 * strength)
	_sp.resize(_n * 4)
	for i in _n:
		_sp[i * 4] = _rng.randf() * TAU
		_sp[i * 4 + 1] = _rng.randf_range(260.0, 720.0) * (0.6 + 0.4 * strength)
		_sp[i * 4 + 2] = _rng.randf_range(2.5, 6.0)
		_sp[i * 4 + 3] = _rng.randf_range(30.0, 110.0) * (0.7 + 0.3 * strength)
	if strength >= 1.0:
		_shafts = 10 if strength < 1.5 else 16
		_shaft_ang.resize(_shafts)
		var off := _rng.randf() * TAU
		for i in _shafts:
			_shaft_ang[i] = off + TAU * i / _shafts + _rng.randf_range(-0.08, 0.08)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _dur:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _dur, 0.0, 1.0)
	var e := Fx.out_expo(k)
	var fade := (1.0 - k) * (1.0 - k)
	var soft := Fx.soft_dot()
	var hot := color.lerp(Color.WHITE, 0.55)
	# Flash core.
	var fr := (90.0 + 120.0 * strength) * (0.6 + 0.8 * Fx.out_cubic(minf(1.0, k * 3.0)))
	draw_texture_rect(soft, Rect2(-Vector2(fr, fr), Vector2(fr, fr) * 2.0), false, Color(hot, pow(1.0 - k, 3.0)))
	# Light shafts fanning out.
	for i in _shafts:
		var dir := Vector2.from_angle(_shaft_ang[i] + k * 0.15)
		var ln := (380.0 + 520.0 * strength) * Fx.out_cubic(minf(1.0, k * 2.2))
		var wd := (26.0 + 18.0 * strength) * (1.0 - k * 0.5)
		Fx.streak(_quad, Vector2.ZERO, dir * ln, wd, wd * 2.2)
		_qcol[0] = Color(hot, 0.5 * fade)
		_qcol[1] = Color(color, 0.0)
		_qcol[2] = Color(color, 0.0)
		_qcol[3] = Color(hot, 0.5 * fade)
		draw_polygon(_quad, _qcol)
	# Shockwave rings.
	var ring := Fx.ring()
	var r1 := 40.0 + (260.0 + 260.0 * strength) * e
	draw_texture_rect(ring, Rect2(-Vector2(r1, r1), Vector2(r1, r1) * 2.0), false, Color(hot, 0.9 * fade))
	if strength >= 1.0:
		var k2 := clampf((_t - 0.1) / _dur, 0.0, 1.0)
		var r2 := 30.0 + (180.0 + 300.0 * strength) * Fx.out_expo(k2)
		draw_texture_rect(ring, Rect2(-Vector2(r2, r2), Vector2(r2, r2) * 2.0), false, Color(color, 0.6 * (1.0 - k2) * (1.0 - k2)))
	# Sparks.
	for i in _n:
		var dir := Vector2.from_angle(_sp[i * 4])
		var d := _sp[i * 4 + 1] * e
		var ln := _sp[i * 4 + 3] * (1.0 - k * 0.7)
		Fx.streak(_quad, dir * (d + 10.0), dir * maxf(0.0, d - ln), _sp[i * 4 + 2] * (1.0 - k * 0.6), 0.0)
		_qcol[0] = Color(1, 1, 1, fade)
		_qcol[1] = Color(color, 0.0)
		_qcol[2] = Color(color, 0.0)
		_qcol[3] = Color(1, 1, 1, fade)
		draw_polygon(_quad, _qcol)
