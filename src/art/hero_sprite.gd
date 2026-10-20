class_name HeroSprite
extends Node2D
## Animated battle/stage character (HeroArt.make_sprite). Wraps a RigPlayer.
## Feet at the node origin. At scale 1 the character is battle size: the 2048-unit rig
## canvas maps to BASE_SCALE (figure ~275 px tall). Scale the node freely for other sizes.
## Faces right by default; set_facing(-1) mirrors it.
##
## Signals: anim_event(name) - "hit" on the impact frame (damage numbers, projectiles),
## "release" when a spell leaves the hand, "step"/"land" for sounds; anim_finished(name);
## vfx_requested(kind, global_pos, facing) for animation events named "vfx_<kind>" - the battle
## screen spawns the effect (kinds: slash, thrust, bolt, burst, sparkle, charge, dissolve).
##
## Legendary heroes wear a holographic foil in every look (holo; src/art/holo_foil.gdshader): a
## rainbow film, a glare sweep and glitter on her glossy materials that move with the phone's tilt,
## wherever she is shown large. Battle units turn it off (unit_view.gd).

signal anim_event(name: String)
signal anim_finished(name: String)
signal vfx_requested(kind: String, global_pos: Vector2, facing: int)

const BASE_SCALE := 0.145
const FALLBACK_RIG := "_silhouette"
const LUNGE_STOP := 120.0       ## px (node space) a melee lunge stops short of the target
const BOSS_SCALE := 1.3
const HOLO_SHADER := preload("res://src/art/holo_foil.gdshader")
## Foil weight per bone (by name; others 1.0): never the face, little on hair and the head (hair,
## not headgear, is most of it), softer on big feathered wings, so the foil sits on her outfit,
## armour and weapon.
const HOLO_BONE_FOIL := {"face": 0.0, "head": 0.45, "neck": 0.7}
const HOLO_HAIR_FOIL := 0.3
const HOLO_WING_FOIL := 0.6

var hero_id := ""
var role := ""
var faction := ""
var rig: RigPlayer
var is_dead := false
var facing := 1
var is_fallback := false

var _body: Node2D
var _shadow: Sprite2D
var _aura_back: Sprite2D
var _lunge_vec := Vector2.ZERO
var _boss := false
var _echo := false
var _t := 0.0
var _hit_flash := 0.0
var _holo_on := false          ## the foil shader is on the rig
var _holo_motion := -1.0       ## motion uniform last sent (Reduce motion holds it at 0)

## Holographic foil on her art (holo_foil.gdshader). setup() turns it on for Legendary heroes, in
## every look; set it false where she is small or busy (battle units). Warp rigs only.
## Idle gestures (the rig's meta "idle_gestures": animation names): while she idles, one plays on
## the overlay track every 9-16 s (a wing stretch, a sway to a beat ...), so a lobby idle never
## visibly loops. Rigs without the list are unaffected.
var idle_gestures := true
var _gesture_t := 7.0

var holo := false:
	set(v):
		holo = v
		_apply_holo()

static var _shadow_tex: Texture2D
## Debug (main.gd --holo-debug=N; tuning only): 1 shows the foil's masks, 2 what the foil adds.
static var holo_debug := 0


## Builds the sprite for `id` (a HeroData id). Unknown art falls back to a faction-tinted
## silhouette rig, so every hero animates with the shared animations.
## skin_art: a skin's art folder (data/skins.json "art"), or "" for the base look.
func setup(id: String, skin_art: String = "") -> void:
	hero_id = id
	var def := HeroData.get_def(id)
	role = str(def.get("role", "striker"))
	faction = str(def.get("faction", "celestial"))
	_body = Node2D.new()
	_body.name = "Body"
	_body.scale = Vector2(BASE_SCALE, BASE_SCALE)
	add_child(_body)
	if _shadow_tex == null:
		_shadow_tex = _make_shadow_tex()
	_aura_back = Sprite2D.new()
	_aura_back.texture = _shadow_tex
	_aura_back.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_aura_back.material = add
	_body.add_child(_aura_back)
	_shadow = Sprite2D.new()
	_shadow.texture = _shadow_tex
	_shadow.modulate = Color(0.02, 0.0, 0.06, 0.55)
	_shadow.scale = Vector2(5.2, 1.1)
	_body.add_child(_shadow)
	rig = RigPlayer.new()
	rig.name = "Rig"
	var data := RigData.load_rig(id, skin_art) if skin_art != "" else null
	if data == null:
		data = RigData.load_rig(id)
	if data == null:
		data = RigData.load_rig(FALLBACK_RIG)
		is_fallback = true
	if data == null:
		push_error("HeroSprite: no rig for %s and no fallback rig built" % id)
		return
	_body.add_child(rig)
	rig.setup(data)
	rig.hero_id = id if not is_fallback else FALLBACK_RIG
	rig.fx_color = _fx_color()
	if is_fallback:
		var fc := HeroArt.faction_color(faction)
		rig.set_tint(&"map_on", 1.0)
		rig.set_tint(&"map_dark", Color("0d0a1c"))
		rig.set_tint(&"map_mid", fc.darkened(0.4))
		rig.set_tint(&"map_light", fc.lightened(0.35))
	rig.anim_event.connect(_on_event)
	rig.anim_finished.connect(_on_finished)
	holo = not is_fallback and str(def.get("rarity", "")) == "legendary"
	play_idle()


## Puts the foil shader on the rig (or takes it off) with her face ellipse and the per-bone weights.
func _apply_holo() -> void:
	var want := holo and rig != null and rig.rig != null and rig.rig.kind == "warp" and not is_fallback
	if want == _holo_on:
		return
	if rig == null or not rig.set_warp_shader(HOLO_SHADER if want else null):
		_holo_on = false
		return
	_holo_on = want
	_holo_motion = -1.0
	if not want:
		return
	var rd := rig.rig
	var w := PackedFloat32Array()
	w.resize(RigPlayer.MAX_WARP_BONES)
	for i in w.size():
		w[i] = 1.0
		if i < rd.bone_names.size():
			var n := rd.bone_names[i]
			if HOLO_BONE_FOIL.has(n):
				w[i] = float(HOLO_BONE_FOIL[n])
			elif n.begins_with("hair") or n in ["ponytail", "braid", "bangs"]:
				w[i] = HOLO_HAIR_FOIL
			elif n.begins_with("wing"):
				w[i] = HOLO_WING_FOIL
	rig.set_warp_param(&"bone_foil", w)
	rig.set_warp_param(&"face_ellipse", rd.face_ellipse())
	rig.set_warp_param(&"debug_view", holo_debug)
	_sync_holo_motion()


## Reduce motion (the setting) holds the foil still and gentle; checked every frame (cheap).
func _sync_holo_motion() -> void:
	var m := 1.0 if Kit.motion_ok() else 0.0
	if m != _holo_motion:
		_holo_motion = m
		rig.set_warp_param(&"motion", m)


func _fx_color() -> Color:
	var m: Dictionary = rig.rig.meta if rig and rig.rig else {}
	if m.has("fx_color"):
		return Color(str(m.fx_color))
	return HeroArt.faction_color(faction).lightened(0.25)


# ------------------------------------------------------------------ actions

func play_idle() -> void:
	if rig == null or is_dead:
		return
	rig.play(_anim("idle"), 0)
	rig.stop(1, 0.15)


## Attack the unit standing at `target_global_pos`. Melee roles lunge toward it (the lunge
## timing comes from the animation). Returns the animation name; listen for anim_event("hit").
func play_attack(target_global_pos: Vector2) -> String:
	if rig == null or is_dead:
		return ""
	var a := attack_anim()
	var local := to_local(target_global_pos)
	var dx := local.x - signf(local.x) * LUNGE_STOP if absf(local.x) > LUNGE_STOP else 0.0
	_lunge_vec = Vector2(dx, local.y)
	rig.play(a, 1)
	return a


## Skill cast (support roles get the support cast). Returns the animation name.
func play_cast() -> String:
	if rig == null or is_dead:
		return ""
	var a := _anim("support_cast" if role == "support" else "cast")
	_lunge_vec = Vector2.ZERO
	rig.play(a, 1)
	return a


func play_ultimate(target_global_pos: Vector2 = Vector2.INF) -> String:
	if rig == null or is_dead:
		return ""
	_lunge_vec = Vector2.ZERO
	if target_global_pos != Vector2.INF and role in ["striker", "assassin", "guardian"]:
		var local := to_local(target_global_pos)
		_lunge_vec = Vector2(local.x - signf(local.x) * LUNGE_STOP if absf(local.x) > LUNGE_STOP else 0.0, local.y)
	rig.play(_anim("ultimate"), 1)
	return "ultimate"


func play_hit() -> void:
	if rig == null or is_dead:
		return
	if rig.current(1) in ["attack_melee", "attack_thrust", "ultimate"]:
		_hit_flash = 1.0    # don't interrupt our own swing; just flash
		return
	_hit_flash = 1.0
	rig.play(_anim("hit"), 1)


func play_death() -> void:
	if rig == null or is_dead:
		return
	is_dead = true
	rig.stop(1, 0.0)
	rig.play(_anim("death"), 0, 0, 0.08)


func play_victory() -> void:
	if rig == null or is_dead:
		return
	rig.stop(1, 0.1)
	rig.play(_anim("victory"), 0)


## Plays any animation by name. Looping animations replace the base (idle) track; one-shots
## play on top and return to the base when done.
func play(anim: String) -> void:
	if rig == null:
		return
	match anim:
		"idle":
			play_idle()
		"death":
			play_death()
		"hit":
			play_hit()
		"victory":
			play_victory()
		_:
			var a := RigAnim.find(_anim(anim), rig.hero_id, rig.rig.anim_kind(), rig.rig.dir)
			if a == null:
				return
			if a.loop:
				rig.play(_anim(anim), 0)
			else:
				_lunge_vec = Vector2.ZERO
				rig.play(_anim(anim), 1)


## Animation speed multiplier (battle speed 1/2/4): scales animations, events and physics.
func set_speed(mult: float) -> void:
	if rig:
		rig.speed_scale = mult


## True while an action (attack, cast, hit...) is still playing on top of idle.
func is_busy() -> bool:
	return rig != null and rig.is_playing(1)


## Resting expression, e.g. set_expression("eyes", "open"); "" restores the hero's default.
## Overlay slots: "eyes" (open/closed/smile/hurt), "mouth" (default/open/smile/hurt).
func set_expression(slot: String, variant: String) -> void:
	if rig:
		rig.set_expression(slot, variant)


func attack_anim() -> String:
	var m: Dictionary = rig.rig.meta if rig and rig.rig else {}
	if m.has("attack") and not is_fallback:
		return str(m.attack)
	match role:
		"caster":
			return "attack_ranged"
		"support":
			return "attack_ranged"
		_:
			var w := str(m.get("weapon", ""))
			return "attack_thrust" if w == "spear" else "attack_melee"


func _anim(a: String) -> String:
	return a


# ------------------------------------------------------------------ looks

func set_facing(dir: int) -> void:
	facing = -1 if dir < 0 else 1
	_apply_scale()


## Enemy "echo" look: desaturated with violet shadows.
func set_echo(on: bool) -> void:
	_echo = on
	if rig == null:
		return
	rig.set_tint(&"desat", 0.5 if on else 0.0)
	rig.set_tint(&"shade", 0.7 if on else 0.0)
	rig.fx_color = Color("b48cff") if on else _fx_color()


func set_boss(on: bool) -> void:
	_boss = on
	_apply_scale()
	_aura_back.visible = on
	if on:
		_aura_back.modulate = Color(HeroArt.faction_color(faction) if not _echo else Color("9a5cff"), 0.5)


func _apply_scale() -> void:
	if _body == null:
		return
	var s := BASE_SCALE * (BOSS_SCALE if _boss else 1.0)
	_body.scale = Vector2(s * facing, s)


## Global position of a body point, for effects: "chest" (hit point), "head", "weapon".
func get_point(which: String) -> Vector2:
	if rig == null:
		return global_position
	match which:
		"weapon":
			return rig.to_global(rig.get_weapon_tip())
		"head":
			return rig.get_bone_global_position("head")
		_:
			return rig.get_bone_global_position("chest")


## Approximate on-screen height in px at the current scale.
## Her outline (the art's alpha bounds) in this node's local units, feet at the origin, at the
## current scale: what a view must fit to show her whole (HeroArt.fit_sprite). `core`: only her
## body, without the wings, tail, weapon, cape and ribbons a full-screen view may cut
## (RigData.core_rect).
func figure_rect(core: bool = false) -> Rect2:
	var unit := absf(_body.scale.y) * absf(scale.y)
	if rig == null or rig.rig == null or rig.rig.image == null:
		var h := get_height()
		return Rect2(-h * 0.16, -h, h * 0.32, h)
	var rd := rig.rig
	var r: Rect2
	if core:
		r = rd.core_rect()
	else:
		var u := HeroArt.used_rect(rd.image)
		var sx := rd.canvas.x / maxf(float(rd.image.get_width()), 1.0)
		var sy := rd.canvas.y / maxf(float(rd.image.get_height()), 1.0)
		r = Rect2(u.position.x * sx - rd.origin.x, u.position.y * sy - rd.origin.y, u.size.x * sx, u.size.y * sy)
	if facing < 0:
		r.position.x = -r.end.x
	return Rect2(r.position * unit, r.size * unit)


func get_height() -> float:
	var h := 1900.0
	if rig and rig.rig:
		h = -rig.rig.bounds.position.y
	return h * absf(_body.scale.y) * absf(scale.y)


func _on_finished(n: String) -> void:
	anim_finished.emit(n)


func _on_event(n: String) -> void:
	anim_event.emit(n)
	if n.begins_with("vfx_"):
		var kind := n.substr(4)
		vfx_requested.emit(kind, vfx_point(kind), facing)


## Where an effect of `kind` should appear (global position).
func vfx_point(kind: String) -> Vector2:
	match kind:
		"bolt", "charge", "burst":
			return get_point("weapon")
		"sparkle":
			return get_point("head")
		"slash", "thrust":
			var c := get_point("chest")
			return c + Vector2(facing * get_height() * 0.35, 0.0)
		_:
			return get_point("chest")


func _process(delta: float) -> void:
	if rig == null:
		return
	_t += delta
	_body.position = _lunge_vec * rig.lunge
	if idle_gestures and not is_dead and rig.current(0) == _anim("idle") and not rig.is_playing(1):
		_gesture_t -= delta
		if _gesture_t <= 0.0:
			_gesture_t = randf_range(9.0, 16.0)
			var gl: Variant = rig.rig.meta.get("idle_gestures", []) if rig.rig else []
			if gl is Array and not (gl as Array).is_empty():
				rig.play(str((gl as Array)[randi() % (gl as Array).size()]), 1)
	if _holo_on:
		_sync_holo_motion()
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 6.0)
		rig.set_tint(&"flash", _hit_flash * 0.65)
		rig.set_tint(&"flash_color", Color(1, 1, 1))
	if _boss:
		var k := 0.5 + 0.5 * sin(_t * 2.6)
		_aura_back.position = Vector2(0, -900)
		_aura_back.scale = Vector2(9.0 + k, 13.0 + k)
		_aura_back.modulate.a = 0.28 + 0.14 * k


static func _make_shadow_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
