extends Node2D
## One battle unit on the field: the animated HeroSprite plus its overhead bars (HP with a
## trailing damage chip, shield, energy), status icons and stun stars. Feet at the origin.
## The battle screen feeds it display-time values from sim events; it never reads the sim.

const STATUS_ICONS := {
	"stun": "star", "burn": "faction_infernal", "regen": "stat_hp", "taunt": "role_guardian",
	"atk_up": "stat_atk", "atk_down": "stat_atk", "def_up": "stat_def", "def_down": "stat_def",
	"spd_up": "stat_spd",
}
const DEBUFFS := ["stun", "burn", "atk_down", "def_down"]
const BAR_W := 108.0

var uid := ""
var hero_id := ""
var side := "ally"
var slot := 0
var is_boss := false
var faction := ""
var max_hp := 1
var hp := 1
var shield := 0
var energy := 0
var dead := false
var sprite: Node2D
## status -> display ms when it ends
var statuses := {}
var home_facing := 1
var depth_scale := 1.0

var _bars: Node2D
var _chip := 1.0
var _t := 0.0
var _head_h := 260.0
var _faction_tex: Texture2D
var _icon_cache := {}
var _bars_alpha := 1.0


func setup(u: Dictionary, k: float, facing: int, echo: bool) -> void:
	uid = str(u.uid)
	hero_id = str(u.hero_id)
	side = str(u.side)
	slot = int(u.slot)
	is_boss = bool(u.get("is_boss", false))
	max_hp = maxi(1, int(u.max_hp))
	hp = int(u.hp)
	shield = int(u.get("shield", 0))
	energy = int(u.get("energy", 0))
	faction = str(Game.hero_def(hero_id).get("faction", "celestial"))
	_faction_tex = Kit.icon_texture("faction_" + faction)
	depth_scale = k
	home_facing = facing
	sprite = HeroArt.make_sprite(hero_id)
	add_child(sprite)
	sprite.scale = Vector2(k, k)
	sprite.call("set_facing", facing)
	if echo:
		sprite.call("set_echo", true)
	if is_boss:
		sprite.call("set_boss", true)
	_head_h = float(sprite.call("get_height"))
	_bars = Node2D.new()
	_bars.name = "Bars"
	_bars.z_index = 200
	_bars.draw.connect(_draw_bars)
	add_child(_bars)


## Local y of the top of the head (negative).
func head_y() -> float:
	return -_head_h


func chest_global() -> Vector2:
	return to_global(Vector2(0, -_head_h * 0.55))


func head_global() -> Vector2:
	return to_global(Vector2(0, -_head_h * 0.9))


func hand_global() -> Vector2:
	return to_global(Vector2(home_facing * _head_h * 0.18, -_head_h * 0.6))


func set_speed(s: float) -> void:
	var rig: Variant = sprite.get("rig") if sprite else null
	if rig is Node:
		(rig as Node).set("speed_scale", s)


func attack_anim() -> String:
	return str(sprite.call("attack_anim")) if sprite else "attack_melee"


func face_toward(p: Vector2) -> void:
	var dx := p.x - global_position.x
	if absf(dx) > 40.0:
		sprite.call("set_facing", 1 if dx > 0.0 else -1)
	else:
		sprite.call("set_facing", home_facing)


func play_attack(target: Vector2) -> void:
	if dead:
		return
	face_toward(target)
	sprite.call("play_attack", target)


func play_ultimate(target: Vector2) -> void:
	if dead:
		return
	if target != Vector2.INF:
		face_toward(target)
	sprite.call("play_ultimate", target)


func play_hit() -> void:
	if not dead:
		sprite.call("play_hit")


func set_hp(new_hp: int, new_shield: int) -> void:
	hp = clampi(new_hp, 0, max_hp)
	shield = maxi(0, new_shield)
	_bars.queue_redraw()


func set_energy(e: int) -> void:
	energy = clampi(e, 0, 1000)
	_bars.queue_redraw()


func add_status(st: String, until_ms: float) -> void:
	if dead:
		return
	statuses[st] = maxf(float(statuses.get(st, 0.0)), until_ms)
	_bars.queue_redraw()


## Drops statuses that ended by display time `now_ms`.
func tick_statuses(now_ms: float) -> void:
	var changed := false
	for k: String in statuses.keys():
		if float(statuses[k]) <= now_ms:
			statuses.erase(k)
			changed = true
	if changed:
		_bars.queue_redraw()


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0
	shield = 0
	energy = 0
	statuses.clear()
	sprite.call("play_death")
	var tw := create_tween()
	tw.tween_property(self, "_bars_alpha", 0.0, 0.25)
	tw.tween_interval(1.1)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5)


## Instantly shows the final state after a Skip.
func snap_to(u: Dictionary) -> void:
	if not bool(u.get("alive", true)):
		if not dead:
			die()
		return
	set_hp(int(u.hp), int(u.shield))
	set_energy(int(u.energy))
	statuses.clear()


func bars_visible(on: bool) -> void:
	_bars.visible = on


func _process(delta: float) -> void:
	_t += delta
	var frac := float(hp) / float(max_hp)
	if _chip > frac:
		_chip = maxf(frac, _chip - delta * 0.8)
		_bars.queue_redraw()
	elif _chip < frac:
		_chip = frac
	if statuses.has("stun") or energy >= 1000 or (_bars_alpha > 0.0 and _bars_alpha < 1.0):
		_bars.queue_redraw()


func _draw_bars() -> void:
	if _bars_alpha <= 0.01:
		return
	var a := _bars_alpha
	var w := BAR_W * (1.35 if is_boss else 1.0) * clampf(depth_scale, 0.85, 1.05)
	var y := -_head_h - 26.0
	var x0 := -w * 0.5 + 12.0
	# Faction emblem at the left end.
	if _faction_tex:
		_bars.draw_circle(Vector2(x0 - 14, y + 7), 15, Color(0.05, 0.03, 0.1, 0.85 * a), true, -1.0, true)
		_bars.draw_texture_rect(_faction_tex, Rect2(Vector2(x0 - 27, y - 6), Vector2(26, 26)), false, Color(1, 1, 1, a))
	# HP frame.
	var hp_h := 13.0
	var r := Rect2(x0, y, w - 10.0, hp_h)
	_bars.draw_rect(r.grow(2.0), Color(0.03, 0.02, 0.07, 0.9 * a))
	_bars.draw_rect(r, Color(0.16, 0.12, 0.24, a))
	var frac := float(hp) / float(max_hp)
	if _chip > frac:
		_bars.draw_rect(Rect2(r.position + Vector2(r.size.x * frac, 0), Vector2(r.size.x * (_chip - frac), hp_h)), Color(1.0, 0.92, 0.7, 0.9 * a))
	var hc := Color("4fd68f") if side == "ally" else Color("e5483a")
	if frac < 0.3 and side == "ally":
		hc = Color("f2a23a")
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, hp_h)), Color(hc, a))
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, hp_h * 0.4)), Color(1, 1, 1, 0.22 * a))
	# Shield: bright overlay from the left, capped at the bar width.
	if shield > 0:
		var sf := minf(1.0, float(shield) / float(max_hp))
		_bars.draw_rect(Rect2(r.position + Vector2(0, -5), Vector2(r.size.x * sf, 5)), Color(0.75, 0.92, 1.0, 0.95 * a))
	# Energy.
	var er := Rect2(x0, y + hp_h + 4, w - 10.0, 6)
	_bars.draw_rect(er.grow(1.5), Color(0.03, 0.02, 0.07, 0.9 * a))
	var ef := float(energy) / 1000.0
	var ec := Color("6fc3e8") if ef < 1.0 else Color("ffe08a").lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 8.0))
	_bars.draw_rect(Rect2(er.position, Vector2(er.size.x * ef, er.size.y)), Color(ec, a))
	# Status icons above the bar.
	var ix := x0
	for st: String in statuses:
		var tex := _status_tex(st)
		if tex == null:
			continue
		var bad := DEBUFFS.has(st)
		var ip := Vector2(ix, y - 30)
		_bars.draw_circle(ip + Vector2(11, 11), 12, Color(0.35, 0.05, 0.08, 0.85 * a) if bad else Color(0.05, 0.2, 0.15, 0.85 * a), true, -1.0, true)
		_bars.draw_texture_rect(tex, Rect2(ip + Vector2(2, 2), Vector2(18, 18)), false, Color(1, 1, 1, a))
		if st.ends_with("_up") or st.ends_with("_down"):
			var up := st.ends_with("_up")
			var tp := ip + Vector2(19, 18)
			var col := Color("5cd6a0") if up else Color("ff5a4a")
			var pts := PackedVector2Array([tp + Vector2(-5, 3), tp + Vector2(5, 3), tp + Vector2(0, -5)]) if up else PackedVector2Array([tp + Vector2(-5, -3), tp + Vector2(5, -3), tp + Vector2(0, 5)])
			_bars.draw_colored_polygon(pts, Color(col, a))
		ix += 25.0
	# Stun: little stars circling the head.
	if statuses.has("stun") and not dead:
		var hc2 := Vector2(0, y + 40)
		for i in 3:
			var ang := _t * 5.0 + TAU * i / 3.0
			var p := hc2 + Vector2(cos(ang) * 30.0, sin(ang) * 9.0)
			_draw_star(p, 7.0, Color(1.0, 0.9, 0.35, a))


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	_bars.draw_colored_polygon(pts, col)


func _status_tex(st: String) -> Texture2D:
	if _icon_cache.has(st):
		return _icon_cache[st]
	var n := str(STATUS_ICONS.get(st, ""))
	var tex: Texture2D = Kit.icon_texture(n) if n != "" else null
	_icon_cache[st] = tex
	return tex
