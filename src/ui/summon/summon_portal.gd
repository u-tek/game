extends Control
## The press run (the summon charge, in the poster look): a sheet on the matte being printed. A
## halftone rosette grows out of its middle as the charge rises, its dot screen turning faster and
## faster; a registration target and a ring of ticks spin up around it; the run's number and the
## count of prints are set huge on the sheet. The ink is the rarity tell, in the rarity language
## (src/ui/v4/rarity_kit.gd; the sequence drives `color`, `color2` and `ink_name`): ink black for
## Rares only; violet over a teal copy out of register when an Epic or better is inside (the Epic's
## two plates); and for a Legendary (`crackle`) the sheet floods gold foil, glinting with the
## phone's tilt, and the screen prints in black, shaking out of register. `implode` pulls the
## rosette in just before the burst. Size it to the whole screen and set `center` / `radius`;
## `count` is the number of prints in the run.

const PK := preload("res://src/ui/v4/poster_kit.gd")
const RK := preload("res://src/ui/v4/rarity_kit.gd")

var center := Vector2(360, 600)
var radius := 290.0
var charge := 0.0
var color := PK.INK
## The misregistered copy's ink (teal under an Epic's violet; black otherwise).
var color2 := PK.INK
## The ink readout ("BLACK", "VIOLET + TEAL", "BLACK ON GOLD FOIL").
var ink_name := "BLACK"
var crackle := 0.0
var implode := 0.0
## Whole-sheet opacity (fades it in at the start).
var reveal := 0.0
var count := 10

var _t := 0.0
var _spin := 0.0
var _sheet: Control
var _flood: Control
var _foil: ColorRect
var _dots: TextureRect
var _dots2: TextureRect
var _m1: ShaderMaterial
var _m2: ShaderMaterial
var _marks: Control
var _pct: Label
var _ink_l: Label
var _rng := RandomNumberGenerator.new()
var _giant: Array[RichTextLabel] = []
var _root: Control


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_rng.seed = 4711
	var sw := radius * 2.1
	var sh := minf(radius * 3.0, get_viewport_rect().size.y * 0.74)
	var rect := Rect2(center.x - sw * 0.5, center.y - sh * 0.48, sw, sh)
	_root = Control.new()
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_root)
	_sheet = PK.poster(_root, rect)
	# The gold foil flood (a Legendary): the whole sheet's foil, shown through a window rising from
	# the bottom.
	_flood = Control.new()
	_flood.name = "FoilFlood"
	_flood.mouse_filter = MOUSE_FILTER_IGNORE
	_flood.clip_contents = true
	_flood.size = Vector2(sw, 0)
	_flood.position = Vector2(0, sh)
	_sheet.add_child(_flood)
	_foil = RK.foil_rect(_flood, Rect2(Vector2.ZERO, Vector2(sw, sh)), "gold", 0, {"glint": 1.2, "sparkle": 1.0, "speed": 0.16})
	# The giant count of prints, cut off by the sheet's bottom left corner.
	_giant = PK.giant(_sheet, "×%02d" % count, 230, [[0.0, sw, PK.INK]], Vector2(-12, sh - 196), Vector2(sw, 260), 0.0)
	for g in _giant:
		g.modulate.a = 0.9
	# The rosette (and its misregistered black copy).
	var c := center - rect.position
	var d := radius * 2.2
	_dots2 = _rosette(PK.INK)
	_m2 = _dots2.material as ShaderMaterial
	_dots2.position = c - Vector2(d, d) * 0.5
	_dots2.size = Vector2(d, d)
	_sheet.add_child(_dots2)
	_dots = _rosette(color)
	_m1 = _dots.material as ShaderMaterial
	_dots.position = c - Vector2(d, d) * 0.5
	_dots.size = Vector2(d, d)
	_dots.pivot_offset = Vector2(d, d) * 0.5
	_dots2.pivot_offset = Vector2(d, d) * 0.5
	_sheet.add_child(_dots)
	_marks = Control.new()
	_marks.mouse_filter = MOUSE_FILTER_IGNORE
	_marks.size = rect.size
	_marks.draw.connect(_draw_marks.bind(c))
	_sheet.add_child(_marks)
	# Press micro type.
	PK.at(_sheet, PK.t("PRESS RUN Nº 0047\n%d SHEETS · %s" % [count, Kit.print_date_short()], 12, PK.INK, "mono_bold"), Vector2(sw - 230, 18))
	_ink_l = PK.t("INK —", 12, PK.INK, "mono_bold")
	PK.at(_sheet, _ink_l, Vector2(sw - 230, sh - 64))
	_pct = PK.t("CHARGE 000%", 12, PK.INK, "mono_bold")
	PK.at(_sheet, _pct, Vector2(sw - 230, sh - 44))
	PK.vt(_sheet, "©2026 HH · HALO & HORN · PORTAL", 10, Color(PK.INK, 0.7), Vector2(sw - 14, 20))
	_root.modulate.a = 0.0


func _rosette(ink: Color) -> TextureRect:
	var g := Gradient.new()
	# Bright in the middle, gone (transparent) at the rim, so the screen ends in a circle.
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0.45, 0.45, 0.45, 1))
	g.add_point(0.85, Color(0.15, 0.15, 0.15, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 128
	gt.height = 128
	var tr := TextureRect.new()
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.material = SignalKit.halftone_material(11.0, ink, true)
	return tr


func _process(delta: float) -> void:
	_t += delta
	_spin += delta * (0.25 + charge * charge * 5.0) * (1.0 if Kit.motion_ok() else 0.0)
	_root.modulate.a = reveal
	var flood := clampf(crackle, 0.0, 1.0)
	var sh := _sheet.size.y
	_flood.size = Vector2(_sheet.size.x, sh * flood)
	_flood.position = Vector2(0, sh * (1.0 - flood))
	_foil.position = Vector2(0, -sh * (1.0 - flood))
	# The screen: dots spread out from the middle as the charge rises; the implosion pulls them in.
	var lift := lerpf(-0.75, 0.25, _ease_out(charge)) - implode * 1.1
	var ink := color
	_m1.set_shader_parameter("ink", Color(ink, 0.95))
	_m1.set_shader_parameter("lift", lift)
	_m1.set_shader_parameter("gain", 1.3 + 0.4 * charge)
	_m1.set_shader_parameter("angle", 0.5236 + _spin * 0.6)
	_m1.set_shader_parameter("cell", 11.0 - 3.0 * charge)
	# The copy: faint black early on; the Epic's teal plate stands out; black on the gold flood.
	var teal := clampf((color2.b - color2.r) * 2.0, 0.0, 1.0)
	_m2.set_shader_parameter("ink", Color(color2, 0.85 if flood > 0.0 else lerpf(0.35 * charge, 0.8, teal)))
	_m2.set_shader_parameter("lift", lift - 0.1)
	_m2.set_shader_parameter("angle", 0.26 - _spin * 0.4)
	_m2.set_shader_parameter("cell", 11.0 - 3.0 * charge)
	# Out of register: the black copy shakes off the red one, harder for a Legendary.
	var off := (2.0 + 10.0 * charge * charge + 26.0 * flood) * (1.0 if Kit.motion_ok() else 0.2)
	_dots2.position = _dots.position + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * off * 0.5 + Vector2(off, -off * 0.5)
	var s := 1.0 - 0.55 * implode
	_dots.scale = Vector2(s, s)
	_dots2.scale = Vector2(s, s)
	var pal := PK.PAPER if flood > 0.5 else PK.INK
	_pct.text = "CHARGE %03d%%" % int(round(charge * 100.0))
	_ink_l.text = "INK  %s" % ink_name
	_pct.add_theme_color_override("font_color", PK.INK)
	_ink_l.add_theme_color_override("font_color", PK.INK)
	for g in _giant:
		g.add_theme_color_override("default_color", pal if flood > 0.5 else PK.INK)
	_marks.queue_redraw()


static func _ease_out(x: float) -> float:
	var u := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - u * u * u


## The registration target, a ring of ticks spinning up and the charge arc, in ink.
func _draw_marks(c: Vector2) -> void:
	var ci := _marks
	var ink := PK.INK
	var r := radius * (1.0 - 0.3 * implode)
	ci.draw_arc(c, 34.0, 0.0, TAU, 48, ink, 1.6, true)
	ci.draw_line(c - Vector2(58, 0), c + Vector2(58, 0), ink, 1.4)
	ci.draw_line(c - Vector2(0, 58), c + Vector2(0, 58), ink, 1.4)
	ci.draw_circle(c, 5.0, ink)
	var n := 72
	for i in n:
		var a := TAU * i / n + _spin * 0.35
		var long := i % 6 == 0
		var d := Vector2.from_angle(a)
		ci.draw_line(c + d * (r * 0.96), c + d * (r * (0.96 - (0.06 if long else 0.025))), Color(ink, 0.9 if long else 0.5), 1.2, true)
	ci.draw_arc(c, r, 0.0, TAU, 128, Color(ink, 0.5), 1.0, true)
	if charge > 0.0:
		ci.draw_arc(c, r * 1.04, -PI * 0.5, -PI * 0.5 + TAU * charge, maxi(4, int(128 * charge)), PK.SIGNAL if crackle < 0.5 else ink, 4.0, true)
		var e := -PI * 0.5 + TAU * charge
		ci.draw_circle(c + Vector2.from_angle(e) * r * 1.04, 6.0, PK.SIGNAL if crackle < 0.5 else ink)
	# Crop marks around the screen.
	var q := r * 1.12
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var p := c + s * q
		ci.draw_line(p, p - Vector2(s.x * 22, 0), ink, 1.2)
		ci.draw_line(p, p - Vector2(0, s.y * 22), ink, 1.2)
