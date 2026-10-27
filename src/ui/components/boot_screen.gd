extends Control
## Boot / loading screen: a print run (style v4 "Signal", the poster house style; docs/dev/ui-style-v4.md
## section 3, "Loading screens"). The loading poster (a dark band with the Lobby hero as a red
## halftone print, HALO & HORN set huge on its side across the band's edge, mono micro type, a
## barcode) is printed live while the game loads, about four seconds in all (owner, 2026-10-20: "load
## for longer, and be animated, rather than just jumping into the game"):
##   0.0   crop marks print on the matte where the sheet will land            MAKE READY
##   0.3   the blank sheet feeds in from the press and settles into the marks FEEDING SHEET
##   1.0   an ink roller runs down it: the key plate (band, type, micro type)  PLATE 1 · KEY
##   1.6   a signal-red roller: her halftone print, the ampersand, the light,  PLATE 2 · SIGNAL
##         a hair out of register; 2.3 it snaps into register with the target  REGISTER
##   2.65  the press comes down: HALO & HORN is debossed into the paper        PRESSING
##   3.05  the proof stamp                                                     PROOF OK
##   3.6   once the real work is done (main.gd: threaded loads, then the Lobby built under this
##         screen and drawn once), the sheet is pulled off the press, up and away, and the Lobby
##         plays its intro.
## Under the poster: LOADING % with the stage, the sheet counter, a printed progress rule that never
## runs ahead of the real work (nor ahead of the run), a tip that changes every 2.6 s, the signature.
## Everything is a function of time (_apply), so a shot can hold any moment (freeze_at).
## Reduce motion: the poster stands printed, the rule fills, a short fade.
##   var boot := BootScreen.new(); add_child(boot)
##   boot.show_print(hero_id, skin)      # her halftone print (once her art is loaded)
##   boot.set_progress(0.5)              # real work done, 0..1 (never goes backwards)
##   boot.finish(func() -> void: ...)    # lifts when the run is done, calls `done`, frees itself
##   boot.freeze_at(1.8)                 # screenshots: hold the run at 1.8 s

const PrintBits := preload("res://src/ui/components/print_bits.gd")

const SPLASH := Color(0.07, 0.055, 0.14, 1)
const MATTE := SignalKit.MATTE
const PAPER := SignalKit.PAPER
const INK := SignalKit.INK
const BAND := Kit.BAND
const SIG := SignalKit.SIGNAL
const TIPS: Array[String] = [
	"The Sanctum keeps filling while you're away. Collect it from the Lobby.",
	"Your first summon every day is free.",
	"Quick Claim collects hours of Sanctum rewards at once.",
	"Five heroes fight together. Fill every slot in your Team.",
	"Turn off auto ultimates in Settings to time each one yourself.",
	"The Spire is an endless tower beside the campaign.",
	"Beat Rue to clean her tag off your Lobby poster.",
	"Every summoned hero is a numbered print. Some come out misprinted.",
]
## Space under the poster for the progress rule, the tip and the signature.
const FOOT_H := 196.0
## The run (seconds) before the sheet may leave the press, and the lift-off.
const RUN := 3.6
const EXIT := 0.5
const T_MARKS := Vector2(0.06, 0.5)
const T_FEED := Vector2(0.3, 1.02)
const T_KEY := Vector2(1.0, 1.62)
const T_SIG := Vector2(1.6, 2.22)
const T_REG := Vector2(2.3, 2.62)
const T_PRESS := 2.65
const T_STAMP := 3.05
## How far the signal plate lands out of register before it snaps in.
const MISREG := Vector2(12, -8)
const ROLLER_H := 34.0
const DEPTH := 4.5
const STAGES := [[0.3, "MAKE READY"], [1.0, "FEEDING SHEET"], [1.6, "PLATE 1 · KEY"], [2.3, "PLATE 2 · SIGNAL"],
	[2.65, "REGISTER"], [3.05, "PRESSING"], [99.0, "PROOF OK"]]
const COUNT_TO := 2026

var _t := 0.0
var _frozen := false
var _motion := true
var _progress := 0.0
var _shown := 0.0
var _finishing := false
var _done := Callable()
var _exiting := false
var _exit_t := 0.0
var _tip_i := 0
var _top := 0.0
var _bottom := 0.0
var _pr := Rect2()
var _bw := 0.0
var _last_stage := ""

var _matte: ColorRect
var _marks: Control
var _holder: Control
var _poster: Control
var _key_a: Control
var _sig_a: Control
var _sig_a_in: Control
var _key_b: Control
var _sig_b: Control
var _sig_b_in: Control
var _type_group: Node
var _amp_group: Node
var _type: Array[Label] = []
var _clips: Array[Control] = []
var _amp_label: Label
var _micro: Control
var _sig_micro: Control
var _print: TextureRect
var _print_id := ""
var _stamp: Control
var _roller_k: Roller
var _roller_s: Roller
var _foot: Control
var _pct: Label
var _stage: Label
var _count: Label
var _rule: Control
var _tip: Label
var _grain: Control
var _cover: ColorRect
var _led: Control

static var _rng := RandomNumberGenerator.new()
## The signal plate's ink: the house red, or on a holiday with its own ink (calendar.json) that ink:
## the print shop runs the day's colour, and the proof stamp names the day.
var _ink := SIG
var _day_word := ""


func _ready() -> void:
	name = "BootScreen"
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rng.randomize()
	_motion = Kit.motion_ok()
	var g := Kit.autoload("Game")
	if g != null and g.has_method("today"):
		var day := int(g.call("today"))
		var hx := CalendarRules.ink(day)
		if hx != "":
			_ink = Color(hx)
			for h: Dictionary in CalendarRules.holidays_on(day):
				_day_word = str(h.get("stamp", ""))
				break
	var ui := Kit.autoload("UI")
	_top = float(ui.call("safe_top")) if ui else 0.0
	_bottom = float(ui.call("safe_bottom")) if ui else 0.0

	_matte = ColorRect.new()
	_matte.color = MATTE
	_matte.mouse_filter = MOUSE_FILTER_IGNORE
	_matte.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_matte)
	_marks = CropMarks.new()
	add_child(_marks)
	_build_sheet()
	_build_foot()
	_roller_k = Roller.new()
	_roller_k.name = "InkRoller"
	add_child(_roller_k)
	_roller_s = Roller.new()
	_roller_s.name = "SignalRoller"
	_roller_s.signal_ink = true
	_roller_s.ink = _ink
	add_child(_roller_s)
	_grain = SignalKit.grain(0.06, true)
	add_child(_grain)

	_cover = ColorRect.new()
	_cover.color = SPLASH
	_cover.mouse_filter = MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_cover)
	var tw := _cover.create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.4 if _motion else 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	resized.connect(_layout)
	_layout()


## Target progress 0..1 of the real work (the rule eases toward it and never moves backwards).
func set_progress(p: float) -> void:
	_progress = maxf(_progress, clampf(p, 0.0, 1.0))


## The real work is done: once the run has printed (and the rule is full) the sheet lifts off, `done`
## is called as it goes (the Lobby plays its intro under it) and the screen frees itself.
func finish(done: Callable = Callable()) -> void:
	if _finishing:
		return
	_finishing = true
	_done = done
	_progress = 1.0


## Screenshots: holds the run at `t` seconds (the rule shows what the run would show then).
func freeze_at(t: float) -> void:
	_frozen = true
	_t = maxf(t, 0.0)
	if _cover:
		_cover.visible = false
	_apply(_anim_t())


## Her red halftone print on the band (head to waist), from her loaded art.
func show_print(id: String, skin: String) -> void:
	if id == "" or id == _print_id or _sig_a_in == null:
		return
	_print_id = id
	var tex := HeroArt.texture(id, skin)
	if tex == null:
		return
	var face := HeroArt.portrait_region(id, skin)
	var at := AtlasTexture.new()
	at.atlas = tex
	var reg := Rect2(face.get_center() - Vector2(face.size.x * 0.5, face.size.y * 0.62), Vector2(face.size.x * 1.0, face.size.y * 2.3))
	at.region = reg.intersection(Rect2(Vector2.ZERO, Vector2(tex.get_size())))
	if _print and is_instance_valid(_print):
		_print.queue_free()
	_print = TextureRect.new()
	_print.name = "HalftonePrint"
	_print.texture = at
	_print.mouse_filter = MOUSE_FILTER_IGNORE
	_print.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_print.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_print.material = SignalKit.halftone_material(7.0, Kit.PRINT_RED if _ink == SIG else _ink)
	_sig_a_in.add_child(_print)
	_place_print()
	# Late art (the signal plate already ran): it inks in.
	if _motion and not _frozen and _t > T_SIG.x:
		_print.modulate.a = 0.0
		_print.create_tween().tween_property(_print, "modulate:a", 1.0, 0.35)


# ------------------------------------------------------------------ build

## The sheet: real paper (PhysicalKit) and its plates as clipped layers in print order: key band,
## signal print, key type and micro type, signal ampersand and marks; the proof stamp on top.
func _build_sheet() -> void:
	# (Laid out in _layout; the relief overlay goes on once the plates are in, deferred.)
	_poster = PhysicalKit.sheet(self, Rect2(16, 16, 688, 1000), PAPER, 0.28, {"relief": true})
	_holder = _poster.get_meta("shadow") as Control
	_key_a = _plate("KeyBand")
	_sig_a = _plate("SignalPrint")
	_sig_a_in = _inner(_sig_a)
	_key_b = _plate("KeyType")
	_type_group = PhysicalKit.deboss(_key_b, DEPTH)
	for i in 2:
		var clip := Control.new()
		clip.mouse_filter = MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		_type_group.add_child(clip)
		_clips.append(clip)
		var l := Label.new()
		l.mouse_filter = MOUSE_FILTER_IGNORE
		clip.add_child(l)
		_type.append(l)
	_micro = Control.new()
	_micro.name = "Micro"
	_micro.mouse_filter = MOUSE_FILTER_IGNORE
	_key_b.add_child(_micro)
	_sig_b = _plate("SignalMarks")
	_sig_b_in = _inner(_sig_b)
	_amp_group = PhysicalKit.deboss(_sig_b_in, DEPTH)
	_amp_label = Label.new()
	_amp_label.mouse_filter = MOUSE_FILTER_IGNORE
	_amp_group.add_child(_amp_label)
	_sig_micro = Control.new()
	_sig_micro.name = "SignalMicro"
	_sig_micro.mouse_filter = MOUSE_FILTER_IGNORE
	_sig_b_in.add_child(_sig_micro)
	var rim := "PRESS PROOF · %s · RUN 2026 · " % (_day_word if _day_word != "" else "HALO & HORN")
	_stamp = SignalKit.stamp(rim, "OK", 136.0)
	_stamp.name = "ProofStamp"
	_stamp.set("ink", Color(_ink.darkened(0.12 if _ink != SIG else 0.0), 0.92))
	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.rotation = -0.16
	_poster.add_child(_stamp)


func _plate(plate_name: String) -> Control:
	var c := Control.new()
	c.name = plate_name
	c.mouse_filter = MOUSE_FILTER_IGNORE
	c.clip_contents = true
	_poster.add_child(c)
	return c


## A plate's content holder (offset out of register while the plate prints).
func _inner(plate: Control) -> Control:
	var c := Control.new()
	c.mouse_filter = MOUSE_FILTER_IGNORE
	plate.add_child(c)
	return c


func _build_foot() -> void:
	_foot = Control.new()
	_foot.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_foot)
	_pct = Kit.label("LOADING  0%", 14, INK, "mono_bold")
	_foot.add_child(_pct)
	_stage = Kit.label("", 14, Color(INK, 0.6), "mono")
	_foot.add_child(_stage)
	_count = Kit.label("", 14, Color(INK, 0.6), "mono")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foot.add_child(_count)
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


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	_pr = Rect2(16, _top + 16, w - 32, maxf(h - _top - 16 - _bottom - FOOT_H, 400.0))
	var ps := _pr.size
	_bw = roundf(ps.x * 0.5)
	for n: Control in [_holder, _poster]:
		n.size = ps
		n.pivot_offset = ps * 0.5
	var paper := _holder.get_node_or_null("Paper") as ColorRect
	if paper:
		paper.size = ps + Vector2(PhysicalKit.MARGIN, PhysicalKit.MARGIN) * 2.0
		(paper.material as ShaderMaterial).set_shader_parameter("rect_size", paper.size)
	var relief: Variant = _poster.get_meta("relief") if _poster.has_meta("relief") else null
	if relief is ColorRect:
		(relief as ColorRect).size = ps
		((relief as ColorRect).material as ShaderMaterial).set_shader_parameter("rect_size", ps)
		var bb := _poster.get_node_or_null("ReliefCopy") as BackBufferCopy
		if bb:
			bb.rect = Rect2(Vector2.ZERO, ps)
	for plate: Control in [_key_a, _sig_a, _key_b, _sig_b]:
		plate.size = ps
	for n: Node in _key_a.get_children():
		n.queue_free()
	var band := ColorRect.new()
	band.color = BAND
	band.mouse_filter = MOUSE_FILTER_IGNORE
	band.size = Vector2(_bw, ps.y)
	_key_a.add_child(band)
	_place_print()
	_set_type(ps, _bw)
	_set_micro(ps, _bw)
	_stamp.position = Vector2(_bw + (ps.x - 48.0 - _bw) * 0.56, ps.y * 0.6) - _stamp.size * 0.5
	(_marks as CropMarks).rect = _pr
	_marks.size = size
	_roller_k.size = Vector2(ps.x + 28.0, ROLLER_H + 18.0)
	_roller_s.size = _roller_k.size
	# Under the poster: LOADING % and the stage, the counter, the rule, the tip, the signature.
	var fy := _pr.end.y + 26.0
	_foot.position = Vector2(0, fy)
	_foot.size = Vector2(w, FOOT_H - 26.0)
	_pct.position = Vector2(20, 0)
	_stage.position = Vector2(150, 0)
	_count.size = Vector2(300, 20)
	_count.position = Vector2(w - 20 - 300, 0)
	_rule.position = Vector2(20, 26)
	_rule.size = Vector2(w - 40, 16)
	_tip.size = Vector2(w - 40 - 230, 0)
	_tip.custom_minimum_size.x = w - 40 - 230
	_tip.position = Vector2(20, 58)
	var sig := _foot.get_node("Signature") as Label
	sig.size = Vector2(240, 60)
	sig.position = Vector2(w - 20 - 240, 50)
	_apply(_anim_t())


func _place_print() -> void:
	if _print and is_instance_valid(_print) and _pr.size.y > 0.0:
		_print.position = Vector2(0, _pr.size.y * 0.2)
		_print.size = Vector2(_bw, _pr.size.y * 0.8)


## HALO & HORN, turned clockwise and running down the poster across the band's edge: paper-white
## over the band (knocked out of the key plate), ink over the paper; the ampersand on the signal plate.
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
	var before := f.get_string_size("HALO ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_amp_label.text = "&"
	_amp_label.add_theme_font_override("font", f)
	_amp_label.add_theme_font_size_override("font_size", fs)
	_amp_label.add_theme_color_override("font_color", _ink)
	_amp_label.rotation = PI * 0.5
	_amp_label.position = Vector2(x_top, ps.y * 0.03 + before)


## Mono micro type on the poster (key plate): the mark, the issue line, a vertical credit on the band,
## a job ticket, the three factions as labels with ticks down the right-hand rule, the colour bar and
## register target, the serial and a barcode. On the signal plate: the light, the bar's signal patches
## and the signal target (they show the misregistration, then line up).
func _set_micro(ps: Vector2, bw: float) -> void:
	for holder: Control in [_micro, _sig_micro]:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		holder.size = ps
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
	var col_x := bw + 96.0
	var job := Kit.label("JOB      HH-0001\nSTOCK    FELT 120\nPLATES   K + SIGNAL\nPRESS    01", 10, Color(INK, 0.72), "mono")
	job.add_theme_constant_override("line_spacing", 2)
	job.position = Vector2(col_x, 22)
	_micro.add_child(job)
	_rect(_micro, Rect2(col_x, 16, rx - 14.0 - col_x, 1), Color(INK, 0.45))
	_rect(_micro, Rect2(rx, 0, 1, ps.y), Color(INK, 0.55))
	var i := 0
	for word: String in ["ANGELS", "DEMONS", "THE FALLEN"]:
		var y := 70.0 + i * ps.y * 0.2
		_rect(_micro, Rect2(rx - 4, y + 2, 9, 1), INK)
		var l := Kit.label(word, 14, INK, "mono_bold")
		l.rotation = PI * 0.5
		l.position = Vector2(rx + 34, y)
		_micro.add_child(l)
		i += 1
	# The colour bar (ink 100/60/30, then signal 100/60/30) and the register target.
	var by := ps.y - 112.0
	for k in 3:
		_rect(_micro, Rect2(col_x + k * 16.0, by, 14, 14), Color(INK, [1.0, 0.6, 0.3][k]))
		_rect(_sig_micro, Rect2(col_x + 48.0 + k * 16.0, by, 14, 14), Color(_ink, [1.0, 0.6, 0.3][k]))
	var tgt := Vector2(col_x + 120.0, by + 7.0)
	_micro.add_child(Target.new(tgt, INK))
	_sig_micro.add_child(Target.new(tgt, _ink))
	var bc := SignalKit.barcode(Vector2(150, 30), INK, 2026)
	bc.position = Vector2(rx - 26 - 150, ps.y - 52)
	_micro.add_child(bc)
	var serial := Kit.label("HH-0001  ·  LOADING SHEET", 10, Color(INK, 0.7), "mono")
	serial.position = Vector2(rx - 26 - 150, ps.y - 70)
	_micro.add_child(serial)
	_led = Control.new()
	_led.mouse_filter = MOUSE_FILTER_IGNORE
	_led.position = Vector2(rx + 14, 30)
	_led.size = Vector2(16, 16)
	_led.draw.connect(func() -> void:
		var k := 0.5 + 0.5 * sin(_t * 3.4) if _motion else 1.0
		_led.draw_circle(Vector2(8, 8), 7.0, Color(_ink, 0.12 * k), true, -1.0, true)
		_led.draw_circle(Vector2(8, 8), 3.6, Color(_ink.lightened(0.2 * k), 0.55 + 0.45 * k), true, -1.0, true))
	_sig_micro.add_child(_led)


func _rect(parent: Control, r: Rect2, c: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.color = c
	cr.mouse_filter = MOUSE_FILTER_IGNORE
	cr.position = r.position
	cr.size = r.size
	parent.add_child(cr)
	return cr


# ------------------------------------------------------------------ the run

## The moment the poster shows: the run's time, or its end when motion is off.
func _anim_t() -> float:
	return _t if _motion else RUN


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.001), 0.0, 1.0)


static func _out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _out_back(x: float, s: float = 1.6) -> float:
	var y := x - 1.0
	return 1.0 + (s + 1.0) * y * y * y + s * y * y


static func _in_out_sine(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * x)


## Lays the poster out as it is at time t of the run.
func _apply(t: float) -> void:
	if _pr.size.x <= 0.0:
		return
	(_marks as CropMarks).k = _out_cubic(_seg(t, T_MARKS.x, T_MARKS.y))
	_marks.queue_redraw()
	# The sheet feeds in from above and settles into the marks.
	var f := _seg(t, T_FEED.x, T_FEED.y)
	var off := Vector2(0, -(_pr.end.y + 60.0) * (1.0 - _out_cubic(f)))
	var rot := -0.05 * (1.0 - _out_cubic(_seg(t, T_FEED.x + 0.1, T_FEED.y + 0.08)))
	# The press: a short dip as it comes down.
	var p := t - T_PRESS
	var dip := 0.0
	if p > 0.0:
		dip = _seg(p, 0.0, 0.08) if p < 0.08 else 1.0 - _out_cubic(_seg(p, 0.08, 0.36))
	_set_sheet(off, rot, 1.0 - 0.014 * dip)
	# The key plate under its roller, then the signal plate under its own.
	# (A plate with nothing printed yet is hidden: a clip on a turned control clips to its bounding
	# box, so an empty one on the tilted sheet would still show a sliver.)
	var ky := _roll(t, T_KEY, _roller_k, off)
	var sy := _roll(t, T_SIG, _roller_s, off)
	for e: Array in [[_key_a, ky], [_key_b, ky], [_sig_a, sy], [_sig_b, sy]]:
		var plate := e[0] as Control
		plate.size.y = float(e[1])
		plate.visible = float(e[1]) > 0.5
	var mis := MISREG * (1.0 - _out_back(_seg(t, T_REG.x, T_REG.y), 2.2))
	_sig_a_in.position = mis
	_sig_b_in.position = mis
	# Debossed: the cut deepens as the press lands.
	var d := DEPTH * _out_cubic(_seg(p, 0.04, 0.3))
	for g: Node in [_type_group, _amp_group]:
		var m := (g as CanvasItem).material as ShaderMaterial if g is CanvasItem else null
		if m:
			m.set_shader_parameter("depth", d)
			m.set_shader_parameter("floor_shade", 0.06 * d / DEPTH)
	# The proof stamp thumps on.
	var s := _seg(t, T_STAMP, T_STAMP + 0.2)
	_stamp.visible = s > 0.0
	_stamp.modulate.a = minf(1.0, s * 3.0)
	_stamp.scale = Vector2.ONE * lerpf(1.7, 1.0, _out_cubic(s))


## A roller running down the sheet over [a, b]: places it, returns how far down the plate is printed.
func _roll(t: float, span: Vector2, roller: Roller, off: Vector2) -> float:
	var ps := _pr.size
	var k := _in_out_sine(_seg(t, span.x, span.y))
	var y := lerpf(-ROLLER_H * 0.5, ps.y + ROLLER_H, k)
	roller.visible = t > span.x - 0.02 and t < span.y + 0.02
	roller.position = _pr.position + off + Vector2(-14.0, y - ROLLER_H * 0.5)
	roller.modulate.a = minf(1.0, minf(_seg(t, span.x - 0.02, span.x + 0.08), 1.0 - _seg(t, span.y - 0.08, span.y + 0.02)) * 1.0)
	return clampf(y, 0.0, ps.y)


func _set_sheet(off: Vector2, rot: float, k: float) -> void:
	for n: Control in [_holder, _poster]:
		n.position = _pr.position + off
		n.rotation = rot
		n.scale = Vector2(k, k)


func _set_stage(t: float) -> void:
	var st := ""
	for e: Array in STAGES:
		if t < float(e[0]):
			st = str(e[1])
			break
	if not _motion:
		st = "PROOF OK" if _finishing and _shown >= 0.999 else "PRINTING"
	elif t >= RUN and not (_finishing and _shown >= 0.999) and not _frozen:
		st = "DRYING"
	if st != _last_stage:
		_last_stage = st
		_stage.text = "·  " + st


func _process(delta: float) -> void:
	if _exiting:
		_exit_t += delta
		_lift(_exit_t)
		return
	if not _frozen:
		_t += delta
	var target := _progress
	if _motion:
		target = minf(target, clampf(_t / RUN, 0.0, 1.0))
	if _frozen:
		_shown = clampf(_t / RUN, 0.0, 1.0)
	else:
		# Follows the target at up to 1.6 a second: it tracks the run's pace exactly and eases over a
		# jump in the real work.
		_shown = move_toward(_shown, target, delta * 1.6)
	_rule.call("set_filled", _shown)
	_pct.text = "LOADING  %d%%" % int(roundf(_shown * 100.0))
	_count.text = "SHEET %04d / %d" % [int(roundf(_shown * COUNT_TO)), COUNT_TO]
	if _motion and not _frozen:
		_apply(_t)
	_set_stage(_anim_t())
	if _led and is_instance_valid(_led):
		_led.queue_redraw()
	# A new tip every 2.6 s.
	if not _frozen and int(_t / 2.6) != int((_t - delta) / 2.6):
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := _tip.create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: _tip.text = "TIP  —  " + TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
	if _finishing and not _frozen and _shown >= 0.999 and _t >= (RUN if _motion else 0.8):
		_start_exit()


## The sheet comes off the press: the Lobby is told to play its intro, the sheet lifts up and away
## while the matte and the foot fade (reduce motion: a plain fade).
func _start_exit() -> void:
	_exiting = true
	_exit_t = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_stage.text = "·  PROOF OK"
	if _done.is_valid():
		_done.call()


func _lift(e: float) -> void:
	var k := _seg(e, 0.0, EXIT if _motion else 0.3)
	if _motion:
		var up := k * k * k
		_set_sheet(Vector2(0, -(_pr.end.y + 80.0) * up), 0.035 * up, 1.0)
		# The foot goes first (its type never sits over the Lobby's), then the matte.
		_foot.modulate.a = 1.0 - smoothstep(0.0, 0.35, k)
		var fade := 1.0 - smoothstep(0.2, 0.9, k)
		for n: CanvasItem in [_matte, _marks, _grain]:
			n.modulate.a = fade
	else:
		modulate.a = 1.0 - k
	if k >= 1.0:
		set_process(false)
		queue_free()


## Crop marks on the matte at the sheet's corners (they draw on as the press makes ready).
class CropMarks:
	extends Control
	var rect := Rect2()
	var k := 0.0
	const GAP := 4.0
	const LEN := 11.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if k <= 0.0 or rect.size.x <= 0.0:
			return
		var c := Color(0.063, 0.067, 0.075, 0.7)
		var l := LEN * k
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var sx := -1.0 if corner.x <= rect.position.x else 1.0
			var sy := -1.0 if corner.y <= rect.position.y else 1.0
			draw_line(corner + Vector2(sx * GAP, 0), corner + Vector2(sx * (GAP + l), 0), c, 1.0)
			draw_line(corner + Vector2(0, sy * GAP), corner + Vector2(0, sy * (GAP + l)), c, 1.0)


## A printer's register target: a ring with a cross through it.
class Target:
	extends Control
	var color := Color.BLACK

	func _init(at: Vector2 = Vector2.ZERO, c: Color = Color.BLACK) -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		color = c
		size = Vector2(28, 28)
		position = at - size * 0.5

	func _draw() -> void:
		var m := size * 0.5
		draw_arc(m, 7.5, 0.0, TAU, 32, color, 1.2, true)
		draw_line(Vector2(0, m.y), Vector2(size.x, m.y), color, 1.0)
		draw_line(Vector2(m.x, 0), Vector2(m.x, size.y), color, 1.0)


## An inking roller seen from above: a rubber cylinder (black ink, or signal red) on steel axle stubs,
## casting a soft shadow down the sheet. Drawn in code: vertical bands of shade, a highlight line.
class Roller:
	extends Control
	var signal_ink := false
	var ink := Color("ff4b1f")

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		var w := size.x
		var h := ROLLER_H
		var x0 := 12.0
		var x1 := w - 12.0
		# Its shadow on the sheet, below it (the light comes from the top left).
		_band(x0 + 6.0, x1 - 2.0, h - 2.0, h + 16.0, Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.0))
		# The cylinder: a dark top edge, the key light's highlight, the body falling into shade, a
		# little light bounced back off the paper at the bottom.
		var stops: Array[float] = [0.0, 0.13, 0.26, 0.56, 0.86, 1.0]
		var cols: Array[Color]
		if signal_ink:
			cols = [ink.darkened(0.3), ink.lightened(0.48), ink.lightened(0.14), ink, ink.darkened(0.24), ink.darkened(0.1)]
		else:
			cols = [Color("1b1c1f"), Color("6a6c72"), Color("2e2f33"), Color("141517"), Color("070708"), Color("2a2b2f")]
		for i in stops.size() - 1:
			_band(x0, x1, stops[i] * h, stops[i + 1] * h, cols[i], cols[i + 1])
		# The wet sheen on the highlight and a hairline where it meets the paper.
		draw_rect(Rect2(x0, h * 0.12, x1 - x0, 1.5), Color(1, 1, 1, 0.42 if signal_ink else 0.34))
		draw_rect(Rect2(x0, h - 1.0, x1 - x0, 1.0), Color(0, 0, 0, 0.5))
		# Steel axle stubs.
		for ax: float in [0.0, x1]:
			_band(ax, ax + 12.0, h * 0.3, h * 0.5, Color("e4e5e8"), Color("a9abb0"))
			_band(ax, ax + 12.0, h * 0.5, h * 0.7, Color("a9abb0"), Color("6d6f74"))

	func _band(x0: float, x1: float, y0: float, y1: float, c0: Color, c1: Color) -> void:
		draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
			PackedColorArray([c0, c0, c1, c1]))
