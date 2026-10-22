extends Control
## A rubber stamp for a real day (the calendar, CalendarRules): the day's name around the rim, the
## date big in the middle, inked unevenly (each stroke a little lighter or heavier, a few worn
## flecks), the same every time for the same seed. press() brings it down onto the page.

const MONTHS: Array[String] = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

var rim := "HALLOWEEN  ·  HALO & HORN  ·  "
var big := "31"
var small := "OCT"
var ink := Color(0.74, 0.12, 0.06, 0.95)
var paper := Color("efece4")
var seed_value := 1


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(108, 108)
	size = custom_minimum_size


## Sets the rim word and the date (month 1..12, day of month).
func setup(word: String, month: int, day: int) -> void:
	rim = "%s  ·  HALO & HORN  ·  " % word
	big = "%02d" % day
	small = MONTHS[clampi(month - 1, 0, 11)]
	seed_value = word.hash() & 0xffff
	pivot_offset = size * 0.5
	queue_redraw()


## The stamp comes down: from above and turned, onto the page with a thud (scale, then settle).
func press(rot: float = -0.12) -> void:
	pivot_offset = size * 0.5
	rotation = rot
	if not Kit.motion_ok():
		modulate.a = 1.0
		return
	modulate.a = 0.0
	scale = Vector2(1.6, 1.6)
	rotation = rot - 0.25
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 1.0, 0.1)
	tw.tween_property(self, "rotation", rot, 0.13)
	tw.chain().tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# The rings in short strokes, each inked a little differently.
	for ring: Array in [[r - 3.0, 3.2], [r - 24.0, 1.6]]:
		var n := 60
		for i in n:
			var a0 := TAU * i / n
			var col := Color(ink, ink.a * rng.randf_range(0.68, 1.0))
			draw_arc(c, float(ring[0]), a0, a0 + TAU / n + 0.012, 3, col, float(ring[1]) * rng.randf_range(0.75, 1.2), true)
	# The rim text.
	var f := Kit.font("mono_bold")
	var fs := 10
	for i in rim.length():
		var a := -PI * 0.5 + TAU * i / rim.length()
		var pos := c + Vector2(cos(a), sin(a)) * (r - 13.5)
		draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
		draw_char(f, Vector2(-3.2, 3.6), rim[i], fs, Color(ink, ink.a * rng.randf_range(0.75, 1.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The date.
	var fb := Kit.font("wide_black")
	var bs := int(r * 0.58)
	var w := fb.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
	draw_string(fb, c + Vector2(-w * 0.5, bs * 0.2), big, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Color(ink, ink.a * 0.95))
	var w2 := f.get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(f, c + Vector2(-w2 * 0.5, bs * 0.2 + 15.0), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	# Worn flecks knocked out of the ink.
	for i in 30:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(r * 0.12, r - 1.0)
		draw_circle(c + Vector2(cos(a), sin(a)) * rr, rng.randf_range(0.5, 1.6), Color(paper, 0.6))
