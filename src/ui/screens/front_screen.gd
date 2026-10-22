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
##   chart the seven sectors as columns between HEAVEN (paper, gold dots) and HELL (ink, red dots), the
##         front line a jagged trench running across at each sector's control, each sector's name on
##         its side and its control in mono at the line; the player's sector carries a signal pin and
##         a light stripe; tap a column to send your souls there; the line rises from neutral when the
##         screen opens;
##   claim last week's result as a stuck-on slip with a CLAIM pass (when there is one);
##   foot  the FIGHT pass to the campaign (every win sends souls_per_win souls), the date, a signature.
## params: scroll (px, screenshots).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")
const PPK := preload("res://src/ui/v4/poster_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color(0.86, 0.66, 0.24)
const BAND_C := Color("141517")
const BAND := 132.0
const HEAD := 330.0
const CHART_H := 640.0
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
		ph = HEAD + 30.0 + CHART_H + 40.0 + (190.0 if not claim.is_empty() else 0.0) + 300.0
		ph = maxf(ph, d.y - 14.0 - 84.0)
		_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
		_poster = PK.poster(_page, Rect2(ox + 16, 14, pw, ph))
		_build_head(pw, war)
		var y := HEAD + 30.0
		_chart = FrontChart.new()
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
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


func _on_pick(sector: int) -> void:
	var r: Dictionary = Game.war_set_focus(sector)
	if bool(r.get("ok", false)):
		Kit.sfx("tap")
		UI.haptic(14)


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
	PK.rect(slip, Rect2(Vector2.ZERO, slip.size), Color("f5f4f0"))
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
	rl.size = Vector2(slip.size.x - 260.0, 40)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(slip, rl, Vector2(24, 104))
	var pass_root := Poster.pass_on(slip, {"width": 230.0, "kicker": "REWARD", "title": "CLAIM", "sub": "", "action": "TAKE  >>>", "icon": "gift"},
		Vector2(slip.size.x - 246.0, 40.0), _claim, "Claim", "ClaimWar", 0.03)
	pass_root.scale = Vector2(0.8, 0.8)


func _claim() -> void:
	var r: Dictionary = Game.war_claim()
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "")), "bad")
		return
	UI.show_reward("Week claimed!", r.value.reward)


func _build_foot(pw: float, y: float, war: Dictionary) -> void:
	var p := _poster
	var focus: Dictionary = (war.sectors as Array)[int(war.focus)]
	var line := PK.t("Your souls go to %s. Tap a sector on the map to send them elsewhere." % str(focus.name), 14, INK, "serif_italic")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size = Vector2(pw - 60, 50)
	line.custom_minimum_size.x = pw - 60
	PK.at(p, line, Vector2(26, y))
	var spec := {"width": 420.0, "kicker": "CAMPAIGN  //  +%d SOULS A WIN" % int(war.souls_per_win), "title": "FIGHT",
		"sub": "TO %s" % str(focus.name).to_upper(), "action": "ENGAGE  >>>", "icon": "sword"}
	Poster.pass_on(p, spec, Vector2(pw - 450.0, y + 80.0), func() -> void: UI.go("campaign"), "Fight", "FrontFight")


# ------------------------------------------------------------------ the chart

## The war map: seven sector columns between HEAVEN (top) and HELL (bottom); the front line at each
## sector's control (positive pushes it down into Hell's half). Tap a column: picked(sector).
class FrontChart:
	extends Control
	signal picked(sector: int)

	const INK := Color("101113")
	const PAPER := Color("e9e8e2")
	const SIG := Color("ff4b1f")
	const GOLD := Color(0.86, 0.66, 0.24)
	const BAND_C := Color("141517")
	const TOP := 54.0
	const FOOT := 40.0

	var war: Dictionary = {}
	## 0..1: how far the line has risen from neutral (the opening animation).
	var grow := 1.0:
		set(v):
			grow = v
			queue_redraw()

	var _down := Vector2.INF

	func _init() -> void:
		# PASS: a drag over the map still scrolls the page; only a tap (little movement) picks.
		mouse_filter = MOUSE_FILTER_PASS

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_down = mb.position
			return
		if _down != Vector2.INF and mb.position.distance_to(_down) < 14.0:
			var n := (war.get("sectors", []) as Array).size()
			if n > 0:
				picked.emit(clampi(int(mb.position.x / (size.x / n)), 0, n - 1))
		_down = Vector2.INF

	## The line's y for a control value (bp): the middle at 0, pushed down by Heaven, up by Hell.
	func _line_y(c: int) -> float:
		var mid := TOP + (size.y - TOP - FOOT) * 0.5
		return mid + float(c) / 10000.0 * (size.y - TOP - FOOT) * 0.44 * grow

	func _draw() -> void:
		var secs: Array = war.get("sectors", [])
		var n := secs.size()
		if n == 0:
			return
		var cw := size.x / n
		var y0 := TOP
		var y1 := size.y - FOOT
		var f := Kit.font("mono_bold")
		var fc := Kit.font("compressed")
		# Paper above (Heaven), ink below (Hell), split at the line, with dots of each side's ink.
		var pts := PackedVector2Array()
		for i in n:
			var c := int((secs[i] as Dictionary).control)
			pts.append(Vector2(i * cw, _line_y(c)))
			pts.append(Vector2((i + 1) * cw, _line_y(c)))
		draw_rect(Rect2(0, y0, size.x, y1 - y0), Color("f5f4f0"))
		var hell := PackedVector2Array(pts)
		hell.append(Vector2(size.x, y1))
		hell.append(Vector2(0, y1))
		draw_colored_polygon(hell, BAND_C)
		var step := 11.0
		var yy := y0 + 6.0
		while yy < y1:
			var xx := fmod(yy * 0.5, step)
			while xx < size.x:
				var i := clampi(int(xx / cw), 0, n - 1)
				var ly := _line_y(int((secs[i] as Dictionary).control))
				var k := clampf(absf(yy - ly) / ((y1 - y0) * 0.5), 0.0, 1.0)
				var r := 1.0 + 2.6 * (1.0 - k)
				if yy < ly - 3.0:
					draw_circle(Vector2(xx, yy), r, Color(GOLD, 0.55), true, -1.0, true)
				elif yy > ly + 3.0:
					draw_circle(Vector2(xx, yy), r, Color(SIG, 0.75), true, -1.0, true)
				xx += step
			yy += step
		# The player's sector: a light stripe down its column.
		var fo := int(war.get("focus", -1))
		if fo >= 0 and fo < n:
			draw_rect(Rect2(fo * cw + 4, y0, cw - 8, y1 - y0), Color(SIG, 0.12))
			draw_rect(Rect2(fo * cw + 4, y0, 2, y1 - y0), Color(SIG, 0.8))
			draw_rect(Rect2((fo + 1) * cw - 6, y0, 2, y1 - y0), Color(SIG, 0.8))
		# Column rules and the trench line (jagged, with ticks toward Hell).
		for i in range(1, n):
			draw_line(Vector2(i * cw, y0), Vector2(i * cw, y1), Color(INK, 0.25), 1.0)
		var prev := Vector2.INF
		for i in n:
			var ly := _line_y(int((secs[i] as Dictionary).control))
			var a := Vector2(i * cw, ly)
			if prev != Vector2.INF:
				draw_line(prev, a, INK, 3.0, true)
			var x := i * cw
			var j := 0
			while x < (i + 1) * cw:
				var dy := 5.0 if j % 2 == 0 else -5.0
				var nx := minf(x + 9.0, (i + 1) * cw)
				draw_line(Vector2(x, ly + (0.0 if j == 0 else -dy)), Vector2(nx, ly + dy), INK, 3.0, true)
				x = nx
				j += 1
			prev = Vector2((i + 1) * cw, ly)
		# Headings: HEAVEN at the top, HELL at the foot; each sector's name turned on its side.
		draw_string(fc, Vector2(6, 40), "HEAVEN", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, INK)
		draw_string(f, Vector2(size.x - 200, 30), "↓ HEAVEN PUSHES DOWN", HORIZONTAL_ALIGNMENT_RIGHT, 194, 10, Color(INK, 0.6))
		draw_string(fc, Vector2(6, size.y - 6), "HELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, SIG)
		draw_string(f, Vector2(size.x - 200, size.y - 14), "↑ HELL PUSHES UP", HORIZONTAL_ALIGNMENT_RIGHT, 194, 10, Color(INK, 0.6))
		for i in n:
			var s: Dictionary = secs[i]
			var c := int(s.control)
			var ly := _line_y(c)
			# The control in mono on a paper tag just under the line.
			var pct := "%+d%%" % roundi(float(c) / 100.0) if c != 0 else "0%"
			var tag := Rect2(i * cw + cw * 0.5 - 26, minf(ly + 10.0, y1 - 22.0), 52, 18)
			draw_rect(tag, Color(PAPER, 0.96))
			draw_rect(Rect2(tag.position, Vector2(3, tag.size.y)), GOLD if c > 0 else (SIG if c < 0 else INK))
			draw_string(f, tag.position + Vector2(6, 13), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
			# The name, turned, in the Heaven half (ink) above the tag.
			draw_set_transform(Vector2(i * cw + cw * 0.5 + 5, y0 + 10), PI * 0.5, Vector2.ONE)
			draw_string(f, Vector2.ZERO, str(s.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# The pin on the player's sector: a signal flag standing on the line, in the Heaven half.
		if fo >= 0 and fo < n:
			var ly := _line_y(int((secs[fo] as Dictionary).control))
			var px := fo * cw + cw * 0.5
			var top := maxf(ly - 74.0, y0 + 150.0)
			draw_line(Vector2(px, ly - 6), Vector2(px, top), SIG, 3.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(px, top), Vector2(px + 34, top + 10), Vector2(px, top + 20)]), SIG)
			draw_rect(Rect2(px - 44, top - 26, 88, 18), Color(PAPER, 0.96))
			draw_string(f, Vector2(px - 44, top - 12), "YOUR SOULS", HORIZONTAL_ALIGNMENT_CENTER, 88, 10, SIG)
		draw_rect(Rect2(0, y0, size.x, y1 - y0), Color(INK, 0.8), false, 2.0)
