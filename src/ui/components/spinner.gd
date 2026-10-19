extends Control
## Loading spinner (Kit.spinner): a faint glass ring with a bright aqua arc whose tail fades
## out, and a white head bead. The arc is drawn once on an inner wheel that a looping tween
## turns, so spinning costs no redraws (and containers can lay the spinner out freely).

var color := Color("8cf2ff")
## Ring thickness in px (0 = size / 11).
var thickness := 0.0

var _wheel: Control


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_wheel = Control.new()
	_wheel.name = "Wheel"
	_wheel.mouse_filter = MOUSE_FILTER_IGNORE
	_wheel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_wheel.draw.connect(_draw_wheel)
	add_child(_wheel)
	resized.connect(_on_resized)
	_on_resized()
	var tw := _wheel.create_tween().set_loops()
	tw.tween_property(_wheel, "rotation", TAU, 0.85).from(0.0)


func _on_resized() -> void:
	if _wheel:
		_wheel.pivot_offset = size * 0.5
		_wheel.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var th := thickness if thickness > 0.0 else maxf(3.0, minf(size.x, size.y) / 11.0)
	var r := minf(size.x, size.y) * 0.5 - th
	if r <= 1.0:
		return
	draw_arc(c, r, 0.0, TAU, 64, Color(color, 0.16), th, true)


func _draw_wheel() -> void:
	var c := _wheel.size * 0.5
	var th := thickness if thickness > 0.0 else maxf(3.0, minf(size.x, size.y) / 11.0)
	var r := minf(_wheel.size.x, _wheel.size.y) * 0.5 - th
	if r <= 1.0:
		return
	# Tail: 20 short arcs fading in toward the head (at angle 0).
	var span := PI * 1.35
	var n := 20
	for i in n:
		var k0 := float(i) / n
		var k1 := float(i + 1) / n
		var a0 := -span + span * k0
		var a1 := -span + span * k1 + 0.02
		_wheel.draw_arc(c, r, a0, a1, 6, Color(color, 0.05 + 0.95 * k1 * k1), th * (0.55 + 0.45 * k1), true)
	_wheel.draw_circle(c + Vector2(r, 0), th * 0.62, Color(1, 1, 1, 0.95), true, -1.0, true)
