class_name PhysicalKit
extends RefCounted
## Physical paper and physical collage objects (style v4 poster look; the owner, 2026-10-19: "make the
## game feel physical", from references 23 and 24). The poster stays the hero: these make its paper
## real and stick a few real objects on it.
##
## Paper (every poster sheet, through PosterKit / HeroPosterKit / survey Poster .poster()):
##   PhysicalKit.sheet(parent, rect, fill, shadow)  a sheet of felt or parchment paper (the tile by the
##                     fill's warmth), lit by the key light that leans with the phone (ui_tilt), with a
##                     hair of thickness, a contact shadow and a soft shadow on the matte; returns the
##                     clipped content control (meta "shadow": the sheet's holder). Big sheets also get
##                     the relief overlay once composed: the print is re-lit through the paper's grain
##                     (hero figures stay above it).
##   PhysicalKit.deboss(parent)        a CanvasGroup: giant type put inside is pressed into the paper
## Objects (Cycles renders, tools/blender/physical_objects.py, assets/art/ui/physical/):
##   PhysicalKit.growth(faction, shape, parent, at, ppu)   thorns (celestial: chrome with blue crystal;
##                     fallen: black with red jelly) or jelly and moss (infernal); shape tl | tr | br | bl
##                     | edge | clump_a | clump_b; `at` is where the poster corner (the piece's origin)
##                     goes, ppu the screen px per world unit (about 70 on a full poster). Add growths
##                     under the stuck-on controls: they may run beneath a touch target, never over one
##   PhysicalKit.paper_fill(control, fill)                real paper inside a StyleBox sheet (dialogs)
##   PhysicalKit.piece(name, parent, at, ppu)             any rendered piece by its manifest anchor
##   PhysicalKit.Led          a real LED (green, orange, red, cyan): steady, breathe, blink or off
##   PhysicalKit.PushCap      the red dome or the red cap in a knurled bezel, up / pressed
##   PhysicalKit.Acrylic      the clear frosted tab or the orange acrylic card over whatever is behind
## Reduce motion (Kit.motion_ok) stops LEDs breathing and blinking.

const DIR := "res://assets/art/ui/physical/"
const PAPER_SHADER := preload("res://src/ui/shaders/paper.gdshader")
const RELIEF_SHADER := preload("res://src/ui/shaders/paper_relief.gdshader")
const DEBOSS_SHADER := preload("res://src/ui/shaders/deboss.gdshader")
const ACRYLIC_SHADER := preload("res://src/ui/shaders/acrylic.gdshader")
## Sheets bigger than this (px area) get the relief overlay (a screen read: only a few per screen).
const RELIEF_AREA := 160000.0
## How far the sheet's shadow reaches past it.
const MARGIN := 34.0

static var _manifest: Dictionary = {}
static var _loaded := false
## A/B checks (debug builds): HH_PHYS_OFF="relief,deboss,acrylic" leaves those out.
static var _off := OS.get_environment("HH_PHYS_OFF").split(",") if OS.is_debug_build() else PackedStringArray()
static var _tex_cache: Dictionary = {}


## The manifest entry of a piece (size, px_per_unit, origin, center, diameter), or {}.
static func info(piece_name: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(DIR + "physical.json", FileAccess.READ)
		if f:
			var j: Variant = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_manifest = j
	return _manifest.get(piece_name, {})


static func tex(file_name: String) -> Texture2D:
	if _tex_cache.has(file_name):
		return _tex_cache[file_name]
	var path := DIR + file_name + ".png"
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[file_name] = t
	return t


# ------------------------------------------------------------------ paper

## Felt (cool greys) or parchment (warm paper) for a sheet's fill colour.
static func paper_kind(fill: Color) -> String:
	return "parch" if fill.r - fill.b > 0.045 and fill.v > 0.55 else "felt"


static func paper_material(fill: Color, size: Vector2, relief: float, seed_pos: Vector2, shadow_a: float = 0.28,
		shadow_r: float = 22.0) -> ShaderMaterial:
	var kind := paper_kind(fill)
	var m := ShaderMaterial.new()
	m.shader = PAPER_SHADER
	m.set_shader_parameter("rect_size", size + Vector2(MARGIN, MARGIN) * 2.0)
	m.set_shader_parameter("margin", MARGIN)
	m.set_shader_parameter("fill", Color(fill.r, fill.g, fill.b, 1.0))
	m.set_shader_parameter("detail", tex("paper_" + kind))
	m.set_shader_parameter("nmap", tex("paper_%s_n" % kind))
	m.set_shader_parameter("tex_offset", seed_pos)
	# Dark sheets (the bands, ink cards) show less grain.
	m.set_shader_parameter("grain", 0.55 if fill.v > 0.5 else 0.35)
	m.set_shader_parameter("relief", relief)
	m.set_shader_parameter("shadow_a", shadow_a)
	m.set_shader_parameter("shadow_r", shadow_r)
	return m


## A poster sheet: the paper (with its shadows) and, over it, the clipped control for its print.
## Returns that control; meta "shadow" is the sheet's holder (same rect: rotate both together),
## meta "paper" the ColorRect drawing the paper. Big sheets get the relief overlay once the screen has
## put its print on them (deferred), unless opts.relief is false.
static func sheet(parent: Node, rect: Rect2, fill: Color, shadow_a: float = 0.28, opts: Dictionary = {}) -> Control:
	var holder := Control.new()
	holder.name = "PosterShadow"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = rect.position
	holder.size = rect.size
	parent.add_child(holder)
	# manual_relief: the caller adds the relief overlay itself (PhysicalKit.relief, where it belongs).
	var manual := bool(opts.get("manual_relief", false))
	var big := manual or (rect.size.x * rect.size.y >= RELIEF_AREA and bool(opts.get("relief", true)))
	var paper := ColorRect.new()
	paper.name = "Paper"
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.position = -Vector2(MARGIN, MARGIN)
	paper.size = rect.size + Vector2(MARGIN, MARGIN) * 2.0
	paper.material = paper_material(fill, rect.size, 0.0 if big else 0.15, rect.position * 1.37, shadow_a, float(opts.get("shadow_r", 22.0)))
	holder.add_child(paper)
	var p := Control.new()
	p.name = "Poster"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	p.set_meta("shadow", holder)
	p.set_meta("paper", paper)
	p.set_meta("paper_kind", paper_kind(fill))
	p.set_meta("tex_offset", rect.position * 1.37)
	if big and not manual:
		_seal.call_deferred(p)
	return p


## The relief overlay, last on the sheet (deferred: after the screen's print), with the hero figures
## moved back above it.
static func _seal(p: Control) -> void:
	if not is_instance_valid(p) or p.has_meta("relief"):
		return
	relief(p)


## Re-lights everything already drawn on sheet `p` through the paper's grain: a BackBufferCopy and the
## overlay, added last; children that hold a hero figure (named HeroBox / HeroAnchor or meta
## "above_paper") move above it. Call it yourself to place it (then the deferred one does nothing).
static func relief(p: Control, at_index: int = -1) -> Control:
	if p.has_meta("relief"):
		return p.get_meta("relief")
	if "relief" in _off:
		return null
	var kind := str(p.get_meta("paper_kind", "felt"))
	var bb := BackBufferCopy.new()
	bb.name = "ReliefCopy"
	bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bb.rect = Rect2(Vector2.ZERO, p.size)
	var ov := ColorRect.new()
	ov.name = "PaperRelief"
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.size = p.size
	var m := ShaderMaterial.new()
	m.shader = RELIEF_SHADER
	m.set_shader_parameter("rect_size", p.size)
	m.set_shader_parameter("nmap", tex("paper_%s_n" % kind))
	m.set_shader_parameter("tex_offset", p.get_meta("tex_offset", Vector2.ZERO))
	m.set_shader_parameter("relief", 0.17 if kind == "parch" else 0.14)
	m.set_shader_parameter("strength", 0.6)
	ov.material = m
	p.add_child(bb)
	p.add_child(ov)
	if at_index >= 0:
		p.move_child(bb, at_index)
		p.move_child(ov, at_index + 1)
	else:
		for c in p.get_children():
			if c != bb and c != ov and _is_figure(c):
				p.move_child(c, -1)
	p.set_meta("relief", ov)
	return ov


static func _is_figure(n: Node) -> bool:
	if n.has_meta("above_paper") or n.name.begins_with("HeroBox") or n.name.begins_with("HeroAnchor") or n is HeroSprite:
		return true
	for c in n.get_children():
		if c.name.begins_with("HeroAnchor") or c is HeroSprite:
			return true
	return false


## Fills `c` (any control, kept in step with its size) with real paper: the grain lit by the tilting
## light, no shadow (for sheets drawn by a StyleBox: the dialogs). Add it as the control's first child.
static func paper_fill(c: Control, fill: Color, relief: float = 0.05, grain: float = 0.22) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Paper"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var kind := paper_kind(fill)
	var m := ShaderMaterial.new()
	m.shader = PAPER_SHADER
	m.set_shader_parameter("margin", 0.0)
	m.set_shader_parameter("fill", Color(fill.r, fill.g, fill.b, 1.0))
	m.set_shader_parameter("detail", tex("paper_" + kind))
	m.set_shader_parameter("nmap", tex("paper_%s_n" % kind))
	m.set_shader_parameter("relief", relief)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("shadow_a", 0.0)
	m.set_shader_parameter("thickness", 0.0)
	r.material = m
	r.resized.connect(func() -> void: m.set_shader_parameter("rect_size", r.size))
	c.add_child(r)
	c.move_child(r, 0)
	return r


## A CanvasGroup whose children (giant type) are pressed into the paper: shadowed walls toward the
## light, a paper-coloured rim away from it. Add the type's clip controls to it.
static func deboss(parent: Node, depth: float = 4.0, rim: Color = Color("f4f3ee")) -> Node:
	if "deboss" in _off:
		var n := Node2D.new()
		parent.add_child(n)
		return n
	var g := CanvasGroup.new()
	g.name = "Deboss"
	g.fit_margin = depth * 2.0 + 4.0
	g.clear_margin = depth * 2.0 + 4.0
	var m := ShaderMaterial.new()
	m.shader = DEBOSS_SHADER
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("rim", rim)
	g.material = m
	parent.add_child(g)
	return g


# ------------------------------------------------------------------ rendered pieces

## The growth piece for a faction: thorn_chrome_* (Celestial), thorn_black_* (Fallen), jelly_*
## (Infernal; its clumps are all "jelly_clump").
static func growth_name(faction: String, shape: String) -> String:
	match faction:
		"infernal":
			return "jelly_" + ("clump" if shape.begins_with("clump") else shape)
		"fallen":
			return "thorn_black_" + shape
	return "thorn_chrome_" + shape


## A rendered piece placed so its manifest origin (the poster corner of a corner piece, the centre of
## round hardware) lands at `at` in parent px, at `ppu` screen px per world unit (or its own size when
## ppu <= 0). Returns the TextureRect (null when the piece is missing).
static func piece(piece_name: String, parent: Node, at: Vector2, ppu: float = 0.0, rot: float = 0.0) -> TextureRect:
	var t := tex(piece_name)
	var inf := info(piece_name)
	if t == null:
		return null
	var k := 1.0
	if ppu > 0.0 and float(inf.get("px_per_unit", 0.0)) > 0.0:
		k = ppu / float(inf.px_per_unit)
	var o: Array = inf.get("origin", [t.get_width() * 0.5, t.get_height() * 0.5])
	var tr := TextureRect.new()
	tr.name = piece_name.to_pascal_case()
	tr.texture = t
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = t.get_size() * k
	tr.pivot_offset = Vector2(float(o[0]), float(o[1])) * k
	tr.position = at - tr.pivot_offset
	tr.rotation = rot
	parent.add_child(tr)
	return tr


static func growth(faction: String, shape: String, parent: Node, at: Vector2, ppu: float = 70.0, rot: float = 0.0) -> TextureRect:
	return piece(growth_name(faction, shape), parent, at, ppu, rot)


## How big a round piece is drawn so its body is `diameter` screen px: the scale for piece().
static func ppu_for(piece_name: String, diameter: float) -> float:
	var inf := info(piece_name)
	var d := float(inf.get("diameter", 0.0))
	if d <= 0.0:
		return 0.0
	return float(inf.get("px_per_unit", 1.0)) * diameter / d


## A real LED: the off render, the lit render (its glow baked in) over it. color: green | orange | red |
## cyan; mode: "steady" | "breathe" | "blink" | "off". Size it with `diameter` (the lens + grommet).
class Led:
	extends Control
	var color := "red"
	var mode := "steady"
	var period := 1.6
	var diameter := 20.0
	var _on: TextureRect
	var _off: TextureRect
	var _t := 0.0

	func _init(c: String = "red", m: String = "steady", d: float = 20.0) -> void:
		color = c
		mode = m
		diameter = d
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		size = Vector2(diameter, diameter)
		_off = _layer("led_%s_off" % color)
		_on = _layer("led_%s_on" % color)
		_apply()
		set_process(mode in ["breathe", "blink"] and Kit.motion_ok())

	## The render, centred on the control, its body `diameter` across.
	func _layer(n: String) -> TextureRect:
		var t := PhysicalKit.tex(n)
		var tr := TextureRect.new()
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var inf := PhysicalKit.info(n)
		var d := float(inf.get("diameter", 40.0))
		var k := diameter / maxf(d, 1.0)
		if t:
			tr.size = t.get_size() * k
			var c: Array = inf.get("center", [t.get_width() * 0.5, t.get_height() * 0.5])
			tr.position = size * 0.5 - Vector2(float(c[0]), float(c[1])) * k
		add_child(tr)
		return tr

	func set_mode(m: String) -> void:
		mode = m
		_t = 0.0
		if is_inside_tree():
			_apply()
			set_process(mode in ["breathe", "blink"] and Kit.motion_ok())

	func _apply() -> void:
		if _on == null:
			return
		var k := 1.0
		match mode:
			"off":
				k = 0.0
			"blink":
				k = 1.0 if fmod(_t, period) < period * 0.55 else 0.0
			"breathe":
				k = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * TAU / period))
		_on.modulate.a = k

	func _process(delta: float) -> void:
		_t += delta
		_apply()


## A red push cap: "dome" (the glossy ellipsoid dome) or "bezel" (the red cap in a knurled silver
## bezel), its body `diameter` across; set_pressed swaps to the pressed render.
class PushCap:
	extends Control
	var kind := "bezel"
	var diameter := 96.0
	var _up: TextureRect
	var _down: TextureRect

	func _init(k: String = "bezel", d: float = 96.0) -> void:
		kind = k
		diameter = d
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		size = Vector2(diameter, diameter * (0.82 if kind == "dome" else 1.0))
		_up = _layer(kind + "_up")
		_down = _layer(kind + "_down")
		_down.visible = false

	func _layer(n: String) -> TextureRect:
		var t := PhysicalKit.tex(n)
		var tr := TextureRect.new()
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var inf := PhysicalKit.info(n)
		var k := diameter / maxf(float(inf.get("diameter", 100.0)), 1.0)
		if t:
			tr.size = t.get_size() * k
			var c: Array = inf.get("center", [t.get_width() * 0.5, t.get_height() * 0.5])
			tr.position = size * 0.5 - Vector2(float(c[0]), float(c[1])) * k
		add_child(tr)
		return tr

	func set_pressed(on: bool) -> void:
		if _up == null:
			return
		_up.visible = not on
		_down.visible = on


## An acrylic slab over whatever is behind it: "tab" (clear, frosted, a steel eyelet) or "card"
## (orange, a halftone dot grid, a round cutout). Its slab is `width` screen px wide; content (type)
## goes in it as children (they sit on top of the slab). frost: blur radius of what shows through.
class Acrylic:
	extends Control
	var kind := "tab"
	var width := 120.0
	var frost := 6.0
	var _surf: ColorRect
	var _mat: ShaderMaterial
	const SLAB_MARGIN := 22.0

	func _init(k: String = "tab", w: float = 120.0) -> void:
		kind = k
		width = w
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var n := "acrylic_" + kind
		var t := PhysicalKit.tex(n + "_t")
		var tsize := t.get_size() if t else Vector2(100, 200)
		size = Vector2(width, width * tsize.y / maxf(tsize.x, 1.0))
		var bb := BackBufferCopy.new()
		bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		bb.rect = Rect2(-Vector2(SLAB_MARGIN, SLAB_MARGIN), size + Vector2(SLAB_MARGIN, SLAB_MARGIN) * 2.0)
		add_child(bb)
		move_child(bb, 0)
		_surf = ColorRect.new()
		_surf.mouse_filter = MOUSE_FILTER_IGNORE
		_surf.position = -Vector2(SLAB_MARGIN, SLAB_MARGIN)
		_surf.size = size + Vector2(SLAB_MARGIN, SLAB_MARGIN) * 2.0
		_mat = ShaderMaterial.new()
		_mat.shader = PhysicalKit.ACRYLIC_SHADER
		_mat.set_shader_parameter("rect_size", _surf.size)
		_mat.set_shader_parameter("margin", SLAB_MARGIN)
		_mat.set_shader_parameter("t_tex", t)
		_mat.set_shader_parameter("l_tex", PhysicalKit.tex(n + "_l"))
		_mat.set_shader_parameter("frost", frost)
		_surf.material = _mat
		add_child(_surf)
		move_child(_surf, 1)

