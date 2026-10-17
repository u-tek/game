extends Node2D
## One battle unit on the field: the animated HeroSprite plus its overhead bars (HP with a
## trailing damage chip, shield, energy), status icons and stun stars. Feet at the origin.
## The battle screen feeds it display-time values from sim events; it never reads the sim.

const BattleFxRef := preload("res://src/ui/battle/battle_fx.gd")
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
## Animation timing read from this hero's rig (battle ms at speed 1; -1 = unknown).
var hit_ms := -1.0
var release_ms := -1.0
var ult_hit_s := -1.0
## True when the attack animation draws its own swing (vfx_slash / vfx_thrust event).
var has_swing_vfx := false

var _bars: Node2D
var _chip := 1.0
var _t := 0.0
var _head_h := 260.0
var _faction_tex: Texture2D
var _icon_cache := {}
var _bars_alpha := 1.0
## Bar opacity while the body is away from its spot (attack lunges).
var _lunge_k := 1.0


## bars_layer: a Node2D drawn above every sprite (same transform as this node's parent);
## the overhead bars live there so no sprite ever covers them.
func setup(u: Dictionary, k: float, facing: int, echo: bool, bars_layer: Node2D) -> void:
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
	# The player's heroes wear their equipped skin; enemies (campaign echoes) keep the base look.
	sprite = HeroArt.make_sprite(hero_id, Game.equipped_skin(hero_id) if side == "ally" else "")
	add_child(sprite)
	sprite.scale = Vector2(k, k)
	sprite.call("set_facing", facing)
	if echo:
		sprite.call("set_echo", true)
	if is_boss:
		sprite.call("set_boss", true)
	_head_h = float(sprite.call("get_height"))
	_read_timing()
	_bars = Node2D.new()
	_bars.name = "Bars_" + uid
	_bars.draw.connect(_draw_bars)
	bars_layer.add_child(_bars)


func _read_timing() -> void:
	var rp: Variant = sprite.get("rig")
	if not (rp is Node):
		return
	var rig_id := str((rp as Node).get("hero_id"))
	var data: Variant = (rp as Node).get("rig")
	var kind := str(data.get("kind")) if data is Object and "kind" in data else ""
	var atk := RigAnim.find(attack_anim(), rig_id, kind)
	if atk:
		var h := atk.event_time("hit")
		hit_ms = h * 1000.0 if h >= 0.0 else -1.0
		var r := atk.event_time("release")
		release_ms = r * 1000.0 if r >= 0.0 else -1.0
		has_swing_vfx = atk.event_time("vfx_slash") >= 0.0 or atk.event_time("vfx_thrust") >= 0.0
	var ult := RigAnim.find("ultimate", rig_id, kind)
	if ult:
		ult_hit_s = ult.event_time("hit")


## Ground marker (cyan for allies, red for enemies) and a soft backlight in the faction
## color, drawn behind the sprite so every unit reads on any floor. Style v2: a thin
## technical ring with four gaps and a faint fill.
func _draw() -> void:
	if dead:
		return
	var k := float(sprite.scale.y) if sprite else 1.0
	var rx := 62.0 * k * (1.3 if is_boss else 1.0)
	var ry := rx * 0.3
	var col := Kit.ACCENT_HI if side == "ally" else Color("ff5a4a")
	var glow := BattleFxRef.glow_texture()
	var gs := Vector2(_head_h * 0.95, _head_h * 1.1)
	draw_texture_rect(glow, Rect2(Vector2(-gs.x * 0.5, -_head_h * 0.55 - gs.y * 0.5), gs), false, Color(HeroArt.faction_color(faction), 0.14))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, Color(col, 0.12), true, -1.0, true)
	for q in 4:
		var a0 := TAU * q / 4.0 + 0.18
		draw_arc(Vector2.ZERO, rx, a0, a0 + TAU / 4.0 - 0.36, 16, Color(col, 0.8), 3.0, true)
	draw_arc(Vector2.ZERO, rx * 0.78, 0, TAU, 48, Color(col, 0.25), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Local y of the top of the head (negative).
func head_y() -> float:
	return -_head_h


## Where the body currently is relative to the formation spot (attack lunges move it).
func body_offset() -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var b: Variant = sprite.get("_body")
	if b is Node2D:
		return (b as Node2D).position * sprite.scale
	return Vector2.ZERO


func chest_global() -> Vector2:
	return to_global(body_offset() + Vector2(0, -_head_h * 0.55))


func head_global() -> Vector2:
	return to_global(body_offset() + Vector2(0, -_head_h * 0.9))


func hand_global() -> Vector2:
	var f := int(sprite.get("facing")) if sprite else home_facing
	return to_global(body_offset() + Vector2(f * _head_h * 0.18, -_head_h * 0.6))


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
	queue_redraw()
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


func _exit_tree() -> void:
	if _bars and is_instance_valid(_bars):
		_bars.queue_free()


func _process(delta: float) -> void:
	_t += delta
	# The bars lean only a little with attack lunges and fade while the body is far from its
	# spot, so units bunching up mid-fight never stack their bars into an unreadable pile.
	var off := body_offset()
	_bars.position = position + off * 0.3
	var lk := clampf(1.0 - (off.length() - 40.0) / 160.0, 0.35, 1.0)
	if absf(lk - _lunge_k) > 0.02:
		_lunge_k = lk
		_bars.queue_redraw()
	var frac := float(hp) / float(max_hp)
	if _chip > frac:
		_chip = maxf(frac, _chip - delta * 0.8)
		_bars.queue_redraw()
	elif _chip < frac:
		_chip = frac
	if statuses.has("stun") or energy >= 1000 or (_bars_alpha > 0.0 and _bars_alpha < 1.0):
		_bars.queue_redraw()


## Overhead bars (style v2): a faction hex at the left, a flat HP bar (allies green,
## enemies red, a pale trailing chip), a shield line, the cyan energy bar (pulsing white when
## the ultimate is ready), status chips above.
func _draw_bars() -> void:
	if _bars_alpha <= 0.01:
		return
	var a := _bars_alpha * _lunge_k
	var w := BAR_W * (1.35 if is_boss else 1.0) * clampf(depth_scale, 0.85, 1.05)
	var y := -_head_h - 26.0
	var x0 := -w * 0.5 + 12.0
	var frame := Color(0.03, 0.035, 0.04, 0.9 * a)
	# Faction emblem in a small dark hex at the left end.
	if _faction_tex:
		var hc0 := Vector2(x0 - 14, y + 8)
		var hx := PackedVector2Array()
		for i in 6:
			var ang := TAU * i / 6.0
			hx.append(hc0 + Vector2(cos(ang), sin(ang)) * 16.0)
		_bars.draw_colored_polygon(hx, Color(0.1, 0.11, 0.13, 0.92 * a))
		hx.append(hx[0])
		_bars.draw_polyline(hx, Color(1, 1, 1, 0.45 * a), 1.5, true)
		_bars.draw_texture_rect(_faction_tex, Rect2(hc0 - Vector2(12, 12), Vector2(24, 24)), false, Color(1, 1, 1, a))
	# HP.
	var hp_h := 12.0
	var r := Rect2(x0, y, w - 10.0, hp_h)
	_bars.draw_rect(r.grow(2.0), frame)
	_bars.draw_rect(r, Color(0.17, 0.18, 0.2, a))
	var frac := float(hp) / float(max_hp)
	if _chip > frac:
		_bars.draw_rect(Rect2(r.position + Vector2(r.size.x * frac, 0), Vector2(r.size.x * (_chip - frac), hp_h)), Color(1.0, 0.96, 0.88, 0.9 * a))
	var hc := Kit.GOOD if side == "ally" else Kit.EMBER
	if frac < 0.3 and side == "ally":
		hc = Kit.ORANGE
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, hp_h)), Color(hc, a))
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, 2.0)), Color(1, 1, 1, 0.4 * a))
	# Segment ticks every 25%.
	for q in range(1, 4):
		var tx := r.position.x + r.size.x * q / 4.0
		_bars.draw_line(Vector2(tx, r.position.y), Vector2(tx, r.end.y), Color(0, 0, 0, 0.35 * a), 1.0)
	# Shield: bright line on top, capped at the bar width.
	if shield > 0:
		var sf := minf(1.0, float(shield) / float(max_hp))
		_bars.draw_rect(Rect2(r.position + Vector2(0, -5), Vector2(r.size.x * sf, 4)), Color(0.85, 0.95, 1.0, 0.95 * a))
	# Energy.
	var er := Rect2(x0, y + hp_h + 4, w - 10.0, 5)
	_bars.draw_rect(er.grow(1.5), frame)
	var ef := float(energy) / 1000.0
	var ec := Kit.ACCENT if ef < 1.0 else Kit.ACCENT_HI.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 8.0))
	_bars.draw_rect(Rect2(er.position, Vector2(er.size.x * ef, er.size.y)), Color(ec, a))
	# Status chips above the bar.
	var ix := x0
	for st: String in statuses:
		var tex := _status_tex(st)
		if tex == null:
			continue
		var bad := DEBUFFS.has(st)
		var ip := Vector2(ix, y - 30)
		var chip := Rect2(ip, Vector2(23, 23))
		_bars.draw_rect(chip, Color(0.08, 0.09, 0.1, 0.9 * a))
		_bars.draw_rect(Rect2(chip.position + Vector2(0, chip.size.y - 3), Vector2(chip.size.x, 3)), Color(Kit.EMBER if bad else Kit.GOOD, a))
		_bars.draw_texture_rect(tex, Rect2(ip + Vector2(3, 2), Vector2(17, 17)), false, Color(1, 1, 1, a))
		if st.ends_with("_up") or st.ends_with("_down"):
			var up := st.ends_with("_up")
			var tp := ip + Vector2(19, 17)
			var col := Kit.GOOD if up else Color("ff5a4a")
			var pts := PackedVector2Array([tp + Vector2(-5, 3), tp + Vector2(5, 3), tp + Vector2(0, -5)]) if up else PackedVector2Array([tp + Vector2(-5, -3), tp + Vector2(5, -3), tp + Vector2(0, 5)])
			_bars.draw_colored_polygon(pts, Color(col, a))
		ix += 26.0
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
