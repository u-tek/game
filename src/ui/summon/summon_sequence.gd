extends Control
## The full-screen summon sequence (owner, 2026-10-19: "a really cool animation ... show a
## splash of each hero, so 10 cards that the user has to actually tap through, and then a
## big reveal if the user gets a rare card"). The summon screen creates it with Game.summon's
## results; it plays three phases:
##
##   charge   (2.7 s) The portal charges: a rune sigil spins up and lights rune by rune, light
##            streaks and motes pour into a growing core, the camera starts to shake. Its
##            color is the rarity tell: aqua drifting to blue for Rares only, violet at
##            1.05 s if an Epic is inside, then an "upgrade" to gold with lightning at 1.8 s
##            for a Legendary. Then the core implodes and bursts (flash, shockwaves).
##   reveal   One hero at a time (summon_reveal.gd), the player taps through: a tap
##            fast-forwards the current hero, the next tap brings the next one. Pips at the
##            top show how many are left and the rarities seen so far.
##   results  All heroes on cards (5x2 grid, or one big card), NEW / shards, the totals, the
##            pity counter, "Summon xN Again" and "Done".
##
## "Skip" (top-right) jumps to the results from anywhere. A tap during the charge jumps to the
## burst. Signals: done (Done pressed), again(count) (Summon again pressed).
## Phase names ("charge", "reveal", "results") are what the e2e scripts wait for.

signal done
signal again(count: int)

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const Backdrop := preload("res://src/ui/summon/summon_backdrop.gd")
const Portal := preload("res://src/ui/summon/summon_portal.gd")
const Burst := preload("res://src/ui/summon/summon_burst.gd")
const Reveal := preload("res://src/ui/summon/summon_reveal.gd")

const CHARGE_TIME := 2.7
const TELL_1 := 1.05
const TELL_2 := 1.8
const BURST_GAP := 0.42
const RARITY_ORDER := {"rare": 0, "epic": 1, "legendary": 2}
const CARD_RATIO := 1.62

## "charge" | "reveal" | "results" ("" before start).
var phase := ""
var results: Array = []
## The summary cards (one holder per result), filled in the results phase.
var cards: Array[Control] = []
## The current reveal while it is a Legendary (the big showcase), else null.
var showcase: Control
## Index of the hero being revealed.
var index := -1
## count -> {currency, amount, ok}: the price of summoning again (the screen's _price).
var price_of: Callable
## Pulls left to the Legendary guarantee, for the results line.
var pity_left := 0

var _best := "rare"
var _cam: Control
var _backdrop: Backdrop
var _portal: Portal
var _flash: ColorRect
var _summary: Control
var _ui: Control
var _skip: Button
var _hint: Label
var _pips: Pips
var _reveal: Reveal
var _next: Reveal
var _next_i := -1
var _charge_t := 0.0
var _tells := 0
var _gap_left := -1.0
var _time := 0.0
var _base_trauma := 0.0
var _kick := 0.0
var _punch := 0.0
var _flash_a := 0.0
var _flash_col := Color.WHITE
var _portal_col := Kit.ACCENT
var _grid_box: Control
var _results_box: VBoxContainer
# Hero images loading on a worker thread during the charge, and the loaded ones (kept so
# they stay cached until the reveals use them).
var _warm_paths: Array[String] = []
var _warm: Array[Resource] = []
## Debug / screenshots: stop the charge clock at `t` seconds.
var charge_hold := -1.0


func setup(res: Array, price: Callable, pity: int) -> void:
	results = res
	price_of = price
	pity_left = pity
	for x: Variant in results:
		var rr := str((x as Dictionary).get("rarity", "rare"))
		if int(RARITY_ORDER.get(rr, 0)) > int(RARITY_ORDER.get(_best, 0)):
			_best = rr
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_backdrop = Backdrop.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)
	_cam = Control.new()
	_cam.name = "Camera"
	_cam.mouse_filter = MOUSE_FILTER_IGNORE
	_cam.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_cam)
	_summary = Control.new()
	_summary.name = "Summary"
	_summary.mouse_filter = MOUSE_FILTER_IGNORE
	_summary.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_summary)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.visible = false
	# Additive: a flash brightens the scene toward white instead of veiling it in a flat tint.
	_flash.material = Fx.additive()
	add_child(_flash)
	_ui = Control.new()
	_ui.name = "Hud"
	_ui.mouse_filter = MOUSE_FILTER_IGNORE
	_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_ui)
	_build_hud()
	resized.connect(_on_resized)
	_on_resized()
	_warm_art()


## Starts loading every pulled hero's painted image (base look and equipped skin) on a
## worker thread, so building each reveal later doesn't stall a frame on the main thread
## (~35 ms per 1024x2048 image on a desktop). Not in headless runs: the dummy renderer's
## texture allocation isn't thread-safe (GL Compatibility queues it to the render thread).
func _warm_art() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for x: Variant in results:
		var id := str((x as Dictionary).get("hero_id", ""))
		var paths: Array[String] = [RigData.file_base(id) + ".png"]
		var skin := Game.equipped_skin(id)
		if skin != "" and HeroArt.has_skin_art(id, skin):
			paths.append(RigData.file_base(id, str(SkinData.get_def(skin).get("art", ""))) + ".png")
		for p in paths:
			if _warm_paths.has(p) or not ResourceLoader.exists(p) or ResourceLoader.has_cached(p):
				continue
			if ResourceLoader.load_threaded_request(p) == OK:
				_warm_paths.append(p)


func _poll_warm() -> void:
	for i in range(_warm_paths.size() - 1, -1, -1):
		var st := ResourceLoader.load_threaded_get_status(_warm_paths[i])
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_warm.append(ResourceLoader.load_threaded_get(_warm_paths[i]))
		_warm_paths.remove_at(i)


func _build_hud() -> void:
	var st := UI.safe_top()
	var sb := UI.safe_bottom()
	_pips = Pips.new()
	_pips.name = "Pips"
	_pips.count = results.size()
	_pips.anchor_right = 1.0
	_pips.offset_top = st + 26.0
	_pips.offset_bottom = st + 74.0
	_pips.visible = false
	_ui.add_child(_pips)
	_skip = Kit.secondary_button("Skip", skip_all, "skip")
	_skip.name = "Skip"
	_skip.mouse_filter = MOUSE_FILTER_STOP
	_skip.custom_minimum_size = Vector2(150, Kit.BUTTON_H)
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -166.0
	_skip.offset_right = -16.0
	_skip.offset_top = st + 6.0
	_skip.offset_bottom = st + 6.0 + Kit.BUTTON_H
	_skip.modulate.a = 0.85
	_ui.add_child(_skip)
	_hint = Kit.label("TAP TO CONTINUE", 24, Kit.INK, "cond_bold", 5)
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -sb - 78.0
	_hint.offset_bottom = -sb - 40.0
	_hint.modulate.a = 0.0
	_ui.add_child(_hint)


func _on_resized() -> void:
	if _cam:
		_cam.pivot_offset = size * 0.5


## The portal's centre (a little above the middle of the safe area).
func _focus() -> Vector2:
	var st := UI.safe_top()
	var h := size.y if size.y > 0.0 else get_viewport_rect().size.y
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	return Vector2(w * 0.5, st + (h - st - UI.safe_bottom()) * 0.44)


# ------------------------------------------------------------------ phases

## Starts the charge. fade_in: fade the whole sequence in (false when replacing another one).
func start(fade_in: bool = true) -> void:
	phase = "charge"
	_charge_t = 0.0
	_tells = 0
	var w := get_viewport_rect().size.x
	_portal = Portal.new()
	_portal.name = "Portal"
	_portal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_portal.center = _focus()
	_portal.radius = w * 0.4
	_cam.add_child(_portal)
	_portal_col = Kit.ACCENT
	_backdrop.focus = _portal.center
	_backdrop.target_tint = Kit.ACCENT
	_backdrop.target_amount = 0.3
	_backdrop.snap()
	if fade_in:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
	UI.sfx("portal")
	UI.haptic(15)


## Debug / screenshots: skip the charge and start revealing hero `i` right away. hold >= 0
## stops that hero's clock at `hold` seconds (a still of one moment).
func start_at(i: int, hold: float = -1.0) -> void:
	phase = "reveal"
	if _portal and is_instance_valid(_portal):
		_portal.queue_free()
	_portal = null
	_backdrop.snap()
	_pips.visible = results.size() > 1
	for k in i:
		_pips.colors[k] = Kit.rarity_color(str((results[k] as Dictionary).get("rarity", "rare")))
	_show_card(clampi(i, 0, results.size() - 1))
	_reveal.hold = hold


func _process(delta: float) -> void:
	_time += delta
	if not _warm_paths.is_empty():
		_poll_warm()
	match phase:
		"charge":
			_step_charge(delta)
		"reveal":
			_step_reveal(delta)
	_step_fx(delta)


func _step_charge(delta: float) -> void:
	_charge_t = _charge_t + delta if charge_hold < 0.0 else minf(_charge_t + delta, charge_hold)
	var k := clampf(_charge_t / CHARGE_TIME, 0.0, 1.0)
	_portal.reveal = Fx.out_cubic(Fx.k01(_charge_t, 0.0, 0.4))
	_portal.charge = k
	var target := _tell_color(_charge_t)
	_portal_col = _portal_col.lerp(target, 1.0 - exp(-delta * 9.0))
	_portal.color = _portal_col
	_portal.crackle = Fx.k01(_charge_t, TELL_2, TELL_2 + 0.25) if _best == "legendary" else 0.0
	_portal.implode = Fx.in_cubic(Fx.k01(_charge_t, CHARGE_TIME - 0.45, CHARGE_TIME))
	_backdrop.target_tint = _portal_col
	_backdrop.target_amount = 0.3 + 0.45 * k
	_backdrop.bubble_speed = 1.0 + 5.0 * k * k
	_base_trauma = 0.05 + 0.3 * k * k + 0.3 * _portal.implode
	if _tells == 0 and _charge_t >= TELL_1:
		_tells = 1
		if _best != "rare":
			_tell(Kit.EPIC, false)
	if _tells == 1 and _charge_t >= TELL_2:
		_tells = 2
		if _best == "legendary":
			_tell(Kit.LEGENDARY, true)
	if _charge_t >= CHARGE_TIME:
		_open_portal()


## The portal color at time t of the charge: the rarity tell.
func _tell_color(t: float) -> Color:
	if _best == "legendary" and t >= TELL_2:
		return Kit.LEGENDARY
	if _best != "rare" and t >= TELL_1:
		return Kit.EPIC
	if _best == "rare":
		return Kit.ACCENT.lerp(Kit.RARE, Fx.k01(t, 1.0, 2.2))
	return Kit.ACCENT


func _tell(col: Color, big: bool) -> void:
	UI.sfx("tell_big" if big else "tell")
	UI.haptic(40 if big else 25)
	_fx_flash(col.lerp(Color.WHITE, 0.4), 0.5 if big else 0.3)
	_kick = maxf(_kick, 0.5 if big else 0.32)
	_punch = maxf(_punch, 0.5 if big else 0.3)
	_spawn_burst(_portal.center, col, 1.0 if big else 0.6)


## The burst at the end of the charge; the first hero is built under the flash.
func _open_portal() -> void:
	phase = "reveal"
	_gap_left = BURST_GAP
	_base_trauma = 0.0
	_kick = 0.9
	_punch = 1.0
	_portal_col = _tell_color(CHARGE_TIME)
	_fx_flash(_portal_col.lerp(Color.WHITE, 0.65), 1.0)
	var at := _portal.center if _portal else _focus()
	_spawn_burst(at, _portal_col, 1.4 + 0.3 * float(RARITY_ORDER.get(_best, 0)))
	UI.sfx("burst")
	UI.haptic(50)
	if _portal:
		var p := _portal
		p.pivot_offset = p.center
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "scale", Vector2(1.9, 1.9), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, 0.28)
		tw.chain().tween_callback(p.queue_free)
	_portal = null
	_backdrop.bubble_speed = 1.0
	_pips.visible = results.size() > 1
	_prepare(0)


## Between the portal burst and the first hero: count down the gap. Then pulse the "tap to
## continue" hint while the current hero has landed.
func _step_reveal(delta: float) -> void:
	if _reveal == null:
		if _gap_left >= 0.0:
			_gap_left -= delta
			if _gap_left < 0.0:
				_show_card(0)
		return
	var target := 0.0
	if _reveal.settled:
		target = 0.6 + 0.4 * sin(_time * 4.0)
	_hint.modulate.a = target if target > 0.0 else maxf(0.0, _hint.modulate.a - delta * 6.0)


## Builds hero i's reveal (hidden, paused) so it is ready when its turn comes.
func _prepare(i: int) -> void:
	if i < 0 or i >= results.size() or (_next != null and _next_i == i):
		return
	if _next and is_instance_valid(_next):
		_next.queue_free()
	var res: Dictionary = results[i]
	var id := str(res.get("hero_id", ""))
	var r := Reveal.new()
	_cam.add_child(r)
	r.visible = false
	r.process_mode = PROCESS_MODE_DISABLED
	r.setup(res, _stars(id, str(res.get("rarity", "rare"))), Game.equipped_skin(id), UI.safe_top(), UI.safe_bottom())
	r.fx.connect(_on_reveal_fx)
	r.landed.connect(_on_landed)
	_next = r
	_next_i = i


func _show_card(i: int) -> void:
	index = i
	_gap_left = -1.0
	_prepare(i)
	var r := _next
	_next = null
	_next_i = -1
	r.visible = true
	r.process_mode = PROCESS_MODE_INHERIT
	_cam.move_child(r, -1)
	r.start()
	_reveal = r
	showcase = r if r.rarity == "legendary" else null
	_pips.current = i
	_hint.text = "TAP TO CONTINUE" if i < results.size() - 1 else ("TAP FOR RESULTS" if results.size() > 1 else "TAP TO CONTINUE")


func _on_landed() -> void:
	_prepare(index + 1)


func _advance() -> void:
	if _reveal:
		_pips.colors[index] = Kit.rarity_color(_reveal.rarity)
		_reveal.leave()
		_reveal = null
	showcase = null
	_hint.modulate.a = 0.0
	if index + 1 < results.size():
		_show_card(index + 1)
	else:
		_show_summary(false)


# ------------------------------------------------------------------ input

## Overlay taps (the screen forwards real and simulated releases here).
func handle_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	tap()


func _gui_input(ev: InputEvent) -> void:
	handle_input(ev)


func tap() -> void:
	match phase:
		"charge":
			_tells = 2
			_open_portal()
		"reveal":
			if _reveal == null:
				if _gap_left >= 0.0:
					_show_card(0)
			elif _reveal.tap():
				_advance()


## Skip: straight to the results.
func skip_all() -> void:
	if phase != "charge" and phase != "reveal":
		return
	if _portal and is_instance_valid(_portal):
		_portal.queue_free()
	_portal = null
	if _reveal and is_instance_valid(_reveal):
		_reveal.leave()
	_reveal = null
	_show_summary(true)


## Fades out and frees itself (Done).
func close() -> void:
	phase = ""
	mouse_filter = MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


# ------------------------------------------------------------------ screen effects

func _on_reveal_fx(kind: String, color: Color, amount: float) -> void:
	match kind:
		"flash":
			_fx_flash(color, amount)
		"shake":
			_kick = maxf(_kick, amount)
			_punch = maxf(_punch, amount * 0.6)
		"tint":
			_backdrop.target_tint = color
			_backdrop.target_amount = amount
		"darken":
			_backdrop.target_darken = amount


func _fx_flash(col: Color, alpha: float) -> void:
	_flash_col = col
	_flash_a = maxf(_flash_a, alpha)


func _step_fx(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 1.7)
	var tr := clampf(_base_trauma + _kick, 0.0, 1.0)
	var amp := tr * tr * 30.0
	_cam.position = Vector2(Fx.wave(_time, 0.0), Fx.wave(_time, 4.1)) * amp
	_punch = maxf(0.0, _punch - delta * 2.4)
	var z := 1.0 + 0.06 * _punch * _punch
	_cam.scale = Vector2(z, z)
	_flash_a = maxf(0.0, _flash_a - delta * 2.0)
	_flash.visible = _flash_a > 0.002
	_flash.color = Color(_flash_col, _flash_a * _flash_a * (3.0 - 2.0 * _flash_a))


func _spawn_burst(at: Vector2, col: Color, strength: float, parent: Control = null) -> void:
	var b := Burst.new()
	b.color = col
	b.strength = strength
	b.position = at
	(parent if parent else _cam).add_child(b)


func _stars(id: String, rarity: String) -> int:
	var h: Dictionary = Game.hero(id)
	return int(h.get("stars", Kit.RARITY_STARS.get(rarity, 1)))


# ------------------------------------------------------------------ results

func _show_summary(skipped: bool) -> void:
	phase = "results"
	showcase = null
	if _next and is_instance_valid(_next):
		_next.queue_free()
	_next = null
	_reveal = null
	_pips.visible = false
	_skip.visible = false
	_hint.visible = false
	_base_trauma = 0.0
	_backdrop.target_tint = Kit.ACCENT
	_backdrop.target_amount = 0.32
	_backdrop.target_darken = 0.0
	_backdrop.focus = Vector2(size.x * 0.5, size.y * 0.4)
	if skipped and _best == "legendary":
		UI.sfx("legendary")
		UI.haptic(60)
	else:
		UI.sfx("reward")
	_build_grid()
	_build_results_box()


func _build_grid() -> void:
	var st := UI.safe_top()
	_grid_box = Control.new()
	_grid_box.name = "Grid"
	_grid_box.mouse_filter = MOUSE_FILTER_IGNORE
	_grid_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_grid_box.offset_top = st
	_grid_box.offset_bottom = -UI.safe_bottom()
	_summary.add_child(_grid_box)
	var area := size - Vector2(0, st + UI.safe_bottom())
	var single := results.size() == 1
	var cols := 1 if single else 5
	var cw := 250.0 if single else floorf(minf(128.0, (area.x - 40.0 - 4 * 10.0) / 5.0))
	var ch := roundf(cw * CARD_RATIO)
	var gap := Vector2(10, 52)
	var rows := ceili(float(results.size()) / cols)
	var total_w := cols * cw + (cols - 1) * gap.x
	var total_h := rows * ch + (rows - 1) * gap.y
	var origin := Vector2((area.x - total_w) * 0.5, area.y * 0.42 - total_h * 0.5)
	cards.clear()
	for i in results.size():
		var cxy := Vector2(i % cols, i / cols)
		var holder := Control.new()
		holder.name = "Card%d" % i
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.position = origin + cxy * (Vector2(cw, ch) + gap)
		holder.size = Vector2(cw, ch)
		_grid_box.add_child(holder)
		cards.append(holder)
		_summary_card(i, holder, cw, ch, 0.08 + i * 0.07)


## One result card: glow (Epic) or glow + rays (Legendary) behind, the portrait card, and
## NEW HERO / +N SHARDS under it; a single pull also shows the rarity on top and the title,
## faction and role under it. It flips in after `delay` seconds.
func _summary_card(i: int, holder: Control, cw: float, ch: float, delay: float) -> void:
	var res: Dictionary = results[i]
	var id := str(res.get("hero_id", ""))
	var rarity := str(res.get("rarity", "rare"))
	var rc := Kit.rarity_color(rarity)
	var mid := Vector2(cw, ch) * 0.5
	var back_fx: Array[Control] = []
	if rarity != "rare":
		var gl := Kit.glow(rc, cw * (2.6 if rarity == "legendary" else 2.0))
		gl.size = gl.custom_minimum_size
		gl.position = mid - gl.size * 0.5
		gl.modulate.a = 0.9 if rarity == "legendary" else 0.7
		holder.add_child(gl)
		back_fx.append(gl)
		if rarity == "legendary":
			var rays := Kit.rays(rc, cw * 3.2, 14)
			rays.position = mid - rays.size * 0.5
			rays.modulate.a = 0.55
			holder.add_child(rays)
			holder.move_child(rays, 0)
			back_fx.append(rays)
	var is_new := bool(res.get("is_new", false))
	var face := Kit.portrait_card(id, {"size": cw, "owned": true, "level": int(Game.hero(id).get("level", 1)), "new": is_new})
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.focus_mode = FOCUS_NONE
	holder.add_child(face)
	var extras: Array[Control] = []
	var note := ""
	if not is_new:
		note = "+%d SHARDS" % int(res.get("shards", 0))
		if int(res.get("dust", 0)) > 0:
			note = "+%d DUST" % int(res.get("dust", 0)) if int(res.get("shards", 0)) == int(res.get("dust", 0)) else note + "  +%d DUST" % int(res.get("dust", 0))
	elif cw < 200.0:
		note = "NEW HERO"
	if note != "":
		var nl := Kit.label(note, 18 if cw < 200 else 24, Kit.ORANGE_HI if is_new else Kit.ACCENT_HI, "cond_bold", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(-20, ch + 6)
		nl.size = Vector2(cw + 40, 26)
		holder.add_child(nl)
		extras.append(nl)
	if cw >= 200.0:
		var badge := Kit.rarity_mark(rarity, 30)
		holder.add_child(badge)
		badge.position = Vector2(cw * 0.5 - badge.get_combined_minimum_size().x * 0.5, -54)
		extras.append(badge)
		var d := Game.hero_def(id)
		var info := Kit.vbox(8)
		info.mouse_filter = MOUSE_FILTER_IGNORE
		info.position = Vector2(cw * 0.5 - 300.0, ch + (40.0 if note != "" else 14.0))
		info.size = Vector2(600, 100)
		var tl := Kit.label(str(d.get("title", "")).to_upper(), 24, Kit.INK, "cond_bold", 4)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(tl)
		var br := Kit.hbox(12)
		br.alignment = BoxContainer.ALIGNMENT_CENTER
		br.mouse_filter = MOUSE_FILTER_IGNORE
		br.add_child(Kit.faction_badge(str(d.get("faction", "")), 34))
		var rb := Kit.role_badge(str(d.get("role", "")), 30)
		rb.size_flags_vertical = SIZE_SHRINK_CENTER
		br.add_child(rb)
		info.add_child(br)
		holder.add_child(info)
		extras.append(info)
	# Flip in: squeezed from the side with a little overshoot; glows and text fade up after.
	face.pivot_offset = Vector2(cw, ch) * 0.5
	face.scale = Vector2(0.05, 1.08)
	face.modulate.a = 0.0
	var tw := face.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(face, "modulate:a", 1.0, 0.05)
	tw.tween_property(face, "scale", Vector2(1.08, 1.08), 0.13).set_trans(Tween.TRANS_SINE)
	tw.tween_property(face, "scale", Vector2.ONE, 0.13)
	back_fx.append_array(extras)
	for c: Control in back_fx:
		var target: float = c.modulate.a
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", target, 0.25).set_delay(delay + 0.12)
	if rarity != "rare":
		tw.tween_callback(_card_burst.bind(holder, mid, rc, rarity == "legendary"))


func _card_burst(holder: Control, mid: Vector2, rc: Color, big: bool) -> void:
	if not is_instance_valid(holder):
		return
	_spawn_burst(holder.global_position - global_position + mid, rc, 0.9 if big else 0.5, _summary)
	if big:
		UI.haptic(25)


func _build_results_box() -> void:
	var st := UI.safe_top()
	var sb := UI.safe_bottom()
	var title := "SUMMON RESULTS"
	if results.size() == 1:
		title = "NEW HERO" if bool((results[0] as Dictionary).get("is_new", false)) else "SUMMON RESULT"
	var top := Kit.ribbon(title, 520.0, Kit.ACCENT, Color.WHITE, 40)
	top.position = Vector2(size.x * 0.5 - 260.0, st + 24.0)
	top.size = Vector2(520, 84)
	_summary.add_child(top)
	Kit.pop_in(top, 0.0, 0.3)
	var summary := Kit.vbox(6)
	summary.mouse_filter = MOUSE_FILTER_IGNORE
	_summary.add_child(summary)

	_results_box = Kit.vbox(12)
	_results_box.anchor_left = 0.0
	_results_box.anchor_right = 1.0
	_results_box.anchor_top = 1.0
	_results_box.anchor_bottom = 1.0
	_results_box.offset_left = 20
	_results_box.offset_right = -20
	_results_box.offset_bottom = -sb - 20.0
	_results_box.offset_top = -sb - 20.0 - 250.0
	_results_box.alignment = BoxContainer.ALIGNMENT_END
	_summary.add_child(_results_box)
	var news := 0
	var shards := 0
	for x: Variant in results:
		var d := x as Dictionary
		if bool(d.get("is_new", false)):
			news += 1
		shards += int(d.get("shards", 0))
	var parts: Array[String] = []
	if news > 0:
		parts.append("%d NEW HERO%s" % [news, "" if news == 1 else "ES"])
	if shards > 0:
		parts.append("+%d SHARDS" % shards)
	if results.size() > 1 and not parts.is_empty():
		var srow := Kit.hbox(10)
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		srow.mouse_filter = MOUSE_FILTER_IGNORE
		srow.add_child(Kit.deco("techline", Vector2(70, 8), Color(1, 1, 1, 0.4)))
		srow.add_child(Kit.label("  ·  ".join(parts), 24, Color.WHITE, "cond_bold", 4))
		var tl2 := Kit.deco("techline", Vector2(70, 8), Color(1, 1, 1, 0.4))
		tl2.scale.x = -1
		tl2.pivot_offset = Vector2(35, 4)
		srow.add_child(tl2)
		summary.add_child(srow)
	var pl := Kit.label("LEGENDARY GUARANTEED WITHIN %d PULLS" % maxi(1, pity_left), 18, Kit.ACCENT_HI, "cond_bold")
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_child(pl)
	var row := Kit.hbox(12)
	var again_n := 10 if results.size() >= 10 else 1
	var p: Dictionary = price_of.call(again_n) if price_of.is_valid() else {"currency": "gems", "amount": 0, "ok": false}
	var again_b := Kit.cost_button("Summon x%d Again" % again_n, str(p.currency), int(p.amount), func() -> void: again.emit(again_n), "secondary", bool(p.ok))
	again_b.name = "Again"
	again_b.disabled = not bool(p.ok)
	again_b.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(again_b)
	var done_b := Kit.primary_button("Done", func() -> void: done.emit(), "check")
	done_b.name = "Done"
	done_b.custom_minimum_size.y = 108
	done_b.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(done_b)
	_results_box.add_child(row)
	if not bool(p.ok):
		var why := Kit.label("Not enough gems or scrolls for another x%d." % again_n, 20, Color("ff6a50"), "bold")
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_results_box.add_child(why)
	var fade_delay := 0.15 + results.size() * 0.05
	_results_box.modulate.a = 0.0
	_results_box.create_tween().tween_property(_results_box, "modulate:a", 1.0, 0.25).set_delay(fade_delay)
	summary.modulate.a = 0.0
	summary.create_tween().tween_property(summary, "modulate:a", 1.0, 0.25).set_delay(fade_delay)
	_stack_results(top, summary)


## Ribbon, cards and the shard / pity summary as one block, centred in the space above the
## buttons.
func _stack_results(ribbon: Control, summary: Control) -> void:
	if cards.is_empty() or _grid_box == null:
		return
	var st := UI.safe_top()
	var g_top := INF
	var g_bot := -INF
	for h in cards:
		g_top = minf(g_top, h.position.y)
		g_bot = maxf(g_bot, h.position.y + h.size.y)
	var single := cards.size() == 1
	var above := 64.0 if single else 0.0
	var below := 160.0 if single else 40.0
	var sum_h := summary.get_combined_minimum_size().y
	var block := 84.0 + 22.0 + above + (g_bot - g_top) + below + sum_h
	var region_top := st + 16.0
	var region_bot := size.y + _results_box.offset_bottom - _results_box.get_combined_minimum_size().y - 20.0
	var want := region_top + maxf(0.0, (region_bot - region_top - block) * 0.5)
	var dy := (want + 84.0 + 22.0 + above) - (st + g_top)
	_grid_box.position.y += dy
	ribbon.position.y = want
	summary.position = Vector2(0, want + block - sum_h)
	summary.size = Vector2(size.x, sum_h)


# ------------------------------------------------------------------ progress pips

## A row of glossy bubbles, one per hero: hollow until seen, then filled in its rarity color;
## the current one wears a pulsing ring.
class Pips extends Control:
	var count := 10
	var current := 0
	var colors: Array[Color] = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		colors.resize(count)
		colors.fill(Color(0, 0, 0, 0))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var gap := minf(34.0, (size.x - 360.0) / maxf(1.0, float(count - 1)))
		var r := 9.0
		var y := size.y * 0.5
		var x0 := size.x * 0.5 - (count - 1) * gap * 0.5
		draw_line(Vector2(x0, y), Vector2(x0 + (count - 1) * gap, y), Color(1, 1, 1, 0.16), 2.0, true)
		for i in count:
			var c := Vector2(x0 + i * gap, y)
			var col: Color = colors[i] if i < colors.size() else Color(0, 0, 0, 0)
			if i == current:
				var pr := r * (1.55 + 0.12 * sin(_t * 5.0))
				draw_circle(c, pr + 3.0, Color(1, 1, 1, 0.12), true, -1.0, true)
				draw_arc(c, pr, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 2.0, true)
				draw_circle(c, r * 0.9, Color(1, 1, 1, 0.9), true, -1.0, true)
			elif col.a > 0.0:
				draw_circle(c, r, col, true, -1.0, true)
				draw_circle(c + Vector2(-0.3, -0.35) * r, r * 0.35, Color(1, 1, 1, 0.6), true, -1.0, true)
				draw_arc(c, r, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.4, true)
			else:
				draw_circle(c, r, Color(0.02, 0.05, 0.12, 0.55), true, -1.0, true)
				draw_arc(c, r, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.6, true)
