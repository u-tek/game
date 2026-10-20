class_name RigPlayer
extends Node2D
## HaloRig runtime: plays a built hero rig (RigData) with keyframed animations (RigAnim),
## crossfades/track mixing, automatic blinking, spring physics for secondary motion, a bend
## shader for soft parts, pseudo-3D head turns ("look") and animation events.
## Spec: docs/dev/halorig.md. Feet are at this node's origin; 1 rig unit = 1 px at scale 1.
##
##   var rig := RigPlayer.new()
##   add_child(rig)
##   rig.setup(RigData.load_rig("seraphiel"))
##   rig.play("idle")                       # track 0, loops
##   rig.play("attack_ranged", 1)           # overlay on track 1, fades back to idle at the end
##   rig.anim_event.connect(func(n): if n == "hit": ...)

signal anim_event(name: String)
signal anim_finished(name: String)

const SHADER := preload("res://src/art/rig/rig.gdshader")
const WARP_SHADER := preload("res://src/art/rig/warp.gdshader")
const MAX_WARP_BONES := 64
const PHYS_DT := 1.0 / 60.0
const MAX_SUBSTEPS := 4
const TRACKS := 3
const BEND_GRID := Vector2i(6, 10)
const BLINK_MIN := 2.5
const BLINK_MAX := 5.0
## A blink: the lids close, hold and open again (s); the closed-eye overlay fades in and out over
## those times instead of popping (on 120 Hz screens that reads as a lid, not a cut).
const BLINK_CLOSE := 0.055
const BLINK_HOLD := 0.045
const BLINK_OPEN := 0.11
const BLINK_TIME := BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN
const HEAD_TURN_SQUASH := 0.05
## Procedural idle (format 2 rigs, docs/dev/halorig.md 11.3): what each bone does, by its name.
enum { ROLE_NONE, ROLE_HIPS, ROLE_TORSO, ROLE_CHEST, ROLE_NECK, ROLE_HEAD, ROLE_ARM, ROLE_FOREARM,
	ROLE_WING, ROLE_BREAST, ROLE_THIGH, ROLE_SHIN, ROLE_TAIL }
## Share of the procedural idle kept while an action plays over it.
const IDLE_ACTION_SHARE := 0.35

var rig: RigData
var speed_scale := 1.0
var physics_enabled := true
var blink_enabled := true
var wind := 1.0                       ## global wind multiplier (0 = still air)
var look_extra := Vector2.ZERO        ## added to the animation's look channel (-1..1)
var fx_color := Color(1.0, 0.85, 0.45)
var manual := false                   ## true: call advance(dt) yourself (previews/tests)
var hero_id := ""
## Format 2 rigs: breathing, weight shift and settling drawn procedurally (_idle_drive) while the
## base track plays "idle". idle_amount scales it (0 = still).
var idle_motion := true
var idle_amount := 1.0


class Binding:
	var rot: Array = []
	var tr: Array = []
	var sc: Array = []
	var bend: Array = []
	var keyed := PackedInt32Array()
	var att: Array = []
	var col: Array = []
	var keyed_slots := PackedInt32Array()


class Entry:
	var anim: RigAnim
	var b: Binding
	var time := 0.0
	var loop := false
	var mix_t := 0.0
	var mix_dur := 0.0
	var prev: Entry = null
	var fading := false
	var fade_t := 0.0
	var fade_dur := 0.15
	var finished_sent := false
	var started := false


var _tracks: Array = []               # Entry or null per track
var _bindings := {}                   # RigAnim -> Binding (per rig)

# per-bone state (indexed like rig.bone_names)
var _n := 0
var _rot := PackedFloat32Array()      # deg offset
var _pos := PackedVector2Array()      # translate offset (parent space)
var _scl := PackedVector2Array()
var _bend_anim := PackedFloat32Array()
var _bend_out := PackedFloat32Array() # radians applied to the shader
var _world: Array[Transform2D] = []   # rig space
var _look_on := PackedInt32Array()    # bones with a look factor
var _head := -1
var _weapon := -1

# springs
var _sp_bones := PackedInt32Array()
var _sp_p := PackedVector2Array()
var _sp_v := PackedVector2Array()
var _sp_tg := PackedVector2Array()    # last frame's target (global)
var _sp_step_tg := PackedVector2Array()
var _sp_off := PackedFloat32Array()   # last offset (rad), for debugging/previews
var _sp_ready := false
var _sp_pp := PackedVector2Array()     # position one physics step earlier: drawn between the two
var _sp_mass := PackedByteArray()      # 1: a soft mass that shifts (breasts) instead of swinging
var _phys_acc := 0.0
var _clock := 0.0
# procedural idle state
var _idle_on := false
var _idle_w := 0.0
var _br_t := 0.0                      # time into the current breath
var _br_len := 4.0                    # this breath's length (s), new every breath
var _br_amp := 1.0                    # this breath's depth, new every breath
var _br := 0.0                        # breath this frame (0 out .. 1 in)
var _lag := PackedFloat32Array()      # per bone: the breath as that bone trails it
var _role := PackedInt32Array()
var _side := PackedFloat32Array()     # per bone: -1 left of her centre, +1 right (unflipped)
var _rank := PackedFloat32Array()     # per bone: order in its group from the top (wings, tail)
var _knees: Array = []                # [thigh, shin]: thighs turn so the knees stay on the planted shins
var _seed := 0.0

# slots
var _slot_nodes: Array[Node2D] = []
var _slot_att := PackedStringArray()  # attachment currently shown
var _slot_xf: Array[Transform2D] = []
var _slot_mesh_cache: Array = []      # per slot: {variant: ArrayMesh}
var _slot_col: Array[Color] = []
var _slot_bendable := PackedByteArray()
var _att_want := PackedStringArray()
var _col_want: Array[Color] = []

var _mat: ShaderMaterial
var _bend_mats: Array = []            # per slot: ShaderMaterial or null
var _warp_mat: ShaderMaterial         # warp rigs: one material (bone uniforms) for body + overlays
var _warp_body: MeshInstance2D           # the base layer (the painting)
var _layer_nodes: Array[MeshInstance2D] = []
var _ua := PackedVector4Array()
var _ub := PackedVector4Array()
var _uc := PackedVector4Array()
var _tint := {}
var _draw_root: Node2D
var _bone_root: Node2D
var _bone_nodes: Array[Node2D] = []
var _bones_live := false

# blink
var _blink_timer := 3.0
var _blink_left := 0.0
var _blink_double := false

# look + fx
var look := Vector2.ZERO              ## final look this frame (read-only)
var lunge := 0.0                      ## lunge channel this frame (read-only)
var fx := {"glow": 0.0, "hand_glow": 0.0, "aura": 0.0, "flash": 0.0, "trail": 0.0, "fade": 0.0}
var _fx_names := ["glow", "hand_glow", "aura", "flash", "trail", "fade"]
var _glow: Sprite2D
var _hand_glow: Sprite2D
var _aura: Sprite2D
var _trail: Line2D
var _trail_on := false
var _trail_pts: Array[Vector2] = []
var _last_tip_xf := Transform2D()
var _queued_events: Array = []
var _frame_dt := 0.0
var _expr := {}                        ## slot -> resting variant override

static var _glow_tex: Texture2D
static var _ring_tex: Texture2D


func _init() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tracks.resize(TRACKS)


## Builds the node tree for `r`. Call once (again to swap the rig).
func setup(r: RigData) -> void:
	for c in get_children():
		c.queue_free()
	rig = r
	hero_id = r.id
	_n = r.bone_names.size()
	_bindings.clear()
	_tracks.clear()
	_tracks.resize(TRACKS)
	_rot.resize(_n)
	_pos.resize(_n)
	_scl.resize(_n)
	_bend_anim.resize(_n)
	_bend_out.resize(_n)
	_world.resize(_n)
	_head = r.bone("head")
	_weapon = r.bone("weapon")
	# look: only the top bone of each chain shifts (children follow it)
	_look_on.clear()
	for i in _n:
		if r.look[i] != Vector2.ZERO:
			var p := r.parent[i]
			var inherited := false
			while p >= 0:
				if r.look[p] != Vector2.ZERO:
					inherited = true
					break
				p = r.parent[p]
			if not inherited:
				_look_on.append(i)
	# springs
	_sp_bones.clear()
	for i in _n:
		if r.spring[i] != null and r.length[i] > 1.0:
			_sp_bones.append(i)
	var ns := _sp_bones.size()
	_sp_p.resize(ns)
	_sp_pp.resize(ns)
	_sp_v.resize(ns)
	_sp_tg.resize(ns)
	_sp_step_tg.resize(ns)
	_sp_off.resize(ns)
	_sp_mass.resize(ns)
	for k in ns:
		_sp_mass[k] = 1 if float((r.spring[_sp_bones[k]] as Dictionary).get("m", 0.0)) > 0.0 else 0
	_sp_ready = false
	_setup_idle(r)

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_bend_mats.clear()

	_bone_root = Node2D.new()
	_bone_root.name = "Bones"
	add_child(_bone_root)
	_bone_nodes.clear()
	for i in _n:
		var bn := Node2D.new()
		bn.name = r.bone_names[i]
		bn.position = r.local[i] if r.parent[i] >= 0 else Vector2.ZERO
		_bone_nodes.append(bn)
		if r.parent[i] >= 0:
			_bone_nodes[r.parent[i]].add_child(bn)
		else:
			_bone_root.add_child(bn)

	if _glow_tex == null:
		_glow_tex = _make_glow_tex(false)
		_ring_tex = _make_glow_tex(true)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_aura = Sprite2D.new()
	_aura.texture = _ring_tex
	_aura.material = add
	_aura.scale = Vector2(3.2, 0.9)
	_aura.visible = false
	add_child(_aura)

	_draw_root = Node2D.new()
	_draw_root.name = "Parts"
	add_child(_draw_root)
	_warp_mat = null
	_warp_body = null
	if r.kind == "warp":
		if _n > MAX_WARP_BONES:
			push_error("RigPlayer[%s]: warp rigs support at most %d bones" % [r.id, MAX_WARP_BONES])
		_warp_mat = ShaderMaterial.new()
		_warp_mat.shader = WARP_SHADER
		_warp_mat.set_shader_parameter(&"body_bone", r.body_bone)
		_ua.resize(MAX_WARP_BONES)
		_ub.resize(MAX_WARP_BONES)
		_uc.resize(MAX_WARP_BONES)
		# One mesh per layer, back to front (format 1: the painting alone); the overlay slots go
		# between them by z below.
		_layer_nodes.clear()
		for ly: Dictionary in r.layers:
			var lm := MeshInstance2D.new()
			lm.name = "Layer_" + str(ly.name)
			lm.mesh = ly.mesh
			lm.texture = ly.image
			lm.material = _warp_mat
			lm.set_meta(&"z", int(ly.z))
			_draw_root.add_child(lm)
			_layer_nodes.append(lm)
		_warp_body = _layer_nodes[0] if not _layer_nodes.is_empty() else null
	_slot_nodes.clear()
	_slot_xf.clear()
	_slot_mesh_cache.clear()
	_slot_col.clear()
	_col_want.clear()
	_slot_att.resize(r.slots.size())
	_att_want.resize(r.slots.size())
	_slot_bendable.resize(r.slots.size())
	for si in r.slots.size():
		var s: Dictionary = r.slots[si]
		var bi: int = s.bone
		var bendable: bool = (r.spring[bi] != null and float(r.spring[bi].get("b", 0.0)) > 0.0) or r.bend[bi] > 0.0
		_slot_bendable[si] = 1 if bendable else 0
		var node: Node2D
		if r.kind == "warp":
			_slot_bendable[si] = 2
			var wm := MeshInstance2D.new()
			wm.material = _warp_mat
			_bend_mats.append(null)
			node = wm
		elif bendable:
			var mi := MeshInstance2D.new()
			var m := ShaderMaterial.new()
			m.shader = SHADER
			m.set_shader_parameter(&"bend_axis", r.axis[bi])
			m.set_shader_parameter(&"bend_len", maxf(r.length[bi], 1.0))
			mi.material = m
			_bend_mats.append(m)
			node = mi
		else:
			var sp := Sprite2D.new()
			sp.centered = false
			sp.material = _mat
			_bend_mats.append(null)
			node = sp
		node.name = s.name
		_draw_root.add_child(node)
		_slot_nodes.append(node)
		_slot_xf.append(Transform2D.IDENTITY)
		_slot_mesh_cache.append({})
		_slot_col.append(Color.WHITE)
		_col_want.append(Color.WHITE)
		_slot_att[si] = ""
		_set_attachment(si, s.default)
	if _layer_nodes.size() > 1:
		# draw order: layers and overlay slots by z (a slot sits above layers with a lower or equal z)
		var items: Array = []
		for ln in _layer_nodes:
			items.append([int(ln.get_meta(&"z", 0)), 0, ln])
		for si in r.slots.size():
			items.append([int(r.slots[si].z), 1, _slot_nodes[si]])
		items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for k in items.size():
			_draw_root.move_child(items[k][2], k)

	_glow = Sprite2D.new()
	_glow.texture = _glow_tex
	_glow.material = add
	_glow.visible = false
	add_child(_glow)
	_hand_glow = Sprite2D.new()
	_hand_glow.texture = _glow_tex
	_hand_glow.material = add
	_hand_glow.visible = false
	add_child(_hand_glow)
	_trail = Line2D.new()
	_trail.material = add
	_trail.width = 46.0
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var wc := Curve.new()
	wc.add_point(Vector2(0, 0))
	wc.add_point(Vector2(1, 1))
	_trail.width_curve = wc
	_trail.visible = false
	add_child(_trail)
	for k in _tint:
		_apply_tint_param(k, _tint[k])
	_blink_timer = randf_range(BLINK_MIN, BLINK_MAX)
	_evaluate(0.0)


func load_hero(id: String) -> bool:
	var r := RigData.load_rig(id)
	if r == null:
		return false
	setup(r)
	return true


# ------------------------------------------------------------------ public API

func has_anim(anim_name: String) -> bool:
	return RigAnim.find(anim_name, hero_id, rig.anim_kind() if rig else "") != null


## Plays `anim_name` on `track` (0 = base/loops, 1+ = overlays). loop: -1 = anim default,
## 0 = once, 1 = loop. mix < 0 uses the animation's own "mix". Returns false if missing.
func play(anim_name: String, track := 0, loop := -1, mix := -1.0) -> bool:
	var a := RigAnim.find(anim_name, hero_id, rig.anim_kind() if rig else "")
	if a == null:
		push_warning("RigPlayer[%s]: no animation '%s'" % [hero_id, anim_name])
		return false
	var e := Entry.new()
	e.anim = a
	e.b = _bind(a)
	e.loop = a.loop if loop < 0 else loop == 1
	e.mix_dur = a.mix if mix < 0.0 else mix
	e.fade_dur = a.mix_out
	var old: Entry = _tracks[track]
	if old != null and e.mix_dur > 0.0:
		if old.fading:
			old.fading = false
		e.prev = old
		old.prev = null
	elif old == null and track > 0 and e.mix_dur > 0.0:
		e.prev = null    # fades in over the lower track
	e.mix_t = 0.0
	if old == null and track == 0:
		e.mix_dur = 0.0
	_tracks[track] = e
	return true


## Fades a track out (overlays) or stops it.
func stop(track := 1, fade := 0.12) -> void:
	var e: Entry = _tracks[track]
	if e == null:
		return
	if fade <= 0.0:
		_tracks[track] = null
	else:
		e.fading = true
		e.fade_t = 0.0
		e.fade_dur = fade


func current(track := 0) -> String:
	var e: Entry = _tracks[track]
	return e.anim.name if e != null else ""


func is_playing(track := 1) -> bool:
	var e: Entry = _tracks[track]
	return e != null and not e.fading and (e.loop or e.time < e.anim.duration)


## Bone origin in this node's space (rig units).
func get_bone_position(bone_name: String) -> Vector2:
	var i := rig.bone(bone_name) if rig else -1
	return _world[i].origin if i >= 0 else Vector2.ZERO


func get_bone_global_position(bone_name: String) -> Vector2:
	return global_transform * get_bone_position(bone_name)


## Node2D that follows the bone (attach effects to it). Bone nodes update every frame once
## any of them has been requested.
func get_bone_node(bone_name: String) -> Node2D:
	_bones_live = true
	var i := rig.bone(bone_name) if rig else -1
	return _bone_nodes[i] if i >= 0 else null


## Weapon tip (or the right hand if the rig has no weapon), in this node's space.
func get_weapon_tip() -> Vector2:
	if rig == null:
		return Vector2.ZERO
	var i := _weapon if _weapon >= 0 else rig.bone("hand_r")
	if i < 0:
		return Vector2(0, -500)
	var tip: Variant = rig.tip[i]
	var local: Vector2 = tip if tip != null else rig.axis[i] * rig.length[i]
	return _world[i] * local


## Blink now (both eyes), regardless of the timer. Only visible when the eyes show "open".
func blink() -> void:
	_blink_left = BLINK_TIME


## Persistent expression: makes `variant` the slot's resting attachment (e.g. "eyes", "open"
## for a hero whose eyes are closed by default). Animations still key over it. "" clears.
func set_expression(slot: String, variant: String) -> void:
	if variant == "":
		_expr.erase(slot)
	else:
		_expr[slot] = variant


func set_tint(param: StringName, value: Variant) -> void:
	_tint[param] = value
	_apply_tint_param(param, value)


## Draws the warp mesh and its overlay patches with `sh` instead of the plain warp shader (null
## restores it). `sh` must include rig_tint.gdshaderinc and warp_skin.gdshaderinc (the Legendary
## foil, src/art/holo_foil.gdshader, does). Warp rigs only; returns false for cutout rigs.
func set_warp_shader(sh: Shader) -> bool:
	if _warp_mat == null:
		return false
	var want: Shader = sh if sh != null else WARP_SHADER
	if _warp_mat.shader != want:
		_warp_mat.shader = want
		# Uniforms are set again for the new shader: the skinning, the tints, the pose.
		_warp_mat.set_shader_parameter(&"body_bone", rig.body_bone)
		for k: StringName in _tint:
			_apply_tint_param(k, _tint[k])
		_upload_warp()
	return true


## Sets a uniform of the warp material (the shader set_warp_shader chose); no-op on cutout rigs.
func set_warp_param(param: StringName, value: Variant) -> void:
	if _warp_mat != null:
		_warp_mat.set_shader_parameter(param, value)


## A uniform of the warp material as last set (null on cutout rigs or when never set).
func get_warp_param(param: StringName) -> Variant:
	return _warp_mat.get_shader_parameter(param) if _warp_mat != null else null


## The shader drawing the warp mesh (WARP_SHADER unless set_warp_shader changed it); null on
## cutout rigs.
func warp_shader() -> Shader:
	return _warp_mat.shader if _warp_mat != null else null


func reset_physics() -> void:
	_sp_ready = false


# ------------------------------------------------------------------ procedural idle (format 2)

## Roles from the bone names (docs/dev/halorig.md 11.3), sides, the order of wings and tail links
## from the top, thigh-shin pairs for the knees, and a per-hero seed so heroes side by side never
## breathe in step.
func _setup_idle(r: RigData) -> void:
	_idle_on = r.kind == "warp" and r.version >= 2
	_role.resize(_n)
	_side.resize(_n)
	_rank.resize(_n)
	_lag.resize(_n)
	_role.fill(ROLE_NONE)
	_rank.fill(0.0)
	_lag.fill(0.0)
	_knees.clear()
	_idle_w = 0.0
	if not _idle_on:
		return
	_seed = float(absi(hash(r.id)) % 1000) * 0.37
	var hb := r.bone("hips")
	var cx := r.setup_world[hb].x if hb >= 0 else 0.0
	var groups := {}
	for i in _n:
		var nm := r.bone_names[i]
		var role := ROLE_NONE
		if nm == "hips":
			role = ROLE_HIPS
		elif nm == "torso" or nm == "spine":
			role = ROLE_TORSO
		elif nm == "chest":
			role = ROLE_CHEST
		elif nm == "neck":
			role = ROLE_NECK
		elif nm == "head":
			role = ROLE_HEAD
		elif nm.begins_with("forearm"):
			role = ROLE_FOREARM
		elif nm.begins_with("arm"):
			role = ROLE_ARM
		elif nm.begins_with("wing"):
			role = ROLE_WING
		elif nm.begins_with("breast"):
			role = ROLE_BREAST
		elif nm.begins_with("thigh"):
			role = ROLE_THIGH
		elif nm.begins_with("shin"):
			role = ROLE_SHIN
		elif nm.begins_with("tail"):
			role = ROLE_TAIL
		_role[i] = role
		_side[i] = -1.0 if r.setup_world[i].x < cx else 1.0
		if role == ROLE_WING or role == ROLE_TAIL:
			var key := "%d:%d" % [role, int(_side[i])]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(i)
	for key: String in groups:
		var lst: Array = groups[key]
		lst.sort_custom(func(a: int, b: int) -> bool: return r.setup_world[a].y < r.setup_world[b].y)
		for k in lst.size():
			_rank[lst[k]] = float(k)
	for i in _n:
		if _role[i] == ROLE_THIGH:
			var sh := r.bone("shin" + r.bone_names[i].substr(5))
			if sh >= 0 and r.parent[i] >= 0:
				_knees.append([i, sh])
	_br_len = randf_range(3.6, 4.4)
	_br_t = randf() * _br_len


## Smooth noise in -1..1 (three sines at unrelated rates: it never visibly repeats).
static func _noise(t: float, s: float, f: float) -> float:
	return 0.55 * sin(t * f * TAU + s) + 0.3 * sin(t * f * 2.13 * TAU + s * 1.7) + 0.15 * sin(t * f * 3.71 * TAU + s * 2.9)


## The procedural idle, added to what the tracks posed: breathing lifts the chest and all it carries,
## the head and arms trail it, each wing opens a little on the breath one after another (top wings
## first), the breasts trail the chest, the weight drifts slowly from hip to hip, and everything
## drifts on slow noise so no two breaths look alike. Full while she idles, IDLE_ACTION_SHARE under an
## action, eased between.
func _idle_drive() -> void:
	var dt := _frame_dt
	var e0: Entry = _tracks[0]
	var idling := e0 != null and e0.anim.name == "idle" and not e0.fading
	var acting := false
	for ti in range(1, TRACKS):
		var e: Entry = _tracks[ti]
		if e != null and not e.fading:
			acting = true
	var want := (IDLE_ACTION_SHARE if acting else 1.0) if idle_motion and idling else 0.0
	_idle_w = move_toward(_idle_w, want, dt * 2.5) if dt > 0.0 else want
	_br_t += dt
	if _br_t >= _br_len:
		_br_t -= _br_len
		_br_len = randf_range(3.5, 4.6)
		_br_amp = randf_range(0.8, 1.15)
	var u := _br_t / _br_len
	var b := smoothstep(0.0, 0.42, u) if u < 0.44 else 1.0 - smoothstep(0.46, 1.0, u)
	_br = b * _br_amp
	var w := _idle_w * idle_amount
	var t := _clock
	var s := _seed
	for i in _n:
		var role := _role[i]
		if role == ROLE_NONE:
			continue
		var tau := 0.0
		match role:
			ROLE_HEAD, ROLE_NECK:
				tau = 0.22
			ROLE_ARM:
				tau = 0.16
			ROLE_FOREARM:
				tau = 0.26
			ROLE_WING:
				tau = 0.2 + 0.12 * _rank[i]
			ROLE_BREAST:
				tau = 0.3
		if tau > 0.0 and dt > 0.0:
			_lag[i] += (_br - _lag[i]) * (1.0 - exp(-dt / tau))
		if w <= 0.0005:
			continue
		var lg := _lag[i]
		match role:
			ROLE_HIPS:
				var nh := _noise(t, s, 0.055)
				_pos[i] += Vector2(1.8 * nh, 0.5 * absf(nh)) * w
				_rot[i] += 0.35 * _noise(t, s + 2.1, 0.05) * w
			ROLE_TORSO:
				_rot[i] += (0.3 * _noise(t, s + 4.2, 0.045) - 0.25 * _noise(t, s + 2.1, 0.05)) * w
			ROLE_CHEST:
				_pos[i].y -= 3.4 * _br * w
				_scl[i] *= Vector2(1.0 + 0.008 * _br * w, 1.0 + 0.012 * _br * w)
			ROLE_NECK:
				_rot[i] += 0.25 * _noise(t, s + 6.3, 0.07) * w
			ROLE_HEAD:
				_pos[i].y += 2.0 * (_br - lg) * w
				_rot[i] += (0.9 * _noise(t, s + 8.4, 0.045) + 0.5 * (lg - 0.5)) * w
			ROLE_ARM:
				_rot[i] += _side[i] * (0.6 * lg + 0.35 * _noise(t, s + 1.3 * i, 0.06)) * w
			ROLE_FOREARM:
				_rot[i] += _side[i] * (0.45 * lg + 0.3 * _noise(t, s + 1.7 * i, 0.08)) * w
			ROLE_WING:
				var ax := rig.axis[i]
				var lift := -signf(ax.x) if absf(ax.x) > 0.05 else -_side[i]
				var k := 1.0 / (1.0 + 0.3 * _rank[i])
				_rot[i] += lift * k * (2.2 * (lg - 0.5) + 0.9 * _noise(t, s + 0.9 * i, 0.08)) * w
			ROLE_BREAST:
				_pos[i].y += 1.2 * (_br - lg) * w
			ROLE_TAIL:
				_rot[i] += 4.0 * sin(t * TAU * 0.3 - _rank[i] * 0.9 + s) * w


## Thighs hang from the hips, shins stand on the ground (parented to root): when the hips move, each
## thigh turns so it still reaches its knee instead of the legs sliding with the hips.
func _keep_knees() -> void:
	for kp: Array in _knees:
		var th: int = kp[0]
		var sh: int = kp[1]
		var hp := rig.parent[th]
		if rig.parent[sh] == hp:
			continue                  # shin rides on the hips too: nothing to keep
		var hpiv := rig.setup_world[hp]
		var tp := rig.setup_world[th]
		var tp2 := hpiv + _pos[hp] + ((tp - hpiv) * _scl[hp]).rotated(deg_to_rad(_rot[hp]))
		var kn := rig.setup_world[sh] + _pos[sh]
		var a0 := (kn - tp).angle()
		var a1 := (kn - tp2).angle()
		_rot[th] += rad_to_deg(angle_difference(a0, a1)) - _rot[hp]


## Manual stepping (set manual = true first): advance animations and physics by dt seconds.
func advance(dt: float) -> void:
	_evaluate(dt)


func _process(delta: float) -> void:
	if not manual and rig != null:
		_evaluate(delta)


# ------------------------------------------------------------------ evaluation

func _evaluate(delta: float) -> void:
	if rig == null:
		return
	var dt := delta * speed_scale
	_frame_dt = dt
	_clock += dt
	_advance_tracks(dt)
	_pose()
	_solve(dt)
	_apply()
	if not _queued_events.is_empty():
		var q := _queued_events
		_queued_events = []
		for ev in q:
			if ev[0] == 0:
				anim_event.emit(ev[1])
			else:
				anim_finished.emit(ev[1])


func _bind(a: RigAnim) -> Binding:
	if _bindings.has(a):
		return _bindings[a]
	var b := Binding.new()
	b.rot.resize(_n)
	b.tr.resize(_n)
	b.sc.resize(_n)
	b.bend.resize(_n)
	for bn in a.bones:
		var i := rig.bone(bn)
		if i < 0:
			continue
		var ch: Dictionary = a.bones[bn]
		b.rot[i] = ch.get("rotate", null)
		b.tr[i] = ch.get("translate", null)
		b.sc[i] = ch.get("scale", null)
		b.bend[i] = ch.get("bend", null)
		b.keyed.append(i)
	var ns := rig.slots.size()
	b.att.resize(ns)
	b.col.resize(ns)
	for sn in a.slots:
		var si := int(rig.slot_index.get(sn, -1))
		if si < 0:
			continue
		b.att[si] = a.slots[sn].get("attachment", null)
		b.col[si] = a.slots[sn].get("color", null)
		b.keyed_slots.append(si)
	_bindings[a] = b
	return b


func _anim_time(e: Entry) -> float:
	var a := e.anim
	if e.loop:
		if e.time < a.duration:
			return e.time
		var span := a.duration - a.loop_start
		if span <= 0.0001:
			return fmod(e.time, a.duration)
		return a.loop_start + fmod(e.time - a.loop_start, span)
	return minf(e.time, a.duration)


func _advance_tracks(dt: float) -> void:
	for ti in TRACKS:
		var e: Entry = _tracks[ti]
		if e == null:
			continue
		var t0 := _anim_time(e) if e.started else -0.0001
		e.started = true
		e.time += dt
		if e.mix_t < e.mix_dur:
			e.mix_t += dt
		if e.prev != null:
			e.prev.time += dt
			if e.mix_t >= e.mix_dur:
				e.prev = null
		var t1 := _anim_time(e)
		if not e.fading:
			_collect_events(e, t0, t1)
		if not e.loop and e.time >= e.anim.duration and not e.finished_sent:
			e.finished_sent = true
			_queued_events.append([1, e.anim.name])
			if ti > 0 and not e.anim.hold and not e.fading:
				e.fading = true
				e.fade_t = 0.0
		if e.fading:
			e.fade_t += dt
			if e.fade_t >= e.fade_dur:
				_tracks[ti] = null


func _collect_events(e: Entry, t0: float, t1: float) -> void:
	var evs: Array = e.anim.events
	if evs.is_empty():
		return
	if t1 >= t0:
		for ev in evs:
			if ev[0] > t0 and ev[0] <= t1:
				_queued_events.append([0, ev[1]])
	else:   # wrapped (loop)
		for ev in evs:
			if ev[0] > t0 and ev[0] <= e.anim.duration:
				_queued_events.append([0, ev[1]])
		for ev in evs:
			if ev[0] >= e.anim.loop_start and ev[0] <= t1:
				_queued_events.append([0, ev[1]])


func _pose() -> void:
	for i in _n:
		_rot[i] = 0.0
		_pos[i] = Vector2.ZERO
		_scl[i] = Vector2.ONE
		_bend_anim[i] = 0.0
	var ns := rig.slots.size()
	for si in ns:
		_att_want[si] = ""
		_col_want[si] = Color.WHITE
	var lk := Vector2.ZERO
	var fxv := {"glow": 0.0, "hand_glow": 0.0, "aura": 0.0, "flash": 0.0, "trail": 0.0, "fade": 0.0}
	var lg := 0.0
	for ti in TRACKS:
		var e: Entry = _tracks[ti]
		if e == null:
			continue
		var w := 1.0
		if e.fading:
			w = 1.0 - clampf(e.fade_t / maxf(e.fade_dur, 0.001), 0.0, 1.0)
		var p: Entry = e.prev
		var m := 1.0
		if e.mix_dur > 0.0 and (p != null or ti > 0):
			m = clampf(e.mix_t / e.mix_dur, 0.0, 1.0)
		var t := _anim_time(e)
		var tp := _anim_time(p) if p != null else 0.0
		var cb := e.b
		var pb: Binding = p.b if p != null else null
		var a := e.anim
		# bones keyed by the current entry
		for i in cb.keyed:
			var tl: RigAnim.Timeline = cb.rot[i]
			if tl != null:
				var v := tl.sample1(t)
				var lo := _rot[i]
				if pb != null and pb.rot[i] != null:
					v = lerpf((pb.rot[i] as RigAnim.Timeline).sample1(tp), v, m)
				else:
					v = lerpf(lo, v, m)
				_rot[i] = lerpf(lo, v, w)
			tl = cb.tr[i]
			if tl != null:
				var v2 := tl.sample2(t)
				var lo2 := _pos[i]
				if pb != null and pb.tr[i] != null:
					v2 = (pb.tr[i] as RigAnim.Timeline).sample2(tp).lerp(v2, m)
				else:
					v2 = lo2.lerp(v2, m)
				_pos[i] = lo2.lerp(v2, w)
			tl = cb.sc[i]
			if tl != null:
				var v3 := tl.sample2(t)
				var lo3 := _scl[i]
				if pb != null and pb.sc[i] != null:
					v3 = (pb.sc[i] as RigAnim.Timeline).sample2(tp).lerp(v3, m)
				else:
					v3 = lo3.lerp(v3, m)
				_scl[i] = lo3.lerp(v3, w)
			tl = cb.bend[i]
			if tl != null:
				var v4 := tl.sample1(t)
				var lo4 := _bend_anim[i]
				if pb != null and pb.bend[i] != null:
					v4 = lerpf((pb.bend[i] as RigAnim.Timeline).sample1(tp), v4, m)
				else:
					v4 = lerpf(lo4, v4, m)
				_bend_anim[i] = lerpf(lo4, v4, w)
		# channels only the fading-out previous entry keys
		if pb != null and m < 1.0:
			var k := (1.0 - m) * w
			for i in pb.keyed:
				if pb.rot[i] != null and cb.rot[i] == null:
					_rot[i] = lerpf(_rot[i], (pb.rot[i] as RigAnim.Timeline).sample1(tp), k)
				if pb.tr[i] != null and cb.tr[i] == null:
					_pos[i] = _pos[i].lerp((pb.tr[i] as RigAnim.Timeline).sample2(tp), k)
				if pb.sc[i] != null and cb.sc[i] == null:
					_scl[i] = _scl[i].lerp((pb.sc[i] as RigAnim.Timeline).sample2(tp), k)
				if pb.bend[i] != null and cb.bend[i] == null:
					_bend_anim[i] = lerpf(_bend_anim[i], (pb.bend[i] as RigAnim.Timeline).sample1(tp), k)
		# slots
		for si in cb.keyed_slots:
			var ak: Variant = cb.att[si]
			if ak != null and w * m >= 0.5:
				_att_want[si] = RigAnim.attachment_at(ak, t)
			var ct: RigAnim.Timeline = cb.col[si]
			if ct != null:
				var c := ct.sample4(t)
				_col_want[si] = _col_want[si].lerp(c, m * w)
		if pb != null and m < 0.5:
			for si in pb.keyed_slots:
				if pb.att[si] != null and cb.att[si] == null:
					_att_want[si] = RigAnim.attachment_at(pb.att[si], tp)
		# look / fx / lunge
		if a.look != null:
			var lv := a.look.sample2(t)
			if p != null and p.anim.look != null:
				lv = p.anim.look.sample2(tp).lerp(lv, m)
			else:
				lv = lk.lerp(lv, m)
			lk = lk.lerp(lv, w)
		elif p != null and p.anim.look != null and m < 1.0:
			lk = lk.lerp(p.anim.look.sample2(tp), (1.0 - m) * w)
		for fname in _fx_names:
			var ft: RigAnim.Timeline = a.fx.get(fname, null)
			var pt: RigAnim.Timeline = p.anim.fx.get(fname, null) if p != null else null
			if ft != null:
				var fv := ft.sample1(t)
				fv = lerpf(pt.sample1(tp) if pt != null else float(fxv[fname]), fv, m)
				fxv[fname] = lerpf(float(fxv[fname]), fv, w)
			elif pt != null and m < 1.0:
				fxv[fname] = lerpf(float(fxv[fname]), pt.sample1(tp), (1.0 - m) * w)
		if a.lunge != null:
			lg = lerpf(lg, a.lunge.sample1(t) * m, w)
		elif p != null and p.anim.lunge != null:
			lg = lerpf(lg, p.anim.lunge.sample1(tp), (1.0 - m) * w)
	look = (lk + look_extra).clamp(Vector2(-1, -1), Vector2(1, 1))
	fx = fxv
	lunge = lg
	if _idle_on:
		_idle_drive()
	if not _knees.is_empty():
		_keep_knees()
	# head turn: features shift with the turn, back hair counter-shifts, head narrows a bit
	if look != Vector2.ZERO:
		for i in _look_on:
			var f: Vector2 = rig.look[i]
			_pos[i] += Vector2(look.x * f.x * rig.look_px.x, look.y * f.y * rig.look_px.y)
		if _head >= 0:
			_scl[_head].x *= 1.0 - HEAD_TURN_SQUASH * absf(look.x)


## World transforms + spring physics (parents first, so springs inherit their parents' sway).
func _solve(dt: float) -> void:
	var G := global_transform if is_inside_tree() else transform
	var det_g := G.determinant()
	var steps := 0
	if physics_enabled and _sp_ready:
		_phys_acc += dt
		steps = mini(int(_phys_acc / PHYS_DT), MAX_SUBSTEPS)
		_phys_acc -= steps * PHYS_DT
		if _phys_acc > PHYS_DT:
			_phys_acc = 0.0
	var si := 0
	var nsp := _sp_bones.size()
	for i in _n:
		var p := rig.parent[i]
		var lpos: Vector2 = (rig.local[i] if p >= 0 else Vector2.ZERO) + _pos[i]
		var pw: Transform2D = _world[p] if p >= 0 else Transform2D.IDENTITY
		var bend := _bend_anim[i]
		var rot_deg := _rot[i]
		if si < nsp and _sp_bones[si] == i:
			var sp: Dictionary = rig.spring[i]
			var lw := pw * Transform2D(deg_to_rad(rot_deg), _scl[i], 0.0, lpos)
			var tip_local: Vector2 = rig.axis[i] * rig.length[i]
			var origin_g := G * lw.origin
			var rigid_g := G * (lw * tip_local)
			var hang_g := origin_g + G.basis_xform(rig.axis[i] * rig.length[i] * Vector2(absf(lw.get_scale().x), absf(lw.get_scale().y)))
			var gk := float(sp.get("g", 0.0))
			var target := rigid_g.lerp(hang_g, gk)
			var len_g := (rigid_g - origin_g).length()
			var wk := float(sp.get("w", 0.0)) * wind
			if wk > 0.0:
				var ph := float(i) * 1.7
				var n1 := 0.55 * sin(_clock * 1.3 + ph) + 0.3 * sin(_clock * 2.7 + ph * 1.7) + 0.15 * sin(_clock * 5.3 + ph * 0.6)
				var n2 := 0.5 * sin(_clock * 1.9 + ph * 1.3)
				target += Vector2(n1, n2 * 0.35) * (wk * 0.22 * len_g)
			if not _sp_ready or (target - _sp_tg[si]).length() > len_g * 2.5 + 40.0:
				_sp_p[si] = target
				_sp_pp[si] = target
				_sp_v[si] = Vector2.ZERO
				_sp_tg[si] = target
				_sp_step_tg[si] = target
			if steps > 0:
				var k := float(sp.get("k", 60.0))
				var c := float(sp.get("c", 8.0))
				var inertia := float(sp.get("i", 0.5))
				var tg0 := _sp_tg[si]
				var pp := _sp_p[si]
				var vv := _sp_v[si]
				var last := _sp_step_tg[si]
				for s in steps:
					if s == steps - 1:
						_sp_pp[si] = pp
					var tg := tg0.lerp(target, float(s + 1) / float(steps))
					pp += (tg - last) * (1.0 - inertia)
					last = tg
					var acc := (tg - pp) * k - vv * c
					vv += acc * PHYS_DT
					pp += vv * PHYS_DT
				_sp_p[si] = pp
				_sp_v[si] = vv
				_sp_step_tg[si] = last
			_sp_tg[si] = target
			# Physics runs at 60 Hz; draw between the last two steps so 120 Hz screens see every
			# frame move (stepped springs judder against the smoothly animated body).
			var pr := _sp_pp[si].lerp(_sp_p[si], clampf(_phys_acc / PHYS_DT, 0.0, 1.0)) if _sp_ready else _sp_p[si]
			if _sp_mass[si] == 1:
				# a soft mass: the part shifts with its lag (clamped), it does not swing on its pivot
				var d := pr - target
				var lim_g := float(sp.get("limit", 8.0)) * G.get_scale().length() * 0.7071
				if d.length() > lim_g:
					d = d.normalized() * lim_g
				lpos += (G * pw).affine_inverse().basis_xform(d)
				_sp_off[si] = d.length()
			else:
				var off := (rigid_g - origin_g).angle_to(pr - origin_g)
				if det_g * pw.determinant() < 0.0:
					off = -off
				var lim := deg_to_rad(float(sp.get("limit", 20.0)))
				off = clampf(off, -lim, lim)
				_sp_off[si] = off
				var b := float(sp.get("b", 0.0))
				rot_deg += rad_to_deg(off * (1.0 - b))
				bend += off * b * 1.6
			si += 1
		elif si < nsp and _sp_bones[si] < i:
			si += 1
		_bend_out[i] = bend
		_world[i] = pw * Transform2D(deg_to_rad(rot_deg), _scl[i], 0.0, lpos)
		if _bones_live:
			_bone_nodes[i].transform = Transform2D(deg_to_rad(rot_deg), _scl[i], 0.0, lpos) if p >= 0 else _world[i]
	if nsp > 0:
		_sp_ready = true


func _apply() -> void:
	# blink timing (automatic when blink_enabled; blink() forces one)
	var blinking := false
	if blink_enabled:
		_blink_timer -= _frame_dt
		if _blink_timer <= 0.0:
			_blink_left = BLINK_TIME
			if _blink_double:
				_blink_double = false
				_blink_timer = randf_range(BLINK_MIN, BLINK_MAX)
			elif randf() < 0.2:
				_blink_double = true
				_blink_timer = 0.28
			else:
				_blink_timer = randf_range(BLINK_MIN, BLINK_MAX)
	var shut := 0.0                     # how far the lids are down, 0..1
	if _blink_left > 0.0:
		blinking = true
		var e := BLINK_TIME - _blink_left
		if e < BLINK_CLOSE:
			shut = e / BLINK_CLOSE
		elif e < BLINK_CLOSE + BLINK_HOLD:
			shut = 1.0
		else:
			shut = 1.0 - (e - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN
		shut = smoothstep(0.0, 1.0, clampf(shut, 0.0, 1.0))
		_blink_left -= _frame_dt
	var ns := rig.slots.size()
	for si in ns:
		var s: Dictionary = rig.slots[si]
		var want := _att_want[si]
		if want == "" or want == "default":
			want = _expr.get(s.name, s.default)
		var alpha := 1.0
		if blinking and want == "open" and s.attachments.has("closed"):
			if (s.attachments.closed as Dictionary).get("texture") != null:
				want = "closed"            # closed-eye overlay over the painted open eyes, fading in
				alpha = shut
			else:
				alpha = 1.0 - shut         # open-eye overlay fading out to the painted closed eyes
		if want != _slot_att[si]:
			_set_attachment(si, want)
		var node := _slot_nodes[si]
		var col := _col_want[si]
		if alpha < 1.0:
			col.a *= alpha
		if col != _slot_col[si]:
			_slot_col[si] = col
			node.self_modulate = col
		var bi: int = s.bone
		if _slot_bendable[si] == 2:
			continue
		node.transform = _world[bi] * _slot_xf[si]
		if _slot_bendable[si] == 1:
			var m: ShaderMaterial = _bend_mats[si]
			var bv := _bend_out[bi]
			if absf(bv - float(m.get_meta(&"b", 0.0))) > 0.0005:
				m.set_meta(&"b", bv)
				m.set_shader_parameter(&"bend", bv)
	if _warp_mat != null:
		_upload_warp()
	_apply_fx()


func _upload_warp() -> void:
	var n := mini(_n, MAX_WARP_BONES)
	for i in n:
		var w := _world[i]
		_ua[i] = Vector4(w.x.x, w.x.y, w.y.x, w.y.y)
		var sw := rig.setup_world[i]
		_ub[i] = Vector4(w.origin.x, w.origin.y, sw.x, sw.y)
		var ax := rig.axis[i]
		_uc[i] = Vector4(ax.x, ax.y, rig.length[i], _bend_out[i])
	_warp_mat.set_shader_parameter(&"bone_a", _ua)
	_warp_mat.set_shader_parameter(&"bone_b", _ub)
	_warp_mat.set_shader_parameter(&"bone_c", _uc)


func _apply_fx() -> void:
	var g := float(fx.get("glow", 0.0))
	_glow.visible = g > 0.01
	if _glow.visible:
		_glow.position = get_weapon_tip()
		_glow.modulate = Color(fx_color, clampf(g, 0.0, 1.0))
		var s := 1.4 + g * 1.6 + 0.12 * sin(_clock * 18.0)
		_glow.scale = Vector2(s, s)
	var hg := float(fx.get("hand_glow", 0.0))
	_hand_glow.visible = hg > 0.01
	if _hand_glow.visible:
		var hi := rig.bone("hand_l")
		var hj := rig.bone("hand_r")
		var hp := Vector2.ZERO
		if hi >= 0 and hj >= 0:
			hp = (_world[hi].origin + _world[hj].origin) * 0.5
		elif hj >= 0:
			hp = _world[hj].origin
		_hand_glow.position = hp
		_hand_glow.modulate = Color(fx_color, clampf(hg, 0.0, 1.0))
		_hand_glow.scale = Vector2.ONE * (1.2 + hg * 1.8)
	var au := float(fx.get("aura", 0.0))
	_aura.visible = au > 0.01
	if _aura.visible:
		_aura.modulate = Color(fx_color, clampf(au, 0.0, 1.0))
		var k := 1.0 + 0.05 * sin(_clock * 6.0)
		_aura.scale = Vector2(3.4 * k * (0.7 + 0.3 * au), 0.95 * k * (0.7 + 0.3 * au))
	var fl := float(fx.get("flash", 0.0))
	if absf(fl - float(_tint.get(&"flash_anim", 0.0))) > 0.002:
		_tint[&"flash_anim"] = fl
		_apply_tint_param(&"flash", maxf(fl, float(_tint.get(&"flash", 0.0))))
	var fd := float(fx.get("fade", 0.0))
	if absf(fd - float(_tint.get(&"dissolve", 0.0))) > 0.002:
		set_tint(&"dissolve", fd)
		set_tint(&"dissolve_color", fx_color)
	# weapon trail
	var tr := float(fx.get("trail", 0.0))
	var on := tr > 0.01
	var wi := _weapon if _weapon >= 0 else rig.bone("hand_r")
	if on and wi >= 0:
		var xf: Transform2D = _world[wi]
		var tip: Variant = rig.tip[wi]
		var tl: Vector2 = tip if tip != null else rig.axis[wi] * rig.length[wi]
		if not _trail_on:
			_trail_pts.clear()
			_last_tip_xf = xf
		# interpolate between last and current weapon transforms so fast swings form an arc
		for k in 4:
			var f := float(k + 1) / 4.0
			var ix := _last_tip_xf.interpolate_with(xf, f)
			_trail_pts.append(ix * tl)
		_last_tip_xf = xf
		while _trail_pts.size() > 28:
			_trail_pts.remove_at(0)
		_trail.points = PackedVector2Array(_trail_pts)
		var gr := Gradient.new()
		gr.set_color(0, Color(fx_color, 0.0))
		gr.set_color(1, Color(fx_color.lightened(0.4), 0.85 * clampf(tr, 0.0, 1.0)))
		_trail.gradient = gr
		_trail.visible = _trail_pts.size() > 2
	elif _trail_on or _trail.visible:
		# let the trail shrink away
		if _trail_pts.size() > 2:
			for k in 3:
				if _trail_pts.size() > 0:
					_trail_pts.remove_at(0)
			_trail.points = PackedVector2Array(_trail_pts)
		else:
			_trail.visible = false
	_trail_on = on


func _set_attachment(si: int, variant: String) -> void:
	var s: Dictionary = rig.slots[si]
	_slot_att[si] = variant
	var node := _slot_nodes[si]
	if not s.attachments.has(variant):
		if variant == "none" or not s.attachments.has(s.default):
			node.visible = false
			return
		variant = s.default
	var att: Dictionary = s.attachments[variant]
	var r: Rect2 = att.rect
	node.visible = true
	var inv := 1.0 / rig.texel
	if _slot_bendable[si] == 2:
		# warp overlay patch: pre-skinned mesh, or nothing when the base image shows this variant
		var wmi := node as MeshInstance2D
		if att.texture == null:
			node.visible = false
			return
		wmi.mesh = att.mesh
		wmi.texture = att.texture
		_slot_xf[si] = Transform2D.IDENTITY
		return
	if _slot_bendable[si] == 1:
		var mi := node as MeshInstance2D
		var cache: Dictionary = _slot_mesh_cache[si]
		if not cache.has(variant):
			cache[variant] = _grid_mesh(r)
		mi.mesh = cache[variant]
		mi.texture = att.texture
		_slot_xf[si] = Transform2D.IDENTITY
	else:
		var sp := node as Sprite2D
		sp.texture = att.texture
		_slot_xf[si] = Transform2D(0.0, Vector2(inv, inv), 0.0, r.position)


## Grid mesh covering `r` (bone space) so the bend shader can curve it.
func _grid_mesh(r: Rect2) -> ArrayMesh:
	var gx := BEND_GRID.x
	var gy := BEND_GRID.y
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in gy + 1:
		for x in gx + 1:
			var u := float(x) / gx
			var v := float(y) / gy
			verts.append(r.position + Vector2(u * r.size.x, v * r.size.y))
			uvs.append(Vector2(u, v))
	for y in gy:
		for x in gx:
			var a := y * (gx + 1) + x
			idx.append_array([a, a + 1, a + gx + 1, a + 1, a + gx + 2, a + gx + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _apply_tint_param(param: StringName, value: Variant) -> void:
	if param == &"flash_anim":
		return
	if _mat == null:
		return
	_mat.set_shader_parameter(param, value)
	if _warp_mat != null:
		_warp_mat.set_shader_parameter(param, value)
	for m in _bend_mats:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter(param, value)


static func _make_glow_tex(ring: bool) -> Texture2D:
	var g := Gradient.new()
	if ring:
		g.offsets = PackedFloat32Array([0.0, 0.55, 0.78, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.97, 0.85, 0.8), Color(1, 0.9, 0.6, 0.22), Color(1, 0.9, 0.6, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
