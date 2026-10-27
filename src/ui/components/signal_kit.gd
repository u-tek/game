class_name SignalKit
extends RefCounted
## Style v4 "Signal" building blocks shared by every rebuilt screen (docs/dev/ui-style-v4.md). Kit
## keeps the tokens, fonts and the shared widgets; this file holds the v4 pieces: lit plates,
## engraving, the pass button (the owner's "THIS is how I want the main buttons to look"), print
## details (stamp, matrix code, barcode, pill) and the halftone / grain layers.
##
##   SignalKit.plate(preset, pos, size, opts, parent)   a Plate (see plate.gd for presets / opts)
##   SignalKit.pass_button(spec, on_pressed)            the OG-pass call to action (silver over signal)
##   SignalKit.etch(text, size, weight, on_light)       text cut into metal
##   SignalKit.etch_icon(name, size, on_light)          an icon cut into metal
##   SignalKit.pill(text, size, color)                  outlined capsule label
##   SignalKit.stamp(label, value, size)                round inspection stamp
##   SignalKit.matrix(size) / barcode(size, color)
##   SignalKit.halftone_material(cell, ink, light_dots) / grain(amount, still)
##   SignalKit.relight(node)                            light plates by the glowing ones (deferred)

const Plate := preload("res://src/ui/components/plate.gd")

const SIGNAL := Color("ff4b1f")
const PAPER := Color("e9e8e2")
const MATTE := Color("f5f4f0")
const INK := Color("101113")
## Engraved ink on silver / slate.
const ETCH := Color("131416")


## A Plate at pos (added to parent when given). opts: cuts [TL, TR, BR, BL], shape (polygon),
## circle, screws (Array of Vector2), glow, glow_radius, pulse, topo, shadow (alpha), recess, bevel,
## hole (Vector3: a round cut-out, x, y centre and z radius in body px).
static func plate(preset: String, pos: Vector2, size: Vector2, opts: Dictionary = {}, parent: Node = null) -> Control:
	var p := Plate.new()
	p.preset = preset
	p.position = pos
	p.size = size
	if opts.has("cuts"):
		p.cuts = opts["cuts"]
	if opts.has("shape"):
		p.shape = opts["shape"]
	p.circle = opts.get("circle", false)
	if opts.has("screws"):
		for s: Vector2 in opts["screws"]:
			p.screws.append(s)
	p.glow = opts.get("glow", 0.0)
	p.glow_radius = opts.get("glow_radius", 18.0)
	p.pulse = opts.get("pulse", 0.0)
	p.topo = opts.get("topo", 0.0)
	p.shadow_a = opts.get("shadow", 0.6)
	p.recess = opts.get("recess", false)
	if opts.has("bevel"):
		p.bevel = opts["bevel"]
	if opts.has("hole"):
		p.hole = opts["hole"]
	if parent:
		parent.add_child(p)
	return p


## Text cut into a plate: a light lip below, a dark wall above, the fill in the plate's shadow tone.
## on_light: silver / slate / paper; false: graphite.
static func etch(text: String, size: int, weight: String = "mono_bold", on_light: bool = true) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ETCH if on_light else Color(1, 1, 1, 0.58)
	var lip := Color(1, 1, 1, 0.7) if on_light else Color(1, 1, 1, 0.12)
	var wall := Color(0, 0, 0, 0.45) if on_light else Color(0, 0, 0, 0.85)
	for layer: Array in [[lip, Vector2(0, 1)], [wall, Vector2(0, -1)], [fill, Vector2.ZERO]]:
		var l := Kit.label(text, size, layer[0], weight)
		l.position = layer[1]
		box.add_child(l)
	box.custom_minimum_size = (box.get_child(2) as Label).get_minimum_size()
	box.size = box.custom_minimum_size
	return box


## An icon cut into a plate (same lip / wall as etch).
static func etch_icon(icon_name: String, size: float, on_light: bool = true) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(size, size)
	box.size = box.custom_minimum_size
	var fill := ETCH if on_light else Color(1, 1, 1, 0.6)
	var lip := Color(1, 1, 1, 0.55) if on_light else Color(1, 1, 1, 0.1)
	var wall := Color(0, 0, 0, 0.4) if on_light else Color(0, 0, 0, 0.8)
	for layer: Array in [[lip, Vector2(0, 1)], [wall, Vector2(0, -1)], [fill, Vector2.ZERO]]:
		var ic := Kit.icon(icon_name, size, layer[0])
		ic.position = layer[1]
		box.add_child(ic)
	return box


## Outlined capsule label (the OG pass's "OG PASS" pill).
static func pill(text: String, size: int = 20, color: Color = Color.WHITE, weight: String = "wide_black") -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.1)
	ps.border_color = Color(color, 0.92)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(40)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 2
	ps.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", ps)
	p.add_child(Kit.label(text, size, color, weight))
	return p


## The pass button: a brushed silver plate (matrix code, kicker, title, sub line, a machined knob
## with an icon) over a glowing signal plate (an outlined action pill and an info line), the shape of
## the owner's OG-pass reference. spec keys: width (400), kicker, title, sub, action, info, icon,
## code (true). Press: both plates sink, the face brightens, a tap sound and haptic.
static func pass_button(spec: Dictionary, on_pressed: Callable = Callable()) -> Control:
	var w: float = spec.get("width", 400.0)
	var root := Control.new()
	# (The silver is 102 tall: its sub-line at 70 clears the bevel; at 94 it was cut in half.)
	root.custom_minimum_size = Vector2(w, 184)
	root.size = root.custom_minimum_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := pass_plates(root, w, spec, false, true)
	var silver: Control = parts.silver
	var sig: Control = parts.sig
	silver.z_index = 1
	var hit := Button.new()
	hit.theme_type_variation = &"BareButton"
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.position = Vector2(-4, -4)
	hit.size = Vector2(w + 8, 192)
	hit.button_down.connect(func() -> void:
		(silver as Plate).set_pressed_look(true)
		(sig as Plate).set_pressed_look(true)
		Kit.haptic(12))
	hit.button_up.connect(func() -> void:
		(silver as Plate).set_pressed_look(false)
		(sig as Plate).set_pressed_look(false))
	if on_pressed.is_valid():
		hit.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	root.add_child(hit)
	return root


## The pass's two plates and their print, under `parent` (shared by pass_button here and
## PosterKit.pass_button): the signal plate (graphite when off) with the action pill and the info
## line, the silver plate with the matrix code, kicker, title (set smaller to fit), sub line and the
## knob (always when `knob`, else only with spec.icon). Returns {silver, sig, info (or null)}.
static func pass_plates(parent: Control, w: float, spec: Dictionary, off: bool, knob: bool) -> Dictionary:
	var sig := plate("graphite" if off else "signal", Vector2(8, 86), Vector2(w - 14, 96), {"cuts": [0, 12, 18, 0],
		"glow": 0.0 if off else 0.4, "glow_radius": 14.0, "pulse": 0.0 if off else 0.5, "topo": 0.6}, parent)
	var top_sz := Vector2(w, 102)
	var silver := plate("silver", Vector2.ZERO, top_sz, {"shape": Plate.tab_bottom(top_sz, 14, w * 0.33, w * 0.65, 14), "topo": 0.5,
		"screws": [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, 74), Vector2(w - 13, 74)]}, parent)
	var x := 26.0
	if spec.get("code", true):
		var code := matrix(Vector2(58, 58))
		code.position = Vector2(26, 13)
		silver.add_child(code)
		x = 98.0
	var kick := etch(str(spec.get("kicker", "")), 10, "mono_bold")
	kick.position = Vector2(x, 12)
	silver.add_child(kick)
	var with_knob := knob or spec.has("icon")
	var title_txt := str(spec.get("title", ""))
	var ts := int(spec.get("title_size", 30))
	var avail := w - x - (92.0 if with_knob else 24.0)
	var tf := Kit.font("wide_black")
	while ts > 14 and tf.get_string_size(title_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x > avail:
		ts -= 1
	var title := etch(title_txt, ts, "wide_black")
	title.position = Vector2(x - 2, 26 + (30 - ts) * 0.6)
	silver.add_child(title)
	var sub := etch(str(spec.get("sub", "")), 10, "mono")
	sub.position = Vector2(x, 68)
	silver.add_child(sub)
	if with_knob:
		var kn := plate("dial", Vector2(w - 82, 20), Vector2(50, 50), {"circle": true, "shadow": 0.5}, silver)
		var ic := Kit.icon(str(spec.get("icon", "flag")), 22, Color(1, 1, 1, 0.95))
		ic.position = Vector2(14, 14)
		kn.add_child(ic)
	var act := pill(str(spec.get("action", "ENGAGE  >>>")), int(spec.get("action_size", 20)), Color(1, 1, 1, 0.45) if off else Color.WHITE)
	act.position = Vector2(18, 32)
	sig.add_child(act)
	var info: Label = null
	if spec.has("info"):
		var ix := maxf(w * 0.56, 34.0 + act.get_combined_minimum_size().x + 14.0)
		info = Kit.label(str(spec["info"]), 10, Color(1, 1, 1, 0.5 if off else 0.9), "mono")
		info.position = Vector2(ix, 30)
		info.size = Vector2(w - 24 - ix, 40)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sig.add_child(info)
	return {"silver": silver, "sig": sig, "info": info}


## The Back control every screen uses (owner: the old one was too small): an ink disc with a
## paper arrow and "BACK" in mono beside it, a 176 x 96 touch target. on_light false prints it for
## a dark band (paper disc, ink arrow). Named "Back".
static func back_button(on_pressed: Callable, on_light: bool = true, text: String = "BACK") -> Button:
	var b := Button.new()
	b.name = "Back"
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(176, 96)
	b.size = b.custom_minimum_size
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = INK if on_light else PAPER
	ds.set_corner_radius_all(32)
	ds.shadow_color = Color(0, 0, 0, 0.22)
	ds.shadow_size = 6
	ds.shadow_offset = Vector2(0, 3)
	ds.anti_aliasing = true
	disc.add_theme_stylebox_override("panel", ds)
	disc.position = Vector2(8, 16)
	disc.size = Vector2(64, 64)
	disc.pivot_offset = disc.size * 0.5
	b.add_child(disc)
	var ar := Kit.icon("back", 34, PAPER if on_light else INK)
	ar.position = Vector2(15, 15)
	ar.size = Vector2(34, 34)
	disc.add_child(ar)
	var l := Kit.label(text, 18, INK if on_light else PAPER, "mono_bold")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(84, 36)
	b.add_child(l)
	b.button_down.connect(func() -> void:
		disc.scale = Vector2(0.9, 0.9)
		Kit.haptic(10))
	b.button_up.connect(func() -> void:
		var tw := disc.create_tween()
		tw.tween_property(disc, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	return b


## Button family (owner, 2026-10-19: one pass everywhere was too samey). The pass stays for battle
## actions; claims are ink stamps, the shop's buys are price tags, equipping is label-maker tape,
## levelling is an arcade push button (hero_poster_kit.gd PressPass), summons are tickets.
## Each builder returns a Button; `button_text` sets its (invisible) text for tests and readers.

## A rubber stamp inked solid in signal: rough inked edge, the word in paper letters, a kicker and a
## dated rim line; press = the stamp comes down. spec: width (300), height (112), word ("CLAIM"),
## kicker, sub, button_text, disabled.
static func stamp_button(spec: Dictionary, on_pressed: Callable = Callable()) -> Button:
	var w: float = spec.get("width", 300.0)
	var h: float = spec.get("height", 112.0)
	var off := bool(spec.get("disabled", false))
	var b := _bare(Vector2(w, h), str(spec.get("button_text", "")))
	var block := _InkBlock.new()
	block.color = Color(INK, 0.35) if off else SIGNAL
	block.size = Vector2(w, h)
	block.pivot_offset = block.size * 0.5
	b.add_child(block)
	var kick := Kit.label(str(spec.get("kicker", "")), 11, Color(MATTE, 0.8), "mono_bold")
	kick.position = Vector2(20, 12)
	block.add_child(kick)
	var word := Kit.label(str(spec.get("word", "CLAIM")), 40, MATTE, "wide_black")
	word.position = Vector2(18, 26)
	block.add_child(word)
	var fw := Kit.font("wide_black").get_string_size(word.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	if fw > w - 40.0:
		word.scale = Vector2.ONE * ((w - 40.0) / fw)
	var sub := Kit.label(str(spec.get("sub", "")), 11, Color(MATTE, 0.85), "mono")
	sub.position = Vector2(20, h - 28)
	block.add_child(sub)
	b.set_meta("sub_label", sub)
	b.set_meta("word_label", word)
	var rule := ColorRect.new()
	rule.color = Color(MATTE, 0.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.position = Vector2(20, h - 34)
	rule.size = Vector2(w - 40, 1)
	block.add_child(rule)
	b.disabled = off
	b.button_down.connect(func() -> void:
		block.scale = Vector2(0.95, 0.95)
		block.rotation = -0.02
		Kit.haptic(14))
	b.button_up.connect(func() -> void:
		var tw := block.create_tween().set_parallel(true)
		tw.tween_property(block, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(block, "rotation", 0.0, 0.22))
	if not off and Kit.motion_ok():
		var pt := block.create_tween().set_loops()
		pt.tween_property(block, "modulate", Color(1.12, 1.12, 1.12), 0.8).set_trans(Tween.TRANS_SINE)
		pt.tween_property(block, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	return b


## A price tag: a paper tag with a punched, rimmed eyelet and its string, the price set huge, a
## kicker, a note line, a barcode and the action in a signal box. spec: width (240), height (300),
## price, kicker, note, action ("BUY"), button_text, disabled, fill ("paper" | "signal").
static func tag_button(spec: Dictionary, on_pressed: Callable = Callable()) -> Button:
	if bool(spec.get("horizontal", false)):
		return _tag_wide(spec, on_pressed)
	var w: float = spec.get("width", 240.0)
	var h: float = spec.get("height", 300.0)
	var off := bool(spec.get("disabled", false))
	var hot := str(spec.get("fill", "paper")) == "signal"
	var b := _bare(Vector2(w, h), str(spec.get("button_text", "")))
	var tag := _TagShape.new()
	tag.fill = SIGNAL if hot else Color("f1efe8")
	tag.size = Vector2(w, h)
	tag.pivot_offset = Vector2(w * 0.5, 0)
	tag.rotation = -0.04
	b.add_child(tag)
	var ink := MATTE if hot else INK
	var eye := plate("silver", Vector2(w * 0.5 - 15, 10), Vector2(30, 30), {"circle": true, "shadow": 0.4, "hole": Vector3(15, 15, 7)}, tag)
	eye.name = "Eyelet"
	var kick := Kit.label(str(spec.get("kicker", "")), 11, Color(ink, 0.75), "mono_bold")
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kick.size = Vector2(w, 16)
	kick.position = Vector2(0, 52)
	tag.add_child(kick)
	var price := Kit.label(str(spec.get("price", "")), 58, ink, "compressed")
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.size = Vector2(w, 70)
	price.position = Vector2(0, 68)
	var pw := Kit.font("compressed").get_string_size(price.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
	if pw > w - 24.0:
		price.add_theme_font_size_override("font_size", int(58.0 * (w - 24.0) / pw))
	tag.add_child(price)
	var note := Kit.label(str(spec.get("note", "")), 11, Color(ink, 0.8), "mono")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size = Vector2(w - 24, 30)
	note.position = Vector2(12, 142)
	tag.add_child(note)
	var bc := barcode(Vector2(w - 60, 26), Color(ink, 0.85), 77)
	bc.position = Vector2(30, h - 112)
	tag.add_child(bc)
	var act := PanelContainer.new()
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.35) if off else (INK if hot else SIGNAL)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	act.add_theme_stylebox_override("panel", sb)
	act.add_child(Kit.label(str(spec.get("action", "BUY")), 20, MATTE, "wide_black"))
	act.position = Vector2(18, h - 70)
	act.custom_minimum_size = Vector2(w - 36, 0)
	(act.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(act)
	b.disabled = off
	b.button_down.connect(func() -> void:
		tag.rotation = 0.03
		tag.scale = Vector2(0.97, 0.97)
		Kit.haptic(12))
	b.button_up.connect(func() -> void:
		var tw := tag.create_tween().set_parallel(true)
		tw.tween_property(tag, "rotation", -0.04, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(tag, "scale", Vector2.ONE, 0.2))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	return b


## The price tag on its side (fits where a pass used to sit): eyelet and string on the left, the
## price huge, a note and a barcode, the action in a box on the right. spec as tag_button plus
## width (400), height (150).
static func _tag_wide(spec: Dictionary, on_pressed: Callable) -> Button:
	var w: float = spec.get("width", 400.0)
	var h: float = spec.get("height", 150.0)
	var off := bool(spec.get("disabled", false))
	var hot := str(spec.get("fill", "paper")) == "signal"
	var b := _bare(Vector2(w, h + 12), str(spec.get("button_text", "")))
	var tag := _TagShape.new()
	tag.horizontal = true
	tag.fill = SIGNAL if hot else Color("f1efe8")
	tag.size = Vector2(w, h)
	tag.position = Vector2(0, 6)
	tag.pivot_offset = Vector2(0, h * 0.5)
	tag.rotation = -0.025
	b.add_child(tag)
	var ink := MATTE if hot else INK
	plate("silver", Vector2(12, h * 0.5 - 15), Vector2(30, 30), {"circle": true, "shadow": 0.4, "hole": Vector3(15, 15, 7)}, tag)
	var box_w := minf(150.0, w * 0.36)
	var x0 := 58.0
	var kick := Kit.label(str(spec.get("kicker", "")), 10, Color(ink, 0.75), "mono_bold")
	kick.position = Vector2(x0, 14)
	kick.size = Vector2(w - x0 - box_w - 24, 14)
	kick.clip_text = true
	tag.add_child(kick)
	var price := Kit.label(str(spec.get("price", "")), 56, ink, "compressed")
	price.position = Vector2(x0 - 2, 26)
	var room := w - x0 - box_w - 28.0
	var pw := Kit.font("compressed").get_string_size(price.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	if pw > room:
		price.add_theme_font_size_override("font_size", maxi(24, int(56.0 * room / pw)))
	tag.add_child(price)
	var note := Kit.label(str(spec.get("note", "")), 11, Color(ink, 0.85), "mono")
	note.position = Vector2(x0, h - 30)
	note.size = Vector2(room, 16)
	note.clip_text = true
	tag.add_child(note)
	var bc := barcode(Vector2(box_w, 22), Color(ink, 0.85), 77)
	bc.position = Vector2(w - box_w - 16, 16)
	tag.add_child(bc)
	var act := PanelContainer.new()
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(INK, 0.3) if off else (INK if hot else SIGNAL)
	sb.set_corner_radius_all(3)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	act.add_theme_stylebox_override("panel", sb)
	var al := Kit.label(str(spec.get("action", "BUY")), 22, MATTE, "wide_black")
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.add_child(al)
	act.custom_minimum_size = Vector2(box_w, 0)
	act.position = Vector2(w - box_w - 16, h - 70)
	tag.add_child(act)
	if spec.has("info"):
		var info := Kit.label(str(spec["info"]), 9, Color(ink, 0.7), "mono")
		info.position = Vector2(w - box_w - 16, 44)
		info.size = Vector2(box_w, 14)
		info.clip_text = true
		tag.add_child(info)
	b.disabled = off
	b.button_down.connect(func() -> void:
		tag.rotation = 0.015
		tag.scale = Vector2(0.98, 0.98)
		Kit.haptic(12))
	b.button_up.connect(func() -> void:
		var tw := tag.create_tween().set_parallel(true)
		tw.tween_property(tag, "rotation", -0.025, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(tag, "scale", Vector2.ONE, 0.2))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	return b


## Label-maker tape: embossed paper letters on a glossy strip (signal or ink) cut with notched
## ends, stuck on at a slight tilt; press = it flattens. 96 px tall target.
static func tape_button(text: String, on_pressed: Callable = Callable(), color: Color = SIGNAL, button_text: String = "") -> Button:
	var f := Kit.font("wide_black")
	var tw_px := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var w := tw_px + 64.0
	var b := _bare(Vector2(w, 96), button_text)
	var tape := _Tape.new()
	tape.color = color
	tape.size = Vector2(w, 60)
	tape.position = Vector2(0, 18)
	tape.pivot_offset = tape.size * 0.5
	tape.rotation = -0.025
	b.add_child(tape)
	for layer: Array in [[Color(1, 1, 1, 0.35), Vector2(0, -1)], [Color(0, 0, 0, 0.35), Vector2(0, 2)], [Color("f7f6f1"), Vector2.ZERO]]:
		var l := Kit.label(text, 26, layer[0], "wide_black")
		l.position = Vector2(32, 12) + (layer[1] as Vector2)
		tape.add_child(l)
	b.button_down.connect(func() -> void:
		tape.scale = Vector2(0.97, 0.9)
		Kit.haptic(10))
	b.button_up.connect(func() -> void:
		tape.create_tween().tween_property(tape, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	if on_pressed.is_valid():
		b.pressed.connect(func() -> void:
			Kit.sfx("tap")
			on_pressed.call())
	return b


static func _bare(sz: Vector2, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = sz
	b.size = sz
	if text != "":
		# Readable by tests and screen readers, invisible on the print.
		b.text = text
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color(0, 0, 0, 0))
	return b


## A solid ink block with a rough, inked edge (a rubber stamp's impression).
class _InkBlock:
	extends Control
	var color := Color("ff4b1f")

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 911
		var pts := PackedVector2Array()
		var n := 18
		for side in 4:
			for i in n:
				var t := float(i) / n
				var p: Vector2
				match side:
					0:
						p = Vector2(t * size.x, 0)
					1:
						p = Vector2(size.x, t * size.y)
					2:
						p = Vector2(size.x * (1.0 - t), size.y)
					_:
						p = Vector2(0, size.y * (1.0 - t))
				var nrm := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][side] as Vector2
				pts.append(p + nrm * rng.randf_range(-1.6, 1.2))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.18) if color.a > 0.5 else Color(0, 0, 0, 0), PackedVector2Array(), null)
		var shifted := PackedVector2Array()
		for p in pts:
			shifted.append(p - Vector2(0, 3))
		draw_colored_polygon(shifted, color)
		# Ink speckle: paper showing through.
		for i in 70:
			var q := Vector2(rng.randf_range(4, size.x - 4), rng.randf_range(2, size.y - 6))
			draw_circle(q, rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.08, 0.22)))


## A shipping-tag shape with a soft shadow (the eyelet sits at the top centre) and its string.
class _TagShape:
	extends Control
	var fill := Color("f1efe8")
	var horizontal := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := 34.0
		if horizontal:
			var hp := PackedVector2Array([Vector2(0, c), Vector2(c, 0), Vector2(w, 0), Vector2(w, h), Vector2(c, h), Vector2(0, h - c)])
			var hs := PackedVector2Array()
			for p in hp:
				hs.append(p + Vector2(5, 7))
			draw_colored_polygon(hs, Color(0, 0, 0, 0.18))
			draw_colored_polygon(hp, fill)
			var outline := hp.duplicate()
			outline.append(hp[0])
			draw_polyline(outline, Color(0, 0, 0, 0.12), 1.0, true)
			var e := Vector2(27, h * 0.5)
			draw_polyline(PackedVector2Array([e, e + Vector2(-22, -14), e + Vector2(-44, 4), e + Vector2(-60, -10)]), Color("101113"), 2.0, true)
			return
		var pts := PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h), Vector2(0, h), Vector2(0, c)])
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(5, 8))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.18))
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h), Vector2(0, h), Vector2(0, c), Vector2(c, 0)]),
			Color(0, 0, 0, 0.12), 1.0, true)
		# The string, looping up out of the eyelet.
		var e := Vector2(w * 0.5, 25)
		draw_polyline(PackedVector2Array([e, e + Vector2(-10, -30), e + Vector2(6, -60), e + Vector2(30, -78)]), Color("101113"), 2.0, true)


## A label-maker tape strip: glossy fill, notched ends, a highlight along the top.
class _Tape:
	extends Control
	var color := Color("ff4b1f")

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var n := 8.0
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - n, h * 0.5), Vector2(w, h), Vector2(0, h), Vector2(n, h * 0.5)])
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(3, 5))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.22))
		draw_colored_polygon(pts, color)
		draw_rect(Rect2(n, 3, w - n * 2, 3), Color(1, 1, 1, 0.22))
		draw_rect(Rect2(n, h - 5, w - n * 2, 2), Color(0, 0, 0, 0.18))


## Round inspection stamp: text around the rim, a big value in the middle.
static func stamp(label: String, value: String, size: float = 112.0) -> Control:
	var s := _Stamp.new()
	s.label = label
	s.value = value
	s.custom_minimum_size = Vector2(size, size)
	s.size = s.custom_minimum_size
	return s


static func matrix(size: Vector2) -> Control:
	var m := _Matrix.new()
	m.custom_minimum_size = size
	m.size = size
	return m


static func barcode(size: Vector2, color: Color = INK, seed_value: int = 289) -> Control:
	var b := _Barcode.new()
	b.color = color
	b.seed_value = seed_value
	b.custom_minimum_size = size
	b.size = size
	return b


## Halftone material for a TextureRect (dots follow brightness, or darkness when light_dots false).
static func halftone_material(cell: float = 7.0, ink: Color = Color(1.0, 0.36, 0.16, 0.95), light_dots: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ui/shaders/halftone.gdshader")
	m.set_shader_parameter("cell", cell)
	m.set_shader_parameter("ink", ink)
	m.set_shader_parameter("light_dots", light_dots)
	m.set_shader_parameter("gain", 1.25)
	return m


## Full-rect film grain (multiplied). Add it last.
static func grain(amount: float = 0.045, still: bool = false) -> ColorRect:
	var g := ColorRect.new()
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ui/shaders/grain.gdshader")
	m.set_shader_parameter("amount", amount)
	m.set_shader_parameter("still", still or not Kit.motion_ok())
	g.material = m
	return g


## Lights every plate by the glowing plates and tubes near it, once the layout has settled.
static func relight(node: Node) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(node):
		Plate.relight_all(tree)


class _Stamp:
	extends Control
	var label := "SANCTUM · "
	var value := "41%"
	var ink := Color(0.1, 0.11, 0.12, 0.85)

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r - 6.0, 0.0, TAU, 64, ink, 1.5, true)
		draw_arc(c, r - 22.0, 0.0, TAU, 64, ink, 1.0, true)
		var f := Kit.font("mono_bold")
		for i in label.length():
			var a := -PI * 0.5 + TAU * i / label.length()
			var pos := c + Vector2(cos(a), sin(a)) * (r - 14.0)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(f, Vector2(-3.0, 3.5), label[i], 9, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var fb := Kit.font("wide_black")
		var fs := int(clampf(r * 0.42, 12.0, 40.0))
		var w := fb.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fb, c + Vector2(-w * 0.5, fs * 0.38), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## Decorative matrix code with three finder squares (not a scannable code).
class _Matrix:
	extends Control

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := 21
		var c := size.x / n
		var rng := RandomNumberGenerator.new()
		rng.seed = 2044
		var ink := Color("1e2023")
		for y in n:
			for x in n:
				if (x < 7 and y < 7) or (x >= n - 7 and y < 7) or (x < 7 and y >= n - 7):
					continue
				if rng.randf() < 0.48:
					draw_rect(Rect2(x * c, y * c, c, c), ink)
		for f: Vector2 in [Vector2(0, 0), Vector2(n - 7, 0), Vector2(0, n - 7)]:
			draw_rect(Rect2(f * c, Vector2(7, 7) * c), ink)
			draw_rect(Rect2((f + Vector2(1, 1)) * c, Vector2(5, 5) * c), Color("d8dbd7"))
			draw_rect(Rect2((f + Vector2(2, 2)) * c, Vector2(3, 3) * c), ink)


## Decorative barcode (seeded bars, not a real code).
class _Barcode:
	extends Control
	var color := Color("101113")
	var seed_value := 289

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x := 0.0
		while x < size.x:
			var bw := float(rng.randi_range(1, 4))
			if rng.randf() < 0.7:
				draw_rect(Rect2(x, 0, minf(bw, size.x - x), size.y), color)
			x += bw + float(rng.randi_range(1, 3))
