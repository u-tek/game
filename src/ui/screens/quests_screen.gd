extends Control
## Screen "quests" (top-bar Quests button), style v4 "Signal" in the approved poster look
## (docs/dev/ui-style-v4.md): today's daily quests as a printed mission sheet. The dark band down
## the left carries the Lobby hero as a red halftone print and "DAILY ORDERS" set huge down the
## poster. Top right, the sheet's title block: sheet number, date, how many orders are done and the
## reset timer with a status light; down the right edge, the tab index (DAILY). Under it a small
## printed mission map (contours of the day's terrain, the river in signal) with one circle per
## order along a route: signal when ready, ink with a tick when claimed, a progress arc otherwise.
## Then the DAILY BONUS line (the one milestone track: "complete N quests", its reward and a CLAIM
## stamp when reached) and the numbered orders: title, tick marks for progress, rewards and an
## action at the right: a CLAIM stamp (ready), GO (jumps to where it is done), DONE (claimed) or
## "N LEFT". Ready orders sort to the top. With two or more ready, a "Claim All" pass is stuck on
## at the bottom (one reward popup); the bonus count sits beside it on a stamped silver disc.

const Poster := preload("res://src/ui/v4/survey/poster.gd")
const TerrainGen := preload("res://src/ui/v4/survey/terrain_gen.gd")
const HUD := preload("res://src/ui/components/hud.gd")
const CONTOURS := preload("res://src/ui/v4/survey/print_contours.gdshader")

## Where a quest is done, by the counter that drives it.
const GO_TO := {
	"idle_claims": "home", "quick_claims": "home", "battles_won": "campaign",
	"summons": "summon", "level_ups": "heroes",
}
const ICONS := {
	"idle_claims": "sanctum", "quick_claims": "speed", "battles_won": "sword", "summons": "summon",
	"level_ups": "upgrade", "daily_quests_done": "crown",
}
const W := 720.0
const BAND_W := 132.0
const RULE_W := 48.0
const ROW_H := 86.0
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL

var _ready_count := 0
var _root: Control
var _pr := Rect2()
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title_fs := 30
var _row_h := ROW_H
var _reset_label: Label
var _done_label: Label
var _map: _MissionMap
var _bonus_line: Control
var _bottom: Control
var _tick := 0.0
var _sig := ""


func setup(_params: Dictionary) -> void:
	UI.set_full_bleed(true)
	Poster.matte(self)
	_root = Control.new()
	_root.name = "Sheet"
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_root)
	_build()
	Game.changed.connect(_refresh)
	_refresh()


## The screen's own entrance (UI calls it instead of the generic stagger).
func intro() -> void:
	pass


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _lobby_hero() -> String:
	var want: Variant = Game.setting("lobby_hero")
	if want is String and want != "" and Game.owns(want):
		return want
	for id: String in Game.formation():
		if id != "" and HeroArt.has_art(id):
			return id
	return "noctaire"


func _build() -> void:
	var vh := get_viewport_rect().size.y
	var top := UI.content_top()
	var bottom := UI.content_bottom()
	_pr = Rect2(18, top + 12, W - 36, vh - bottom - 58 - (top + 12))
	var p := Poster.poster(_root, _pr)
	var pw := _pr.size.x
	var ph := _pr.size.y
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	var doy := int(Time.get_datetime_dict_from_system().get("day", 1)) + 31 * (int(Time.get_datetime_dict_from_system().get("month", 1)) - 1)

	# ---- The dark band: the Lobby hero as a red halftone print, micro type, the giant title.
	Poster.rect(p, Rect2(0, 0, BAND_W, ph), Poster.BAND)
	Poster.halftone_print(p, _lobby_hero(), Rect2(0, ph * 0.36, BAND_W, ph * 0.64), Color(1.0, 0.36, 0.16, 0.95), 6.5)
	Poster.at(p, Poster.t("HH", 34, PAPER, "wide_black"), Vector2(18, 16))
	Poster.at(p, Poster.t("™", 12, PAPER, "mono"), Vector2(82, 18))
	Poster.vlabel(p, "©2026 HH, MISSION SHEET. ALL RIGHTS RESERVED.", Vector2(42, 96), 10, Color(PAPER, 0.8))
	Poster.at(p, Poster.t("No.\n%03d" % doy, 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3))
	Poster.at(p, Poster.t(Poster.date_short(), 12, Color(PAPER, 0.85)), Vector2(70, ph * 0.3 + 40))
	Poster.giant_side(p, "Daily Orders", 150, 150.0, 104.0, 0.0, BAND_W, true)

	# ---- The title block (top right).
	var x0 := BAND_W + 16.0
	var rx := pw - RULE_W
	var tw := rx - 12 - x0
	var tb := Control.new()
	tb.mouse_filter = MOUSE_FILTER_IGNORE
	tb.position = Vector2(x0, 16)
	p.add_child(tb)
	Poster.at(tb, Poster.t("MISSION SHEET No.%03d" % doy, 12, INK), Vector2(0, 0))
	var dl := Poster.t(Poster.date_long(), 12, INK)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size = Vector2(tw, 16)
	Poster.at(tb, dl, Vector2(0, 0))
	Poster.hline(tb, 0, 20, tw, Color(INK, 0.7))
	Poster.at(tb, Poster.t("DAILY ORDERS", 28, INK, "wide_black"), Vector2(-2, 24))
	_done_label = Poster.t("", 22, INK, "wide_black")
	_done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_done_label.size = Vector2(tw, 26)
	Poster.at(tb, _done_label, Vector2(0, 30))
	var dc := Poster.t("CLAIMED", 9, Color(INK, 0.7), "mono_bold")
	dc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dc.size = Vector2(tw, 12)
	Poster.at(tb, dc, Vector2(0, 58))
	var led := HUD.Led.new()
	led.size = Vector2(14, 14)
	led.position = Vector2(0, 64)
	led.mode = "breathe"
	tb.add_child(led)
	Poster.at(tb, Poster.t("RESETS IN", 11, Color(INK, 0.75), "mono"), Vector2(20, 62))
	_reset_label = Poster.t("", 11, INK, "mono_bold")
	_reset_label.name = "ResetsIn"
	Poster.at(tb, _reset_label, Vector2(96, 62))
	Poster.at(tb, Poster.t("ORDERS RESET DAILY  ·  CLAIM BEFORE THE BELL", 10, Color(INK, 0.7), "mono"), Vector2(0, 80))

	# ---- The tab index down the right edge.
	Poster.vline(p, rx, 0, ph, Color(INK, 0.55))
	Poster.vlabel(p, "©2026 ·", Vector2(rx + 34, 12), 12, INK)
	Poster.side_menu(p, rx, 120.0, 96.0, [{"text": "DAILY", "name": "Daily", "active": true}])

	# ---- The mission map.
	# The day's terrain printed as contours under the map's marks (a new sheet every day).
	var map_r := Rect2(x0, 110, tw, clampf(ph * 0.2, 150.0, 210.0))
	var terrain := TerrainGen.new(day % 97, "fallen", 10)
	var cr := ColorRect.new()
	cr.mouse_filter = MOUSE_FILTER_IGNORE
	cr.position = map_r.position
	cr.size = map_r.size
	var m := ShaderMaterial.new()
	m.shader = CONTOURS
	m.set_shader_parameter("height_tex", terrain.height_texture())
	m.set_shader_parameter("river_tex", terrain.river_texture())
	cr.material = m
	p.add_child(cr)
	_map = _MissionMap.new()
	_map.name = "MissionMap"
	_map.position = map_r.position
	_map.size = map_r.size
	p.add_child(_map)
	var pts := PackedVector2Array()
	for k: int in [0, 2, 5, 4, 7, 9]:
		var sp: Vector2 = terrain.stages[k]
		pts.append(Vector2(sp.x / TerrainGen.W + 0.5, sp.y / TerrainGen.D + 0.5))
	_map.points = pts

	# ---- The bonus line, the orders, the bottom strip.
	var ly := _map.position.y + _map.size.y + 10.0
	_bonus_line = Control.new()
	_bonus_line.name = "BonusPanel"
	_bonus_line.mouse_filter = MOUSE_FILTER_IGNORE
	_bonus_line.position = Vector2(x0, ly)
	_bonus_line.size = Vector2(tw, 62)
	p.add_child(_bonus_line)
	_list = Kit.vbox(0)
	_list.mouse_filter = MOUSE_FILTER_PASS
	_scroll = Kit.scroll(_list)
	_scroll.position = Vector2(x0, ly + 66)
	_scroll.size = Vector2(tw, maxf(ph - 182.0 - (ly + 66), 120.0))
	p.add_child(_scroll)
	_bottom = Control.new()
	_bottom.name = "Bottom"
	_bottom.mouse_filter = MOUSE_FILTER_IGNORE
	_bottom.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_root.add_child(_bottom)

	# ---- Under the poster: the date and the hero's signature.
	var fy := _pr.end.y + 12.0
	Poster.at(_root, Poster.t(Poster.date_long(), 22, INK, "regular"), Vector2(20, fy + 8))
	var sig := Poster.t(str(Game.hero_def(_lobby_hero()).get("name", "")), 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	Poster.at(_root, sig, Vector2(W - 24 - 300, fy - 6))
	var swash := Poster.rect(_root, Rect2(W - 230, fy + 38, 200, 2), INK)
	swash.rotation = -0.05
	Poster.grain(_root)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_reset()
		# Past midnight the day's orders turn over: reprint the sheet (unchanged orders cost nothing).
		_refresh()


func _update_reset() -> void:
	if _reset_label:
		_reset_label.text = _hm(Game.ms_until_reset()).to_upper()


## "5h 12m" (or "12m" under an hour).
static func _hm(ms: int) -> String:
	var m := maxi(0, ms) / 60000
	if m < 60:
		return "%dm" % maxi(1, m)
	return "%dh %02dm" % [m / 60, m % 60]


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	_update_reset()
	var qs := Game.quests()
	var sig := JSON.stringify(qs)
	if sig == _sig:
		return
	_sig = sig
	var done := 0
	var ready: Array[Dictionary] = []
	var bonus: Dictionary = {}
	var orders: Array[Dictionary] = []
	for q in qs:
		if str(q.get("counter", "")) == "daily_quests_done":
			bonus = q
		else:
			orders.append(q)
		if bool(q.claimed):
			done += 1
		elif bool(q.get("ready", int(q.progress) >= int(q.goal))):
			ready.append(q)
	_ready_count = ready.size()
	_done_label.text = "%02d/%02d" % [done, qs.size()]
	_map.quests = orders
	_map.bonus = bonus
	_map.queue_redraw()
	_build_bonus(bonus, done, qs.size())

	var sorted := orders.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb if ra != rb else orders.find(a) < orders.find(b))
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	# One title size for the whole sheet: the size the longest title fits at. Rows share the list's
	# height when they can, so the last one isn't cut in half.
	var tw := _scroll.size.x - 4.0 - 52.0 - 120.0
	var cf := Kit.font("compressed")
	_title_fs = 30
	for q: Dictionary in sorted:
		while _title_fs > 18 and cf.get_string_size(str(q.title).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, _title_fs).x > tw:
			_title_fs -= 1
	_row_h = clampf(floorf(_scroll.size.y / maxf(float(sorted.size()), 1.0)), 72.0, ROW_H) if not sorted.is_empty() else ROW_H
	for q: Dictionary in sorted:
		_list.add_child(_quest_row(q, orders.find(q) + 1))
	if qs.is_empty():
		_list.add_child(Poster.t("NO ORDERS TODAY.", 14, Color(INK, 0.6)))
	_restore.call_deferred(keep)
	_build_bottom(ready, bonus)
	SignalKit.relight(_root)


func _restore(y: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


## 0 ready, 1 in progress, 2 claimed.
static func _rank(q: Dictionary) -> int:
	if bool(q.claimed):
		return 2
	return 0 if int(q.progress) >= int(q.goal) else 1


## The one milestone track: "complete N quests", its reward and its CLAIM stamp when reached.
func _build_bonus(bonus: Dictionary, done: int, total: int) -> void:
	for c in _bonus_line.get_children():
		_bonus_line.remove_child(c)
		c.queue_free()
	var bw := _bonus_line.size.x
	Poster.hline(_bonus_line, 0, 0, bw, INK, 1.5)
	Poster.hline(_bonus_line, 0, 61, bw, Color(INK, 0.4))
	if bonus.is_empty():
		# No bonus quest in the data: a plain claimed count.
		Poster.at(_bonus_line, Poster.t("DAILY PROGRESS", 10, Color(INK, 0.7)), Vector2(0, 8))
		Poster.at(_bonus_line, Poster.t("%d / %d CLAIMED" % [done, total], 26, INK, "compressed"), Vector2(0, 22))
		return
	var goal := int(bonus.goal)
	var have := mini(int(bonus.progress), goal)
	var b_ready := not bool(bonus.claimed) and int(bonus.progress) >= goal
	Poster.at(_bonus_line, Poster.t("DAILY BONUS  ·  COMPLETE %d QUESTS" % goal, 10, Color(INK, 0.75)), Vector2(0, 8))
	var big := Poster.t("CLAIMED" if bool(bonus.claimed) else "%d / %d" % [have, goal], 28, SIG if b_ready else INK, "compressed")
	Poster.at(_bonus_line, big, Vector2(0, 22))
	var ticks := _Ticks.new()
	ticks.goal = goal
	ticks.have = have
	ticks.position = Vector2(big.get_minimum_size().x + 14, 36)
	ticks.size = Vector2(goal * 14, 12)
	_bonus_line.add_child(ticks)
	var rl := Poster.reward_lines(bonus.get("reward", {}), 150, 11, INK, 1)
	if bool(bonus.claimed):
		rl.modulate.a = 0.5
	Poster.at(_bonus_line, rl, Vector2(bw - 270, 12))
	if b_ready:
		var bid := str(bonus.id)
		var cb := _claim_stamp(_bonus_line, Vector2(bw - 104, 0), func() -> void: _claim(bid, null), "ClaimBonus")
		if _ready_count == 1:
			Guide.mark(cb, Guide.step() == "quests", 0)


## The bottom strip: the bonus count on a stamped silver disc, and the Claim All pass (two or
## more ready) or the sheet's barcode and serial.
func _build_bottom(ready: Array[Dictionary], bonus: Dictionary) -> void:
	for c in _bottom.get_children():
		_bottom.remove_child(c)
		c.queue_free()
	var pp := _pr.position
	var pw := _pr.size.x
	var ph := _pr.size.y
	var val := "--"
	if not bonus.is_empty():
		val = "OK" if bool(bonus.claimed) else "%d/%d" % [mini(int(bonus.progress), int(bonus.goal)), int(bonus.goal)]
	Poster.stamp_disc(_bottom, "DAILY BONUS · ORDERS DONE · ", val, pp + Vector2(BAND_W + 22, ph - 152), 112.0, -0.12)
	if ready.size() >= 2:
		var total := {}
		for q: Dictionary in ready:
			_merge(total, q.get("reward", {}))
		var gems := int(total.get("gems", 0))
		# Claims are ink stamps (the button family): the pass is for battle.
		var st := SignalKit.stamp_button({"width": 330.0, "height": 124.0, "word": "CLAIM ALL",
			"kicker": "MISSION SHEET // %d ORDERS READY" % ready.size(),
			"sub": ("+%s GEMS  ·  %d REWARDS" % [Kit.format_num(gems), ready.size()]) if gems > 0 else "%d REWARDS" % ready.size(),
			"button_text": "Claim All (%d)" % ready.size()}, _claim_all)
		st.name = "ClaimAll"
		st.position = pp + Vector2(pw - 352, ph - 150)
		st.rotation = -0.03
		_bottom.add_child(st)
		# First-session guidance: collect finished quests.
		Guide.mark(st, Guide.step() == "quests", 0)
	else:
		var bc := SignalKit.barcode(Vector2(200, 44), INK, 4021)
		bc.position = pp + Vector2(pw - 290, ph - 120)
		_bottom.add_child(bc)
		Poster.at(_bottom, Poster.t("SHEET %s  ·  %d READY" % [Poster.date_short(), ready.size()], 10, INK, "mono"), pp + Vector2(pw - 290, ph - 70))


func _quest_row(q: Dictionary, number: int) -> Control:
	var claimed := bool(q.claimed)
	var ready := not claimed and int(q.progress) >= int(q.goal)
	var counter := str(q.get("counter", ""))
	var w := _scroll.size.x - 4.0
	var row := Control.new()
	row.name = "Quest_" + str(q.id)
	row.custom_minimum_size = Vector2(w, _row_h)
	row.mouse_filter = MOUSE_FILTER_PASS
	var ink := INK if not claimed else Color(INK, 0.45)
	Poster.hline(row, 0, _row_h - 1, w, Color(INK, 0.35))
	Poster.at(row, Poster.t("%02d" % number, 24, SIG if ready else ink, "wide_black"), Vector2(0, 8))
	var ic := Kit.icon(str(ICONS.get(counter, "quests")) if not claimed else "check", 22, ink)
	Poster.at(row, ic, Vector2(6, 46))
	var title := Poster.t(str(q.title).to_upper(), _title_fs, ink, "compressed")
	Poster.at(row, title, Vector2(52, 2))
	if claimed:
		Poster.hline(row, 52, 22, minf(title.get_minimum_size().x, w - 172), Color(INK, 0.6), 2.0)
	var p := mini(int(q.progress), int(q.goal))
	var ticks := _Ticks.new()
	ticks.goal = int(q.goal)
	ticks.have = p
	ticks.done = claimed
	ticks.position = Vector2(54, 48)
	ticks.size = Vector2(minf(int(q.goal), 10) * 14.0, 12)
	row.add_child(ticks)
	var pl := Poster.t("%d/%d" % [p, int(q.goal)], 12, ink, "mono_bold")
	Poster.at(row, pl, Vector2(54 + ticks.size.x + 6, 44))
	var rw := Kit.hbox(8)
	rw.mouse_filter = MOUSE_FILTER_IGNORE
	for e: Dictionary in Kit.reward_entries(q.get("reward", {})):
		if str(e.kind) != "currency":
			continue
		rw.add_child(Kit.currency_icon(str(e.id), 20))
		rw.add_child(Poster.t(Kit.format_num(int(e.amount)), 12, ink, "mono_bold"))
	if claimed:
		rw.modulate.a = 0.5
	Poster.at(row, rw, Vector2(54 + ticks.size.x + 50, 43))
	var qid := str(q.id)
	var ax := w - 108.0
	if claimed:
		Poster.rubber(row, "DONE", Vector2(ax + 14, 26), Color(INK, 0.6), 16, 0.06)
		var b := Poster.hit(row, Rect2(ax, 0, 108, _row_h), Callable(), "Done", "Done")
		b.disabled = true
		b.mouse_filter = MOUSE_FILTER_PASS
	elif ready:
		var b := _claim_stamp(row, Vector2(ax, 0), func() -> void: _claim(qid, row), "Claim")
		# A single finished quest: ring its Claim (Claim All takes over for two or more).
		if _ready_count == 1:
			Guide.mark(b, Guide.step() == "quests", 0)
	elif GO_TO.has(counter):
		var dest: String = GO_TO[counter]
		var box := PanelContainer.new()
		box.mouse_filter = MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = INK
		sb.set_border_width_all(1)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		box.add_theme_stylebox_override("panel", sb)
		box.add_child(Poster.t("GO  >", 15, INK, "mono_bold"))
		Poster.at(row, box, Vector2(ax + 18, 26))
		var b := Poster.hit(row, Rect2(ax, 0, 108, _row_h), func() -> void: UI.go(dest), "Go", "Go")
		b.mouse_filter = MOUSE_FILTER_PASS
	else:
		Poster.at(row, Poster.t("%d LEFT" % (int(q.goal) - p), 13, Color(INK, 0.6), "mono_bold"), Vector2(ax + 20, 34))
		var b := Poster.hit(row, Rect2(ax, 0, 108, _row_h), Callable(), "Left", "%d left" % (int(q.goal) - p))
		b.disabled = true
		b.mouse_filter = MOUSE_FILTER_PASS
	return row


## A CLAIM stamp inked solid in signal (owner: a filled claim reads as "not done yet") with paper
## type, a soft shadow, a slow pulse and a status light: the tap area is 108 x 86, and its Button
## carries the word "Claim" (tests, accessibility).
func _claim_stamp(parent: Control, pos: Vector2, on_pressed: Callable, node_name: String) -> Button:
	var st := PanelContainer.new()
	st.mouse_filter = MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = SIG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.shadow_color = Color(SIG.darkened(0.5), 0.4)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	st.add_theme_stylebox_override("panel", sb)
	st.add_child(Poster.t("CLAIM", 19, Color("f5f4f0"), "wide_black"))
	st.position = pos + Vector2(4, 22)
	st.rotation = -0.05
	parent.add_child(st)
	if Kit.motion_ok():
		st.pivot_offset = Vector2(48, 18)
		var tw := st.create_tween().set_loops()
		tw.tween_property(st, "scale", Vector2(1.06, 1.06), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(st, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var led := HUD.Led.new()
	led.size = Vector2(16, 16)
	led.position = pos + Vector2(88, 12)
	led.mode = "blink"
	parent.add_child(led)
	var b := Poster.hit(parent, Rect2(pos, Vector2(108, _row_h)), on_pressed, node_name, "Claim")
	b.mouse_filter = MOUSE_FILTER_PASS
	b.button_down.connect(func() -> void: st.modulate = Color(0.8, 0.8, 0.8))
	b.button_up.connect(func() -> void: st.modulate = Color.WHITE)
	return b


# ------------------------------------------------------------------ actions

func _claim(qid: String, from: Control) -> void:
	var r := Game.claim_quest(qid)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Can't claim yet")), "bad")
		if from and is_instance_valid(from):
			Kit.shake(from, 8)
		return
	var title := "Quest Complete"
	for q: Dictionary in Game.quests():
		if str(q.id) == qid:
			title = str(q.title)
	UI.show_reward(title, r.get("value", {}))


func _claim_all() -> void:
	var total := {}
	var n := 0
	# Claiming can make the "complete N quests" quest ready, so loop until nothing is left.
	for _pass in 3:
		for q: Dictionary in Game.quests():
			if bool(q.claimed) or int(q.progress) < int(q.goal):
				continue
			var r := Game.claim_quest(str(q.id))
			if bool(r.get("ok", false)):
				n += 1
				_merge(total, r.get("value", {}))
	if n == 0:
		UI.toast("Nothing to claim yet")
		return
	UI.show_reward("%d Quests Complete" % n if n > 1 else "Quest Complete", total)


static func _merge(into: Dictionary, reward: Dictionary) -> void:
	for k: Variant in reward:
		var v: Variant = reward[k]
		if v is int:
			into[k] = int(into.get(k, 0)) + int(v)
		elif v is Dictionary:
			var d: Dictionary = into.get(k, {})
			for kk: Variant in v:
				d[kk] = int(d.get(kk, 0)) + int(v[kk])
			into[k] = d
		elif v is Array:
			var a: Array = into.get(k, [])
			a.append_array(v)
			into[k] = a


# ------------------------------------------------------------------ printed pieces

## Progress as tick boxes (up to 10; more goals print a hairline bar).
class _Ticks:
	extends Control
	var goal := 1
	var have := 0
	var done := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := INK if not done else Color(INK, 0.45)
		if goal > 10:
			draw_rect(Rect2(0, size.y * 0.5 - 1, size.x, 2), Color(ink, 0.25))
			draw_rect(Rect2(0, size.y * 0.5 - 2, size.x * float(have) / goal, 4), SIG if not done else ink)
			return
		for i in goal:
			var r := Rect2(i * 14.0, 0, 10, 10)
			if i < have:
				draw_rect(r, SIG if (have >= goal and not done) else ink)
			else:
				draw_rect(r, ink, false, 1.0)


## The printed mission map: a frame with corner ticks, a north arrow and a scale bar, the route
## through the orders' circles (in data order) and the bonus as a double ring at its end.
class _MissionMap:
	extends Control
	var points := PackedVector2Array()
	var quests: Array = []
	var bonus: Dictionary = {}
	var _t := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var f := Kit.font("mono_bold")
		var fm := Kit.font("mono")
		draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.7), false, 1.0)
		for c: Vector2 in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			var dx := 10.0 if c.x == 0.0 else -10.0
			var dy := 10.0 if c.y == 0.0 else -10.0
			draw_line(c + Vector2(dx * 0.3, dy * 0.3), c + Vector2(dx * 1.6, dy * 0.3), INK, 1.5)
			draw_line(c + Vector2(dx * 0.3, dy * 0.3), c + Vector2(dx * 0.3, dy * 1.6), INK, 1.5)
		# North arrow and scale bar.
		var na := Vector2(size.x - 26, 30)
		draw_colored_polygon(PackedVector2Array([na + Vector2(0, -14), na + Vector2(6, 6), na + Vector2(0, 2), na + Vector2(-6, 6)]), INK)
		draw_string(f, na + Vector2(-4, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
		var sb := Vector2(12, size.y - 14)
		for i in 4:
			draw_rect(Rect2(sb + Vector2(i * 18, 0), Vector2(18, 4)), INK if i % 2 == 0 else PAPER)
		draw_rect(Rect2(sb, Vector2(72, 4)), INK, false, 1.0)
		draw_string(fm, sb + Vector2(80, 5), "0 - 2 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
		var n := mini(points.size(), quests.size() + (0 if bonus.is_empty() else 1))
		if n < 1:
			return
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2(points[i].x * size.x, points[i].y * size.y))
		# The route.
		for i in n - 1:
			_dashed(pts[i], pts[i + 1], Color(INK, 0.75), 1.3, 6.0, 4.0)
		for i in n:
			var c := pts[i]
			var is_bonus := i >= quests.size()
			var q: Dictionary = bonus if is_bonus else quests[i]
			var claimed := bool(q.get("claimed", false))
			var goal := maxi(int(q.get("goal", 1)), 1)
			var prog := mini(int(q.get("progress", 0)), goal)
			var ready := not claimed and prog >= goal
			var r := 13.0 if not is_bonus else 16.0
			if ready:
				var k := 0.5 + 0.5 * sin(_t * 3.4)
				draw_arc(c, r + 5.0 + 3.0 * k, 0.0, TAU, 40, Color(SIG, 0.7 - 0.4 * k), 1.2, true)
				draw_circle(c, r, SIG * 1.5)
			elif claimed:
				draw_circle(c, r, INK)
				draw_line(c + Vector2(-5, 0), c + Vector2(-1, 4), PAPER, 2.0, true)
				draw_line(c + Vector2(-1, 4), c + Vector2(6, -4), PAPER, 2.0, true)
			else:
				draw_circle(c, r, PAPER)
				draw_arc(c, r, 0.0, TAU, 32, INK, 1.3, true)
				if prog > 0:
					draw_arc(c, r + 4.0, -PI * 0.5, -PI * 0.5 + TAU * float(prog) / goal, 32, SIG, 2.4, true)
			if is_bonus:
				draw_arc(c, r + 9.0, 0.0, TAU, 40, Color(INK, 0.8), 1.0, true)
			var label := "B" if is_bonus else "%02d" % (i + 1)
			var lc := PAPER if (ready or claimed) else INK
			if not claimed:
				var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(f, c + Vector2(-lw * 0.5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, lc)
			else:
				draw_string(f, c + Vector2(r + 4, -r * 0.4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)

	func _dashed(a: Vector2, b: Vector2, c: Color, w: float, on: float, off: float) -> void:
		var len := a.distance_to(b)
		if len < 0.5:
			return
		var d := (b - a) / len
		var s := 0.0
		while s < len:
			draw_line(a + d * s, a + d * minf(s + on, len), c, w, true)
			s += on + off
