extends Node2D
## The souls over the battlefield (combat v1, the war version; docs/dev/combat-v1.md): a crowd of
## glowing wisps hanging in the sky above the foes, the prize of every fight. Each belongs to a side: the
## player's burn gold, the foe's signal red. As the fight swings (the share of HP each side has
## lost), wisps change hands one by one and drift toward their owner's line. When the fight ends
## the winner's side takes them all: on a victory every wisp turns gold and streams down into the
## team. A display layer only: it reads the battle screen's views and never touches the sim.
##   var s := SoulsCrowd.new(); layer.add_child(s); s.setup(field_rect)
##   s.update_share(share)   # 0..1, the player's share (every frame)
##   s.finish(true)          # victory: every wisp flies to the team; returns the souls won

const BattleFxRef := preload("res://src/ui/battle/battle_fx.gd")
const COUNT := 40
const GOLD := Color(1.0, 0.82, 0.42)
const RED := Color(1.0, 0.3, 0.14)

var band := Rect2(0, 0, 720, 120)
var _wisps: Array[Dictionary] = []
var _share := 0.5
var _t := 0.0
var _done := ""
var _done_t := 0.0


## field: the battle field rect (screen px); the crowd fills a band across its sky, over the foes.
func setup(field: Rect2) -> void:
	band = Rect2(field.position.x + field.size.x * 0.05, field.position.y + field.size.y * 0.04,
		field.size.x * 0.9, field.size.y * 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	_wisps.clear()
	for i in COUNT:
		_wisps.append({
			"u": rng.randf(), "v": rng.randf(),
			# The order wisps change hands in (a shuffled rank, so they turn all over the crowd).
			"rank": rng.randf(),
			"phase": rng.randf() * TAU, "speed": rng.randf_range(0.6, 1.3), "size": rng.randf_range(0.7, 1.25),
			"own": 0.5, "pos": Vector2.ZERO, "fly": 0.0,
		})
	_wisps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rank) < float(b.rank))
	for w: Dictionary in _wisps:
		w.pos = _home(w)
		w.own = 1.0 if _wisps.find(w) < COUNT / 2 else 0.0


## The player's share of the souls, 0..1 (0.5 at the start).
func update_share(share: float) -> void:
	if _done == "":
		_share = clampf(share, 0.0, 1.0)


## How many wisps are the player's right now.
func souls_owned() -> int:
	var n := 0
	for w: Dictionary in _wisps:
		if float(w.own) > 0.5:
			n += 1
	return n


## The fight is over: the winner takes every wisp (victory: they stream down into the team).
## Returns the souls the player won.
func finish(victory: bool) -> int:
	_done = "win" if victory else "lose"
	_done_t = 0.0
	_share = 1.0 if victory else 0.0
	return COUNT if victory else 0


func _home(w: Dictionary) -> Vector2:
	return band.position + Vector2(float(w.u) * band.size.x, float(w.v) * band.size.y)


func _process(delta: float) -> void:
	_t += delta
	if _done != "":
		_done_t += delta
	var mine := int(round(_share * COUNT))
	for i in _wisps.size():
		var w: Dictionary = _wisps[i]
		# The first `mine` in rank order are the player's; ownership eases over about half a second.
		var goal := 1.0 if i < mine else 0.0
		w.own = move_toward(float(w.own), goal, delta * 2.2)
		var home := _home(w)
		# Owned wisps lean toward their side's line: the player's down, the foe's up.
		var lean := (float(w.own) - 0.5) * band.size.y * 0.7
		var bob := Vector2(sin(_t * float(w.speed) + float(w.phase)) * 9.0, cos(_t * float(w.speed) * 1.3 + float(w.phase)) * 6.0)
		var target := home + Vector2(0, lean) + bob
		if _done != "":
			# The take: wisps stream to the winner's line, staggered by rank.
			var k := clampf((_done_t - float(i) * 0.02) / 0.9, 0.0, 1.0)
			w.fly = k
			var off := Vector2(0, (900.0 if _done == "win" else -700.0) * k * k)
			target = home + off
		w.pos = (w.pos as Vector2).lerp(target, 1.0 - exp(-delta * 5.0))
	queue_redraw()


func _draw() -> void:
	var glow := BattleFxRef.glow_texture()
	# The count, printed on a small paper tag at the crowd's left: the player's souls of the total.
	var f := Kit.font("mono_bold")
	var txt := "SOULS  %02d / %d" % [souls_owned(), COUNT]
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var tp := band.position + Vector2(0, -4)
	draw_rect(Rect2(tp + Vector2(1, 2), Vector2(tw + 18, 22)), Color(0, 0, 0, 0.28))
	draw_rect(Rect2(tp, Vector2(tw + 18, 22)), Color(0.914, 0.91, 0.886, 0.96))
	draw_rect(Rect2(tp, Vector2(4, 22)), GOLD.darkened(0.15))
	draw_string(f, tp + Vector2(10, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.063, 0.067, 0.075))
	for w: Dictionary in _wisps:
		var own := float(w.own)
		var col := RED.lerp(GOLD, own)
		var fade := 1.0 - float(w.fly)
		if fade <= 0.01:
			continue
		var flick := 0.75 + 0.25 * sin(_t * 3.1 * float(w.speed) + float(w.phase))
		var s := 40.0 * float(w.size)
		var p: Vector2 = w.pos
		# A dark halo so the wisp reads over a bright sky, then its glow, then the flame itself: a
		# teardrop whose tip sways (up for the foe's, a softer lean for the player's), a hot core.
		draw_texture_rect(glow, Rect2(p - Vector2(s, s) * 0.7, Vector2(s, s) * 1.4), false, Color(0.05, 0.02, 0.06, 0.35 * fade))
		draw_texture_rect(glow, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(col, 0.7 * flick * fade))
		var r := 6.5 * float(w.size)
		var sway := sin(_t * 2.3 * float(w.speed) + float(w.phase)) * r * 0.9
		_flame(p, r, sway, Color(col, 0.95 * fade))
		_flame(p + Vector2(0, r * 0.25), r * 0.55, sway * 0.6, Color(col.lerp(Color.WHITE, 0.7), fade))


## A teardrop flame: a round base of radius r at p and a tip about 2.6 r above it, leaning by sway.
func _flame(p: Vector2, r: float, sway: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(p + Vector2(sway, -r * 2.6))
	for i in 13:
		var a := deg_to_rad(-20.0 + 220.0 * i / 12.0)
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
