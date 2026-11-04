extends Node2D
## The battle's printed hits (src/ui/battle/hit_plan.gd plans each one). One node draws every live
## impression in one _draw through one material (ink_print.gdshader), so nothing is made or freed per
## hit: each is two draws of a Blender-rendered edge-field sheet (assets/art/ui/hit/, made by
## tools/blender/hit_fx.py + finish_hit_fx.py), its second plate first, a few pixels out of register,
## then its key plate. An impression rides its foe's body (re-read every frame, so a lunge and the
## camera's glide carry it); the battle screen keeps this layer between the foes and the heroines, so
## a heroine standing in front of a foe covers the foe's print. It steps through its frames, holds,
## then lifts: the shader's cut rises against paper grain, so the thin bristles go first. A stroke is
## a diagonal cut across her, alternating per attacker; a cross is two strokes, the second a beat later
## and turned 75 degrees. A shot of ink flies as a droplet stretched along its flight (the splat prints
## when the damage lands). A fallen echo leaves an ink blot on the street, drawn by a second
## PressLayer under the units (`blots`).

const DeviceTier := preload("res://src/art/device_tier.gd")
const SHADER := preload("res://src/ui/shaders/ink_print.gdshader")
const GRAIN := preload("res://assets/art/ui/hit/press_grain.png")
## shape -> [sheet, columns, frames]; the frame size comes from the sheet.
const SHEETS := {
	"slash0": [preload("res://assets/art/ui/hit/slash0.png"), 3, 6],
	"slash1": [preload("res://assets/art/ui/hit/slash1.png"), 3, 6],
	"thrust": [preload("res://assets/art/ui/hit/thrust.png"), 3, 6],
	"splat": [preload("res://assets/art/ui/hit/splat.png"), 3, 6],
	"droplet": [preload("res://assets/art/ui/hit/droplet.png"), 4, 4],
	"blot": [preload("res://assets/art/ui/hit/blot.png"), 1, 1],
	"executed": [preload("res://assets/art/ui/hit/executed.png"), 3, 3],
}
## A rubber stamp's width against her body, its tilt, and its press (kiss, full, spread), hold and lift.
const STAMP_W := 0.72
const STAMP_TILT := -0.13
const STAMP_PLAN := {"frames": [0, 1, 2], "step": 0.045, "hold": 0.85, "lift": 0.3}
## Where the second plate settles after a crit's wide first strike.
const SETTLED := Vector2(4.0, 3.0)
const MAX_BLOTS := 6
## A stroke's tilt across the blow, and how far a cross's second stroke turns from the first.
const DIAGONAL := 0.56
const CROSS_TURN := 1.3
const CROSS_DELAY := 0.06

## A blot layer: ink stains that stay (no lift) at 40% under the units.
var blots := false
## Paused while a cut-in holds the screen (nothing ages; it still redraws where its foes are).
var paused := false
## Live impressions at once (4 on phones that are not Pro); 2 on one unit.
var cap := 6
var _items: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## attacker uid -> the sign of her last stroke's tilt (a one-two, not the same stroke twice).
var _tilt := {}


func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("grain", GRAIN)
	m.set_shader_parameter("grain_on", 1.0 if DeviceTier.pro() else 0.0)
	m.set_shader_parameter("fade", 0.4 if blots else 1.0)
	material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not DeviceTier.pro():
		cap = 4


## The display rng (seeded per battle, so tools/shoot repeats a fight's prints).
func seed_rng(s: int) -> void:
	_rng.seed = s


## An impression on unit `v` (it rides her body): plan from HitPlan.plan, `dir` the blow's direction on
## the screen, `off` from her chest in screen pixels. src_uid: the attacker (her strokes alternate).
## A "cross" plan, or cross = true (an assassin's two cuts), prints two strokes as an X.
func impress(v: Node2D, plan: Dictionary, dir: Vector2, off: Vector2, src_uid: String = "", cross: bool = false) -> void:
	var shape := str(plan.get("impress", ""))
	if shape == "" or v == null:
		return
	var crossed := cross or shape == "cross"
	if shape == "cross":
		shape = "slash"
	var rot := 0.0
	var flip := 1.0
	var variant := shape
	match shape:
		"splat", "thrust":
			rot = dir.angle()
		_:
			# A cut across her: a fixed diagonal, mirrored for a blow going left, alternating sides.
			variant = "slash%d" % _rng.randi_range(0, 1)
			flip = -1.0 if dir.x < 0.0 else 1.0
			var sgn := -float(_tilt.get(src_uid, 1.0))
			_tilt[src_uid] = sgn
			rot = sgn * DIAGONAL * flip
	_make_room(str(v.get("uid")))
	_add(v, plan, variant, rot, flip, float(plan.get("size", 1.0)), off, 0.0)
	if crossed and shape == "slash":
		var second := "slash1" if variant == "slash0" else "slash0"
		_add(v, plan, second, rot + CROSS_TURN * flip, flip, float(plan.get("size", 1.0)) * 0.9, off, -CROSS_DELAY)
	queue_redraw()


func _add(v: Node2D, plan: Dictionary, shape: String, rot: float, flip: float, size_k: float, off: Vector2, t0: float) -> void:
	var tex: Texture2D = SHEETS[shape][0]
	var fw := float(tex.get_width()) / float(SHEETS[shape][1])
	_items.append({"kind": shape, "view": weakref(v), "off": off, "rot": rot, "s": size_k * float(v.call("body_height")) / fw,
		"flip": flip, "t": t0, "frames": plan.get("frames", [0, 1, 2, 3, 4, 5]), "step": float(plan.get("step", 0.028)),
		"hold": float(plan.get("hold", 0.05)), "lift": float(plan.get("lift", 0.1)),
		"key": plan.get("key", Color.WHITE), "back": plan.get("back", Color.BLACK), "offset": plan.get("offset", Vector2(3, 2)),
		"settle": bool(plan.get("settle", false)), "uid": str(v.get("uid"))})


## A rubber stamp pressed across unit `v` (EXECUTED: tools/textures/stamp_print.py) in `key` ink: one plate
## (a stamp prints once, in register), across her shoulders, tilted; it holds, then lifts. The battle keeps
## a stamp layer over the heroines, so one standing in front never hides it.
func stamp(v: Node2D, key: Color, word: String = "executed") -> void:
	if v == null or not SHEETS.has(word):
		return
	_make_room(str(v.get("uid")))
	var tex: Texture2D = SHEETS[word][0]
	var fw := float(tex.get_width()) / float(SHEETS[word][1])
	var plan := STAMP_PLAN.duplicate()
	if not Kit.motion_ok():
		plan.frames = [2]
	_items.append({"kind": word, "view": weakref(v), "off": Vector2(0, -0.12 * float(v.call("body_height"))),
		"rot": STAMP_TILT + _rng.randf_range(-0.04, 0.04), "s": STAMP_W * float(v.call("body_height")) / fw, "flip": 1.0,
		"t": 0.0, "frames": plan.frames, "step": float(plan.step), "hold": float(plan.hold), "lift": float(plan.lift),
		"key": key, "back": Color(0, 0, 0, 0), "offset": Vector2.ZERO, "settle": false, "uid": str(v.get("uid"))})
	queue_redraw()


## A shot of ink in flight from `src`'s hand to `dst`'s chest over `dur` seconds (re-read every frame):
## one plate, stretched along its flight (the register shows on the splat it prints).
func droplet(src: Node2D, dst: Node2D, dur: float, key: Color) -> void:
	if src == null or dst == null:
		return
	var toward_camera := str(dst.get("side")) == "ally"
	_items.append({"kind": "droplet", "src": weakref(src), "view": weakref(dst), "t": 0.0, "dur": maxf(dur, 0.05),
		"key": key, "back": Color(0, 0, 0, 0), "offset": Vector2.ZERO,
		"s0": 0.55 if toward_camera else 1.0, "s1": 1.0 if toward_camera else 0.55, "uid": ""})
	queue_redraw()


## A blot where unit `v` stands (blot layers only): an ink stain that stays for the fight; the oldest
## goes past six.
func blot(v: Node2D, scale_k: float = 1.0) -> void:
	if v == null:
		return
	var count := 0
	for it in _items:
		if it.kind == "blot":
			count += 1
	if count >= MAX_BLOTS:
		for i in _items.size():
			if _items[i].kind == "blot":
				_items.remove_at(i)
				break
	var h := float(v.call("body_height"))
	var fw := float((SHEETS.blot[0] as Texture2D).get_width())
	_items.append({"kind": "blot", "at": to_local(v.global_position), "s": 0.9 * h / fw * scale_k, "t": 0.0,
		"key": Color("141517"), "back": Color(0, 0, 0, 0), "offset": Vector2.ZERO, "rot": _rng.randf_range(-0.08, 0.08)})
	queue_redraw()


func clear() -> void:
	_items.clear()
	queue_redraw()


## Live prints now (tests and the caps).
func live() -> int:
	return _items.size()


## At most `cap` live and 2 on one unit: the oldest is dropped.
func _make_room(uid: String) -> void:
	var on_unit := 0
	for it in _items:
		if str(it.get("uid", "")) == uid:
			on_unit += 1
	if on_unit >= 2:
		for i in _items.size():
			if str(_items[i].get("uid", "")) == uid:
				_items.remove_at(i)
				break
	var n := 0
	for it in _items:
		if it.kind != "droplet" and it.kind != "blot":
			n += 1
	if n >= cap:
		for i in _items.size():
			if _items[i].kind != "droplet" and _items[i].kind != "blot":
				_items.remove_at(i)
				break


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	var moving := false
	var i := 0
	while i < _items.size():
		var it := _items[i]
		var done := false
		match str(it.kind):
			"blot":
				if float(it.t) < 0.08:
					moving = true
					if not paused:
						it.t = float(it.t) + delta
			"droplet":
				moving = true
				if not paused:
					it.t = float(it.t) + delta
				done = float(it.t) >= float(it.dur) or (it.view as WeakRef).get_ref() == null or (it.src as WeakRef).get_ref() == null
			_:
				moving = true
				if not paused:
					it.t = float(it.t) + delta
				var fr: Array = it.frames
				done = float(it.t) >= fr.size() * float(it.step) + float(it.hold) + float(it.lift) or (it.view as WeakRef).get_ref() == null
		if done:
			_items.remove_at(i)
		else:
			i += 1
	# Blots only move while they spread; then the layer is still (no redraw every frame).
	if moving or _items.is_empty():
		queue_redraw()


func _draw() -> void:
	for it in _items:
		var kind := str(it.kind)
		if float(it.t) < 0.0:
			continue
		var sheet: Array = SHEETS[kind]
		var tex: Texture2D = sheet[0]
		var cols := int(sheet[1])
		var nfr := int(sheet[2])
		var fw := float(tex.get_width()) / cols
		var fh := float(tex.get_height()) / ceilf(float(nfr) / cols)
		var pos := Vector2.ZERO
		var rot := 0.0
		var sc := Vector2.ONE
		var frame := 0
		var lift := 0.0
		var off: Vector2 = it.offset
		match kind:
			"blot":
				pos = it.at
				rot = float(it.rot)
				sc = Vector2.ONE * float(it.s) * (0.7 + 0.3 * minf(float(it.t) / 0.08, 1.0))
			"droplet":
				var a: Node2D = (it.src as WeakRef).get_ref()
				var b: Node2D = (it.view as WeakRef).get_ref()
				if a == null or b == null:
					continue
				var p0 := to_local(a.call("hand_global"))
				var p1 := to_local(b.call("chest_global"))
				var k := clampf(float(it.t) / float(it.dur), 0.0, 1.0)
				var arc := minf(60.0, p0.distance_to(p1) * 0.15)
				pos = p0.lerp(p1, k) + Vector2(0, -arc * 4.0 * k * (1.0 - k))
				var vel := (p1 - p0) + Vector2(0, -arc * 4.0 * (1.0 - 2.0 * k))
				rot = vel.angle()
				frame = int(float(it.t) / 0.04) % 4
				var s := lerpf(float(it.s0), float(it.s1), k) * 0.7
				# Stretched along its flight: most at mid-flight.
				sc = Vector2(s * lerpf(1.0, 2.2, sin(k * PI)), s)
			_:
				var v: Node2D = (it.view as WeakRef).get_ref()
				if v == null:
					continue
				pos = to_local(v.call("chest_global")) + (it.off as Vector2)
				rot = float(it.rot)
				sc = Vector2(float(it.s) * float(it.flip), float(it.s))
				var fr: Array = it.frames
				var step := float(it.step)
				var idx := mini(int(float(it.t) / step), fr.size() - 1)
				frame = int(fr[idx])
				var lift_at := fr.size() * step + float(it.hold)
				lift = clampf((float(it.t) - lift_at) / maxf(float(it.lift), 0.001), 0.0, 1.0)
				if bool(it.settle):
					off = off.lerp(SETTLED, clampf(float(it.t) / 0.05, 0.0, 1.0))
				elif idx < 2:
					# The stamp frames: out of register by twice as much, then it seats.
					off *= 2.0
		var src := Rect2((frame % cols) * fw, floorf(float(frame) / cols) * fh, fw, fh)
		var rect := Rect2(-fw * 0.5, -fh * 0.5, fw, fh)
		var back: Color = it.back
		var key: Color = it.key
		if back.a > 0.0:
			draw_set_transform(pos + off, rot, sc)
			draw_texture_rect_region(tex, rect, src, Color(back.r, back.g, back.b, 1.0 - lift))
		draw_set_transform(pos, rot, sc)
		draw_texture_rect_region(tex, rect, src, Color(key.r, key.g, key.b, 1.0 - lift))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
