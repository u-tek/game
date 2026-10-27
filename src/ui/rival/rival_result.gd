extends "res://src/ui/battle/battle_result.gd"
## The Rival's result poster (battle screen mode "rival"), built like the battle reports (risograph
## prints in the poster look): a dark band down the left with Rue's ace as a red halftone, the verdict
## turned on its side (YOU BEAT RUE. / RUE WINS.), paper on the band and signal on the paper over an
## ink plate out of register, the winner in full colour in a hairline box, Rue's line on a paper slip,
## the record, and:
##   a win    the haul as a printed bracket table (or "pride only" when today's haul was taken), the
##            print taken from her binder as a slab stuck on the poster, your marker tag scrawled across
##            the foot ("ENVOY WAS HERE").
##   a loss   a rubber stamp COST: NOTHING, a sticker SHE TAGGED YOUR LOBBY, and how to win (numbered
##            printed lines: level up, team, counter her faction).
## Buttons: the pass (Done: back to her poster on a win, Rematch on a loss), "← Lobby" printed under
## the poster, and a printed Rematch / Done beside it. Actions go to on_action: "rival" | "retry" |
## "home" | "level" | "formation".

const CK := preload("res://src/ui/v4/collect/collect_kit.gd")


## data: victory, value (complete_rival's {reward, print, haul, line, record}), mvp, foe, team_size,
## safe_top, safe_bottom, report_no, rival (Game.rival()).
func show_rival(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var p := _poster
	var pw := _pr.size.x
	var ph := _pr.size.y
	var win := bool(data.get("victory", false))
	var val: Dictionary = data.get("value", {})
	var rv: Dictionary = data.get("rival", {})
	var ace := str(rv.get("ace", ""))
	var mvp: Dictionary = data.get("mvp", {})
	var winner := str(mvp.get("hero_id", "")) if win else ace
	var wskin := Kit.hero_look(winner) if winner != "" else ""
	var x_end := pw - RULE - 10.0

	# The band: Rue's ace as a red halftone, the micro type.
	BP.rect(p, Rect2(0, 0, BAND_W, ph), BP.BAND)
	if ace != "":
		var ht := BP.halftone(ace, Kit.hero_look(ace), {"crop": "face"})
		ht.position = Vector2(0, ph * 0.5)
		ht.size = Vector2(BAND_W, ph * 0.5)
		p.add_child(ht)
	BP.at(p, BP.t("HH", 30, BP.PAPER, "wide_black"), Vector2(18, 14))
	var rights := BP.t("RIVAL REPORT  ·  ©2026 HH  ·  THE OTHER SUMMONER", 10, Color(BP.PAPER, 0.8), "mono_bold")
	rights.rotation = PI * 0.5
	rights.position = Vector2(30, 70)
	p.add_child(rights)

	# The verdict down the poster.
	var word := "YOU BEAT RUE." if win else "RUE WINS."
	var room := ph - 250.0
	var fs := BP.fit(word, room, 240, 120)
	var cap := BP.caps(fs)
	var cap_h := cap.y - cap.x
	var feet_x := BAND_W - cap_h * 0.55
	var pos := Vector2(feet_x + cap.y, 26.0)
	var block := Vector2(room + 80.0, fs * 1.3)
	var paper_r := Rect2(BAND_W, 0, pw - BAND_W, ph)
	_giant = BP.giant(p, word, fs, pos + Vector2(6, 5), block, [[paper_r, Color(BP.INK, 0.92)]])
	_giant.append_array(BP.giant(p, word, fs, pos, block, [[Rect2(0, 0, BAND_W, ph), BP.PAPER], [paper_r, BP.SIG]]))
	var x0 := feet_x + cap_h + 16.0
	var cw := x_end - x0

	# The title block.
	var rec: Dictionary = val.get("record", rv.get("record", {}))
	BP.at(p, BP.t("RIVAL REPORT  ·  No.%04d" % int(data.get("report_no", 0)), 11, BP.INK, "mono_bold"), Vector2(x0, 18))
	BP.at(p, BP.t("RUE", 46, BP.INK, "compressed"), Vector2(x0 - 2, 28))
	var sub := BP.t("RECORD %02d—%02d  ·  %s" % [int(rec.get("wins", 0)), int(rec.get("losses", 0)), "YOUR WIN" if win else "HER WIN"], 11,
		Color(BP.INK, 0.8), "mono")
	BP.at(p, sub, Vector2(x0, 88))
	var date := BP.t(_date_long(), 11, BP.INK, "mono_bold")
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.size = Vector2(120, 16)
	BP.at(p, date, Vector2(x0 + cw - 120, 18))

	# The winner in full colour, boxed by a hairline.
	var box_h := minf(ph * 0.42, 520.0)
	var box := Rect2(x0, 112.0, cw, box_h)
	var hb := Control.new()
	hb.name = "HeroBox"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.clip_contents = true
	hb.position = box.position
	hb.size = box.size
	p.add_child(hb)
	if winner != "":
		var height := box.size.y * 0.96
		var feet := Vector2(box.size.x * 0.56, box.size.y - 6.0)
		_hero = PK.hero_fig(hb, winner, wskin, feet, height)
		var spr := _hero.get_child(0) as Node2D
		var sr := PK.still_rect(spr, _hero.position, height)
		var echo := BP.riso(winner, wskin, "full", {"shift_b": Vector2(5, -4), "cell_a": 6.0, "cell_b": 5.0, "strength": 0.9})
		echo.position = _hero.position + (sr.position - _hero.position) * 1.1 + Vector2(-58, -10)
		echo.size = sr.size * 1.1
		hb.add_child(echo)
		hb.move_child(echo, 0)
		if spr.has_method("play_victory"):
			spr.call("play_victory")
	HPK.rule(p, box.position, Vector2(box.size.x, 1))
	HPK.rule(p, box.position + Vector2(0, box.size.y - 1), Vector2(box.size.x, 1))
	HPK.rule(p, box.position, Vector2(1, box.size.y))
	HPK.rule(p, box.position + Vector2(box.size.x - 1, 0), Vector2(1, box.size.y))
	var who := BP.t(("YOUR MVP  ·  %s" if win else "HER ACE  ·  %s") % str(HeroData.get_def(winner).get("name", "")).to_upper(), 10, BP.INK, "mono_bold")
	BP.at(p, who, Vector2(x0 + 8, box.end.y + 6))

	# Her line on a paper slip, stuck over the box's foot.
	var line := str(val.get("line", rv.get("line", "")))
	var slip := PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f4f3ef")
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(1, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	slip.add_theme_stylebox_override("panel", sb)
	var lv := Kit.vbox(0)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(BP.t("RUE  ·  %s" % ("AFTER LOSING" if win else "GLOATING"), 10, BP.SIG, "mono_bold"))
	var ll := BP.t("“%s”" % line, 22, BP.INK, "serif_italic")
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.custom_minimum_size = Vector2(cw - 40.0, 0)
	lv.add_child(ll)
	slip.add_child(lv)
	slip.position = Vector2(x0 - 30.0, box.end.y - 70.0)
	slip.rotation = -0.025
	p.add_child(slip)
	_fade_in.append(slip)

	var y := box.end.y + 40.0
	if win:
		y = _win_block(p, val, x0, y, cw)
	else:
		y = _loss_block(p, x0, y, cw, rv)
	_rule_labels(p, pw - RULE, 18, ph - 18, ["RIVAL", "RUE", "WIN" if win else "LOSS", "RECORD", "%02d—%02d" % [int(rec.get("wins", 0)),
		int(rec.get("losses", 0))]], BP.INK)

	# The pass, the printed Lobby and the other way out.
	if win:
		_pass = _make_pass("Done", "rival", {"kicker": "RIVAL // FILED", "title": "BACK TO HER POSTER", "sub": "SHE'S SULKING",
			"action": "DONE  >>>", "icon": "check", "info": "REMATCH ANY TIME"})
	else:
		_pass = _make_pass("Rematch", "retry", {"kicker": "RIVAL // AGAIN", "title": "REMATCH", "sub": "LOSING COSTS NOTHING",
			"action": "FIGHT  >>>", "icon": "flag", "info": "HER TEAM TODAY · SAME LEVEL"})
	_page.add_child(_lobby_button())
	var other := PK.print_button("Rematch" if win else "Done", func() -> void: _emit("retry" if win else "rival"),
		{"size": Vector2(200, 88), "text_size": 17})
	other.name = "Rematch" if win else "Done"
	other.position = Vector2(_pr.position.x + 210, _pr.end.y + 8)
	_page.add_child(other)
	p.add_child(SignalKit.grain(0.05, true))
	_animate_in(0)


## A win: the haul (or pride only), the print taken from her binder, your tag across the foot.
func _win_block(p: Control, val: Dictionary, x0: float, y: float, cw: float) -> float:
	var reward: Dictionary = val.get("reward", {})
	var pd: Dictionary = val.get("print", {})
	BP.at(p, BP.t("TODAY'S HAUL" if bool(val.get("haul", false)) else "TODAY'S HAUL WAS ALREADY TAKEN", 12, BP.INK, "mono_bold"), Vector2(x0, y))
	BP.rect(p, Rect2(x0, y + 20, cw, 1), Color(BP.INK, 0.55))
	var rows: Array = _reward_rows(reward) if bool(val.get("haul", false)) else [["PRIDE", "+1", true], ["NEXT HAUL", "TOMORROW"]]
	var tw := cw if pd.is_empty() else cw - 190.0
	var tb := PK.data_table(rows, tw, {"size": 14, "row_h": 28.0, "bar": Color(1, 1, 1, 0.7)})
	tb.position = Vector2(x0, y + 32)
	p.add_child(tb)
	_fade_in.append(tb)
	if not pd.is_empty():
		var card := PrintCard.make(pd, Vector2(176, 264))
		card.name = "WonPrint"
		card.position = Vector2(x0 + cw - 176.0, y - 10.0)
		card.rotation = 0.06
		card.pivot_offset = card.size * 0.5
		p.add_child(card)
		_fade_in.append(card)
		var lab := BP.t("FROM HER BINDER", 10, BP.SIG, "mono_bold")
		BP.at(p, lab, Vector2(x0 + cw - 170.0, y + 262.0))
	# Your tag across the foot of the poster.
	var who := ProfileScreen.player_name()
	var txt := "%s WAS HERE" % who
	var sc := CK.Scrawl.new()
	sc.name = "YourTag"
	sc.text = txt
	sc.color = Color("1a1b1e")
	sc.stroke = 7.0
	sc.seed_v = int((val.get("record", {}) as Dictionary).get("fights", 3))
	var h := 48.0
	sc.size = Vector2(CK.Scrawl.width_for(txt, h, 7.0), h)
	var s := minf(1.0, (cw + 60.0) / sc.size.x)
	sc.scale = Vector2(s, s)
	sc.position = Vector2(x0 - 70.0, y + 296.0)
	sc.rotation = -0.06
	p.add_child(sc)
	_fade_in.append(sc)
	return y + 350.0


## A loss: COST: NOTHING, she tagged your Lobby, how to win.
func _loss_block(p: Control, x0: float, y: float, cw: float, rv: Dictionary) -> float:
	var st := PrintCard.Stamp.new()
	st.text = "COST: NOTHING"
	st.sub = "NO GEMS · NO GOLD · NO PRINTS LOST"
	st.color = BP.SIG
	st.size = Vector2(minf(cw, 330.0), 92)
	st.position = Vector2(x0, y - 4)
	st.pivot_offset = st.size * 0.5
	st.rotation = -0.05
	p.add_child(st)
	_fade_in.append(st)
	var stk := CK.Sticker.new()
	stk.lines = ["TAGGED", "YOUR LOBBY POSTER"]
	stk.fill = SignalKit.INK
	stk.ink = BP.SIG
	stk.horns = true
	stk.size = Vector2(118, 118)
	# Stuck across the photo's corner, clear of the stamp's small print.
	stk.position = Vector2(x0 + cw - 92.0, y - 74.0)
	stk.rotation = 0.12
	p.add_child(stk)
	_fade_in.append(stk)
	var ty := y + 104.0
	BP.at(p, BP.t("HOW TO BEAT HER", 12, BP.INK, "mono_bold"), Vector2(x0, ty))
	BP.rect(p, Rect2(x0, ty + 20, cw, 1), Color(BP.INK, 0.55))
	var c: Dictionary = rv.get("counter", {})
	var lines := [["Level up your team", "She fights at your level, give or take", "level"],
		["Change your team", "She reads your main faction after %d fights" % int(RivalRules.data().learn_after), "formation"]]
	if str(c.get("faction", "")) != "":
		var counter := ""
		for f in BattleSim.FACTIONS:
			if str(BattleSim.BEATS.get(f, "")) == str(c.faction):
				counter = f
		lines[1] = ["Bring %s" % counter.capitalize(), "She stacks %s; %s beats them" % [str(c.faction).capitalize(), counter.capitalize()], "formation"]
	for i in lines.size():
		var b := _tip_line(i + 1, str(lines[i][0]), str(lines[i][1]), str(lines[i][2]), cw)
		b.position = Vector2(x0, ty + 28 + i * 92)
		p.add_child(b)
	return ty + 28 + lines.size() * 92
