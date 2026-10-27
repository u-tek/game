extends Control
## Screen "front": the War for Souls (WarRules, GameModel.war; docs/dev/combat-v1.md), a printed war
## map in the house poster style (docs/dev/ui-style-v4.md section 0) with the ideas of the exploded
## map layers (ref 1), the mission map (12) and the mono data table with brackets (14).
##
## Before the player picks a side, the Oath: the poster split down the middle, HALO on paper with a
## Celestial heroine's print, HORN on ink with an Infernal one's, CHOOSE set huge across both, a pass
## under each half. After, the front:
##   head  the dark band with WAR. down it, the side's name, the week (day, days left), the
##         standing "HEAVEN 4 · 3 HELL" big, the souls data table;
##   chart the relief map (src/ui/v4/front_relief.gd): the seven sectors as one slab of land, Heaven's
##         cliffs far, Hell's basin near; Heaven's ground paper with gold dots, Hell's ink with red
##         dots and lava; the trench at each sector's control, its name down its column and its
##         control on a tag at the line; the player's sector ruled in signal with the flag; tap a
##         sector to send your souls there; the lines rise from neutral when the screen opens;
##   champ the week's enemy Champion (GameModel champion): her figure in full colour over her red
##         print in a dark panel, her name huge, the week's bar (the share worn down, tier ticks with
##         their rewards), tries left today and a FIGHT HER pass (battle mode champion);
##   claim last week's result as a stuck-on slip with a CLAIM pass (when there is one);
##   foot  the FIGHT pass to the campaign (every win sends souls_per_win souls), the date, a signature.
## params: scroll (px, screenshots).

const DistrictModel := preload("res://src/ui/v4/district_model.gd")
const FrontRelief := preload("res://src/ui/v4/front_relief.gd")
const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")
const Signature := preload("res://src/ui/components/signature.gd")
const PPK := preload("res://src/ui/v4/poster_kit.gd")

const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL
const GOLD := Color(0.86, 0.66, 0.24)
const BAND_C := Kit.BAND
const BAND := 132.0
const HEAD := 330.0
const CHART_H := 640.0
const CHAMP_H := 520.0
const MAX_W := 760.0
## Heroines printed on the Oath's two halves.
const HALO_FACE := "seraphiel"
const HORN_FACE := "mordessa"

var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _chart: Control
var _built := Vector2.ZERO
var _rebuild_queued := false


func setup(params: Dictionary) -> void:
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	if params.has("scroll"):
		_scroll_to.call_deferred(int(params.scroll))


func _scroll_to(y: int) -> void:
	for i in 6:
		await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = y


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_changed):
		Game.changed.disconnect(_on_changed)


func _on_changed() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _on_resized() -> void:
	if _scroll == null or size.x <= 0.0:
		return
	var d := _dims()
	if absf(d.x - _built.x) > 2.0 or absf(d.y - _built.y) > 2.0:
		_on_changed()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	var keep := _scroll.scroll_vertical if is_instance_valid(_scroll) else 0
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build(false)
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


func _build(animate: bool = true) -> void:
	var d := _dims()
	_built = d
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	var pw := w - 32.0
	var war: Dictionary = Game.war()
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_scroll = Kit.scroll(_page)
	_scroll.name = "Front"
	_scroll.size = d
	add_child(_scroll)
	var ph := 0.0
	if str(war.side) == "":
		ph = maxf(d.y - 14.0 - 84.0, 1020.0)
		_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
		_poster = PK.poster(_page, Rect2(ox + 16, 14, pw, ph))
		_build_oath(pw, ph)
	else:
		var claim: Dictionary = war.claim
		ph = HEAD + 30.0 + CHART_H + 40.0 + CHAMP_H + 30.0 + (190.0 if not claim.is_empty() else 0.0) + 300.0
		ph = maxf(ph, d.y - 14.0 - 84.0)
		_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
		_poster = PK.poster(_page, Rect2(ox + 16, 14, pw, ph))
		_build_head(pw, war)
		var y := HEAD + 30.0
		_chart = FrontRelief.new()
		_chart.name = "Chart"
		_chart.position = Vector2(18, y)
		_chart.size = Vector2(pw - 36, CHART_H)
		_chart.set("war", war)
		_chart.set("grow", 0.0 if animate and Kit.motion_ok() else 1.0)
		_chart.connect("picked", _on_pick)
		_poster.add_child(_chart)
		if animate and Kit.motion_ok():
			var tw := _chart.create_tween()
			tw.tween_property(_chart, "grow", 1.0, 0.9).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		y += CHART_H + 40.0
		var ch: Dictionary = war.get("champion", {})
		if not ch.is_empty():
			_build_champion(pw, y, ch)
			y += CHAMP_H + 30.0
		if not claim.is_empty():
			_build_claim(pw, y, claim)
			y += 190.0
		_build_foot(pw, y, war)
	var fy := 14.0 + ph + 14.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sig := PK.t("the Front", 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	PK.at(_page, sig, Vector2(ox + w - 24 - 300, fy - 6))
	var back := SignalKit.back_button(func() -> void: UI.back(), str(war.side) == "")
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))


# ------------------------------------------------------------------ the Oath (no side yet)

func _build_oath(pw: float, ph: float) -> void:
	var p := _poster
	var half := floorf(pw * 0.5)
	# The two halves: Heaven on the paper, Hell on ink; each heroine's print fills her half.
	PK.rect(p, Rect2(half, 0, pw - half, ph), BAND_C)
	var ht := PK.halftone_print(HALO_FACE, "", Vector2(half, ph * 0.62), 7.0, Color(GOLD, 0.85))
	ht.position = Vector2(0, ph * 0.2)
	p.add_child(ht)
	var hr := PK.halftone_print(HORN_FACE, "", Vector2(pw - half, ph * 0.62), 7.0)
	hr.position = Vector2(half, ph * 0.2)
	p.add_child(hr)
	# HALO and HORN set as big as their halves allow.
	var fs := 170
	while fs > 60 and PK.text_w("HORN.", fs) > half - 40.0:
		fs -= 4
	PK.giant(p, "HALO", fs, Vector2(22, 112), Vector2(half, fs * 1.3), [[Rect2(0, 0, half, ph), INK]], 0, "compressed", false)
	PK.giant(p, "HORN[color=#%s].[/color]" % SIG.to_html(false), fs, Vector2(half + 22, 112), Vector2(pw - half, fs * 1.3),
		[[Rect2(half, 0, pw - half, ph), PAPER]], 0, "compressed", false)
	# Each side's heroine in full colour in front of her print, clipped to her half.
	for k in 2:
		var box := Control.new()
		box.name = "HeroBox"
		box.clip_contents = true
		box.mouse_filter = MOUSE_FILTER_IGNORE
		box.position = Vector2(0 if k == 0 else half, 112.0 + fs * 0.9)
		box.size = Vector2(half if k == 0 else pw - half, ph - 112.0 - fs * 0.9 - 150.0)
		p.add_child(box)
		PPK.hero_fig(box, HALO_FACE if k == 0 else HORN_FACE, "", Vector2(box.size.x * 0.5, box.size.y + 60.0), box.size.y * 1.05)
	var kick := PK.t("THE WAR FOR SOULS  ·  CHOOSE YOUR SIDE", 12, SIG, "mono_bold")
	kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kick.size = Vector2(pw, 16)
	kick.size = Vector2(pw - 170, 16)
	PK.at(p, kick, Vector2(150, 20))
	# The terms, small, on a paper strip under the heading (the heroines stand below it).
	var bg := ColorRect.new()
	bg.color = Color(PAPER, 0.94)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.position = Vector2(150, 42)
	bg.size = Vector2(pw - 170, 70)
	p.add_child(bg)
	var body := PK.t("Every victory sends souls to your side's front.
Both sides are rewarded every week, winners more.
Switch sides when a new week starts.", 10, INK, "mono")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size = Vector2(pw - 170, 70)
	PK.at(p, body, Vector2(150, 42))
	var specs := [
		["heaven", {"width": half - 36.0, "kicker": "THE OATH  //  HALO", "title": "HEAVEN", "sub": "THE CHOIR'S SIDE", "action": "SWEAR  >>>", "icon": "faction_celestial"}, 18.0],
		["hell", {"width": pw - half - 36.0, "kicker": "THE OATH  //  HORN", "title": "HELL", "sub": "THE PIT'S SIDE", "action": "SWEAR  >>>", "icon": "faction_infernal"}, half + 18.0],
	]
	for s: Array in specs:
		var side: String = s[0]
		Poster.pass_on(p, s[1], Vector2(float(s[2]), ph - 200.0), func() -> void: _choose(side), "Swear", "Swear_" + side,
			-0.03 if side == "heaven" else 0.03)


func _choose(side: String) -> void:
	var r: Dictionary = Game.war_choose_side(side)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "")), "bad")
		return
	Kit.sfx("tap")
	UI.haptic(30)
	UI.toast("You fight for %s" % WarRules.side_name(side), "good")


# ------------------------------------------------------------------ the front

func _build_head(pw: float, war: Dictionary) -> void:
	var p := _poster
	var side := str(war.side)
	PK.rect(p, Rect2(0, 0, BAND, HEAD), BAND_C)
	var face := HALO_FACE if side == "heaven" else HORN_FACE
	var ht := PK.halftone_print(face, "", Vector2(BAND, HEAD * 0.6), 6.0, Color(GOLD, 0.85) if side == "heaven" else PK.PRINT)
	ht.position = Vector2(0, HEAD * 0.4)
	p.add_child(ht)
	Poster.vlabel(p, "©2026 HH · THE WAR FOR SOULS", Vector2(24, 110), 10, Color(PAPER, 0.8))
	var title := "WAR[color=#%s].[/color]" % SIG.to_html(false)
	var fs := 200
	while fs > 80 and PK.text_w("WAR.", fs) > HEAD - 150.0:
		fs -= 4
	var gx := BAND + roundf(fs * 0.5)
	PK.giant(p, title, fs, Vector2(gx, 104), Vector2(HEAD, fs * 1.3), [[Rect2(0, 0, BAND, HEAD), PAPER],
		[Rect2(BAND, 0, gx - BAND + 6.0, HEAD), INK]], 0, "compressed", true)
	var x0 := gx + 22.0
	var tw := pw - x0 - 18.0
	PK.at(p, PK.t("YOU FIGHT FOR %s" % str(war.side_name).to_upper(), 12, SIG, "mono_bold"), Vector2(x0, 18))
	if Signature.has_ink(Game.signature()):
		# Sworn: the oath carries the player's signature.
		var sg := Signature.new()
		sg.strokes = Game.signature()
		sg.ink = Color(INK, 0.8)
		sg.weight = 2.4
		sg.size = Vector2(110, 30)
		sg.position = Vector2(x0 + 200, 4)
		p.add_child(sg)
	var wk := PK.t("WEEK %02d  ·  DAY %d / 7" % [int(war.week) + 1, int(war.day_in_week)], 12, INK, "mono_bold")
	wk.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wk.size = Vector2(tw, 16)
	PK.at(p, wk, Vector2(x0, 18))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 38))
	var st: Dictionary = war.standing
	var h := int(st.heaven)
	var e := int(st.hell)
	PK.at(p, PK.t("HEAVEN", 11, Color(INK, 0.7), "mono_bold"), Vector2(x0, 50))
	var hl := CK.deboss("%d" % h, 96, PAPER, "compressed", 2.0)
	PK.at(p, hl, Vector2(x0 - 2, 62))
	var el := PK.t("%d" % e, 96, SIG, "compressed")
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	el.size = Vector2(tw, 110)
	PK.at(p, el, Vector2(x0, 58))
	var hell_l := PK.t("HELL", 11, Color(INK, 0.7), "mono_bold")
	hell_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hell_l.size = Vector2(tw, 14)
	PK.at(p, hell_l, Vector2(x0, 50))
	var lead := "HOLDING" if str(st.winner) == str(war.side) else ("LOSING" if str(st.winner) != "" else "LEVEL")
	var mid := PK.t("SECTORS HELD  ·  %s" % lead, 10, Color(INK, 0.62), "mono")
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.size = Vector2(tw, 14)
	PK.at(p, mid, Vector2(x0, 120))
	var rows := [
		["YOUR SOULS TODAY", Kit.format_full(int(war.souls_today))],
		["THIS WEEK", Kit.format_full(int(war.souls_week))],
		["ALL TIME", Kit.format_full(int(war.souls_total))],
		["PER VICTORY", "+%d" % int(war.souls_per_win)],
		["WEEK ENDS IN", "%d DAY%s" % [int(war.days_left), "" if int(war.days_left) == 1 else "S"]],
	]
	PK.at(p, PPK.data_table(rows, tw, {"size": 11, "row_h": 22.0}), Vector2(x0, 168))
	# The oath allows a change of side at a week's start (no souls sent yet, last week claimed).
	if int(war.souls_week) == 0 and (war.claim as Dictionary).is_empty():
		var other := "hell" if str(war.side) == "heaven" else "heaven"
		var sw := PPK.print_button("CHANGE TO %s  ↗" % WarRules.side_name(other).to_upper(), _ask_switch.bind(other),
			{"size": Vector2(tw, 44), "text_size": 11, "align": "right"})
		sw.name = "SwitchSide"
		PK.at(p, sw, Vector2(x0, 276))
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


func _ask_switch(side: String) -> void:
	UI.confirm("Swear to %s for this week? Your souls go to its front until the next week starts." % WarRules.side_name(side),
		func() -> void:
			var r: Dictionary = Game.war_choose_side(side)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			Kit.sfx("stamp")
			UI.go("front"), Callable(), "Swear", "Stay")


func _on_pick(sector: int) -> void:
	var r: Dictionary = Game.war_set_focus(sector)
	if bool(r.get("ok", false)):
		Kit.sfx("tap")
		UI.haptic(14)


## The enemy Champion: a dark panel, her red print, her figure in front, her name and the week's bar.
func _build_champion(pw: float, y: float, ch: Dictionary) -> void:
	var p := _poster
	var panel := Control.new()
	panel.name = "Champion"
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.position = Vector2(18, y)
	panel.size = Vector2(pw - 36, CHAMP_H)
	p.add_child(panel)
	PK.rect(panel, Rect2(Vector2.ZERO, panel.size), BAND_C)
	var hero := str(ch.hero)
	var fig_w := floorf(panel.size.x * 0.48)
	var ht := PK.halftone_print(hero, "", Vector2(fig_w, CHAMP_H), 6.0)
	panel.add_child(ht)
	var box := Control.new()
	box.name = "HeroBox"
	box.clip_contents = true
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.size = Vector2(fig_w, CHAMP_H)
	panel.add_child(box)
	PPK.hero_fig(box, hero, "", Vector2(fig_w * 0.5, CHAMP_H + 40.0), CHAMP_H * 1.05)
	var x0 := fig_w + 18.0
	var tw := panel.size.x - x0 - 18.0
	PK.at(panel, PK.t("THE ENEMY CHAMPION  ·  THIS WEEK", 11, SIG, "mono_bold"), Vector2(x0, 18))
	var nm := str(ch.name).to_upper()
	var fs := 92
	while fs > 40 and PK.text_w(nm, fs) > tw:
		fs -= 4
	PK.at(panel, PK.t(nm, fs, PAPER, "compressed"), Vector2(x0 - 2, 34))
	PK.at(panel, PK.t("%s  ·  LV %d  ·  ★6  ·  BOSS" % [str(ch.title).to_upper(), int(ch.level)], 10, Color(PAPER, 0.7), "mono"), Vector2(x0, 36 + fs * 1.05))
	var yy := 60.0 + fs * 1.05
	PK.at(panel, PK.t("WORN DOWN THIS WEEK", 10, Color(PAPER, 0.7), "mono_bold"), Vector2(x0, yy))
	var pct := PK.t("%d%%" % int(ch.pct), 64, SIG, "compressed")
	PK.at(panel, pct, Vector2(x0 - 2, yy + 12))
	PK.at(panel, PK.t("%s / %s DAMAGE" % [Kit.format_num(int(ch.damage)), Kit.format_num(int(ch.hp))], 10, Color(PAPER, 0.7), "mono"), Vector2(x0, yy + 84))
	# The tiers as a list with their rewards, reached ones ticked in signal.
	var ty := yy + 110.0
	for t: Variant in ch.tiers:
		var td := t as Dictionary
		var on := bool(td.done)
		var parts: Array[String] = []
		for k: Variant in (td.reward as Dictionary):
			parts.append("%s %s" % [Kit.format_num(int(td.reward[k])), str(Kit.CURRENCY_SHORT.get(str(k), str(k))).to_upper()])
		var row := PK.t(("✓ " if on else "· ") + "%d%%   " % int(td.pct) + "  ".join(parts), 10, SIG if on else Color(PAPER, 0.8), "mono_bold" if on else "mono")
		row.size = Vector2(tw, 14)
		row.clip_text = true
		PK.at(panel, row, Vector2(x0, ty))
		ty += 18.0
	var left := int(ch.tries_left)
	PK.at(panel, PK.t("%d / 3 TRIES LEFT TODAY" % left, 11, PAPER if left > 0 else Color(PAPER, 0.5), "mono_bold"), Vector2(x0, CHAMP_H - 176.0))
	var spec := {"width": tw + 10.0, "kicker": "BOSS  //  45 S  //  DAMAGE COUNTS", "title": "FIGHT" if left > 0 else "RESTING",
		"sub": "THE CHAMPION  ·  %d LEFT" % left, "action": "ENGAGE  >>>" if left > 0 else "RESTS  ·  BACK AT MIDNIGHT", "icon": "sword", "disabled": left <= 0}
	Poster.pass_on(panel, spec, Vector2(x0 - 6.0, CHAMP_H - 150.0), func() -> void:
		if left > 0:
			UI.go("battle", {"mode": "champion"}), "Fight", "FightChampion")


func _build_claim(pw: float, y: float, claim: Dictionary) -> void:
	var p := _poster
	var won := bool(claim.won)
	var slip := Control.new()
	slip.name = "Claim"
	slip.mouse_filter = MOUSE_FILTER_IGNORE
	slip.position = Vector2(22, y)
	slip.size = Vector2(pw - 44, 160)
	slip.rotation = -0.012
	p.add_child(slip)
	PK.rect(slip, Rect2(3, 5, slip.size.x, slip.size.y), Color(0, 0, 0, 0.18))
	PK.rect(slip, Rect2(Vector2.ZERO, slip.size), SignalKit.MATTE)
	PK.rect(slip, Rect2(0, 0, 8, slip.size.y), SIG if won else INK)
	var winner := str(claim.winner)
	var head := "LAST WEEK  ·  " + ("%s HELD THE FRONT" % WarRules.side_name(winner).to_upper() if winner != "" else "THE FRONT HELD LEVEL")
	PK.at(slip, PK.t(head, 12, SIG if won else INK, "mono_bold"), Vector2(24, 16))
	PK.at(slip, PK.t("YOU WON" if won else "YOUR SHARE", 52, INK, "compressed"), Vector2(22, 34))
	var parts: Array[String] = []
	for k: Variant in (claim.reward as Dictionary):
		parts.append("%s %s" % [Kit.format_full(int(claim.reward[k])), str(Kit.CURRENCY_SHORT.get(str(k), str(k))).to_upper()])
	var rl := PK.t("  ·  ".join(parts) + "
%d SECTOR%s HELD" % [int(claim.held), "" if int(claim.held) == 1 else "S"], 11, Color(INK, 0.72), "mono")
	rl.size = Vector2(slip.size.x - 300.0, 40)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(slip, rl, Vector2(24, 104))
	Poster.pass_on(slip, {"width": 270.0, "kicker": "REWARD", "title": "CLAIM", "sub": "LAST WEEK", "action": "TAKE  >>>", "icon": "gift"},
		Vector2(slip.size.x - 280.0, 18.0), _claim, "Claim", "ClaimWar", 0.03)


func _claim() -> void:
	var r: Dictionary = Game.war_claim()
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "")), "bad")
		return
	UI.show_reward("Week claimed!", r.value.reward)


func _district_plate(at: Vector2, sz: Vector2, war: Dictionary) -> void:
	var root := Control.new()
	root.name = "District"
	root.position = at
	root.size = sz
	root.rotation = 0.025
	root.pivot_offset = sz * 0.5
	root.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.add_child(root)
	var silver := SignalKit.plate("silver", Vector2.ZERO, sz, {"topo": 0.5, "cuts": [12, 0, 12, 0],
		"screws": [Vector2(12, 12), Vector2(sz.x - 12, 12), Vector2(12, sz.y - 12), Vector2(sz.x - 12, sz.y - 12)]}, root)
	var kick := SignalKit.etch("YOUR QUARTER", 10, "mono_bold")
	kick.position = Vector2(22, 12)
	silver.add_child(kick)
	var m := DistrictModel.new()
	m.mini = true
	m.position = Vector2(8, 26)
	m.size = Vector2(sz.x - 16, (sz.x - 16) * 530.0 / 652.0)
	silver.add_child(m)
	m.set("dist", Game.district())
	var souls := SignalKit.etch("%s SOULS  ›" % Kit.format_num(int(war.souls_total)), 12, "mono_bold")
	souls.position = Vector2(22, sz.y - 30)
	silver.add_child(souls)
	var hit := Button.new()
	hit.name = "DistrictLink"
	hit.text = "District"
	hit.add_theme_color_override("font_color", Color.TRANSPARENT)
	hit.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	hit.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	hit.theme_type_variation = &"BareButton"
	hit.focus_mode = FOCUS_NONE
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.position = Vector2(-4, -4)
	hit.size = sz + Vector2(8, 8)
	hit.button_down.connect(func() -> void: (silver as SignalKit.Plate).set_pressed_look(true))
	hit.button_up.connect(func() -> void: (silver as SignalKit.Plate).set_pressed_look(false))
	hit.pressed.connect(func() -> void:
		Kit.sfx("tap")
		UI.go("district"))
	root.add_child(hit)


func _build_foot(pw: float, y: float, war: Dictionary) -> void:
	var p := _poster
	var focus: Dictionary = (war.sectors as Array)[int(war.focus)]
	var line := PK.t("Your souls go to %s. Tap a sector on the map to send them elsewhere." % str(focus.name), 14, INK, "serif_italic")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size = Vector2(pw - 60, 50)
	line.custom_minimum_size.x = pw - 60
	PK.at(p, line, Vector2(26, y))
	# The district: where the souls settle. A machined plate left of the FIGHT pass with a live
	# miniature of the quarter's model (owner, 2026-10-23: it was not obvious how to get there).
	_district_plate(Vector2(18, y + 66), Vector2(pw - 450.0 - 30.0, 220.0), war)
	var spec := {"width": 420.0, "kicker": "CAMPAIGN  //  +%d SOULS A WIN" % int(war.souls_per_win), "title": "FIGHT",
		"sub": "TO %s" % str(focus.name).to_upper(), "action": "ENGAGE  >>>", "icon": "sword"}
	Poster.pass_on(p, spec, Vector2(pw - 450.0, y + 110.0), func() -> void: UI.go("campaign"), "Fight", "FrontFight")
