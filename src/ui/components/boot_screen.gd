extends Control
## Boot / loading screen (main.gd shows it while the first screen builds), style v4 "Signal" in the
## poster house style (docs/dev/ui-style-v4.md: section 0, and section 3 "Loading screens: halftone
## hero posters with a line of type"). A printed poster on the paper matte: a wide dark band
## carrying a red halftone print of the lobby hero, HALO & HORN set huge in compressed type turned
## on its side across the band and the paper (paper-white on the band, ink on the paper, the
## ampersand in signal), mono micro type (issue number, date, serials, the three factions as
## labels with ticks down the right-hand rule), a barcode; under the poster a printed progress rule
## (ticks filling in signal), LOADING with the percentage, a rotating tip line and the signature.
## It fades in from the engine's splash colour, so there is no flash at launch.
##   var boot := BootScreen.new(); add_child(boot)
##   boot.set_progress(0.5)              # eased, never goes backwards
##   boot.finish(func() -> void: ...)    # fills to 100 %, fades out, frees itself

const PrintBits := preload("res://src/ui/components/print_bits.gd")

const SPLASH := Color(0.07, 0.055, 0.14, 1)
const MATTE := Color("f5f4f0")
const PAPER := Color("e9e8e2")
const INK := Color("101113")
const BAND := Color("141517")
const SIG := Color("ff4b1f")
const TIPS: Array[String] = [
	"The Sanctum keeps filling while you're away. Collect it from the Lobby.",
	"Your first summon every day is free.",
	"Quick Claim collects hours of Sanctum rewards at once.",
	"Five heroes fight together. Fill every slot in your Team.",
	"Turn off auto ultimates in Settings to time each one yourself.",
	"The Spire is an endless tower beside the campaign.",
]
## Space under the poster for the progress rule, the tip and the signature.
const FOOT_H := 196.0

var _t := 0.0
var _progress := 0.0
var _shown := 0.0
var _tip_i := 0
var _tip: Label
var _pct: Label
var _rule: Control
var _cover: ColorRect
var _poster: Control
var _shadow: Panel
var _band: ColorRect
var _print: TextureRect
var _type: Array[Label] = []
var _clips: Array[Control] = []
var _micro: Control
var _foot: Control
var _finishing := false
var _top := 0.0
var _bottom := 0.0

static var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "BootScreen"
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rng.randomize()
	var ui := Kit.autoload("UI")
	_top = float(ui.call("safe_top")) if ui else 0.0
	_bottom = float(ui.call("safe_bottom")) if ui else 0.0

	var matte := ColorRect.new()
	matte.color = MATTE
	matte.mouse_filter = MOUSE_FILTER_IGNORE
	matte.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(matte)
	_shadow = Panel.new()
	_shadow.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = PAPER
	ss.shadow_color = Color(0, 0, 0, 0.28)
	ss.shadow_size = 22
	ss.shadow_offset = Vector2(0, 8)
	_shadow.add_theme_stylebox_override("panel", ss)
	add_child(_shadow)
	_poster = Control.new()
	_poster.name = "Poster"
	_poster.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.clip_contents = true
	add_child(_poster)
	_band = ColorRect.new()
	_band.color = BAND
	_band.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.add_child(_band)
	_print = _hero_print()
	if _print:
		_band.add_child(_print)
	# Two clips for the giant type: paper-white over the band, ink over the paper.
	for i in 2:
		var clip := Control.new()
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		_poster.add_child(clip)
		_clips.append(clip)
		var rt := Label.new()
		rt.mouse_filter = MOUSE_FILTER_IGNORE
		clip.add_child(rt)
		_type.append(rt)
	_micro = Control.new()
	_micro.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.add_child(_micro)

	_foot = Control.new()
	_foot.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_foot)
	_pct = Kit.label("LOADING  0%", 14, INK, "mono_bold")
	_foot.add_child(_pct)
	var date := Kit.label(Kit._print_date() + "  ·  ISSUE No.001", 14, Color(INK, 0.6), "mono")
	date.name = "Date"
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foot.add_child(date)
	var rule := PrintBits.TickRule.new()
	rule.color = Color(INK, 0.6)
	rule.step = 9.0
	rule.tick = 5.0
	rule.filled = 0.0
	_rule = rule
	_foot.add_child(_rule)
	_tip = Kit.label("", 15, Color(INK, 0.72), "mono")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# A real width up front: an autowrap label measured at zero width keeps a huge height.
	_tip.custom_minimum_size.x = 420
	_foot.add_child(_tip)
	_tip_i = _rng.randi() % TIPS.size()
	_tip.text = "TIP  —  " + TIPS[_tip_i]
	var sig := Kit.label("Halo & Horn", 44, INK, "serif_italic")
	sig.name = "Signature"
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foot.add_child(sig)
	add_child(SignalKit.grain(0.06, true))

	_cover = ColorRect.new()
	_cover.color = SPLASH
	_cover.mouse_filter = MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_cover)
	var tw := _cover.create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	resized.connect(_layout)
	_layout()
	# The giant type typesets down the poster.
	if Kit.motion_ok():
		for l in _type:
			l.visible_ratio = 0.0
			l.create_tween().tween_property(l, "visible_ratio", 1.0, 0.7).set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Target progress 0..1 (the rule eases toward it and never moves backwards).
func set_progress(p: float) -> void:
	_progress = maxf(_progress, clampf(p, 0.0, 1.0))


## Fills the rule, fades the screen out with a slight zoom of the poster, frees itself, then calls
## `done`.
func finish(done: Callable = Callable()) -> void:
	if _finishing:
		return
	_finishing = true
	_progress = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_poster.pivot_offset = _poster.size * 0.5
	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		if done.is_valid():
			done.call())
	tw.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_poster, "scale", Vector2(1.03, 1.03), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## The lobby hero (or the strongest in the team) as a red halftone print, head to waist.
func _hero_print() -> TextureRect:
	var id := _pick_hero()
	if id == "":
		return null
	var skin := Kit.hero_look(id)
	var tex := HeroArt.texture(id, skin)
	if tex == null:
		return null
	var face := HeroArt.portrait_region(id, skin)
	var at := AtlasTexture.new()
	at.atlas = tex
	var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.5, face.size.y * 0.62), Vector2(face.size.x * 1.0, face.size.y * 2.3))
	at.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	var ht := TextureRect.new()
	ht.texture = at
	ht.mouse_filter = MOUSE_FILTER_IGNORE
	ht.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ht.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ht.material = SignalKit.halftone_material(7.0, Kit.PRINT_RED)
	return ht


func _pick_hero() -> String:
	var g := Kit.autoload("Game")
	if g == null:
		return ""
	var want: Variant = g.call("setting", "lobby_hero")
	if want is String and want != "" and bool(g.call("owns", want)):
		return want
	var f: Variant = g.call("formation")
	if f is Array:
		for id: Variant in f:
			if str(id) != "" and HeroArt.has_art(str(id)):
				return str(id)
	var ids := HeroData.ids()
	return str(ids[0]) if not ids.is_empty() else ""


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var pr := Rect2(16, _top + 16, w - 32, maxf(h - _top - 16 - _bottom - FOOT_H, 400.0))
	_shadow.position = pr.position
	_shadow.size = pr.size
	_poster.position = pr.position
	_poster.size = pr.size
	var bw := roundf(pr.size.x * 0.5)
	_band.size = Vector2(bw, pr.size.y)
	if _print:
		_print.position = Vector2(0, pr.size.y * 0.2)
		_print.size = Vector2(bw, pr.size.y * 0.8)
	_set_type(pr.size, bw)
	_set_micro(pr.size, bw)
	# Under the poster: LOADING % and the date over the rule, the tip, the signature.
	var fy := pr.end.y + 26.0
	_foot.position = Vector2(0, fy)
	_foot.size = Vector2(w, FOOT_H - 26.0)
	_pct.position = Vector2(20, 0)
	var date := _foot.get_node("Date") as Label
	date.size = Vector2(320, 20)
	date.position = Vector2(w - 20 - 320, 0)
	_rule.position = Vector2(20, 26)
	_rule.size = Vector2(w - 40, 16)
	_tip.size = Vector2(w - 40 - 230, 0)
	_tip.custom_minimum_size.x = w - 40 - 230
	_tip.position = Vector2(20, 58)
	var sig := _foot.get_node("Signature") as Label
	sig.size = Vector2(240, 60)
	sig.position = Vector2(w - 20 - 240, 50)
	queue_redraw()


## HALO & HORN, turned clockwise and running down the poster across the band's edge.
func _set_type(ps: Vector2, bw: float) -> void:
	var f := Kit.font("compressed")
	var text := "HALO & HORN"
	var fs := 120
	while fs < 320 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 4).x < ps.y * 0.94:
		fs += 4
	var asc := f.get_ascent(fs)
	# Turned clockwise, the caps run from x_top - asc to x_top - asc + 0.72 fs: their middle sits on
	# the band's edge, so the line is half paper-white on the band, half ink on the paper.
	var x_top := bw + asc - fs * 0.36
	for i in 2:
		var x0 := 0.0 if i == 0 else bw
		var wid := bw if i == 0 else ps.x - bw
		_clips[i].position = Vector2(x0, 0)
		_clips[i].size = Vector2(wid, ps.y)
		var l := _type[i]
		l.text = text
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", MATTE if i == 0 else INK)
		l.rotation = PI * 0.5
		l.position = Vector2(x_top - x0, ps.y * 0.03)
	# The ampersand in signal (the poster's one keyword).
	_amp(ps, x_top, fs, f)


var _amp_label: Label
var _led: Control


## A signal "&" laid exactly over the ampersand of the giant line.
func _amp(ps: Vector2, x_top: float, fs: int, f: Font) -> void:
	if _amp_label == null:
		_amp_label = Label.new()
		_amp_label.mouse_filter = MOUSE_FILTER_IGNORE
		_poster.add_child(_amp_label)
		_poster.move_child(_amp_label, _poster.get_child_count() - 1)
	var before := f.get_string_size("HALO ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_amp_label.text = "&"
	_amp_label.add_theme_font_override("font", f)
	_amp_label.add_theme_font_size_override("font_size", fs)
	_amp_label.add_theme_color_override("font_color", SIG)
	_amp_label.rotation = PI * 0.5
	_amp_label.position = Vector2(x_top, ps.y * 0.03 + before)
	_amp_label.visible_ratio = 1.0
	if not Kit.motion_ok():
		return
	_amp_label.modulate.a = 0.0
	_amp_label.create_tween().tween_property(_amp_label, "modulate:a", 1.0, 0.2).set_delay(0.55)


## Mono micro type on the poster: the mark, the issue line, a vertical credit on the band, the three
## factions as labels with ticks down the right-hand rule, a barcode.
func _set_micro(ps: Vector2, _bw: float) -> void:
	for c in _micro.get_children():
		_micro.remove_child(c)
		c.queue_free()
	_micro.size = ps
	var mark := Kit.label("HH", 34, PAPER, "wide_black")
	mark.position = Vector2(20, 18)
	_micro.add_child(mark)
	var tm := Kit.label("™", 12, PAPER, "mono")
	tm.position = Vector2(84, 20)
	_micro.add_child(tm)
	var issue := Kit.label("ISSUE No.001\n%s" % Kit._print_date(), 11, Color(PAPER, 0.8), "mono_bold")
	issue.position = Vector2(20, 66)
	_micro.add_child(issue)
	var rights := Kit.label("©2026 HH, ALL RIGHTS RESERVED.", 11, Color(PAPER, 0.75), "mono_bold")
	rights.rotation = PI * 0.5
	rights.position = Vector2(46, 130)
	_micro.add_child(rights)
	var rx := ps.x - 48.0
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.55)
	rule.mouse_filter = MOUSE_FILTER_IGNORE
	rule.position = Vector2(rx, 0)
	rule.size = Vector2(1, ps.y)
	_micro.add_child(rule)
	var i := 0
	for word: String in ["ANGELS", "DEMONS", "THE FALLEN"]:
		var y := 70.0 + i * ps.y * 0.2
		var tick := ColorRect.new()
		tick.color = INK
		tick.mouse_filter = MOUSE_FILTER_IGNORE
		tick.position = Vector2(rx - 4, y + 2)
		tick.size = Vector2(9, 1)
		_micro.add_child(tick)
		var l := Kit.label(word, 14, INK, "mono_bold")
		l.rotation = PI * 0.5
		l.position = Vector2(rx + 34, y)
		_micro.add_child(l)
		i += 1
	var led := Control.new()
	led.mouse_filter = MOUSE_FILTER_IGNORE
	led.position = Vector2(rx + 14, 30)
	led.size = Vector2(16, 16)
	led.draw.connect(func() -> void:
		var k := 0.5 + 0.5 * sin(_t * 3.4)
		led.draw_circle(Vector2(8, 8), 7.0, Color(SIG, 0.12 * k), true, -1.0, true)
		led.draw_circle(Vector2(8, 8), 3.6, Color(SIG.lightened(0.2 * k), 0.55 + 0.45 * k), true, -1.0, true))
	_micro.add_child(led)
	_led = led
	var bc := SignalKit.barcode(Vector2(150, 30), INK, 2026)
	bc.position = Vector2(ps.x - 48 - 26 - 150, ps.y - 52)
	_micro.add_child(bc)
	var serial := Kit.label("HH-0001  ·  LOADING SHEET", 10, Color(INK, 0.7), "mono")
	serial.position = Vector2(ps.x - 48 - 26 - 150, ps.y - 70)
	_micro.add_child(serial)


func _process(delta: float) -> void:
	_t += delta
	_shown = minf(_progress, _shown + (_progress - _shown) * minf(1.0, delta * 6.0) + delta * 0.04)
	_rule.call("set_filled", _shown)
	_pct.text = "LOADING  %d%%" % int(roundf(_shown * 100.0))
	if _led and is_instance_valid(_led):
		_led.queue_redraw()
	# A new tip every 2.6 s.
	if int(_t / 2.6) != int((_t - delta) / 2.6) and not _finishing:
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := _tip.create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: _tip.text = "TIP  —  " + TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
