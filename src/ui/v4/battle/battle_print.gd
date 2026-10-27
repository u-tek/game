extends RefCounted
## Style v4 battle pieces in the approved poster look (docs/dev/ui-style-v4.md section 0): the battle
## HUD as printed instrument readouts on paper strips around the full-colour fight, and the results as
## two-tone risograph posters. Used by battle_screen.gd, ally_portrait.gd, unit_view.gd and
## battle_result.gd.
##   const BP := preload("res://src/ui/v4/battle/battle_print.gd")
##
##   BP.t(text, size, color, weight)            a Label (mono micro type by default)
##   BP.shade(parent, rect, down)               the soft shadow a paper strip casts on the field
##   BP.riso(hero_id, skin, crop, opts)         a two-plate risograph print of a hero (signal + ink,
##                                              out of register), multiplied onto the paper under it
##   BP.halftone(hero_id, skin, opts)           a one-colour halftone print (for dark bands)
##   BP.giant(parent, bb, fs, pos, block, regions, rot)  giant type, one copy per region and ink
##   BP.pose(labels, offset, scale, alpha)      moves a giant() block
##   BP.Ticks                                   a printed tick ruler (top or bottom edge)
##   BP.Readout                                 a mono bar with a trailing chip and a tick ruler
##   BP.BossBand                                the boss as a printed band: her name huge, a two-tone
##                                              HP bar under it, her red halftone print at the end

const HUD := preload("res://src/ui/components/hud.gd")
const RISO := preload("res://src/ui/v4/battle/riso.gdshader")

const MATTE := SignalKit.MATTE
const PAPER := SignalKit.PAPER
## The paper of a strip's darker parts (inside frames, empty bars).
const PAPER_DIM := Color("d9d8d1")
const INK := SignalKit.INK
const BAND := Kit.BAND
const SIG := SignalKit.SIGNAL
const SIG_HI := Color("ff8a62")
## Red halftone ink on dark bands (the Lobby poster's print).
const RED_INK := Color(1.0, 0.36, 0.16, 0.95)


static func t(text: String, size: int, color: Color = INK, weight: String = "mono") -> Label:
	var l := Kit.label(text, size, color, weight)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func at(parent: Node, c: Control, pos: Vector2) -> Control:
	c.position = pos
	parent.add_child(c)
	return c


static func rect(parent: Node, r: Rect2, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.color = color
	c.position = r.position
	c.size = r.size
	parent.add_child(c)
	return c


## The soft shadow a paper strip casts on the field: `rect` is the shadow's area, darkest at the
## strip's edge (down = the strip is above it).
static func shade(parent: Node, r: Rect2, down: bool = true, alpha: float = 0.34) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Color(0, 0, 0, alpha)
	var b := Color(0, 0, 0, 0)
	tr.texture = Kit.vgradient(a, b) if down else Kit.vgradient(b, a)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = r.position
	tr.size = r.size
	parent.add_child(tr)
	return tr


## A crop of a hero's art for prints: "face" (head to waist), "full" (the whole still) or "bust".
static func _print_tex(hero_id: String, skin: String, crop: String, zoom: float = 1.0) -> Texture2D:
	var tex := HeroArt.texture(hero_id, skin)
	if tex == null or crop == "full":
		return tex
	var face := HeroArt.portrait_region(hero_id, skin)
	var at_tex := AtlasTexture.new()
	at_tex.atlas = tex
	var tall := 1.9 if crop == "face" else 3.4
	var half := Vector2(face.size.x * (0.42 if crop == "face" else 0.8), face.size.y * 0.62) / maxf(zoom, 0.1)
	var reg := Rect2(face.get_center() - half, Vector2(half.x * 2.0, face.size.y * tall / maxf(zoom, 0.1)))
	at_tex.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	return at_tex


## The risograph material: opts cell_a, cell_b, shift_b (Vector2 px), gain_a, lift_a, gain_b, cut_b,
## ink_a, ink_b, strength.
static func riso_material(opts: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RISO
	for k: String in ["cell_a", "cell_b", "shift_a", "shift_b", "gain_a", "lift_a", "gain_b", "cut_b", "ink_a", "ink_b", "strength", "angle_a", "angle_b"]:
		if opts.has(k):
			m.set_shader_parameter(k, opts[k])
	return m


## A risograph print of a hero (signal and ink plates, out of register), multiplied onto whatever is
## under it (print it on paper). crop: "face" | "bust" | "full". Returns a TextureRect (size it).
static func riso(hero_id: String, skin: String, crop: String = "full", opts: Dictionary = {}) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if crop != "full" else TextureRect.STRETCH_SCALE
	tr.texture = _print_tex(hero_id, skin, crop, float(opts.get("zoom", 1.0)))
	tr.material = riso_material(opts)
	return tr


## A one-colour halftone print of a hero (red light dots for dark bands). opts: crop ("face"),
## cell (7), ink, light_dots (true), angle (radians), gain, zoom.
static func halftone(hero_id: String, skin: String, opts: Dictionary = {}) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture = _print_tex(hero_id, skin, str(opts.get("crop", "face")), float(opts.get("zoom", 1.0)))
	var m := SignalKit.halftone_material(float(opts.get("cell", 7.0)), opts.get("ink", RED_INK), bool(opts.get("light_dots", true)))
	if opts.has("angle"):
		m.set_shader_parameter("angle", float(opts["angle"]))
	if opts.has("gain"):
		m.set_shader_parameter("gain", float(opts["gain"]))
	tr.material = m
	return tr


## Giant display type, one copy per region, each in that region's ink and clipped to it (two-tone
## where it crosses a band; an out-of-register second plate is another call with a shifted pos).
## regions: [[Rect2, Color], ...] in parent coordinates. Turned (rot = PI / 2, reads downwards):
## `pos` is the top-right corner of the turned block and `block` its size before turning (x = its
## length down the page). Returns the labels (pose() moves them together).
static func giant(parent: Control, bb: String, fs: int, pos: Vector2, block: Vector2, regions: Array,
		rot: float = PI * 0.5, weight: String = "compressed", line_sep: int = -14, deboss: bool = true) -> Array[RichTextLabel]:
	var out: Array[RichTextLabel] = []
	var host: Node = PhysicalKit.deboss(parent, clampf(fs * 0.03, 2.5, 6.0)) if deboss else parent
	for r: Array in regions:
		var rr: Rect2 = r[0]
		if rr.size.x <= 0.0 or rr.size.y <= 0.0:
			continue
		var clip := Control.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.position = rr.position
		clip.size = rr.size
		host.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.text = bb
		rt.fit_content = false
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.add_theme_font_override("normal_font", Kit.font(weight))
		rt.add_theme_font_size_override("normal_font_size", fs)
		rt.add_theme_color_override("default_color", r[1])
		rt.add_theme_constant_override("line_separation", line_sep)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.size = block
		rt.rotation = rot
		rt.position = pos - rr.position
		rt.set_meta("base", rt.position)
		clip.add_child(rt)
		out.append(rt)
	return out


static func pose(labels: Array[RichTextLabel], offset: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	for rt in labels:
		if is_instance_valid(rt):
			rt.position = (rt.get_meta("base") as Vector2) + offset
			rt.scale = Vector2(scale, scale)
			rt.modulate.a = alpha


## The largest size (from max_fs down) at which `text` in `weight` is at most `width` px long.
static func fit(text: String, width: float, max_fs: int, min_fs: int, weight: String = "compressed") -> int:
	var f := Kit.font(weight)
	var fs := max_fs
	while fs > min_fs and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 2
	return fs


## Cap top and baseline of a line of `weight` at `fs`, from the line's top.
static func caps(fs: int, weight: String = "compressed") -> Vector2:
	var f := Kit.font(weight)
	var a := f.get_ascent(fs)
	return Vector2(a - fs * 0.72, a)


## A printed tick ruler: `count` divisions across the width, majors every `major`; drawn down from
## the top edge (from_top) or up from the bottom edge.
class Ticks:
	extends Control
	var count := 50
	var major := 10
	var color := Color(0.063, 0.067, 0.075, 0.55)
	var from_top := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var step := size.x / maxf(1.0, float(count))
		for i in count + 1:
			var x := minf(i * step, size.x - 0.5)
			var big := major > 0 and i % major == 0
			var l := size.y if big else size.y * 0.5
			var c := color if big else Color(color, color.a * 0.75)
			if from_top:
				draw_line(Vector2(x, 0), Vector2(x, l), c, 1.0)
			else:
				draw_line(Vector2(x, size.y), Vector2(x, size.y - l), c, 1.0)


## A mono readout bar: hairline frame, `fill` up to the value, a pale chip that trails behind after a
## hit, and a tick ruler under it (`ticks` divisions, majors at the ends and the middle).
class Readout:
	extends Control
	var value := 1.0
	var chip := 1.0
	var fill := SignalKit.INK
	var track := Color(0.063, 0.067, 0.075, 0.07)
	var frame := Color(0.063, 0.067, 0.075, 0.85)
	var chip_color := Color(0.063, 0.067, 0.075, 0.28)
	var ticks := 10
	var bar_h := 8.0
	var tick_h := 4.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_value(v: float, instant: bool = false) -> void:
		value = clampf(v, 0.0, 1.0)
		if instant or value > chip:
			chip = value
		set_process(chip > value)
		queue_redraw()

	func _process(delta: float) -> void:
		if chip > value:
			chip = maxf(value, chip - delta * 0.8)
			queue_redraw()
		else:
			set_process(false)

	func _draw() -> void:
		var r := Rect2(0, 0, size.x, bar_h)
		draw_rect(r, track)
		if chip > value:
			draw_rect(Rect2(r.size.x * value, 0, r.size.x * (chip - value), bar_h), chip_color)
		draw_rect(Rect2(0, 0, r.size.x * value, bar_h), fill)
		draw_rect(r, frame, false, 1.0)
		if ticks > 0 and tick_h > 0.0:
			var step := size.x / float(ticks)
			for i in ticks + 1:
				var big := i == 0 or i == ticks or i * 2 == ticks
				var x := minf(i * step, size.x - 0.5)
				draw_line(Vector2(x, bar_h), Vector2(x, bar_h + (tick_h if big else tick_h * 0.55)), Color(frame, frame.a * 0.8), 1.0)


## The boss as a printed band across the field's top: a dark band with her red halftone print fading
## in at the right end, "BOSS · <faction> ECHO · LV" in mono, her name huge in compressed paper type,
## the HP bar in signal crossing the foot of her name (the letters print ink where they cross the
## fill: two-tone), a tick ruler under it and the HP in mono. set_hp() animates the fill and a chip.
class BossBand:
	extends Control
	const H := 88.0
	const BAR_Y := 58.0
	const BAR_H := 14.0
	var frac := 1.0
	var chip := 1.0
	var hp := 1
	var max_hp := 1
	var down := false
	var _bars: Control
	var _paper: Control
	var _ink_clip: Control
	var _ink: Control
	var _stamp: Control

	func build(hero_id: String, boss_name: String, kicker: String, w: float) -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		size = Vector2(w, H)
		clip_contents = true
		var bg := ColorRect.new()
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		bg.color = Kit.BAND
		bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(bg)
		if hero_id != "":
			var pr := TextureRect.new()
			var tex := HeroArt.texture(hero_id, "")
			if tex:
				var face := HeroArt.portrait_region(hero_id, "")
				var at_tex := AtlasTexture.new()
				at_tex.atlas = tex
				var reg := Rect2(face.position - face.size * Vector2(0.35, 0.2), face.size * Vector2(1.7, 1.25))
				at_tex.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
				pr.texture = at_tex
			pr.mouse_filter = MOUSE_FILTER_IGNORE
			pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pr.material = SignalKit.halftone_material(6.0, Color(1.0, 0.36, 0.16, 0.95), true)
			pr.anchor_left = 1.0
			pr.anchor_right = 1.0
			pr.anchor_bottom = 1.0
			pr.offset_left = -250
			add_child(pr)
			var fade := TextureRect.new()
			fade.mouse_filter = MOUSE_FILTER_IGNORE
			fade.texture = Kit.vgradient(Kit.BAND, Color(0.078, 0.082, 0.09, 0.0), true)
			fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fade.stretch_mode = TextureRect.STRETCH_SCALE
			fade.anchor_left = 1.0
			fade.anchor_right = 1.0
			fade.anchor_bottom = 1.0
			fade.offset_left = -252
			fade.offset_right = -150
			add_child(fade)
		_bars = Control.new()
		_bars.mouse_filter = MOUSE_FILTER_IGNORE
		_bars.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		_bars.draw.connect(_draw_bars)
		add_child(_bars)
		var fs := _fit_name(boss_name.to_upper(), w * 0.6)
		_paper = _BandText.new()
		_paper.set("title", boss_name.to_upper())
		_paper.set("kicker", kicker)
		_paper.set("fs", fs)
		_paper.set("ink", SignalKit.PAPER)
		_paper.set("accent", SignalKit.SIGNAL)
		_paper.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(_paper)
		_ink_clip = Control.new()
		_ink_clip.mouse_filter = MOUSE_FILTER_IGNORE
		_ink_clip.clip_contents = true
		_ink_clip.position = Vector2(16, BAR_Y)
		_ink_clip.size = Vector2(w - 32, BAR_H)
		add_child(_ink_clip)
		_ink = _BandText.new()
		_ink.set("title", boss_name.to_upper())
		_ink.set("kicker", kicker)
		_ink.set("fs", fs)
		_ink.set("ink", SignalKit.INK)
		_ink.set("accent", SignalKit.INK)
		_ink.position = -_ink_clip.position
		_ink.size = size
		_ink_clip.add_child(_ink)
		resized.connect(_on_resized)

	static func _fit_name(text: String, width: float) -> int:
		var f := Kit.font("compressed")
		var fs := 66
		while fs > 34 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			fs -= 2
		return fs

	func _on_resized() -> void:
		if _ink:
			_ink.size = size
		_layout_fill()

	func set_hp(new_hp: int, new_max: int, animate: bool = true) -> void:
		hp = maxi(new_hp, 0)
		max_hp = maxi(new_max, 1)
		frac = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		if not animate or frac > chip:
			chip = frac
		_paper.set("hp_text", "HP %s / %s" % [Kit.format_full(hp), Kit.format_full(max_hp)])
		_paper.set("pct", "%d%%" % ceili(frac * 100.0) if hp > 0 else "0%")
		_ink.set("hp_text", _paper.get("hp_text"))
		_ink.set("pct", _paper.get("pct"))
		_paper.queue_redraw()
		_ink.queue_redraw()
		_layout_fill()
		set_process(chip > frac)
		if hp <= 0 and not down:
			_set_down()

	func _layout_fill() -> void:
		if _ink_clip == null:
			return
		_ink_clip.size = Vector2(maxf((size.x - 32.0) * frac, 0.0), BAR_H)
		_bars.queue_redraw()

	func _process(delta: float) -> void:
		if chip > frac:
			chip = maxf(frac, chip - delta * 0.6)
			_bars.queue_redraw()
		else:
			set_process(false)

	## A rubber-stamp DOWN across her name.
	func _set_down() -> void:
		down = true
		var p := PanelContainer.new()
		p.mouse_filter = MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = SignalKit.SIGNAL
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		p.add_theme_stylebox_override("panel", sb)
		p.add_child(Kit.label("DOWN", 28, SignalKit.SIGNAL, "wide_black"))
		p.position = Vector2(size.x * 0.42, 18)
		p.rotation = -0.12
		add_child(p)
		_stamp = p
		if Kit.motion_ok():
			p.pivot_offset = Vector2(60, 20)
			p.scale = Vector2(1.6, 1.6)
			p.modulate.a = 0.0
			var tw := p.create_tween().set_parallel(true)
			tw.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(p, "modulate:a", 1.0, 0.1)

	func _draw_bars() -> void:
		var w := size.x - 32.0
		var r := Rect2(16, BAR_Y, w, BAR_H)
		_bars.draw_rect(r, Color(0.91, 0.91, 0.89, 0.1))
		if chip > frac:
			_bars.draw_rect(Rect2(16 + w * frac, BAR_Y, w * (chip - frac), BAR_H), Color(0.91, 0.91, 0.89, 0.55))
		_bars.draw_rect(Rect2(16, BAR_Y, w * frac, BAR_H), SignalKit.SIGNAL)
		_bars.draw_rect(r, Color(0.91, 0.91, 0.89, 0.55), false, 1.0)
		# Tick ruler under the bar: every 2%, majors every 10%.
		for i in 51:
			var x := 16.0 + minf(w * i / 50.0, w - 0.5)
			var big := i % 5 == 0
			_bars.draw_line(Vector2(x, BAR_Y + BAR_H + 1), Vector2(x, BAR_Y + BAR_H + (8.0 if big else 4.0)), Color(0.91, 0.91, 0.89, 0.6 if big else 0.35), 1.0)


## The boss band's type in one ink: kicker, name, HP numbers and percentage (drawn twice, the ink
## copy clipped to the HP fill).
class _BandText:
	extends Control
	var title := ""
	var kicker := ""
	var fs := 60
	var ink := SignalKit.PAPER
	var accent := SignalKit.SIGNAL
	var hp_text := ""
	var pct := ""

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mb := Kit.font("mono_bold")
		var mono := Kit.font("mono")
		var comp := Kit.font("compressed")
		draw_string(mb, Vector2(16, 17), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)
		var bw := mb.get_string_size("BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(mono, Vector2(16 + bw + 8, 17), kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.8))
		draw_string(comp, Vector2(14, 70), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		var hw := mono.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(mono, Vector2(size.x - 16 - hw, 17), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.8))
		var pw := comp.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string(comp, Vector2(size.x - 16 - pw, 54), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, ink)
