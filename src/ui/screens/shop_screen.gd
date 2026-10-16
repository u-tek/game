extends Control
## Screen "shop": prototype offers as illustrated cards with tags (best value, monthly,
## limited, popular, free). Every purchase button reads "Test purchase: no charge" because
## this build has no real payments: buying calls Game.buy_offer and shows the reward popup.
## Limits ("1 per account", "2 of 3 left", "Claimed today") and the Moonlit Pass days left are
## shown on each card. The free daily gift sits at the top.

const DARK_INK := Color("3d2306")
const TAG_COLORS := {
	"best value": Color("f2c14e"), "monthly": Color("6fc3e8"), "limited": Color("d9412b"),
	"popular": Color("b36bf0"), "free": Color("5cd6a0"),
}
## Big art icon per offer (falls back to its main reward currency).
const OFFER_ICONS := {
	"daily_gift": "gift", "starter_pack": "chest", "monthly_card": "crown", "scroll_bundle": "scrolls",
}

var _list: VBoxContainer
var _scroll: ScrollContainer
var _sig := ""
var _tick := 0.0
var _reset_labels: Array[Label] = []


func setup(params: Dictionary) -> void:
	_build()
	Game.changed.connect(_refresh)
	_refresh()
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params["scroll"]))


## Shot/testing helper (params.scroll).
func _scroll_to(px: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = px


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _build() -> void:
	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_right = -22
	col.offset_top = 14
	add_child(col)
	var head := Kit.hbox(12)
	head.add_child(Kit.icon("shop", 64))
	var tv := Kit.vbox(0)
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.add_child(Kit.header("Shop", 44))
	var note := Kit.caption("Prototype build: every purchase is a free test purchase.", 21, Kit.GOOD)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(note)
	head.add_child(tv)
	col.add_child(head)
	_list = Kit.vbox(18)
	var m := Kit.margin(_list, 0, 0)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 26)
	_scroll = Kit.scroll(m)
	col.add_child(_scroll)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		for l in _reset_labels:
			if is_instance_valid(l):
				l.text = "Back in %s" % Kit.format_time(Game.ms_until_reset())


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	var offers := Game.offers()
	var sig := JSON.stringify(offers) + str(Game.monthly_card_days_left())
	if sig == _sig:
		return
	_sig = sig
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_reset_labels.clear()
	var featured: Array[Dictionary] = []
	var packs: Array[Dictionary] = []
	for o in offers:
		if _is_gem_pack(o):
			packs.append(o)
		else:
			featured.append(o)
	for o in featured:
		_list.add_child(_offer_card(o))
	if not packs.is_empty():
		_list.add_child(Kit.section_header("Gems", 30))
		for o in packs:
			_list.add_child(_pack_row(o))
	_restore.call_deferred(keep)


func _restore(y: int) -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


## A plain gems-for-money pack (only gems in the reward, no tag but "popular").
static func _is_gem_pack(o: Dictionary) -> bool:
	var r: Dictionary = o.get("reward", {})
	return r.size() == 1 and r.has("gems") and str(o.id) != "monthly_card" and str(o.get("price_label", "")) != "Free"


func _offer_card(o: Dictionary) -> Control:
	var id := str(o.id)
	var tag := str(o.get("tag", ""))
	var accent: Color = TAG_COLORS.get(tag, Kit.GOLD)
	var available := bool(o.get("available", true))
	var card := PanelContainer.new()
	card.mouse_filter = MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", Kit.box(accent.darkened(0.62).lerp(Kit.PANEL_HI, 0.35), Color("120d26"), accent.darkened(0.05), 20.0, 3, 20))
	var v := Kit.vbox(12)
	card.add_child(v)

	var top := Kit.hbox(16)
	var art := Control.new()
	art.custom_minimum_size = Vector2(128, 128)
	art.mouse_filter = MOUSE_FILTER_IGNORE
	var gl := Kit.glow(accent, 170)
	gl.position = Vector2(-21, -21)
	gl.size = Vector2(170, 170)
	gl.modulate.a = 0.55
	art.add_child(gl)
	var icon_name := str(OFFER_ICONS.get(id, _main_currency(o)))
	var ic := Kit.icon(icon_name, 112)
	ic.position = Vector2(8, 8)
	ic.size = Vector2(112, 112)
	art.add_child(ic)
	top.add_child(art)
	var info := Kit.vbox(4)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	var nrow := Kit.hbox(8)
	var n := Kit.header(str(o.name), 32)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	nrow.add_child(n)
	if tag != "":
		var tg := Kit.tag(tag.to_upper(), accent, DARK_INK if accent.get_luminance() > 0.5 else Color.WHITE, 18)
		tg.size_flags_vertical = SIZE_SHRINK_BEGIN
		nrow.add_child(tg)
	info.add_child(nrow)
	var d := Kit.body(str(o.get("description", "")), 22, Kit.INK_DIM)
	info.add_child(d)
	top.add_child(info)
	v.add_child(top)

	var rewards := Kit.reward_list(o.get("reward", {}), 92.0, true, false)
	var side_by_side := Kit.reward_entries(o.get("reward", {})).size() <= 3
	var bottom := Kit.hbox(14)
	var status := Kit.vbox(6)
	status.size_flags_horizontal = SIZE_EXPAND_FILL
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	if side_by_side:
		status.add_child(rewards)
	else:
		v.add_child(rewards)
	var lim := Kit.caption(_limit_text(o), 21, Kit.INK)
	lim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(lim)
	if id == "monthly_card":
		var days := int(o.get("days_left", Game.monthly_card_days_left()))
		var dl := Kit.label("Active: %d days left" % days if days > 0 else "Not active yet", 22, Kit.GOOD if days > 0 else Kit.INK_DIM, "extrabold")
		status.add_child(dl)
	if not available and str(o.get("period", "")) == "day":
		var rl := Kit.caption("", 21, Kit.INK_DIM)
		rl.text = "Back in %s" % Kit.format_time(Game.ms_until_reset())
		_reset_labels.append(rl)
		status.add_child(rl)
	bottom.add_child(status)
	var bb := _buy_button(o, 300.0)
	bb.size_flags_vertical = SIZE_SHRINK_END
	bottom.add_child(bb)
	v.add_child(bottom)
	if not available:
		card.modulate = Color(0.75, 0.73, 0.8)
	return card


func _pack_row(o: Dictionary) -> Control:
	var tag := str(o.get("tag", ""))
	var accent: Color = TAG_COLORS.get(tag, Kit.SKY)
	var card := Kit.card(16)
	var row := Kit.hbox(14)
	card.add_child(row)
	var art := Control.new()
	art.custom_minimum_size = Vector2(96, 96)
	art.mouse_filter = MOUSE_FILTER_IGNORE
	var gl := Kit.glow(Kit.SKY, 130)
	gl.position = Vector2(-17, -17)
	gl.size = Vector2(130, 130)
	gl.modulate.a = 0.4
	art.add_child(gl)
	var gems := int(o.get("reward", {}).get("gems", 0))
	var count := 1 if gems < 1000 else (2 if gems < 3000 else 3)
	for i in count:
		var ic := Kit.icon("gems", 70 - i * 6)
		ic.position = Vector2(12 + (i - (count - 1) * 0.5) * 18, 14 - i * 6 + (count - 1) * 4)
		ic.size = ic.custom_minimum_size
		art.add_child(ic)
	row.add_child(art)
	var info := Kit.vbox(2)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var amt := Kit.hbox(8)
	amt.add_child(Kit.label(Kit.format_full(gems), 34, Kit.INK, "black", 4))
	amt.add_child(Kit.caption("gems", 22))
	info.add_child(amt)
	if tag != "":
		var tg := Kit.tag(tag.to_upper(), accent, Color.WHITE, 15)
		art.add_child(tg)
		var ts := tg.get_combined_minimum_size()
		tg.position = Vector2(48 - ts.x * 0.5, 96 - ts.y + 6)
	info.add_child(Kit.caption(str(o.name), 22, Kit.INK_DIM))
	row.add_child(info)
	row.add_child(_buy_button(o, 266.0))
	return card


func _buy_button(o: Dictionary, width: float) -> Button:
	var id := str(o.id)
	var available := bool(o.get("available", true))
	var free := not bool(o.get("test_purchase", true))
	var b := Kit.primary_button("", func() -> void: _buy(id)) if available else Kit.secondary_button("")
	b.custom_minimum_size = Vector2(width, 104)
	var v := Kit.vbox(0)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_bottom = -6
	var line1 := ""
	var line2 := ""
	if not available:
		b.disabled = true
		line1 = "Claimed" if str(o.get("period", "")) == "day" else "Sold out"
		line2 = "Come back tomorrow" if str(o.get("period", "")) == "day" else "Limit reached"
	elif free:
		line1 = "Claim Free"
		line2 = "Daily gift"
	else:
		line1 = "Buy  %s" % str(o.get("price_label", ""))
		line2 = "Test purchase: no charge"
	var c1 := DARK_INK if available else Kit.INK_DIM
	var a := Kit.label(line1, 30, c1, "extrabold")
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var s := Kit.label(line2, 19, Color("5a3a0e") if available else Kit.INK_DIM, "black")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	b.add_child(v)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	return b


func _limit_text(o: Dictionary) -> String:
	var limit := int(o.get("limit", 0))
	var bought := int(o.get("purchased", 0))
	var period := str(o.get("period", "once"))
	if limit <= 0:
		return "No limit" + ("  ·  bought %d" % bought if bought > 0 else "")
	if period == "day":
		return "%d per day" % limit if limit > 1 else "Once a day"
	if limit == 1:
		return "Once per account" + ("  ·  purchased" if bought >= 1 else "")
	return "%d of %d left" % [maxi(0, limit - bought), limit]


static func _main_currency(o: Dictionary) -> String:
	var r: Dictionary = o.get("reward", {})
	for c: String in ["gems", "scrolls", "gold", "hero_exp", "dust"]:
		if r.has(c):
			return c
	return "gift"


func _buy(id: String) -> void:
	var name_s := id
	for o: Dictionary in Game.offers():
		if str(o.id) == id:
			name_s = str(o.name)
	var r := Game.buy_offer(id)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "Purchase failed")), "bad")
		return
	UI.show_reward(name_s, r.get("value", {}))
