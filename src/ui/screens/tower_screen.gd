extends Control
## Screen "tower": the Spire (TowerData, data/tower.json), style v4 "Signal" in the approved poster
## look (docs/dev/ui-style-v4.md). A printed poster on the paper matte: the dark band down the left
## carries the next floor's lead enemy as a red halftone print and "THE SPIRE" set huge down the
## poster; the centrepiece is the climb as an exploded stack of floor plates in
## isometric line art (src/ui/v4/survey/plate_stack.gd: cleared floors in ink, the next floor in
## signal red, sealed floors on paper, boss floors with a second rim), each with a leader to its
## label. The title block (top right) holds the best floor; the right edge is an altitude ruler
## (0 to the top floor) with the best floor and the next one marked. Under the stack, the next
## floor's cartouche (power check, enemy echoes with the counter, first-clear rewards), the TEAM
## stamp and the Fight pass. Before the unlock the stack prints grey under a SEALED stamp and the
## pass goes to the campaign; after the top floor the cartouche says so.

const Poster := preload("res://src/ui/v4/survey/poster.gd")
const PlateStack := preload("res://src/ui/v4/survey/plate_stack.gd")
const HUD := preload("res://src/ui/components/hud.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")
## Floors shown on the stack: this many below the next one and above it.
const BELOW := 1
const ABOVE := 3
const W := 720.0
const BAND_W := 132.0
const RULE_W := 48.0
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL

var _root: Control
var _pr := Rect2()
var _fight_btn: Button
var _sig := ""


func setup(_params: Dictionary) -> void:
	UI.set_full_bleed(true)
	Poster.matte(self)
	_root = Control.new()
	_root.name = "Sheet"
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_root)
	Game.changed.connect(_refresh)
	_refresh()


## The screen's own entrance (UI calls it instead of the generic stagger).
func intro() -> void:
	pass


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _refresh() -> void:
	if not is_inside_tree():
		return
	# Reprint only when something on the poster changed.
	var sig := "%d|%d|%s|%d" % [Game.tower_next(), Game.tower_best(), str(Game.tower_unlocked()), Game.team_power()]
	if sig == _sig:
		return
	_sig = sig
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_build()


func _build() -> void:
	var vh := get_viewport_rect().size.y
	var top := UI.content_top()
	var bottom := UI.content_bottom()
	_pr = Rect2(18, top + 12, W - 36, vh - bottom - 58 - (top + 12))
	var p := Poster.poster(_root, _pr)
	var pw := _pr.size.x
	var ph := _pr.size.y
	var unlocked := Game.tower_unlocked()
	var total := Game.tower_floors()
	var nxt := Game.tower_next()
	var best := Game.tower_best()
	var summit := nxt > total
	var shown := mini(nxt, total)
	var fl := Game.tower_floor(shown)
	var lead := _lead_of(fl)
	var stage_y := ph - 352.0

	# ---- The dark band: the next floor's lead enemy as a red halftone print, micro type.
	Poster.rect(p, Rect2(0, 0, BAND_W, ph), Poster.BAND)
	if lead != "":
		Poster.halftone_print(p, lead, Rect2(0, ph * 0.36, BAND_W, ph * 0.64), Color(1.0, 0.36, 0.16, 0.95), 6.5)
	p.add_child(SignalKit.back_button(func() -> void: UI.back(), false))
	Poster.giant_side(p, TowerData.NAME, 150, 150.0, 104.0, 0.0, BAND_W, true)

	# ---- The stack of floors.
	var stack := PlateStack.new()
	stack.name = "Stack"
	stack.position = Vector2(BAND_W, 104)
	stack.size = Vector2(pw - RULE_W - BAND_W - 4, stage_y - 104)
	var lo := maxi(1, shown - BELOW)
	var hi := mini(total, maxi(shown + ABOVE, lo + BELOW + ABOVE))
	lo = maxi(1, mini(lo, hi - BELOW - ABOVE))
	var list: Array = []
	for f in range(lo, hi + 1):
		var tf := Game.tower_floor(f)
		var state := "cleared" if f <= best else ("next" if f == nxt and unlocked else "locked")
		var boss := bool(tf.get("is_boss", false))
		var label := "F.%03d  %s" % [f, "NEXT" if state == "next" else ("CLEARED" if state == "cleared" else "SEALED")]
		var sub := ""
		if boss:
			sub = ("BOSS  ·  " + sub) if sub != "" else "BOSS FLOOR"
		elif f % 5 == 0 and state != "cleared":
			sub = sub if sub != "" else "GEM FLOOR"
		list.append({"floor": f, "state": state, "boss": boss, "label": label, "sub": sub})
	stack.floors = list
	stack.muted = not unlocked
	stack.fit(stack.size)
	p.add_child(stack)
	if not unlocked:
		Poster.rubber(p, "SEALED", Vector2(BAND_W + stack.size.x * 0.22, 104 + stack.size.y * 0.42), SIG, 30, -0.14)

	# ---- The title block (top right).
	var x0 := 252.0
	var tw := pw - RULE_W - 12 - x0
	var tb := Control.new()
	tb.mouse_filter = MOUSE_FILTER_IGNORE
	tb.position = Vector2(x0, 16)
	p.add_child(tb)
	Poster.at(tb, Poster.t("TOWER SURVEY", 12, INK), Vector2(0, 0))
	var dl := Poster.t("%03d FLOORS" % total, 12, INK)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size = Vector2(tw, 16)
	Poster.at(tb, dl, Vector2(0, 0))
	Poster.hline(tb, 0, 20, tw, Color(INK, 0.7))
	Poster.at(tb, Poster.t(TowerData.NAME.to_upper(), 28, INK, "wide_black"), Vector2(-2, 24))
	Poster.at(tb, Poster.t("CLIMB AS HIGH AS YOU CAN", 11, Color(INK, 0.75), "mono"), Vector2(0, 62))
	Poster.at(tb, Poster.t("EVERY 10TH FLOOR: A BOSS  ·  EVERY 5TH: GEMS", 11, INK, "mono_bold"), Vector2(0, 80))
	var bl := Poster.t("%03d/%03d" % [best, total], 22, INK, "wide_black")
	bl.name = "BestFloor"
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bl.size = Vector2(tw, 26)
	Poster.at(tb, bl, Vector2(0, 30))
	var bc := Poster.t("BEST FLOOR", 9, Color(INK, 0.7), "mono_bold")
	bc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bc.size = Vector2(tw, 12)
	Poster.at(tb, bc, Vector2(0, 58))

	# ---- The altitude ruler down the right edge.
	var rx := pw - RULE_W
	Poster.vline(p, rx, 0, ph, Color(INK, 0.55))
	Poster.vlabel(p, "©2026 ·", Vector2(rx + 34, 12), 12, INK)
	Poster.vlabel(p, "ALTITUDE / FLOORS", Vector2(rx + 34, 96), 12, INK)
	var r0 := 300.0
	var r1 := ph - 200.0
	for k in 13:
		var fk := int(round(total * (12 - k) / 12.0))
		var yk := lerpf(r0, r1, k / 12.0)
		Poster.rect(p, Rect2(rx - (8 if k % 3 == 0 else 4), yk, 8 if k % 3 == 0 else 4, 1), INK)
		if k % 3 == 0:
			Poster.at(p, Poster.t("%03d" % fk, 9, Color(INK, 0.7), "mono"), Vector2(rx + 6, yk - 7))
	var by := lerpf(r1, r0, float(best) / maxf(total, 1))
	var bm := Poster.t("BEST %03d >" % best, 9, INK, "mono_bold")
	bm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bm.size = Vector2(90, 12)
	Poster.at(p, bm, Vector2(rx - 96, by - 6))
	if unlocked and not summit:
		var ny := lerpf(r1, r0, float(nxt) / maxf(total, 1))
		Poster.rect(p, Rect2(rx - 12, ny, 12, 2), SIG)
		var led := HUD.Led.new()
		led.size = Vector2(16, 16)
		led.position = Vector2(rx + 16, ny - 8 - 16)
		led.mode = "breathe"
		p.add_child(led)

	# ---- The cartouche for the next floor, then the TEAM stamp and the Fight pass.
	var s := Control.new()
	s.name = "FloorPanel"
	s.mouse_filter = MOUSE_FILTER_IGNORE
	s.position = Vector2(BAND_W, stage_y)
	s.size = Vector2(rx - BAND_W, ph - stage_y)
	p.add_child(s)
	var sw := s.size.x
	Poster.rect(s, Rect2(0, 0, sw, 178), PAPER)
	Poster.hline(s, 0, 0, sw, INK, 1.5)
	Poster.hline(s, 0, 178, sw, Color(INK, 0.4))
	var slot := Control.new()
	slot.mouse_filter = MOUSE_FILTER_IGNORE
	slot.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_root.add_child(slot)
	_fight_btn = null
	if not unlocked:
		var need := TowerData.UNLOCK_CLEARED
		var st := Game.stage(need - 1)
		Poster.at(s, Poster.t("LOCKED", 10, Color(INK, 0.7)), Vector2(14, 8))
		Poster.at(s, Poster.t("SEALED", 40, SIG, "wide_black"), Vector2(12, 18))
		var msg := Poster.t("Clear stage %s in the campaign\nto open %s." % [str(st.get("id", need)), TowerData.NAME], 20, INK, "regular")
		Poster.at(s, msg, Vector2(14, 84))
		var spec := {"width": 400.0, "kicker": "CAMPAIGN // OPENS THE SPIRE", "title": "STAGE %s" % str(st.get("id", need)),
			"sub": "CLEAR IT TO BREAK THE SEAL", "action": "CAMPAIGN  >>>", "icon": "campaign", "info": "%d / %d CLEARED" % [Game.cleared_count(), need]}
		Poster.pass_on(slot, spec, _pr.position + Vector2(pw - 412, ph - 176), func() -> void: UI.go("campaign"), "Campaign", "Campaign")
		_tail(lead)
		return
	if summit:
		Poster.at(s, Poster.t("SUMMIT", 10, Color(INK, 0.7)), Vector2(14, 8))
		Poster.at(s, Poster.t("%03d" % total, 40, SIG, "wide_black"), Vector2(12, 18))
		var top_msg := Poster.t("You cleared every floor of %s.\nMore floors are coming." % TowerData.NAME, 20, INK, "regular")
		Poster.at(s, top_msg, Vector2(14, 84))
		Poster.rubber(s, "SUMMIT", Vector2(sw - 200, 30), SIG, 22, -0.1)
		_tail(lead)
		return
	var team := int(Game.team_power())
	var rec := int(fl.get("recommended_power", 0))
	var boss := bool(fl.get("is_boss", false))
	Poster.hline(s, 0, 74, sw, Color(INK, 0.4))
	Poster.vline(s, sw * 0.62, 74, 104, Color(INK, 0.4))
	Poster.at(s, Poster.t("FLOOR", 10, Color(INK, 0.7)), Vector2(14, 8))
	var idl := Poster.t("%03d" % nxt, 40, SIG, "wide_black")
	Poster.at(s, idl, Vector2(12, 18))
	var idw := idl.get_minimum_size().x
	Poster.at(s, Poster.t("BOSS FLOOR" if boss else ("GEM FLOOR" if nxt % 5 == 0 else "NEXT FLOOR"), 36, INK, "compressed"), Vector2(idw + 28, 10))
	Poster.at(s, Poster.t("BEST %03d  ·  NEXT %03d / %03d" % [best, nxt, total], 10, Color(INK, 0.7), "mono"), Vector2(idw + 30, 54))
	var verdict := StageInfo.verdict_light(team, rec)
	for row: Array in [["REC PWR %s" % Kit.format_full(rec), INK, "mono_bold", 10.0], ["TEAM %s" % Kit.format_num(team), Color(INK, 0.75), "mono", 30.0],
			[str(verdict[0]).to_upper(), verdict[1], "mono_bold", 50.0]]:
		var l := Poster.t(str(row[0]), 12, row[1], str(row[2]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size = Vector2(150, 16)
		Poster.at(s, l, Vector2(sw - 162, float(row[3])))
	if boss:
		Poster.rubber(s, "BOSS", Vector2(sw - 236, -12), SIG, 14, -0.08)
	var foe := StageInfo.main_faction(fl)
	var ctr := StageInfo.counter_of(foe)
	var eh := "ENEMY ECHOES"
	if ctr != "":
		eh += "  ·  COUNTER %s +20%%" % str(Kit.FACTION_NAMES.get(ctr, ctr)).to_upper()
	Poster.at(s, Poster.t(eh, 10, INK), Vector2(14, 82))
	Poster.at(s, Poster.echo_strip(StageInfo.enemy_slots(fl), 46.0), Vector2(14, 100))
	var rx2 := sw * 0.62 + 12
	Poster.at(s, Poster.t("FIRST CLEAR", 10, INK), Vector2(rx2, 82))
	Poster.at(s, Poster.reward_lines(fl.get("first_clear_reward", {}), sw - rx2 - 10, 11), Vector2(rx2, 100))
	var pp := _pr.position
	Poster.stamp_disc(slot, "TEAM · FORMATION · POWER · ", Kit.format_num(team), pp + Vector2(BAND_W + 22, ph - 152), 112.0, -0.12,
		func() -> void: UI.go("formation"), "Team", "Team")
	var spec := {"width": 400.0, "kicker": "ENGAGE", "title": "FLOOR %03d" % nxt, "sub": ("BOSS FLOOR" if boss else "BEST %03d" % best),
		"action": "FIGHT  >>>", "icon": "sword"}
	var pass_root := Poster.pass_on(slot, spec, pp + Vector2(pw - 412, ph - 176), func() -> void: _fight(nxt), "Fight", "FightFloor")
	_fight_btn = Poster.pass_hit(pass_root)
	_tail(lead)


## Under the poster: the date and a signature; grain over everything; light the plates.
func _tail(lead: String) -> void:
	var fy := _pr.end.y + 12.0
	Poster.at(_root, Poster.t(Poster.date_long(), 22, INK, "regular"), Vector2(20, fy + 8))
	var who := str(Game.hero_def(lead).get("name", "")) if lead != "" else TowerData.NAME
	var sig := Poster.t(who, 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	Poster.at(_root, sig, Vector2(W - 24 - 300, fy - 6))
	var swash := Poster.rect(_root, Rect2(W - 230, fy + 38, 200, 2), INK)
	swash.rotation = -0.05
	Poster.grain(_root)
	SignalKit.relight(_root)


## The boss of a floor (or its first enemy).
func _lead_of(fl: Dictionary) -> String:
	var first := ""
	for e: Variant in fl.get("enemies", []):
		if e is Dictionary:
			if first == "":
				first = str((e as Dictionary).get("hero_id", ""))
			if bool((e as Dictionary).get("is_boss", false)):
				return str((e as Dictionary).get("hero_id", ""))
	return first


func _fight(f: int) -> void:
	if Game.formation().all(func(x: Variant) -> bool: return str(x) == ""):
		UI.toast("Place at least one hero in your formation", "bad")
		UI.go("formation")
		return
	UI.go("battle", {"mode": "tower", "floor": f})
