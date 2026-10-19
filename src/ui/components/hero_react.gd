class_name HeroReact
extends RefCounted
## A hero's reaction to a tap (owner, 2026-10-19: "more complex than just a bounce"), shared by the
## Lobby poster and the hero dossier. One tap combines:
## - an ink-and-signal ring burst with printed dots where the finger landed (misregistered, like
##   two print plates);
## - a camera punch on the figure (a quick scale-up from her feet that springs back) and a wobble;
## - an expression from the HaloRig's eye and mouth variants;
## - a pose that changes tap by tap: victory, a cast with sparks, a hop, a laughing flinch;
## - on a flurry of taps (4 within the window) a flustered beat: the poster shakes and a "!!"
##   rubber stamp lands by her head.
## Reduce motion keeps the pose and the expression only.
##   var hold := HeroReact.react(host, sprite, anchor, tap_pos_in_host, taps_in_a_row, shake_target)
##   (play_idle after `hold` seconds; the expression resets itself)

const SIG := Color("ff4b1f")
const INK := Color("101113")
const PAPER := Color("f5f4f0")
## Taps closer together than this count as a flurry.
const FLURRY_GAP := 1.4

## The poses in turn (the fourth is the flustered one): [eyes, mouth, animation].
const BEATS := [["smile", "smile", "victory"], ["closed", "smile", "cast"], ["open", "open", "hop"],
	["closed", "open", "hit"]]


## Counts taps in a row: pass the previous count and the seconds since the last tap.
static func next_count(prev: int, since: float) -> int:
	return prev + 1 if since < FLURRY_GAP else 1


## Plays the reaction. Returns how long the pose holds (seconds) so the caller can return the
## hero to idle.
static func react(host: Control, sprite: Node2D, anchor: Node2D, at: Vector2, n: int, shake_target: Control = null) -> float:
	if sprite == null or not is_instance_valid(sprite):
		return 0.0
	var flustered := n >= 4
	var beat: Array = BEATS[3] if flustered else BEATS[(maxi(n, 1) - 1) % 3]
	sprite.call("set_expression", "eyes", beat[0])
	sprite.call("set_expression", "mouth", beat[1])
	match str(beat[2]):
		"victory":
			sprite.call("play_victory")
		"hit":
			sprite.call("play_hit")
		_:
			sprite.call("play", beat[2])
	var hold := 2.4 if not flustered else 1.6
	Kit.haptic(30 if flustered else 14)
	Kit.sfx("tap")
	var tree := host.get_tree() if host else null
	if tree:
		var wr: WeakRef = weakref(sprite)
		tree.create_timer(hold).timeout.connect(func() -> void:
			var s: Variant = wr.get_ref()
			if s:
				(s as Node2D).call("set_expression", "eyes", "")
				(s as Node2D).call("set_expression", "mouth", ""))
	if not Kit.motion_ok():
		return hold
	# Camera punch from her feet, then a wobble that leans away from the finger.
	if anchor and is_instance_valid(anchor):
		if not anchor.has_meta("react_base"):
			anchor.set_meta("react_base", anchor.scale)
		var base: Vector2 = anchor.get_meta("react_base")
		anchor.scale = base * (1.1 if flustered else 1.06)
		anchor.create_tween().tween_property(anchor, "scale", base, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var feet := host.get_global_transform().affine_inverse() * anchor.global_position
		var lean := -1.0 if at.x > feet.x else 1.0
		var rw := anchor.create_tween()
		rw.tween_property(anchor, "rotation", 0.04 * lean, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rw.tween_property(anchor, "rotation", -0.028 * lean, 0.16).set_trans(Tween.TRANS_SINE)
		rw.tween_property(anchor, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var fx := _Burst.new()
	fx.position = at
	fx.big = flustered
	fx.sparks = str(beat[2]) == "cast"
	host.add_child(fx)
	if flustered:
		if shake_target and is_instance_valid(shake_target):
			Kit.shake(shake_target, 9)
		_stamp(host, at + Vector2(-30, -150))
	return hold


## A "!!" rubber stamp that slams on and fades.
static func _stamp(host: Control, pos: Vector2) -> void:
	var l := Kit.label("!!", 72, SIG, "wide_black")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = pos
	l.rotation = -0.22
	l.pivot_offset = Vector2(40, 40)
	l.scale = Vector2(1.8, 1.8)
	l.modulate.a = 0.0
	host.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.08)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(l.queue_free)


## Rings and printed dots bursting from the touch point (signal plate and ink plate out of register),
## with faction-free sparks for a cast.
class _Burst:
	extends Control
	var big := false
	var sparks := false
	var _t := 0.0
	var _dots: Array = []

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in 16:
			var a := TAU * i / 16.0 + rng.randf_range(-0.2, 0.2)
			_dots.append([Vector2(cos(a), sin(a)), rng.randf_range(60.0, 140.0), rng.randf_range(2.5, 7.0), i % 2 == 0])

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.75:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_t / 0.75, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var fade := 1.0 - k
		var s := 1.4 if big else 1.0
		draw_arc(Vector2.ZERO, lerpf(8.0, 96.0, e) * s, 0.0, TAU, 48, Color(HeroReact.SIG, 0.9 * fade), 5.0 * fade + 1.0, true)
		draw_arc(Vector2(4, 3), lerpf(6.0, 74.0, e) * s, 0.0, TAU, 48, Color(HeroReact.INK, 0.8 * fade), 2.5 * fade + 0.5, true)
		for d: Array in _dots:
			var p: Vector2 = (d[0] as Vector2) * float(d[1]) * e * s
			var c: Color = HeroReact.SIG if bool(d[3]) else HeroReact.INK
			draw_circle(p + (Vector2(3, 2) if not bool(d[3]) else Vector2.ZERO), float(d[2]) * (1.0 - k * 0.6), Color(c, fade))
		if sparks:
			for i in 8:
				var a := TAU * i / 8.0 + _t * 3.0
				var r0 := lerpf(20.0, 120.0, e)
				var dir := Vector2(cos(a), sin(a))
				draw_line(dir * r0, dir * (r0 + 22.0 * fade), Color(HeroReact.PAPER, fade), 3.0, true)
				draw_line(dir * r0 + Vector2(2, 2), dir * (r0 + 22.0 * fade) + Vector2(2, 2), Color(HeroReact.SIG, fade), 2.0, true)
