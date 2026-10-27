extends Control
## Screen "battle": plays a campaign stage. params: stage_index (int); skip (bool, for
## screenshots: skips to the result right away). params mode = "tower" and floor (int) play a
## floor of the Spire instead (the floor is stage-shaped, so the rest of the screen is shared).
## params mode = "champion" fights the war's enemy Champion (Game.war_champion_setup: her alone as a
## boss, 45 s; the damage counts, the week's tiers pay; a printed result sheet, then the front).
## params mode = "rival" fights Rue's team today (Game.rival_battle_setup; a result poster of its own,
## src/ui/rival/rival_result.gd: YOU BEAT RUE with the haul and her print, or RUE WINS, which costs
## nothing).
## Debug builds on a throwaway save (--rich / --fresh), for screenshots: result = "victory" |
## "defeat" skips to that result; manual = true plays with manual ultimates (cards fill and wait).
##
## Style v4 (the poster look, docs/dev/ui-style-v4.md): the fight stays in full colour; the HUD
## around it is printed instrument readouts on paper strips (src/ui/v4/battle/battle_print.gd): the
## top strip (stage, FOES / TEAM pips, TIME, AUTO, the speed stamp, SKIP), the boss band, paper
## readout tags over the units, the allies as framed print cards on the bottom strip; the results
## are risograph posters (battle_result.gd).
##
## Front view (combat v1, the war version; docs/dev/combat-v1.md): the team stands big in the
## foreground, facing the camera, along a line wider than the screen; the camera glides along it to
## whoever is acting (a sideways swipe on the field looks along the line; the camera follows the
## fight again a moment later; a tap on a heroine puts her in the spotlight, a tap on a foe marks it:
## BattleSim.set_spotlight / set_mark). The foes stand smaller in the mid-ground and drift a little with the
## camera. Over them the souls crowd (src/ui/battle/souls_crowd.gd) turns gold or red as the fight
## swings; the winner takes it. The team's overhead tags stay hidden: their cards on the
## bottom strip carry HP and energy.
##
## The BattleSim runs a little ahead of what the player sees (SIM_LEAD_MS of battle time).
## Every event is scheduled on a display clock so animations line up with their results:
## an attack starts its swing early enough that the impact frame lands exactly when its
## damage shows, ranged attacks launch a bolt that arrives on time, and an ultimate holds
## the clock for a short cinematic (dim, portrait sweep, skill name, shake) while the
## caster winds up. Battle speed (1x/2x/4x) scales the display clock and the rigs.
## Game.complete_stage (or complete_tower) is called exactly once per battle: on the result, on
## Retreat, or (as a defeat) if the player leaves mid-fight.

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const UnitView := preload("res://src/ui/battle/unit_view.gd")
const BattleFx := preload("res://src/ui/battle/battle_fx.gd")
const UltCinematic := preload("res://src/ui/battle/ult_cinematic.gd")
const SoulsCrowd := preload("res://src/ui/battle/souls_crowd.gd")
const AllyPortrait := preload("res://src/ui/battle/ally_portrait.gd")
const BattleResult := preload("res://src/ui/battle/battle_result.gd")
const RivalResult := preload("res://src/ui/rival/rival_result.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")
const BP := preload("res://src/ui/v4/battle/battle_print.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")
const HPK := preload("res://src/ui/v4/hero_poster_kit.gd")
const HUD := preload("res://src/ui/components/hud.gd")
const Plate := preload("res://src/ui/components/plate.gd")

const TICK_MS := 100
## How far (battle ms) the sim runs ahead of the display clock. Must exceed the longest lead.
const SIM_LEAD_MS := 760.0
## Battle ms from the start of each attack animation to its impact frame (fallbacks when
## a rig's animation has no "hit" / "release" event; UnitView reads the real timing).
const HIT_LEAD := {"attack_melee": 330.0, "attack_thrust": 320.0, "attack_ranged": 400.0}
## Bolt flight time (battle ms) for ranged attacks; the bolt leaves at the release frame.
const BOLT_MS := 240.0
## Impact frame of the shared "ultimate" animation (seconds at speed 1).
const ULT_HIT_S := 0.98
## The top strip (below the safe area), the boss band and the bottom strip (above the safe area).
const TOP_H := 104.0
const BOSS_H := 88.0
const BOTTOM_H := 196.0
## Width of an ally card on the bottom strip.
const PORTRAIT_W := 120.0
const END_DELAY := 1.4
const INTRO_TIME := 1.25
const FRONT_X := [0.31, 0.69]
const BACK_X := [0.16, 0.5, 0.84]
## Front view: a front-row heroine's height (share of the field), the spacing along the team's line
## (share of the screen width) and the slots left to right along it (the front pair near the middle).
const ALLY_H := 0.6
const ALLY_PITCH := 0.5
const LINE_ORDER := [2, 0, 3, 1, 4]
## A front-row foe's height (share of the field); how much the foes move with the camera.
const FOE_H := 0.24
const FOE_PARALLAX := 0.28
## The camera: glide rate (1/s), how long a focus holds before another may take it, and how long a
## swipe keeps it where the player left it (seconds).
const CAM_RATE := 3.0
const CAM_HOLD := 0.9
const SWIPE_HOLD := 2.6
## Where repeat numbers on one unit appear (fan slots 0-3, relative to the head).
const NUM_FAN := [Vector2(0, -10), Vector2(34, -40), Vector2(-34, -70), Vector2(14, -100)]
## Status words float up in mono type: debuffs in signal, buffs on paper.
const STATUS_TEXT := {
	"stun": ["STUNNED", SignalKit.SIGNAL], "burn": ["BURN", Color("ff8a62")], "regen": ["REGEN", Color("9fe0bf")],
	"taunt": ["TAUNT", SignalKit.MATTE], "atk_up": ["ATK UP", SignalKit.MATTE], "atk_down": ["ATK DOWN", SignalKit.SIGNAL],
	"def_up": ["DEF UP", SignalKit.MATTE], "def_down": ["DEF DOWN", SignalKit.SIGNAL], "spd_up": ["HASTE", SignalKit.MATTE],
	"charm": ["CHARMED", Color("ff6fae")],
}
## Floating numbers (style v4): damage in compressed type, paper on ink for hits on echoes, ink on
## paper for hits on the team, signal for crits and executes; heals and shields in mono.
const NUM_PAPER := SignalKit.MATTE
const NUM_INK := SignalKit.INK
const NUM_HEAL := Color("9fe0bf")
const NUM_SHIELD := Color("c9d6de")

var _index := -1
var _stage: Dictionary = {}
## "stage" (campaign), "tower" (the Spire: _floor) or "rival" (Rue)
var _mode := "stage"
var _floor := 0
var _setup: Dictionary = {}
var _sim: BattleSim
var _views: Dictionary = {}
var _portraits: Dictionary = {}
var _queue: Array[Dictionary] = []
var _seq := 0
var _display_ms := 0.0
var _speed := 1
var _hold := 0.0
## Hit stop: seconds left of a brief freeze on big hits (crits, ultimates) that sells the impact.
var _hitstop := 0.0
var _flash_rect: ColorRect
var _hold_view: Node2D
var _phase := "intro"
var _phase_t := 0.0
var _completed := false
var _team_size := 0
var _boss_uid := ""

var _world: Control
var _units: Node2D
var _dim: ColorRect
var _bars: Node2D
var _fx: Node2D
var _numbers: Control
var _hud: Control
var _bottom: Control
var _overlay: Control
var _timer_label: Label
var _time_ticks: Control
var _foe_dots: Control
var _team_dots: Control
var _alive_sig := ""
var _auto_slot: Control
var _auto_led: Control
var _auto_caption: Label
var _mode_note: Label
var _speed_stamp: Control
var _boss_band: Control
## Debug screenshots: the result a Skip lands on ("victory" | "defeat"; "" = the real one).
var _force_result := ""
var _shake_t := 0.0
var _shake_amp := 0.0
var _dim_target := 0.0
var _manual_hint: Control
var _num_stack: Dictionary = {}
## Front view: each unit's spot (allies: x along the team's line, foes: x on screen; y on screen),
## the camera (x along the line) and its goal, the focus hold, the swipe.
var _home: Dictionary = {}
var _cam_x := 0.0
var _cam_goal := 0.0
var _cam_lock_until := 0.0
var _swipe_until := 0.0
var _drag_from := Vector2.INF
var _drag_cam := 0.0
var _dragged := false
## The hint for the hands-on taps (shown once per player, then remembered in the settings).
var _tap_hint: Control
var _souls: Node2D
var _souls_won := -1
## The photo finish: the field at the last blow of a won fight, for the victory poster (null until then).
var _photo: Texture2D
## The souls slip's line ("+40 SOULS  ->  ..."), for the photo finish's caption.
var _souls_line := ""
## Encore (battle_sim): the last ally ultimate's hero, when its window closes (display ms) and the
## sticker over the cards that counts it down.
var _encore_hero := ""
var _encore_until := -1.0
var _encore_tag: Control
var _encore_label: Label
var _num_n := 0
var _shown_secs := -1


func setup(params: Dictionary) -> void:
	UI.set_chrome(false, false)
	if str(params.get("mode", "")) == "champion":
		_mode = "champion"
		_setup = Game.war_champion_setup()
		var ch: Dictionary = (Game.war() as Dictionary).get("champion", {})
		if _setup.is_empty() or ch.is_empty():
			_completed = true
			UI.toast("No tries left against the Champion today", "bad")
			UI.go("front")
			return
		_index = 0
		_stage = {"index": 0, "id": "CHAMP", "chapter": 4, "name": str(ch.name), "is_boss": true,
			"background": str(_setup.get("background", "")), "enemies": _setup.get("enemies", []), "recommended_power": 0}
	elif str(params.get("mode", "")) == "rival":
		_mode = "rival"
		if not Game.rival_unlocked():
			_completed = true
			UI.toast("Rue hasn't shown up yet", "bad")
			UI.go("rival")
			return
		_setup = Game.rival_battle_setup()
		var rv: Dictionary = Game.rival()
		_index = 0
		_stage = {"index": 0, "id": "RUE", "chapter": 0, "name": "Lv %d" % int(rv.get("level", 0)), "is_boss": false,
			"background": str(_setup.get("background", "")), "enemies": _setup.get("enemies", []),
			"recommended_power": int(rv.get("power", 0))}
	elif str(params.get("mode", "")) == "tower":
		_mode = "tower"
		_floor = int(params.get("floor", Game.tower_next()))
		_stage = Game.tower_floor(_floor)
		if _stage.is_empty() or not Game.tower_unlocked() or _floor != Game.tower_next():
			_completed = true
			UI.toast("That floor is locked", "bad")
			UI.go("tower")
			return
		_index = int(_stage.index)
		_setup = Game.tower_battle_setup(_floor)
	else:
		_index = int(params.get("stage_index", Game.cleared_count()))
		_stage = Game.stage(_index)
		if _stage.is_empty() or Game.stage_status(_index) == "locked":
			_completed = true
			UI.toast("That stage is locked", "bad")
			UI.go("campaign")
			return
		_setup = Game.stage_battle_setup(_index)
	if (_setup.get("allies", []) as Array).is_empty():
		_completed = true
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	_team_size = (_setup.allies as Array).size()
	_sim = BattleSim.new(_setup)
	_sim.auto_ultimates = Game.setting("auto_ultimates") != false
	if _debug_params_ok():
		var fr := str(params.get("result", ""))
		_force_result = fr if fr in ["victory", "defeat"] else ""
		if bool(params.get("manual", false)):
			_sim.auto_ultimates = false
	var sp: Variant = Game.setting("battle_speed")
	_speed = int(sp) if (sp is int or sp is float) and [1, 2, 4].has(int(sp)) else 1
	for u: Dictionary in _sim.units:
		if u.side == "enemy" and bool(u.is_boss):
			_boss_uid = str(u.uid)
	_build()
	_layout_units()
	_start_intro()
	# Screenshots: jump to the result (params skip = true, or a forced result).
	if bool(params.get("skip", false)) or _force_result != "":
		get_tree().create_timer(0.4).timeout.connect(_skip)
	# Screenshots (debug, throwaway save): encore_demo = true plays an Encore close-up of the first
	# two heroines once the fight starts (display only; the sim is untouched).
	# tap_demo = true: spotlights the second heroine and marks the first foe once the fight starts.
	if _debug_params_ok() and bool(params.get("tap_demo", false)):
		get_tree().create_timer(INTRO_TIME + 0.4).timeout.connect(func() -> void:
			var a: Array[Node2D] = []
			var e: Array[Node2D] = []
			for uid: String in _views:
				(a if str(_views[uid].get("side")) == "ally" else e).append(_views[uid])
			if a.size() >= 2:
				_tap_unit(a[1])
			if not e.is_empty():
				_tap_unit(e[0]))
	if _debug_params_ok() and bool(params.get("encore_demo", false)):
		get_tree().create_timer(INTRO_TIME + 0.3).timeout.connect(func() -> void:
			var ids: Array[String] = []
			for uid: String in _views:
				if str(_views[uid].get("side")) == "ally":
					ids.append(uid)
			if ids.size() >= 2:
				_encore_hero = str(_views[ids[0]].get("hero_id"))
				_start_ult({"type": "ultimate", "src": ids[1], "skill_name": "Encore Demo", "targets": [], "encore": 1}))


## Debug-only params (result, manual) work in debug builds on the throwaway save only.
func _debug_params_ok() -> bool:
	var args := OS.get_cmdline_user_args()
	return OS.is_debug_build() and (args.has("--rich") or args.has("--fresh"))


func _exit_tree() -> void:
	# Leaving mid-fight (back gesture) counts as a defeat, so the battle is still
	# reported exactly once.
	if not _completed and _index >= 0 and _sim != null:
		_completed = true
		# Deferred on Game, not on this screen: the screen is freed before the call would run.
		var out := {"victory": false, "winner": "enemy", "retreat": true}
		# Leaving during the victory pose (the last foe already down) is still that result.
		if _phase == "ending":
			out = _sim.outcome()
		if _mode == "tower":
			Game.complete_tower.call_deferred(_floor, out)
		elif _mode == "champion":
			# The damage dealt before leaving still counts.
			var co := _sim.outcome()
			co["retreat"] = true
			Game.complete_champion.call_deferred(co)
		elif _mode == "rival":
			Game.complete_rival.call_deferred(out)
		else:
			Game.complete_stage.call_deferred(_index, out)


## Reports the battle to the game once: the campaign stage or the Spire floor.
func _report(outcome: Dictionary) -> Dictionary:
	if _mode == "tower":
		return Game.complete_tower(_floor, outcome)
	if _mode == "rival":
		return Game.complete_rival(outcome)
	if _mode == "champion":
		return Game.complete_champion(outcome)
	return Game.complete_stage(_index, outcome)


## Where Retreat and the result's back button lead.
func _back_screen() -> String:
	if _mode == "rival":
		return "rival"
	if _mode == "champion":
		return "front"
	return "tower" if _mode == "tower" else "campaign"


# ------------------------------------------------------------------ build

func _build() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.mouse_filter = MOUSE_FILTER_IGNORE
	_world.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_world)
	var bd := SceneBackdrop.new()
	bd.kind = str(_setup.get("background", _stage.get("background", "chapter-1")))
	bd.floor_shade = 0.0
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_world.add_child(bd)
	# Horizon and battle ring follow the field layout.
	var f := _field_rect()
	bd.horizon = clampf((f.position.y + f.size.y * 0.12) / maxf(size.y, 1.0), 0.12, 0.4) if size.y > 0.0 else 0.22
	bd.sigil_y = (f.position.y + f.size.y * 0.5) / maxf(size.y, 1.0) if size.y > 0.0 else 0.5

	_souls = SoulsCrowd.new()
	_souls.name = "Souls"
	_souls.visible = _mode != "champion"
	_world.add_child(_souls)
	_units = Node2D.new()
	_units.name = "Units"
	_world.add_child(_units)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.025, 0.035, 1.0)
	_dim.modulate.a = 0.0
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	_dim.size = Vector2(4000, 4000)
	_dim.position = Vector2(-1000, -1000)
	_units.add_child(_dim)
	_bars = Node2D.new()
	_bars.name = "Bars"
	_world.add_child(_bars)
	_fx = Node2D.new()
	_fx.name = "Fx"
	_world.add_child(_fx)
	_numbers = Control.new()
	_numbers.name = "Numbers"
	_numbers.mouse_filter = MOUSE_FILTER_IGNORE
	_numbers.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_world.add_child(_numbers)

	for u: Dictionary in _sim.units:
		var v: Node2D = UnitView.new()
		_units.add_child(v)
		# The Champion stands in her own colours (not an echo): she is the show.
		v.call("setup", u, 1.0, 1 if u.side == "ally" else -1, u.side == "enemy" and _mode != "champion", _bars)
		_views[str(u.uid)] = v
		var spr: Node2D = v.get("sprite")
		if spr and spr.has_signal("vfx_requested"):
			spr.connect("vfx_requested", _on_vfx.bind(v))

	_build_hud()
	_build_bottom()
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_overlay)
	resized.connect(_on_resized)


func _on_resized() -> void:
	_layout_units()
	var bd := _world.get_child(0)
	var f := _field_rect()
	if bd and size.y > 0.0:
		bd.set("horizon", clampf((f.position.y + f.size.y * 0.12) / size.y, 0.12, 0.4))
		bd.set("sigil_y", (f.position.y + f.size.y * 0.5) / size.y)
		(bd as CanvasItem).queue_redraw()


## Field area between the HUD and the portrait bar.
func _field_rect() -> Rect2:
	var top := UI.safe_top() + TOP_H + (BOSS_H if _boss_uid != "" else 0.0)
	var bottom := size.y - UI.safe_bottom() - BOTTOM_H
	return Rect2(0, top, size.x, maxf(bottom - top, 200.0))


func _layout_units() -> void:
	if _units == null or size.y <= 0.0:
		return
	var f := _field_rect()
	var w := f.size.x
	var pitch := w * ALLY_PITCH
	for uid: String in _views:
		var v: Node2D = _views[uid]
		var side: String = v.get("side")
		var slot: int = v.get("slot")
		var back := slot >= 2
		var sprite: Node2D = v.get("sprite")
		var boss: bool = v.get("is_boss")
		var base_h := float(sprite.call("get_height")) / maxf(absf(sprite.scale.y), 0.001)
		var k := 1.0
		if side == "ally":
			# The team: big, feet on the bottom strip, the back row a little smaller and higher.
			k = f.size.y * ALLY_H * (0.9 if back else 1.0) / maxf(base_h, 1.0)
			var li := maxi(LINE_ORDER.find(slot), 0)
			_home[uid] = Vector2(li * pitch, f.end.y - (f.size.y * 0.04 if back else 0.0) - 2.0)
			v.set("depth_scale", 1.04 if back else 1.1)
			v.set("lock_facing", true)
			v.queue_redraw()
			v.set("bars_off", true)
			v.call("bars_visible", false)
		else:
			# The foes: smaller, in the mid-ground; bosses 30% bigger with the crown on screen. The
			# war's Champion towers over the field, centred behind the team.
			k = f.size.y * FOE_H * (0.86 if back else 1.0) * (1.3 if boss else 1.0) / maxf(base_h, 1.0)
			var x := w * (float(BACK_X[clampi(slot - 2, 0, 2)]) if back else float(FRONT_X[clampi(slot, 0, 1)]))
			var y := f.position.y + f.size.y * (0.36 if back else 0.45)
			if _mode == "champion":
				k = f.size.y * 0.62 / maxf(base_h, 1.0)
				x = w * 0.5
				y = f.position.y + f.size.y * 0.66
			if boss:
				y = maxf(y, f.position.y + base_h * k + 40.0)
			_home[uid] = Vector2(x, y)
			v.set("depth_scale", 0.86 if back else 0.95)
		sprite.scale = Vector2(k, k)
		v.set("_head_h", float(sprite.call("get_height")))
	if _souls:
		_souls.call("setup", f)
	_cam_x = _clamp_cam(pitch * 2.0)
	_cam_goal = _cam_x
	_place_units()
	_layout_order()


## The camera's range along the team's line: two heroines always fill the view.
func _clamp_cam(x: float) -> float:
	var pitch := _width() * ALLY_PITCH
	return clampf(x, pitch * 0.5, pitch * 3.5)


## Puts every unit at its spot for the camera: the team slides along its line, the foes drift a
## little the other way (parallax).
func _place_units() -> void:
	var w := _width()
	var mid := w * ALLY_PITCH * 2.0
	for uid: String in _views:
		var v: Node2D = _views[uid]
		if not _home.has(uid):
			continue
		var h: Vector2 = _home[uid]
		if str(v.get("side")) == "ally":
			v.position = Vector2(w * 0.5 + h.x - _cam_x, h.y)
		else:
			v.position = Vector2(h.x - (_cam_x - mid) * FOE_PARALLAX, h.y)


## Points the camera at an ally (by uid): her spot on the line. Ignored while a recent focus or a
## swipe holds it, unless forced (ultimates).
func _focus(uid: String, force: bool = false) -> void:
	var v: Node2D = _views.get(uid)
	if v == null or str(v.get("side")) != "ally" or v.get("dead") or not _home.has(uid):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _swipe_until or (not force and now < _cam_lock_until):
		return
	_cam_goal = _clamp_cam((_home[uid] as Vector2).x)
	_cam_lock_until = now + CAM_HOLD


## The player's share of the souls: how much more of the foes' health is gone than the team's.
func _souls_share() -> float:
	var lost := {"ally": [0, 0], "enemy": [0, 0]}
	for uid: String in _views:
		var v: Node2D = _views[uid]
		var side := str(v.get("side"))
		var acc: Array = lost[side]
		acc[0] = int(acc[0]) + int(v.get("max_hp")) - int(v.get("hp"))
		acc[1] = int(acc[1]) + int(v.get("max_hp"))
	var ea: Array = lost.enemy
	var aa: Array = lost.ally
	var e := float(ea[0]) / maxf(float(ea[1]), 1.0)
	var a := float(aa[0]) / maxf(float(aa[1]), 1.0)
	return clampf(0.5 + 0.5 * (e - a), 0.0, 1.0)


## A sideways drag on the field looks along the team's line; the camera stays there a moment.
func _gui_input(event: InputEvent) -> void:
	if _phase != "fight" and _phase != "intro":
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_from = mb.position
			_drag_cam = _cam_goal
			_dragged = false
		else:
			if _drag_from != Vector2.INF and not _dragged and _phase == "fight":
				_tap_field(mb.position)
			_drag_from = Vector2.INF
		return
	var mm := event as InputEventMouseMotion
	if mm and _drag_from != Vector2.INF:
		var dx := mm.position.x - _drag_from.x
		if absf(dx) > 12.0:
			_dragged = true
			_cam_goal = _clamp_cam(_drag_cam - dx * 1.15)
			_cam_x = lerpf(_cam_x, _cam_goal, 0.5)
			_swipe_until = Time.get_ticks_msec() / 1000.0 + SWIPE_HOLD
			accept_event()


## A tap on the field: the heroine or foe under the finger (heroines first: they stand in front).
## A heroine takes the spotlight (faster ultimate, harder hits; a short cooldown between switches),
## a foe becomes the team's mark.
func _tap_field(p: Vector2) -> void:
	var best: Node2D = null
	var best_d := INF
	for side: String in ["ally", "enemy"]:
		for uid: String in _views:
			var v: Node2D = _views[uid]
			if str(v.get("side")) != side or v.get("dead"):
				continue
			var h := float(v.get("_head_h"))
			var w := h * 0.36
			var feet := v.global_position - global_position
			var r := Rect2(feet.x - w * 0.5, feet.y - h * 0.95, w, h * 0.95)
			if r.has_point(p):
				var d := absf(p.x - feet.x)
				if d < best_d:
					best = v
					best_d = d
		if best:
			break
	if best == null:
		return
	_tap_unit(best)


func _tap_unit(best: Node2D) -> void:
	var uid := str(best.get("uid"))
	if str(best.get("side")) == "ally":
		if _sim.set_spotlight(uid):
			for k: String in _views:
				_views[k].call("set_spotlit", k == uid)
			_focus(uid, true)
			_swipe_until = Time.get_ticks_msec() / 1000.0 + SWIPE_HOLD
			_float_text(best, "SPOTLIGHT", Color(1.0, 0.86, 0.5), 20, 46.0, 0.0, Vector2(0, -20), "mono_bold")
			Kit.sfx("tap")
			UI.haptic(18)
		elif _sim.spotlight() != uid:
			_float_text(best, "SPOTLIGHT COOLING", NUM_PAPER, 16, 30.0, 0.0, Vector2(0, -20), "mono_bold")
	else:
		if _sim.set_mark(uid):
			for k: String in _views:
				_views[k].call("set_marked", k == uid)
			_float_text(best, "MARKED", BP.SIG, 18, 40.0, 0.0, Vector2(0, -30), "mono_bold")
			Kit.sfx("tap")
			UI.haptic(12)
	_hide_tap_hint()


## The first fights teach the taps: a sticker over the field until the player has used them.
func _show_tap_hint() -> void:
	if Game.setting("seen_tap_hint") == true or _tap_hint != null:
		return
	var hint := _sticker(BP.PAPER)
	var l := BP.t("TAP A HEROINE: SPOTLIGHT  ·  TAP A FOE: MARK", 13, BP.INK, "mono_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_child(l)
	var f := _field_rect()
	hint.position = Vector2((_width() - 520.0) * 0.5, f.position.y + f.size.y * 0.3)
	hint.custom_minimum_size = Vector2(520, 0)
	hint.rotation = -0.015
	_overlay.add_child(hint)
	_tap_hint = hint


func _hide_tap_hint() -> void:
	if _tap_hint and is_instance_valid(_tap_hint):
		_tap_hint.queue_free()
		Game.set_setting("seen_tap_hint", true)
	_tap_hint = null


## Width of the screen (before the first layout, the viewport's).
func _width() -> float:
	return size.x if size.x > 0.0 else get_viewport_rect().size.x


func _height() -> float:
	return size.y if size.y > 0.0 else get_viewport_rect().size.y


## Top HUD (style v4 poster look): a paper strip printed like an instrument panel over the field,
## with a hairline and a tick ruler along its foot and a soft shadow under it. EXIT (a printed arrow),
## the stage block (kicker, the stage id huge in compressed type, the name, FOES / TEAM pips), the TIME
## block (the clock in compressed type over a tick ruler that empties), then AUTO (a status light),
## the battle speed as a stamp on a silver disc and SKIP with signal chevrons. A boss fight adds the
## boss band under the strip (BP.BossBand: her name huge, the HP bar crossing it, her red print).
func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.mouse_filter = MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_hud)
	var top := UI.safe_top()
	var w := _width()
	var strip_h := top + TOP_H
	if _boss_uid != "":
		_build_boss_band(strip_h, w)
	var sh := BP.shade(_hud, Rect2(0, strip_h, w, 18), true)
	sh.anchor_right = 1.0
	sh.offset_right = 0.0
	var paper := ColorRect.new()
	paper.name = "TopStrip"
	paper.color = BP.PAPER
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	paper.anchor_right = 1.0
	paper.offset_bottom = strip_h
	_hud.add_child(paper)
	var foot := ColorRect.new()
	foot.color = Color(BP.INK, 0.75)
	foot.mouse_filter = MOUSE_FILTER_IGNORE
	foot.anchor_right = 1.0
	foot.offset_top = strip_h - 1.0
	foot.offset_bottom = strip_h
	_hud.add_child(foot)
	var ruler := BP.Ticks.new()
	ruler.count = int(w / 10.0)
	ruler.major = 6
	ruler.color = Color(BP.INK, 0.45)
	ruler.anchor_right = 1.0
	ruler.offset_top = strip_h - 9.0
	ruler.offset_bottom = strip_h - 2.0
	_hud.add_child(ruler)

	var y0 := top
	# EXIT: a long printed arrow and its label.
	var ex := _hud_hit("Hud_Exit", Rect2(4, y0 + 8, 88, 88), _ask_retreat)
	var arrow := HPK.Arrow.new()
	arrow.size = Vector2(40, 16)
	arrow.position = Vector2(20, 26)
	ex.add_child(arrow)
	var exl := BP.t("Exit", 12, BP.INK, "mono_bold")
	exl.uppercase = true
	exl.position = Vector2(20, 48)
	ex.add_child(exl)
	_hud.add_child(ex)
	BP.rect(_hud, Rect2(98, y0 + 14, 1, TOP_H - 30), Color(BP.INK, 0.55))

	# The stage block.
	var kick := BP.t(("SPIRE · FLOOR" if _mode == "tower" else ("RIVAL · CHALLENGE" if _mode == "rival" else "STAGE · CH.%02d" % (int(_stage.get("chapter", 0)) + 1))), 11, Color(BP.INK, 0.7), "mono_bold")
	kick.position = Vector2(110, y0 + 10)
	_hud.add_child(kick)
	var id_text := ("F%02d" % _floor) if _mode == "tower" else str(_stage.get("id", ""))
	var idl := BP.t(id_text, 52, BP.INK, "compressed")
	idl.position = Vector2(108, y0 + 18)
	_hud.add_child(idl)
	var idw := Kit.font("compressed").get_string_size(id_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	var nx := 110.0 + idw + 12.0
	var nm := BP.t(str(_stage.get("name", "")).to_upper(), 11, BP.INK, "mono")
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	nm.clip_text = true
	nm.position = Vector2(nx, y0 + 33)
	nm.size = Vector2(maxf(312.0 - nx, 40.0), 32)
	_hud.add_child(nm)
	var n_foes := 0
	for u: Dictionary in _sim.units:
		if u.side == "enemy":
			n_foes += 1
	var fl := BP.t("FOES", 10, Color(BP.INK, 0.75), "mono_bold")
	fl.position = Vector2(110, y0 + 76)
	_hud.add_child(fl)
	_foe_dots = HUD.Dots.new()
	_foe_dots.count = n_foes
	_foe_dots.filled = n_foes
	_foe_dots.square = true
	_foe_dots.gap = 2.0
	_foe_dots.dot = 9.0
	_foe_dots.color = BP.SIG
	_foe_dots.empty = Color(BP.INK, 0.45)
	_foe_dots.position = Vector2(142, y0 + 80)
	_foe_dots.size = Vector2(n_foes * 11 - 2, 9)
	_hud.add_child(_foe_dots)
	# TEAM follows however many foes there are (five used to print over it).
	var tx := maxf(142.0 + n_foes * 11.0 + 8.0, 200.0)
	var tl := BP.t("TEAM", 10, Color(BP.INK, 0.75), "mono_bold")
	tl.position = Vector2(tx, y0 + 76)
	_hud.add_child(tl)
	_team_dots = HUD.Dots.new()
	_team_dots.count = _team_size
	_team_dots.filled = _team_size
	_team_dots.square = true
	_team_dots.gap = 2.0
	_team_dots.dot = 9.0
	_team_dots.color = BP.INK
	_team_dots.empty = Color(BP.INK, 0.45)
	_team_dots.position = Vector2(tx + 32, y0 + 80)
	_team_dots.size = Vector2(_team_size * 11 - 2, 9)
	_hud.add_child(_team_dots)
	BP.rect(_hud, Rect2(322, y0 + 14, 1, TOP_H - 30), Color(BP.INK, 0.55))

	# The TIME block.
	var tk := BP.t("TIME", 11, Color(BP.INK, 0.7), "mono_bold")
	tk.position = Vector2(334, y0 + 10)
	_hud.add_child(tk)
	_timer_label = BP.t("1:30", 46, BP.INK, "compressed")
	_timer_label.position = Vector2(332, y0 + 22)
	_hud.add_child(_timer_label)
	_time_ticks = PK.ticks(30, 30, Vector2(88, 9), Color(BP.INK, 0.4), BP.INK)
	_time_ticks.position = Vector2(334, y0 + 80)
	_hud.add_child(_time_ticks)

	# AUTO, the speed stamp and SKIP, pinned to the right edge.
	var right := Control.new()
	right.name = "HudRight"
	right.mouse_filter = MOUSE_FILTER_IGNORE
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -280.0
	right.offset_right = -8.0
	right.offset_top = y0 + 8.0
	right.offset_bottom = y0 + 96.0
	_hud.add_child(right)
	_auto_slot = _hud_hit("Hud_Auto", Rect2(0, 0, 88, 88), _toggle_auto)
	var sock := Panel.new()
	sock.mouse_filter = MOUSE_FILTER_IGNORE
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(BP.INK, 0.06)
	ss.border_color = Color(BP.INK, 0.6)
	ss.set_border_width_all(1)
	ss.set_corner_radius_all(9)
	ss.anti_aliasing = true
	sock.add_theme_stylebox_override("panel", ss)
	sock.position = Vector2(10, 14)
	sock.size = Vector2(18, 18)
	_auto_slot.add_child(sock)
	_auto_led = HUD.Led.new()
	_auto_led.mode = "breathe"
	_auto_led.color = BP.SIG
	_auto_led.position = Vector2(5, 9)
	_auto_led.size = Vector2(28, 28)
	_auto_slot.add_child(_auto_led)
	_auto_caption = BP.t("Auto", 14, BP.INK, "mono_bold")
	_auto_caption.uppercase = true
	_auto_caption.position = Vector2(10, 38)
	_auto_slot.add_child(_auto_caption)
	var asub := BP.t("ULTIMATES", 9, Color(BP.INK, 0.65), "mono")
	asub.position = Vector2(10, 58)
	_auto_slot.add_child(asub)
	right.add_child(_auto_slot)
	_rebuild_auto()

	var spd := _hud_hit("Hud_Speed", Rect2(94, 0, 88, 88), _toggle_speed)
	var disc := PK.stamp_disc(spd, Vector2(7, 7), 74.0, "SPEED · 1X · 2X · 4X · ", "%dX" % _speed, -0.12)
	_speed_stamp = disc.get_meta("stamp") as Control
	spd.button_down.connect(func() -> void: (disc as Plate).set_pressed_look(true))
	spd.button_up.connect(func() -> void: (disc as Plate).set_pressed_look(false))
	right.add_child(spd)

	var skip := _hud_hit("Hud_Skip", Rect2(184, 0, 88, 88), _skip)
	var skl := BP.t("Skip", 15, BP.INK, "mono_bold")
	skl.uppercase = true
	skl.position = Vector2(14, 20)
	skip.add_child(skl)
	var chev := PK.chevrons(3, 18.0, BP.SIG)
	chev.position = Vector2(15, 46)
	skip.add_child(chev)
	BP.rect(skip, Rect2(14, 72, 52, 1), Color(BP.INK, 0.8))
	right.add_child(skip)
	SignalKit.relight(self)


## The boss band under the top strip.
func _build_boss_band(y: float, w: float) -> void:
	var bv: Node2D = _views[_boss_uid]
	var hid := str(bv.get("hero_id"))
	var def := Game.hero_def(hid)
	var u := _sim.unit(_boss_uid)
	var fac := str(Kit.FACTION_NAMES.get(str(def.get("faction", "")), str(def.get("faction", "")))).to_upper()
	var kicker := "·  %s ECHO" % fac
	if int(u.get("level", 0)) > 0:
		kicker += "  ·  LV%d" % int(u.level)
	_boss_band = BP.BossBand.new()
	_boss_band.name = "BossBand"
	_boss_band.call("build", hid, str(def.get("name", "")), kicker, w)
	_boss_band.anchor_right = 1.0
	_boss_band.offset_left = 0.0
	_boss_band.offset_right = 0.0
	_boss_band.offset_top = y
	_boss_band.offset_bottom = y + BOSS_H
	_hud.add_child(_boss_band)
	_boss_band.call("set_hp", int(u.get("hp", 1)), int(u.get("max_hp", 1)), false)


## A bare HUD button (88 px target) that holds printed type; dims while held and plays the tap.
func _hud_hit(node_name: String, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_STOP
	b.position = r.position
	b.size = r.size
	b.button_down.connect(func() -> void:
		b.modulate.a = 0.6
		Kit.haptic(10))
	b.button_up.connect(func() -> void: b.modulate.a = 1.0)
	b.pressed.connect(func() -> void:
		Kit.sfx("tap")
		cb.call())
	return b


## AUTO's light and caption ("Auto" lit in signal, "Manual" dark) and the bottom strip's note.
func _rebuild_auto() -> void:
	var on := _sim.auto_ultimates
	if _auto_led:
		_auto_led.visible = on
	if _auto_caption:
		_auto_caption.text = "Auto" if on else "Manual"
	if _mode_note:
		_mode_note.text = "ULTIMATES · AUTO" if on else "ULTIMATES · MANUAL · TAP"


## Bottom strip (style v4 poster look): a paper strip with a hairline and a tick ruler along its top
## edge and a soft shadow over the field; the five allies as framed print cards (AllyPortrait); turned
## micro type in the margins (the squad count, the ultimates mode). Stuck on above it: the faction
## bonus as a paper sticker and the manual-mode hint as a signal sticker.
func _build_bottom() -> void:
	var w := _width()
	_bottom = Control.new()
	_bottom.name = "Bottom"
	_bottom.mouse_filter = MOUSE_FILTER_IGNORE
	_bottom.anchor_top = 1.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_top = -(BOTTOM_H + UI.safe_bottom())
	add_child(_bottom)
	var sh := BP.shade(_bottom, Rect2(0, -18, w, 18), false)
	sh.anchor_right = 1.0
	sh.offset_right = 0.0
	var paper := ColorRect.new()
	paper.name = "BottomStrip"
	paper.color = BP.PAPER
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	paper.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_bottom.add_child(paper)
	var edge := ColorRect.new()
	edge.color = Color(BP.INK, 0.75)
	edge.mouse_filter = MOUSE_FILTER_IGNORE
	edge.anchor_right = 1.0
	edge.offset_bottom = 1.0
	_bottom.add_child(edge)
	var ruler := BP.Ticks.new()
	ruler.count = int(w / 10.0)
	ruler.major = 6
	ruler.from_top = true
	ruler.color = Color(BP.INK, 0.45)
	ruler.anchor_right = 1.0
	ruler.offset_top = 1.0
	ruler.offset_bottom = 8.0
	_bottom.add_child(ruler)
	var squad := BP.t("SQUAD · %02d" % _team_size, 10, Color(BP.INK, 0.7), "mono_bold")
	squad.rotation = PI * 0.5
	squad.position = Vector2(30, 24)
	_bottom.add_child(squad)
	_mode_note = BP.t("", 10, Color(BP.INK, 0.7), "mono_bold")
	_mode_note.rotation = PI * 0.5
	_mode_note.anchor_left = 1.0
	_mode_note.anchor_right = 1.0
	_mode_note.offset_left = -12.0
	_mode_note.offset_top = 24.0
	_bottom.add_child(_mode_note)
	_rebuild_auto()
	var row := Kit.hbox(8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.anchor_right = 1.0
	row.offset_top = 16
	row.offset_bottom = 16 + AllyPortrait.HEIGHT
	_bottom.add_child(row)
	var by_slot := {}
	for u: Dictionary in _sim.units:
		if u.side == "ally":
			by_slot[int(u.slot)] = u
	for s in 5:
		if not by_slot.has(s):
			# An unused slot: an empty printed frame (heroes can't join mid-battle).
			var e := Control.new()
			e.custom_minimum_size = Vector2(PORTRAIT_W, AllyPortrait.HEIGHT)
			e.mouse_filter = MOUSE_FILTER_IGNORE
			var no := BP.t("%02d" % (s + 1), 11, Color(BP.INK, 0.4), "mono_bold")
			no.position = Vector2(0, -1)
			e.add_child(no)
			var ph := Panel.new()
			ph.mouse_filter = MOUSE_FILTER_IGNORE
			ph.add_theme_stylebox_override("panel", Kit.box(Color(BP.INK, 0.04), Color(BP.INK, 0.04), Color(BP.INK, 0.25), 0, 1))
			ph.position = Vector2(0, AllyPortrait.TOP)
			ph.size = Vector2(PORTRAIT_W, AllyPortrait.FRAME_H)
			e.add_child(ph)
			var dash := BP.t("EMPTY", 10, Color(BP.INK, 0.4), "mono_bold")
			dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dash.position = Vector2(0, AllyPortrait.TOP + AllyPortrait.FRAME_H * 0.5 - 8)
			dash.size = Vector2(PORTRAIT_W, 16)
			e.add_child(dash)
			row.add_child(e)
			continue
		var u: Dictionary = by_slot[s]
		var p: Button = AllyPortrait.new()
		p.call("setup", u, PORTRAIT_W)
		p.set("manual", not _sim.auto_ultimates)
		var uid := str(u.uid)
		p.pressed.connect(func() -> void: _on_portrait(uid))
		row.add_child(p)
		_portraits[uid] = p
	# The faction bonus as a paper sticker over the field.
	var fb := _sim.faction_bonus("ally")
	if not fb.is_empty():
		var chip := _sticker(BP.PAPER)
		var r2 := Kit.hbox(8)
		r2.mouse_filter = MOUSE_FILTER_IGNORE
		var fi := Kit.icon("faction_" + str(fb.faction), 18, BP.INK)
		fi.size_flags_vertical = SIZE_SHRINK_CENTER
		r2.add_child(fi)
		r2.add_child(BP.t("x%d  ·  +%d%% HP & ATK" % [int(fb.count), int(fb.bonus_bp) / 100], 12, BP.INK, "mono_bold"))
		chip.add_child(r2)
		chip.position = Vector2(12, -42)
		chip.rotation = -0.02
		_bottom.add_child(chip)
	var hint := _sticker(BP.SIG)
	var hl := BP.t("MANUAL  ·  TAP A FULL CARD TO CAST", 13, BP.PAPER, "mono_bold")
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_child(hl)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.grow_horizontal = GROW_DIRECTION_BOTH
	hint.offset_top = -48
	hint.offset_bottom = -14
	hint.visible = false
	_bottom.add_child(hint)
	_manual_hint = hint
	# Encore: after a heroine's ultimate, a signal sticker counts the window down; a second ultimate
	# inside it chains (by hand: +15% per step).
	var enc := _sticker(BP.INK)
	_encore_label = BP.t("", 14, BP.SIG, "mono_bold")
	_encore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enc.add_child(_encore_label)
	enc.anchor_left = 0.5
	enc.anchor_right = 0.5
	enc.grow_horizontal = GROW_DIRECTION_BOTH
	enc.offset_top = -86
	enc.offset_bottom = -52
	enc.rotation = -0.02
	enc.visible = false
	_bottom.add_child(enc)
	_encore_tag = enc


## A printed sticker (paper or signal) with a small shadow.
func _sticker(fill: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(1, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


## Shows the manual-mode hint for a few seconds.
func _flash_hint() -> void:
	if _manual_hint == null:
		return
	_manual_hint.visible = true
	_manual_hint.modulate.a = 1.0
	var tw := _manual_hint.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_manual_hint, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: _manual_hint.visible = false)


# ------------------------------------------------------------------ intro

## The units fade up into place; a printed slip with the stage slides across the field, then FIGHT
## slams in, huge in compressed signal type over an ink plate printed out of register.
func _start_intro() -> void:
	_phase = "intro"
	_phase_t = 0.0
	for uid: String in _views:
		var v: Node2D = _views[uid]
		var sprite: Node2D = v.get("sprite")
		sprite.modulate.a = 0.0
		var dy := 26.0 if v.get("side") == "ally" else -26.0
		sprite.position.y = dy
		var tw := sprite.create_tween().set_parallel(true)
		var delay := randf_range(0.0, 0.25)
		tw.tween_property(sprite, "modulate:a", 1.0, 0.35).set_delay(delay)
		tw.tween_property(sprite, "position:y", 0.0, 0.45).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		v.call("set_speed", float(_speed))
	var slip := _sticker(BP.PAPER)
	var col := Kit.vbox(0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var kick := ("SPIRE  ·  FLOOR %02d" % _floor) if _mode == "tower" else ("STAGE %s  ·  CH.%02d" % [str(_stage.get("id", "")), int(_stage.get("chapter", 0)) + 1])
	if _mode == "rival":
		kick = "RIVAL  ·  SHE CHOSE THIS TEAM FOR YOU"
	elif _mode == "champion":
		kick = "THE ENEMY CHAMPION  ·  WEAR HER DOWN"
	col.add_child(BP.t(kick, 12, BP.SIG, "mono_bold"))
	var nm := BP.t(str(_stage.get("name", "")).to_upper(), 44, BP.INK, "compressed")
	col.add_child(nm)
	var ticks := BP.Ticks.new()
	ticks.count = 40
	ticks.major = 10
	ticks.custom_minimum_size = Vector2(0, 7)
	col.add_child(ticks)
	slip.add_child(col)
	_overlay.add_child(slip)
	var ss := slip.get_combined_minimum_size()
	slip.size = ss
	slip.position = Vector2((_width() - ss.x) * 0.5, _height() * 0.42 - ss.y - 30.0)
	slip.rotation = -0.025
	Kit.offset_in(slip, Vector2(-60, 0), 0.05, 0.3)
	var tw2 := slip.create_tween()
	tw2.tween_interval(0.85)
	tw2.tween_property(slip, "modulate:a", 0.0, 0.2)
	tw2.tween_callback(slip.queue_free)
	var fight := Control.new()
	fight.mouse_filter = MOUSE_FILTER_IGNORE
	fight.size = Vector2(600, 260)
	fight.position = Vector2((_width() - 600.0) * 0.5, _height() * 0.44 - 130.0)
	fight.pivot_offset = Vector2(300, 130)
	for plate: Array in [[BP.INK, Vector2(8, 6)], [BP.SIG, Vector2.ZERO]]:
		var l := BP.t("FIGHT", 210, plate[0], "compressed")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(600, 260)
		l.position = plate[1]
		fight.add_child(l)
	fight.modulate.a = 0.0
	_overlay.add_child(fight)
	var tw3 := fight.create_tween()
	tw3.tween_interval(0.95)
	tw3.tween_callback(func() -> void:
		fight.modulate.a = 1.0
		fight.scale = Vector2(1.6, 1.6)
		UI.sfx("hit"))
	tw3.tween_property(fight, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw3.tween_interval(0.25)
	tw3.tween_property(fight, "modulate:a", 0.0, 0.2)
	tw3.tween_callback(fight.queue_free)
	if not _sim.auto_ultimates:
		_flash_hint()


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	if _sim == null:
		return
	_update_shake(delta)
	_dim.modulate.a = move_toward(_dim.modulate.a, _dim_target, delta * 4.0)
	_cam_x = lerpf(_cam_x, _cam_goal, 1.0 - exp(-delta * CAM_RATE))
	_place_units()
	if _souls and _souls_won < 0:
		_souls.call("update_share", _souls_share())
	match _phase:
		"intro":
			_phase_t += delta
			if _phase_t >= INTRO_TIME:
				_phase = "fight"
				if _mode == "stage":
					_show_tap_hint()
		"fight":
			_step_display(delta)
		"ending":
			_phase_t += delta
			if _phase_t >= END_DELAY:
				_finish(_sim.outcome())
	_update_hud()


func _step_display(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		if _hitstop > 0.0:
			return
		# (Inside an ultimate's hold the hold owns the speeds: the caster's and everyone else frozen.)
		if _hold <= 0.0:
			for uid: String in _views:
				_views[uid].call("set_speed", float(_speed))
	if _hold > 0.0:
		_hold -= delta
		if _hold > 0.0:
			return
		_end_hold()
	_display_ms += delta * 1000.0 * _speed
	while not _sim.is_over() and float(_sim.t_ms) < _display_ms + SIM_LEAD_MS:
		_ingest(_sim.step())
	while not _queue.is_empty() and float(_queue[0].at) <= _display_ms:
		var item: Dictionary = _queue.pop_front()
		_apply(item.ev)
		if _hold > 0.0 or _phase != "fight":
			break
	for uid: String in _views:
		_views[uid].call("tick_statuses", _display_ms)


func _ingest(events: Array) -> void:
	for ev: Dictionary in events:
		var t := float(ev.get("t", _sim.t_ms))
		match str(ev.type):
			"attack":
				var v: Node2D = _views.get(str(ev.src))
				var anim := str(v.call("attack_anim")) if v else "attack_melee"
				if anim == "attack_ranged":
					var rel: float = float(v.get("release_ms")) if v and float(v.get("release_ms")) > 0.0 else float(HIT_LEAD.attack_ranged)
					_push(t - rel - BOLT_MS, ev)
					_push(t - BOLT_MS, {"type": "_bolt", "src": ev.src, "target": ev.target, "t": t})
				else:
					var hit: float = float(v.get("hit_ms")) if v and float(v.get("hit_ms")) > 0.0 else float(HIT_LEAD.get(anim, 330.0))
					_push(t - hit, ev)
			"end":
				_push(t + 350.0, ev)
			_:
				_push(t, ev)


func _push(at: float, ev: Dictionary) -> void:
	_seq += 1
	var item := {"at": maxf(at, _display_ms), "seq": _seq, "ev": ev}
	var i := _queue.bsearch_custom(item, func(a: Dictionary, b: Dictionary) -> bool:
		return a.at < b.at or (a.at == b.at and a.seq < b.seq), false)
	_queue.insert(i, item)


func _apply(ev: Dictionary) -> void:
	match str(ev.type):
		"attack":
			var src: Node2D = _views.get(str(ev.src))
			var dst: Node2D = _views.get(str(ev.target))
			if src and dst and not src.get("dead"):
				src.call("play_attack", _lunge_point(src, dst))
				# The camera finds the heroine acting, or the one being hit.
				_focus(str(ev.src) if str(src.get("side")) == "ally" else str(ev.target))
		"_bolt":
			var s2: Node2D = _views.get(str(ev.src))
			var d2: Node2D = _views.get(str(ev.target))
			if s2 and d2 and not s2.get("dead"):
				var col := _fx_color(s2)
				BattleFx.projectile(_fx, _fx.to_local(s2.call("hand_global")), _fx.to_local(d2.call("chest_global")), BOLT_MS / 1000.0 / _speed, col)
		"damage":
			_on_damage(ev)
		"heal":
			var hv: Node2D = _views.get(str(ev.target))
			if hv:
				hv.call("set_hp", int(ev.hp_after), int(hv.get("shield")))
				_float_text(hv, "+%s" % Kit.format_num(int(ev.amount)), NUM_HEAL, 26, 60.0, 0.0, Vector2.ZERO, "mono_bold")
				BattleFx.burst(_fx, _fx.to_local(hv.call("chest_global")), Color("5cd6a0"), 46.0, 6)
				_sync_portrait(hv)
				if str(ev.target) == _boss_uid and _boss_band:
					_boss_band.call("set_hp", int(ev.hp_after), int(hv.get("max_hp")), false)
		"shield":
			var sv: Node2D = _views.get(str(ev.target))
			if sv:
				sv.call("set_hp", int(sv.get("hp")), int(ev.shield_after))
				_float_text(sv, "+%s" % Kit.format_num(int(ev.amount)), NUM_SHIELD, 22, 50.0, 0.0, Vector2(0, 26), "mono_bold")
				BattleFx.burst(_fx, _fx.to_local(sv.call("chest_global")), Color("8fd3ff"), 60.0, 0)
		"status":
			var tv: Node2D = _views.get(str(ev.target))
			if tv and not tv.get("dead"):
				var st := str(ev.status)
				tv.call("add_status", st, _display_ms + float(ev.duration_ms))
				var info: Array = STATUS_TEXT.get(st, [st.to_upper(), NUM_PAPER])
				_float_text(tv, str(info[0]), info[1], 18, 40.0, 0.08, Vector2(0, -34), "mono_bold")
		"ultimate":
			_start_ult(ev)
		"energy":
			var ev_v: Node2D = _views.get(str(ev.unit))
			if ev_v:
				ev_v.call("set_energy", int(ev.energy))
				var p: Node = _portraits.get(str(ev.unit))
				if p:
					p.call("set_energy", int(ev.energy))
		"death":
			var dv: Node2D = _views.get(str(ev.unit))
			if dv:
				dv.call("die")
				var dp: Node = _portraits.get(str(ev.unit))
				if dp:
					dp.call("set_dead")
				if str(ev.unit) == _boss_uid and _boss_band:
					_boss_band.call("set_hp", 0, int(dv.get("max_hp")), true)
		"end":
			_on_end(str(ev.winner))


func _on_damage(ev: Dictionary) -> void:
	var dst: Node2D = _views.get(str(ev.target))
	if dst == null:
		return
	var src: Node2D = _views.get(str(ev.src))
	dst.call("set_hp", int(ev.hp_after), int(ev.shield_after))
	_sync_portrait(dst)
	var amount := int(ev.amount)
	var crit := bool(ev.get("crit", false))
	var adv := bool(ev.get("advantage", false))
	var ult := bool(ev.get("from_ultimate", false))
	var dot := bool(ev.get("dot", false))
	var on_ally := str(dst.get("side")) == "ally"
	# Hits on echoes: paper type cut out of ink; hits on the team: ink type cut out of paper.
	var col := NUM_INK if on_ally else NUM_PAPER
	var edge := NUM_PAPER if on_ally else NUM_INK
	var fs := 36
	var weight := "compressed"
	var text := Kit.format_num(amount)
	if dot:
		col = BP.SIG_HI
		edge = NUM_INK
		fs = 20
		weight = "mono_bold"
	elif bool(ev.get("execute", false)):
		col = BP.SIG
		edge = NUM_INK
		fs = 46
		text = "EXECUTE"
	else:
		if adv and not on_ally:
			col = BP.SIG_HI
		if crit:
			col = BP.SIG
			edge = NUM_INK if not on_ally else NUM_PAPER
			fs = 50
			text += "!"
		if ult:
			fs += 6
	_float_text(dst, text, col, fs, 70.0 if not dot else 44.0, 0.0, Vector2(randf_range(-14.0, 14.0), 0), weight, edge)
	if not dot:
		dst.call("play_hit")
		var at: Vector2 = _fx.to_local(dst.call("chest_global"))
		if ult:
			BattleFx.burst(_fx, at, _fx_color(src) if src else Kit.ACCENT_HI, 80.0, 10)
		elif src and str(src.call("attack_anim")) != "attack_ranged" and not bool(src.get("has_swing_vfx")):
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), str(src.get("side")) == "enemy", 64.0 * float(dst.get("depth_scale")))
		UI.sfx("hit")
		if ult:
			_shake(11.0)
			_hit_stop(0.1)
			_screen_flash(Color(1, 1, 1), 0.35)
		elif crit:
			_shake(7.0)
			_hit_stop(0.07)
			# Against the Champion the whole team crits all the time: no flash, or the screen strobes.
			if _mode != "champion":
				_screen_flash(Color(1, 0.95, 0.8), 0.22)
		else:
			_shake(2.5)
	if str(ev.target) == _boss_uid and _boss_band:
		_boss_band.call("set_hp", int(ev.hp_after), int(dst.get("max_hp")), true)


## Freeze the display clock and every rig for `secs` (real time) on a big hit.
func _hit_stop(secs: float) -> void:
	if _hold > 0.0:
		return
	if _hitstop <= 0.0:
		for uid: String in _views:
			_views[uid].call("set_speed", 0.02)
	_hitstop = maxf(_hitstop, secs)


## The photo finish's frame: the field snaps into a photograph's white border (a thick paper edge,
## crop marks at the corners), a hair smaller and turned, and holds there until the report comes.
func _snap_frame(f: Rect2) -> void:
	var fr := _SnapFrame.new()
	fr.name = "PhotoFinish"
	fr.caption = "FIG. 01  ·  THE LAST BLOW" + ("  ·  " + _souls_line if _souls_line != "" else "")
	fr.position = f.position
	fr.size = f.size
	fr.pivot_offset = f.size * 0.5
	add_child(fr)
	# Under the overlay, where the report comes up over it.
	if _overlay and _overlay.get_parent() == self:
		move_child(fr, _overlay.get_index())
	fr.scale = Vector2(1.06, 1.06)
	fr.modulate.a = 0.0
	var tw := fr.create_tween().set_parallel(true)
	tw.tween_property(fr, "modulate:a", 1.0, 0.05)
	tw.tween_property(fr, "scale", Vector2(0.985, 0.985), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(fr, "rotation", -0.012, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## A photograph's border over the field: paper outside the picture, a hairline inside, crop marks.
class _SnapFrame:
	extends Control
	const EDGE := 14.0
	var caption := ""

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var matte := SignalKit.MATTE
		var white := Color("fcfbf8")
		# The matte far around it (the frame shrinks, so the screen outside it is covered), then the
		# print's white edge.
		var far := 400.0
		draw_rect(Rect2(-far, -far, size.x + far * 2.0, far), matte)
		draw_rect(Rect2(-far, size.y, size.x + far * 2.0, far), matte)
		draw_rect(Rect2(-far, 0, far, size.y), matte)
		draw_rect(Rect2(size.x, 0, far, size.y), matte)
		draw_rect(Rect2(0, 0, size.x, EDGE), white)
		draw_rect(Rect2(0, size.y - EDGE, size.x, EDGE), white)
		draw_rect(Rect2(0, 0, EDGE, size.y), white)
		draw_rect(Rect2(size.x - EDGE, 0, EDGE, size.y), white)
		# The print's shadow on the matte, down and to the right.
		for i in 4:
			var g := 3.0 + i * 3.0
			var a := 0.07 - i * 0.014
			draw_rect(Rect2(size.x, 8.0 + g * 0.5, g, size.y - 4.0), Color(0, 0, 0, a))
			draw_rect(Rect2(8.0 + g * 0.5, size.y, size.x - 4.0, g), Color(0, 0, 0, a))
		draw_rect(r.grow(-EDGE), Color(SignalKit.INK, 0.6), false, 1.0)
		var ink := SignalKit.INK
		for c: Vector2 in [Vector2(EDGE, EDGE), Vector2(size.x - EDGE, EDGE), Vector2(EDGE, size.y - EDGE), Vector2(size.x - EDGE, size.y - EDGE)]:
			var sx := -1.0 if c.x < size.x * 0.5 else 1.0
			var sy := -1.0 if c.y < size.y * 0.5 else 1.0
			draw_line(c + Vector2(sx * 3.0, 0), c + Vector2(sx * 12.0, 0), ink, 1.5)
			draw_line(c + Vector2(0, sy * 3.0), c + Vector2(0, sy * 12.0), ink, 1.5)
		var f := Kit.font("mono_bold")
		draw_string(f, Vector2(EDGE + 2.0, size.y + 16.0), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - EDGE * 2.0, 11, Color(ink, 0.85))


## A brief full-screen flash (additive white-ish) for crits and ultimates.
func _screen_flash(col: Color, peak: float) -> void:
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.name = "HitFlash"
		_flash_rect.mouse_filter = MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_flash_rect.material = m
		_world.add_child(_flash_rect)
	_flash_rect.color = Color(col, peak)
	_flash_rect.modulate.a = 1.0
	var tw := _flash_rect.create_tween()
	tw.tween_property(_flash_rect, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Effects the hero animations ask for (animation events named "vfx_<kind>").
func _on_vfx(kind: String, pos: Vector2, facing: int, v: Node2D) -> void:
	var at := _fx.to_local(pos)
	var col := _fx_color(v)
	var k := float(v.get("depth_scale"))
	match kind:
		"slash":
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), facing < 0, 62.0 * k)
		"thrust":
			BattleFx.slash(_fx, at, Color(1.0, 0.95, 0.85), facing < 0, 44.0 * k)
		"bolt":
			BattleFx.burst(_fx, at, col, 26.0 * k, 4)
		"burst":
			BattleFx.burst(_fx, at, col, 72.0 * k, 10)
		"charge":
			BattleFx.burst(_fx, at, col, 44.0 * k, 6)
		"sparkle":
			BattleFx.burst(_fx, at, Kit.GOLD_LIGHT, 34.0 * k, 6)
		"dissolve":
			BattleFx.burst(_fx, at, Color("b48cff"), 80.0 * k, 12)


## Floating-number lifetime factor for the current battle speed.
func _life() -> float:
	return 1.0 / sqrt(float(_speed))


func _sync_portrait(v: Node2D) -> void:
	var p: Node = _portraits.get(str(v.get("uid")))
	if p:
		p.call("set_hp", int(v.get("hp")))


## Where a melee lunge should stop: just short of the target, along the line between them.
func _lunge_point(src: Node2D, dst: Node2D) -> Vector2:
	var a := src.global_position
	var b := dst.global_position
	# Front view: the big heroines step a little toward their mark; foes come further forward.
	return a + (b - a) * (0.16 if str(src.get("side")) == "ally" else 0.3)


## Spawn point for a floating number over a unit. Numbers that land on the same unit in
## quick succession fan out (up and to alternating sides) instead of piling up; _num_n is
## the slot used (0-3).
func _num_pos(v: Node2D) -> Vector2:
	var uid := str(v.get("uid"))
	var now := Time.get_ticks_msec()
	var st: Array = _num_stack.get(uid, [0, 0])
	var n := int(st[1]) + 1 if now - int(st[0]) < 320 else 0
	_num_stack[uid] = [now, n % 4]
	_num_n = n % 4
	return v.call("head_global") - _numbers.global_position + NUM_FAN[_num_n]


## A floating number or status word over unit `v`, kept below the HUD: when it would rise
## into the top bar (top-row enemies on short screens) it starts lower, and its fan slot
## stacks downward instead.
func _float_text(v: Node2D, text: String, col: Color, fs: int, rise: float, delay: float = 0.0, extra: Vector2 = Vector2.ZERO,
		weight: String = "compressed", edge: Color = NUM_INK) -> void:
	var pos := _num_pos(v) + extra
	var lo := _hud_bottom() + 8.0 + fs * 0.75 + rise
	if pos.y < lo:
		pos.y = lo + _num_n * 30.0 + maxf(extra.y, 0.0)
	pos.x = clampf(pos.x, 70.0, size.x - 70.0)
	BattleFx.number(_numbers, pos, text, col, fs, rise, delay, _life(), weight, edge)


## Bottom edge of the top strip (and the boss band) in the numbers layer's space.
func _hud_bottom() -> float:
	var b := UI.safe_top() + TOP_H + (BOSS_H if _boss_uid != "" else 0.0)
	return b - _numbers.global_position.y


func _fx_color(v: Node2D) -> Color:
	if v == null:
		return Kit.ACCENT_HI
	if str(v.get("side")) == "enemy":
		return Color("b48cff")
	return HeroArt.faction_color(str(v.get("faction"))).lightened(0.3)


# ------------------------------------------------------------------ ultimates

func _start_ult(ev: Dictionary) -> void:
	var v: Node2D = _views.get(str(ev.src))
	if v == null or v.get("dead"):
		return
	var ally := str(v.get("side")) == "ally"
	if ally:
		_focus(str(ev.src), true)
	# The caster's wind-up plays during the hold; enemy ultimates wind up faster so the
	# player's own heroes get the longer, bigger moment.
	var cs := minf(float(_speed), 2.0) * (1.0 if ally else 1.6)
	var hit_s: float = float(v.get("ult_hit_s"))
	var d := (hit_s if hit_s > 0.0 else ULT_HIT_S) / cs
	if ally:
		# The player's close-up (UltCinematic) gets at least 1.5 s at 1x before the hit lands.
		d = maxf(d, 1.5 / cs)
	_hold = d
	_hold_view = v
	for uid: String in _views:
		var u: Node2D = _views[uid]
		u.call("set_speed", cs if u == v else 0.0)
		u.call("bars_visible", u == v)
	var target := Vector2.INF
	var targets: Array = ev.get("targets", [])
	if not targets.is_empty():
		var tv: Node2D = _views.get(str(targets[0]))
		if tv and str(tv.get("side")) != str(v.get("side")):
			target = _lunge_point(v, tv)
	v.call("play_ultimate", target)
	_units.move_child(v, -1)
	_dim_target = 0.62 if ally else 0.4
	var c: Control = UltCinematic.new()
	_overlay.add_child(c)
	var step := int(ev.get("encore", 0))
	var partner := _encore_hero if ally and step > 0 and _encore_hero != str(v.get("hero_id")) else ""
	c.call("play", str(v.get("hero_id")), str(ev.get("skill_name", "Ultimate")), ally, d + 0.12, partner, step)
	if ally:
		_encore_hero = str(v.get("hero_id"))
		_encore_until = _display_ms + float(BattleSim.ENCORE_WINDOW_MS)
	UI.sfx("ult")
	UI.haptic(40 if ally else 20)
	_shake(4.0)
	var p: Node = _portraits.get(str(ev.src))
	if p:
		p.set("queued", false)


func _end_hold() -> void:
	_hold = 0.0
	_dim_target = 0.0
	for uid: String in _views:
		var u: Node2D = _views[uid]
		u.call("set_speed", float(_speed))
		u.call("bars_visible", true)
	if _hold_view and is_instance_valid(_hold_view):
		var ally := str(_hold_view.get("side")) == "ally"
		_shake(12.0 if ally else 8.0)
	_hold_view = null
	_layout_order()


## Restores depth order after a caster was raised above the dim.
func _layout_order() -> void:
	var order: Array = []
	for uid: String in _views:
		order.append(_views[uid])
	order.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.position.y < b.position.y)
	for i in order.size():
		_units.move_child(order[i], i)
	_units.move_child(_dim, -1)


func _on_portrait(uid: String) -> void:
	if _phase != "fight" and _phase != "intro":
		return
	var p: Node = _portraits.get(uid)
	var v: Node2D = _views.get(uid)
	if p == null or v == null or v.get("dead"):
		return
	if int(v.get("energy")) < 1000:
		UI.toast("%s is still charging" % str(Game.hero_def(str(v.get("hero_id"))).get("name", "")))
		return
	if _sim.request_ultimate(uid):
		UI.sfx("tap")
		p.call("mark_queued")
	elif _sim.auto_ultimates or bool(p.get("queued")):
		p.call("mark_queued")
	elif (_sim.unit(uid).get("statuses", {}) as Dictionary).has("stun"):
		UI.toast("%s is stunned" % str(Game.hero_def(str(v.get("hero_id"))).get("name", "")), "bad")


# ------------------------------------------------------------------ controls

func _toggle_auto() -> void:
	var on := not _sim.auto_ultimates
	_sim.auto_ultimates = on
	Game.set_setting("auto_ultimates", on)
	_rebuild_auto()
	for uid: String in _portraits:
		var p: Node = _portraits[uid]
		p.set("manual", not on)
		(p as CanvasItem).queue_redraw()
	if not on and _phase != "result":
		_flash_hint()
	else:
		_manual_hint.visible = false
	UI.toast("Auto ultimates on" if on else "Manual ultimates")


func _toggle_speed() -> void:
	_speed = {1: 2, 2: 4, 4: 1}.get(_speed, 1)
	Game.set_setting("battle_speed", _speed)
	if _speed_stamp:
		_speed_stamp.set("value", "%dX" % _speed)
		_speed_stamp.queue_redraw()
	if _hold <= 0.0:
		for uid: String in _views:
			_views[uid].call("set_speed", float(_speed))


func _skip() -> void:
	if _phase == "result" or _completed:
		return
	var out := _sim.run_to_end()
	_queue.clear()
	_hold = 0.0
	_dim_target = 0.0
	for c in _overlay.get_children():
		c.queue_free()
	for u: Dictionary in _sim.units:
		var v: Node2D = _views.get(str(u.uid))
		if v == null:
			continue
		v.call("set_speed", float(_speed))
		v.call("bars_visible", true)
		v.call("snap_to", u)
		var p: Node = _portraits.get(str(u.uid))
		if p:
			if bool(u.alive):
				p.call("set_hp", int(u.hp))
				p.call("set_energy", int(u.energy))
			else:
				p.call("set_dead")
	if _boss_band and _boss_uid != "":
		var bu := _sim.unit(_boss_uid)
		_boss_band.call("set_hp", int(bu.get("hp", 0)) if bool(bu.get("alive", true)) else 0, int(bu.get("max_hp", 1)), true)
	_display_ms = float(_sim.t_ms)
	var winner := str(out.get("winner", "enemy"))
	if _force_result != "":
		winner = "ally" if _force_result == "victory" else "enemy"
	_on_end(winner)
	_phase_t = END_DELAY - 0.5


func _ask_retreat() -> void:
	if _completed:
		UI.go(_back_screen())
		return
	var ask := "Retreat from her? The damage you've done still counts." if _mode == "champion" else "Retreat from this battle? It counts as a defeat."
	UI.confirm(ask, func() -> void:
		if _completed:
			return
		# The last foe fell while the question was up: that is the result, not a retreat.
		if _phase == "ending":
			_finish(_sim.outcome())
			return
		_completed = true
		var out := {"victory": false, "winner": "enemy", "retreat": true}
		if _mode == "champion":
			# The damage dealt before leaving still counts (the same as leaving by Back).
			out = _sim.outcome()
			out["retreat"] = true
		_report(out)
		UI.go(_back_screen()), Callable(), "Retreat", "Keep fighting", true)


# ------------------------------------------------------------------ end

func _on_end(winner: String) -> void:
	if _phase == "ending" or _phase == "result":
		return
	_phase = "ending"
	_phase_t = 0.0
	_manual_hint.visible = false
	if _mode == "champion":
		_souls_won = 0
	if _souls and _souls_won < 0:
		_souls_won = int(_souls.call("finish", winner == "ally"))
		# The slip only where the win really pays souls (not Rue's fights, not before the war opens).
		if winner == "ally" and _mode != "rival" and Game.war_unlocked():
			# Where they go: the player's sector on the front (WarRules), or a nudge to pick a side.
			var to := ""
			var war: Dictionary = Game.war()
			if str(war.side) == "":
				to = "  ·  PICK A SIDE ON THE FRONT"
			else:
				to = "  →  " + str(((war.sectors as Array)[int(war.focus)] as Dictionary).name).to_upper()
			_souls_line = "+%d SOULS%s" % [_souls_won, to]
			var slip := BP.t(_souls_line, 40 if to == "" else 30, Color(1.0, 0.82, 0.42), "compressed")
			slip.position = Vector2(20.0, _field_rect().position.y + _field_rect().size.y * 0.5)
			slip.size = Vector2(_width() - 40.0, 60)
			slip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_overlay.add_child(slip)
			var tw := slip.create_tween()
			tw.tween_property(slip, "position:y", slip.position.y + 160.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(slip, "modulate:a", 0.0, 0.5).set_delay(0.7)
	for uid: String in _views:
		var v: Node2D = _views[uid]
		if not v.get("dead") and (str(v.get("side")) == "ally") == (winner == "ally"):
			var sprite: Node2D = v.get("sprite")
			sprite.call("set_facing", int(v.get("home_facing")))
			sprite.call("play_victory")
	if winner == "ally":
		_photo_finish()


## The photo finish: the frame the last foe fell on is taken (the field, as it was drawn), with a
## shutter's click and flash and a short freeze; the victory poster prints it as its press photo.
func _photo_finish() -> void:
	# The overlay (the souls slip, the tap hint) stays out of the picture; with the frame it stays
	# hidden until the report (the slip's line goes on the photo's caption instead).
	if _overlay:
		_overlay.visible = false
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _phase == "result":
		return
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty() or not Kit.motion_ok():
		_overlay.visible = true
	if img == null or img.is_empty():
		return
	var vs := get_viewport_rect().size
	var k := float(img.get_width()) / maxf(vs.x, 1.0)
	var f := _field_rect()
	var gr := get_global_rect()
	var r := Rect2i(Vector2i((gr.position + f.position) * k), Vector2i(f.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x < 8 or r.size.y < 8:
		_overlay.visible = true
		return
	_photo = ImageTexture.create_from_image(img.get_region(r))
	UI.sfx("shutter")
	UI.haptic(20)
	if Kit.motion_ok():
		_screen_flash(Color(1, 1, 1), 0.7)
		_snap_frame(f)
		# Everyone holds still for a beat, as in the picture.
		for uid: String in _views:
			_views[uid].call("set_speed", 0.02)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			for uid: String in _views:
				_views[uid].call("set_speed", float(_speed)))


func _finish(outcome: Dictionary) -> void:
	if _completed:
		return
	_completed = true
	_phase = "result"
	if _overlay:
		_overlay.visible = true
	if _force_result != "":
		outcome = _forced(outcome)
	var res := _report(outcome)
	var val: Dictionary = res.get("value", {}) if res.get("value") is Dictionary else {}
	if _mode == "rival":
		_finish_rival(outcome, val)
		return
	if _mode == "champion":
		_finish_champion(val)
		return
	var r: Control = BattleResult.new()
	r.set("on_action", _on_result_action)
	_overlay.add_child(r)
	if bool(outcome.get("victory", false)):
		UI.sfx("victory")
		UI.haptic(30)
		var has_next: bool
		var next_text: String
		if _mode == "tower":
			has_next = _floor < Game.tower_floors()
			next_text = "Next Floor"
		else:
			var nxt := _index + 1
			has_next = nxt < Game.stages().size() and Game.stage_status(nxt) != "locked"
			var new_chapter := has_next and int(Game.stage(nxt).get("chapter", 0)) != int(_stage.get("chapter", 0))
			next_text = "Next Chapter" if new_chapter else "Next Stage"
		r.call("show_victory", {
			"stage": _stage, "outcome": outcome, "reward": val.get("reward", {}),
			"first_clear": bool(val.get("first_clear", false)), "stars": _stars(outcome),
			"team_size": _team_size, "mvp": _mvp(outcome), "has_next": has_next,
			"next_text": next_text, "back_text": "Spire" if _mode == "tower" else "Campaign",
			"safe_top": UI.safe_top(), "safe_bottom": UI.safe_bottom(),
			"mode": _mode, "floor": _floor, "report_no": _report_no(), "souls": int(val.get("souls", 0)),
			"photo": _photo,
		})
	else:
		UI.sfx("defeat")
		r.call("show_defeat", {
			"stage": _stage, "outcome": outcome, "team_power": int(Game.team_power()),
			"safe_top": UI.safe_top(), "safe_bottom": UI.safe_bottom(),
			"mvp": _mvp(outcome), "foe": _foe_mvp(outcome), "team_size": _team_size,
			"mode": _mode, "floor": _floor, "report_no": _report_no(),
		})


## The Champion's result: a printed sheet with the damage huge, the week's bar with its tiers, any
## tier rewards just reached; OK goes back to the front.
func _finish_champion(val: Dictionary) -> void:
	UI.sfx("victory")
	UI.haptic(30)
	var ch: Dictionary = (Game.war() as Dictionary).get("champion", {})
	var col := Kit.vbox(8)
	col.custom_minimum_size.x = 560
	col.add_child(BP.t("THE ENEMY CHAMPION  ·  %s" % str(ch.get("name", "")).to_upper(), 12, BP.SIG, "mono_bold"))
	var big := BP.t(Kit.format_full(int(val.get("damage", 0))), 96, BP.INK, "compressed")
	col.add_child(big)
	col.add_child(BP.t("DAMAGE THIS FIGHT  ·  %d%% OF HER WORN DOWN THIS WEEK" % int(val.get("pct", 0)), 12, BP.INK, "mono_bold"))
	var bar := ChampBar.new()
	bar.custom_minimum_size = Vector2(560, 46)
	bar.set("champ", ch)
	col.add_child(bar)
	var rw: Dictionary = val.get("reward", {})
	if not rw.is_empty():
		col.add_child(BP.t("TIER REACHED", 11, BP.SIG, "mono_bold"))
		col.add_child(Kit.reward_receipt(rw, 560.0, {"compact": true}))
	col.add_child(BP.t("%d TR%s LEFT TODAY" % [int(ch.get("tries_left", 0)), "Y" if int(ch.get("tries_left", 0)) == 1 else "IES"], 11, Color(BP.INK, 0.6), "mono"))
	UI.popup("Champion", col, func() -> void: UI.go("front"), 640.0, true)


## The Champion's week as a bar: the share worn down in ink, the tiers as ticks (signal once reached).
class ChampBar:
	extends Control
	var champ: Dictionary = {}

	func _draw() -> void:
		var w := size.x
		var y := 8.0
		var h := 16.0
		draw_rect(Rect2(0, y, w, h), Color(0.063, 0.067, 0.075, 0.12))
		var pct := clampf(float(champ.get("pct", 0)) / 100.0, 0.0, 1.0)
		draw_rect(Rect2(0, y, w * pct, h), Color(0.063, 0.067, 0.075))
		var f := Kit.font("mono_bold")
		for t: Variant in champ.get("tiers", []):
			var td := t as Dictionary
			var x := w * float(td.pct) / 100.0
			var on := bool(td.done)
			draw_line(Vector2(x, y - 4), Vector2(x, y + h + 4), SignalKit.SIGNAL if on else Color(0.063, 0.067, 0.075, 0.6), 2.0)
			draw_string(f, Vector2(x - 30, y + h + 18), "%d%%" % int(td.pct), HORIZONTAL_ALIGNMENT_CENTER, 60, 10,
				SignalKit.SIGNAL if on else Color(0.063, 0.067, 0.075, 0.7))


## The Rival's result poster: YOU BEAT RUE (the haul, her print, your tag) or RUE WINS (costs nothing).
func _finish_rival(outcome: Dictionary, val: Dictionary) -> void:
	var r: Control = RivalResult.new()
	r.set("on_action", _on_result_action)
	_overlay.add_child(r)
	var win := bool(outcome.get("victory", false))
	UI.sfx("victory" if win else "defeat")
	if win:
		UI.haptic(30)
	r.call("show_rival", {"victory": win, "value": val, "outcome": outcome, "mvp": _mvp(outcome), "foe": _foe_mvp(outcome),
		"team_size": _team_size, "safe_top": UI.safe_top(), "safe_bottom": UI.safe_bottom(), "report_no": _report_no(),
		"rival": Game.rival()})


## Debug screenshots: the outcome turned into the forced result (counts kept plausible).
func _forced(outcome: Dictionary) -> Dictionary:
	var o := outcome.duplicate(true)
	var win := _force_result == "victory"
	o["victory"] = win
	o["winner"] = "ally" if win else "enemy"
	if win and int(o.get("allies_alive", 0)) <= 0:
		o["allies_alive"] = _team_size
	if not win and int(o.get("enemies_alive", 0)) <= 0:
		o["enemies_alive"] = 1
	if not win:
		o["timeout"] = false
	return o


## The battle report's serial number (battles fought so far).
func _report_no() -> int:
	return int(Game.counter("battles_won")) + int(Game.counter("battles_lost"))


## The echo that dealt the most damage: {hero_id, damage}.
func _foe_mvp(outcome: Dictionary) -> Dictionary:
	var dmg: Dictionary = outcome.get("damage_dealt", {})
	var best := ""
	var best_n := -1
	for uid: String in dmg:
		if uid.begins_with("a") or not _views.has(uid):
			continue
		if int(dmg[uid]) > best_n:
			best_n = int(dmg[uid])
			best = uid
	if best == "":
		return {}
	return {"hero_id": str(_views[best].get("hero_id")), "damage": best_n}


## 3 stars with nobody lost, 2 with at least half the team standing, else 1.
func _stars(outcome: Dictionary) -> int:
	var alive := int(outcome.get("allies_alive", 0))
	if alive >= _team_size:
		return 3
	if alive * 2 >= _team_size:
		return 2
	return 1


func _mvp(outcome: Dictionary) -> Dictionary:
	var dmg: Dictionary = outcome.get("damage_dealt", {})
	var best := ""
	var best_n := -1
	var total := 0
	for uid: String in dmg:
		if not uid.begins_with("a"):
			continue
		var n := int(dmg[uid])
		total += n
		if n > best_n:
			best_n = n
			best = uid
	if best == "" or not _views.has(best):
		return {}
	return {"hero_id": str(_views[best].get("hero_id")), "damage": best_n, "share": (best_n * 100 / maxi(1, total))}


func _on_result_action(action_name: String) -> void:
	match action_name:
		"home":
			UI.go("home")
		"next":
			if _mode == "tower":
				UI.go("battle", {"mode": "tower", "floor": _floor + 1})
				return
			var nxt := _index + 1
			if int(Game.stage(nxt).get("chapter", 0)) != int(_stage.get("chapter", 0)):
				UI.go("campaign", {"open_stage": nxt})
			else:
				UI.go("battle", {"stage_index": nxt})
		"rival":
			UI.go("rival")
		"retry":
			if _mode == "rival":
				UI.go("battle", {"mode": "rival"})
				return
			if _mode == "tower":
				UI.go("battle", {"mode": "tower", "floor": _floor})
			else:
				UI.go("battle", {"stage_index": _index})
		"campaign":
			UI.go(_back_screen())
		"heroes":
			UI.go("heroes")
		"level":
			# Straight to the team hero who most needs a level (else the hero list).
			var lid := Guide.level_target()
			if lid != "":
				UI.go("hero_detail", {"hero_id": lid, "browse": Game.formation().filter(func(x: Variant) -> bool: return str(x) != "")})
			else:
				UI.go("heroes")
		"formation":
			UI.go("formation")


# ------------------------------------------------------------------ hud & feel

## The clock, its tick ruler (one tick per 3 s left; signal in the last 10 s) and the FOES / TEAM
## pips (who is still standing on the display clock).
func _update_hud() -> void:
	if _timer_label == null:
		return
	if _encore_tag:
		var left := (_encore_until - _display_ms) / 1000.0
		var on := _phase == "fight" and _hold <= 0.0 and left > 0.0
		_encore_tag.visible = on
		if on:
			_encore_label.text = "ENCORE  ·  %.1f S  ·  CAST ANOTHER TO CHAIN" % left
	var foes := 0
	var team := 0
	for uid: String in _views:
		var v: Node2D = _views[uid]
		if not v.get("dead"):
			if str(v.get("side")) == "ally":
				team += 1
			else:
				foes += 1
	var sig := "%d/%d" % [foes, team]
	if sig != _alive_sig:
		_alive_sig = sig
		if _foe_dots:
			_foe_dots.set("filled", foes)
			_foe_dots.queue_redraw()
		if _team_dots:
			_team_dots.set("filled", team)
			_team_dots.queue_redraw()
	var max_ms := maxi(1, int(_sim.max_ms))
	var secs := maxi(0, int(max_ms - _display_ms)) / 1000
	if secs == _shown_secs:
		return
	_shown_secs = secs
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	if _time_ticks:
		_time_ticks.set("filled", ceili(30.0 * secs * 1000.0 / float(max_ms)))
		if secs <= 10:
			_time_ticks.set("on", BP.SIG)
		_time_ticks.queue_redraw()
	if secs <= 10:
		_timer_label.add_theme_color_override("font_color", BP.SIG)


func _shake(amount: float) -> void:
	_shake_amp = maxf(_shake_amp, amount)
	_shake_t = 0.28


func _update_shake(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var k := maxf(_shake_t, 0.0) / 0.28
		_world.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp * k
		if _shake_t <= 0.0:
			_shake_amp = 0.0
			_world.position = Vector2.ZERO
