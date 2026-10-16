extends Control
## Screen "quests": today's daily quests. Each card shows an icon, the goal, a progress bar,
## its rewards and an action: Claim (ready), Go (jumps to where the quest is done) or a
## Claimed check. Ready quests sort to the top; "Claim all" collects every ready quest in one
## reward popup. A header counts completed quests and when they reset (local midnight).

## Where a quest is done, by the counter that drives it.
const GO_TO := {
	"idle_claims": "home", "quick_claims": "home", "battles_won": "campaign",
	"summons": "summon", "level_ups": "heroes",
}
const ICONS := {
	"idle_claims": "chest", "quick_claims": "speed", "battles_won": "sword", "summons": "summon",
	"level_ups": "arrow_up", "daily_quests_done": "crown",
}

var _ready_count := 0
var _list: VBoxContainer
var _scroll: ScrollContainer
var _reset_label: Label
var _done_label: Label
var _done_bar: ProgressBar
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
	var col := Kit.vbox(14)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_right = -22
	col.offset_top = 14
	col.offset_bottom = -12
	add_child(col)

	var head := Kit.panel("glass", 18)
	var hv := Kit.vbox(10)
	head.add_child(hv)
	var top := Kit.hbox(12)
	top.add_child(Kit.icon("quests", 64))
	var tv := Kit.vbox(0)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Kit.header("Daily Quests", 40))
	_reset_label = Kit.caption("", 22)
	tv.add_child(_reset_label)
	top.add_child(tv)
	hv.add_child(top)
	var prog := Kit.hbox(12)
	_done_bar = Kit.progress_bar(0, 1, Kit.GOLD, 26, "")
	prog.add_child(_done_bar)
	_done_label = Kit.label("", 24, Kit.GOLD_LIGHT, "black", 4)
	prog.add_child(_done_label)
	hv.add_child(prog)
	col.add_child(head)

	_list = Kit.vbox(14)
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
		_reset_label.text = "Resets in %s" % _hm(Game.ms_until_reset())


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
	for q in qs:
		if bool(q.claimed):
			done += 1
		elif bool(q.get("ready", int(q.progress) >= int(q.goal))):
			ready.append(q)
	_ready_count = ready.size()
	Kit.set_progress(_done_bar, done, qs.size(), "", false)
	_done_label.text = "%d / %d claimed" % [done, qs.size()]

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
		_list.add_child(_quest_card(q))
	if qs.is_empty():
		_list.add_child(Kit.empty_state("No quests today.", "quests"))
	_restore.call_deferred(keep)

	for c in _claim_all_slot.get_children():
		c.queue_free()
	if ready.size() >= 2:
		var b := Kit.primary_button("Claim all (%d)" % ready.size(), _claim_all, "gift")
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


func _quest_card(q: Dictionary) -> Control:
	var claimed := bool(q.claimed)
	var ready := not claimed and int(q.progress) >= int(q.goal)
	var counter := str(q.get("counter", ""))
	var card := Kit.card(16)
	if ready:
		card.add_theme_stylebox_override("panel", Kit.box(Color("3a2c5e"), Color("231a44"), Kit.GOLD, 16.0, 3, 16))
	var row := Kit.hbox(14)
	card.add_child(row)

	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(84, 84)
	disc.size_flags_vertical = SIZE_SHRINK_CENTER
	disc.mouse_filter = MOUSE_FILTER_IGNORE
	var acc := Kit.GOLD if ready else (Kit.GOOD if claimed else Kit.VIOLET)
	disc.add_theme_stylebox_override("panel", Kit.box(acc.darkened(0.45), acc.darkened(0.8), acc.darkened(0.1), 999.0, 3))
	var ic := Kit.icon(str(ICONS.get(counter, "quests")), 54)
	ic.position = Vector2(15, 15)
	ic.size = Vector2(54, 54)
	disc.add_child(ic)
	row.add_child(disc)

	var mid := Kit.vbox(8)
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	var t := Kit.label(str(q.title), 26, Kit.INK if not claimed else Kit.INK_DIM, "extrabold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(t)
	var p := mini(int(q.progress), int(q.goal))
	var bar := Kit.progress_bar(p, int(q.goal), Kit.GOLD if ready else (Kit.GOOD if claimed else Kit.SKY), 24, "%d / %d" % [p, int(q.goal)])
	mid.add_child(bar)
	var rw := Kit.hbox(12)
	rw.mouse_filter = MOUSE_FILTER_IGNORE
	for e: Dictionary in Kit.reward_entries(q.get("reward", {})):
		if str(e.kind) != "currency":
			continue
		var pair := Kit.hbox(4)
		pair.mouse_filter = MOUSE_FILTER_IGNORE
		pair.add_child(Kit.currency_icon(str(e.id), 32))
		pair.add_child(Kit.label(Kit.format_num(int(e.amount)), 22, Kit.INK if not claimed else Kit.INK_DIM, "black", 4))
		rw.add_child(pair)
	mid.add_child(rw)
	row.add_child(mid)

	var qid := str(q.id)
	var b: Button
	if claimed:
		b = Kit.secondary_button("Done", Callable(), "check")
		b.disabled = true
	elif ready:
		b = Kit.primary_button("Claim", func() -> void: _claim(qid, card))
		Kit.set_dot(b, true, 24, Vector2(8, 8))
		# A single finished quest: ring its Claim button (Claim all takes over for two or more).
		if _ready_count == 1:
			Guide.mark(b, Guide.step() == "quests", 0)
	elif GO_TO.has(counter):
		var dest: String = GO_TO[counter]
		b = Kit.secondary_button("Go", func() -> void: UI.go(dest), "chevron_right")
	else:
		b = Kit.secondary_button("Go")
		b.disabled = true
		b.text = "%d left" % (int(q.goal) - p)
	b.custom_minimum_size = Vector2(150, 88)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(b)
	if claimed:
		card.modulate = Color(1, 1, 1, 0.66)
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
