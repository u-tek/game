extends Control
## The summoning portal charging up (drawn with additive light): a rune sigil of rotating
## rings that light up rune by rune, light streaks pulled in from off-screen, motes spiralling
## into a growing core, and lightning crackle when a Legendary is coming. The sequence drives
## `charge` (0..1), `color` (the rarity tell), `crackle` and `implode` (the core collapsing
## just before the burst). Size it to the whole screen and set `center` / `radius`.

const Fx := preload("res://src/ui/summon/summon_fx.gd")

const STREAKS := 40
const MOTES := 70
const RUNES := 60
const BOLTS := 4
const BOLT_SEGS := 8
const RAYS := 20

var center := Vector2(360, 600)
var radius := 290.0
var charge := 0.0
var color := Color("18c3e8")
var crackle := 0.0
var implode := 0.0
## Whole-sigil opacity (fades it in at the start).
var reveal := 0.0

var _t := 0.0
var _spin := 0.0
var _rng := RandomNumberGenerator.new()
# Streaks: angle, phase, speed, width. Motes: angle, phase, size.
var _s := PackedFloat32Array()
var _m := PackedFloat32Array()
var _bolts: Array[PackedVector2Array] = []
var _bolt_t := 0.0
var _quad := PackedVector2Array()
var _qcol := PackedColorArray()
var _hex := PackedVector2Array()
var _rune := PackedVector2Array()
var _tri := PackedVector2Array()
var _tcol := PackedColorArray()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	material = Fx.additive()
	_rng.seed = 1234
	_quad.resize(4)
	_qcol.resize(4)
	_hex.resize(4)
	_rune.resize(3)
	_tri.resize(3)
	_tcol.resize(3)
	_s.resize(STREAKS * 4)
	for i in STREAKS:
		_s[i * 4] = _rng.randf() * TAU
		_s[i * 4 + 1] = _rng.randf()
		_s[i * 4 + 2] = _rng.randf_range(0.6, 1.3)
		_s[i * 4 + 3] = _rng.randf_range(2.0, 5.0)
	_m.resize(MOTES * 3)
	for i in MOTES:
		_m[i * 3] = _rng.randf() * TAU
		_m[i * 3 + 1] = _rng.randf()
		_m[i * 3 + 2] = _rng.randf_range(5.0, 15.0)
	for b in BOLTS:
		var p := PackedVector2Array()
		p.resize(BOLT_SEGS + 1)
		_bolts.append(p)


func _process(delta: float) -> void:
	_t += delta
	_spin += delta * (0.35 + charge * charge * 4.5)
	if crackle > 0.0:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			_bolt_t = 0.05
			_make_bolts()
	queue_redraw()


func _make_bolts() -> void:
	for b in BOLTS:
		var p := _bolts[b]
		var ang := _rng.randf() * TAU
		var end := center + Vector2.from_angle(ang) * radius * _rng.randf_range(0.75, 1.05)
		var start := center + Vector2.from_angle(ang + _rng.randf_range(-0.4, 0.4)) * radius * 0.08
		var n := (end - start).orthogonal().normalized()
		for i in BOLT_SEGS + 1:
			var k := float(i) / BOLT_SEGS
			var off := 0.0 if i == 0 or i == BOLT_SEGS else _rng.randf_range(-1.0, 1.0) * radius * 0.09
			p[i] = start.lerp(end, k) + n * off


func _draw() -> void:
	var c := center
	var r := radius * (1.0 - implode * 0.18)
	var col := color
	var hot := col.lerp(Color.WHITE, 0.45)
	var soft := Fx.soft_dot()
	var ch := charge
	var vis := reveal

	# Outer aura.
	var ar := r * (1.35 + 0.65 * ch)
	draw_texture_rect(soft, Rect2(c - Vector2(ar, ar), Vector2(ar, ar) * 2.0), false, Color(col, (0.22 + 0.4 * ch) * vis))

	# God rays fanning out behind the sigil, growing with the charge.
	if ch > 0.2:
		var ra := (ch - 0.2) / 0.8
		for i in RAYS:
			var a0 := TAU * i / RAYS + _spin * 0.04
			var ln := r * (1.3 + 1.1 * ra) * (1.0 if i % 2 == 0 else 0.7)
			var hw := 0.045 + 0.02 * float(i % 3)
			_tri[0] = c
			_tri[1] = c + Vector2.from_angle(a0 - hw) * ln
			_tri[2] = c + Vector2.from_angle(a0 + hw) * ln
			_tcol[0] = Color(hot, 0.22 * ra * vis)
			_tcol[1] = Color(col, 0.0)
			_tcol[2] = Color(col, 0.0)
			draw_polygon(_tri, _tcol)

	# Light streaks pulled in from off-screen.
	if ch > 0.05:
		var spd := 0.25 + 2.4 * ch * ch
		for i in STREAKS:
			var ang := _s[i * 4]
			var u := fposmod(_s[i * 4 + 1] + _t * spd * _s[i * 4 + 2], 1.0)
			var d := lerpf(r * 2.7, r * 0.12, u * u)
			var ln := (60.0 + 260.0 * ch) * (1.0 - u * 0.6)
			var a := sin(PI * u) * (0.12 + 0.75 * ch) * minf(1.0, (ch - 0.05) * 6.0)
			var dir := Vector2.from_angle(ang)
			Fx.streak(_quad, c + dir * d, c + dir * (d + ln), _s[i * 4 + 3] * (0.8 + ch), 0.0)
			_qcol[0] = Color(hot, a)
			_qcol[1] = Color(col, 0.0)
			_qcol[2] = Color(col, 0.0)
			_qcol[3] = Color(hot, a)
			draw_polygon(_quad, _qcol)

	# The sigil.
	var base_a := (0.22 + 0.6 * ch) * vis
	draw_arc(c, r, 0.0, TAU, 96, Color(col, base_a), 2.5, true)
	draw_arc(c, r * 0.9, 0.0, TAU, 96, Color(col, base_a * 0.7), 1.5, true)
	# Runes between the two outer circles, lighting up one by one as the charge rises.
	var rot := _spin * 0.18
	for i in RUNES:
		var fi := float(i) / RUNES
		var ang := rot + TAU * fi
		var lit := clampf((ch * 1.25 - fi) * 8.0, 0.0, 1.0)
		var sweep := pow(maxf(0.0, cos(ang * 1.0 - _t * 3.0)), 12.0) * ch
		var a := (0.16 + 0.7 * lit + 0.5 * sweep) * vis
		var rc := col.lerp(Color.WHITE, 0.3 * lit + 0.5 * sweep)
		var dir := Vector2.from_angle(ang)
		var p := c + dir * r * 0.95
		var t := dir.orthogonal()
		match i % 5:
			0:
				draw_line(c + dir * r * 0.915, c + dir * r * 0.985, Color(rc, a), 2.0, true)
			1:
				draw_arc(p, r * 0.016, 0.0, TAU, 10, Color(rc, a), 1.6, true)
			2:
				_hex[0] = p + dir * r * 0.025
				_hex[1] = p + t * r * 0.016
				_hex[2] = p - dir * r * 0.025
				_hex[3] = p - t * r * 0.016
				draw_colored_polygon(_hex, Color(rc, a * 0.85))
			3:
				_rune[0] = p - t * r * 0.018 - dir * r * 0.02
				_rune[1] = p + dir * r * 0.02
				_rune[2] = p + t * r * 0.018 - dir * r * 0.02
				draw_polyline(_rune, Color(rc, a), 1.8, true)
			_:
				draw_line(p - t * r * 0.012, p + t * r * 0.012, Color(rc, a), 2.0, true)
	# Segmented ring, counter-rotating.
	var seg := 10
	for i in seg:
		var a0 := -_spin * 0.55 + TAU * i / seg
		draw_arc(c, r * 0.78, a0, a0 + TAU / seg * 0.62, 18, Color(col, base_a * 0.9), 3.0 + 4.0 * ch, true)
	# Hexagram: two triangles turning slowly, small orbs at the points.
	var hr := r * 0.66
	for tri in 2:
		var a0 := _spin * 0.12 + (PI / 3.0 if tri == 1 else 0.0) - PI / 2.0
		for k in 3:
			var p0 := c + Vector2.from_angle(a0 + TAU * k / 3.0) * hr
			var p1 := c + Vector2.from_angle(a0 + TAU * (k + 1) / 3.0) * hr
			draw_line(p0, p1, Color(col, base_a * 0.75), 2.0, true)
			draw_texture_rect(soft, Rect2(p0 - Vector2(14, 14) * (1.0 + ch), Vector2(28, 28) * (1.0 + ch)), false, Color(hot, base_a))
	draw_arc(c, hr, 0.0, TAU, 72, Color(col, base_a * 0.5), 1.5, true)
	# Fast dashed inner ring.
	var dashes := 24
	for i in dashes:
		var a0 := _spin * 1.1 + TAU * i / dashes
		draw_arc(c, r * 0.4, a0, a0 + TAU / dashes * 0.45, 6, Color(hot, base_a * 0.8), 2.5, true)

	# Motes spiralling into the core.
	var mspd := 0.3 + 1.2 * ch
	for i in MOTES:
		var life := fposmod(_m[i * 3 + 1] + _t * mspd, 1.0)
		var dist := r * 1.35 * (1.0 - life)
		var ang := _m[i * 3] + life * 3.4 + _spin * 0.2
		var p := c + Vector2.from_angle(ang) * dist
		var sz := _m[i * 3 + 2] * (0.5 + life)
		draw_texture_rect(soft, Rect2(p - Vector2(sz, sz), Vector2(sz, sz) * 2.0), false, Color(hot, life * (0.35 + 0.6 * ch) * vis))

	# Lightning crackle (a Legendary is coming).
	if crackle > 0.01:
		for p in _bolts:
			draw_polyline(p, Color(col, 0.35 * crackle), 9.0, true)
			draw_polyline(p, Color(1, 1, 1, 0.9 * crackle), 2.5, true)

	# Core: coloured bloom and a white-hot centre that pulses faster as it charges.
	var pulse := 1.0 + 0.08 * sin(_t * (6.0 + 22.0 * ch))
	var shrink := 1.0 - implode * 0.75
	var cr := r * (0.22 + 0.32 * ch) * pulse * (1.0 - implode * 0.4)
	draw_texture_rect(soft, Rect2(c - Vector2(cr, cr) * 2.0, Vector2(cr, cr) * 4.0), false, Color(col, (0.35 + 0.5 * ch) * vis))
	var wr := r * (0.06 + 0.12 * ch) * pulse * shrink
	draw_texture_rect(soft, Rect2(c - Vector2(wr, wr) * 2.0, Vector2(wr, wr) * 4.0), false, Color(1, 1, 1, (0.6 + 0.4 * ch) * vis))
	draw_circle(c, wr * 0.55, Color(1, 1, 1, (0.5 + 0.5 * ch) * vis), true, -1.0, true)
