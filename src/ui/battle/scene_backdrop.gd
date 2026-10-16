extends Control
## Scene backdrop for the core-loop screens: "home", "chapter-1", "chapter-2", "chapter-3".
## Uses HeroArt.background(kind) when the art exists; otherwise paints the place in code
## (sky, distant silhouettes, a perspective floor) so every screen has a setting. Drifting
## motes (gold dust, embers, violet sparks) keep it alive. The static layer is drawn once;
## only the small mote layer redraws per frame.
##
##   var bd := SceneBackdrop.new()        # const SceneBackdrop := preload(this file)
##   bd.kind = "chapter-2"; bd.horizon = 0.24; bd.sigil_y = 0.5
##   add_child(bd)

const MOTES := 34

## "home" | "chapter-1" | "chapter-2" | "chapter-3"
var kind := "chapter-1"
## Where the sky meets the floor, as a fraction of the height.
var horizon := 0.3
## Battle ring on the floor at this height fraction (< 0: none).
var sigil_y := -1.0
## Dims the whole scene a little (0..1) so UI on top reads well.
var dim := 0.0
## How much the floor darkens toward the bottom edge (0..1).
var floor_shade := 0.4
var motes_enabled := true

var _tex: Texture2D
var _pal: Dictionary
var _motes: Array[Dictionary] = []
var _mote_layer: Control
var _rng := RandomNumberGenerator.new()
var _t := 0.0

const PALETTES := {
	"chapter-1": {
		"sky": [Color("17123a"), Color("3b2f6e"), Color("d9a25e")],
		"haze": Color("8c6fa8"), "far": Color("3a2d63"), "near": Color("150f2c"),
		"floor": [Color("4a3d78"), Color("1a1433")], "line": Color(0.95, 0.78, 0.45, 0.16),
		"sigil": Color("f2c14e"), "mote": Color("ffe3a0"), "rise": 1.0, "stars": 50,
	},
	"chapter-2": {
		"sky": [Color("12070e"), Color("4a1420"), Color("ff7a33")],
		"haze": Color("a4413a"), "far": Color("3c1418"), "near": Color("12060a"),
		"floor": [Color("3a1a1c"), Color("140809")], "line": Color(1.0, 0.45, 0.2, 0.12),
		"sigil": Color("ff6a3a"), "mote": Color("ffa04a"), "rise": 1.6, "stars": 20,
	},
	"chapter-3": {
		"sky": [Color("0b0920"), Color("2a1d58"), Color("5aa9bd")],
		"haze": Color("6a5aa8"), "far": Color("2a2152"), "near": Color("0d0a22"),
		"floor": [Color("31285e"), Color("0f0c24")], "line": Color(0.6, 0.55, 1.0, 0.12),
		"sigil": Color("a98bff"), "mote": Color("c7b2ff"), "rise": -0.6, "stars": 80,
	},
	# The lobby: the sanctum hall, a cool steel-and-stone interior (style v2).
	"home": {
		"sky": [Color("141920"), Color("2c3540"), Color("5c6876")],
		"haze": Color("b9d6ea"), "far": Color("232a33"), "near": Color("0f1318"),
		"floor": [Color("5a6571"), Color("161a20")], "line": Color(0.8, 0.92, 1.0, 0.07),
		"sigil": Color("6fd8ff"), "mote": Color("e4f6ff"), "rise": 0.3, "stars": 0,
		"vignette": Color(0.01, 0.015, 0.02, 0.5),
	},
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not PALETTES.has(kind):
		kind = "chapter-1"
	_pal = PALETTES[kind]
	_tex = HeroArt.background(kind)
	_rng.seed = hash(kind)
	_mote_layer = Control.new()
	_mote_layer.name = "Motes"
	_mote_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mote_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mote_layer.draw.connect(_draw_motes)
	add_child(_mote_layer)
	resized.connect(_on_resized)
	set_process(motes_enabled)
	_on_resized()


func _on_resized() -> void:
	_seed_motes()
	queue_redraw()
	if _mote_layer:
		_mote_layer.queue_redraw()


# ------------------------------------------------------------------ static layer

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var hy := h * horizon
	if _tex:
		_draw_cover(_tex)
		_vgrad(Rect2(0, 0, w, h * 0.25), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0))
	else:
		if kind == "home":
			_draw_hall(w, h, hy)
		else:
			_draw_sky(w, hy)
			match kind:
				"chapter-1":
					_draw_sanctum(w, hy)
				"chapter-2":
					_draw_wastes(w, hy)
				"chapter-3":
					_draw_abyss(w, hy)
			_draw_floor(w, h, hy)
	if sigil_y >= 0.0:
		_draw_sigil(Vector2(w * 0.5, h * sigil_y), w)
	# Side vignette and optional dim.
	var vg: Color = _pal.get("vignette", Color(0.02, 0.0, 0.06, 0.45))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.16, 0), Vector2(w * 0.16, h), Vector2(0, h)]),
		PackedColorArray([vg, Color(vg, 0.0), Color(vg, 0.0), vg]))
	draw_polygon(PackedVector2Array([Vector2(w * 0.84, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.84, h)]),
		PackedColorArray([Color(vg, 0.0), vg, vg, Color(vg, 0.0)]))
	if dim > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.02, 0.08, dim))


func _draw_cover(tex: Texture2D) -> void:
	var ts := tex.get_size()
	var k := maxf(size.x / ts.x, size.y / ts.y)
	var ds := ts * k
	draw_texture_rect(tex, Rect2((size - ds) * 0.5, ds), false)


func _draw_sky(w: float, hy: float) -> void:
	var sky: Array = _pal.sky
	var mid := hy * 0.55
	_vgrad(Rect2(0, 0, w, mid), sky[0], sky[1])
	_vgrad(Rect2(0, mid, w, hy - mid + 1.0), sky[1], sky[2])
	# Stars, fading toward the horizon.
	var r := RandomNumberGenerator.new()
	r.seed = 99 + hash(kind)
	for i in int(_pal.stars):
		var p := Vector2(r.randf() * w, pow(r.randf(), 1.6) * hy * 0.85)
		var z := r.randf()
		var a := (0.2 + z * 0.6) * (1.0 - p.y / maxf(hy, 1.0))
		draw_circle(p, 0.7 + z * 1.5, Color(1.0, 0.95, 0.88, a), true, -1.0, true)
		if z > 0.95:
			var c := Color(1.0, 0.92, 0.75, a * 0.6)
			draw_line(p - Vector2(5, 0), p + Vector2(5, 0), c, 1.0, true)
			draw_line(p - Vector2(0, 5), p + Vector2(0, 5), c, 1.0, true)
	# Horizon glow.
	var g: Color = sky[2]
	_glow_ellipse(Vector2(w * 0.5, hy), w * 0.9, hy * 0.45, Color(g.lightened(0.2), 0.45))


## Chapter 1: the broken cathedral of the sky (pointed arches, pillars, a cracked rose window).
func _draw_sanctum(w: float, hy: float) -> void:
	var haze: Color = _pal.haze
	var far: Color = _pal.far
	var near: Color = _pal.near
	# Light shafts from high left.
	for i in 4:
		var x0 := w * (0.05 + i * 0.17)
		var x1 := x0 + w * 0.08
		var spread := w * (0.35 + i * 0.05)
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1 + spread, hy), Vector2(x0 + spread * 0.7, hy)]),
			PackedColorArray([Color(1, 0.88, 0.6, 0.10), Color(1, 0.88, 0.6, 0.10), Color(1, 0.88, 0.6, 0.0), Color(1, 0.88, 0.6, 0.0)]))
	# Rose window (cracked) behind everything.
	var rc := Vector2(w * 0.5, hy * 0.5)
	var rr := minf(w * 0.3, hy * 0.42)
	var rose := Color(haze, 0.55)
	draw_arc(rc, rr, deg_to_rad(200), deg_to_rad(500), 64, rose, 6.0, true)
	draw_arc(rc, rr * 0.86, deg_to_rad(210), deg_to_rad(470), 64, Color(rose, 0.4), 2.0, true)
	draw_circle(rc, rr * 0.82, Color(1.0, 0.85, 0.55, 0.06), true, -1.0, true)
	draw_arc(rc, rr * 0.28, 0, TAU, 40, rose, 4.0, true)
	for i in 12:
		if i == 2 or i == 3:
			continue
		var a := TAU * i / 12.0
		var d := Vector2(cos(a), sin(a))
		draw_line(rc + d * rr * 0.28, rc + d * rr * 0.84, Color(rose, 0.7), 3.0, true)
		draw_arc(rc + d * rr * 0.6, rr * 0.16, 0, TAU, 24, Color(rose, 0.45), 2.0, true)
	# Far arcade: pillars joined by pointed arches, a few broken.
	var n := 7
	var base := hy + 2.0
	var pw := w / float(n)
	for i in n + 1:
		var x := pw * i
		var ph := hy * (0.42 + 0.08 * sin(i * 1.7))
		draw_rect(Rect2(x - pw * 0.09, base - ph, pw * 0.18, ph), far)
		draw_rect(Rect2(x - pw * 0.13, base - ph - 6, pw * 0.26, 8), far)
		if i < n and i != 2 and i != 5:
			var a0 := Vector2(x, base - ph)
			var a1 := Vector2(x + pw, base - hy * (0.42 + 0.08 * sin((i + 1) * 1.7)))
			var apex := (a0 + a1) * 0.5 + Vector2(0, -pw * 0.62)
			var pts := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				pts.append(a0.lerp(apex, t).lerp(apex.lerp(a1, t), t))
			draw_polyline(pts, far, pw * 0.12, true)
	_glow_ellipse(Vector2(w * 0.5, hy), w * 0.7, hy * 0.12, Color(_pal.sky[2], 0.35))
	# Near broken pillars framing the scene.
	_broken_pillar(Vector2(w * 0.04, hy + 30), w * 0.12, hy * 0.95, near, 3)
	_broken_pillar(Vector2(w * 0.94, hy + 30), w * 0.11, hy * 0.78, near, 7)


func _broken_pillar(foot: Vector2, pw: float, ph: float, col: Color, seed_v: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var pts := PackedVector2Array([foot + Vector2(-pw * 0.5, 0), foot + Vector2(-pw * 0.5, -ph)])
	var steps := 5
	for k in steps + 1:
		var t := k / float(steps)
		pts.append(foot + Vector2(-pw * 0.5 + pw * t, -ph - r.randf_range(-ph * 0.08, ph * 0.06)))
	pts.append(foot + Vector2(pw * 0.5, 0))
	draw_polygon(pts, PackedColorArray([col]))
	# Fluting highlight.
	for k in 3:
		var x := foot.x - pw * 0.25 + pw * 0.25 * k
		draw_line(Vector2(x, foot.y), Vector2(x, foot.y - ph * 0.9), Color(1, 0.9, 0.7, 0.05), 2.0)


## Chapter 2: cinder ridges, a burning volcano, obsidian spires.
func _draw_wastes(w: float, hy: float) -> void:
	var far: Color = _pal.far
	var near: Color = _pal.near
	var haze: Color = _pal.haze
	# Volcano glow and smoke.
	var vc := Vector2(w * 0.66, hy * 0.62)
	_glow_ellipse(vc, w * 0.35, hy * 0.35, Color(1.0, 0.45, 0.15, 0.35))
	for i in 5:
		var c := vc + Vector2(-i * w * 0.05, -hy * 0.1 - i * hy * 0.09)
		draw_circle(c, w * (0.05 + i * 0.022), Color(0.12, 0.04, 0.06, 0.35 - i * 0.05), true, -1.0, true)
	# Far ridge with the volcano cone.
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var ridge := PackedVector2Array([Vector2(0, hy + 2)])
	var steps := 18
	for k in steps + 1:
		var x := w * k / float(steps)
		var y := hy - hy * (0.12 + r.randf() * 0.1)
		var dv := absf(x - vc.x) / (w * 0.22)
		if dv < 1.0:
			y = minf(y, vc.y + (hy - vc.y) * dv * dv + r.randf() * 6.0)
		ridge.append(Vector2(x, y))
	ridge.append(Vector2(w, hy + 2))
	draw_polygon(ridge, PackedColorArray([Color(haze.darkened(0.45), 1.0)]))
	draw_circle(Vector2(vc.x, vc.y + 6), w * 0.035, Color(1.0, 0.6, 0.2, 0.8), true, -1.0, true)
	# Lava rivulets down the cone.
	for s in [-1.0, 0.4, 1.0]:
		var p0 := Vector2(vc.x + s * 8.0, vc.y + 10)
		var p1 := Vector2(vc.x + s * w * 0.09, hy - 4)
		draw_line(p0, p1, Color(1.0, 0.5, 0.15, 0.55), 3.0, true)
	# Mid ridge.
	var mid := PackedVector2Array([Vector2(0, hy + 2)])
	for k in 13:
		mid.append(Vector2(w * k / 12.0, hy - hy * (0.04 + r.randf() * 0.07)))
	mid.append(Vector2(w, hy + 2))
	draw_polygon(mid, PackedColorArray([far]))
	_glow_ellipse(Vector2(w * 0.5, hy), w * 0.8, hy * 0.08, Color(1.0, 0.45, 0.2, 0.35))
	# Near spires.
	for sp: Array in [[0.03, 0.75, 0.08], [0.11, 0.48, 0.05], [0.9, 0.85, 0.09], [0.97, 0.5, 0.05]]:
		var bx: float = w * float(sp[0])
		var ht: float = hy * float(sp[1])
		var bw: float = w * float(sp[2])
		draw_polygon(PackedVector2Array([Vector2(bx - bw, hy + 30), Vector2(bx - bw * 0.25, hy + 30 - ht * 0.6),
			Vector2(bx + bw * 0.05, hy + 30 - ht), Vector2(bx + bw * 0.3, hy + 30 - ht * 0.55), Vector2(bx + bw, hy + 30)]),
			PackedColorArray([near]))
		draw_line(Vector2(bx + bw * 0.05, hy + 30 - ht), Vector2(bx + bw * 0.3, hy + 30 - ht * 0.55), Color(1.0, 0.5, 0.2, 0.25), 2.0, true)


## Chapter 3: an eclipse over floating islands and broken halos.
func _draw_abyss(w: float, hy: float) -> void:
	var far: Color = _pal.far
	var near: Color = _pal.near
	var haze: Color = _pal.haze
	# Eclipse.
	var ec := Vector2(w * 0.62, hy * 0.36)
	var er := minf(w * 0.13, hy * 0.24)
	_glow_ellipse(ec, er * 3.2, er * 3.2, Color(0.55, 0.45, 1.0, 0.35))
	for i in 6:
		draw_arc(ec, er * (1.04 + i * 0.05), 0, TAU, 64, Color(0.85, 0.8, 1.0, 0.35 - i * 0.05), 3.0, true)
	draw_circle(ec, er, Color("07051a"), true, -1.0, true)
	draw_arc(ec, er, deg_to_rad(-60), deg_to_rad(60), 32, Color(0.75, 0.95, 1.0, 0.8), 2.0, true)
	# Floating islands (flat tops, jagged undersides).
	var r := RandomNumberGenerator.new()
	r.seed = 777
	for isl: Array in [[0.16, 0.42, 0.13], [0.86, 0.6, 0.1], [0.38, 0.7, 0.07], [0.74, 0.22, 0.05]]:
		var c := Vector2(w * float(isl[0]), hy * float(isl[1]))
		var iw: float = w * float(isl[2])
		var pts := PackedVector2Array([c + Vector2(-iw, 0)])
		var k := 6
		for j in k + 1:
			var t := j / float(k)
			var depth := sin(t * PI) * iw * (0.9 + r.randf() * 0.4)
			pts.append(c + Vector2(iw * (t * 2.0 - 1.0) * 0.9, depth))
		pts.append(c + Vector2(iw, 0))
		draw_polygon(pts, PackedColorArray([far.lerp(haze, 0.25)]))
		draw_line(c + Vector2(-iw, 0), c + Vector2(iw, 0), Color(0.7, 0.9, 1.0, 0.35), 2.0, true)
	# Broken halos.
	for hl: Array in [[0.28, 0.2, 0.06], [0.9, 0.34, 0.04]]:
		var c2 := Vector2(w * float(hl[0]), hy * float(hl[1]))
		var rx: float = w * float(hl[2])
		draw_set_transform(c2, -0.3, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, rx, deg_to_rad(20), deg_to_rad(300), 40, Color(1.0, 0.85, 0.55, 0.55), 4.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Low ridge and mist.
	var ridge := PackedVector2Array([Vector2(0, hy + 2)])
	for j in 15:
		ridge.append(Vector2(w * j / 14.0, hy - hy * (0.03 + r.randf() * 0.06)))
	ridge.append(Vector2(w, hy + 2))
	draw_polygon(ridge, PackedColorArray([near]))
	_glow_ellipse(Vector2(w * 0.5, hy), w * 0.85, hy * 0.1, Color(0.45, 0.75, 0.85, 0.3))


## Home (the lobby): the sanctum hall. A tall steel-and-stone interior: a great arched
## window of pale morning light with spires beyond, light shafts across the floor, dark side
## pylons with indicator lights and hatched hazard bands, a ceiling truss, and a technical
## halo ring hanging behind the lobby hero's head. Cool greys so the dark chrome and the
## hero's colors read on top.
func _draw_hall(w: float, h: float, hy: float) -> void:
	var sky: Array = _pal.sky
	var haze: Color = _pal.haze
	var near: Color = _pal.near
	_vgrad(Rect2(0, 0, w, hy * 0.45), sky[0], sky[1])
	_vgrad(Rect2(0, hy * 0.45, w, hy * 0.55 + 1.0), sky[1], sky[2])
	# Wall panel seams.
	for i in range(1, 12):
		var x := w * i / 12.0
		draw_line(Vector2(x, hy * 0.06), Vector2(x, hy), Color(1, 1, 1, 0.03), 2.0)
	for k in 3:
		var y := hy * (0.3 + k * 0.24)
		draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.12), 3.0)
		draw_line(Vector2(0, y + 3.0), Vector2(w, y + 3.0), Color(1, 1, 1, 0.04), 1.0)
	# The great window.
	var ww := w * 0.6
	var win := Rect2(w * 0.5 - ww * 0.5, hy * 0.1, ww, hy * 0.86)
	_glow_ellipse(Vector2(w * 0.5, win.position.y + win.size.y * 0.55), ww * 1.05, win.size.y * 0.75, Color(0.78, 0.9, 1.0, 0.22))
	var arch := _arch_points(win)
	var cols := PackedColorArray()
	for p in arch:
		var t := clampf((p.y - win.position.y) / win.size.y, 0.0, 1.0)
		cols.append(Color("8fb9d8").lerp(Color("eef6fb"), pow(t, 0.8)))
	draw_polygon(arch, cols)
	# Beyond the glass: soft clouds and pale spires in the light.
	var r := RandomNumberGenerator.new()
	r.seed = 5150
	var base := win.end.y
	var x := win.position.x
	while x < win.end.x:
		var bw := ww * r.randf_range(0.05, 0.1)
		var ht := win.size.y * r.randf_range(0.08, 0.2) * (1.8 if r.randf() < 0.2 else 1.0)
		var col := Color(haze.darkened(0.15), 0.55)
		var x1 := minf(x + bw, win.end.x)
		draw_rect(Rect2(x, base - ht, x1 - x, ht), col)
		draw_polygon(PackedVector2Array([Vector2(x, base - ht), Vector2((x + x1) * 0.5, base - ht - bw * 1.4), Vector2(x1, base - ht)]), PackedColorArray([col]))
		x += bw + ww * r.randf_range(0.0, 0.04)
	for k in 6:
		var c := Vector2(win.position.x + ww * r.randf(), win.position.y + win.size.y * r.randf_range(0.35, 0.8))
		_glow_ellipse(c, ww * r.randf_range(0.18, 0.3), ww * 0.05, Color(1, 1, 1, 0.35))
	# Mullions, transoms and tracery.
	var frame := Color("1a2027")
	for k in range(1, 4):
		var mx := win.position.x + ww * k / 4.0
		var top_y := _arch_y(win, mx)
		draw_line(Vector2(mx, top_y), Vector2(mx, win.end.y), frame, 7.0)
	for ty: float in [0.5, 0.74]:
		var yy := win.position.y + win.size.y * ty
		draw_line(Vector2(win.position.x, yy), Vector2(win.end.x, yy), frame, 6.0)
	var rc := Vector2(w * 0.5, win.position.y + ww * 0.36)
	draw_arc(rc, ww * 0.17, 0, TAU, 48, frame, 6.0, true)
	draw_arc(rc, ww * 0.07, 0, TAU, 32, frame, 5.0, true)
	for k in 8:
		var a := TAU * k / 8.0
		draw_line(rc + Vector2(cos(a), sin(a)) * ww * 0.07, rc + Vector2(cos(a), sin(a)) * ww * 0.17, frame, 4.0, true)
	var closed := arch.duplicate()
	closed.append(arch[0])
	draw_polyline(closed, frame, 12.0, true)
	draw_polyline(closed, Color(1, 1, 1, 0.22), 2.0, true)
	# Light shafts falling from the window to the floor.
	for k in 5:
		var x0 := win.position.x + ww * (0.08 + k * 0.2)
		var x1 := x0 + ww * 0.1
		var spread := w * (0.1 + k * 0.05)
		var lc := Color(0.86, 0.95, 1.0, 0.07)
		draw_polygon(PackedVector2Array([Vector2(x0, win.position.y + win.size.y * 0.3), Vector2(x1, win.position.y + win.size.y * 0.3),
			Vector2(x1 + spread, h * 0.98), Vector2(x0 + spread * 0.6, h * 0.98)]),
			PackedColorArray([lc, lc, Color(lc, 0.0), Color(lc, 0.0)]))
	# Floor: polished stone with the window's light pool and technical guide lines.
	var fl: Array = _pal.floor
	_vgrad(Rect2(0, hy, w, h - hy), fl[0], fl[1])
	_glow_ellipse(Vector2(w * 0.5, hy + (h - hy) * 0.22), w * 0.62, (h - hy) * 0.2, Color(0.85, 0.95, 1.0, 0.3))
	var line: Color = _pal.line
	var vp := Vector2(w * 0.5, hy - (h - hy) * 0.7)
	for i in 13:
		var bx := w * (-0.7 + i * 0.2)
		var a2 := (hy - vp.y) / (h - vp.y)
		draw_line(vp.lerp(Vector2(bx, h), a2), Vector2(bx, h), line, 1.5, true)
	for i in range(1, 10):
		var t := pow(i / 9.0, 1.8)
		var yy := hy + (h - hy) * t
		draw_line(Vector2(0, yy), Vector2(w, yy), Color(line, line.a * (0.5 + t)), 1.5, true)
	var cy := Color(0.43, 0.85, 1.0, 0.22)
	for s: float in [-1.0, 1.0]:
		draw_line(Vector2(w * 0.5 + s * w * 0.18, hy + 4.0), Vector2(w * 0.5 + s * w * 0.62, h), cy, 3.0, true)
	draw_rect(Rect2(0, hy - 2.0, w, 4.0), Color(0, 0, 0, 0.25))
	# Side pylons.
	for side: float in [-1.0, 1.0]:
		var pw := w * 0.15
		var px := 0.0 if side < 0.0 else w - pw
		var pr := Rect2(px, 0, pw, hy + (h - hy) * 0.08)
		_vgrad(pr, near, Color("1e252e"))
		var edge := px + pw if side < 0.0 else px
		draw_line(Vector2(edge, 0), Vector2(edge, pr.end.y), Color(0.6, 0.85, 1.0, 0.22), 2.0)
		draw_line(Vector2(edge - side * 8.0, 0), Vector2(edge - side * 8.0, pr.end.y), Color(1, 1, 1, 0.05), 1.0)
		var yy := 90.0
		while yy < pr.end.y:
			draw_line(Vector2(px, yy), Vector2(px + pw, yy), Color(1, 1, 1, 0.05), 1.0)
			yy += 110.0
		# Hatched hazard band.
		var band := Rect2(px, hy * 0.7, pw, 26.0)
		draw_rect(band, Color(0, 0, 0, 0.3))
		var hx := band.position.x - band.size.y
		while hx < band.end.x:
			var a3 := Vector2(maxf(hx, band.position.x), band.end.y - (maxf(hx, band.position.x) - hx))
			var b3 := Vector2(minf(hx + band.size.y, band.end.x), band.position.y + (hx + band.size.y - minf(hx + band.size.y, band.end.x)))
			draw_line(a3, b3, Color(0.43, 0.85, 1.0, 0.35), 4.0)
			hx += 14.0
		# Indicator lights.
		for k in 5:
			var ly := hy * (0.16 + k * 0.11)
			var lx := px + (pw - 26.0 if side < 0.0 else 12.0)
			var lc2 := Color("6fd8ff") if k % 3 != 1 else Color("ffb24a")
			draw_rect(Rect2(lx, ly, 14.0, 4.0), Color(lc2, 0.85))
			_glow_ellipse(Vector2(lx + 7.0, ly + 2.0), 22.0, 8.0, Color(lc2, 0.35))
	# Ceiling truss.
	var tb := hy * 0.07
	_vgrad(Rect2(0, 0, w, tb), Color("0b0e12"), Color("181e25"))
	draw_line(Vector2(0, tb), Vector2(w, tb), Color(1, 1, 1, 0.1), 2.0)
	var step := w / 10.0
	for k in 10:
		var x0 := k * step
		draw_line(Vector2(x0, tb - 4.0), Vector2(x0 + step * 0.5, 8.0), Color(1, 1, 1, 0.07), 3.0)
		draw_line(Vector2(x0 + step * 0.5, 8.0), Vector2(x0 + step, tb - 4.0), Color(1, 1, 1, 0.07), 3.0)
	# The technical halo ring behind the hero's head.
	var hc := Vector2(w * 0.5, hy * 0.36)
	var hr := w * 0.34
	_glow_ellipse(hc, hr * 1.2, hr * 1.2, Color(0.43, 0.85, 1.0, 0.1))
	var ring := Color(0.55, 0.88, 1.0, 0.5)
	for k in 6:
		var a0 := TAU * k / 6.0 + 0.12
		draw_arc(hc, hr, a0, a0 + TAU / 6.0 - 0.18, 24, ring, 3.0, true)
	draw_arc(hc, hr + 12.0, 0, TAU, 96, Color(ring, 0.18), 1.0, true)
	draw_arc(hc, hr - 10.0, deg_to_rad(200), deg_to_rad(340), 48, Color(ring, 0.35), 6.0, true)
	for k in 60:
		var a := TAU * k / 60.0
		var d := Vector2(cos(a), sin(a))
		var l := 10.0 if k % 5 == 0 else 5.0
		draw_line(hc + d * (hr + 14.0), hc + d * (hr + 14.0 + l), Color(ring, 0.4 if k % 5 == 0 else 0.22), 1.5, true)


func _arch_points(r: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(r.position.x, r.end.y))
	var n := 24
	for k in n + 1:
		var x := r.position.x + r.size.x * k / float(n)
		pts.append(Vector2(x, _arch_y(r, x)))
	pts.append(Vector2(r.end.x, r.end.y))
	return pts


## Top edge at x of a pointed (two-centred) arch whose apex touches the top of r.
func _arch_y(r: Rect2, x: float) -> float:
	var w := r.size.x
	var rad := w * 0.75
	var rise := sqrt(rad * rad - pow(w * 0.5 - rad, 2.0))
	var spring := r.position.y + rise
	# Each half is an arc centred on the opposite side of the span.
	var cx := r.position.x + (rad if x - r.position.x <= w * 0.5 else w - rad)
	var dx := x - cx
	return spring - sqrt(maxf(rad * rad - dx * dx, 0.0))


func _draw_floor(w: float, h: float, hy: float) -> void:
	var fl: Array = _pal.floor
	_vgrad(Rect2(0, hy, w, h - hy), fl[1], fl[0])
	# Darken toward the bottom edge a bit so UI reads.
	_vgrad(Rect2(0, h - (h - hy) * 0.35, w, (h - hy) * 0.35), Color(0, 0, 0, 0), Color(0.02, 0.0, 0.05, floor_shade))
	var line: Color = _pal.line
	var vp := Vector2(w * 0.5, hy - (h - hy) * 0.5)
	# Radial floor seams toward the vanishing point.
	for i in 15:
		var bx := w * (-0.9 + i * 0.2)
		var a := (hy - vp.y) / (h - vp.y)
		var top := vp.lerp(Vector2(bx, h), a)
		draw_line(top, Vector2(bx, h), line, 1.5, true)
	# Horizontal seams, closer together near the horizon.
	for i in range(1, 12):
		var t := pow(i / 11.0, 1.9)
		var y := hy + (h - hy) * t
		draw_line(Vector2(0, y), Vector2(w, y), Color(line, line.a * (0.4 + t)), 1.5, true)
	# Horizon haze line.
	_vgrad(Rect2(0, hy - 2, w, (h - hy) * 0.12), Color(_pal.haze, 0.35), Color(_pal.haze, 0.0))
	match kind:
		"chapter-2":
			_draw_lava_cracks(w, h, hy)
		"chapter-3":
			for i in 4:
				var y := hy + (h - hy) * (0.15 + i * 0.22)
				_glow_ellipse(Vector2(w * (0.3 + 0.4 * (i % 2)), y), w * 0.6, (h - hy) * 0.05, Color(0.6, 0.55, 0.95, 0.10))


func _draw_lava_cracks(w: float, h: float, hy: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 1337
	for i in 7:
		var p := Vector2(r.randf() * w, hy + (h - hy) * (0.1 + r.randf() * 0.85))
		var pts := PackedVector2Array([p])
		var dir := Vector2.from_angle(r.randf() * TAU)
		dir.y *= 0.35
		for k in 6:
			dir = dir.rotated(r.randf_range(-0.7, 0.7))
			var depth := (p.y - hy) / (h - hy)
			p += dir.normalized() * (20.0 + 30.0 * depth)
			pts.append(p)
		var d := (pts[0].y - hy) / (h - hy)
		draw_polyline(pts, Color(1.0, 0.35, 0.1, 0.18), 7.0 * (0.4 + d), true)
		draw_polyline(pts, Color(1.0, 0.65, 0.25, 0.55), 2.0 * (0.5 + d), true)


func _draw_sigil(c: Vector2, w: float) -> void:
	var col: Color = _pal.sigil
	var rx := w * 0.44
	draw_set_transform(c, 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, rx, Color(col, 0.05), true, -1.0, true)
	draw_arc(Vector2.ZERO, rx, 0, TAU, 96, Color(col, 0.35), 4.0, true)
	draw_arc(Vector2.ZERO, rx * 0.92, 0, TAU, 96, Color(col, 0.18), 2.0, true)
	draw_arc(Vector2.ZERO, rx * 0.55, 0, TAU, 72, Color(col, 0.2), 2.0, true)
	for i in 16:
		var a := TAU * i / 16.0
		var d := Vector2(cos(a), sin(a))
		draw_line(d * rx * 0.58, d * rx * (0.88 if i % 2 == 0 else 0.76), Color(col, 0.16), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ helpers

func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Soft elliptical glow made of stacked translucent ellipses.
func _glow_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if ry <= 0.0 or rx <= 0.0:
		return
	draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
	for i in 8:
		var t := i / 8.0
		draw_circle(Vector2.ZERO, rx * (1.0 - t * 0.85), Color(col, col.a * 0.16), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ motes

func _seed_motes() -> void:
	_motes.clear()
	if not motes_enabled or size.x <= 0.0:
		return
	for i in MOTES:
		_motes.append(_new_mote(true))


func _new_mote(anywhere: bool) -> Dictionary:
	var rise: float = _pal.get("rise", 1.0)
	var y := _rng.randf() * size.y if anywhere else (size.y + 10.0 if rise > 0.0 else -10.0)
	return {
		"p": Vector2(_rng.randf() * size.x, y),
		"v": Vector2(_rng.randf_range(-6.0, 6.0), -rise * _rng.randf_range(10.0, 26.0)),
		"r": _rng.randf_range(1.2, 3.2),
		"ph": _rng.randf() * TAU,
		"a": _rng.randf_range(0.35, 0.9),
	}


func _process(delta: float) -> void:
	if _motes.is_empty() or not is_visible_in_tree():
		return
	_t += delta
	for i in _motes.size():
		var m: Dictionary = _motes[i]
		var p: Vector2 = m.p
		p += (m.v as Vector2) * delta + Vector2(sin(_t * 0.9 + float(m.ph)) * 8.0 * delta, 0)
		m.p = p
		if p.y < -12.0 or p.y > size.y + 12.0 or p.x < -12.0 or p.x > size.x + 12.0:
			_motes[i] = _new_mote(false)
	_mote_layer.queue_redraw()


func _draw_motes() -> void:
	var col: Color = _pal.get("mote", Color.WHITE)
	for m in _motes:
		var tw := 0.6 + 0.4 * sin(_t * 2.3 + float(m.ph))
		var a: float = float(m.a) * tw
		var r: float = m.r
		_mote_layer.draw_circle(m.p, r * 3.2, Color(col, a * 0.12), true, -1.0, true)
		_mote_layer.draw_circle(m.p, r, Color(col.lightened(0.3), a), true, -1.0, true)
