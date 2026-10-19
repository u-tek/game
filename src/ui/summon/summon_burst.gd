extends Control
## One ink burst (the poster look's "grain burst"): a spray of ink dots and dashes flung outward, a
## ring of halftone dots racing out and a few hard ink rules, in `color` on the paper. Position it at
## the burst point (it draws around its own origin) and add it; it frees itself when done.
## strength: 0.5 = a small pop (Rare), 1 = Epic, 2 = Legendary.

const Fx := preload("res://src/ui/summon/summon_fx.gd")

var color := Color("101113")
var strength := 1.0

var _t := 0.0
var _dur := 1.0
var _rng := RandomNumberGenerator.new()
# Drops: angle, speed, size, kind (0 dot, 1 dash).
var _sp := PackedFloat32Array()
var _n := 0
var _rules := 0
var _rule_ang := PackedFloat32Array()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_rng.randomize()
	_dur = 0.6 + 0.3 * strength
	_n = int(20 + 34 * strength)
	_sp.resize(_n * 4)
	for i in _n:
		_sp[i * 4] = _rng.randf() * TAU
		_sp[i * 4 + 1] = _rng.randf_range(220.0, 760.0) * (0.6 + 0.4 * strength)
		_sp[i * 4 + 2] = _rng.randf_range(2.0, 7.0) * (0.8 + 0.25 * strength)
		_sp[i * 4 + 3] = 1.0 if _rng.randf() < 0.3 else 0.0
	if strength >= 1.0:
		_rules = 6 if strength < 1.5 else 12
		_rule_ang.resize(_rules)
		for i in _rules:
			_rule_ang[i] = _rng.randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	if _t >= _dur:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / _dur, 0.0, 1.0)
	var e := Fx.out_expo(k)
	var fade := 1.0 - k * k
	# A ring of halftone dots racing out.
	var rr := 30.0 + (240.0 + 220.0 * strength) * e
	var dots := int(36 + 30 * strength)
	for i in dots:
		var a := TAU * i / dots
		var p := Vector2.from_angle(a) * rr
		draw_circle(p, (3.0 + 3.0 * strength) * (1.0 - k), Color(color, fade))
	if strength >= 1.0:
		var r2 := 20.0 + (160.0 + 200.0 * strength) * Fx.out_expo(clampf(k * 1.3 - 0.1, 0.0, 1.0))
		var n2 := int(dots * 0.7)
		for i in n2:
			var a2 := TAU * (i + 0.5) / n2
			draw_circle(Vector2.from_angle(a2) * r2, (2.0 + 2.0 * strength) * (1.0 - k), Color(color, fade * 0.8))
	# Hard ink rules shooting out.
	for i in _rules:
		var d := Vector2.from_angle(_rule_ang[i])
		var r0 := (60.0 + 300.0 * strength) * e
		draw_line(d * r0 * 0.55, d * r0, Color(color, fade), 2.0 + strength, true)
	# The spray.
	for i in _n:
		var d2 := Vector2.from_angle(_sp[i * 4])
		var dist := _sp[i * 4 + 1] * e
		var sz := _sp[i * 4 + 2] * (1.0 - k * 0.6)
		var c := Color(color, fade)
		if _sp[i * 4 + 3] > 0.5:
			draw_line(d2 * dist, d2 * (dist + sz * 5.0), c, sz * 0.6, true)
		else:
			draw_circle(d2 * dist, sz, c)
