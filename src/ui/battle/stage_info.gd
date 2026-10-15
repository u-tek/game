extends RefCounted
## Shared stage helpers for the campaign and battle screens: counter-faction math, power
## verdicts, enemy/ally lineup strips and first-clear reward previews.
##   const StageInfo := preload("res://src/ui/battle/stage_info.gd")

const ECHO_TINT := Color(0.84, 0.76, 1.0)
const SHORT_RED := Color("ff6a50")


## The faction that beats `faction` on the counter wheel ("" if none).
static func counter_of(faction: String) -> String:
	for f: String in BattleSim.BEATS:
		if str(BattleSim.BEATS[f]) == faction:
			return f
	return ""


## {faction: count} of a stage's enemies.
static func enemy_factions(st: Dictionary) -> Dictionary:
	var out := {}
	for e: Dictionary in st.get("enemies", []):
		var f := str(Game.hero_def(str(e.hero_id)).get("faction", ""))
		out[f] = int(out.get(f, 0)) + 1
	return out


## Most common enemy faction of a stage.
static func main_faction(st: Dictionary) -> String:
	var counts := enemy_factions(st)
	var best := str(st.get("enemy_faction", ""))
	var best_n := -1
	for f: String in ["celestial", "infernal", "fallen"]:
		if int(counts.get(f, 0)) > best_n:
			best_n = int(counts.get(f, 0))
			best = f
	return best


## {faction: count} in the player's formation.
static func team_factions() -> Dictionary:
	var out := {}
	for id: String in Game.formation():
		if id == "":
			continue
		var f := str(Game.hero_def(id).get("faction", ""))
		out[f] = int(out.get(f, 0)) + 1
	return out


## [label, color] comparing team power with the recommendation.
static func verdict(team: int, rec: int) -> Array:
	if rec <= 0 or team * 100 >= rec * 130:
		return ["Easy", Kit.GOOD]
	if team >= rec:
		return ["Fair", Kit.GOOD]
	if team * 100 >= rec * 85:
		return ["Tough", Kit.GOLD]
	return ["Very hard", SHORT_RED]


static func power_color(team: int, rec: int) -> Color:
	return verdict(team, rec)[1]


## Lineup strip: front row (slots 0-1) and back row (slots 2-4) as hero cards.
## units: Array of 5 Dictionaries indexed by slot ({} = empty) with hero_id, level, stars,
## is_boss. echo = enemy echo tint.
static func lineup(units: Array, card: float, echo: bool) -> HBoxContainer:
	var row := Kit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_group("Front", units, [0, 1], card, echo))
	var sep := ColorRect.new()
	sep.color = Color(Kit.GOLD, 0.25)
	sep.custom_minimum_size = Vector2(2, card * 0.8)
	sep.size_flags_vertical = Control.SIZE_SHRINK_END
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sep)
	row.add_child(_group("Back", units, [2, 3, 4], card, echo))
	return row


static func _group(title: String, units: Array, slots: Array, card: float, echo: bool) -> VBoxContainer:
	var v := Kit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Kit.caption(title.to_upper(), 17, Color(Kit.INK_DIM, 0.9))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := Kit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s: int in slots:
		var u: Dictionary = units[s] if s < units.size() else {}
		if u.is_empty():
			var e := Kit.empty_slot(card)
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(e)
			continue
		var opts := {"size": card, "owned": true}
		if u.has("level"):
			opts["level"] = int(u.level)
		if u.has("stars"):
			opts["stars"] = int(u.stars)
		if bool(u.get("is_boss", false)):
			opts["tag"] = "BOSS"
		var c := Kit.hero_card(str(u.hero_id), opts)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if echo:
			c.modulate = ECHO_TINT
		h.add_child(c)
	v.add_child(h)
	return v


## Enemies of a stage as a 5-slot array for lineup().
static func enemy_slots(st: Dictionary) -> Array:
	var out: Array = [{}, {}, {}, {}, {}]
	for e: Dictionary in st.get("enemies", []):
		var s := int(e.slot)
		if s >= 0 and s < 5:
			out[s] = e
	return out


## The player's formation as a 5-slot array for lineup().
static func team_slots() -> Array:
	var out: Array = []
	for id: String in Game.formation():
		if id == "":
			out.append({})
		else:
			var h := Game.hero(id)
			out.append({"hero_id": id, "level": int(h.get("level", 1)), "stars": int(h.get("stars", 1))})
	return out


## Reward tiles for a stage's first-clear reward preview (currencies plus gear drops).
static func reward_preview(reward: Dictionary, tile: float) -> HFlowContainer:
	var f := Kit.reward_list(reward, tile, true)
	for d: Dictionary in reward.get("gear_drops", []):
		f.add_child(gear_tile(str(d.get("slot", "weapon")), int(d.get("tier", 1)), tile))
	return f


## A gear tile for a drop that doesn't exist yet (slot + tier).
static func gear_tile(slot: String, tier: int, tile: float) -> Control:
	var col := Kit.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var acc := Kit.tier_color(tier)
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.custom_minimum_size = Vector2(tile, tile)
	face.add_theme_stylebox_override("panel", Kit.box(acc.darkened(0.55).lerp(Kit.PANEL_HI, 0.35), Color("100c22"), acc.darkened(0.1), 14, 3))
	var ic := Kit.icon("gear_" + slot, tile * 0.62)
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.offset_left = -tile * 0.31
	ic.offset_right = tile * 0.31
	ic.offset_top = -tile * 0.31
	ic.offset_bottom = tile * 0.31
	face.add_child(ic)
	var tl := Kit.label("T%d" % tier, int(tile * 0.18), acc.lightened(0.3), "black", 4)
	tl.position = Vector2(8, 2)
	face.add_child(tl)
	col.add_child(face)
	var n := Kit.caption(str(Kit.GEAR_SLOT_NAMES.get(slot, "Gear")), 18, Kit.INK_DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size.x = tile
	col.add_child(n)
	col.custom_minimum_size.x = tile
	return col


## "Bring X" counter hint block for a stage (inset panel).
static func counter_hint(st: Dictionary) -> PanelContainer:
	var p := Kit.panel("inset", 14)
	var v := Kit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var foe := main_faction(st)
	var ctr := counter_of(foe)
	var team := team_factions()
	var r1 := Kit.hbox(8)
	r1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r1.add_child(Kit.caption("Enemies", 22))
	var counts := enemy_factions(st)
	for f: String in ["celestial", "infernal", "fallen"]:
		if int(counts.get(f, 0)) > 0:
			r1.add_child(Kit.faction_badge(f, 30))
			r1.add_child(Kit.label("x%d" % int(counts[f]), 22, Kit.INK, "black"))
	v.add_child(r1)
	if ctr != "":
		var r2 := Kit.hbox(8)
		r2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r2.add_child(Kit.caption("Counter", 22))
		r2.add_child(Kit.faction_badge(ctr, 30))
		var have := int(team.get(ctr, 0))
		var txt := "+20%% damage  ·  you field %d" % have
		r2.add_child(Kit.label(txt, 22, Kit.GOOD if have > 0 else Kit.INK_DIM, "extrabold"))
		v.add_child(r2)
	var weak := str(BattleSim.BEATS.get(foe, ""))
	var n_weak := int(team.get(weak, 0))
	if weak != "" and n_weak > 0:
		var w := Kit.body("Careful: %s echoes deal +20%% damage to your %d %s hero%s." % [
			str(Kit.FACTION_NAMES.get(foe, foe)), n_weak, str(Kit.FACTION_NAMES.get(weak, weak)), "" if n_weak == 1 else "es"], 21, Color("ffb09a"))
		v.add_child(w)
	return p
