extends RefCounted
## The plan for one blow on the field (pure: no nodes, so it is unit-tested; tests/unit/test_hit_plan.gd).
## battle_screen._on_damage asks plan(hit, ctx) and carries it out: PressLayer prints the impression,
## the Galley sets the number, UnitView takes the impact frame and the knock, the screen stops and
## kicks, UI plays the sounds and the haptic.
##
## Every blow is a print pulled on the field: one Blender-rendered ink impression on the struck body
## (a dry-brush stroke for a slash, a jab for a thrust, a splat for a shot, two strokes crossed for a
## crit), its key plate over a second plate a few pixels out of
## register: paper over ink (paper reads on the dark street). Signal only on the camera's heroine's
## crit. Nothing is printed on a heroine: her blows dock on her card (Galley).
## hit: {kind ("melee", "thrust", "assassin", "ranged"), on_ally, crit, adv, kill, last_foe, heavy_bp
##   (the damage over her max HP, basis points), absorbed, support, src_uid, dst_uid}.
## ctx: {speed (1, 2, 4), motion (Kit.motion_ok), pro (DeviceTier.pro), focus (the blow is the camera's:
##   by the heroine it follows), champion, now (real ms), gov (the governor's state, kept by the caller
##   and changed here)}.

const PAPER := Color("e9e8e2")
const INK := Color("141517")
const SIG := Color("ff5c29")

## Per battle speed: frame step (s), the frames shown, hold after the last frame (s), lift (s),
## micro stop on the camera's blows (s), a crit's stop (s), knock (basic, crit, px), camera kick px.
const SPEEDS := {
	1: {"step": 0.028, "frames": [0, 1, 2, 3, 4, 5], "hold": 0.14, "lift": 0.12, "stop": 0.033, "crit_stop": 0.06,
		"knock": 8.0, "knock_crit": 14.0, "kick": 2.0, "thump": 4.0},
	2: {"step": 0.02, "frames": [0, 1, 2, 3, 4, 5], "hold": 0.09, "lift": 0.1, "stop": 0.017, "crit_stop": 0.045,
		"knock": 6.0, "knock_crit": 10.0, "kick": 0.0, "thump": 3.0},
	4: {"step": 0.016, "frames": [0, 2, 4, 5], "hold": 0.05, "lift": 0.08, "stop": 0.0, "crit_stop": 0.0,
		"knock": 0.0, "knock_crit": 6.0, "kick": 0.0, "thump": 0.0},
}
## Off the camera: a smaller print and fewer frames, no stop, a small knock.
const OFF_FRAMES := [0, 2, 4, 5]
## The governor: impact frames at most 3 a second on the whole field and 330 ms apart on one unit;
## at most 8 haptics a second.
const FLIPS_PER_S := 3
const FLIP_GAP_MS := 330
const HAPTICS_PER_S := 8
## A blow on a heroine of at least this much of her HP (basis points) jolts her out of register.
const HEAVY_BP := 800
const FELT_BP := 500
const JOLT_GAP_MS := 1200


static func new_gov() -> Dictionary:
	return {"flips": [], "unit_flip": {}, "haptics": [], "jolt": {}, "haptic_at": -1000, "tick_at": -1000}


static func plan(hit: Dictionary, ctx: Dictionary) -> Dictionary:
	var speed := int(ctx.get("speed", 1))
	var sp: Dictionary = SPEEDS.get(speed, SPEEDS[1])
	var motion := bool(ctx.get("motion", true))
	var focus := bool(ctx.get("focus", false))
	var champion := bool(ctx.get("champion", false))
	var now := int(ctx.get("now", 0))
	var gov: Dictionary = ctx.get("gov", new_gov())
	var on_ally := bool(hit.get("on_ally", false))
	var crit := bool(hit.get("crit", false))
	var adv := bool(hit.get("adv", false))
	var kill := bool(hit.get("kill", false))
	var kind := str(hit.get("kind", "melee"))
	var p := {
		"impress": _shape(kind), "size": 1.0, "frames": (sp.frames as Array).duplicate(), "step": float(sp.step),
		"hold": float(sp.hold), "lift": float(sp.lift), "key": PAPER, "back": INK, "offset": Vector2(5, 4),
		"settle": false, "flip": 0, "flip_dark": INK, "flip_light": PAPER, "ink_take": true, "jolt": false,
		"stop": 0.0, "knock": 0.0, "kick": 0.0, "thump": 0.0, "sounds": [], "haptic": [], "slab": false,
		"react": true,
	}
	# A stroke crosses her whole body (it reads at phone size); a splat sits on her.
	if bool(hit.get("support", false)):
		p.size = 0.75 * 0.8
	elif kind == "ranged":
		p.size = 0.75
	else:
		p.size = 1.35
	if on_ally:
		return _on_heroine(p, hit, ctx, sp, gov, now)

	# A blow on an echo. Signal is spent once: on the camera's heroine's crit (its second plate, its
	# impact frame's lights, its slab); an advantage hit only clacks.
	if bool(hit.get("absorbed", false)):
		# A dry print: the shield took it all, nothing got through.
		p.back = Color(0, 0, 0, 0)
	if crit and not champion:
		# A crit crosses her: two strokes as an X (a splat for a shot). The ultimate keeps its crown.
		p.impress = "splat" if kind == "ranged" else "cross"
		p.size = (1.0 if kind == "ranged" else 1.1) * (1.0 if focus else 0.8)
		p.offset = Vector2(7, 5)
		p.settle = true
		p.knock = float(sp.knock_crit) * (1.0 if focus else 0.5)
		if focus:
			p.back = SIG
			p.slab = true
			p.stop = float(sp.crit_stop)
			p.thump = float(sp.thump)
			p.flip_light = SIG
			p.sounds = [["stamp", 1.05, 0.0, 0.0], ["clack", 1.3, 0.0, 0.03]]
			_haptic(p, gov, now, 14, 0.45, 250)
		else:
			p.sounds = [["stamp", 1.05, -6.0, 0.0]]
		if _take_flip(gov, str(hit.get("dst_uid", "")), now, true):
			p.flip = 3 if speed < 4 else 2
	elif crit:
		# The Champion: the whole team crits all the time. The number still gets its signal slab.
		p.slab = true
		p.sounds = [["press", 1.0, -2.0, 0.0]]
	elif focus:
		p.stop = float(sp.stop)
		p.knock = float(sp.knock)
		p.kick = float(sp.kick)
		if speed < 4 and _take_flip(gov, str(hit.get("dst_uid", "")), now, false):
			p.flip = 2
		var pitch := {"thrust": 0.85, "assassin": 1.12}.get(kind, 1.0) as float
		p.sounds = [["splat" if kind == "ranged" else "press", pitch, 0.0, 0.0]]
		_haptic(p, gov, now, 6, 0.18, 120)
	else:
		p.size *= 0.75
		p.frames = OFF_FRAMES.duplicate()
		p.knock = float(sp.knock) * 0.5
		p.sounds = [["splat" if kind == "ranged" else "press", 1.0, -7.0, 0.0]]
	if adv and not crit:
		p.sounds.append(["clack", 1.8, -4.0, 0.0])
	if kill:
		p.stop = maxf(float(p.stop), 0.14 if bool(hit.get("last_foe", false)) else 0.09)
		# (After any crit stamp: the same sound within 45 ms is skipped.)
		p.sounds.append(["stamp", 0.8, 0.0, 0.05])
		p.sounds.append(["peel", 1.0, 0.0, 0.16])
		_haptic(p, gov, now, 22, 0.6, 0)
	if not motion:
		_calm(p)
	return p


## A blow on a heroine: nothing is printed on her painting (her number docks on her card). Only the
## blows she feels (5% of her HP or more, a crit, the last one) make her flinch, dip in ink and
## knock; a heavy blow or a crit also jolts her out of register, at most every 1.2 s.
static func _on_heroine(p: Dictionary, hit: Dictionary, ctx: Dictionary, _sp: Dictionary, gov: Dictionary, now: int) -> Dictionary:
	var crit := bool(hit.get("crit", false))
	var heavy := int(hit.get("heavy_bp", 0))
	var kill := bool(hit.get("kill", false))
	p.impress = ""
	p.react = crit or kill or heavy >= FELT_BP
	p.knock = 4.0 if bool(p.react) and int(ctx.get("speed", 1)) < 4 else 0.0
	p.sounds = [["hit", 0.9, -4.0 if heavy >= HEAVY_BP else -8.0, 0.0]]
	if crit:
		p.sounds = [["stamp", 0.95, -2.0, 0.0]]
		_haptic(p, gov, now, 18, 0.55, 250)
	elif heavy >= FELT_BP:
		_haptic(p, gov, now, 10, 0.3, 250)
	if crit or heavy >= HEAVY_BP:
		var uid := str(hit.get("dst_uid", ""))
		if now - int((gov.jolt as Dictionary).get(uid, -100000)) >= JOLT_GAP_MS:
			gov.jolt[uid] = now
			p.jolt = true
	if kill:
		p.stop = 0.12
		p.flip = 3
		p.flip_light = SIG
		p.sounds = [["stamp", 0.7, 1.0, 0.0], ["peel", 0.8, -2.0, 0.05]]
		p.haptic = []
		_haptic(p, gov, now, 40, 0.8, 0)
	if not bool(ctx.get("motion", true)):
		_calm(p)
	return p


## A haptic from outside a blow (a shield, a debuff landing on a heroine), through the same
## governor: [ms, amplitude] to play, or [] when the field's budget or the gap says no.
static func haptic(gov: Dictionary, now: int, ms: int, amp: float, gap: int) -> Array:
	var p := {"haptic": []}
	_haptic(p, gov, now, ms, amp, gap)
	return p.haptic


## Reduce motion: the print fades in at its last frame and out, nothing stops, jolts or knocks.
static func _calm(p: Dictionary) -> void:
	p.frames = [5]
	p.step = 0.06
	p.hold = 0.2
	p.lift = 0.15
	p.stop = 0.0
	p.kick = 0.0
	p.thump = 0.0
	p.knock = 0.0
	p.flip = 0
	p.jolt = false
	p.settle = false
	if not p.haptic.is_empty():
		p.haptic = [int(p.haptic[0]), float(p.haptic[1]) * 0.7]


static func _shape(kind: String) -> String:
	match kind:
		"thrust":
			return "thrust"
		"ranged":
			return "splat"
	return "slash"


## An impact frame for unit `uid` now, if the governor allows: at most FLIPS_PER_S on the whole field
## in any second, and FLIP_GAP_MS apart on one unit (a crit skips the per-unit gap, not the cap).
static func _take_flip(gov: Dictionary, uid: String, now: int, priority: bool) -> bool:
	var flips: Array = gov.flips
	while not flips.is_empty() and now - int(flips[0]) >= 1000:
		flips.pop_front()
	if flips.size() >= FLIPS_PER_S:
		return false
	if not priority and now - int((gov.unit_flip as Dictionary).get(uid, -100000)) < FLIP_GAP_MS:
		return false
	flips.append(now)
	gov.unit_flip[uid] = now
	return true


## A haptic, if no other fired within `gap` ms and the field's 8 a second aren't used up.
static func _haptic(p: Dictionary, gov: Dictionary, now: int, ms: int, amp: float, gap: int) -> void:
	var hs: Array = gov.haptics
	while not hs.is_empty() and now - int(hs[0]) >= 1000:
		hs.pop_front()
	if hs.size() >= HAPTICS_PER_S or now - int(gov.haptic_at) < gap:
		return
	hs.append(now)
	gov.haptic_at = now
	p.haptic = [ms, amp]
