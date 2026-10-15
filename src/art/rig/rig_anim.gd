class_name RigAnim
extends RefCounted
## One HaloRig animation (assets/art/anim/<name>.anim.json), compiled for fast sampling.
## Format and easing math: docs/dev/halorig.md section 5. Shared by every hero; a hero may
## override any animation with assets/art/heroes/<id>/anim/<name>.anim.json.

const SHARED_DIR := "res://assets/art/anim/"
const HEROES_DIR := "res://assets/art/heroes/"

enum { E_LINEAR, E_STEP, E_SINE_IN, E_SINE_OUT, E_SINE_IN_OUT, E_QUAD_IN, E_QUAD_OUT,
	E_QUAD_IN_OUT, E_CUBIC_IN, E_CUBIC_OUT, E_CUBIC_IN_OUT, E_QUINT_OUT, E_EXPO_OUT,
	E_BACK_IN, E_BACK_OUT, E_BACK_IN_OUT, E_ELASTIC_OUT }

const EASE_NAMES := {
	"linear": E_LINEAR, "step": E_STEP, "sine_in": E_SINE_IN, "sine_out": E_SINE_OUT,
	"sine_in_out": E_SINE_IN_OUT, "quad_in": E_QUAD_IN, "quad_out": E_QUAD_OUT,
	"quad_in_out": E_QUAD_IN_OUT, "cubic_in": E_CUBIC_IN, "cubic_out": E_CUBIC_OUT,
	"cubic_in_out": E_CUBIC_IN_OUT, "quint_out": E_QUINT_OUT, "expo_out": E_EXPO_OUT,
	"back_in": E_BACK_IN, "back_out": E_BACK_OUT, "back_in_out": E_BACK_IN_OUT,
	"elastic_out": E_ELASTIC_OUT,
}


## A keyframed curve with `dim` floats per key. Ease on key i shapes the segment i -> i+1.
class Timeline:
	var dim := 1
	var times := PackedFloat32Array()
	var values := PackedFloat32Array()
	var eases := PackedInt32Array()

	func _seg(t: float) -> int:
		var n := times.size()
		if t <= times[0]:
			return -1
		if t >= times[n - 1]:
			return n - 1
		var i := 0
		while i < n - 1 and times[i + 1] <= t:
			i += 1
		return i

	func _alpha(i: int, t: float) -> float:
		var t0 := times[i]
		var t1 := times[i + 1]
		var x := (t - t0) / maxf(t1 - t0, 0.00001)
		return RigAnim.ease_value(eases[i], x)

	func sample1(t: float) -> float:
		var i := _seg(t)
		if i < 0:
			return values[0]
		if i >= times.size() - 1:
			return values[i]
		return lerpf(values[i], values[i + 1], _alpha(i, t))

	func sample2(t: float) -> Vector2:
		var i := _seg(t)
		if i < 0:
			return Vector2(values[0], values[1])
		if i >= times.size() - 1:
			return Vector2(values[i * 2], values[i * 2 + 1])
		var a := _alpha(i, t)
		return Vector2(lerpf(values[i * 2], values[i * 2 + 2], a), lerpf(values[i * 2 + 1], values[i * 2 + 3], a))

	func sample4(t: float) -> Color:
		var i := _seg(t)
		var j := maxi(i, 0) * 4
		if i < 0 or i >= times.size() - 1:
			return Color(values[j], values[j + 1], values[j + 2], values[j + 3])
		var a := _alpha(i, t)
		return Color(lerpf(values[j], values[j + 4], a), lerpf(values[j + 1], values[j + 5], a),
			lerpf(values[j + 2], values[j + 6], a), lerpf(values[j + 3], values[j + 7], a))


var name := ""
var duration := 1.0
var loop := false
var loop_start := 0.0     ## after the first pass, a looping anim repeats [loop_start, duration]
var hold := false         ## non-looping: keep the last frame instead of fading out (death)
var mix := 0.1            ## default crossfade (s) when this animation starts
var mix_out := 0.15       ## fade-out (s) when a non-looping overlay ends
var bones := {}           ## bone -> {"rotate": TL1, "translate": TL2, "scale": TL2, "bend": TL1}
var slots := {}           ## slot -> {"attachment": [[t, variant]...], "color": TL4}
var look: Timeline = null ## head-turn channel, x/y in -1..1
var fx := {}              ## fx name -> TL1 ("glow", "hand_glow", "aura", "flash", "trail")
var lunge: Timeline = null ## 0..1 share of the attack lunge (HeroSprite moves toward the target)
var events: Array = []    ## [[t, name], ...] sorted by t

static var _cache := {}


static func ease_value(e: int, x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	match e:
		E_LINEAR:
			return x
		E_STEP:
			return 0.0 if x < 1.0 else 1.0
		E_SINE_IN:
			return 1.0 - cos(x * PI * 0.5)
		E_SINE_OUT:
			return sin(x * PI * 0.5)
		E_SINE_IN_OUT:
			return -(cos(PI * x) - 1.0) * 0.5
		E_QUAD_IN:
			return x * x
		E_QUAD_OUT:
			return 1.0 - (1.0 - x) * (1.0 - x)
		E_QUAD_IN_OUT:
			return 2.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) * 0.5
		E_CUBIC_IN:
			return x * x * x
		E_CUBIC_OUT:
			return 1.0 - pow(1.0 - x, 3.0)
		E_CUBIC_IN_OUT:
			return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5
		E_QUINT_OUT:
			return 1.0 - pow(1.0 - x, 5.0)
		E_EXPO_OUT:
			return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)
		E_BACK_IN:
			return 2.70158 * x * x * x - 1.70158 * x * x
		E_BACK_OUT:
			return 1.0 + 2.70158 * pow(x - 1.0, 3.0) + 1.70158 * pow(x - 1.0, 2.0)
		E_BACK_IN_OUT:
			var c2 := 1.70158 * 1.525
			if x < 0.5:
				return (pow(2.0 * x, 2.0) * ((c2 + 1.0) * 2.0 * x - c2)) * 0.5
			return (pow(2.0 * x - 2.0, 2.0) * ((c2 + 1.0) * (x * 2.0 - 2.0) + c2) + 2.0) * 0.5
		E_ELASTIC_OUT:
			if x <= 0.0 or x >= 1.0:
				return x
			return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * (2.0 * PI / 3.0)) + 1.0
	return x


## Loads (cached) animation `anim_name`: the hero's override first, then (for warp rigs) the
## shared warp set in anim/warp/, then the shared set. Null if missing.
static func find(anim_name: String, hero_id: String = "", kind: String = "") -> RigAnim:
	var paths: Array[String] = []
	if hero_id != "":
		paths.append("%s%s/anim/%s.anim.json" % [HEROES_DIR, hero_id, anim_name])
	if kind == "warp":
		paths.append("%swarp/%s.anim.json" % [SHARED_DIR, anim_name])
	paths.append("%s%s.anim.json" % [SHARED_DIR, anim_name])
	for p in paths:
		if _cache.has(p):
			return _cache[p]
		if FileAccess.file_exists(p):
			var a := RigAnim.from_file(p)
			_cache[p] = a
			if a != null:
				return a
	return null


static func clear_cache() -> void:
	_cache.clear()


static func from_file(path: String) -> RigAnim:
	var txt := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		push_error("RigAnim: cannot parse %s" % path)
		return null
	var a := RigAnim.new()
	a._load(d, path)
	return a


static func _tl(keys: Array, kind: String, path: String) -> Timeline:
	var tl := Timeline.new()
	tl.dim = {"rotate": 1, "bend": 1, "fx": 1, "translate": 2, "scale": 2, "look": 2, "color": 4}[kind]
	var ks := keys.duplicate()
	ks.sort_custom(func(p, q): return float(p.get("t", 0.0)) < float(q.get("t", 0.0)))
	for k in ks:
		if not (k is Dictionary):
			continue
		tl.times.append(float(k.get("t", 0.0)))
		var e := str(k.get("e", "linear"))
		if not EASE_NAMES.has(e):
			push_warning("RigAnim %s: unknown ease '%s'" % [path, e])
		tl.eases.append(int(EASE_NAMES.get(e, E_LINEAR)))
		match kind:
			"rotate", "bend", "fx":
				tl.values.append(float(k.get("v", 0.0)))
			"translate", "look":
				tl.values.append(float(k.get("x", 0.0)))
				tl.values.append(float(k.get("y", 0.0)))
			"scale":
				tl.values.append(float(k.get("x", 1.0)))
				tl.values.append(float(k.get("y", 1.0)))
			"color":
				var c := Color(str(k.get("c", "ffffffff")))
				tl.values.append_array([c.r, c.g, c.b, c.a])
	if tl.times.is_empty():
		return null
	return tl


func _load(d: Dictionary, path: String) -> void:
	name = str(d.get("name", path.get_file().get_basename().get_basename()))
	duration = maxf(float(d.get("duration", 1.0)), 0.01)
	loop = bool(d.get("loop", false))
	loop_start = clampf(float(d.get("loop_start", 0.0)), 0.0, duration)
	hold = bool(d.get("hold", false))
	mix = float(d.get("mix", 0.1))
	mix_out = float(d.get("mix_out", 0.15))
	var bd: Dictionary = d.get("bones", {})
	for b in bd:
		var ch := {}
		for kind in ["rotate", "translate", "scale", "bend"]:
			if bd[b].has(kind):
				var tl := _tl(bd[b][kind], kind, path)
				if tl != null:
					ch[kind] = tl
		bones[b] = ch
	var sd: Dictionary = d.get("slots", {})
	for s in sd:
		var ch := {}
		if sd[s].has("attachment"):
			var arr: Array = []
			for k in sd[s]["attachment"]:
				arr.append([float(k.get("t", 0.0)), str(k.get("v", "default"))])
			arr.sort_custom(func(p, q): return p[0] < q[0])
			ch["attachment"] = arr
		if sd[s].has("color"):
			var tl := _tl(sd[s]["color"], "color", path)
			if tl != null:
				ch["color"] = tl
		slots[s] = ch
	if d.has("look"):
		look = _tl(d["look"], "look", path)
	var fd: Dictionary = d.get("fx", {})
	for k in fd:
		var tl := _tl(fd[k], "fx", path)
		if tl != null:
			fx[k] = tl
	if d.has("lunge"):
		lunge = _tl(d["lunge"], "fx", path)
	for e in d.get("events", []):
		events.append([float(e.get("t", 0.0)), str(e.get("name", ""))])
	events.sort_custom(func(p, q): return p[0] < q[0])


## Discrete attachment key in effect at time t ("" = not keyed yet).
static func attachment_at(keys: Array, t: float) -> String:
	var v := ""
	for k in keys:
		if k[0] <= t + 0.00001:
			v = k[1]
		else:
			break
	if v == "" and not keys.is_empty():
		v = keys[0][1]
	return v


## Time of the first event called `ev`, or -1.
func event_time(ev: String) -> float:
	for e in events:
		if e[1] == ev:
			return e[0]
	return -1.0
