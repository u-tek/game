extends Control
## Screen "home": the Lobby (style v2, docs/dev/ui-style-v2.md section 6). Full bleed under
## the translucent chrome: the lobby hero stands full body (animated HeroSprite, cropped by
## the nav) in the sanctum hall, with a speech bubble. Top left: a banner carousel (summon
## banner, offers, chapter); top right: the objective strip (the guide's next step, else
## "Clear Stage x-y"). Side buttons: Daily and Offers on the left, Hero, View (hide the
## UI) and the Spire (tower) on the right. The four shortcut plates: Shop and Sanctum (idle rewards, fill %, tap
## for the claim sheet with Quick Claim) bottom left, Team and Campaign (next stage preview)
## bottom right. Tap the hero for another line; the edge chevrons switch the lobby hero
## (saved as the "lobby_hero" setting). Refreshes on Game.changed and once a second.

const SceneBackdrop := preload("res://src/ui/battle/scene_backdrop.gd")
const LobbyLines := preload("res://src/ui/battle/lobby_lines.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")

## Game setting holding the hero the player picked for the lobby.
const HERO_KEY := "lobby_hero"
const BANNER_SECS := 5.0
const BANNER_SIZE := Vector2(330, 132)
const NOTICE_W := 340.0
## Shortcut plates: about 37% / 42% of the width with a clear gap in the middle, so the
## hero's legs show between the two columns.
const TOP_PLATE := Vector2(268, 116)
const BIG_PLATE := Vector2(304, 150)
const ROW_GAP := 8.0
## Plate inset from the screen edges.
const PLATE_EDGE := 8.0
## Gap between the bottom plate row and the nav (clears the raised Lobby hexagon).
const PLATE_LIFT := 28.0
const SIDE_PITCH := 128.0
const BUBBLE_W := 400.0
## The hero's head (halo) starts this far below the top bar; the feet end below the window.
const HEAD_GAP := 140.0
const FIGURE_VISIBLE := 0.92

var _backdrop: Control
var _shade: TextureRect
var _anchor: Node2D
var _sprite: Node2D
var _hero_id := ""
## What the Lobby sprite shows (HeroArt.art_key: hero, skin, nude or not); a change rebuilds it.
var _hero_key := ""
var _hero_hit: Button
var _ui: Control
var _banner_slot: Control
var _banner_page := 0
var _banner_t := 0.0
var _notice: Button
var _notice_cb := Callable()
var _speech: PanelContainer
var _line := 0
var _prev_btn: Button
var _next_btn: Button
var _side_daily: Button
var _side_offers: Button
var _side_tower: Button
var _side_hero: Button
var _side_view: Button
var _shop: Button
var _sanctum: Button
var _meter: PanelContainer
var _team: Button
var _campaign: Button
var _camp_info: VBoxContainer
var _camp_sig := ""
var _full := false
var _restore: Button
var _sheet: Control
var _sheet_refs: Dictionary = {}
var _t := 0.0
var _tick := 0.0
var _cheer_left := 0.0


## params: sheet (bool) opens the Sanctum sheet (screenshots).
func setup(params: Dictionary) -> void:
	UI.set_full_bleed(true)
	_build()
	Game.changed.connect(_refresh)
	resized.connect(_layout)
	_refresh()
	_layout.call_deferred()
	if bool(params.get("sheet", false)):
		_open_sanctum.call_deferred()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)
	_close_sheet()


# ------------------------------------------------------------------ build

func _build() -> void:
	_backdrop = SceneBackdrop.new()
	_backdrop.kind = "home"
	_backdrop.horizon = 0.64
	_backdrop.floor_shade = 0.0
	_backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_backdrop)

	_anchor = Node2D.new()
	_anchor.name = "LobbyHero"
	add_child(_anchor)

	# Shade behind the shortcut plates so they read over any art.
	_shade = TextureRect.new()
	_shade.name = "Shade"
	_shade.texture = Kit.vgradient(Color(Kit.CHROME, 0.0), Color(Kit.CHROME, 0.86))
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = MOUSE_FILTER_IGNORE
	_shade.anchor_top = 0.56
	_shade.anchor_right = 1.0
	_shade.anchor_bottom = 1.0
	add_child(_shade)

	# Tap the hero: another line and a little reaction.
	_hero_hit = Button.new()
	_hero_hit.name = "HeroHit"
	_hero_hit.theme_type_variation = &"BareButton"
	_hero_hit.focus_mode = FOCUS_NONE
	_hero_hit.mouse_filter = MOUSE_FILTER_PASS
	_hero_hit.pressed.connect(_on_hero_tap)
	add_child(_hero_hit)

	_ui = Control.new()
	_ui.name = "LobbyUI"
	_ui.mouse_filter = MOUSE_FILTER_IGNORE
	_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_ui)

	_banner_slot = Control.new()
	_banner_slot.name = "BannerSlot"
	_banner_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_banner_slot.size = Vector2(BANNER_SIZE.x, BANNER_SIZE.y + 22.0)
	_ui.add_child(_banner_slot)
	_show_banner(0, false)

	_notice = Kit.notice_bar("", func() -> void:
		if _notice_cb.is_valid():
			_notice_cb.call(), NOTICE_W)
	_ui.add_child(_notice)

	_side_daily = Kit.side_button("quests", "Daily", func() -> void: UI.go("quests"), "dark")
	_side_offers = Kit.side_button("gift", "Offers", func() -> void: UI.go("shop"), "orange")
	_side_hero = Kit.side_button("avatar", "Hero", _open_hero, "dark")
	_side_view = Kit.side_button("eye_off", "View", _hide_ui, "dark")
	_side_tower = Kit.side_button("trophy", "Spire", func() -> void: UI.go("tower"), "dark")
	_side_tower.name = "SideSpire"
	Kit.add(_ui, [_side_daily, _side_offers, _side_hero, _side_view, _side_tower])

	_speech = Kit.speech_bubble("", "", BUBBLE_W)
	_ui.add_child(_speech)
	_prev_btn = _chevron(-1)
	_next_btn = _chevron(1)
	Kit.add(_ui, [_prev_btn, _next_btn])

	# Shortcut plates.
	_shop = Kit.shortcut("Shop", "shop", "blue", func() -> void: UI.go("shop"), {"size": TOP_PLATE})
	_meter = Kit.percent_meter("Fill", 0.0, "sanctum")
	_sanctum = Kit.shortcut("Sanctum", "sanctum", "dark", _open_sanctum, {"size": BIG_PLATE, "sub": _meter})
	_team = Kit.shortcut("Team", "team", "white", func() -> void: UI.go("formation"), {"size": TOP_PLATE, "side": "right"})
	_campaign = Kit.shortcut("Campaign", "campaign", "orange", _on_campaign, {"size": BIG_PLATE, "side": "right"})
	# The "!" sits inside the plate's corner, clear of the screen edge.
	var cbadge := Kit.new_badge(30.0, "!")
	cbadge.set("round", true)
	cbadge.set("color", Kit.ACCENT)
	cbadge.name = "KitNew"
	cbadge.position = Vector2(BIG_PLATE.x - 40.0, -10.0)
	_campaign.add_child(cbadge)
	_camp_info = Kit.vbox(0)
	_camp_info.name = "StageInfo"
	_camp_info.mouse_filter = MOUSE_FILTER_IGNORE
	(_campaign.get("face") as Control).add_child(_camp_info)
	Kit.add(_ui, [_shop, _sanctum, _team, _campaign])


## Bare chevron button at a screen edge (switches the lobby hero). dir -1 = previous.
func _chevron(dir: int) -> Button:
	var b := Kit.icon_button("chevron_right", func() -> void: _switch_hero(dir), Kit.BUTTON_H, "bare")
	b.name = "Prev" if dir < 0 else "Next"
	var g := b.get_node("Glyph") as TextureRect
	g.flip_h = dir < 0
	g.modulate = Color(1, 1, 1, 0.85)
	g.offset_left = -22.0
	g.offset_top = -22.0
	g.offset_right = 22.0
	g.offset_bottom = 22.0
	return b


func _layout() -> void:
	if _ui == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var w := size.x
	var vh := size.y
	var top := UI.content_top() + 10.0
	var bottom := UI.content_bottom()

	_banner_slot.position = Vector2(14, top)
	_notice.position = Vector2(w - NOTICE_W - 8.0, top + 10.0)
	_notice.size = Vector2(NOTICE_W, Kit.BUTTON_H)

	# Shortcut grid, ending PLATE_LIFT above the nav.
	var by := vh - bottom - PLATE_LIFT - (TOP_PLATE.y + ROW_GAP + BIG_PLATE.y)
	_place(_shop, Vector2(PLATE_EDGE, by), TOP_PLATE)
	_place(_sanctum, Vector2(PLATE_EDGE, by + TOP_PLATE.y + ROW_GAP), BIG_PLATE)
	_place(_team, Vector2(w - TOP_PLATE.x - PLATE_EDGE, by), TOP_PLATE)
	_place(_campaign, Vector2(w - BIG_PLATE.x - PLATE_EDGE, by + TOP_PLATE.y + ROW_GAP), BIG_PLATE)
	_camp_info.position = Vector2(BIG_PLATE.x * 0.07, BIG_PLATE.y * 0.6)
	_camp_info.size = Vector2(BIG_PLATE.x * 0.42, BIG_PLATE.y * 0.34)

	# Side buttons under the banner.
	var sy := top + BANNER_SIZE.y + 40.0
	var sw := _side_daily.get_combined_minimum_size()
	_side_daily.position = Vector2(6, sy)
	_side_offers.position = Vector2(6, sy + SIDE_PITCH)
	_side_hero.position = Vector2(w - sw.x - 6.0, sy)
	_side_view.position = Vector2(w - sw.x - 6.0, sy + SIDE_PITCH)
	_side_tower.position = Vector2(w - sw.x - 6.0, sy + SIDE_PITCH * 2.0)

	# Speech bubble at the hero's waist, left of the centre line; chevrons at the edges.
	var bh := maxf(_speech.get_combined_minimum_size().y, 96.0)
	var bub_y := minf(vh * 0.5 - 30.0, by - bh - 40.0)
	# Below the side buttons (three on the right), but never into the shortcut plates.
	bub_y = minf(maxf(bub_y, sy + SIDE_PITCH * 3.0 - 8.0), by - bh - 12.0)
	_speech.position = Vector2(84, bub_y)
	_speech.size = Vector2(BUBBLE_W, 0)
	var cy := bub_y + bh * 0.5 - Kit.BUTTON_H * 0.5
	_prev_btn.position = Vector2(0, cy)
	_next_btn.position = Vector2(w - Kit.BUTTON_H, cy)

	# The hero: full body, head under the banner row, cropped by the nav.
	var head := UI.content_top() + HEAD_GAP
	var fig_h := (vh - head) / FIGURE_VISIBLE
	_anchor.position = Vector2(w * 0.5, head + fig_h)
	if _sprite and is_instance_valid(_sprite):
		_sprite.scale = Vector2.ONE
		var base_h: float = _sprite.call("get_height")
		var k := fig_h / maxf(base_h, 1.0)
		_sprite.scale = Vector2(k, k)
	_hero_hit.position = Vector2(w * 0.24, head)
	_hero_hit.size = Vector2(w * 0.52, maxf(by - head - 12.0, 120.0))
	if _restore:
		_restore.size = size


func _place(c: Control, at: Vector2, sz: Vector2) -> void:
	c.position = at
	c.size = sz


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_hero()
	_refresh_idle()
	_refresh_campaign()
	_refresh_badges()
	_refresh_guide()


## First-session guidance: the Sanctum (free quick claim), Team and Campaign plates; the
## Sanctum sheet marks its Quick Claim button.
func _refresh_guide() -> void:
	var step := Guide.step()
	Guide.mark(_sanctum, step == "claim", 0)
	Guide.mark(_team, step == "formation", 0)
	Guide.mark(_campaign, step == "battle", 0)
	var q: Variant = _sheet_refs.get("quick", null)
	if q is Control and is_instance_valid(q):
		Guide.mark(q as Control, step == "claim", 0)


func _refresh_badges() -> void:
	Kit.set_dot(_side_daily.get_node("Face/Tile") as Control, int(Game.quests_ready_count()) > 0, 20.0, Vector2(-8, -6))
	var gift := false
	for o: Dictionary in Game.offers():
		if str(o.get("price_label", "")) == "Free" and bool(o.get("available", false)):
			gift = true
	Kit.set_new(_side_offers.get_node("Face/Tile") as Control, gift, 28.0, Vector2(-12, -10))
	Kit.set_dot(_team, Guide.formation_can_improve(), 21.0, Vector2(-2, -6))
	_refresh_objective()


## The objective strip: the guide's next step while it is active, else the next stage.
func _refresh_objective() -> void:
	var st := Game.current_stage()
	var text := "Next: Stage %s" % str(st.get("id", "")) if not st.is_empty() else "Every stage cleared"
	var cb := _on_campaign
	match Guide.step():
		"claim":
			# The first claim is the free Quick Claim inside the Sanctum sheet.
			var idle: Dictionary = Game.idle_status()
			var hours := int(idle.get("quick_claim_ms", 7200000)) / 3600000
			text = "Quick Claim %dh of rewards" % hours
			cb = _open_sanctum
		"summon":
			text = "Summon new heroes"
			cb = func() -> void: UI.go("summon")
		"formation":
			text = "Fill your team"
			cb = func() -> void: UI.go("formation")
		"level":
			text = "Level up heroes"
			cb = func() -> void: UI.go("heroes")
		"quests":
			text = "Claim quest rewards"
			cb = func() -> void: UI.go("quests")
	var l := _notice.get_meta("text_label") as Label
	if l.text != text:
		l.text = text
		Kit.fit_label(l, NOTICE_W - 130.0, 24, 18)
	_notice_cb = cb


# ------------------------------------------------------------------ the lobby hero

## The hero shown in the lobby: the player's pick if still owned, else the strongest team
## hero (heroes with painted art first).
func _pick_hero() -> String:
	var want: Variant = Game.setting(HERO_KEY)
	if want is String and want != "" and Game.owns(want):
		return want
	var best := ""
	var best_score := -1
	for id: String in Game.formation():
		if id == "":
			continue
		var score: int = int(Game.hero_power(id)) + (100000000 if HeroArt.has_art(id) else 0)
		if score > best_score:
			best_score = score
			best = id
	if best == "":
		var owned := Game.owned_heroes()
		if not owned.is_empty():
			best = str(owned[0].id)
	return best


## Owned heroes in lobby order: the team first (slot order), then the rest by power.
func _hero_order() -> Array[String]:
	var out: Array[String] = []
	for id: String in Game.formation():
		if id != "" and not out.has(id):
			out.append(id)
	var rest: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		var id := str(h.get("id", ""))
		if id != "" and not out.has(id):
			rest.append(id)
	rest.sort_custom(func(a: String, b: String) -> bool: return int(Game.hero_power(a)) > int(Game.hero_power(b)))
	out.append_array(rest)
	return out


func _refresh_hero() -> void:
	var id := _pick_hero()
	var many := _hero_order().size() > 1
	_prev_btn.visible = many
	_next_btn.visible = many
	var skin := Game.equipped_skin(id) if id != "" else ""
	var key := HeroArt.art_key(id, skin) if id != "" else ""
	if id == _hero_id and key == _hero_key:
		return
	_hero_id = id
	_hero_key = key
	if _sprite and is_instance_valid(_sprite):
		_sprite.queue_free()
	_sprite = null
	_cheer_left = 0.0
	if id == "":
		_speech.visible = false
		return
	_sprite = HeroArt.make_sprite(id, skin)
	_anchor.add_child(_sprite)
	_speech.visible = true
	(_speech.get_meta("name_label") as Label).text = str(Game.hero_def(id).get("name", id))
	_line = int(Time.get_unix_time_from_system() / 60.0) % LobbyLines.lines(id).size()
	_say(LobbyLines.lines(id)[_line])
	_layout()


func _say(text: String) -> void:
	var l := _speech.get_meta("text_label") as Label
	l.text = text
	l.visible_ratio = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "visible_ratio", 1.0, clampf(text.length() * 0.018, 0.25, 1.1))
	# A longer line can wrap to another row: keep the chevrons centred on the bubble.
	_layout.call_deferred()


func _on_hero_tap() -> void:
	if _hero_id == "":
		return
	var lines := LobbyLines.lines(_hero_id)
	_line = (_line + 1) % lines.size()
	_say(lines[_line])
	_cheer()


func _switch_hero(dir: int) -> void:
	var order := _hero_order()
	if order.size() < 2:
		return
	var i := order.find(_hero_id)
	var nxt := order[posmod(i + dir, order.size())]
	Game.set_setting(HERO_KEY, nxt)


func _open_hero() -> void:
	if _hero_id != "":
		UI.go("hero_detail", {"hero_id": _hero_id, "browse": _hero_order()})


## Hides the lobby UI and the chrome to look at the hero; any tap brings them back.
func _hide_ui() -> void:
	_ui.visible = false
	_shade.visible = false
	UI.set_chrome(false, false)
	_restore = Button.new()
	_restore.name = "ShowUI"
	_restore.theme_type_variation = &"BareButton"
	_restore.focus_mode = FOCUS_NONE
	_restore.position = Vector2.ZERO
	_restore.size = size
	add_child(_restore)
	_restore.pressed.connect(func() -> void:
		_restore.queue_free()
		_restore = null
		_ui.visible = true
		_shade.visible = true
		UI.set_chrome(true, true))


## The hero celebrates for a moment (claims, taps).
func _cheer() -> void:
	if _sprite and is_instance_valid(_sprite) and _sprite.has_method("play_victory"):
		_sprite.call("play_victory")
		_cheer_left = 2.6


# ------------------------------------------------------------------ banner carousel

## Shows banner page `page` (0 summon, 1 offers, 2 chapter) in the top-left slot.
func _show_banner(page: int, animate: bool = true) -> void:
	_banner_page = posmod(page, 3)
	_banner_t = 0.0
	var old: Array[Node] = _banner_slot.get_children()
	var b := _make_banner(_banner_page)
	_banner_slot.add_child(b)
	for o in old:
		if animate and o is Control:
			var tw := (o as Control).create_tween()
			tw.tween_property(o, "modulate:a", 0.0, 0.2)
			tw.tween_callback(o.queue_free)
		else:
			o.queue_free()
	if animate:
		b.modulate.a = 0.0
		b.position.x = 18.0
		var tw2 := b.create_tween().set_parallel(true)
		tw2.tween_property(b, "modulate:a", 1.0, 0.25)
		tw2.tween_property(b, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _make_banner(page: int) -> Button:
	var opts := {"size": BANNER_SIZE, "pages": 3, "page": page}
	var title := ""
	var sub := ""
	var cb := Callable()
	var badge := false
	match page:
		0:
			var bn := Game.banner()
			title = str(bn.get("name", "Summon"))
			var free := bool(Game.free_pull_available())
			sub = "Free pull ready" if free else "Summon now"
			opts["hero_id"] = _featured(int(Time.get_unix_time_from_system() / BANNER_SECS / 3.0))
			badge = free
			cb = func() -> void: UI.go("summon")
		1:
			var offer := _featured_offer()
			title = str(offer.get("name", "Offers"))
			sub = "Free gift" if str(offer.get("price_label", "")) == "Free" else str(offer.get("tag", "Offer"))
			opts["color"] = Kit.ORANGE
			opts["hero_id"] = "liora"
			badge = bool(offer.get("available", false)) and str(offer.get("price_label", "")) == "Free"
			cb = func() -> void: UI.go("shop")
		_:
			var st := Game.current_stage()
			var chs := Game.chapters()
			var ci := clampi(int(st.get("chapter", chs.size() - 1)), 0, chs.size() - 1)
			var ch: Dictionary = chs[ci]
			title = "Chapter %d  %s" % [ci + 1, str(ch.get("name", ""))]
			var first := int(ch.get("first_stage", ci * 10))
			var count := int(ch.get("stage_count", 10))
			sub = "%d / %d cleared" % [clampi(Game.cleared_count() - first, 0, count), count]
			opts["color"] = HeroArt.faction_color(str(ch.get("faction", "celestial")))
			opts["sub_color"] = Kit.ACCENT_HI
			var boss := _boss_of(Game.stage(first + count - 1))
			if boss != "":
				opts["hero_id"] = boss
				opts["skin"] = ""        # an enemy: the base look
			cb = _on_campaign
	var b := Kit.banner_card(title, sub, cb, opts)
	b.name = "Banner"
	# The "N" sits on the corner, clear of the title.
	Kit.set_new(b, badge, 30.0, Vector2(-12, -12))
	return b


## A featured (legendary) hero of the summon banner, rotating with `turn`.
func _featured(turn: int) -> String:
	var pool: Array = Game.banner().get("pool", [])
	var legends: Array[String] = []
	for id: Variant in pool:
		if str(Game.hero_def(str(id)).get("rarity", "")) == "legendary":
			legends.append(str(id))
	if legends.is_empty():
		return str(pool[0]) if not pool.is_empty() else ""
	return legends[posmod(turn, legends.size())]


## The offer worth showing: a free gift waiting, else the first offer still available.
func _featured_offer() -> Dictionary:
	var first := {}
	for o: Dictionary in Game.offers():
		if not bool(o.get("available", false)):
			continue
		if str(o.get("price_label", "")) == "Free":
			return o
		if first.is_empty():
			first = o
	return first if not first.is_empty() else {"name": "Shop", "tag": "Offers", "available": false}


# ------------------------------------------------------------------ campaign plate

func _refresh_campaign() -> void:
	var st := Game.current_stage()
	var team := int(Game.team_power())
	var rec := int(st.get("recommended_power", 0))
	var verdict := StageInfo.verdict(team, rec)
	var sig := "%s|%d|%s" % [str(st.get("id", "")), rec, str(verdict[0])]
	var badge := _campaign.get_node_or_null("KitNew") as Control
	if badge:
		badge.visible = not st.is_empty() and team >= rec
	if sig == _camp_sig:
		return
	_camp_sig = sig
	for c in _camp_info.get_children():
		c.queue_free()
	if st.is_empty():
		_campaign.call("set_art", null, "")
		var done := Kit.label("ALL STAGES CLEARED", 20, Color(1, 1, 1, 0.85), "cond_bold")
		_camp_info.add_child(done)
		return
	var boss := _boss_of(st)
	_campaign.call("set_art", Kit.art_crop(boss, 2.2, 1.4) if boss != "" else null, "STAGE %s" % str(st.id))
	var nm := Kit.label(str(st.get("name", "")).to_upper(), 20, Color(1, 1, 1, 0.88), "cond_bold")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = BIG_PLATE.x * 0.42
	_camp_info.add_child(nm)
	var row := Kit.hbox(4)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(Kit.icon("power", 24))
	var col: Color = verdict[1]
	row.add_child(Kit.label(Kit.format_num(rec), 24, col.lerp(Color.WHITE, 0.15), "cond_bold"))
	if bool(st.get("is_boss", false)):
		row.add_child(Kit.tag("BOSS", Kit.EMBER, Color.WHITE, 16))
	_camp_info.add_child(row)


## The boss of a stage (or its first enemy) as a hero id.
func _boss_of(st: Dictionary) -> String:
	var first := ""
	for e: Variant in st.get("enemies", []):
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		if first == "":
			first = str(d.get("hero_id", ""))
		if bool(d.get("is_boss", false)):
			return str(d.get("hero_id", ""))
	return first


func _on_campaign() -> void:
	var st := Game.current_stage()
	if st.is_empty():
		UI.go("campaign")
		return
	UI.go("campaign", {"open_stage": int(st.index)})


# ------------------------------------------------------------------ sanctum (idle rewards)

func _refresh_idle() -> void:
	var st: Dictionary = Game.idle_status()
	var elapsed := int(st.get("elapsed_ms", 0))
	var cap := maxi(int(st.get("cap_ms", 1)), 1)
	var pct := 100.0 * float(elapsed) / float(cap)
	_full = bool(st.get("full", false))
	Kit.set_percent_meter(_meter, pct)
	# The Sanctum grows with the campaign: its level (next to the title) is the number of
	# stages cleared.
	_sanctum.call("set_title_tag", "LV %d" % maxi(1, Game.cleared_count()))
	Kit.set_new(_sanctum, _full, 30.0, Vector2(-6, -10))
	_refresh_sheet(st)


## The Sanctum sheet: fill meter, rate, pending rewards, Quick Claim and Claim.
func _open_sanctum() -> void:
	if _sheet and is_instance_valid(_sheet):
		return
	var st: Dictionary = Game.idle_status()
	var col := Kit.vbox(18)
	col.custom_minimum_size.x = 580
	var head := Kit.hbox(16)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	var hx := Kit.hex_badge("sanctum", 84, Kit.ACCENT_DEEP, Color.WHITE)
	hx.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(hx)
	var mid := Kit.vbox(0)
	mid.mouse_filter = MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(Kit.label("SANCTUM FILL", 22, Kit.TEXT_DIM, "cond_bold"))
	var pct_l := Kit.label("0%", 56, Kit.ACCENT_DEEP, "title")
	mid.add_child(pct_l)
	head.add_child(mid)
	var right := Kit.vbox(2)
	right.mouse_filter = MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	var time_l := Kit.label("", 26, Kit.TEXT, "cond_bold")
	time_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(time_l)
	var rate := Kit.hbox(4)
	rate.alignment = BoxContainer.ALIGNMENT_END
	rate.mouse_filter = MOUSE_FILTER_IGNORE
	rate.add_child(Kit.currency_icon("gold", 28))
	var per_hour: Dictionary = st.get("per_hour", {})
	rate.add_child(Kit.label("+%s / h" % Kit.format_full(int(per_hour.get("gold", 0))), 24, Kit.TEXT_DIM, "cond_bold"))
	right.add_child(rate)
	head.add_child(right)
	col.add_child(head)
	var bar := Kit.progress_bar(0, 1, Kit.ACCENT, 18, "", true)
	col.add_child(bar)
	col.add_child(Kit.header_bar("Ready to collect", null, "chest"))
	var pending := Kit.vbox(0)
	pending.custom_minimum_size.y = 150
	pending.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(pending)
	var hint := Kit.body("The Sanctum fills for %s while you are away. Clearing stages raises its rate." % Kit.format_time(int(st.get("cap_ms", 0))), 21, Kit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var row := Kit.hbox(14)
	var quick_slot := Kit.hbox(0)
	quick_slot.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(quick_slot)
	var claim_slot := Kit.hbox(0)
	claim_slot.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(claim_slot)
	col.add_child(row)
	_sheet_refs = {"pct": pct_l, "time": time_l, "bar": bar, "pending": pending, "quick_slot": quick_slot,
		"claim_slot": claim_slot, "pending_sig": "-", "quick_sig": "-"}
	_sheet = UI.popup("Sanctum", col, func() -> void:
		_sheet = null
		_sheet_refs = {}, 640.0, true)
	_refresh_sheet(st)
	_refresh_guide()


func _close_sheet() -> void:
	if _sheet and is_instance_valid(_sheet):
		UI.close_modal(_sheet)
	_sheet = null
	_sheet_refs = {}


func _refresh_sheet(st: Dictionary) -> void:
	if _sheet_refs.is_empty() or _sheet == null or not is_instance_valid(_sheet):
		return
	var elapsed := int(st.get("elapsed_ms", 0))
	var cap := maxi(int(st.get("cap_ms", 1)), 1)
	(_sheet_refs.pct as Label).text = "%d%%" % int(100.0 * elapsed / cap)
	(_sheet_refs.time as Label).text = ("FULL  %s" % Kit.format_time(cap)) if bool(st.get("full", false)) else "%s / %s" % [Kit.format_time(elapsed), Kit.format_time(cap)]
	Kit.set_progress(_sheet_refs.bar as ProgressBar, elapsed, cap, "", false)
	var pending: Dictionary = st.get("pending", {})
	var sig := JSON.stringify(pending)
	if sig != str(_sheet_refs.pending_sig):
		_sheet_refs.pending_sig = sig
		var box := _sheet_refs.pending as VBoxContainer
		for c in box.get_children():
			c.queue_free()
		var any := false
		for k: String in pending:
			if int(pending[k]) > 0:
				any = true
		if any:
			box.add_child(Kit.reward_list(pending, 104, true, true, true))
		else:
			box.add_child(Kit.empty_state("Your heroes are gathering rewards...", "sanctum", true))
		# Claim: cyan when there is something to collect, a resting light button otherwise.
		var cs := _sheet_refs.claim_slot as HBoxContainer
		for c in cs.get_children():
			c.queue_free()
		var claim := Kit.primary_button("Claim", _claim, "chest") if any else Kit.light_button("Claim", Callable(), "chest")
		claim.name = "Claim"
		claim.disabled = not any
		claim.size_flags_horizontal = SIZE_EXPAND_FILL
		claim.custom_minimum_size.y = 108
		cs.add_child(claim)
	var cost := int(st.get("quick_claim_cost", -1))
	var left := int(st.get("quick_claims_left", 0))
	var qsig := "%d/%d" % [cost, left]
	if qsig != str(_sheet_refs.quick_sig):
		_sheet_refs.quick_sig = qsig
		var slot := _sheet_refs.quick_slot as HBoxContainer
		for c in slot.get_children():
			c.queue_free()
		var q := _make_quick_button(cost, left, int(st.get("quick_claim_ms", 7200000)))
		slot.add_child(q)
		_sheet_refs["quick"] = q
		Guide.mark(q, Guide.step() == "claim", 0)


func _make_quick_button(cost: int, left: int, ms: int) -> Button:
	var hours := "%dh" % (ms / 3600000)
	var b: Button
	if cost < 0 or left <= 0:
		b = Kit.light_button("")
		b.disabled = true
		_two_line(b, "Quick Claim", "NONE LEFT TODAY", Kit.TEXT_DIM, Kit.TEXT_DIM)
	elif cost == 0:
		b = Kit.light_button("", _quick_claim)
		_two_line(b, "Quick Claim", "FREE  ·  %s NOW" % hours.to_upper(), Kit.TEXT, Color("1f9e63"))
	else:
		b = Kit.cost_button("Quick Claim %s" % hours, "gems", cost, _quick_claim, "light")
	b.name = "QuickClaim"
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 108)
	return b


func _two_line(b: Button, line1: String, line2: String, c1: Color, c2: Color) -> void:
	var v := Kit.vbox(0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var a := Kit.label(line1, 30, c1, "extrabold")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := Kit.label(line2, 22, c2, "cond_bold")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	v.add_child(s)
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_bottom = -4
	b.add_child(v)


func _claim() -> void:
	var st: Dictionary = Game.idle_status()
	var pending: Dictionary = st.get("pending", {})
	var has_any := false
	for k: String in pending:
		if int(pending[k]) > 0:
			has_any = true
	if not has_any:
		UI.toast("Nothing to collect yet. The Sanctum fills every minute.")
		return
	_close_sheet()
	var reward: Dictionary = Game.claim_idle()
	UI.show_reward("Sanctum Rewards", reward)
	_cheer()


func _quick_claim() -> void:
	var st: Dictionary = Game.idle_status()
	var cost := int(st.get("quick_claim_cost", -1))
	var hours := int(st.get("quick_claim_ms", 7200000)) / 3600000
	if cost < 0:
		UI.toast("No quick claims left today", "bad")
		return
	if cost > Game.currency("gems"):
		UI.toast("Not enough gems", "bad")
		return
	var run := func() -> void:
		_close_sheet()
		var res: Dictionary = Game.quick_claim()
		if not bool(res.get("ok", false)):
			UI.toast(str(res.get("error", "Quick claim failed")), "bad")
			return
		UI.show_reward("Quick Claim: %dh" % hours, res.get("value", {}))
		_cheer()
	if cost == 0:
		run.call()
	else:
		UI.confirm("Spend %s gems to collect %d hours of Sanctum rewards now?" % [Kit.format_full(cost), hours], run, Callable(), "Spend %s" % Kit.format_full(cost))


# ------------------------------------------------------------------ motion

func _process(delta: float) -> void:
	_t += delta
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh_idle()
	if _ui.visible:
		_banner_t += delta
		if _banner_t >= BANNER_SECS:
			_show_banner(_banner_page + 1)
	if _cheer_left > 0.0:
		_cheer_left -= delta
		if _cheer_left <= 0.0 and _sprite and is_instance_valid(_sprite):
			_sprite.call("play_idle")
	# A full Sanctum breathes.
	if _full:
		var k := 0.5 + 0.5 * sin(_t * 3.2)
		_meter.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.25, 1.35), k)
	else:
		_meter.modulate = Color.WHITE
