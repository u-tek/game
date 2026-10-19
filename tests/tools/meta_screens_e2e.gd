extends SceneTree
## End-to-end check of the meta screens through the real main scene (headless):
##   tools/gd --headless --path . -s tests/tools/meta_screens_e2e.gd -- --fresh
## Heroes (filters, sort, open) -> hero detail (level tap / hold / max, star up with the dust
## confirm, gear picker, auto-equip, browse, unowned preview) -> formation (remove, place,
## swap, empty team, auto-fill) -> summon (free pull waits for a tap, x10 on scrolls tapped
## through hero by hero, x10 through Skip, real taps then a real Skip, gem pull through the
## confirm, forced Legendary showcase, leaving mid-sequence) -> quests (claim,
## claim all) -> shop (buy, limits) -> settings (toggles, speed, dev tools, reset save).
## Exit code 1 on any failed check. Watch the output for SCRIPT ERROR lines too.

var _fails: Array[String] = []
var _checks := 0
var _game: Node
var _ui: Node


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		printerr("E2E: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_game = root.get_node("Game")
	_ui = root.get_node("UI")
	await _heroes()
	await _skins()
	await _detail()
	await _real_input()
	await _formation()
	await _summon()
	await _quests()
	await _shop()
	await _settings()
	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E meta screens: %d checks, %d failures" % [_checks, _fails.size()])
	quit(1 if _fails.size() > 0 else 0)


# ------------------------------------------------------------------ helpers

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(what)
		printerr("  FAIL: ", what)


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _go(screen: String, params: Dictionary = {}) -> Control:
	_close_modals()
	_ui.go(screen, params)
	await _frames(4)
	_check(_ui.current_name == screen, "navigate to %s (at %s)" % [screen, _ui.current_name])
	return _ui.current


func _close_modals() -> void:
	var guard := 0
	while _ui.has_modal() and guard < 20:
		_ui.handle_back()
		guard += 1


## Finds a Button in the top modal (or under `from`) whose text or label contains `text`.
func _find_button(from: Node, text: String) -> Button:
	if from is Button:
		var b := from as Button
		if b.text.contains(text) and not b.disabled:
			return b
		for c in b.find_children("*", "Label", true, false):
			if (c as Label).text.contains(text) and not b.disabled:
				return b
	for c in from.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


func _press_in_modal(text: String) -> bool:
	var layer: Control = _ui.root.get("modal_layer")
	if layer == null or layer.get_child_count() == 0:
		return false
	var top := layer.get_child(layer.get_child_count() - 1)
	var b := _find_button(top, text)
	if b == null:
		return false
	b.pressed.emit()
	return true


# ------------------------------------------------------------------ heroes

func _heroes() -> void:
	var s := await _go("heroes")
	for i in 3:
		s.call("_cycle_sort")
		await _frames(1)
	s.set("_faction_idx", 1)
	s.call("_refresh", true)
	s.set("_role_idx", 2)
	s.call("_refresh", true)
	s.set("_faction_idx", 0)
	s.set("_role_idx", 0)
	s.call("_refresh", true)
	await _frames(2)
	var owned: Array = []
	for h: Dictionary in _game.owned_heroes():
		owned.append(str(h.id))
	_check(owned.size() >= 3, "fresh game owns starters")
	var browse: Array[String] = []
	for x: Variant in owned:
		browse.append(str(x))
	s.call("_open", browse[0], browse)
	await _frames(4)
	_check(_ui.current_name == "hero_detail", "tap a card opens hero_detail")
	_check(str(_ui.current_params.get("hero_id", "")) == browse[0], "detail opened for the tapped hero")


# ------------------------------------------------------------------ skins on cards

## The art on a hero's roster card (Heroes screen), or null.
func _card_atlas(s: Node, id: String) -> Texture2D:
	var card := s.find_child("PortraitCard_" + id, true, false)
	var art := card.find_child("Art", true, false) as TextureRect if card else null
	var at := art.texture as AtlasTexture if art else null
	return at.atlas if at else null


## A skin the player equips shows on her Heroes card, the top-bar avatar and the Lobby at once,
## and the nudity setting swaps the art right away (the owner's report, 2026-10-19).
func _skins() -> void:
	var id := "kessa"
	var sid := ""
	for sk: Dictionary in _game.skins_for(id):
		if bool(sk.installed):
			sid = str(sk.id)
			break
	_check(sid != "", "kessa has an installed skin")
	if sid == "":
		return
	_game.dev_add("gems", 10000)
	_check(bool(_game.buy_skin(sid).ok), "buy a skin")
	var s := await _go("heroes")
	_check(_card_atlas(s, id) == HeroArt.texture(id), "the Heroes card shows the base look before")
	_check(bool(_game.equip_skin(id, sid).ok), "equip the skin")
	await _frames(2)
	_check(_card_atlas(s, id) == HeroArt.texture(id, sid) and HeroArt.texture(id, sid) != HeroArt.texture(id),
		"the Heroes card shows the new skin at once")
	var lead := ""
	for f: Variant in _game.formation():
		if str(f) != "" and lead == "":
			lead = str(f)
	var av: TextureRect = _ui.root.get("_avatar_art")
	_check(av != null and av.texture == Kit.art_crop(lead, 1.0, 1.7, _game.equipped_skin(lead)), "the top-bar avatar wears the lead's skin")
	var tame := HeroArt.texture(id, sid)
	_game.set_setting("nudity", true)
	await _frames(2)
	_check(_card_atlas(s, id) == HeroArt.texture(id, sid), "nudity on: the card follows at once")
	if HeroArt.has_adult_art(id, sid):
		_check(HeroArt.texture(id, sid) != tame, "nudity on: the skin's adult art")
	_check(av.texture == Kit.art_crop(lead, 1.0, 1.7, _game.equipped_skin(lead)), "nudity on: the avatar follows")
	_game.set_setting("lobby_hero", id)
	var h := await _go("home")
	_check(str(h.get("_hero_id")) == id and str(h.get("_hero_key")) == HeroArt.art_key(id, sid), "the Lobby hero wears her skin (nude)")
	_game.set_setting("nudity", false)
	await _frames(2)
	_check(str(h.get("_hero_key")) == HeroArt.art_key(id, sid) and HeroArt.texture(id, sid) == tame, "nudity off: the Lobby hero is dressed again")
	_game.equip_skin(id, "")
	_game.set_setting("lobby_hero", "")


# ------------------------------------------------------------------ hero detail

func _detail() -> void:
	var id := "uriela"
	_game.dev_add("gold", 2000000)
	_game.dev_add("hero_exp", 2000000)
	var s := await _go("hero_detail", {"hero_id": id})
	var lv0 := int(_game.hero(id).level)
	s.call("_on_level_tap")
	await _frames(2)
	_check(int(_game.hero(id).level) == lv0 + 1, "Level Up tap gains one level")
	# A hold: repeated quiet level-ups, then release celebrates once.
	s.call("_on_level_down")
	for i in 4:
		s.call("_do_level", 1, true)
		s.set("_hold_gained", int(s.get("_hold_gained")) + 1)
	s.call("_end_hold")
	_check(int(_game.hero(id).level) == lv0 + 5, "hold repeats level-ups")
	s.call("_on_level_max")
	await _frames(2)
	_check(int(_game.hero(id).level) == int(_game.max_level(id)), "Max levels to the cap")
	s.call("_on_level_tap")
	await _frames(2)
	_check(int(_game.hero(id).level) == int(_game.max_level(id)), "level tap at cap does nothing")
	# Star up with dust filling missing shards (goes through the confirm).
	_game.dev_add("dust", 100000)
	var st0 := int(_game.hero(id).stars)
	s.call("_on_star_up")
	await _frames(2)
	_check(_press_in_modal("Star Up"), "star-up confirm shows")
	await _frames(3)
	_check(int(_game.hero(id).stars) == st0 + 1, "Star Up adds a star")
	# Gear: make two items, equip one from the picker, then auto-equip.
	_game.model.create_gear("weapon", 2)
	_game.model.create_gear("armor", 3)
	_game.changed.emit()
	await _frames(2)
	s.call("_open_gear_picker", "weapon")
	await _frames(3)
	_check(_press_in_modal("Equip") or _press_in_modal("Swap"), "gear picker lists an item to equip")
	await _frames(3)
	_check(str(_game.hero(id).gear.get("weapon", "")) != "", "picker equips the weapon")
	s.call("_open_gear_picker", "weapon")
	await _frames(3)
	_check(_press_in_modal("Remove"), "picker can remove worn gear")
	await _frames(3)
	_check(str(_game.hero(id).gear.get("weapon", "")) == "", "Remove unequips")
	s.call("_on_auto_equip")
	await _frames(2)
	_check(str(_game.hero(id).gear.get("armor", "")) != "", "Auto-equip fills armor")
	_close_modals()
	# Browse.
	var before := str(_ui.current_params.get("hero_id", ""))
	s.call("_browse_step", 1)
	await _frames(4)
	_check(_ui.current_name == "hero_detail" and str(_ui.current_params.get("hero_id", "")) != before, "next arrow browses")
	_ui.current.call("_browse_step", -1)
	await _frames(4)
	_check(str(_ui.current_params.get("hero_id", "")) == before, "prev arrow browses back")
	_ui.current.call("_poke_hero")
	# Unowned preview.
	var unowned := ""
	for d: Dictionary in _game.all_hero_defs():
		if not _game.owns(str(d.id)):
			unowned = str(d.id)
			break
	if unowned != "":
		var u := await _go("hero_detail", {"hero_id": unowned})
		_check(u.get("_lvl_btn") == null, "unowned preview has no level panel")
	await _go("hero_detail", {"hero_id": "nobody"})


# ------------------------------------------------------------------ real input

func _press(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


## Real pointer events: a held Level Up repeats (and the release adds nothing extra), a tap on
## a hero card in the scrolling grid opens the hero, and taps skip the summon sequence.
func _real_input() -> void:
	var id := "kessa"
	_game.dev_add("gold", 3000000)
	_game.dev_add("hero_exp", 3000000)
	var s := await _go("hero_detail", {"hero_id": id})
	var sc: ScrollContainer = s.get("_scroll")
	var btn: Button = s.get("_lvl_btn")
	var vh: float = root.get_visible_rect().size.y
	for i in 6:
		await _frames(2)
		var gy := btn.get_global_rect().get_center().y
		if gy > vh * 0.3 and gy < vh * 0.7:
			break
		sc.scroll_vertical += int(gy - vh * 0.5)
	await _frames(3)
	var c := btn.get_global_rect().get_center()
	var lv0 := int(_game.hero(id).level)
	_press(c, true)
	await create_timer(1.6).timeout
	var lv_hold := int(_game.hero(id).level)
	_press(c, false)
	await _frames(3)
	var lv_end := int(_game.hero(id).level)
	_check(lv_hold - lv0 >= 4, "holding Level Up repeats (gained %d)" % (lv_hold - lv0))
	_check(lv_end == lv_hold, "releasing a hold adds no extra level")
	_press(c, true)
	await _frames(2)
	_press(c, false)
	await _frames(3)
	_check(int(_game.hero(id).level) == lv_end + 1, "a real tap levels once")
	# Tap a card in the heroes grid.
	var h := await _go("heroes")
	await _frames(4)
	var cards := h.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return b.get("hero_id") != null and str(b.get("hero_id")) != "")
	_check(not cards.is_empty(), "heroes grid has cards")
	if not cards.is_empty():
		var card: Button = cards[0]
		var want := str(card.get("hero_id"))
		var cc := card.get_global_rect().get_center()
		_press(cc, true)
		await _frames(2)
		_press(cc, false)
		await _frames(4)
		_check(_ui.current_name == "hero_detail" and str(_ui.current_params.get("hero_id", "")) == want, "tapping a hero card opens their page")
	# Real taps on the summon overlay: taps move the reveal along, then the Skip button.
	var su := await _go("summon")
	_game.dev_add("scrolls", 10)
	su.call("_try_summon", 10)
	await _frames(3)
	var mid := root.get_visible_rect().size * 0.5
	for i in 4:
		_press(mid, true)
		await _frames(1)
		_press(mid, false)
		await _frames(3)
	var seq: Node = su.get("_seq")
	_check(str(su.get("_phase")) == "reveal" and seq != null and int(seq.get("index")) >= 0, "real taps open the portal and reveal heroes")
	var skip := _find_button(su, "Skip")
	_check(skip != null and skip.is_visible_in_tree(), "Skip shows during the reveal")
	if skip:
		var skc := skip.get_global_rect().get_center()
		_press(skc, true)
		await _frames(1)
		_press(skc, false)
		await _frames(3)
	_check(str(su.get("_phase")) == "results", "real taps skip to the summon results")
	_check((su.get("_cards") as Array).size() == 10, "Skip shows all 10 results")
	su.call("_finish")
	await _frames(2)


# ------------------------------------------------------------------ formation

func _formation() -> void:
	var s := await _go("formation")
	var f0: Array = _game.formation()
	var first := -1
	for i in 5:
		if str(f0[i]) != "":
			first = i
			break
	s.call("_tap_slot", first)
	await _frames(2)
	_check(str(_game.formation()[first]) == "", "tap a placed hero removes them")
	var removed := str(f0[first])
	s.call("_tap_hero", removed)
	await _frames(2)
	_check(_game.formation().has(removed), "tap a listed hero places them")
	# Select an empty slot, then move a placed hero there.
	var empty: int = _game.formation().find("")
	if empty >= 0:
		s.call("_tap_slot", empty)
		s.call("_tap_hero", removed)
		await _frames(2)
		_check(str(_game.formation()[empty]) == removed, "selected slot receives the hero (move)")
	# Empty the team: nothing saved, warning shown.
	for i in 5:
		if str(s.get("_slots")[i]) != "":
			s.call("_tap_slot", i)
	await _frames(2)
	_check((s.get("_warn") as Label).visible, "empty team shows a warning")
	_check(_game.formation().has(removed) or not _game.formation().all(func(x: Variant) -> bool: return str(x) == ""), "saved team never empty")
	s.call("_on_auto")
	await _frames(2)
	var filled := 0
	for x: Variant in _game.formation():
		if str(x) != "":
			filled += 1
	_check(filled == mini(5, _game.owned_heroes().size()), "Auto-fill fills the team")
	_check(not (s.get("_warn") as Label).visible or filled > 0, "auto-fill clears the empty state")


# ------------------------------------------------------------------ summon

func _summon() -> void:
	var s := await _go("summon")
	# Free daily pull.
	_check(bool(_game.free_pull_available()), "fresh game has the free pull")
	s.call("_do_summon", 1, true)
	await _frames(2)
	_check(str(s.get("_phase")) == "charge", "summon starts with the charge")
	_check(not _ui.chrome_top and not _ui.chrome_nav, "chrome hidden during the summon")
	# Nothing advances without a tap: the hero waits for the player.
	await _wait_real(4.0)
	_check(str(s.get("_phase")) == "reveal", "the single hero waits for a tap (phase %s)" % str(s.get("_phase")))
	await _wait_results(s, "free pull", true)
	s.call("_finish")
	await _frames(2)
	_check(_ui.chrome_top and _ui.chrome_nav, "Done restores the chrome")
	_check(not bool(_game.free_pull_available()), "free pull used")
	# x10 on scrolls, tapped through hero by hero.
	var scrolls0 := int(_game.currency("scrolls"))
	s.call("_try_summon", 10)
	await _frames(2)
	_check(int(_game.currency("scrolls")) == scrolls0 - 10, "x10 pays with scrolls first")
	var seen := await _wait_results(s, "x10 tapped", true)
	_check(seen.size() == 10, "tapping through shows every hero's reveal (saw %d)" % seen.size())
	_check((s.get("_cards") as Array).size() == 10, "x10 shows 10 cards")
	# x10 through the Skip button: straight to the results.
	_game.dev_add("scrolls", 10)
	s.call("_again", 10)
	await _frames(3)
	var skip := _find_button(s, "Skip")
	_check(skip != null, "Skip button during the summon")
	if skip:
		skip.pressed.emit()
	await _frames(2)
	_check(str(s.get("_phase")) == "results", "Skip reaches the results")
	_check((s.get("_cards") as Array).size() == 10, "Skip shows 10 cards")
	# Again: no scrolls left, so gems through the confirm.
	var gems0 := int(_game.currency("gems"))
	s.call("_again", 1)
	await _frames(2)
	_check(_press_in_modal("Summon"), "gem summon asks first")
	await _frames(2)
	_check(int(_game.currency("gems")) == gems0 - int(_game.banner().cost_one), "x1 paid with gems")
	await _wait_results(s, "again x1", true)
	s.call("_finish")
	# Forced Legendary: the big reveal (showcase) plays, taps move it on.
	_game.model.state.summon.pity = int(_game.banner().pity_legendary) - 1
	_game.dev_add("gems", 3000)
	s.call("_do_summon", 1, false)
	var saw_showcase := false
	var t0 := Time.get_ticks_msec()
	var last_tap := t0
	while Time.get_ticks_msec() - t0 < 20000 and str(s.get("_phase")) != "results":
		await process_frame
		var sc: Variant = s.get("_showcase")
		if sc is Control and is_instance_valid(sc):
			saw_showcase = true
		if Time.get_ticks_msec() - last_tap > 300:
			last_tap = Time.get_ticks_msec()
			_overlay_tap(s)
	_check(saw_showcase, "Legendary showcase appears")
	_check(str(s.get("_phase")) == "results", "Legendary sequence reaches the results")
	var res: Array = s.get("_results")
	_check(not res.is_empty() and str((res[0] as Dictionary).rarity) == "legendary", "pity gives a Legendary")
	s.call("_finish")
	# Leaving mid-sequence never strands the chrome.
	_game.dev_add("gems", 3000)
	s.call("_do_summon", 1, false)
	await _frames(5)
	_ui.go("home")
	await _frames(3)
	_check(_ui.chrome_top and _ui.chrome_nav, "leaving mid-summon restores chrome")
	# Unaffordable: no gems or scrolls.
	s = await _go("summon")
	_game.dev_add("gems", -int(_game.currency("gems")))
	_game.dev_add("scrolls", -int(_game.currency("scrolls")))
	await _frames(2)
	s.call("_try_summon", 10)
	await _frames(2)
	_check(str(s.get("_phase")) == "", "can't summon without currency")
	_check((s.get("_reason") as Control).visible, "reason shown when unaffordable")
	s.call("_open_rates")
	await _frames(2)
	_check(_ui.has_modal(), "Rates opens the odds panel")
	_close_modals()


## Waits for the summon results, tapping the overlay every 0.15 s when `tap` is on (each tap
## fast-forwards the current hero or brings the next one). Returns the hero indexes whose
## reveal was seen.
func _wait_results(s: Control, what: String, tap: bool) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var last_tap := t0
	var seen := {}
	while Time.get_ticks_msec() - t0 < 30000 and str(s.get("_phase")) != "results":
		await process_frame
		var seq: Node = s.get("_seq")
		if seq and str(s.get("_phase")) == "reveal" and int(seq.get("index")) >= 0:
			seen[int(seq.get("index"))] = true
		if tap and Time.get_ticks_msec() - last_tap > 150:
			last_tap = Time.get_ticks_msec()
			_overlay_tap(s)
	_check(str(s.get("_phase")) == "results", "%s reaches the results (phase %s)" % [what, str(s.get("_phase"))])
	return seen


## A simulated tap (release) on the summon overlay.
func _overlay_tap(s: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	s.call("_on_overlay_input", ev)


func _wait_real(sec: float) -> void:
	await create_timer(sec).timeout


# ------------------------------------------------------------------ quests

func _quests() -> void:
	var s := await _go("quests")
	var ready := 0
	for q: Dictionary in _game.quests():
		if bool(q.get("ready", false)):
			ready += 1
	_check(ready >= 1, "summoning made a quest ready")
	var gems0 := int(_game.currency("gems"))
	s.call("_claim_all")
	await _frames(3)
	_check(int(_game.currency("gems")) > gems0, "Claim all grants gems")
	for q: Dictionary in _game.quests():
		_check(not bool(q.get("ready", false)), "no quest left ready after Claim all (%s)" % str(q.id))
	s.call("_claim", "dq_idle", null)
	await _frames(2)
	_close_modals()


# ------------------------------------------------------------------ shop

func _shop() -> void:
	var s := await _go("shop")
	var gems0 := int(_game.currency("gems"))
	s.call("_buy", "daily_gift")
	await _frames(2)
	_check(int(_game.currency("gems")) > gems0, "daily gift grants gems")
	s.call("_buy", "daily_gift")
	await _frames(2)
	s.call("_buy", "starter_pack")
	await _frames(2)
	var offers: Array = _game.offers()
	for o: Dictionary in offers:
		if str(o.id) == "starter_pack":
			_check(not bool(o.available), "starter pack sold out after one buy")
	s.call("_buy", "monthly_card")
	await _frames(2)
	_check(int(_game.monthly_card_days_left()) > 0, "monthly card active")
	var b := _find_button(s, "Test purchase: no charge")
	_check(b != null, "purchase buttons say Test purchase: no charge")
	_close_modals()


# ------------------------------------------------------------------ settings

func _settings() -> void:
	var s := await _go("settings")
	var gems0 := int(_game.currency("gems"))
	var gb := _find_button(s, "+3,000 Gems")
	_check(gb != null, "dev +gems button")
	if gb:
		gb.pressed.emit()
	_check(int(_game.currency("gems")) == gems0 + 3000, "+3000 gems")
	var gold0 := int(_game.currency("gold"))
	var b2 := _find_button(s, "+100K Gold")
	if b2:
		b2.pressed.emit()
	_check(int(_game.currency("gold")) == gold0 + 100000, "+100K gold")
	var x0 := int(_game.currency("hero_exp"))
	var b3 := _find_button(s, "+50K Hero EXP")
	if b3:
		b3.pressed.emit()
	_check(int(_game.currency("hero_exp")) == x0 + 50000, "+50K hero EXP")
	var off0 := int(_game.state.dev_time_offset)
	var b4 := _find_button(s, "Skip 8 hours")
	if b4:
		b4.pressed.emit()
	_check(int(_game.state.dev_time_offset) == off0 + 8 * 3600000, "skip 8 hours")
	# Nudity: 18+ confirm first, then an obvious notice both ways and the row's state line.
	var nt := s.find_child("Toggle_nudity", true, false) as CheckButton
	_check(nt != null, "nudity toggle")
	if nt:
		nt.button_pressed = true
		await _frames(1)
		_check(_game.setting("nudity") == false, "nudity waits for the 18+ confirm")
		_check(_press_in_modal("I'm 18+"), "nudity asks 18+ first")
		await _frames(2)
		_check(_game.setting("nudity") == true and HeroArt.nudity, "nudity on")
		var notice: Node = _ui.root.get_node_or_null("NudityNotice")
		_check(notice != null and bool(notice.get_meta("on", false)), "big notice: NUDITY MODE ENABLED")
		var st := s.find_child("NudityState", true, false) as Label
		_check(st != null and st.text.begins_with("NUDITY MODE ON"), "the row says nudity mode is on")
		nt.button_pressed = false
		await _frames(2)
		_check(_game.setting("nudity") == false and not HeroArt.nudity, "nudity off")
		notice = _ui.root.get_node_or_null("NudityNotice")
		_check(notice != null and not bool(notice.get_meta("on", true)), "big notice: NUDITY MODE DISABLED")
		_check(st != null and st.text.begins_with("NUDITY MODE OFF"), "the row says nudity mode is off")
	for c in s.find_children("*", "CheckButton", true, false):
		(c as CheckButton).button_pressed = not (c as CheckButton).button_pressed
	await _frames(1)
	_check(_game.setting("sound") == false, "sound toggle saves")
	for c in s.find_children("*", "CheckButton", true, false):
		(c as CheckButton).button_pressed = true
	await _frames(1)
	_check(_game.setting("sound") == true and _game.setting("auto_ultimates") == true, "toggles back on")
	var rb := _find_button(s, "Reset Save")
	_check(rb != null, "Reset Save button")
	if rb:
		rb.pressed.emit()
		await _frames(2)
		_check(_press_in_modal("Reset"), "reset asks first")
		await _frames(4)
		_check(_ui.current_name == "home", "reset returns home")
		_check(int(_game.owned_heroes().size()) == 3, "reset gives a new game")
