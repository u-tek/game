extends Control
## Screen "formation" (bottom-nav Team tab): pick the five heroes who fight. Style v4
## (docs/dev/ui-style-v4.md): the team as a printed poster in the approved Lobby poster's look, on a
## paper matte (the idea of numbered units: five positions set as huge compressed numerals).
## The poster: a dark band down the left with the lead hero's red halftone print, the brand marks and
## the team's data in paper type (faction counts and the bonus they give, the next stage's enemy
## factions and which of ours counter them); the Auto-fill stamp on a silver disc stuck on its foot;
## on the paper the team power set big, then the five positions "01"-"05": the FRONT pair (slots 0-1,
## facing the enemy) large, the BACK three below, each a giant numeral with the hero's art in full
## colour boxed by a hairline in front of it, her name, level and role, and an "x" to take her out.
## An empty position prints a hollow numeral and "+ ASSIGN"; the chosen one turns signal ("PICK A
## HERO"). Down the right-hand rule FRONT and BACK as turned labels; the Battle pass (to the
## campaign) stuck over the poster's foot. The whole screen scrolls as one page (owner: "not a tiny
## little window"): under the poster the bench, faction tabs and every owned hero who is not in the
## team as a printed card in a three-column grid (owner, 2026-10-20: a hero put in the team leaves
## the list). Placing a hero flies her art up to her position and the cards after her slide over to
## close the gap; taking her out drops her card back in. With nobody left on the bench, a printed
## note says so and links to Summon.
## Tap an empty position to choose it, then a bench hero to place them there; tapping a bench hero
## with no position chosen puts them in the best free one (front for guardians and strikers). Tap a
## placed hero to take them out. Every valid change is saved right away with Game.set_formation.

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const PosterCard := preload("res://src/ui/v4/poster_card.gd")
const HUD := preload("res://src/ui/components/hud.gd")

const SLOT_ORDER_FRONT: Array[int] = [0, 1, 2, 3, 4]
const SLOT_ORDER_BACK: Array[int] = [2, 3, 4, 0, 1]
const FRONT_ROLES: Array[String] = ["guardian", "striker"]
const BAND := 150.0
const RULE_IN := 44.0
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const FACTION_SHORT := {"celestial": "CEL", "infernal": "INF", "fallen": "FAL"}
## Free room at the poster's foot, where the Battle pass is stuck on.
const PASS_ROOM := 118.0
const BENCH_COLS := 3
const BENCH_HSEP := 12.0
const BENCH_VSEP := 18.0
## Bench cards slide to their new place in this long (seconds) when the grid re-flows.
const REFLOW := 0.32
## The poster is never wider than this (tablets centre it on the matte).
const MAX_W := 760.0

static var _filter_idx := 0

var _auto_btn: Button
var _slots: Array = ["", "", "", "", ""]
var _selected := -1
var _slot_holders: Array[Control] = []
var _poster: Control
var _band_print: Control
var _band_lead := ""
var _power_label: Label
var _power_value := -1
var _data_l: Label
## The bench: a plain control whose cards are placed by hand (so they can slide when it re-flows).
var _bench: Control
var _card_w := 200.0
var _card_h := 284.0
## Bench cards on show, by hero id, and what each was built from (a change rebuilds that card).
var _cards: Dictionary = {}
var _card_sigs: Dictionary = {}
var _bench_note: Control
var _bench_laid := false
## Where each position's art box is (holder space), for the art that flies up from the bench.
var _slot_boxes: Array[Rect2] = [Rect2(), Rect2(), Rect2(), Rect2(), Rect2()]
var _page: Control
var _page_scroll: ScrollContainer
var _filter_row: Control
var _warn: Label
var _hint: Label
var _pass: PK.Pass
var _built := false


## params: scroll (int, screenshots) scrolls the page once built; debug builds (motion shots): empty
## (array of positions) shows those positions empty without saving, tap_hero (id) taps her bench
## card after a moment.
func setup(params: Dictionary) -> void:
	_slots = Game.formation()
	if OS.is_debug_build() and params.get("empty", null) is Array:
		for i: Variant in params["empty"]:
			if int(i) >= 0 and int(i) < _slots.size():
				_slots[int(i)] = ""
	if OS.is_debug_build() and params.has("tap_hero"):
		_debug_tap.call_deferred(str(params["tap_hero"]))
	if params.has("scroll"):
		_scroll_later.call_deferred(int(params["scroll"]))
	if size.y > 0.0:
		_build()
	else:
		resized.connect(_build, CONNECT_ONE_SHOT)
	Game.changed.connect(_on_game_changed)


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game_changed):
		Game.changed.disconnect(_on_game_changed)


func _on_game_changed() -> void:
	# Another source (auto-fill, a new hero) changed the saved team: follow it unless the
	# player is mid-edit with an empty team (which can't be saved).
	if _has_hero(_slots):
		_slots = Game.formation()
	_refresh()


# ------------------------------------------------------------------ build

func _build() -> void:
	if _built:
		return
	_built = true
	# Wider windows (tablets) keep the poster at phone width, centred on the matte.
	var w := minf(size.x, MAX_W)
	var ox := floorf((size.x - w) * 0.5)
	PK.matte(self)
	# One scrolling page: the poster, then the bench grid.
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(size.x, size.y)
	_page_scroll = Kit.scroll(_page)
	_page_scroll.name = "TeamPage"
	_page_scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_page_scroll)
	PK.at(_page, PK.t("HALO & HORN  ©2026", 12, INK, "mono_bold"), Vector2(ox + 20, 8))
	var pub := PK.t("FORMATION  ·  FIVE POSITIONS", 12, Color(INK, 0.7), "mono")
	pub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pub.size = Vector2(420, 16)
	PK.at(_page, pub, Vector2(ox + w - 20 - 420, 9))

	var pr := Rect2(ox + 18, 30, w - 36, clampf(size.y - 70.0, 860.0, 1080.0))
	_poster = PK.poster(_page, pr)
	var p := _poster
	var pw := pr.size.x
	var ph := pr.size.y

	# ---- The band: the lead's print, the marks, the team's data.
	PK.rect(p, Rect2(0, 0, BAND, ph), PK.BAND)
	PK.at(p, PK.t("HH", 28, PAPER, "wide_black"), Vector2(14, 12))
	PK.at(p, PK.t("™", 11, PAPER, "mono"), Vector2(70, 14))
	PK.at(p, PK.t("FORMATION\nNo.05", 11, Color(PAPER, 0.85), "mono_bold"), Vector2(14, 54))
	_data_l = PK.t("", 10, Color(PAPER, 0.9), "mono")
	_data_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_data_l.size = Vector2(BAND - 36, 0)
	PK.at(p, _data_l, Vector2(14, 104))
	PK.at(p, PK.vlabel("©2026 HH, ALL RIGHTS RESERVED.", 10, Color(PAPER, 0.45)), Vector2(BAND - 6, 10))

	# ---- The right-hand rule.
	PK.rule(p, Vector2(pw - RULE_IN, 0), Vector2(1, ph))
	PK.at(p, PK.vlabel("©2026 ·", 12, INK), Vector2(pw - 12, 12))

	# ---- Team power, big, top right of the paper.
	var xr := pw - RULE_IN - 12.0
	var x0 := BAND + 16.0
	PK.at(p, PK.t("05 POSITIONS", 12, INK, "mono_bold"), Vector2(x0, 14))
	PK.at(p, PK.t("FRONT FACES THE ENEMY\nBACK IS PROTECTED", 9, Color(INK, 0.6), "mono"), Vector2(x0, 34))
	var pt := PK.t("TEAM POWER", 10, INK, "mono_bold")
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pt.size = Vector2(200, 14)
	PK.at(p, pt, Vector2(xr - 200, 12))
	_power_label = PK.t("0", 62, INK, "compressed")
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_power_label.size = Vector2(300, 70)
	PK.at(p, _power_label, Vector2(xr - 300, 18))

	# ---- The five positions.
	var top := 100.0
	var usable := ph - top - 54.0 - PASS_ROOM
	var front_h := floorf(usable * 0.54)
	var back_h := usable - front_h
	var cx0 := BAND + 10.0
	var cx1 := pw - RULE_IN - 6.0
	var cw_f := (cx1 - cx0) / 2.0
	var cw_b := (cx1 - cx0) / 3.0
	_slot_holders.clear()
	for i in 5:
		var r := Rect2(cx0 + i * cw_f, top, cw_f, front_h) if i < 2 else Rect2(cx0 + (i - 2) * cw_b, top + front_h, cw_b, back_h)
		var holder := Control.new()
		holder.name = "Slot%d" % i
		holder.mouse_filter = MOUSE_FILTER_IGNORE
		holder.position = r.position
		holder.size = r.size
		p.add_child(holder)
		_slot_holders.append(holder)
	PK.rule(p, Vector2(cx0, top + front_h - 4), Vector2(cx1 - cx0, 1), Color(INK, 0.3))
	_edge_label(p, "FRONT", top + 10)
	_edge_label(p, "BACK", top + front_h + 10)

	# ---- Notes at the poster's foot: the hint, or the empty-team warning in signal.
	_hint = PK.t("TAP A BENCH HERO TO PLACE HER, A PLACED ONE TO TAKE HER OUT. PICK A POSITION FIRST TO CHOOSE WHERE.", 9, Color(INK, 0.6), "mono")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size = Vector2(maxf(pw - x0 - 330.0, 180.0), 0)
	PK.at(p, _hint, Vector2(x0, ph - 48))
	_warn = PK.t("", 11, SIG, "mono_bold")
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.size = Vector2(maxf(pw - x0 - 330.0, 180.0), 0)
	_warn.visible = false
	PK.at(p, _warn, Vector2(x0, ph - 44))

	# ---- The Auto-fill stamp on a silver disc, stuck on the band's foot.
	var disc := SignalKit.plate("silver", pr.position + Vector2(20, ph - 132), Vector2(112, 112), {"circle": true, "shadow": 0.5}, _page)
	disc.rotation = -0.1
	disc.add_child(SignalKit.stamp("AUTO-FILL · STRONGEST FIVE · ", "AUTO", 112))
	_auto_btn = Button.new()
	_auto_btn.name = "AutoFill"
	_auto_btn.theme_type_variation = &"BareButton"
	_auto_btn.focus_mode = FOCUS_NONE
	_auto_btn.mouse_filter = MOUSE_FILTER_PASS
	_auto_btn.position = pr.position + Vector2(14, ph - 138)
	_auto_btn.size = Vector2(124, 124)
	_page.add_child(_auto_btn)
	Kit.add_press_fx(_auto_btn, disc)
	Kit._connect_pressed(_auto_btn, _on_auto)

	# ---- The Battle pass stuck over the poster's foot, then the bench under the poster.
	var by := pr.end.y
	_pass = PK.make_pass(300.0, "sword", false, false)
	_pass.hit.name = "Battle"
	Kit._connect_pressed(_pass.hit, func() -> void: UI.go("campaign"))
	_pass.position = Vector2(ox + w - 18 - 300, by - PASS_ROOM - 4.0)
	_pass.rotation = -0.025
	_filter_row = Control.new()
	_filter_row.name = "BenchTabs"
	_filter_row.mouse_filter = MOUSE_FILTER_IGNORE
	_filter_row.position = Vector2(ox + 18, by + 84)
	_filter_row.size = Vector2(w - 36, 28)
	_page.add_child(_filter_row)
	PK.rule(_page, Vector2(ox + 18, by + 124), Vector2(w - 36, 1), Color(INK, 0.3))
	_card_w = floorf((w - 36.0 - BENCH_HSEP * (BENCH_COLS - 1)) / BENCH_COLS)
	_card_h = roundf(_card_w * 1.42)
	_bench = Control.new()
	_bench.name = "Bench"
	_bench.mouse_filter = MOUSE_FILTER_IGNORE
	_bench.position = Vector2(ox + 18, by + 140)
	_bench.size = Vector2(w - 36, _card_h)
	_page.add_child(_bench)
	_page.add_child(_pass)
	_refresh_pass()
	PK.grain(self)
	SignalKit.relight(self)
	_refresh()


## A turned label down the right-hand rule with a tick (row markers).
func _edge_label(p: Control, text: String, y: float) -> void:
	PK.at(p, PK.vlabel(text, 13, INK, "mono_bold"), Vector2(p.size.x - 14, y))
	PK.rule(p, Vector2(p.size.x - RULE_IN - 4, y + 2), Vector2(9, 1), INK)


func _refresh_pass() -> void:
	var st := Game.current_stage()
	if st.is_empty():
		_pass.set_text("CAMPAIGN // ALL CLEAR", "REPLAY", "EVERY STAGE IS CLEARED", "BATTLE  >>>", "")
	else:
		_pass.set_text("CAMPAIGN // NEXT", "STAGE %s" % str(st.id), str(st.get("name", "")).to_upper(), "BATTLE  >>>",
			"REC PWR %s" % Kit.format_full(int(st.get("recommended_power", 0))))


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not _built or not is_inside_tree():
		return
	_refresh_slots()
	_refresh_summary()
	_refresh_bench()
	# First-session guidance: Auto-fill when it would clearly help.
	Guide.mark(_auto_btn, Guide.step() == "formation")


func _refresh_slots() -> void:
	for i in 5:
		var holder := _slot_holders[i]
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		var id := str(_slots[i])
		var idx := i
		var r := Rect2(Vector2.ZERO, holder.size)
		var front := i < 2
		# The numeral as big as the position allows: its height, and two digits across 80% of its
		# width (wider and neighbouring numerals run together: "0102").
		var num := clampf(r.size.y * (0.62 if front else 0.66), 80.0, 240.0)
		num = minf(num, num * r.size.x * 0.8 / maxf(PK.text_w("%02d" % (i + 1), int(num)), 1.0))
		var box := Rect2(r.size.x * (0.3 if front else 0.2), r.size.y * (0.26 if front else 0.3),
			r.size.x * (0.64 if front else 0.74), r.size.y * (0.6 if front else 0.52))
		_slot_boxes[i] = box
		var numeral := PK.t("%02d" % (i + 1), int(num), INK, "compressed")
		numeral.position = Vector2(-2, -num * 0.17)
		holder.add_child(numeral)
		if id == "":
			var sel := _selected == i
			if sel:
				numeral.add_theme_color_override("font_color", SIG)
			else:
				# A hollow numeral: outline only.
				numeral.add_theme_color_override("font_color", Color(INK, 0.0))
				numeral.add_theme_constant_override("outline_size", 3)
				numeral.add_theme_color_override("font_outline_color", Color(INK, 0.45))
			var dash := Dashed.new()
			dash.color = SIG if sel else Color(INK, 0.45)
			dash.position = box.position
			dash.size = box.size
			holder.add_child(dash)
			var cap := PK.t("PICK A HERO" if sel else "+ ASSIGN", 11, SIG if sel else Color(INK, 0.6), "mono_bold")
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cap.size = Vector2(box.size.x, 16)
			PK.at(holder, cap, box.position + Vector2(0, box.size.y * 0.5 - 8))
			PK.at(holder, PK.t("FRONT" if front else "BACK", 9, Color(INK, 0.5), "mono"), box.position + Vector2(0, box.size.y + 6))
			if sel:
				var led := HUD.Led.new()
				led.mode = "breathe"
				led.size = Vector2(16, 16)
				led.position = box.position + Vector2(box.size.x - 20, 4)
				holder.add_child(led)
			var e := _hit(holder, Rect2(Vector2(0, box.position.y - 20), Vector2(r.size.x, box.size.y + 40)), func() -> void: _tap_slot(idx))
			e.name = "Empty%d" % i
		else:
			var def := Game.hero_def(id)
			PK.rect(holder, box, Color("dedcd4"))
			var art := TextureRect.new()
			art.name = "Art"
			art.mouse_filter = MOUSE_FILTER_IGNORE
			art.texture = Kit.art_crop(id, box.size.x / box.size.y, 1.0, Kit.hero_look(id))
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			art.position = box.position
			art.size = box.size
			holder.add_child(art)
			var fr := Panel.new()
			fr.mouse_filter = MOUSE_FILTER_IGNORE
			var fb := StyleBoxFlat.new()
			fb.draw_center = false
			fb.border_color = Color(INK, 0.7)
			fb.set_border_width_all(1)
			fr.add_theme_stylebox_override("panel", fb)
			fr.position = box.position
			fr.size = box.size
			holder.add_child(fr)
			var nm := PK.t(str(def.get("name", id)).to_upper(), 13 if front else 11, INK, "mono_bold")
			nm.size = Vector2(box.size.x + 10, 16)
			nm.clip_text = true
			PK.at(holder, nm, box.position + Vector2(0, box.size.y + 5))
			var lv := int(Game.hero(id).get("level", 1))
			var sub := PK.t("LV %d  ·  %s" % [lv, str(Kit.ROLE_NAMES.get(str(def.get("role", "")), "")).to_upper()], 9, Color(INK, 0.6), "mono")
			sub.size = Vector2(box.size.x + 10, 14)
			sub.clip_text = true
			PK.at(holder, sub, box.position + Vector2(0, box.size.y + 22))
			var card := _hit(holder, Rect2(box.position - Vector2(4, 4), box.size + Vector2(8, 8)), func() -> void: _tap_slot(idx))
			card.name = "Placed%d" % i
			Kit.add_press_fx(card, art)
			# The "x" takes the hero out too (as a tap on her does), with an 88 px target.
			var xl := PK.t("x", 15, PAPER, "mono_bold")
			xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			xl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			xl.size = Vector2(22, 22)
			var xbg := PK.rect(holder, Rect2(box.position + Vector2(box.size.x - 22, 0), Vector2(22, 22)), INK)
			xbg.add_child(xl)
			var xb := _hit(holder, Rect2(box.position + Vector2(box.size.x - 11 - 44, 11 - 44), Vector2(88, 88)), func() -> void: _tap_slot(idx))
			xb.name = "Remove"


func _refresh_summary() -> void:
	var power := 0
	for id: Variant in _slots:
		if str(id) != "":
			power += int(Game.hero_power(str(id)))
	if _power_value >= 0 and power != _power_value:
		Kit.count_to(_power_label, _power_value, power, 0.45, true)
		Kit.pulse(_power_label, 1.06)
	else:
		_power_label.text = Kit.format_full(power)
	_power_value = power
	# The band: faction counts and their bonus, then the next stage's counter hint.
	var lines: Array[String] = ["FACTIONS"]
	var counts := _faction_counts(_slots)
	var best := ""
	var parts: Array[String] = []
	for f: String in Kit.FACTIONS:
		var n := int(counts.get(f, 0))
		parts.append("%s %d" % [str(FACTION_SHORT.get(f, f)), n])
		if n > 0 and (best == "" or n > int(counts.get(best, 0))):
			best = f
	lines.append(" · ".join(parts))
	var bp := BattleSim.faction_bonus_bp(int(counts.get(best, 0))) if best != "" else 0
	if bp > 0:
		lines.append("%s +%d%% HP & ATK" % [str(Kit.FACTION_NAMES.get(best, best)).to_upper(), bp / 100])
	else:
		lines.append("3/4/5 ALIKE: +%d/%d/%d%%" % [BattleSim.faction_bonus_bp(3) / 100, BattleSim.faction_bonus_bp(4) / 100, BattleSim.faction_bonus_bp(5) / 100])
	lines.append("")
	var st := Game.current_stage()
	if st.is_empty():
		lines.append("EVERY STAGE IS CLEARED. REPLAY STAGES FROM THE CAMPAIGN MAP.")
	else:
		var enemy_counts := {}
		for e: Dictionary in st.get("enemies", []):
			var f := str(Game.hero_def(str(e.hero_id)).get("faction", ""))
			enemy_counts[f] = int(enemy_counts.get(f, 0)) + 1
		lines.append("NEXT %s" % str(st.id))
		var ep: Array[String] = []
		for f: String in Kit.FACTIONS:
			if enemy_counts.has(f):
				ep.append("%s x%d" % [str(FACTION_SHORT.get(f, f)), int(enemy_counts[f])])
		lines.append("ENEMY " + " ".join(ep))
		var mine := _faction_counts(_slots)
		var fielded := 0
		var shown := {}
		var cp: Array[String] = []
		for ef: String in Kit.FACTIONS:
			if not enemy_counts.has(ef):
				continue
			for f: String in Kit.FACTIONS:
				if str(BattleSim.BEATS.get(f, "")) == ef and not shown.has(f):
					shown[f] = true
					cp.append(str(FACTION_SHORT.get(f, f)))
					fielded += int(mine.get(f, 0))
		lines.append("COUNTER %s +%d%%" % [" ".join(cp), BattleSim.ADVANTAGE_BP / 100])
		lines.append("%d IN TEAM" % fielded)
	_data_l.text = "\n".join(lines)
	# The band print follows the lead (the first hero in the team).
	var lead := ""
	for id: Variant in _slots:
		if str(id) != "" and lead == "":
			lead = str(id)
	if lead == "":
		lead = "noctaire"
	var key := HeroArt.art_key(lead, Kit.hero_look(lead))
	if key != _band_lead:
		_band_lead = key
		if _band_print and is_instance_valid(_band_print):
			_band_print.queue_free()
		var ph := _poster.size.y
		_band_print = PK.halftone_print(lead, Kit.hero_look(lead), Vector2(BAND, ph * 0.46), 6.0, PK.PRINT, 1.2)
		_band_print.position = Vector2(0, ph * 0.54)
		_poster.add_child(_band_print)
		_poster.move_child(_band_print, 1)


func _refresh_bench() -> void:
	if _bench == null:
		return
	var owned := Game.owned_heroes()
	var free_n := 0
	for hd: Dictionary in owned:
		if not _slots.has(str(hd.id)):
			free_n += 1
	# Faction tabs: ALL and the three factions, printed, the chosen one signal.
	for c in _filter_row.get_children():
		_filter_row.remove_child(c)
		c.queue_free()
	PK.at(_filter_row, PK.t("BENCH  %02d" % free_n, 13, INK, "mono_bold"), Vector2(0, 4))
	var opts := ["ALL"]
	for f: String in Kit.FACTIONS:
		opts.append(str(FACTION_SHORT.get(f, f)))
	for i in opts.size():
		var on := i == _filter_idx
		var x := 140.0 + i * 60.0
		var l := PK.t(str(opts[i]), 13, SIG if on else INK, "mono_bold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(60, 18)
		PK.at(_filter_row, l, Vector2(x, 4))
		if on:
			PK.rect(_filter_row, Rect2(x + 16, 26, 28, 3), SIG)
		var idx := i
		var b := _hit(_filter_row, Rect2(x, -48, 60, 88), func() -> void:
			_filter_idx = idx
			# Deferred: the refresh reprints these tabs, this one included.
			_refresh_bench.call_deferred())
		b.name = "Faction_%d" % i
	var in_team := PK.t("%02d IN TEAM" % (owned.size() - free_n), 11, Color(INK, 0.55), "mono")
	in_team.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	in_team.size = Vector2(130, 16)
	PK.at(_filter_row, in_team, Vector2(_filter_row.size.x - 130, 6))
	# Only the heroes not placed, strongest first.
	var ids: Array[String] = []
	var of_faction := 0
	for hd: Dictionary in owned:
		var id := str(hd.id)
		var fac := str(Game.hero_def(id).get("faction", ""))
		if _filter_idx > 0 and fac != Kit.FACTIONS[_filter_idx - 1]:
			continue
		of_faction += 1
		if _slots.has(id):
			continue
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa := int(Game.hero_power(a))
		var pb := int(Game.hero_power(b))
		return pa > pb if pa != pb else a < b)
	var keep := _page_scroll.scroll_vertical
	_lay_bench(ids)
	_refresh_bench_note(ids.is_empty(), of_faction)
	# The page ends under the last row of cards (or the note).
	var rows := ceili(float(ids.size()) / BENCH_COLS)
	var grid_h := rows * (_card_h + BENCH_VSEP) if rows > 0 else 190.0
	_bench.size.y = grid_h
	_page.custom_minimum_size = Vector2(size.x, _bench.position.y + grid_h + 40.0)
	_restore_scroll.call_deferred(keep)


## Places the bench cards for `ids` (in order): cards that left fold away, new ones drop in, the
## rest slide to their new place. The first lay-out (and reduce motion) just puts them there.
func _lay_bench(ids: Array[String]) -> void:
	var animate := _bench_laid and Kit.motion_ok() and is_visible_in_tree()
	_bench_laid = true
	for id: String in _cards.keys():
		var gone := not ids.has(id)
		var stale := not gone and str(_card_sigs.get(id, "")) != _card_sig(id)
		if not gone and not stale:
			continue
		var old := _cards[id] as Control
		_cards.erase(id)
		_card_sigs.erase(id)
		if gone and animate:
			_fold_away(old)
		else:
			old.queue_free()
	var i := 0
	var fresh := 0
	for id in ids:
		var at := Vector2((i % BENCH_COLS) * (_card_w + BENCH_HSEP), (i / BENCH_COLS) * (_card_h + BENCH_VSEP))
		i += 1
		var card := _cards.get(id) as Control
		if card == null:
			card = _make_card(id)
			card.position = at
			_bench.add_child(card)
			_cards[id] = card
			_card_sigs[id] = _card_sig(id)
			if animate:
				_drop_in(card, 0.06 + 0.03 * fresh)
				fresh += 1
			continue
		var tw: Variant = card.get_meta("move_tw") if card.has_meta("move_tw") else null
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		if card.position.distance_to(at) < 0.5:
			card.position = at
		elif animate:
			var mv := card.create_tween()
			mv.tween_property(card, "position", at, REFLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			card.set_meta("move_tw", mv)
		else:
			card.position = at


func _make_card(id: String) -> Control:
	var o := {"size": _card_w, "ratio": 1.42, "compact": _card_w < 170.0, "owned": true,
		"on_pressed": func() -> void: _tap_hero(id)}
	var card := PosterCard.new()
	card.setup(id, o)
	card.size = Vector2(_card_w, _card_h)
	card.pivot_offset = card.size * 0.5
	return card


## What a bench card shows (level, stars, gear, the look she wears): a change rebuilds it.
func _card_sig(id: String) -> String:
	return JSON.stringify(Game.hero(id)) + "|" + HeroArt.art_key(id, Kit.hero_look(id))


## A card leaving the bench (placed in the team, or filtered out) folds away where it stood.
func _fold_away(card: Control) -> void:
	card.mouse_filter = MOUSE_FILTER_IGNORE
	if card is BaseButton:
		(card as BaseButton).disabled = true
	card.pivot_offset = card.size * 0.5
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2(0.86, 0.86), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(card.queue_free)


## A card coming back to the bench (taken out of the team) drops into its place.
func _drop_in(card: Control, delay: float) -> void:
	card.modulate.a = 0.0
	card.scale = Vector2(0.92, 0.92)
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The empty bench: a printed note in a dashed box (everyone is in the team, or none of this
## faction is free) with a link to Summon.
func _refresh_bench_note(empty: bool, of_faction: int) -> void:
	if _bench_note and is_instance_valid(_bench_note):
		_bench_note.queue_free()
	_bench_note = null
	if not empty:
		return
	var fac := "" if _filter_idx == 0 else str(Kit.FACTION_NAMES.get(Kit.FACTIONS[_filter_idx - 1], "")).to_upper()
	var head := "EVERYONE IS IN THE TEAM"
	var sub := "EVERY HERO YOU OWN IS PLACED. TAKE ONE OUT AND SHE COMES BACK HERE."
	if of_faction == 0:
		head = "NO %sHEROES YET" % ("" if fac == "" else fac + " ")
		sub = "SUMMON TO FIND %sHEROES." % ("NEW " if fac == "" else fac + " ")
	elif fac != "":
		head = "EVERY %s IS IN THE TEAM" % fac
		sub = "NO %s HEROES ARE WAITING ON THE BENCH." % fac
	var w := _bench.size.x
	var note := Control.new()
	note.name = "BenchEmpty"
	note.mouse_filter = MOUSE_FILTER_IGNORE
	note.size = Vector2(w, 168)
	_bench.add_child(note)
	_bench_note = note
	var dash := Dashed.new()
	dash.color = Color(INK, 0.4)
	dash.size = note.size
	note.add_child(dash)
	PK.at(note, PK.t("BENCH // EMPTY", 11, SIG, "mono_bold"), Vector2(18, 16))
	var big := PK.t(head, 44, INK, "compressed")
	big.size = Vector2(w - 36, 52)
	big.clip_text = true
	PK.at(note, big, Vector2(16, 34))
	var sl := PK.t(sub, 11, Color(INK, 0.6), "mono")
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.size = Vector2(w - 36 - 190, 0)
	sl.custom_minimum_size.x = w - 36 - 190
	PK.at(note, sl, Vector2(18, 98))
	# Summon, as a printed link in signal (an 88 px target).
	var link := PK.t("SUMMON  →", 15, SIG, "mono_bold")
	link.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	link.size = Vector2(160, 20)
	PK.at(note, link, Vector2(w - 18 - 160, 118))
	PK.rect(note, Rect2(w - 18 - 104, 141, 104, 2), SIG)
	var b := _hit(note, Rect2(w - 18 - 190, 84, 190, 88), func() -> void: UI.go("summon"))
	b.name = "BenchSummon"
	if Kit.motion_ok() and is_visible_in_tree():
		note.modulate.a = 0.0
		note.create_tween().tween_property(note, "modulate:a", 1.0, 0.25).set_delay(0.12)


func _debug_tap(id: String) -> void:
	await get_tree().create_timer(0.9).timeout
	if is_inside_tree():
		_tap_hero(id)


func _scroll_later(y: int) -> void:
	for i in 4:
		await get_tree().process_frame
	_restore_scroll(y)


func _restore_scroll(y: int) -> void:
	if is_instance_valid(_page_scroll):
		_page_scroll.scroll_vertical = y


func _hit(parent: Control, r: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"BareButton"
	b.focus_mode = FOCUS_NONE
	b.mouse_filter = MOUSE_FILTER_PASS
	b.position = r.position
	b.size = r.size
	parent.add_child(b)
	Kit._connect_pressed(b, cb)
	return b


# ------------------------------------------------------------------ editing

func _tap_slot(i: int) -> void:
	var id := str(_slots[i])
	if id != "":
		_slots[i] = ""
		_selected = i
		_commit()
		return
	_selected = -1 if _selected == i else i
	_refresh_slots.call_deferred()


func _tap_hero(id: String) -> void:
	var at := _slots.find(id)
	if at >= 0:
		if _selected >= 0:
			_slots[at] = ""
			_slots[_selected] = id
			_selected = -1
		else:
			_slots[at] = ""
		_commit()
		return
	var target := _selected
	if target < 0 or str(_slots[target]) != "":
		target = _best_free_slot(id)
	if target < 0:
		UI.toast("The team is full. Tap a hero in the team to take them out.")
		for h in _slot_holders:
			Kit.shake(h, 6)
		return
	var from := Rect2()
	var card := _cards.get(id) as Control
	if card and is_instance_valid(card) and card.is_visible_in_tree():
		from = card.get_global_rect()
	_slots[target] = id
	_selected = -1
	_commit()
	if target < _slot_holders.size():
		_pop_slot.call_deferred(target)
		if from.size.x > 0.0:
			_fly_to_slot.call_deferred(id, from, target)


func _pop_slot(i: int) -> void:
	if i < _slot_holders.size() and is_instance_valid(_slot_holders[i]):
		Kit.pop_in(_slot_holders[i], 0.0, 0.28)


## Her art lifts off the bench card (screen rect `from`) and flies up into position `i`'s box as
## the position pops in. Nothing when motion is off or neither end is on screen.
func _fly_to_slot(id: String, from: Rect2, i: int) -> void:
	if not Kit.motion_ok() or i >= _slot_holders.size() or not is_instance_valid(_slot_holders[i]):
		return
	var holder := _slot_holders[i]
	var box := _slot_boxes[i]
	var xf := holder.get_global_transform()
	var to := Rect2(xf * box.position, box.size * xf.get_scale())
	var vp := get_viewport_rect()
	if not vp.intersects(from) and not vp.intersects(to):
		return
	var ghost := TextureRect.new()
	ghost.name = "FlyArt"
	ghost.mouse_filter = MOUSE_FILTER_IGNORE
	ghost.texture = Kit.art_crop(id, box.size.x / maxf(box.size.y, 1.0), 1.0, Kit.hero_look(id))
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ghost.top_level = true
	ghost.z_index = 20
	ghost.position = from.position
	ghost.size = from.size
	add_child(ghost)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "position", to.position, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ghost, "size", to.size, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.1).set_delay(0.26)
	tw.chain().tween_callback(ghost.queue_free)


## Front for guardians and strikers, back for everyone else, else any free slot.
func _best_free_slot(id: String) -> int:
	var role := str(Game.hero_def(id).get("role", ""))
	var order: Array = SLOT_ORDER_FRONT if FRONT_ROLES.has(role) else SLOT_ORDER_BACK
	for i in order:
		if str(_slots[i]) == "":
			return i
	return -1


func _commit() -> void:
	if _has_hero(_slots):
		_warn.visible = false
		_hint.visible = true
		var r := Game.set_formation(_slots.duplicate())
		if not bool(r.get("ok", false)):
			UI.toast(str(r.get("error", "Couldn't save the team")), "bad")
		# Game.changed refreshes everything.
	else:
		_warn.text = "PLACE AT LEAST ONE HERO. YOUR LAST SAVED TEAM IS KEPT UNTIL THEN."
		_warn.visible = true
		_hint.visible = false
		_refresh.call_deferred()


func _on_auto() -> void:
	Game.auto_formation()
	_selected = -1
	_slots = Game.formation()
	_warn.visible = false
	_hint.visible = true
	_refresh()
	UI.sfx("reward")
	UI.toast("Strongest team placed and equipped", "good")
	for h in _slot_holders:
		Kit.pop_in(h, randf() * 0.12, 0.3)


static func _has_hero(slots: Array) -> bool:
	for s: Variant in slots:
		if str(s) != "":
			return true
	return false


func _faction_counts(slots: Array) -> Dictionary:
	var counts := {}
	for s: Variant in slots:
		var id := str(s)
		if id == "":
			continue
		var f := str(Game.hero_def(id).get("faction", ""))
		counts[f] = int(counts.get(f, 0)) + 1
	return counts


## A dashed hairline box (an empty position).
class Dashed:
	extends Control
	var color := Color(0.06, 0.07, 0.08, 0.45)
	var dash := 8.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO]
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var dl := a.distance_to(b)
			var d := (b - a) / maxf(dl, 0.001)
			var t := 0.0
			while t < dl:
				draw_line(a + d * t, a + d * minf(t + dash, dl), color, 1.2)
				t += dash * 2.0
