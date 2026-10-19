extends RefCounted
## HUD pieces for style v4 "Signal" (docs/dev/ui-style-v4.md): the scientific-instrument line work
## that frames heroes, maps and devices. All geometry, drawn in _draw, crisp at any scale. Build them
## through Kit (Kit.hud_ring, Kit.leader, Kit.ruler, Kit.led, Kit.stat_dots, Kit.scanline).
##   Ring     concentric dial: tick ring, rotating segment band, dashed inner ring, optional
##            progress arc with an end dot, mono labels around it
##   Leader   a callout: anchor dot, a line that rises then runs sideways, a mono label (and an
##            optional bold title) at its end; draws itself on
##   Ruler    a tick ruler (horizontal or vertical) with mono numbers on major ticks
##   Led      a status light with a soft glow; steady, blinking or breathing
##   Dots     stat dots (filled of max), round or square
##   Scan     a bright line sweeping across its rect, with a faint trail (big moments)

## Concentric instrument dial, centred in the control.
class Ring:
	extends Control
	## Outer radius in px (0 = fit the control).
	var radius := 0.0
	var color := Color(1, 1, 1, 0.22)
	var accent := Color("ff4b1f")
	## 0..1 accent arc from 12 o'clock, clockwise (< 0 = none).
	var progress := -1.0
	## Degrees per second for the segment band (the dashed ring turns the other way at half speed).
	var spin := 6.0
	## Mono labels placed around the dial: [[degrees, text], ...] (0 = top, clockwise).
	var labels: Array = []
	var label_size := 13
	## Minor tick every `tick_step` degrees (0 = no tick ring); every 6th is long.
	var tick_step := 3.0
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)
		set_process(spin != 0.0 and Kit.motion_ok())

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := radius if radius > 0.0 else minf(size.x, size.y) * 0.5 - 2.0
		if r < 8.0:
			return
		var rot := deg_to_rad(_t * spin)
		# Outer hairline and tick ring.
		draw_arc(c, r, 0.0, TAU, 160, color, 1.0, true)
		if tick_step > 0.0:
			var n := int(round(360.0 / tick_step))
			for i in n:
				var a := deg_to_rad(i * tick_step) - PI * 0.5
				var long := i % 6 == 0
				var l := 10.0 if long else 4.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * (r - 3.0), c + d * (r - 3.0 - l), Color(color, color.a * (1.0 if long else 0.6)), 1.0, true)
		# Rotating segment band (four arcs with gaps).
		var rb := r * 0.84
		for k in 4:
			var a0 := rot + k * PI * 0.5 + 0.12
			draw_arc(c, rb, a0, a0 + PI * 0.5 - 0.5 - (0.25 if k % 2 == 0 else 0.0), 48, Color(color, color.a * 1.1), 4.0, true)
		# Dashed inner ring, counter-rotating.
		var ri := r * 0.7
		var dash := 48
		for k in dash:
			if k % 2 == 1:
				continue
			var a1 := -rot * 0.5 + k * TAU / dash
			draw_arc(c, ri, a1, a1 + TAU / dash * 0.7, 6, Color(color, color.a * 0.7), 1.0, true)
		# Crosshair notches at the four compass points.
		for k in 4:
			var a2 := k * PI * 0.5
			var d2 := Vector2(cos(a2), sin(a2))
			draw_line(c + d2 * (ri - 8.0), c + d2 * (ri + 8.0), Color(color, color.a * 1.4), 1.0, true)
		# Progress arc.
		if progress >= 0.0:
			var p := clampf(progress, 0.0, 1.0)
			var rp := r * 0.92
			draw_arc(c, rp, -PI * 0.5, -PI * 0.5 + TAU, 160, Color(accent, 0.18), 3.0, true)
			if p > 0.0:
				draw_arc(c, rp, -PI * 0.5, -PI * 0.5 + TAU * p, maxi(int(160 * p), 4), accent, 3.0, true)
				var ae := -PI * 0.5 + TAU * p
				draw_circle(c + Vector2(cos(ae), sin(ae)) * rp, 4.5, accent)
		# Labels.
		var f := Kit.font("mono")
		for l in labels:
			var a3 := deg_to_rad(float(l[0])) - PI * 0.5
			var pos := c + Vector2(cos(a3), sin(a3)) * (r + 14.0)
			var txt := str(l[1])
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			var off := Vector2(-w * 0.5 + cos(a3) * w * 0.5, label_size * 0.35)
			draw_string(f, pos + off, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(color, minf(color.a * 2.6, 1.0)))


## A callout line from an anchor to a label. Position the control so its origin is the anchor.
class Leader:
	extends Control
	var text := ""
	var title := ""
	var color := Color(1, 1, 1, 0.75)
	var title_color := Color("f1f0eb")
	## Vertical rise (negative = up) and horizontal run (negative = left) of the elbow.
	var rise := -60.0
	var run := 80.0
	var text_size := 14
	var title_size := 24
	## 0..1: how much of the callout is drawn (Kit.leader animates it on).
	var reveal := 1.0:
		set(v):
			reveal = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var a := Vector2.ZERO
		var b := Vector2(0, rise)
		var e := Vector2(run, rise)
		var l1 := absf(rise)
		var l2 := absf(run)
		var total := maxf(l1 + l2, 1.0)
		var drawn := total * clampf(reveal, 0.0, 1.0)
		draw_circle(a, 3.5, color)
		draw_arc(a, 8.0, 0.0, TAU, 24, Color(color, color.a * 0.6), 1.0, true)
		if drawn <= l1:
			draw_line(a, a.lerp(b, drawn / maxf(l1, 0.001)), color, 1.0, true)
			return
		draw_line(a, b, color, 1.0, true)
		var t := (drawn - l1) / maxf(l2, 0.001)
		draw_line(b, b.lerp(e, t), color, 1.0, true)
		if t < 0.999:
			return
		draw_line(e + Vector2(0, -5), e + Vector2(0, 5), color, 1.0, true)
		var f := Kit.font("mono")
		var fb := Kit.font("extrabold")
		var right := run >= 0.0
		var pad := 8.0
		var y := rise
		if title != "":
			var tw := fb.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
			var tx := e.x + pad if right else e.x - pad - tw
			draw_string(fb, Vector2(tx, y - 6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, title_color)
		if text != "":
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
			var x := e.x + pad if right else e.x - pad - w
			draw_string(f, Vector2(x, y + text_size + (4.0 if title != "" else -2.0)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)


## Tick ruler. Horizontal unless `vertical`.
class Ruler:
	extends Control
	var color := Color(1, 1, 1, 0.3)
	var step := 8.0
	var major_every := 5
	var vertical := false
	## Numbers on major ticks: start value and increment (empty `numbers` = none).
	var numbers := true
	var start := 0
	var increment := 10
	var text_size := 11

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var f := Kit.font("mono")
		var length := size.y if vertical else size.x
		var depth := size.x if vertical else size.y
		var n := int(length / step)
		for i in n + 1:
			var p := i * step
			var major := i % major_every == 0
			var l := depth * (0.6 if major else 0.3)
			var col := Color(color, color.a * (1.0 if major else 0.6))
			if vertical:
				draw_line(Vector2(0, p), Vector2(l, p), col, 1.0)
			else:
				draw_line(Vector2(p, depth), Vector2(p, depth - l), col, 1.0)
			if major and numbers and not vertical and p + 20.0 < length:
				draw_string(f, Vector2(p + 3.0, depth - l), str(start + (i / major_every) * increment), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, col)


## Status light with a glow.
class Led:
	extends Control
	var color := Color("ff3b1f")
	## "steady" | "blink" | "breathe"
	var mode := "steady"
	var period := 1.4
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_process(mode != "steady" and Kit.motion_ok())

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var k := 1.0
		if mode == "blink":
			k = 1.0 if fmod(_t, period) < period * 0.55 else 0.18
		elif mode == "breathe":
			k = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * TAU / period))
		for i in 5:
			var g := 1.0 - i / 5.0
			draw_circle(c, r * (0.45 + 0.55 * (i + 1) / 5.0), Color(color, 0.09 * k * g))
		draw_circle(c, r * 0.36, Color(color.lightened(0.35 * k), 0.35 + 0.65 * k))
		draw_circle(c - Vector2(r * 0.08, r * 0.1), r * 0.12, Color(1, 1, 1, 0.55 * k))


## Stat dots: `filled` of `count`.
class Dots:
	extends Control
	var count := 5
	var filled := 3
	var color := Color("f1f0eb")
	var empty := Color(1, 1, 1, 0.22)
	var square := false
	var gap := 6.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var d := size.y if size.y > 0.0 else 14.0
		return Vector2(count * d + (count - 1) * gap, d)

	func _draw() -> void:
		var d := size.y
		for i in count:
			var c := Vector2(i * (d + gap) + d * 0.5, d * 0.5)
			var on := i < filled
			if square:
				var r := Rect2(c - Vector2(d, d) * 0.4, Vector2(d, d) * 0.8)
				if on:
					draw_rect(r, color)
				else:
					draw_rect(r, empty, false, 1.0)
			elif on:
				draw_circle(c, d * 0.42, color)
			else:
				draw_arc(c, d * 0.38, 0.0, TAU, 24, empty, 1.5, true)


## A bright line sweeping down (or across) its rect with a fading trail.
class Scan:
	extends Control
	var color := Color("ff4b1f")
	var period := 3.2
	var horizontal := false
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_process(Kit.motion_ok())

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var k := fmod(_t, period) / period
		var trail := 26
		for i in trail:
			var kk := k - i * 0.004
			if kk < 0.0:
				break
			var a := color.a * (1.0 - float(i) / trail) * (0.9 if i == 0 else 0.22)
			if horizontal:
				var x := size.x * kk
				draw_line(Vector2(x, 0), Vector2(x, size.y), Color(color, a), 1.0 if i > 0 else 2.0)
			else:
				var y := size.y * kk
				draw_line(Vector2(0, y), Vector2(size.x, y), Color(color, a), 1.0 if i > 0 else 2.0)



## Floating dust and bokeh: soft discs drifting up through the scene (big moments, the Lobby).
## `depth` 0..1 sets size and blur (near = big, soft); a few bright motes run above 1.0 so they bloom.
class Dust:
	extends Control
	var count := 36
	var color := Color(1.0, 0.42, 0.22)
	var near := false
	var _p: Array = []
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _ready() -> void:
		_rng.seed = 909 if near else 404
		for i in count:
			_p.append(_spawn(true))
		set_process(Kit.motion_ok())

	func _spawn(anywhere: bool) -> Dictionary:
		var depth := _rng.randf()
		var r := lerpf(1.2, 3.0, depth) if not near else lerpf(6.0, 16.0, depth)
		return {"x": _rng.randf() * size.x, "y": (_rng.randf() if anywhere else 1.05) * size.y,
			"r": r, "v": lerpf(6.0, 22.0, _rng.randf()), "ph": _rng.randf() * TAU,
			"a": lerpf(0.15, 0.6, _rng.randf()) * (0.3 if near else 1.0), "hot": _rng.randf() < 0.12}

	func _process(delta: float) -> void:
		for i in _p.size():
			var d: Dictionary = _p[i]
			d["y"] -= d["v"] * delta
			d["ph"] += delta * 0.6
			if d["y"] < -20.0:
				_p[i] = _spawn(false)
		queue_redraw()

	func _draw() -> void:
		for d: Dictionary in _p:
			var pos := Vector2(d["x"] + sin(d["ph"]) * 8.0, d["y"])
			var c := color * (2.2 if d["hot"] else 1.0)
			var a: float = d["a"]
			var r: float = d["r"]
			if near:
				# Out-of-focus disc: a soft fill with a slightly brighter rim.
				draw_circle(pos, r, Color(c, a * 0.18))
				draw_arc(pos, r - 0.5, 0.0, TAU, 32, Color(c, a * 0.3), 1.2, true)
			else:
				draw_circle(pos, r * 2.4, Color(c, a * 0.08))
				draw_circle(pos, r, Color(c, a * 0.55))
