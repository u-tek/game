extends Control
## Screen "district": the player's quarter on their side of the front (DistrictRules, GameModel
## district; docs/dev/combat-v1.md) in the house poster style, built like the exploded isometric map
## of reference 1: the quarter as a printed block plan in isometric line art (our own projection,
## drawn in 2D), each building a box on the ground grid, open ones inked and solid, the next one in
## signal, later ones as dashed outlines with the souls they need; each keeper's portrait framed on
## a leader line over her building. Under the plan, the ledger: one row per building (name, its idle
## bonus, its keeper or "NO KEEPER"), tap a row to choose a keeper (a sheet of owned heroines, the
## side's faction first: they double the bonus). The head: the quarter's name huge on the band, the
## lifetime souls debossed, the idle bonus per currency, the next building and the souls it needs.
## params: keeper (a building index: opens its keeper sheet; screenshots).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const GOLD := Color(0.86, 0.66, 0.24)
const BAND_C := Color("141517")
const BAND := 132.0
const HEAD := 300.0
const PLAN_H := 530.0
const ROW_H := 74.0
const MAX_W := 760.0

var _scroll: ScrollContainer
var _page: Control
var _poster: Control
var _built := Vector2.ZERO
var _rebuild_queued := false
var _sheet: Control


func setup(params: Dictionary) -> void:
	if str(Game.war().side) == "":
		UI.toast("Swear to a side on the front first", "info")
		UI.go("front")
		return
	_build()
	Game.changed.connect(_on_changed)
	resized.connect(_on_resized)
	# Screenshots: keeper = a building index opens its keeper sheet.
	if params.has("keeper"):
		_pick_keeper.call_deferred(int(params.keeper))


func _exit_tree() -> void:
	if Game.changed.is_connected(_on_changed):
		Game.changed.disconnect(_on_changed)
	if _sheet and is_instance_valid(_sheet):
		UI.close_modal(_sheet)


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
	_build()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


func _build() -> void:
	var d := _dims()
	_built = d
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	var pw := w - 32.0
	var dist: Dictionary = Game.district()
	var bl: Array = dist.buildings
	var ph := maxf(HEAD + 30.0 + PLAN_H + 30.0 + bl.size() * ROW_H + 60.0, d.y - 14.0 - 84.0)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
	_scroll = Kit.scroll(_page)
	_scroll.name = "District"
	_scroll.size = d
	add_child(_scroll)
	var pr := Rect2(ox + 16, 14, pw, ph)
	_poster = PK.poster(_page, pr)
	_build_head(pw, dist)
	var plan := DistrictPlan.new()
	plan.name = "Plan"
	plan.position = Vector2(18, HEAD + 30.0)
	plan.size = Vector2(pw - 36, PLAN_H)
	plan.set("dist", dist)
	_poster.add_child(plan)
	_keeper_prints(plan, dist)
	_build_ledger(pw, HEAD + 30.0 + PLAN_H + 30.0, dist)
	var fy := pr.end.y + 14.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sig := PK.t("the Quarter", 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	PK.at(_page, sig, Vector2(ox + w - 24 - 300, fy - 6))
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))


func _build_head(pw: float, dist: Dictionary) -> void:
	var p := _poster
	var side := str(dist.side)
	PK.rect(p, Rect2(0, 0, BAND, HEAD), BAND_C)
	Poster.vlabel(p, "©2026 HH · THE WAR FOR SOULS · DISTRICT", Vector2(24, 110), 10, Color(PAPER, 0.8))
	var word := "HALO" if side == "heaven" else "HORN"
	var title := "%s[color=#%s].[/color]" % [word, SIG.to_html(false)]
	var fs := 200
	# Measured type runs short of the set giant; fit with room to spare so the full stop shows.
	while fs > 60 and PK.text_w(word + ".", fs) * 1.45 > HEAD - 120.0:
		fs -= 4
	var gx := BAND + roundf(fs * 0.5)
	PK.giant(p, title, fs, Vector2(gx, 104), Vector2(HEAD, fs * 1.3), [[Rect2(0, 0, BAND, HEAD), PAPER],
		[Rect2(BAND, 0, gx - BAND + 6.0, HEAD), INK]], 0, "compressed", true)
	var x0 := gx + 22.0
	var tw := pw - x0 - 18.0
	PK.at(p, PK.t(str(dist.name).to_upper(), 12, SIG, "mono_bold"), Vector2(x0, 18))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 38))
	PK.at(p, PK.t("SOULS SETTLED", 10, Color(INK, 0.7), "mono_bold"), Vector2(x0, 48))
	PK.at(p, CK.deboss(Kit.format_num(int(dist.souls)), 80, PAPER, "compressed", 2.0), Vector2(x0 - 2, 60))
	var parts: Array[String] = []
	for k: Variant in (dist.bonus as Dictionary):
		parts.append("+%s%% %s" % [_pct(int(dist.bonus[k])), str(Kit.CURRENCY_SHORT.get(str(k), str(k))).to_upper()])
	var bonus := PK.t("IDLE  " + ("  ·  ".join(parts) if not parts.is_empty() else "NO BONUS YET"), 11, INK, "mono_bold")
	bonus.size = Vector2(tw, 32)
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(p, bonus, Vector2(x0, 160))
	var nxt: Dictionary = dist.next
	var nl := ("NEXT  %s AT %s SOULS" % [str(nxt.name).to_upper(), Kit.format_num(int(nxt.souls))]) if not nxt.is_empty() else "EVERY BUILDING OPEN"
	PK.at(p, PK.t(nl, 10, Color(INK, 0.7), "mono"), Vector2(x0, 200))
	var kf := "A CELESTIAL OR FALLEN" if side == "heaven" else "AN INFERNAL OR FALLEN"
	var kl := PK.t("%s KEEPER DOUBLES A BUILDING'S BONUS." % kf, 10, Color(INK, 0.7), "mono")
	kl.size = Vector2(tw, 30)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PK.at(p, kl, Vector2(x0, 220))
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


static func _pct(bp: int) -> String:
	return ("%d" % (bp / 100)) if bp % 100 == 0 else ("%.1f" % (bp / 100.0))


## Each keeper's portrait framed over her building, on a leader line from its roof.
func _keeper_prints(plan: Control, dist: Dictionary) -> void:
	for b: Variant in dist.buildings:
		var bd := b as Dictionary
		var hid := str(bd.keeper)
		if hid == "" or not bool(bd.open):
			continue
		var roof: Vector2 = plan.call("roof_point", int(bd.i))
		var s := 64.0
		var at := roof + Vector2(-s * 0.5, -s - 40.0)
		var fr := Control.new()
		fr.mouse_filter = MOUSE_FILTER_IGNORE
		fr.position = at
		fr.size = Vector2(s, s)
		plan.add_child(fr)
		PK.rect(fr, Rect2(-2, -2, s + 4, s + 4), SIG if bool(bd.doubled) else INK)
		var pic := HeroArt.make_portrait(hid, s, Game.equipped_skin(hid))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.size = Vector2(s, s)
		fr.add_child(pic)


func _build_ledger(pw: float, y: float, dist: Dictionary) -> void:
	var p := _poster
	PK.at(p, PK.t("THE LEDGER  ·  TAP A BUILDING TO CHOOSE ITS KEEPER", 11, INK, "mono_bold"), Vector2(24, y - 22))
	for b: Variant in dist.buildings:
		var bd := b as Dictionary
		var open := bool(bd.open)
		var row := Control.new()
		row.name = "Building_%d" % int(bd.i)
		row.mouse_filter = MOUSE_FILTER_PASS
		row.position = Vector2(20, y)
		row.size = Vector2(pw - 40, ROW_H - 6)
		p.add_child(row)
		PK.rect(row, Rect2(Vector2.ZERO, row.size), Color("f5f4f0") if open else Color(INK, 0.04))
		PK.rect(row, Rect2(0, 0, 5, row.size.y), (SIG if bool(bd.doubled) else INK) if open else Color(INK, 0.2))
		PK.at(row, PK.t("%02d" % (int(bd.i) + 1), 24, INK if open else Color(INK, 0.35), "compressed"), Vector2(16, 14))
		PK.at(row, PK.t(str(bd.name).to_upper(), 15, INK if open else Color(INK, 0.45), "mono_bold"), Vector2(60, 12))
		var cur := str(Kit.CURRENCY_SHORT.get(str(bd.currency), str(bd.currency))).to_upper()
		var sub := ("+%s%% %s IDLE" % [_pct(int(bd.bonus_bp)), cur]) + ("  ·  DOUBLED" if bool(bd.doubled) else "") if open \
			else "OPENS AT %s SOULS  ·  +%s%% %s" % [Kit.format_num(int(bd.souls)), _pct(int(bd.bonus_bp)), cur]
		PK.at(row, PK.t(sub, 10, SIG if bool(bd.doubled) else Color(INK, 0.7), "mono"), Vector2(60, 36))
		var hid := str(bd.keeper)
		var kl := PK.t(str(Game.hero_def(hid).get("name", "")).to_upper() if hid != "" else ("NO KEEPER  ›" if open else ""), 12,
			INK if hid != "" else SIG, "mono_bold")
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kl.size = Vector2(220, 16)
		PK.at(row, kl, Vector2(row.size.x - 300, 24))
		if hid != "":
			var pic := HeroArt.make_portrait(hid, 54, Game.equipped_skin(hid))
			pic.mouse_filter = MOUSE_FILTER_IGNORE
			pic.position = Vector2(row.size.x - 64, 7)
			pic.size = Vector2(54, 54)
			row.add_child(pic)
		if open:
			var bi := int(bd.i)
			Kit.make_tappable(row, func() -> void: _pick_keeper(bi))
		y += ROW_H


## The keeper sheet: owned heroines, the side's faction first (they double), tap one to place her.
func _pick_keeper(building: int) -> void:
	var dist: Dictionary = Game.district()
	var side := str(dist.side)
	var b: Dictionary = (dist.buildings as Array)[building]
	var ids: Array[String] = []
	for h: Dictionary in Game.owned_heroes():
		ids.append(str(h.id))
	ids.sort_custom(func(a: String, c: String) -> bool:
		var ma := DistrictRules.kept_mult(side, str(Game.hero_def(a).get("faction", ""))) > 10000
		var mc := DistrictRules.kept_mult(side, str(Game.hero_def(c).get("faction", ""))) > 10000
		return ma and not mc if ma != mc else a < c)
	var col := Kit.vbox(10)
	col.custom_minimum_size.x = 560
	col.add_child(PK.t("%s  ·  +%s%% %s IDLE" % [str(b.name).to_upper(), _pct(int(DistrictRules.BUILDINGS[building].bonus_bp)),
		str(Kit.CURRENCY_SHORT.get(str(b.currency), "")).to_upper()], 12, INK, "mono_bold"))
	col.add_child(PK.t("Heroines marked x2 double it.", 13, Color(INK, 0.7), "serif_italic"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	sc.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	var modal_ref: Array[Control] = []
	if str(b.keeper) != "":
		var clear := Kit.light_button("No keeper", func() -> void:
			Game.district_set_keeper(building, "")
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0]), "close")
		col.add_child(clear)
	for id in ids:
		var card := Control.new()
		card.custom_minimum_size = Vector2(130, 166)
		card.mouse_filter = MOUSE_FILTER_PASS
		var pic := HeroArt.make_portrait(id, 130, Game.equipped_skin(id))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.size = Vector2(130, 130)
		card.add_child(pic)
		var nm := PK.t(str(Game.hero_def(id).get("name", id)).to_upper(), 10, INK, "mono_bold")
		nm.position = Vector2(0, 134)
		nm.size = Vector2(130, 14)
		nm.clip_text = true
		card.add_child(nm)
		if DistrictRules.kept_mult(side, str(Game.hero_def(id).get("faction", ""))) > 10000:
			var x2 := PK.t("x2", 14, PAPER, "mono_bold")
			var tag := ColorRect.new()
			tag.color = SIG
			tag.size = Vector2(34, 22)
			tag.mouse_filter = MOUSE_FILTER_IGNORE
			card.add_child(tag)
			x2.position = Vector2(6, 1)
			card.add_child(x2)
		if id == str(b.keeper):
			var on := ColorRect.new()
			on.color = Color(SIG, 0.25)
			on.size = Vector2(130, 130)
			on.mouse_filter = MOUSE_FILTER_IGNORE
			card.add_child(on)
		var hid := id
		Kit.make_tappable(card, func() -> void:
			var r: Dictionary = Game.district_set_keeper(building, hid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			Kit.sfx("tap")
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0]))
		grid.add_child(card)
	_sheet = UI.popup("Keeper", col, func() -> void: _sheet = null, 640.0, true)
	modal_ref.append(_sheet)


## The quarter's block plan: buildings as boxes on an isometric ground grid (ink line art on paper).
class DistrictPlan:
	extends Control

	const INK := Color("101113")
	const PAPER := Color("e9e8e2")
	const SIG := Color("ff4b1f")
	## Grid spots (cell x, cell y) for each building, in data order: a small street plan.
	const SPOTS := [Vector2i(3, 6), Vector2i(0, 5), Vector2i(5, 5), Vector2i(0, 1), Vector2i(6, 1), Vector2i(2, 0), Vector2i(5, 0), Vector2i(7, 0)]
	const CELL := 46.0
	const GRID := 8
	const UNIT_H := 22.0

	var dist: Dictionary = {}

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	## Ground point (iso) for grid coords (x, y) and height z (px).
	func _iso(x: float, y: float, z: float = 0.0) -> Vector2:
		var o := Vector2(size.x * 0.5, 130.0)
		return o + Vector2((x - y) * CELL * 0.866, (x + y) * CELL * 0.5 - z)

	## The middle of a building's roof (for the keeper prints' leaders).
	func roof_point(i: int) -> Vector2:
		var b: Dictionary = (dist.buildings as Array)[i]
		var s: Vector2i = SPOTS[i % SPOTS.size()]
		return _iso(s.x + int(b.w) * 0.5, s.y + int(b.d) * 0.5, int(b.h) * UNIT_H)

	func _draw() -> void:
		# The ground: a paper slab with the street grid and the souls' road through the middle.
		var g := PackedVector2Array([_iso(0, 0), _iso(GRID, 0), _iso(GRID, GRID), _iso(0, GRID)])
		draw_colored_polygon(g, Color("f5f4f0"))
		var slab := PackedVector2Array([_iso(GRID, 0), _iso(GRID, GRID), _iso(GRID, GRID, -18), _iso(GRID, 0, -18)])
		draw_colored_polygon(slab, Color(INK, 0.15))
		var slab2 := PackedVector2Array([_iso(0, GRID), _iso(GRID, GRID), _iso(GRID, GRID, -18), _iso(0, GRID, -18)])
		draw_colored_polygon(slab2, Color(INK, 0.28))
		for k in GRID + 1:
			draw_line(_iso(k, 0), _iso(k, GRID), Color(INK, 0.12), 1.0, true)
			draw_line(_iso(0, k), _iso(GRID, k), Color(INK, 0.12), 1.0, true)
		draw_polyline(PackedVector2Array([_iso(0, 3.5), _iso(GRID, 3.5)]), Color(SIG, 0.5), 6.0, true)
		draw_polyline(g + PackedVector2Array([g[0]]), INK, 1.5, true)
		# Buildings, back to front.
		var order: Array = range((dist.get("buildings", []) as Array).size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var sa: Vector2i = SPOTS[a % SPOTS.size()]
			var sb: Vector2i = SPOTS[b % SPOTS.size()]
			return sa.x + sa.y < sb.x + sb.y)
		var next_shown := false
		var f := Kit.font("mono_bold")
		for i: int in order:
			var b: Dictionary = (dist.buildings as Array)[i]
			var s: Vector2i = SPOTS[i % SPOTS.size()]
			var w := int(b.w)
			var d := int(b.d)
			var h := int(b.h) * UNIT_H
			var open := bool(b.open)
			var is_next := not open and int(b.souls) == int((dist.get("next", {}) as Dictionary).get("souls", -1))
			var top := PackedVector2Array([_iso(s.x, s.y, h), _iso(s.x + w, s.y, h), _iso(s.x + w, s.y + d, h), _iso(s.x, s.y + d, h)])
			var right := PackedVector2Array([_iso(s.x + w, s.y, 0), _iso(s.x + w, s.y + d, 0), _iso(s.x + w, s.y + d, h), _iso(s.x + w, s.y, h)])
			var left := PackedVector2Array([_iso(s.x, s.y + d, 0), _iso(s.x + w, s.y + d, 0), _iso(s.x + w, s.y + d, h), _iso(s.x, s.y + d, h)])
			if open:
				draw_colored_polygon(left, INK)
				draw_colored_polygon(right, Color(INK, 0.78))
				draw_colored_polygon(top, PAPER if not bool(b.doubled) else Color(SIG, 0.9))
				# Window ticks down the left face.
				for k in int(b.h):
					var y0 := (k + 0.5) * UNIT_H
					draw_line(_iso(s.x + 0.25, s.y + d, y0), _iso(s.x + w - 0.25, s.y + d, y0), Color(PAPER, 0.35), 1.0, true)
				draw_polyline(top + PackedVector2Array([top[0]]), INK, 1.5, true)
			else:
				var col := SIG if is_next else Color(INK, 0.35)
				for poly: PackedVector2Array in [left, right, top]:
					_dashed(poly + PackedVector2Array([poly[0]]), col)
				var lab := "%s SOULS" % Kit.format_num(int(b.souls))
				draw_string(f, top[0] + Vector2(-10, -10), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
				if is_next and not next_shown:
					next_shown = true
			# The building's number on its roof.
			draw_string(f, (top[0] + top[2]) * 0.5 + Vector2(-8, 5), "%02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				(PAPER if bool(b.doubled) else INK) if open else Color(INK, 0.4))
		# Leaders from each keeper's print down to her roof.
		for i: int in order:
			var b: Dictionary = (dist.buildings as Array)[i]
			if str(b.keeper) != "" and bool(b.open):
				var r := roof_point(i) + Vector2(0, -12)
				draw_line(r, r + Vector2(0, -28), SIG if bool(b.doubled) else INK, 1.5, true)

	func _dashed(pts: PackedVector2Array, col: Color) -> void:
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 8.0))
			for j in n:
				if j % 2 == 0:
					draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), col, 1.4, true)
