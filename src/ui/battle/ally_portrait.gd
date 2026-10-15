extends Button
## Battle bottom-bar portrait for one ally: round face, energy ring that fills and glows
## when the ultimate is ready, HP bar, and a "TAP" hint in manual mode. Greyed out with a
## cross when the hero falls. The battle screen calls set_hp / set_energy / set_dead.

const RING_W := 8.0
const MASK_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tc.a *= smoothstep(0.5, 0.47, d);\n\tCOLOR = c;\n}\n"
const GRAY_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tvec4 c = texture(TEXTURE, UV) * COLOR;\n\tfloat g = dot(c.rgb, vec3(0.3, 0.59, 0.11)) * 0.55;\n\tc.rgb = vec3(g);\n\tc.a *= smoothstep(0.5, 0.47, d);\n\tCOLOR = c;\n}\n"

static var _mask_mat: ShaderMaterial
static var _gray_mat: ShaderMaterial

var uid := ""
var hero_id := ""
var max_hp := 1
var hp := 1
var energy := 0
var dead := false
var manual := false
var queued := false
var _face: Control
var _over: Control
var _t := 0.0
var _flash := 0.0
var _font: Font
var _rarity_col := Color.WHITE


func setup(u: Dictionary, w: float) -> void:
	uid = str(u.uid)
	hero_id = str(u.hero_id)
	max_hp = maxi(1, int(u.max_hp))
	hp = int(u.hp)
	energy = int(u.get("energy", 0))
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(w, w + 34.0)
	_font = Kit.font("black")
	_rarity_col = Kit.rarity_color(str(Game.hero_def(hero_id).get("rarity", "rare")))
	var d := w - 28.0
	_face = HeroArt.make_portrait(hero_id, d)
	_face.mouse_filter = MOUSE_FILTER_IGNORE
	_face.position = Vector2(14, 10)
	_face.size = Vector2(d, d)
	if _mask_mat == null:
		var sh := Shader.new()
		sh.code = MASK_SHADER
		_mask_mat = ShaderMaterial.new()
		_mask_mat.shader = sh
		var sh2 := Shader.new()
		sh2.code = GRAY_SHADER
		_gray_mat = ShaderMaterial.new()
		_gray_mat.shader = sh2
	_face.material = _mask_mat
	add_child(_face)
	_over = Control.new()
	_over.mouse_filter = MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_over.draw.connect(_draw_over)
	add_child(_over)
	Kit.add_press_fx(self)


func set_hp(v: int) -> void:
	hp = clampi(v, 0, max_hp)
	queue_redraw()


func set_energy(v: int) -> void:
	var was_full := energy >= 1000
	energy = clampi(v, 0, 1000)
	if energy < 1000:
		queued = false
	if energy >= 1000 and not was_full:
		_flash = 1.0
		Kit.pulse(self, 1.1)
	queue_redraw()


func set_dead() -> void:
	dead = true
	hp = 0
	energy = 0
	queued = false
	_face.material = _gray_mat
	queue_redraw()


## Visual feedback for a tap that queued the ultimate.
func mark_queued() -> void:
	queued = true
	_flash = 1.0
	Kit.pulse(self, 1.12)


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
	if energy >= 1000 or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var d := w - 28.0
	var c := Vector2(w * 0.5, 10.0 + d * 0.5)
	var r := d * 0.5
	var ready := energy >= 1000 and not dead
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	# Glow behind a ready portrait.
	if ready:
		for i in 5:
			draw_circle(c, r + 18.0 - i * 3.0, Color(1.0, 0.85, 0.4, 0.06 + 0.05 * pulse), true, -1.0, true)
	# Back disc and rarity rim.
	draw_circle(c, r + 2.0, Color(0.05, 0.03, 0.1, 0.95), true, -1.0, true)
	draw_circle(c, r, _rarity_col.darkened(0.6) if not dead else Color(0.15, 0.13, 0.2), true, -1.0, true)
	# Energy ring.
	var ring_r := r + 6.0
	draw_arc(c, ring_r, 0, TAU, 64, Color(0.05, 0.03, 0.1, 0.95), RING_W + 4.0, true)
	draw_arc(c, ring_r, 0, TAU, 64, Color(0.25, 0.22, 0.38), RING_W, true)
	if not dead and energy > 0:
		var ef := float(energy) / 1000.0
		var col := Color("6fc3e8") if not ready else Color("ffd45e").lerp(Color.WHITE, 0.35 * pulse)
		draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * ef, 64, col, RING_W, true)
		if ready:
			var a := _t * 3.0
			draw_circle(c + Vector2(cos(a), sin(a)) * ring_r, 5.0, Color(1, 1, 1, 0.95), true, -1.0, true)
	if _flash > 0.0:
		draw_arc(c, ring_r + 4.0 + (1.0 - _flash) * 14.0, 0, TAU, 64, Color(1, 0.95, 0.7, _flash), 4.0, true)
	# HP bar.
	var by := 10.0 + d + 14.0
	var br := Rect2(10, by, w - 20, 12)
	draw_rect(br.grow(2.0), Color(0.03, 0.02, 0.07, 0.95))
	draw_rect(br, Color(0.16, 0.12, 0.24))
	var hf := float(hp) / float(max_hp)
	var hc := Color("4fd68f") if hf >= 0.3 else Color("f2a23a")
	draw_rect(Rect2(br.position, Vector2(br.size.x * hf, br.size.y)), hc)
	draw_rect(Rect2(br.position, Vector2(br.size.x * hf, br.size.y * 0.4)), Color(1, 1, 1, 0.22))
	_over.queue_redraw()


## Drawn above the face: the fallen cross and the TAP / READY badge.
func _draw_over() -> void:
	var w := size.x
	var d := w - 28.0
	var c := Vector2(w * 0.5, 10.0 + d * 0.5)
	var r := d * 0.5
	var ready := energy >= 1000 and not dead
	if dead:
		var k := r * 0.55
		_over.draw_line(c - Vector2(k, k), c + Vector2(k, k), Color(0.9, 0.25, 0.2, 0.9), 7.0, true)
		_over.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Color(0.9, 0.25, 0.2, 0.9), 7.0, true)
	elif ready and manual and not queued:
		_badge(Vector2(c.x, c.y + r - 2.0), "TAP", Color("ffd45e"), Color("3d2306"))
	elif ready and queued:
		_badge(Vector2(c.x, c.y + r - 2.0), "READY", Color.WHITE, Color("3d2306"))


func _badge(at: Vector2, text: String, bg: Color, fg: Color) -> void:
	var fs := 18
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(at.x - tw * 0.5 - 10, at.y - 12, tw + 20, 24)
	_over.draw_rect(rect.grow(2.0), Color(0.05, 0.02, 0.1, 0.9))
	_over.draw_rect(rect, bg)
	_over.draw_string(_font, Vector2(rect.position.x + 10, rect.position.y + 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
