extends Control
## A campaign world turning on its dossier (style v4 "Signal", poster look; docs/dev/ui-style-v4.md,
## built like the owner's planet-dossier reference): the chapter's planet, modelled and baked in
## Blender (tools/blender/planets.py: albedo, normal and height maps per world) and shaded in real
## time by planet.gdshader (a grey studio render on the day side that turns into halftone print in
## the shadow, an ink terminator, lava that glows, ice and crystal that glint), in an IsoView at 30
## fps. Around it the instrument's line work, drawn in 2D: ring arcs with ticks and segment marks
## that draw on, a crosshair, diagonal strokes, a status line that types in (a locked world's
## "Signal lost ..."), the MASS tag, a barcode ring with its ID turning slowly, and a vertical gauge
## whose marker is the chapter's progress. A soft shadow lies under the planet on the paper.
##
##   var w := WorldView.new(); w.world = 3; w.center = Vector2(330, 280); w.radius = 190.0
##   w.size = Vector2(684, 560); add_child(w); w.pressed.connect(...)
##
## A drag turns the world (a flick keeps it spinning, then it settles back into its slow turn and
## its tilt eases back); a tap on the disc emits `pressed`. Reduce motion: no turn, no typing, no
## draw-on (a drag still turns it). zoom(k) scales the planet up about its centre (the dossier's
## zoom into the survey map).

signal pressed

const IsoView := preload("res://src/ui/v4/survey/iso_view.gd")
const SHADER := preload("res://src/ui/v4/survey/planet.gdshader")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")
## Degrees per second of the idle turn.
const SPIN := 5.0

## Per world (1..6): glow (lava, embers), glint (ice, crystal), vertex relief, normal strength, tint.
const LOOK := {
	1: {"glow": 0.0, "glint": 0.25, "relief": 0.018, "normal": 1.25, "tint": Color(1.0, 0.99, 0.97)},
	2: {"glow": 0.5, "glow_range": Vector2(0.55, 0.98), "glint": 0.0, "relief": 0.022, "normal": 1.25, "tint": Color(1.0, 0.97, 0.95), "glow_color": Color("ff5a26")},
	3: {"glow": 0.0, "glint": 0.0, "relief": 0.02, "normal": 1.2, "tint": Color(0.98, 0.98, 1.0)},
	4: {"glow": 0.0, "glint": 0.8, "relief": 0.014, "normal": 1.25, "tint": Color(0.97, 0.99, 1.0)},
	5: {"glow": 1.0, "glint": 0.0, "relief": 0.02, "normal": 1.2, "tint": Color(1.0, 1.0, 1.0), "glow_color": Color("ff4b1f")},
	6: {"glow": 0.0, "glint": 1.0, "relief": 0.022, "normal": 1.25, "tint": Color(0.98, 0.97, 1.0)},
}

## The world (1..6), the planet's centre and radius (local px); set before adding to the tree.
var world := 1
var center := Vector2(300, 300)
var radius := 180.0
## Still locked: the planet prints drained and the line reads "Signal lost".
var locked := false
## Just the planet (no instrument, no turn, rendered once): the neighbour peeking in.
var bare := false
## 0..1: the gauge's marker (stages cleared).
var progress := 0.0
## The MASS tag's value and the barcode ring's ID line.
var mass_text := ""
var id_text := ""
var loading_text := ""

var view: IsoView
var _pivot: Node3D
var _planet: MeshInstance3D
var _mat: ShaderMaterial
var _hud: Control
var _shadow: TextureRect
var _spin := 0.0
var _vel := 0.0
var _tilt := 0.0
var _holding := false
var _moved := false
var _press_at := Vector2.ZERO
var _t := 0.0
var _zoom := 1.0

static var _mesh: SphereMesh
static var _shadow_tex: GradientTexture2D


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP


func _ready() -> void:
	clip_contents = false
	# The world's own seeded starting angle, so each one shows a different face first.
	_spin = float((world * 137) % 360)
	_shadow = TextureRect.new()
	_shadow.texture = _shadow_texture()
	_shadow.mouse_filter = MOUSE_FILTER_IGNORE
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_shadow)
	view = IsoView.new()
	view.yaw = 0.0
	view.pitch = 0.0
	view.sway = 0.0
	view.pitch_sway = 0.0
	view.tilt_yaw = 5.0
	view.tilt_pitch = 3.0
	view.drag_turn = false
	view.fps_cap = 30.0
	view.max_scale = 1.8
	view.animate = not bare
	add_child(view)
	_pivot = Node3D.new()
	view.world.add_child(_pivot)
	_planet = MeshInstance3D.new()
	_planet.mesh = _sphere()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_apply_look()
	_planet.material_override = _mat
	_pivot.add_child(_planet)
	if not bare:
		_hud = _Hud.new()
		_hud.wv = self
		_hud.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_hud)
	else:
		_shadow.modulate.a = 0.6
		set_process(false)
	resized.connect(_layout)
	_layout()
	_place()


## Only the planet's disc takes touches (the rest of the instrument is print).
func _has_point(point: Vector2) -> bool:
	return point.distance_to(center) <= radius * _zoom * 1.12


static func _sphere() -> SphereMesh:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 320
		_mesh.rings = 160
	return _mesh


static func _shadow_texture() -> GradientTexture2D:
	if _shadow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.06, 0.06, 0.07, 0.34))
		g.set_color(1, Color(0.06, 0.06, 0.07, 0.0))
		g.add_point(0.55, Color(0.06, 0.06, 0.07, 0.16))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = g
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to = Vector2(1.0, 0.5)
		_shadow_tex.width = 128
		_shadow_tex.height = 128
	return _shadow_tex


static func texture_path(n: int, kind: String) -> String:
	return "res://assets/art/worlds/w%d_%s.%s" % [n, kind, "png" if kind == "height" else "jpg"]


func _apply_look() -> void:
	var look: Dictionary = LOOK.get(world, LOOK[1])
	for kind: String in ["albedo", "normal", "height"]:
		var p := texture_path(world, kind)
		if ResourceLoader.exists(p):
			_mat.set_shader_parameter(kind + "_tex", load(p))
	_mat.set_shader_parameter("paper", PAPER)
	_mat.set_shader_parameter("ink", INK)
	_mat.set_shader_parameter("dot_ink", INK)
	_mat.set_shader_parameter("glow_color", look.get("glow_color", SIGNAL))
	_mat.set_shader_parameter("tint", look.get("tint", Color.WHITE))
	_mat.set_shader_parameter("glow", float(look.get("glow", 0.0)))
	_mat.set_shader_parameter("glow_range", look.get("glow_range", Vector2(0.12, 0.8)))
	_mat.set_shader_parameter("glint", float(look.get("glint", 0.0)))
	_mat.set_shader_parameter("relief", float(look.get("relief", 0.045)))
	_mat.set_shader_parameter("normal_k", float(look.get("normal", 1.0)))
	_mat.set_shader_parameter("locked", 1.0 if locked else 0.0)
	_mat.set_shader_parameter("flow", 1.0 if Kit.motion_ok() else 0.0)


## Zooms the planet about its centre (1 = rest); the dossier's dive into the survey map.
func zoom(k: float) -> void:
	_zoom = maxf(k, 0.01)
	_layout()


func _layout() -> void:
	if view == null:
		return
	# The view is a square around the planet with room for its relief; while it zooms the square
	# grows with it (each frame a little, so a stale frame never shows stretched), up to a cap past
	# which the planet simply overflows it, rendered at a lower scale while it moves.
	var r := radius * _zoom
	var s := minf(r * 2.2, maxf(size.x, size.y) * 1.3)
	view.max_scale = 1.8 if _zoom <= 1.001 else 1.0
	view.position = center - Vector2(s, s) * 0.5
	view.size = Vector2(s, s)
	view.ortho_width = s / r
	view.shift = Vector2.ZERO
	_mat.set_shader_parameter("cell", 4.4 * view.render_scale())
	var sh := Vector2(r * 2.5, r * 1.15)
	_shadow.position = center + Vector2(r * 0.16, r * 0.86) - sh * 0.5
	_shadow.size = sh
	_shadow.visible = _zoom < 1.4
	view.request_render()
	if _hud:
		_hud.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var anim := Kit.motion_ok()
	if not _holding:
		if anim:
			_spin += (SPIN + _vel) * delta
		else:
			_spin += _vel * delta
		_vel = lerpf(_vel, 0.0, clampf(delta * 2.2, 0.0, 1.0))
		_tilt = lerpf(_tilt, 0.0, clampf(delta * 1.6, 0.0, 1.0))
	_place()
	# Live, the view renders itself at its 30 fps cap; still (Reduce motion), only while a drag or
	# its coast is turning the world.
	if not view.is_live() and (absf(_vel) > 0.05 or absf(_tilt) > 0.05 or _holding):
		view.request_render()
	if anim and _hud:
		_hud.queue_redraw()


## The planet's turn: a fixed axial tilt, the drag's tilt, and the spin about its own axis.
func _place() -> void:
	if _pivot == null:
		return
	_pivot.basis = Basis(Vector3.RIGHT, deg_to_rad(16.0 + _tilt)) * Basis(Vector3.BACK, deg_to_rad(-14.0)) \
		* Basis(Vector3.UP, deg_to_rad(_spin))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.position.distance_to(center) > radius * 1.15:
				return
			_holding = true
			_moved = false
			_press_at = mb.position
			_vel = 0.0
			accept_event()
		elif _holding:
			_holding = false
			accept_event()
			if not _moved:
				Kit.haptic(10)
				pressed.emit()
	elif event is InputEventMouseMotion and _holding:
		var mm := event as InputEventMouseMotion
		if not _moved and mm.position.distance_to(_press_at) > 12.0:
			_moved = true
		if _moved:
			_spin += mm.relative.x * 0.32
			_tilt = clampf(_tilt + mm.relative.y * 0.18, -24.0, 24.0)
			_vel = clampf(mm.velocity.x * 0.32 * 0.25, -120.0, 120.0)
			view.request_render()
			accept_event()


## The instrument's line work around the planet (2D, over it).
class _Hud:
	extends Control
	var wv

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if wv == null:
			return
		var c: Vector2 = wv.center
		var z: float = wv._zoom
		var r: float = wv.radius
		var t: float = wv._t
		var anim := Kit.motion_ok()
		# Everything fades as the planet zooms (the dive into the map).
		var fade := clampf(1.0 - (z - 1.0) * 2.5, 0.0, 1.0)
		if fade <= 0.0:
			return
		var ink := Color(INK, 0.82 * fade)
		var thin := Color(INK, 0.4 * fade)
		# The arcs draw on over the first 0.7 s.
		var k := clampf(t / 0.7, 0.0, 1.0) if anim else 1.0
		k = 1.0 - pow(1.0 - k, 3.0)
		var fm := Kit.font("mono")
		var fb := Kit.font("mono_bold")
		# Arc A over the top left with fine ticks inside and segment marks outside.
		var ra := r * 1.12
		var a0 := deg_to_rad(-170.0)
		var a1 := deg_to_rad(-40.0)
		var ae := lerpf(a0, a1, k)
		draw_arc(c, ra, a0, ae, 96, ink, 1.4, true)
		var deg := -170.0
		while deg <= rad_to_deg(ae):
			var d := Vector2.from_angle(deg_to_rad(deg))
			var long := int(round(deg)) % 10 == 0
			draw_line(c + d * (ra - 2.0), c + d * (ra - (7.0 if long else 3.5)), thin, 1.0, true)
			deg += 2.0
		for sm: Array in [[-124.0, 7.0], [-116.0, 5.0], [-109.0, 9.0], [-96.0, 4.0], [-150.0, 3.0]]:
			var a := deg_to_rad(float(sm[0]))
			if a > ae:
				continue
			draw_arc(c, ra + 6.0, a, a + deg_to_rad(float(sm[1])), 8, Color(INK, (0.85 if float(sm[1]) > 6.0 else 0.4) * fade), 4.0, true)
		# Arc B: a thin outer arc on the right, broken, with diagonal strokes outside it.
		var rb := r * 1.26
		draw_arc(c, rb, deg_to_rad(-58.0), lerpf(deg_to_rad(-58.0), deg_to_rad(-18.0), k), 32, thin, 1.0, true)
		draw_arc(c, rb, deg_to_rad(8.0), lerpf(deg_to_rad(8.0), deg_to_rad(48.0), k), 32, thin, 1.0, true)
		for sd: float in [-52.0, -44.0, -30.0, 30.0, 41.0]:
			var d2 := Vector2.from_angle(deg_to_rad(sd))
			var p0 := c + d2 * (rb + 10.0)
			var tang := Vector2(-d2.y, d2.x)
			draw_line(p0 - tang * 9.0 + d2 * 6.0, p0 + tang * 9.0 - d2 * 6.0, Color(INK, 0.75 * fade * k), 1.4, true)
		# A short arc low on the right, and the small radial marks low on the left.
		draw_arc(c, r * 1.08, deg_to_rad(52.0), deg_to_rad(52.0 + 26.0 * k), 16, ink, 1.2, true)
		for i in 5:
			var d3 := Vector2.from_angle(deg_to_rad(148.0 + i * 6.0))
			draw_line(c + d3 * (r * 1.18), c + d3 * (r * 1.18 + (8.0 if i % 2 == 0 else 4.0)), Color(INK, 0.7 * fade * k), 2.0, true)
		# The crosshair at nine o'clock.
		var ch := c + Vector2(-r * 1.17, 0.0)
		draw_line(ch - Vector2(9, 0), ch + Vector2(9, 0), ink, 1.2, true)
		draw_line(ch - Vector2(0, 16), ch + Vector2(0, 16), ink, 1.2, true)
		# A status line (a locked world's "Signal lost ...") types in over the top left, then its
		# dots keep cycling. Open worlds print none (a "Loading ..." that never ends read as stuck).
		var lt: String = wv.loading_text
		if lt != "":
			var shown := lt
			if anim:
				var n := int(t / 0.055)
				if n < lt.length():
					shown = lt.substr(0, n)
				else:
					var base := lt.trim_suffix("...").trim_suffix(" ")
					var dots := 1 + int(fmod(t * 1.6, 3.0))
					shown = base + " " + ".".repeat(dots)
			var lp := c + Vector2(-r * 0.86, -r * 1.36)
			draw_string(fm, lp, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
			# Three short bars before it (a signal meter).
			for i in 3:
				draw_rect(Rect2(lp + Vector2(-26.0 + i * 5.0, -11.0), Vector2(2.0, 10.0)), Color(INK, (0.85 if i < 2 else 0.35) * fade))
			draw_line(lp + Vector2(-38, -20), lp + Vector2(-38, -6), ink, 1.2, true)
			draw_line(lp + Vector2(-38, -6), lp + Vector2(-30, -6), ink, 1.2, true)
		# The MASS tag across the lower left of the planet.
		var mt: String = wv.mass_text
		if mt != "":
			var mp := c + Vector2(-r * 0.98, r * 0.36)
			var mw := r * 1.02
			draw_rect(Rect2(mp, Vector2(mw, 24.0)), Color(INK, 0.84 * fade))
			draw_rect(Rect2(mp + Vector2(mw, 0.0), Vector2(r * 0.42, 24.0)), Color(INK, 0.22 * fade))
			draw_string(fb, mp + Vector2(10.0, 16.5), "MASS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(PAPER, fade))
			draw_string(fm, mp + Vector2(66.0, 16.5), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(PAPER, fade))
			for i in 4:
				draw_line(mp + Vector2(mw + 8.0 + i * 5.0, 7.0), mp + Vector2(mw + 8.0 + i * 5.0 + 18.0, 7.0 + i * 3.0), Color(INK, 0.45 * fade), 1.0, true)
		# The barcode ring at the lower right, turning slowly, with its ID and corner brackets.
		var bc := c + Vector2.from_angle(deg_to_rad(38.0)) * (r * 1.2)
		var br := maxf(r * 0.23, 36.0)
		var rot := t * 0.12 if anim else 0.0
		var seed_v: int = 977 * int(wv.world)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		# Radial bars of seeded widths round a ring (a gap at the bottom), like a printed code wheel.
		var a := 0.0
		var r_in := br * 0.6
		while a < TAU - 0.34:
			var w := rng.randf_range(0.04, 0.16)
			if rng.randf() < 0.86:
				var aa := a + rot + 1.9
				var steps := maxi(2, int(w * 40.0))
				var pts := PackedVector2Array()
				for s in steps + 1:
					pts.append(bc + Vector2.from_angle(aa + w * s / steps) * br)
				for s in range(steps, -1, -1):
					pts.append(bc + Vector2.from_angle(aa + w * s / steps) * r_in)
				draw_colored_polygon(pts, Color(INK, 0.95 * fade))
			a += w + rng.randf_range(0.022, 0.05)
		draw_arc(bc, r_in - 3.0, 0.0, TAU, 40, Color(INK, 0.35 * fade), 1.0, true)
		draw_circle(bc, 2.0, Color(INK, 0.8 * fade))
		var bs := br * 1.55
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				var q := bc + Vector2(sx, sy) * bs
				draw_line(q, q - Vector2(sx * 8.0, 0.0), thin, 1.0, true)
				draw_line(q, q - Vector2(0.0, sy * 8.0), thin, 1.0, true)
		var it: String = wv.id_text
		draw_string(fm, bc + Vector2(-br * 0.5, br * 1.55 + 14.0), it, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
		# The vertical gauge on the right: the chapter's progress.
		var gx := c.x + r * 1.5
		var gy0 := c.y - r * 0.62
		var gy1 := c.y + r * 0.62
		draw_line(Vector2(gx, gy0), Vector2(gx, lerpf(gy0, gy1, k)), ink, 1.2, true)
		for i in 11:
			var y := lerpf(gy0, gy1, i / 10.0)
			draw_line(Vector2(gx - (6.0 if i % 5 == 0 else 3.0), y), Vector2(gx, y), thin, 1.0, true)
		var py := lerpf(gy1, gy0, clampf(float(wv.progress), 0.0, 1.0))
		draw_rect(Rect2(gx - 2.0, py - 14.0, 4.0, 28.0), Color(SIGNAL if not wv.locked else INK, fade))
		var tri := PackedVector2Array([Vector2(gx + 8.0, py), Vector2(gx + 15.0, py - 5.0), Vector2(gx + 15.0, py + 5.0)])
		draw_colored_polygon(tri, ink)
