extends Control
## The full-screen summon sequence (owner, 2026-10-19: "a really cool animation ... show a
## splash of each hero, so 10 cards that the user has to actually tap through, and then a
## big reveal if the user gets a rare card"), in the poster look of style v4 (a run of posters
## coming off the press; docs/dev/ui-style-v4.md). The summon screen creates it with Game.summon's
## results; it plays three phases:
##
##   charge   (2.7 s) The press run (summon_portal.gd): a halftone rosette grows on a sheet, its
##            screen turning faster, a registration target and a tick ring spinning up, the page
##            starting to shake. The ink is the rarity tell: black for Rares only, signal red at
##            1.05 s if an Epic is inside, then at 1.8 s the sheet floods signal and prints in
##            black, shaking out of register, for a Legendary. Then the rosette implodes and the
##            press bursts (paper-white flash, an ink burst, a grain burst).
##   reveal   One poster per hero (summon_reveal.gd), the player taps through: a tap
##            fast-forwards the current hero, the next tap brings the next one. A row of printed
##            squares at the top counts the sheets and marks the rarities seen so far.
##   results  The contact sheet: every hero as a small poster on one sheet (5 x 2, or one big
##            poster) printed with her print's flaw, her serial, a MISPRINT / HOLO tag, NEW / shards,
##            the totals as a bracketed table (with the misprints), the pity, "Again" (the
##            screen's summon ticket, make_ticket) and "Done". The screen shows the top bar and
##            the nav again for the results (results_shown); the sheet fits between them.
##
## "Skip" (top-right) jumps to the results from anywhere. A tap during the charge jumps to the
## burst. Signals: done (Done pressed), again(count) (Summon again pressed), results_shown (just
## before the contact sheet is built).
## Phase names ("charge", "reveal", "results") are what the e2e scripts wait for.

signal done
signal again(count: int)
signal results_shown

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const Backdrop := preload("res://src/ui/summon/summon_backdrop.gd")
const Portal := preload("res://src/ui/summon/summon_portal.gd")
const Burst := preload("res://src/ui/summon/summon_burst.gd")
const Reveal := preload("res://src/ui/summon/summon_reveal.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")

const CHARGE_TIME := 2.7
const TELL_1 := 1.05
const TELL_2 := 1.8
const BURST_GAP := 0.42
const RARITY_ORDER := {"rare": 0, "epic": 1, "legendary": 2}
const CARD_RATIO := 1.72
const GRAIN := 0.06

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
## The results table's last row [key, value] (the banner's pity or its pulls left); empty = the
## Legendary guarantee from pity_left.
var pity_row: Array = []
## (count, on_pressed) -> Button: the screen's summon ticket for "Again" (else an OG pass).
var make_ticket: Callable
## A small label on a featured result's print ("RATE UP"); "" = none.
var featured_note := "RATE UP"

var _best := "rare"
var _cam: Control
var _backdrop: Backdrop
var _portal: Portal
var _flash: ColorRect
var _grain: ColorRect
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
var _grain_k := 0.0
var _portal_col := PK.INK
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
	_backdrop.inset_top = UI.safe_top()
	_backdrop.inset_bottom = UI.safe_bottom()
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
	# Additive: the paper overexposes toward white (and blooms) instead of a flat veil.
	_flash.material = Fx.additive()
	add_child(_flash)
	# Film grain over the whole run; it bursts with every reveal.
	_grain = SignalKit.grain(GRAIN, false)
	_grain.name = "Grain"
	add_child(_grain)
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
	_pips.offset_left = 20.0
	_pips.offset_right = -190.0
	_pips.offset_top = st + 22.0
	_pips.offset_bottom = st + 74.0
	_pips.visible = false
	_ui.add_child(_pips)
	_skip = PK.print_button("Skip  >>", skip_all, {"size": Vector2(160, Kit.BUTTON_H), "align": "right", "text_size": 17})
	_skip.name = "Skip"
	_skip.mouse_filter = MOUSE_FILTER_STOP
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -180.0
	_skip.offset_right = -20.0
	_skip.offset_top = st + 4.0
	_skip.offset_bottom = st + 4.0 + Kit.BUTTON_H
	_ui.add_child(_skip)
	_hint = Kit.label("TAP TO CONTINUE  ———  >>>", 15, PK.INK, "mono_bold")
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -sb - 72.0
	_hint.offset_bottom = -sb - 40.0
	_hint.modulate.a = 0.0
	_ui.add_child(_hint)


func _on_resized() -> void:
	if _cam:
		_cam.pivot_offset = size * 0.5


## The press's centre (a little above the middle of the safe area).
func _focus() -> Vector2:
	var st := UI.safe_top()
	var h := size.y if size.y > 0.0 else get_viewport_rect().size.y
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	return Vector2(w * 0.5, st + (h - st - UI.safe_bottom()) * 0.46)


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
	_portal.radius = w * 0.38
	_portal.count = results.size()
	_cam.add_child(_portal)
	_portal_col = PK.INK
	_backdrop.focus = _portal.center
	_backdrop.target_tint = PK.INK
	_backdrop.target_amount = 0.0
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
		_pips.colors[k] = _pip_color(str((results[k] as Dictionary).get("rarity", "rare")))
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
	_portal.reveal = Fx.out_cubic(Fx.k01(_charge_t, 0.0, 0.3))
	_portal.charge = k
	var target := _tell_color(_charge_t)
	_portal_col = _portal_col.lerp(target, 1.0 - exp(-delta * 12.0))
	_portal.color = _portal_col
	_portal.crackle = Fx.out_cubic(Fx.k01(_charge_t, TELL_2, TELL_2 + 0.3)) if _best == "legendary" else 0.0
	_portal.implode = Fx.in_cubic(Fx.k01(_charge_t, CHARGE_TIME - 0.45, CHARGE_TIME))
	_backdrop.target_tint = PK.SIGNAL if _best != "rare" and _charge_t >= TELL_1 else PK.INK
	_backdrop.target_amount = 0.2 + 0.4 * k
	_backdrop.bubble_speed = 1.0 + 5.0 * k * k
	_base_trauma = 0.05 + 0.3 * k * k + 0.3 * _portal.implode
	_grain_k = maxf(_grain_k, 0.04 * k)
	if _tells == 0 and _charge_t >= TELL_1:
		_tells = 1
		if _best != "rare":
			_tell(PK.SIGNAL, false)
	if _tells == 1 and _charge_t >= TELL_2:
		_tells = 2
		if _best == "legendary":
			_tell(PK.SIGNAL, true)
	if _charge_t >= CHARGE_TIME:
		_open_portal()


## The press ink at time t of the charge: the rarity tell (a Legendary's flood prints in black).
func _tell_color(t: float) -> Color:
	if _best == "legendary" and t >= TELL_2:
		return PK.INK
	if _best != "rare" and t >= TELL_1:
		return PK.SIGNAL
	return PK.INK


func _tell(col: Color, big: bool) -> void:
	UI.sfx("tell_big" if big else "tell")
	UI.haptic(40 if big else 25)
	_fx_flash(col.lerp(Color.WHITE, 0.5), 0.45 if big else 0.25)
	_kick = maxf(_kick, 0.5 if big else 0.32)
	_punch = maxf(_punch, 0.5 if big else 0.3)
	_grain_k = maxf(_grain_k, 0.2 if big else 0.12)
	_spawn_burst(_portal.center, col if not big else PK.INK, 1.0 if big else 0.6)


## The burst at the end of the charge; the first hero is built under the flash.
func _open_portal() -> void:
	phase = "reveal"
	_gap_left = BURST_GAP
	_base_trauma = 0.0
	_kick = 0.9
	_punch = 1.0
	_portal_col = _tell_color(CHARGE_TIME)
	_fx_flash(Color(1, 0.98, 0.95), 1.0)
	_grain_k = 0.3
	var at := _portal.center if _portal else _focus()
	_spawn_burst(at, PK.SIGNAL if _best != "rare" else PK.INK, 1.4 + 0.3 * float(RARITY_ORDER.get(_best, 0)))
	UI.sfx("burst")
	UI.haptic(50)
	if _portal:
		var p := _portal
		p.pivot_offset = p.center
		var tw := p.create_tween().set_parallel(true)
		tw.tween_property(p, "scale", Vector2(1.6, 1.6), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 0.0, 0.28)
		tw.chain().tween_callback(p.queue_free)
	_portal = null
	_backdrop.bubble_speed = 1.0
	_pips.visible = results.size() > 1
	_prepare(0)


## Between the press burst and the first hero: count down the gap. Then pulse the "tap to
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
	r.setup(res, _stars(id, str(res.get("rarity", "rare"))), Game.equipped_skin(id), UI.safe_top(), UI.safe_bottom(), i + 1, results.size())
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
	_hint.text = "TAP TO CONTINUE  ———  >>>" if i < results.size() - 1 else ("TAP FOR THE CONTACT SHEET  >>>" if results.size() > 1 else "TAP TO CONTINUE  ———  >>>")


func _on_landed() -> void:
	_prepare(index + 1)


func _advance() -> void:
	if _reveal:
		_pips.colors[index] = _pip_color(_reveal.rarity)
		_reveal.leave()
		_reveal = null
	showcase = null
	_hint.modulate.a = 0.0
	if index + 1 < results.size():
		_show_card(index + 1)
	else:
		_show_summary(false)


## Printed squares: ink for a Rare, signal for an Epic or a Legendary (a Legendary also gets a ring).
static func _pip_color(rarity: String) -> Color:
	match rarity:
		"legendary":
			return Color(PK.SIGNAL, 0.999)
		"epic":
			return PK.SIGNAL
	return PK.INK


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
		"grain":
			_grain_k = maxf(_grain_k, amount)


func _fx_flash(col: Color, alpha: float) -> void:
	_flash_col = col
	_flash_a = maxf(_flash_a, alpha)


func _step_fx(delta: float) -> void:
	_kick = maxf(0.0, _kick - delta * 1.7)
	var tr := clampf(_base_trauma + _kick, 0.0, 1.0)
	var amp := tr * tr * 30.0
	_cam.position = Vector2(Fx.wave(_time, 0.0), Fx.wave(_time, 4.1)) * amp
	_punch = maxf(0.0, _punch - delta * 2.4)
	var z := 1.0 + 0.05 * _punch * _punch
	_cam.scale = Vector2(z, z)
	_flash_a = maxf(0.0, _flash_a - delta * 2.0)
	_flash.visible = _flash_a > 0.002
	_flash.color = Color(_flash_col, _flash_a * _flash_a * (3.0 - 2.0 * _flash_a))
	_grain_k = maxf(0.0, _grain_k - delta * 0.6)
	(_grain.material as ShaderMaterial).set_shader_parameter("amount", GRAIN + _grain_k)


func _spawn_burst(at: Vector2, col: Color, strength: float, parent: Control = null) -> void:
	var b := Burst.new()
	b.color = col
	b.strength = strength
	b.position = at
	(parent if parent else _cam).add_child(b)


func _stars(id: String, rarity: String) -> int:
	var h: Dictionary = Game.hero(id)
	return int(h.get("stars", Kit.RARITY_STARS.get(rarity, 1)))


# ------------------------------------------------------------------ results: the contact sheet

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
	_backdrop.target_tint = PK.INK
	_backdrop.target_amount = 0.0
	_backdrop.target_darken = 0.0
	_grain_k = maxf(_grain_k, 0.12)
	# The chrome comes back for the results (the screen listens); the sheet fits under it.
	results_shown.emit()
	if skipped and _best == "legendary":
		UI.sfx("legendary")
		UI.haptic(60)
	else:
		UI.sfx("reward")
	_build_sheet()


func _build_sheet() -> void:
	var ct := UI.content_top()
	var cb := UI.content_bottom()
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	var h := size.y if size.y > 0.0 else get_viewport_rect().size.y
	var single := results.size() == 1
	var news := 0
	var shards := 0
	for x: Variant in results:
		var d := x as Dictionary
		if bool(d.get("is_new", false)):
			news += 1
		shards += int(d.get("shards", 0))
	# The sheet between the top bar and the nav, leaving the bottom for the ticket and Done.
	var sr := Rect2(18, ct + 16, w - 36, maxf(420.0, h - cb - 196 - (ct + 16)))
	var sheet := PK.poster(_summary, sr)
	sheet.name = "Sheet"
	var pw := sr.size.x
	var ph := sr.size.y
	PK.at(sheet, PK.t("CONTACT SHEET  ·  PRESS RUN Nº 0047  ·  %d PRINT%s  ·  19.10.26" % [results.size(), "" if single else "S"], 11, PK.INK, "mono_bold"), Vector2(20, 16))
	var word := ("NEW HERO" if news > 0 else "RESULT") if single else "RESULTS"
	var tf := Kit.font("compressed")
	var tsz := clampi(int(ph * 0.15), 80, 150)
	while tsz > 70 and tf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x > pw - 190:
		tsz -= 4
	var g := PK.giant(sheet, word, tsz, [[0.0, pw, PK.INK]], Vector2(14, 22), Vector2(pw + 200, tsz * 1.2), 0.0)
	for l in g:
		l.modulate.a = 0.0
		l.create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
	var head_b := 36.0 + tsz * 0.86
	PK.rule(sheet, Rect2(20, head_b, pw - 40, 1), Color(PK.INK, 0.55))
	PK.at(sheet, PK.t("%d NEW  ·  +%d SHARDS  ·  BEST: %s" % [news, shards, str(Kit.RARITY_NAMES.get(_best, _best)).to_upper()], 11,
		PK.INK, "mono"), Vector2(20, head_b + 8))
	if news > 0:
		var stp := PK.stamp_disc(sheet, Vector2(pw - 136, 18), 116, "NEW · HEROES · NEW · ", "%02d" % news, 0.12)
		Kit.pop_in(stp, 0.25)
	# The totals table (built first: the prints fill the space above it).
	var rows_t: Array = []
	if single:
		var d0 := Game.hero_def(str((results[0] as Dictionary).get("hero_id", "")))
		rows_t.append([str(d0.get("title", "")).to_upper(), "%s · %s" % [str(Kit.FACTION_NAMES.get(str(d0.get("faction", "")), "")).to_upper(),
			str(Kit.ROLE_NAMES.get(str(d0.get("role", "")), "")).to_upper()]])
	if news > 0:
		rows_t.append(["NEW HERO%s" % ("" if news == 1 else "ES"), "%d" % news])
	if shards > 0:
		rows_t.append(["SHARDS", "+%d" % shards])
	var flawed := 0
	var foiled := 0
	for x: Variant in results:
		var pdx: Variant = (x as Dictionary).get("print", {})
		if pdx is Dictionary:
			if str((pdx as Dictionary).get("flaw", "")) != "":
				flawed += 1
			if bool((pdx as Dictionary).get("holo", false)):
				foiled += 1
	if flawed + foiled > 0:
		var parts: Array[String] = []
		if flawed > 0:
			parts.append("%d MISPRINT%s" % [flawed, "" if flawed == 1 else "S"])
		if foiled > 0:
			parts.append("%d HOLO" % foiled)
		rows_t.append(["OFF THE PRESS", " · ".join(parts), true])
	if pity_row.size() >= 2:
		rows_t.append([str(pity_row[0]), str(pity_row[1]), true])
	else:
		rows_t.append(["LEGENDARY GUARANTEED WITHIN", "%d PULL%s" % [maxi(1, pity_left), "" if pity_left == 1 else "S"], true])
	var tb := PK.data_table(rows_t, pw - 40, {"size": 14, "row_h": 28.0, "bar": Color(1, 1, 1, 0.7)})
	tb.position = Vector2(20, ph - 16 - tb.size.y)
	# The prints, on strips of film with sprocket holes and frame numbers.
	var area := Rect2(0, head_b + 34, pw, tb.position.y - 18 - (head_b + 34))
	var cols := 1 if single else 5
	var nrows := ceili(float(results.size()) / cols)
	var gap := 12.0
	var strip_h := floorf((area.size.y - (nrows - 1) * 14.0) / nrows)
	var cw := floorf((pw - 40 - (cols - 1) * gap) / cols)
	var ch := minf(strip_h - 56.0, cw * 2.5)
	if single:
		ch = strip_h - 56.0
		cw = roundf(minf(ch / CARD_RATIO, pw * 0.56))
	cards.clear()
	for r in nrows:
		var sy := area.position.y + r * (strip_h + 14.0)
		var film := _Film.new()
		film.position = Vector2(0, sy)
		film.size = Vector2(pw, strip_h)
		film.first = r * cols
		film.cols = cols
		film.frame_w = cw + gap
		film.x0 = (pw - (cols * cw + (cols - 1) * gap)) * 0.5
		sheet.add_child(film)
		for c in cols:
			var i := r * cols + c
			if i >= results.size():
				break
			var holder := Control.new()
			holder.name = "Card%d" % i
			holder.mouse_filter = MOUSE_FILTER_IGNORE
			holder.position = Vector2(film.x0 + c * (cw + gap), sy + (strip_h - ch) * 0.5)
			holder.size = Vector2(cw, ch)
			sheet.add_child(holder)
			cards.append(holder)
			_mini_poster(i, holder, cw, ch, 0.1 + i * 0.07, sr.position)
	# The totals under the prints, then the pass and Done under the sheet.
	sheet.add_child(tb)
	PK.grain(sheet, 0.06)
	_build_buttons(sr)


func _build_buttons(sr: Rect2) -> void:
	var again_n := 10 if results.size() >= 10 else 1
	var p: Dictionary = price_of.call(again_n) if price_of.is_valid() else {"currency": "gems", "amount": 0, "ok": false}
	var cost := "%d SCROLL%s" % [int(p.amount), "" if int(p.amount) == 1 else "S"] if str(p.currency) == "scrolls" else "%s GEMS" % Kit.format_full(int(p.amount))
	var box := Control.new()
	box.name = "Buttons"
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.position = Vector2(0, sr.end.y + 14)
	box.size = Vector2(size.x, 180)
	_summary.add_child(box)
	var again_b: Button
	if make_ticket.is_valid():
		again_b = make_ticket.call(again_n, func() -> void: again.emit(again_n))
		again_b.position = Vector2(14, 6)
	else:
		again_b = PK.pass_button({"width": 420.0, "kicker": "SUMMON // PRESS AGAIN", "title": "AGAIN ×%d" % again_n,
			"sub": "SAME RATES · SAME PITY", "action": "PULL ×%d  >>>" % again_n, "info": cost, "icon": "summon",
			"disabled": not bool(p.ok), "title_size": 26}, func() -> void: again.emit(again_n))
		again_b.position = Vector2(14, 0)
	again_b.name = "Again"
	again_b.rotation = -0.02
	box.add_child(again_b)
	var done_b := PK.plate_button("Done", func() -> void: done.emit(), {"size": Vector2(236, 112), "kicker": "CLOSE THE RUN",
		"icon": "check", "text_size": 30, "screws": true, "cuts": [14, 0, 14, 0]})
	done_b.name = "Done"
	done_b.position = Vector2(size.x - 236 - 18, 26)
	box.add_child(done_b)
	if not bool(p.ok) and not make_ticket.is_valid():
		var why := PK.t("NOT ENOUGH GEMS OR SCROLLS FOR ANOTHER x%d" % again_n, 12, PK.SIGNAL, "mono_bold")
		why.position = Vector2(24, 172)
		box.add_child(why)
	var fade := 0.15 + results.size() * 0.05
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, 0.25).set_delay(fade)
	SignalKit.relight(box)


## One small poster on the contact sheet: her art in full colour over a strip in the rarity's
## ink, her name in compressed type, the sheet number, NEW or her shards. A Legendary is printed on
## signal paper and ringed in grease pencil. It drops onto the sheet after `delay` seconds.
func _mini_poster(i: int, holder: Control, cw: float, ch: float, delay: float, sheet_pos: Vector2) -> void:
	var res: Dictionary = results[i]
	var id := str(res.get("hero_id", ""))
	var rarity := str(res.get("rarity", "rare"))
	var d := Game.hero_def(id)
	var big := cw >= 200.0
	var legend := rarity == "legendary"
	var face := Control.new()
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size = Vector2(cw, ch)
	holder.add_child(face)
	var p := PK.poster(face, Rect2(Vector2.ZERO, Vector2(cw, ch)), PK.SIGNAL if legend else PK.PAPER, 0.3)
	var strip := 16.0 if not big else 34.0
	var sc := PK.BAND if rarity == "rare" else (PK.SIGNAL if rarity == "epic" else PK.INK)
	PK.rule(p, Rect2(0, 0, strip, ch), sc)
	var art_h := ch * 0.68
	var art := TextureRect.new()
	art.mouse_filter = MOUSE_FILTER_IGNORE
	art.texture = Kit.art_crop(id, (cw - strip - 8) / art_h, 1.0, Game.equipped_skin(id))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(strip + 4, 4)
	art.size = Vector2(cw - strip - 8, art_h)
	var pd: Dictionary = res.get("print", {}) if res.get("print") is Dictionary else {}
	if not pd.is_empty() and (str(pd.get("flaw", "")) != "" or bool(pd.get("holo", false))):
		# Printed as it came off the press: the flaw and the foil on her contact print.
		art.stretch_mode = TextureRect.STRETCH_SCALE
		var pm := PrintCard.material_for(pd, PrintCard.region_of(art.texture), maxf(3.0, cw * 0.04))
		pm.set_shader_parameter("paper", PK.SIGNAL if legend else PK.PAPER)
		pm.set_shader_parameter("cell", 4.0 if not big else 6.0)
		art.material = pm
	p.add_child(art)
	PK.hairbox(p, Rect2(art.position, art.size), Color(PK.INK, 0.6))
	var nm := PK.t(str(d.get("name", id)).to_upper(), 64 if big else 30, PK.INK, "compressed")
	Kit.fit_label(nm, cw - strip - 10, 64 if big else 30, 14)
	nm.position = Vector2(strip + 5, art_h + (6 if big else 2))
	p.add_child(nm)
	var info := "Nº %02d · %s" % [i + 1, str(Kit.RARITY_NAMES.get(rarity, rarity)).to_upper()]
	if not pd.is_empty():
		info = ("No. %04d · %s" % [int(pd.get("serial", 0)), str(Kit.RARITY_NAMES.get(rarity, rarity)).to_upper()]) if not big \
			else "%s  ·  %s" % [PrintCard.serial_line(pd).to_upper(), str(Kit.RARITY_NAMES.get(rarity, rarity)).to_upper()]
	var il := PK.t(info, 13 if big else 9, PK.INK if legend or rarity == "rare" else PK.SIGNAL, "mono_bold")
	il.position = Vector2(strip + 6, ch - (58 if big else 34))
	p.add_child(il)
	var is_new := bool(res.get("is_new", false))
	if bool(res.get("featured", false)) and featured_note != "":
		# Printed tag in the corner of a featured hero's print.
		var fn := PK.t(featured_note, 13 if big else 9, PK.PAPER if not legend else PK.SIGNAL, "mono_bold")
		var fbg := ColorRect.new()
		fbg.mouse_filter = MOUSE_FILTER_IGNORE
		fbg.color = PK.INK if legend else PK.SIGNAL
		fbg.position = Vector2(strip + 4, 4)
		fbg.size = fn.get_minimum_size() + Vector2(10, 2)
		p.add_child(fbg)
		fn.position = fbg.position + Vector2(5, 1)
		p.add_child(fn)
	var note := "NEW HERO" if is_new else "+%d SHARDS" % int(res.get("shards", 0))
	if not is_new and int(res.get("dust", 0)) > 0:
		note = "+%d DUST" % int(res.get("dust", 0)) if int(res.get("shards", 0)) == int(res.get("dust", 0)) else note + " +%d DUST" % int(res.get("dust", 0))
	var nl := PK.t(note, 15 if big else 10, PK.PAPER if legend and is_new else (PK.SIGNAL if is_new else PK.INK), "mono_bold")
	nl.position = Vector2(strip + 6, ch - (34 if big else 20))
	p.add_child(nl)
	if not pd.is_empty():
		_print_tags(p, pd, Vector2(strip + 4, 4), Vector2(cw - strip - 8, art_h), big, legend)
	if big:
		var vt := PK.vt(p, "©2026 HH · %s" % str(Kit.FACTION_NAMES.get(str(d.get("faction", "")), "")).to_upper(), 10, PK.PAPER, Vector2(strip - 6, 10))
		vt.modulate.a = 0.9
	if legend:
		var loop := _Loop.new()
		loop.position = Vector2(-10, -10)
		loop.size = Vector2(cw + 20, ch + 20)
		holder.add_child(loop)
	# Drops onto the sheet: from a little bigger and turned, with a print's slight tilt.
	var rot := (float((i * 7919) % 11) - 5.0) * 0.004
	face.pivot_offset = Vector2(cw, ch) * 0.5
	face.rotation = rot + 0.08
	face.scale = Vector2(1.18, 1.18)
	face.modulate.a = 0.0
	var tw := face.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(face, "modulate:a", 1.0, 0.06)
	tw.parallel().tween_property(face, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(face, "rotation", rot, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if rarity != "rare":
		tw.tween_callback(_card_burst.bind(holder, Vector2(cw, ch) * 0.5, PK.SIGNAL if not legend else PK.INK, legend))


## A misprint's or a holo's tag stuck on the corner of its contact print (signal MISPRINT with the
## flaw, an ink HOLO tag with a rainbow edge), and the edition line on a big single print.
func _print_tags(p: Control, pd: Dictionary, art_pos: Vector2, art_size: Vector2, big: bool, legend: bool) -> void:
	var y := art_pos.y + art_size.y - (34.0 if big else 25.0)
	var flaw := str(pd.get("flaw", ""))
	if flaw != "":
		var txt := "MISPRINT" if not big else "MISPRINT · %s" % PrintRules.flaw_name(flaw).to_upper()
		var l := PK.t(txt, 15 if big else 9, PK.PAPER, "mono_bold")
		var bg := ColorRect.new()
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		bg.color = PK.INK if legend else PK.SIGNAL
		bg.size = l.get_minimum_size() + Vector2(8, 2)
		bg.position = Vector2(art_pos.x + 2, y)
		bg.rotation = -0.04
		l.position = Vector2(4, 1)
		bg.add_child(l)
		p.add_child(bg)
		y -= 22.0 if big else 15.0
	if bool(pd.get("holo", false)):
		var l2 := PK.t("HOLO" if not big else "HOLO FOIL", 15 if big else 9, PK.PAPER, "mono_bold")
		var bg2 := ColorRect.new()
		bg2.mouse_filter = MOUSE_FILTER_IGNORE
		bg2.color = PK.INK
		bg2.size = l2.get_minimum_size() + Vector2(8, 2)
		bg2.position = Vector2(art_pos.x + 2, y)
		l2.position = Vector2(4, 1)
		bg2.add_child(l2)
		var rb := _Rainbow.new()
		rb.position = Vector2(0, bg2.size.y)
		rb.size = Vector2(bg2.size.x, 3)
		bg2.add_child(rb)
		p.add_child(bg2)
	if big:
		var el := PK.t(PrintCard.edition_line(pd), 12, PK.INK, "mono")
		el.position = Vector2(art_pos.x + 2, art_pos.y + art_size.y + 92.0)
		p.add_child(el)


func _card_burst(holder: Control, mid: Vector2, rc: Color, big: bool) -> void:
	if not is_instance_valid(holder):
		return
	_spawn_burst(holder.global_position - global_position + mid, rc, 0.9 if big else 0.5, _summary)
	if big:
		UI.haptic(25)


# ------------------------------------------------------------------ progress: printed squares

## A row of printed squares, one per sheet: hollow until seen, then filled (ink for a Rare,
## signal for an Epic, signal with a ring for a Legendary); the current one blinks. "07 / 10" next
## to them.
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
		var ink := Color("101113")
		var s := 14.0
		var gap := 8.0
		var y := size.y * 0.5 - s * 0.5
		var f := Kit.font("mono_bold")
		draw_string(f, Vector2(0, y + 12), "SHEET %02d / %02d" % [current + 1, count], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
		var x0 := 140.0
		for i in count:
			var r := Rect2(x0 + i * (s + gap), y, s, s)
			var col: Color = colors[i] if i < colors.size() else Color(0, 0, 0, 0)
			if i == current:
				var on := fmod(_t, 0.8) < 0.5
				draw_rect(r, Color("ff4b1f") if on else ink, false, 2.0)
				draw_rect(r.grow(-4), Color("ff4b1f") if on else ink)
			elif col.a > 0.0:
				draw_rect(r, Color(col, 1.0))
				if col.a < 1.0:
					draw_rect(r.grow(3), ink, false, 1.0)
			else:
				draw_rect(r, Color(ink, 0.6), false, 1.0)


## A strip of film on the contact sheet: sprocket holes along both edges, frame numbers.
class _Film extends Control:
	var first := 0
	var cols := 5
	var frame_w := 130.0
	var x0 := 20.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var paper := Color("e9e8e2")
		draw_rect(Rect2(Vector2.ZERO, size), Color("141517"))
		var x := 8.0
		while x < size.x - 10.0:
			for y: float in [8.0, size.y - 17.0]:
				draw_rect(Rect2(x, y, 12, 9), Color(paper, 0.85))
			x += 24.0
		var f := Kit.font("mono_bold")
		for c in cols:
			var n := first + c + 1
			draw_string(f, Vector2(x0 + c * frame_w, 32), "%02dA  >" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(paper, 0.7))
		draw_string(f, Vector2(size.x - 120, size.y - 22), "HH 400 · 0047", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ff4b1f", 0.9))


## A thin rainbow strip (the holo tag's foil edge).
class _Rainbow extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := 12
		for k in n:
			draw_rect(Rect2(size.x * k / n, 0, size.x / n + 1.0, size.y), Color.from_hsv(float(k) / n, 0.55, 1.0))


## A grease-pencil loop around a print (a Legendary on the contact sheet).
class _Loop extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for k in 66:
			var a := TAU * k / 60.0 - 0.6
			var wob := 1.0 + 0.03 * sin(a * 3.0 + 1.0) + 0.02 * sin(a * 7.0)
			pts.append(c + Vector2(cos(a) * size.x * 0.52, sin(a) * size.y * 0.51) * wob)
		draw_polyline(pts, Color("ff4b1f"), 3.0, true)
