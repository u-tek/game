extends Control
## Boot / loading screen (main.gd shows it while the first screen builds): deep ocean glass
## with slow rising Aero bubbles, the HALO & HORN wordmark under a chrome halo that a light
## runs around, a glossy progress bar with a moving shimmer, and a rotating tip line. It
## fades in from the engine's splash colour, so there is no flash at launch.
##   var boot := BootScreen.new(); add_child(boot)
##   boot.set_progress(0.5)              # eased, never goes backwards
##   boot.finish(func() -> void: ...)    # fills to 100 %, fades out, frees itself

const KitBox := preload("res://src/ui/components/kit_box.gd")

const SPLASH := Color(0.07, 0.055, 0.14, 1)
const TOP := Color("10284a")
const BOT := Color("050b18")
const TIPS: Array[String] = [
	"The Sanctum keeps filling while you're away. Collect it from the Lobby.",
	"Your first summon every day is free.",
	"Quick Claim collects hours of Sanctum rewards at once.",
	"Five heroes fight together. Fill every slot in your Team.",
	"Turn off auto ultimates in Settings to time each one yourself.",
	"The Spire is an endless tower beside the campaign.",
]
const BAR_W := 440.0
const BAR_H := 14.0

var _t := 0.0
var _progress := 0.0
var _shown := 0.0
var _tip_i := 0
var _tip: Label
var _title: Control
var _sigil: Control
var _cover: ColorRect
var _bar: Control
var _bubbles: Array[Vector4] = [] # x (0..1), phase, speed, radius
var _finishing := false
var _bottom := 0.0
var _glow_tex: Texture2D

static var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "BootScreen"
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rng.randomize()
	for i in 16:
		_bubbles.append(Vector4(_rng.randf(), _rng.randf(), _rng.randf_range(0.025, 0.06), _rng.randf_range(6.0, 26.0)))
	var ui := Kit.autoload("UI")
	_bottom = float(ui.call("safe_bottom")) if ui else 0.0
	var g := Kit.glow(Kit.ACCENT, 8.0)
	_glow_tex = g.texture
	g.free()

	_sigil = Control.new()
	_sigil.name = "Sigil"
	_sigil.mouse_filter = MOUSE_FILTER_IGNORE
	_sigil.draw.connect(_draw_sigil)
	add_child(_sigil)

	_title = Control.new()
	_title.name = "Title"
	_title.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_title)
	var word := Kit.hbox(14)
	word.alignment = BoxContainer.ALIGNMENT_CENTER
	word.mouse_filter = MOUSE_FILTER_IGNORE
	for part: Array in [["HALO", Color.WHITE], ["&", Kit.ACCENT_HI], ["HORN", Color.WHITE]]:
		var l := Kit.title(str(part[0]), 92, part[1])
		l.add_theme_color_override("font_shadow_color", Color(0.02, 0.35, 0.6, 0.55))
		l.add_theme_constant_override("shadow_outline_size", 14)
		l.add_theme_constant_override("shadow_offset_y", 0)
		word.add_child(l)
	word.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_title.add_child(word)
	var sub := Kit.label("ANGELS  ·  DEMONS  ·  THE FALLEN", 24, Color(0.75, 0.9, 1.0, 0.75), "cond_bold")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	sub.offset_top = 112
	sub.offset_bottom = 142
	_title.add_child(sub)

	_bar = Control.new()
	_bar.name = "Bar"
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)

	_tip = Kit.label("", 22, Color(0.82, 0.9, 1.0, 0.82), "bold")
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A real width up front: an autowrap label measured at zero width keeps a huge height.
	_tip.custom_minimum_size.x = 520
	add_child(_tip)
	_tip_i = _rng.randi() % TIPS.size()
	_tip.text = "TIP  " + TIPS[_tip_i]

	_cover = ColorRect.new()
	_cover.color = SPLASH
	_cover.mouse_filter = MOUSE_FILTER_IGNORE
	_cover.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_cover)
	var tw := _cover.create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# The wordmark rises in.
	_title.modulate.a = 0.0
	var tw2 := _title.create_tween().set_parallel(true)
	tw2.tween_property(_title, "modulate:a", 1.0, 0.6).set_delay(0.12)
	tw2.tween_method(func(v: float) -> void: _title.set_meta("rise", v), 26.0, 0.0, 0.8).set_delay(0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	resized.connect(_layout)
	_layout()


## Target progress 0..1 (the bar eases toward it and never moves backwards).
func set_progress(p: float) -> void:
	_progress = maxf(_progress, clampf(p, 0.0, 1.0))


## Fills the bar, fades the screen out with a slight zoom of the wordmark, frees itself,
## then calls `done`.
func finish(done: Callable = Callable()) -> void:
	if _finishing:
		return
	_finishing = true
	_progress = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_callback(func() -> void:
		if done.is_valid():
			done.call())
	tw.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_title, "scale", Vector2(1.06, 1.06), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cy := h * 0.42
	_sigil.position = Vector2(w * 0.5 - 200.0, cy - 250.0)
	_sigil.size = Vector2(400, 260)
	_title.position = Vector2(0, cy - 40.0)
	_title.size = Vector2(w, 150)
	_title.pivot_offset = Vector2(w * 0.5, 60)
	var by := h - _bottom - 150.0
	_bar.position = Vector2((w - BAR_W) * 0.5, by)
	_bar.size = Vector2(BAR_W, 60)
	_tip.size = Vector2(w - 96.0, 0)
	_tip.position = Vector2(48, by - 86.0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_shown = minf(_progress, _shown + (_progress - _shown) * minf(1.0, delta * 6.0) + delta * 0.04)
	var rise: float = _title.get_meta("rise", 0.0)
	_title.position.y = size.y * 0.42 - 40.0 + rise
	# A new tip every 2.6 s.
	if int(_t / 2.6) != int((_t - delta) / 2.6) and not _finishing:
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := _tip.create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func() -> void: _tip.text = "TIP  " + TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
	queue_redraw()
	_sigil.queue_redraw()
	_bar.queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([TOP, TOP, BOT, BOT]))
	# Soft aqua light behind the wordmark, breathing.
	var gr := w * (0.62 + 0.03 * sin(_t * 1.6))
	var gc := Vector2(w * 0.5, h * 0.4)
	if _glow_tex:
		draw_texture_rect(_glow_tex, Rect2(gc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1, 1, 1, 0.42))
	# Aero bubbles drifting up.
	for b in _bubbles:
		var k := fmod(b.y + _t * b.z, 1.0)
		var p := Vector2(b.x * w + sin(_t * 0.8 + b.y * 9.0) * 14.0, h * (1.05 - k * 1.15))
		var a := sin(PI * k) * 0.5
		draw_circle(p, b.w, Color(0.6, 0.9, 1.0, 0.07 * a), true, -1.0, true)
		draw_arc(p, b.w, 0.0, TAU, 24, Color(0.75, 0.95, 1.0, 0.35 * a), 1.5, true)
		draw_arc(p, b.w * 0.62, PI * 1.1, PI * 1.45, 6, Color(1, 1, 1, 0.6 * a), maxf(1.5, b.w * 0.14), true)


## The chrome halo: a tilted ring with a soft glow and a light running around it.
func _draw_sigil() -> void:
	var c := Vector2(_sigil.size.x * 0.5, _sigil.size.y * 0.62 + sin(_t * 1.8) * 4.0)
	var rx := 128.0
	var ry := 40.0
	var n := 72
	var head := fmod(_t * 0.55, 1.0) * TAU
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var glow := PackedColorArray()
	for i in n + 1:
		var a := TAU * float(i) / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		var d := absf(wrapf(a - head, -PI, PI))
		var lit := pow(maxf(0.0, 1.0 - d / 1.4), 2.0)
		# The near (lower) half of the ring is brighter, like chrome catching the light.
		var near := 0.55 + 0.45 * maxf(0.0, sin(a))
		cols.append(Color(0.78, 0.95, 1.0, 0.55 * near).lerp(Color(1, 1, 1, 1), lit))
		glow.append(Color(0.1, 0.75, 1.0, 0.1 + 0.25 * lit))
	var ci := _sigil.get_canvas_item()
	RenderingServer.canvas_item_add_polyline(ci, pts, glow, 26.0, true)
	RenderingServer.canvas_item_add_polyline(ci, pts, cols, 8.0, true)
	# A star glint where the light is.
	var hp := c + Vector2(cos(head) * rx, sin(head) * ry)
	var s := 16.0 + 4.0 * sin(_t * 9.0)
	var w := s * 0.2
	_sigil.draw_colored_polygon(PackedVector2Array([hp + Vector2(0, -s), hp + Vector2(w, -w), hp + Vector2(s, 0), hp + Vector2(w, w),
		hp + Vector2(0, s), hp + Vector2(-w, w), hp + Vector2(-s, 0), hp + Vector2(-w, -w)]), Color(1, 1, 1, 0.9))


func _draw_bar() -> void:
	var ci := _bar.get_canvas_item()
	var track := Rect2(0, 0, BAR_W, BAR_H)
	var tp := KitBox.shape_points(track, BAR_H * 0.5, 0.0, 0, 0.0, 6)
	KitBox.fill_poly(ci, tp, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.14))
	KitBox.stroke_poly(ci, tp, Color(1, 1, 1, 0.18), 1.0)
	var fw := maxf(BAR_H, BAR_W * _shown)
	var fill := Rect2(0, 0, fw, BAR_H)
	var fp := KitBox.shape_points(fill, BAR_H * 0.5, 0.0, 0, 0.0, 6)
	KitBox.fill_poly(ci, fp, Color("6fe6ff"), Color("0c9be6"))
	# Shimmer: a bright band sliding along the filled part.
	var sx := fmod(_t * 1.1, 1.6) / 1.6 * (fw + 120.0) - 60.0
	var band := PackedVector2Array([Vector2(sx - 30, BAR_H), Vector2(sx - 10, 0), Vector2(sx + 30, 0), Vector2(sx + 10, BAR_H)])
	var bp := KitBox.clip_convex(band, fp)
	if bp.size() >= 3:
		_bar.draw_colored_polygon(bp, Color(1, 1, 1, 0.45))
	var gl := Rect2(fill.position + Vector2(4, 2), Vector2(maxf(fw - 8.0, 1.0), BAR_H * 0.38))
	_bar.draw_rect(gl, Color(1, 1, 1, 0.25))
	var f := Kit.font("cond_bold")
	var txt := "LOADING  %d%%" % int(roundf(_shown * 100.0))
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_bar.draw_string(f, Vector2((BAR_W - tw) * 0.5, BAR_H + 30.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.9, 1.0, 0.7))
