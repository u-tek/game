extends Control
## The Campaign's chapter select (style v4 "Signal", poster look; docs/dev/ui-style-v4.md), built like
## the owner's planet-dossier reference: each chapter is a world. The chapter's planet turns in the
## middle of a printed instrument (WorldView: the Blender-baked planet in real time, ring arcs, ticks,
## "Loading ...", the MASS tag, a barcode ring, a progress gauge); the next world peeks in from the
## right edge; the catalogue mark sits top right ("01  S1 |"); under the planet the chapter name runs
## huge between ‹ › arrows over a pale band with the chapter number ghosted behind it, then a
## two-column mono data list (host, stages cleared, enemy levels and grades, recommended power, the
## counter faction, the boss; then the world's terrain class and flavour readouts from
## data/worlds.json). The ENTER pass is stuck on bottom right; a locked world is stamped LOCKED
## and says which stage opens it.
##
##   var d := WorldDossier.new(); d.size = poster_size; poster.add_child(d); d.build(ci)
##   d.enter_pressed.connect(...)   # the planet or the pass: zoom into the survey map
##   d.switch_pressed.connect(...)  # ‹ › or the neighbour planet: show another chapter
##
## dive(then) plays the zoom into the planet (the line work and type fade, the planet grows past the
## poster) and calls `then`; arrive() plays it backwards when coming out of a map.

signal enter_pressed
signal switch_pressed(chapter_index: int)

const WorldView := preload("res://src/ui/v4/survey/world_view.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const StageInfo := preload("res://src/ui/battle/stage_info.gd")
const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIGNAL := Color("ff4b1f")

var chapter := 0
var world_view: WorldView
var enter_button: Button
var _chrome: Control
var _neighbor: WorldView
## Debug builds (screenshots): print the world as open even when it is still locked.
var look_open := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true


## The world record for chapter ci from data/worlds.json ({} when missing).
static func world_of(ci: int) -> Dictionary:
	var ws: Array = GameData.worlds().get("worlds", [])
	return ws[ci] if ci >= 0 and ci < ws.size() else {}


func build(ci: int) -> void:
	chapter = ci
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var chs := Game.chapters()
	var ch: Dictionary = chs[ci]
	var wd := world_of(ci)
	var pw := size.x
	var ph := size.y
	var first := int(ch.get("first_stage", 0))
	var count := int(ch.get("stage_count", 10))
	var done := clampi(Game.cleared_count() - first, 0, count)
	var locked := Game.stage_status(first) == "locked" and not look_open
	var faction := str(ch.get("faction", "celestial"))
	var n := int(wd.get("world", ci + 1))
	var r := clampf(pw * 0.255, 140.0, 186.0)
	var c := Vector2(pw * 0.44, 104.0 + r)

	# The next world peeks in from the right edge (drawn first: the main world sits over it).
	if ci + 1 < chs.size():
		_neighbor = WorldView.new()
		_neighbor.bare = true
		_neighbor.world = int(world_of(ci + 1).get("world", ci + 2))
		_neighbor.locked = Game.stage_status(int(chs[ci + 1].get("first_stage", 0))) == "locked"
		_neighbor.radius = r * 0.8
		_neighbor.center = Vector2(pw + r * 0.38, c.y + r * 0.08)
		_neighbor.size = Vector2(pw + r * 2.0, ph)
		_neighbor.name = "NextWorld"
		_neighbor.pressed.connect(func() -> void: switch_pressed.emit(ci + 1))
		add_child(_neighbor)

	# The world itself, with its instrument.
	world_view = WorldView.new()
	world_view.name = "World"
	world_view.world = n
	world_view.locked = locked
	world_view.center = c
	world_view.radius = r
	world_view.progress = float(done) / maxf(float(count), 1.0)
	world_view.mass_text = str(wd.get("mass", ""))
	world_view.id_text = "ID %s-%03d" % [str(wd.get("code", "W")), (ci + 1) * 7]
	world_view.loading_text = "Signal lost ..." if locked else "Loading ..."
	world_view.size = Vector2(pw, ph)
	world_view.pressed.connect(func() -> void: enter_pressed.emit())
	add_child(world_view)

	_chrome = Control.new()
	_chrome.name = "Dossier"
	_chrome.mouse_filter = MOUSE_FILTER_IGNORE
	_chrome.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_chrome)
	var p := _chrome

	# The catalogue mark, top right: the world number small, its code large and thin, a cursor bar.
	var code := str(wd.get("code", "W%d" % n))
	var big := Poster.tv(code, 88, INK, 140.0, 88.0)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	big.size = Vector2(200, 100)
	Poster.at(p, big, Vector2(pw - 60 - 200, 0))
	Poster.rect(p, Rect2(pw - 46, 26, 1.5, 64), INK)
	var sup := Poster.t("%02d" % (ci + 1), 12, Color(INK, 0.55), "mono")
	sup.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sup.size = Vector2(60, 16)
	var cw := big.get_theme_font("font").get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, 88).x
	Poster.at(p, sup, Vector2(pw - 60 - cw - 66, 30))
	# Small marks at the top: a tick at the centre, the sheet's corner brackets.
	Poster.rect(p, Rect2(pw * 0.5, 10, 1, 12), Color(INK, 0.6))
	_bracket(p, Vector2(pw - 18, 12), -1.0, 1.0)
	# Micro type down the left edge.
	Poster.vlabel(p, "©2026 HH, WORLD SURVEY %02d/%02d. ALL RIGHTS RESERVED." % [ci + 1, chs.size()], Vector2(24, 126), 10, Color(INK, 0.7))

	# The name row: a pale band, the chapter number ghosted huge behind, the name between ‹ ›.
	var ny := c.y + r * 1.34
	Poster.rect(p, Rect2(0, ny - 8, pw, 104), Color(INK, 0.045))
	var ghost := Poster.tv("%02d" % (ci + 1), 230, INK, 900.0, 62.0)
	ghost.modulate.a = 0.045
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ghost.size = Vector2(300, 220)
	Poster.at(p, ghost, Vector2(pw - 318, ny - 70))
	var name_txt := str(ch.get("name", "")).to_upper()
	var nm := Poster.tv(name_txt, 104, INK, 820.0, 62.0)
	Kit.fit_label(nm, pw - 124, 104, 44)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nfs := nm.get_theme_font_size("font_size")
	var nh := float(nfs) * 1.2
	nm.size = Vector2(pw - 100, nh)
	Poster.at(p, nm, Vector2(50, ny + 44 - nfs * 0.62 + 52.0 - nh * 0.5))
	var nw := nm.get_theme_font("font").get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	var nx0 := 50.0 + (pw - 100 - nw) * 0.5
	_arrow(p, Vector2(maxf(nx0 - 24.0, 18.0), ny + 46.0), -1, ci > 0, func() -> void: switch_pressed.emit(ci - 1), "PrevWorld")
	_arrow(p, Vector2(minf(nx0 + nw + 24.0, pw - 18.0), ny + 46.0), 1, ci + 1 < chs.size(), func() -> void: switch_pressed.emit(ci + 1), "NextWorldArrow")
	Poster.rect(p, Rect2(nx0, ny + 100, 72, 2), INK)
	var sub := Poster.t("CHAPTER %02d  ·  %s" % [ci + 1, str(wd.get("class", "")).to_upper()], 11, Color(INK, 0.7), "mono")
	Poster.at(p, sub, Vector2(nx0 + 86, ny + 94))

	# The data list: the chapter's numbers, a gap, then the world's readouts.
	var ly := ny + 126.0
	var lx0 := 34.0
	var lx1 := pw * 0.49
	var rows: Array = []
	var host := str(Kit.FACTION_NAMES.get(faction, faction)).to_upper()
	rows.append(["HOST", host, false])
	rows.append(["STAGES CLEARED", "[  %02d / %02d  ]" % [done, count], true])
	var lv := _range_of(first, count, "level")
	rows.append(["ENEMY LEVEL", "LV %d – %d" % [lv.x, lv.y], false])
	var gr := _range_of(first, count, "stars")
	rows.append(["ENEMY GRADE", ("★%d – ★%d" % [gr.x, gr.y]) if gr.x != gr.y else ("★%d" % gr.x), false])
	var rp0 := int(Game.stage(first).get("recommended_power", 0))
	var rp1 := int(Game.stage(first + count - 1).get("recommended_power", 0))
	rows.append(["REC. POWER", "%s – %s" % [Kit.format_num(rp0), Kit.format_num(rp1)], false])
	var ctr := StageInfo.counter_of(faction)
	if ctr != "":
		rows.append(["COUNTER", "%s +20%%" % str(Kit.FACTION_NAMES.get(ctr, ctr)).to_upper(), false])
	var boss := _boss_name(first + count - 1)
	if boss != "":
		rows.append(["BOSS", boss.to_upper(), false])
	rows.append([])
	for ro: Variant in wd.get("readouts", []):
		if ro is Array and (ro as Array).size() >= 2:
			rows.append([str(ro[0]).to_upper(), str(ro[1]).to_upper(), false])
	var y := ly
	var rh := 19.0
	for row: Array in rows:
		if row.is_empty():
			y += 10.0
			continue
		var hi := bool(row[2])
		if hi:
			Poster.rect(p, Rect2(lx0 - 12, y - 2, lx1 - lx0 + 24, rh + 2), Color(INK, 0.07))
			Poster.rect(p, Rect2(lx0 - 8, y + 2, 2, rh - 6), INK)
		var a := Poster.t(str(row[0]), 11, INK, "mono_bold" if hi else "mono")
		Poster.at(p, a, Vector2(lx0, y))
		var b := Poster.t(str(row[1]), 11, SIGNAL if hi and done >= count else INK, "mono_bold" if hi else "mono")
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.size = Vector2(lx1 - lx0, 16)
		Kit.fit_label(b, (lx1 - lx0) * 0.6, 11, 8)
		Poster.at(p, b, Vector2(lx0, y))
		y += rh
	_bracket(p, Vector2(lx0 - 20, ly - 14), 1.0, 1.0)
	_bracket(p, Vector2(lx1 + 20, ly - 14), -1.0, 1.0)
	_bracket(p, Vector2(lx0 - 20, y + 8), 1.0, -1.0)
	_bracket(p, Vector2(lx1 + 20, y + 8), -1.0, -1.0)
	var bar := SignalKit.barcode(Vector2(46, 10), INK, 311 + ci * 17)
	Poster.at(p, bar, Vector2(lx1 - 46, y + 14))
	# The six worlds as a printed index (this one in signal, sealed ones dim).
	var ix := pw - 300.0
	var iy := ly - 2.0
	Poster.at(p, Poster.t("WORLDS", 10, Color(INK, 0.7), "mono_bold"), Vector2(ix, iy))
	Poster.at(p, Poster.t("%02d / %02d" % [ci + 1, chs.size()], 10, INK, "mono"), Vector2(ix + 220, iy))
	Poster.rect(p, Rect2(ix, iy + 22, 270, 1), Color(INK, 0.5))
	for k in chs.size():
		var open_k := Game.stage_status(int(chs[k].get("first_stage", 0))) != "locked"
		var kx := ix + 8.0 + k * 50.0
		var on := k == ci
		Poster.rect(p, Rect2(kx, iy + 16, 1.5 if not on else 3.0, 12), SIGNAL if on else Color(INK, 0.8 if open_k else 0.35))
		var kl := Poster.t("%02d" % (k + 1) + ("" if open_k else " ×"), 11, SIGNAL if on else Color(INK, 0.85 if open_k else 0.35), "mono_bold" if on else "mono")
		Poster.at(p, kl, Vector2(kx - 2, iy + 32))

	# ENTER: the pass, stuck on bottom right. A locked world gets a LOCKED stamp and its key stage.
	enter_button = null
	if locked:
		var prev := Game.stage(first - 1)
		Poster.rubber(p, "LOCKED", c + Vector2(-r * 0.62, -24), SIGNAL, 30, -0.12)
		# The key, printed bottom right: which stage opens this world.
		var kx := pw - 300.0
		var ky := ph - 200.0
		Poster.rect(p, Rect2(kx, ky, 270, 1.5), INK)
		Poster.at(p, Poster.t("ACCESS KEY", 10, Color(INK, 0.7), "mono_bold"), Vector2(kx, ky + 8))
		var key := Poster.tv("CLEAR %s" % str(prev.get("id", "")), 64, INK, 820.0, 62.0)
		Poster.at(p, key, Vector2(kx - 2, ky + 20))
		var kl := Poster.t("THE WORLD OPENS WHEN STAGE %s IS CLEARED." % str(prev.get("id", "")), 10, Color(INK, 0.7), "mono")
		Poster.at(p, kl, Vector2(kx, ky + 104))
		Poster.rubber(p, "SEALED", Vector2(kx + 150, ky + 128), Color(INK, 0.8), 18, 0.08)
	else:
		var spec := {"width": 300.0, "code": false, "kicker": "SURVEY // WORLD %s" % code, "title": "CH.%02d" % (ci + 1),
			"sub": "%d STAGES" % count, "action": "ENTER  >>>", "icon": "map"}
		var pass_root := Poster.pass_on(p, spec, Vector2(pw - 312, ph - 194), func() -> void: enter_pressed.emit(), "Enter", "EnterWorld")
		enter_button = Poster.pass_hit(pass_root)
	SignalKit.relight(self)


## A small ‹ or › with an 88 px hit area centred on `at`; dim when there is nothing that way.
func _arrow(p: Control, at: Vector2, dir: int, on: bool, cb: Callable, node_name: String) -> void:
	var tri := Polygon2D.new()
	var s := 9.0
	tri.polygon = PackedVector2Array([Vector2(-s * 0.6 * dir, -s), Vector2(s * 0.6 * dir, 0), Vector2(-s * 0.6 * dir, s)])
	tri.color = Color(INK, 0.9 if on else 0.2)
	tri.position = at
	p.add_child(tri)
	if on:
		Poster.hit(p, Rect2(at - Vector2(44, 44), Vector2(88, 88)), cb, node_name, "‹" if dir < 0 else "›")


## An L-shaped corner bracket at `at`, its arms running along +x*sx and +y*sy.
func _bracket(p: Control, at: Vector2, sx: float, sy: float) -> void:
	var l := 12.0
	Poster.rect(p, Rect2(at.x if sx > 0 else at.x - l, at.y if sy > 0 else at.y - 1.0, l, 1.2), Color(INK, 0.8))
	Poster.rect(p, Rect2(at.x if sx > 0 else at.x - 1.0, at.y if sy > 0 else at.y - l, 1.2, l), Color(INK, 0.8))


## min / max of an enemy field ("level" or "stars") over the chapter's stages.
func _range_of(first: int, count: int, key: String) -> Vector2i:
	var lo := 1 << 30
	var hi := 0
	for i in count:
		for e: Variant in Game.stage(first + i).get("enemies", []):
			if e is Dictionary:
				var v := int((e as Dictionary).get(key, 0))
				lo = mini(lo, v)
				hi = maxi(hi, v)
	return Vector2i(lo if hi > 0 else 0, hi)


func _boss_name(stage_index: int) -> String:
	for e: Variant in Game.stage(stage_index).get("enemies", []):
		if e is Dictionary and bool((e as Dictionary).get("is_boss", false)):
			return str(Game.hero_def(str((e as Dictionary).get("hero_id", ""))).get("name", ""))
	return ""


## The zoom into the planet: the type and line work fade, the planet grows past the poster; `then`
## runs at the end. Instant with Reduce motion.
func dive(then: Callable) -> void:
	if not Kit.motion_ok():
		then.call()
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_chrome, "modulate:a", 0.0, 0.22)
	if _neighbor:
		tw.tween_property(_neighbor, "modulate:a", 0.0, 0.22)
	tw.tween_method(world_view.zoom, 1.0, 3.4, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(then)


## The way back out of a map: the planet shrinks to its place and the dossier prints in.
func arrive() -> void:
	if not Kit.motion_ok():
		return
	_chrome.modulate.a = 0.0
	world_view.zoom(3.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(world_view.zoom, 3.2, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_chrome, "modulate:a", 1.0, 0.3).set_delay(0.35)
	if _neighbor:
		_neighbor.modulate.a = 0.0
		tw.tween_property(_neighbor, "modulate:a", 1.0, 0.3).set_delay(0.35)
