extends Button
## Battle bottom-rail card for one ally (style v2): a Kit hero card with an HP bar and a cyan
## energy bar under it. A full energy bar gives the card a cyan glow ring and a pulsing "ULT"
## tag ("READY" once the tap queued the ultimate). A fallen hero turns grey with a dark veil.
## The battle screen calls set_hp / set_energy / set_dead / mark_queued and reads energy,
## dead, queued; manual = manual-ultimate mode.

const BAR_GAP := 6.0
const HP_H := 10.0
const EN_H := 7.0

var uid := ""
var hero_id := ""
var max_hp := 1
var hp := 1
var energy := 0
var dead := false
var manual := false
var queued := false
var _card: Control
var _over: Control
var _t := 0.0
var _flash := 0.0
var _font: Font
var _w := 120.0


func setup(u: Dictionary, w: float) -> void:
	uid = str(u.uid)
	hero_id = str(u.hero_id)
	max_hp = maxi(1, int(u.max_hp))
	hp = int(u.hp)
	energy = int(u.get("energy", 0))
	_w = w
	theme_type_variation = &"BareButton"
	focus_mode = FOCUS_NONE
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(w, w + BAR_GAP + HP_H + 4.0 + EN_H + 6.0)
	_font = Kit.font("cond_black")
	var opts := {"size": w, "owned": true, "show_faction": true}
	if u.has("level"):
		opts["level"] = int(u.level)
	if u.has("stars"):
		opts["stars"] = int(u.stars)
	_card = Kit.hero_card(hero_id, opts)
	_card.mouse_filter = MOUSE_FILTER_IGNORE
	_card.position = Vector2.ZERO
	_card.size = Vector2(w, w)
	add_child(_card)
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
		Kit.pulse(self, 1.08)
	queue_redraw()
	_over.queue_redraw()


func set_dead() -> void:
	dead = true
	hp = 0
	energy = 0
	queued = false
	_card.material = Kit.grayscale_material()
	for c in _card.find_children("*", "CanvasItem", true, false):
		(c as CanvasItem).use_parent_material = true
	queue_redraw()
	_over.queue_redraw()


## Visual feedback for a tap that queued the ultimate.
func mark_queued() -> void:
	queued = true
	_flash = 1.0
	Kit.pulse(self, 1.1)
	_over.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
	if (energy >= 1000 and not dead) or _flash > 0.0:
		queue_redraw()
		_over.queue_redraw()


## Behind the card: the ready glow. Under it: HP and energy bars.
func _draw() -> void:
	var ready := energy >= 1000 and not dead
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var cr := Rect2(Vector2.ZERO, Vector2(_w, _w))
	if ready:
		for i in 4:
			var g := 4.0 + i * 4.0
			draw_rect(cr.grow(g), Color(Kit.ACCENT_HI, (0.16 - i * 0.035) * (0.6 + 0.4 * pulse)), true)
	var y := _w + BAR_GAP
	var hr := Rect2(2, y, _w - 4, HP_H)
	draw_rect(hr.grow(2.0), Color(0.03, 0.035, 0.04, 0.92))
	draw_rect(hr, Color(0.17, 0.18, 0.2))
	var hf := float(hp) / float(max_hp)
	draw_rect(Rect2(hr.position, Vector2(hr.size.x * hf, hr.size.y)), Kit.GOOD if hf >= 0.3 else Kit.ORANGE)
	draw_rect(Rect2(hr.position, Vector2(hr.size.x * hf, 2.0)), Color(1, 1, 1, 0.4))
	var er := Rect2(2, y + HP_H + 4.0, _w - 4, EN_H)
	draw_rect(er.grow(2.0), Color(0.03, 0.035, 0.04, 0.92))
	var ef := float(energy) / 1000.0 if not dead else 0.0
	var ec := Kit.ACCENT if ef < 1.0 else Kit.ACCENT_HI.lerp(Color.WHITE, 0.5 * pulse)
	draw_rect(Rect2(er.position, Vector2(er.size.x * ef, er.size.y)), ec)


## Over the card: the ready ring and ULT / READY tag, or the fallen veil.
func _draw_over() -> void:
	var cr := Rect2(Vector2.ZERO, Vector2(_w, _w))
	if dead:
		_over.draw_rect(cr, Color(0.02, 0.02, 0.03, 0.5))
		_tag(Vector2(_w * 0.5, _w * 0.5), "DOWN", Color(0.12, 0.13, 0.15, 0.95), Color(1, 1, 1, 0.7))
		return
	var ready := energy >= 1000
	if ready:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		_over.draw_rect(cr.grow(1.0), Color(Kit.ACCENT_HI, 0.75 + 0.25 * pulse), false, 3.0)
		if queued:
			_tag(Vector2(_w * 0.5, 4.0), "READY", Color.WHITE, Kit.ACCENT_DEEP)
		else:
			var bg := Kit.ACCENT.lerp(Kit.ACCENT_HI, pulse * 0.6)
			_tag(Vector2(_w * 0.5, 4.0), "ULT" if not manual else "TAP ULT", bg, Color.WHITE)
	if _flash > 0.0:
		_over.draw_rect(cr.grow(4.0 + (1.0 - _flash) * 10.0), Color(1, 1, 1, _flash * 0.8), false, 3.0)


func _tag(at: Vector2, text: String, bg: Color, fg: Color) -> void:
	var fs := 19
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(at.x - tw * 0.5 - 10, at.y - 13, tw + 20, 26)
	_over.draw_rect(rect.grow(1.5), Color(0, 0, 0, 0.5))
	_over.draw_rect(rect, bg)
	_over.draw_string(_font, Vector2(rect.position.x + 10, rect.position.y + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
