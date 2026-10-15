extends Button
## Campaign map medallion for one stage. status: "cleared" | "current" | "locked".
## Cleared: gold ring, faction-tinted face, check badge. Current: bright pulsing ring and a
## bobbing "NEXT" marker. Locked: dim with a lock. Bosses are bigger, ember-ringed, with a
## crown. Built with setup(); tap handling is the screen's (Kit press animation included).

var stage_id := ""
var status := "locked"
var is_boss := false
var tint := Color("f2c14e")
var _t := 0.0
var _font: Font
var _check: Texture2D
var _lock: Texture2D
var _crown: Texture2D


func setup(id: String, st: String, boss: bool, faction_tint: Color, diameter: float) -> void:
	stage_id = id
	status = st
	is_boss = boss
	tint = faction_tint
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(diameter, diameter)
	size = custom_minimum_size
	_font = Kit.font("black")
	_check = Kit.icon_texture("check")
	_lock = Kit.icon_texture("lock")
	_crown = Kit.icon_texture("crown")
	Kit.add_press_fx(self)
	set_process(status == "current")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var locked := status == "locked"
	var current := status == "current"
	var ring := Kit.GOLD
	if is_boss:
		ring = Color("ff7a52") if not locked else Color("7a4a52")
	elif locked:
		ring = Color("5a5078")
	var pulse := 0.5 + 0.5 * sin(_t * 3.4)
	# Glow behind the current stage.
	if current:
		for i in 6:
			var t := i / 6.0
			draw_circle(c, r * (1.55 - t * 0.5), Color(Kit.GOLD_LIGHT, (0.05 + 0.04 * pulse)), true, -1.0, true)
	# Drop shadow.
	draw_circle(c + Vector2(0, 5), r + 3, Color(0, 0, 0, 0.45), true, -1.0, true)
	# Rim.
	draw_circle(c, r + 2, ring.darkened(0.55), true, -1.0, true)
	draw_circle(c, r, ring if not current else ring.lerp(Color.WHITE, 0.25 * pulse), true, -1.0, true)
	# Face.
	var face_top := tint.darkened(0.25) if not locked else Color("2a2448")
	var face_bot := tint.darkened(0.72) if not locked else Color("13102a")
	var fr := r * 0.8
	var steps := 10
	for i in steps:
		var t := i / float(steps - 1)
		draw_circle(c + Vector2(0, -fr * 0.15 * (1.0 - t)), fr * (1.0 - t * 0.55), face_bot.lerp(face_top, t), true, -1.0, true)
	draw_arc(c, fr, 0, TAU, 48, Color(1, 1, 1, 0.18 if not locked else 0.06), 2.0, true)
	# Gloss.
	draw_arc(c, fr * 0.78, deg_to_rad(200), deg_to_rad(330), 24, Color(1, 1, 1, 0.16 if not locked else 0.05), fr * 0.12, true)
	# Label or lock.
	if locked:
		if _lock:
			var ls := r * 0.9
			draw_texture_rect(_lock, Rect2(c - Vector2(ls, ls) * 0.5, Vector2(ls, ls)), false, Color(1, 1, 1, 0.55))
	else:
		var fs := int(r * (0.5 if stage_id.length() <= 3 else 0.42))
		var tw := _font.get_string_size(stage_id, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := c + Vector2(-tw * 0.5, fs * 0.36)
		draw_string_outline(_font, base, stage_id, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Kit.OUTLINE)
		draw_string(_font, base, stage_id, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.INK)
	# Crown for bosses.
	if is_boss and _crown:
		var cs := r * 0.85
		draw_texture_rect(_crown, Rect2(c + Vector2(-cs * 0.5, -r - cs * 0.62), Vector2(cs, cs)), false, Color(1, 1, 1, 1.0 if not locked else 0.5))
	# Cleared badge.
	if status == "cleared" and _check:
		var bs := r * 0.62
		var bc := c + Vector2(r * 0.68, r * 0.62)
		draw_circle(bc, bs * 0.55, Kit.OUTLINE, true, -1.0, true)
		draw_circle(bc, bs * 0.47, Color("2e9e6e"), true, -1.0, true)
		draw_texture_rect(_check, Rect2(bc - Vector2(bs, bs) * 0.36, Vector2(bs, bs) * 0.72), false)
