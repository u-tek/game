extends Control
## Screen "quests" (top-bar Quests button), style v2: today's daily quests on a light page.
## A dark header with the DAILY tab and the reset timer; a white progress panel (claimed out
## of total, with the "complete N quests" bonus as the milestone); then one white row per
## quest: a hex glyph (cyan when ready, grey when done), the goal, a cyan progress bar, the
## rewards and an action: Claim (ready, red dot), Go (jumps to where the quest is done) or a
## disabled Done. Ready quests sort to the top; "Claim All" collects every ready quest in one
## reward popup.

## Where a quest is done, by the counter that drives it.
const GO_TO := {
	"idle_claims": "home", "quick_claims": "home", "battles_won": "campaign",
	"summons": "summon", "level_ups": "heroes",
}
const ICONS := {
	"idle_claims": "sanctum", "quick_claims": "speed", "battles_won": "sword", "summons": "summon",
	"level_ups": "upgrade", "daily_quests_done": "crown",
}

var _ready_count := 0
var _list: VBoxContainer
var _scroll: ScrollContainer
var _reset_label: Label
var _done_label: Label
var _done_bar: ProgressBar
var _milestone: HBoxContainer
var _claim_all_slot: HBoxContainer
var _tick := 0.0
var _sig := ""


func setup(_params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _build() -> void:
	var head := Kit.hbox(12)
	head.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 10
	head.offset_bottom = 10 + Kit.BUTTON_H
	head.add_child(Kit.tab_strip([{"text": "Daily", "icon": "quests"}], 0, Callable(), 210.0))
	head.add_child(Kit.spacer(0, 0, true))
	var rt := Kit.hbox(8)
	rt.mouse_filter = MOUSE_FILTER_IGNORE
	rt.size_flags_vertical = SIZE_SHRINK_CENTER
	rt.add_child(Kit.icon("timer", 34, Kit.INK_DIM))
	var rv := Kit.vbox(-6)
	rv.mouse_filter = MOUSE_FILTER_IGNORE
	rv.add_child(Kit.label("RESETS IN", 16, Kit.INK_DIM, "cond_bold"))
	_reset_label = Kit.label("", 30, Kit.INK, "cond_bold")
	rv.add_child(_reset_label)
	rt.add_child(rv)
	head.add_child(rt)
	add_child(head)

	var page := Kit.page_bg("light")
	page.offset_top = 10 + Kit.BUTTON_H
	add_child(page)

	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_top = 10 + Kit.BUTTON_H + 16
	col.offset_left = 16
	col.offset_right = -16
	col.offset_bottom = -14
	add_child(col)

	# Progress panel: claimed / total with the bonus quest as the milestone.
	var prog := Kit.info_panel(14)
	var pv := Kit.vbox(8)
	prog.add_child(pv)
	var ph := Kit.hbox(10)
	ph.add_child(Kit.hex_badge("quests", 56, Kit.ACCENT, Color.WHITE))
	var pt := Kit.vbox(-4)
	pt.size_flags_horizontal = SIZE_EXPAND_FILL
	pt.alignment = BoxContainer.ALIGNMENT_CENTER
	pt.add_child(Kit.label("DAILY PROGRESS", 18, Kit.TEXT_DIM, "cond_bold"))
	_done_label = Kit.label("", 36, Kit.TEXT, "title")
	pt.add_child(_done_label)
	ph.add_child(pt)
	_milestone = Kit.hbox(6)
	_milestone.mouse_filter = MOUSE_FILTER_IGNORE
	ph.add_child(_milestone)
	pv.add_child(ph)
	_done_bar = Kit.progress_bar(0, 1, Kit.ACCENT, 16, "", true)
	pv.add_child(_done_bar)
	col.add_child(prog)

	_list = Kit.vbox(10)
	var m := Kit.margin(_list, 0, 0)
	m.add_theme_constant_override("margin_bottom", 16)
	_scroll = Kit.scroll(m)
	col.add_child(_scroll)

	_claim_all_slot = Kit.hbox(0)
	col.add_child(_claim_all_slot)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_reset()


func _update_reset() -> void:
	if _reset_label:
		_reset_label.text = _hm(Game.ms_until_reset())


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
	for q in qs:
		if str(q.get("counter", "")) == "daily_quests_done":
			bonus = q
		if bool(q.claimed):
			done += 1
		elif bool(q.get("ready", int(q.progress) >= int(q.goal))):
			ready.append(q)
	_ready_count = ready.size()
	Kit.set_progress(_done_bar, done, qs.size(), "", false)
	_done_label.text = "%d / %d CLAIMED" % [done, qs.size()]
	for c in _milestone.get_children():
		_milestone.remove_child(c)
		c.queue_free()
	if not bonus.is_empty():
		var bv := Kit.vbox(0)
		bv.mouse_filter = MOUSE_FILTER_IGNORE
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_child(Kit.label("BONUS AT %d" % int(bonus.goal), 16, Kit.TEXT_DIM, "cond_bold"))
		bv.add_child(Kit.label("%d / %d" % [mini(int(bonus.progress), int(bonus.goal)), int(bonus.goal)], 22, Kit.ACCENT_DEEP, "cond_bold"))
		_milestone.add_child(bv)
		var rl := Kit.hbox(6)
		rl.mouse_filter = MOUSE_FILTER_IGNORE
		rl.size_flags_vertical = SIZE_SHRINK_CENTER
		for e: Dictionary in Kit.reward_entries(bonus.get("reward", {})):
			rl.add_child(Kit.reward_tile(str(e.kind), str(e.id), int(e.amount), 64.0, false, true))
		if bool(bonus.claimed):
			rl.modulate.a = 0.45
		_milestone.add_child(rl)

	var sorted := qs.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb if ra != rb else qs.find(a) < qs.find(b))
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for q: Dictionary in sorted:
		_list.add_child(_quest_row(q))
	if qs.is_empty():
		_list.add_child(Kit.empty_state("No quests today.", "quests", true))
	_restore.call_deferred(keep)

	for c in _claim_all_slot.get_children():
		_claim_all_slot.remove_child(c)
		c.queue_free()
	if ready.size() >= 2:
		var b := Kit.primary_button("Claim All (%d)" % ready.size(), _claim_all, "gift")
		b.name = "ClaimAll"
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 96
		_claim_all_slot.add_child(b)
		# First-session guidance: collect finished quests.
		Guide.mark(b, Guide.step() == "quests", 0)


func _restore(y: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


## 0 ready, 1 in progress, 2 claimed.
static func _rank(q: Dictionary) -> int:
	if bool(q.claimed):
		return 2
	return 0 if int(q.progress) >= int(q.goal) else 1


func _quest_row(q: Dictionary) -> Control:
	var claimed := bool(q.claimed)
	var ready := not claimed and int(q.progress) >= int(q.goal)
	var counter := str(q.get("counter", ""))
	var card := Kit.info_panel(12)
	card.name = "Quest_" + str(q.id)
	var row := Kit.hbox(14)
	card.add_child(row)

	var hx_fill := Kit.ACCENT if ready else (Color("d9dee4") if claimed else Color("26282c"))
	var hx := Kit.hex_badge(str(ICONS.get(counter, "quests")) if not claimed else "check", 72, hx_fill, Kit.TEXT if claimed else Color.WHITE)
	if ready:
		hx.set("glow", Color(Kit.ACCENT, 0.45))
		hx.set("glow_size", 8.0)
	hx.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(hx)

	var mid := Kit.vbox(6)
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.mouse_filter = MOUSE_FILTER_IGNORE
	var t := Kit.label(str(q.title), 25, Kit.TEXT if not claimed else Kit.TEXT_DIM, "extrabold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(t)
	var p := mini(int(q.progress), int(q.goal))
	var bar := Kit.progress_bar(p, int(q.goal), Kit.ACCENT if not claimed else Color("9aa1aa"), 18, "%d / %d" % [p, int(q.goal)], true)
	mid.add_child(bar)
	var rw := Kit.hbox(12)
	rw.mouse_filter = MOUSE_FILTER_IGNORE
	for e: Dictionary in Kit.reward_entries(q.get("reward", {})):
		if str(e.kind) != "currency":
			continue
		var pair := Kit.hbox(4)
		pair.mouse_filter = MOUSE_FILTER_IGNORE
		pair.add_child(Kit.currency_icon(str(e.id), 30))
		pair.add_child(Kit.label(Kit.format_num(int(e.amount)), 22, Kit.TEXT if not claimed else Kit.TEXT_DIM, "cond_bold"))
		rw.add_child(pair)
	mid.add_child(rw)
	row.add_child(mid)

	var qid := str(q.id)
	var b: Button
	if claimed:
		b = Kit.light_button("Done", Callable(), "check")
		b.disabled = true
	elif ready:
		b = Kit.primary_button("Claim", func() -> void: _claim(qid, card))
		Kit.set_dot(b, true, 22, Vector2(6, 6))
		# A single finished quest: ring its Claim button (Claim All takes over for two or more).
		if _ready_count == 1:
			Guide.mark(b, Guide.step() == "quests", 0)
	elif GO_TO.has(counter):
		var dest: String = GO_TO[counter]
		b = Kit.light_button("Go", func() -> void: UI.go(dest), "arrow_right")
	else:
		b = Kit.light_button("%d left" % (int(q.goal) - p))
		b.disabled = true
	b.custom_minimum_size = Vector2(140, Kit.BUTTON_H)
	b.add_theme_font_size_override("font_size", 26)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(b)
	if claimed:
		card.modulate = Color(1, 1, 1, 0.72)
	return card


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
