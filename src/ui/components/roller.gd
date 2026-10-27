extends Control
## A mechanical counter's roll over a label (the hero page's level up): the label hides while its old
## text rolls to the new one, each changed digit turning up on its drum, right to left, with a clack,
## the way an odometer turns over; then the label shows again. The layout never moves: the roll is
## drawn over the label in its own font, size and colour.
##   Roller.roll(label, "LV 46 / 120", "LV 47 / 120")

const DIGIT_TIME := 0.24
const STAGGER := 0.06

var from_text := ""
var to_text := ""
var font: Font
var font_size := 16
var color := Color.BLACK
var align := HORIZONTAL_ALIGNMENT_LEFT
var _label: Label
var _t := 0.0
var _changed: Array[int] = []
var _clacked := {}
var _quiet := false


## Rolls `label` from `from_text` to its text `to_text`. quiet: no clacks (a fast hold). delay: it
## holds the old text that long first (the label is covered from the start).
static func roll(label: Label, from_t: String, to_t: String, quiet: bool = false, delay: float = 0.0) -> void:
	if label == null or not is_instance_valid(label) or from_t == to_t or not label.is_visible_in_tree():
		return
	if not Kit.motion_ok():
		return
	for c in label.get_children():
		if c.has_meta("roller"):
			c.free()
	var r: Control = load("res://src/ui/components/roller.gd").new()
	r.set_meta("roller", true)
	r.call("_setup", label, from_t, to_t, quiet)
	r.set("_t", -maxf(delay, 0.0))
	label.add_child(r)


func _setup(label: Label, from_t: String, to_t: String, quiet: bool) -> void:
	_label = label
	_quiet = quiet
	mouse_filter = MOUSE_FILTER_IGNORE
	font = label.get_theme_font("font")
	font_size = label.get_theme_font_size("font_size")
	color = label.get_theme_color("font_color")
	align = label.horizontal_alignment
	# Same length (padded on the left), so the drums line up from the right like a counter's.
	var n := maxi(from_t.length(), to_t.length())
	from_text = from_t.lpad(n)
	to_text = to_t.lpad(n)
	for i in range(n - 1, -1, -1):
		if from_text[i] != to_text[i]:
			_changed.append(i)
	size = label.size
	label.self_modulate.a = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	for j in _changed.size():
		if not _clacked.has(j) and _t >= j * STAGGER + DIGIT_TIME * 0.55:
			_clacked[j] = true
			if not _quiet:
				UI.sfx("clack", 0.9 + 0.08 * float(j % 3))
	if _t >= (_changed.size() - 1) * STAGGER + DIGIT_TIME + 0.02:
		if _label and is_instance_valid(_label):
			_label.self_modulate.a = 1.0
		queue_free()


func _draw() -> void:
	if font == null:
		return
	var w := font.get_string_size(to_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x0 := 0.0
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 = size.x - w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x0 = (size.x - w) * 0.5
	var h := font.get_height(font_size)
	var base := (size.y - h) * 0.5 + font.get_ascent(font_size)
	for i in to_text.length():
		var x := x0 + font.get_string_size(to_text.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var j := _changed.find(i)
		if j < 0:
			draw_string(font, Vector2(x, base), to_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			continue
		var p := clampf((_t - j * STAGGER) / DIGIT_TIME, 0.0, 1.0)
		# The drum turns up with a little overshoot; the digits fade where the drum curves away.
		var u := 1.0 + 2.2 * pow(p - 1.0, 3.0) + 1.2 * pow(p - 1.0, 2.0)
		var y_old := -u * h * 0.9
		var y_new := (1.0 - u) * h * 0.9
		draw_string(font, Vector2(x, base + y_old), from_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(color, color.a * clampf(1.0 - absf(y_old) / (h * 0.9), 0.0, 1.0)))
		draw_string(font, Vector2(x, base + y_new), to_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color(color, color.a * clampf(1.0 - absf(y_new) / (h * 0.9), 0.0, 1.0)))
