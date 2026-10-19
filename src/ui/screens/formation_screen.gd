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
## HERO"). Down the right-hand rule FRONT and BACK as turned labels. Under the poster the bench:
## faction tabs, the owned heroes as small printed cards in a sideways strip (the ones in the team
## carry their position number), and the Battle pass (to the campaign).
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
## Room under the poster: bench header, strip and the pass beside it.
const BELOW := 256.0
const BENCH_W := 104.0
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
var _bench: HBoxContainer
var _bench_scroll: ScrollContainer
var _filter_row: Control
var _warn: Label
var _hint: Label
var _pass: PK.Pass
var _built := false


func setup(_params: Dictionary) -> void:
	_slots = Game.formation()
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
	var h := maxf(size.y, 820.0)
	PK.matte(self)
	PK.at(self, PK.t("HALO & HORN  ©2026", 12, INK, "mono_bold"), Vector2(ox + 20, 8))
	var pub := PK.t("FORMATION  ·  FIVE POSITIONS", 12, Color(INK, 0.7), "mono")
	pub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pub.size = Vector2(420, 16)
	PK.at(self, pub, Vector2(ox + w - 20 - 420, 9))

	var pr := Rect2(ox + 18, 30, w - 36, h - 30 - BELOW)
	_poster = PK.poster(self, pr)
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
	var usable := ph - top - 54.0
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
	_hint = PK.t("TAP A BENCH HERO TO ADD OR REMOVE THEM. TAP AN EMPTY POSITION FIRST TO CHOOSE WHERE.", 9, Color(INK, 0.6), "mono")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size = Vector2(cx1 - x0, 0)
	PK.at(p, _hint, Vector2(x0, ph - 40))
	_warn = PK.t("", 11, SIG, "mono_bold")
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.size = Vector2(cx1 - x0, 0)
	_warn.visible = false
	PK.at(p, _warn, Vector2(x0, ph - 44))

	# ---- The Auto-fill stamp on a silver disc, stuck on the band's foot.
	var disc := SignalKit.plate("silver", pr.position + Vector2(20, ph - 132), Vector2(112, 112), {"circle": true, "shadow": 0.5}, self)
	disc.rotation = -0.1
	disc.add_child(SignalKit.stamp("AUTO-FILL · STRONGEST FIVE · ", "AUTO", 112))
	_auto_btn = Button.new()
	_auto_btn.name = "AutoFill"
	_auto_btn.theme_type_variation = &"BareButton"
	_auto_btn.focus_mode = FOCUS_NONE
	_auto_btn.mouse_filter = MOUSE_FILTER_PASS
	_auto_btn.position = pr.position + Vector2(14, ph - 138)
	_auto_btn.size = Vector2(124, 124)
	add_child(_auto_btn)
	Kit.add_press_fx(_auto_btn, disc)
	Kit._connect_pressed(_auto_btn, _on_auto)

	# ---- Under the poster: the bench and the Battle pass.
	var by := pr.end.y
	_filter_row = Control.new()
	_filter_row.name = "BenchTabs"
	_filter_row.mouse_filter = MOUSE_FILTER_IGNORE
	_filter_row.position = Vector2(ox + 18, by + 12)
	_filter_row.size = Vector2(w - 36 - 320, 28)
	add_child(_filter_row)
	_bench = HBoxContainer.new()
	_bench.add_theme_constant_override("separation", 12)
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_top", 6)
	bm.add_theme_constant_override("margin_bottom", 6)
	bm.add_theme_constant_override("margin_left", 4)
	bm.add_theme_constant_override("margin_right", 12)
	bm.add_child(_bench)
	_bench_scroll = ScrollContainer.new()
	_bench_scroll.name = "Bench"
	_bench_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_bench_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bench_scroll.scroll_deadzone = 14
	_bench_scroll.follow_focus = false
	_bench_scroll.mouse_filter = MOUSE_FILTER_PASS
	_bench_scroll.add_child(bm)
	_bench_scroll.position = Vector2(ox + 14, by + 46)
	_bench_scroll.size = Vector2(w - 28 - 324, h - by - 46 - 6)
	add_child(_bench_scroll)
	_pass = PK.make_pass(300.0, "sword", false, false)
	_pass.hit.name = "Battle"
	Kit._connect_pressed(_pass.hit, func() -> void: UI.go("campaign"))
	_pass.position = Vector2(ox + w - 18 - 300, by + 40)
	_pass.rotation = -0.025
	add_child(_pass)
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
	# Faction tabs: ALL and the three factions, printed, the chosen one signal.
	for c in _filter_row.get_children():
		_filter_row.remove_child(c)
		c.queue_free()
	var owned := Game.owned_heroes()
	PK.at(_filter_row, PK.t("BENCH  %02d" % owned.size(), 13, INK, "mono_bold"), Vector2(0, 4))
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
	var keep := _bench_scroll.scroll_horizontal
	for c in _bench.get_children():
		_bench.remove_child(c)
		c.queue_free()
	var ids: Array[String] = []
	for hd: Dictionary in owned:
		var id := str(hd.id)
		var fac := str(Game.hero_def(id).get("faction", ""))
		if _filter_idx > 0 and fac != Kit.FACTIONS[_filter_idx - 1]:
			continue
		ids.append(id)
	# Strongest first, the ones in the team before the rest.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ta := _slots.has(a)
		var tb := _slots.has(b)
		if ta != tb:
			return ta
		var pa := int(Game.hero_power(a))
		var pb := int(Game.hero_power(b))
		return pa > pb if pa != pb else a < b)
	for id in ids:
		var at := _slots.find(id)
		var o := {"size": BENCH_W, "ratio": 1.42, "compact": true, "owned": true, "in_team": at >= 0,
			"on_pressed": func() -> void: _tap_hero(id)}
		if at >= 0:
			o["slot"] = at
		var card := PosterCard.new()
		card.setup(id, o)
		_bench.add_child(card)
	if ids.is_empty():
		var l2 := PK.t("NO HEROES OF THIS FACTION YET.", 12, Color(INK, 0.6), "mono_bold")
		l2.custom_minimum_size = Vector2(300, 140)
		l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bench.add_child(l2)
	_restore_bench_scroll.call_deferred(keep)


func _restore_bench_scroll(x: int) -> void:
	if is_instance_valid(_bench_scroll):
		_bench_scroll.scroll_horizontal = x


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
	_slots[target] = id
	_selected = -1
	_commit()
	if target < _slot_holders.size():
		_pop_slot.call_deferred(target)


func _pop_slot(i: int) -> void:
	if i < _slot_holders.size() and is_instance_valid(_slot_holders[i]):
		Kit.pop_in(_slot_holders[i], 0.0, 0.28)


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
