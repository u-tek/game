extends Control
## Slowly rotating light rays with a soft core (reward popups, summon reveals).
## Size it square and center it behind the thing that should shine.

var color := Color("f2c14e")
var ray_count := 14
## Radians per second.
var speed := 0.25
## Ray width as a fraction of its angular slot.
var ray_width := 0.42


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5


func _process(delta: float) -> void:
	rotation += speed * delta


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var slot := TAU / float(ray_count)
	for i in ray_count:
		var a := slot * i
		var len_k := 1.0 if i % 2 == 0 else 0.72
		var hw := slot * ray_width * 0.5
		var p1 := c + Vector2(cos(a - hw), sin(a - hw)) * r * len_k
		var p2 := c + Vector2(cos(a + hw), sin(a + hw)) * r * len_k
		draw_polygon(PackedVector2Array([c, p1, p2]),
			PackedColorArray([Color(color, 0.42), Color(color, 0.0), Color(color, 0.0)]))
	# Soft core made of stacked translucent discs.
	for k in 6:
		var t := float(k) / 6.0
		draw_circle(c, r * (0.42 - t * 0.36), Color(color.lerp(Color.WHITE, t * 0.6), 0.07 + t * 0.05), true, -1.0, true)
