extends Node2D
## One battle unit on the field: the animated HeroSprite plus its overhead readout (style v4: a
## printed paper tag with HP and a trailing damage chip, a tick ruler, shield and energy), status
## chips and a printed range ring on the ground. Feet at the origin.
## The battle screen feeds it display-time values from sim events; it never reads the sim.
## A blow's reaction (src/ui/battle/hit_plan.gd): an impact frame (her figure printed in two inks for
## a couple of drawn frames, at her own cut point), a knock (a spring along the blow), an ink dip
## instead of a white flash. A fallen echo holds a two-tone proof, then her print lifts off as
## halftone dots, lights first; a fallen heroine settles into her red halftone print and stays.

const BattleFxRef := preload("res://src/ui/battle/battle_fx.gd")
const UltCutinRef := preload("res://src/ui/battle/ult_cutin.gd")
## The knock's spring (rad/s, damping ratio): one overshoot, settled in about 0.2 s.
const KNOCK_W := 38.0
const KNOCK_Z := 0.55
## A fallen echo: the proof holds PROOF_S, then the dots lift off in DOTS_LIFT_S.
const PROOF_S := 0.16
const DOTS_LIFT_S := 0.42
const STATUS_ICONS := {
	"stun": "star", "burn": "faction_infernal", "regen": "stat_hp", "taunt": "role_guardian",
	"atk_up": "stat_atk", "atk_down": "stat_atk", "def_up": "stat_def", "def_down": "stat_def",
	"spd_up": "stat_spd", "charm": "faction_infernal",
}
const DEBUFFS := ["stun", "burn", "atk_down", "def_down", "charm"]
const BAR_W := 108.0
## Style v4 print colours (paper tag, ink, signal) and the ground ring colours.
const PAPER := SignalKit.PAPER
const INK := SignalKit.INK
const SIG := SignalKit.SIGNAL
const MARK_ALLY := SignalKit.MATTE
const MARK_ENEMY := SignalKit.SIGNAL

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
## Front view (the team big in the foreground): she always faces the camera (no flipping toward
## targets) and her overhead tag stays hidden (her card on the bottom strip carries HP and energy).
var lock_facing := false
var bars_off := false
## Hands-on: the heroine in the spotlight (a warm beam behind her, a little brighter) and the foe
## marked for the team (a signal crosshair on her).
var spotlit := false
var marked := false
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
## Her two-tone cut point (UltCutin._cut_point, found a beat into the fight; -1 until then).
var _cut := -1.0
var _skin := ""
## The impact frame shows until this time (_t, seconds; -1 = none): time, not drawn frames, so it
## lasts as long on a 120 Hz phone as in a 30 fps capture.
var _flip_until := -1.0
var _knock := Vector2.ZERO
var _knock_v := Vector2.ZERO
var _knock_px := 0.0
var _knock_s := 1.0
var _base_scale := 1.0
## Seconds since she fell (-1 alive).
var _death_t := -1.0
var _death_cell := 14.0


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
	_skin = Game.equipped_skin(hero_id) if side == "ally" else ""
	sprite = HeroArt.make_sprite(hero_id, _skin)
	sprite.set("holo", false)    # the Legendary foil is for the big portraits, not the battlefield
	add_child(sprite)
	sprite.scale = Vector2(k, k)
	# A blow is an ink dip, not a white flash: a faint one on a heroine (only blows she feels make
	# her react at all: HitPlan), a harder take on foes.
	sprite.set("flash_color", INK)
	sprite.set("flash_peak", 0.1 if side == "ally" else 0.4)
	sprite.set("flash_decay", 8.3 if side == "ally" else 12.5)
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
	var adir := str(data.get("dir")) if data is Object and "dir" in data else ""
	var atk := RigAnim.find(attack_anim(), rig_id, kind, adir)
	if atk:
		var h := atk.event_time("hit")
		hit_ms = h * 1000.0 if h >= 0.0 else -1.0
		var r := atk.event_time("release")
		release_ms = r * 1000.0 if r >= 0.0 else -1.0
		has_swing_vfx = atk.event_time("vfx_slash") >= 0.0 or atk.event_time("vfx_thrust") >= 0.0
	var ult := RigAnim.find("ultimate", rig_id, kind, adir)
	if ult:
		ult_hit_s = ult.event_time("hit")


## Ground marker (style v4): a printed range ring under every unit, paper-white for allies and
## signal for enemies (four arcs with gaps, an inner hairline, ticks around it like an instrument
## scale), with a soft backlight in the faction colour behind the sprite so every unit reads on any
## floor.
func _draw() -> void:
	if dead:
		return
	if spotlit:
		# A warm beam from above, behind her: soft at the top, brightest at her feet.
		var bw := _head_h * 0.62
		# Three nested beams (wide and faint to narrow and bright) so the edges fall off softly.
		for k in 3:
			var wk := 1.0 - k * 0.22
			var ak := 0.13 + k * 0.07
			var beam := PackedVector2Array([Vector2(-bw * 0.16 * wk, -_head_h * 1.3), Vector2(bw * 0.16 * wk, -_head_h * 1.3),
				Vector2(bw * 0.62 * wk, 0), Vector2(-bw * 0.62 * wk, 0)])
			var cols := PackedColorArray([Color(1.0, 0.86, 0.55, 0.0), Color(1.0, 0.86, 0.55, 0.0),
				Color(1.0, 0.8, 0.45, ak), Color(1.0, 0.8, 0.45, ak)])
			draw_polygon(beam, cols)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.24))
		draw_circle(Vector2.ZERO, bw * 0.62, Color(1.0, 0.82, 0.5, 0.35), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if lock_facing:
		# Front view: the team stands at the foot of the screen with no ring under her.
		return
	var k := float(sprite.scale.y) if sprite else 1.0
	var rx := 62.0 * k * (1.3 if is_boss else 1.0)
	var ry := rx * 0.3
	var col := MARK_ALLY if side == "ally" else MARK_ENEMY
	var glow := BattleFxRef.glow_texture()
	var gs := Vector2(_head_h * 0.95, _head_h * 1.1)
	draw_texture_rect(glow, Rect2(Vector2(-gs.x * 0.5, -_head_h * 0.55 - gs.y * 0.5), gs), false, Color(HeroArt.faction_color(faction), 0.14))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, Color(col, 0.1), true, -1.0, true)
	for q in 4:
		var a0 := TAU * q / 4.0 + 0.18
		draw_arc(Vector2.ZERO, rx, a0, a0 + TAU / 4.0 - 0.36, 16, Color(col, 0.85), 2.5, true)
	draw_arc(Vector2.ZERO, rx * 0.78, 0, TAU, 48, Color(col, 0.3), 1.0, true)
	for i in 24:
		var a := TAU * i / 24.0
		var d := Vector2(cos(a), sin(a))
		var l := 9.0 if i % 6 == 0 else 4.0
		draw_line(d * (rx + 3.0), d * (rx + 3.0 + l), Color(col, 0.55 if i % 6 == 0 else 0.3), 1.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Where the body currently is relative to the formation spot (attack lunges move it).
func body_offset() -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	var b: Variant = sprite.get("_body")
	if b is Node2D:
		return (b as Node2D).position * sprite.scale
	return Vector2.ZERO


## Her height on the field (the unit's own pixels).
func body_height() -> float:
	return _head_h


## Her overhead paper tag, in her parent's space (the numbers dock on it).
func tag_rect() -> Rect2:
	var w := BAR_W * (1.35 if is_boss else 1.0) * clampf(depth_scale, 0.85, 1.05)
	var y := -_head_h - 32.0
	var x0 := -w * 0.5 + 12.0
	return Rect2((_bars.position if _bars else position) + Vector2(x0 - 22.0, y - 4.0), Vector2(w - 10.0 + 26.0, 27.0))


## The impact frame: her figure in two inks (`dark` her shadows, `light` her lights, cut at her own
## mid-tone) for `frames` beats of 30 ms (2: 60 ms, 3: 90 ms); `strength` below 1 only leans her
## toward them (a jolt).
func impact(frames: int, dark: Color, light: Color, strength: float = 1.0) -> void:
	if dead or frames <= 0 or sprite == null:
		return
	if _cut < 0.0:
		_cut = UltCutinRef._cut_point(hero_id, _skin)
	sprite.call("two_tone", true, dark, light, _cut, strength)
	_flip_until = _t + 0.03 * frames


## The knock: her body pushed `px` along `dir` (and scaled by `scale_k` at the peak), springing back.
func knock(dir: Vector2, px: float, scale_k: float = 1.0) -> void:
	if dead or px <= 0.0 or sprite == null:
		return
	if _knock_px <= 0.0:
		# The field's layout sizes her (battle_screen): the knock scales from whatever she is now.
		_base_scale = absf(sprite.scale.y)
	_knock = dir.normalized() * px
	_knock_v = Vector2.ZERO
	_knock_px = px
	_knock_s = scale_k


func chest_global() -> Vector2:
	return to_global(body_offset() + Vector2(0, -_head_h * 0.55))


## Her chest at her spot, not where a lunge has carried her (prints land here: a foe mid-lunge is
## behind the heroine she charges, and her print must not land on the heroine).
func chest_home_global() -> Vector2:
	return to_global(Vector2(0, -_head_h * 0.55))


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
	if lock_facing:
		sprite.call("set_facing", home_facing)
		return
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


func set_spotlit(on: bool) -> void:
	if on == spotlit:
		return
	spotlit = on
	if sprite:
		var a := sprite.modulate.a
		sprite.modulate = Color(1.1, 1.08, 1.02) if on else Color.WHITE
		sprite.modulate.a = a
	queue_redraw()


func set_marked(on: bool) -> void:
	if on == marked:
		return
	marked = on
	_bars.queue_redraw()


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
	if _cut < 0.0:
		_cut = UltCutinRef._cut_point(hero_id, _skin)
	var rp: Variant = sprite.get("rig")
	var rs := absf((rp as Node2D).get_global_transform().get_scale().y) if rp is Node2D else 0.3
	# The dots' pitch: 10 screen pixels on a foe, 8 on a heroine, in rig pixels.
	_death_cell = (8.0 if side == "ally" else 10.0) / maxf(rs, 0.01)
	_flip_until = -1.0
	# The halftone rides the warp mesh's rest pose; a cutout rig (the silhouette fallback) just fades.
	var data: Variant = (rp as Node).get("rig") if rp is Node else null
	if not (data is Object and "kind" in data and str(data.get("kind")) == "warp"):
		var ft := create_tween()
		ft.tween_interval(PROOF_S)
		ft.tween_property(sprite, "modulate:a", 0.35 if side == "ally" else 0.0, 0.4)
		return
	_death_t = 0.0
	if not Kit.motion_ok():
		return
	sprite.call("two_tone", true, INK, SIG if side == "ally" else PAPER, _cut)


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
	_bars.visible = on and not bars_off


func _exit_tree() -> void:
	if _bars and is_instance_valid(_bars):
		_bars.queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _cut < 0.0 and _t > 0.3 + slot * 0.12 + (0.6 if side == "enemy" else 0.0):
		# Baked (tools/art_cuts.py), so this is a lookup; spread out in case it falls back to a scan.
		_cut = UltCutinRef._cut_point(hero_id, _skin)
	if _flip_until >= 0.0 and _t >= _flip_until and not dead:
		_flip_until = -1.0
		sprite.call("two_tone", false)
	if _knock_px > 0.0:
		# Sub-steps of at most 1/120 s (one Euler step at 30 fps would blow this spring up).
		var n := ceili(minf(delta, 0.1) * 120.0)
		var dt := minf(delta, 0.1) / maxf(n, 1)
		for _i in n:
			_knock_v += (-KNOCK_W * KNOCK_W * _knock - 2.0 * KNOCK_Z * KNOCK_W * _knock_v) * dt
			_knock += _knock_v * dt
		var kk := clampf(_knock.length() / _knock_px, 0.0, 1.0)
		sprite.position = _knock
		sprite.scale = Vector2(signf(sprite.scale.x), 1.0) * _base_scale * lerpf(1.0, _knock_s, kk)
		if _knock.length() < 0.2 and _knock_v.length() < 2.0:
			_knock_px = 0.0
			sprite.position = Vector2.ZERO
			sprite.scale = Vector2(signf(sprite.scale.x), 1.0) * _base_scale
	if _death_t >= 0.0:
		_step_death(delta)
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
	if energy >= 1000 or (_bars_alpha > 0.0 and _bars_alpha < 1.0):
		_bars.queue_redraw()


## Overhead readout (style v4): a small printed paper tag over the head. An ink square with the
## faction glyph, the HP bar (ink for allies, signal for enemies, an ink chip trailing behind) in a
## hairline frame with a tick ruler under it (every 10%, majors at 0 / 50 / 100%), a dashed shield
## line over it and the energy line in signal under the ruler (it pulses and a light shows at its end
## when the ultimate is ready). Status chips sit above the tag as small printed squares.
func _draw_bars() -> void:
	if marked and not dead:
		# The mark: a signal crosshair over her chest with corner ticks.
		var c := Vector2(0, -_head_h * 0.52)
		var r := _head_h * 0.16
		_bars.draw_arc(c, r, 0, TAU, 40, Color(SIG, 0.95), 3.0, true)
		for q in 4:
			var d := Vector2.from_angle(q * PI * 0.5)
			_bars.draw_line(c + d * (r - 10.0), c + d * (r + 14.0), Color(SIG, 0.95), 3.0, true)
		_bars.draw_circle(c, 4.0, Color(SIG, 0.95), true, -1.0, true)
	if _bars_alpha <= 0.01:
		return
	var a := _bars_alpha * _lunge_k
	var w := BAR_W * (1.35 if is_boss else 1.0) * clampf(depth_scale, 0.85, 1.05)
	var y := -_head_h - 32.0
	var x0 := -w * 0.5 + 12.0
	var bw := w - 10.0
	# The paper tag and its faction square.
	var tag := Rect2(x0 - 22.0, y - 4.0, bw + 26.0, 27.0)
	_bars.draw_rect(Rect2(tag.position + Vector2(1, 2), tag.size), Color(0, 0, 0, 0.28 * a))
	_bars.draw_rect(tag, Color(PAPER, 0.96 * a))
	var sq := Rect2(tag.position + Vector2(2, 2), Vector2(18, tag.size.y - 4))
	_bars.draw_rect(sq, Color(INK, a))
	if _faction_tex:
		_bars.draw_texture_rect(_faction_tex, Rect2(sq.get_center() - Vector2(7, 7), Vector2(14, 14)), false, Color(1, 1, 1, a))
	# HP.
	var hp_h := 9.0
	var r := Rect2(x0, y, bw, hp_h)
	_bars.draw_rect(r, Color(INK, 0.08 * a))
	var frac := float(hp) / float(max_hp)
	if _chip > frac:
		_bars.draw_rect(Rect2(r.position + Vector2(r.size.x * frac, 0), Vector2(r.size.x * (_chip - frac), hp_h)), Color(INK, 0.3 * a))
	var hc := INK if side == "ally" else SIG
	_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, hp_h)), Color(hc, a))
	_bars.draw_rect(r, Color(INK, 0.85 * a), false, 1.0)
	# Tick ruler under the bar.
	for q in 11:
		var tx := r.position.x + minf(r.size.x * q / 10.0, r.size.x - 0.5)
		var tl := 4.0 if q % 5 == 0 else 2.0
		_bars.draw_line(Vector2(tx, r.end.y), Vector2(tx, r.end.y + tl), Color(INK, 0.7 * a), 1.0)
	# Shield: a dashed ink line over the bar, capped at the bar width.
	if shield > 0:
		var sf := minf(1.0, float(shield) / float(max_hp))
		var sx := 0.0
		while sx < r.size.x * sf:
			_bars.draw_rect(Rect2(r.position + Vector2(sx, -3), Vector2(minf(4.0, r.size.x * sf - sx), 2)), Color(INK, 0.85 * a))
			sx += 6.0
	# Energy.
	var er := Rect2(x0, y + hp_h + 6.0, bw, 4.0)
	_bars.draw_rect(er, Color(INK, 0.12 * a))
	var ef := float(energy) / 1000.0
	var ec := SIG if ef < 1.0 else SIG.lerp(Color("ffd2c2"), 0.5 + 0.5 * sin(_t * 8.0))
	_bars.draw_rect(Rect2(er.position, Vector2(er.size.x * ef, er.size.y)), Color(ec, a))
	if ef >= 1.0:
		_bars.draw_circle(Vector2(tag.end.x - 1.0, er.get_center().y), 3.5 + sin(_t * 8.0), Color(SIG, a))
	# Status chips above the tag.
	var ix := tag.position.x
	for st: String in statuses:
		var tex := _status_tex(st)
		if tex == null:
			continue
		var bad := DEBUFFS.has(st)
		var ip := Vector2(ix, tag.position.y - 26)
		var chip := Rect2(ip, Vector2(23, 23))
		_bars.draw_rect(chip, Color(PAPER, 0.96 * a))
		_bars.draw_rect(chip, Color(INK, 0.7 * a), false, 1.0)
		_bars.draw_rect(Rect2(chip.position + Vector2(0, chip.size.y - 3), Vector2(chip.size.x, 3)), Color(SIG if bad else INK, a))
		_bars.draw_texture_rect(tex, Rect2(ip + Vector2(3, 2), Vector2(17, 17)), false, Color(INK, a))
		if st.ends_with("_up") or st.ends_with("_down"):
			var up := st.ends_with("_up")
			var tp := ip + Vector2(19, 15)
			var pts := PackedVector2Array([tp + Vector2(-5, 3), tp + Vector2(5, 3), tp + Vector2(0, -5)]) if up else PackedVector2Array([tp + Vector2(-5, -3), tp + Vector2(5, -3), tp + Vector2(0, 5)])
			_bars.draw_colored_polygon(pts, Color(INK if up else SIG, a))
		ix += 26.0


## A fallen unit's print. An echo: the two-tone proof holds, then her figure turns to paper dots that
## shrink away, the lights first, and she is gone. A heroine: ink and signal for a beat, then she
## settles into her red halftone print (her poster band's) at 40%, sunk a little, and stays on the
## line. Reduce motion: plain crossfades.
func _step_death(delta: float) -> void:
	var was := _death_t
	_death_t += delta
	var t := _death_t
	var calm := not Kit.motion_ok()
	if side == "ally":
		# Her ink dots at 35%: she stays on the line, quiet (the signal stays the camera's).
		if was < 0.05 and t >= 0.05 and not calm:
			sprite.call("two_tone", false)
		if t >= 0.05 or calm:
			var k := clampf((t - (0.0 if calm else 0.05)) / 0.5, 0.0, 1.0)
			sprite.call("halftone", k, INK, _death_cell, 0.0)
			sprite.modulate.a = lerpf(1.0, 0.35, k)
			if not calm:
				sprite.position.y = 8.0 * k
		if t > 0.6:
			_death_t = -1.0
		return
	var proof := 0.0 if calm else PROOF_S
	if was < proof and t >= proof and not calm:
		sprite.call("two_tone", false)
	if t >= proof:
		var k := clampf((t - proof) / (0.3 if calm else DOTS_LIFT_S), 0.0, 1.0)
		if calm:
			sprite.call("halftone", k, PAPER, _death_cell, 0.0)
			sprite.modulate.a = 1.0 - clampf((t - 0.3) / 0.3, 0.0, 1.0)
		else:
			sprite.call("halftone", 1.0, PAPER, _death_cell, k)
	if t >= proof + (0.6 if calm else DOTS_LIFT_S):
		sprite.visible = false
		_death_t = -1.0


func _status_tex(st: String) -> Texture2D:
	if _icon_cache.has(st):
		return _icon_cache[st]
	var n := str(STATUS_ICONS.get(st, ""))
	var tex: Texture2D = Kit.icon_texture(n) if n != "" else null
	_icon_cache[st] = tex
	return tex
