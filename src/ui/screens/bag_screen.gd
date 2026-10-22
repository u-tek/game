extends Control
## Screen "bag": everything the player owns on one printed ledger (the owner, 2026-10-22: "do we
## have an inventory yet??"), in the house poster style (docs/dev/ui-style-v4.md section 0) with the
## data-table idea of reference 14 (a mono table with brackets) and the product shots of 11 / 18.
##
## The poster: a dark band down the left with the avatar hero as a red halftone and BAG set huge down
## it; the ledger head (the issue line, a tick rule, the gem count debossed big); then four sections,
## each a numbered rule ("01 CURRENCY"):
##   01 CURRENCY  one row per currency: its icon, name and what it is for in mono, a dotted leader,
##                the amount in compressed type between brackets, and a printed link (GET, SUMMON,
##                LEVEL UP, STAR UP) to where it is spent or found.
##   02 SHARDS    every owned hero holding shards as a small framed print with "12 / 30" and a progress
##                rule to her next star (signal when she can star up); tap for her page.
##   03 WARDROBE  the skins owned as framed prints (tap: the hero's wardrobe), or a line to the Shop.
##   04 ARMOURY · ALBUM  two printed slips: the gear (pieces, worn, spare) and the print album.
## params: scroll (px, screenshots).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const CK := preload("res://src/ui/v4/collect/collect_kit.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const BAND_C := Color("141517")
const BAND := 132.0
const HEAD := 300.0
const MAX_W := 760.0
## [id, name, what it is for, link label, screen, params]
const CURRENCIES := [
	["gems", "GEMS", "SUMMONS, SKINS, QUICK CLAIMS", "GET  ↗", "shop", {"tab": 1}],
	["scrolls", "SUMMON SCROLLS", "ONE SUMMON EACH", "SUMMON  ↗", "summon", {}],
	["gold", "GOLD", "LEVEL UPS, THE ENVOY'S DRAW", "GET  ↗", "shop", {}],
	["hero_exp", "HERO EXP", "LEVEL UPS", "LEVEL UP  ↗", "heroes", {}],
	["dust", "DUST", "STAR UPS (STANDS IN FOR SHARDS)", "STAR UP  ↗", "heroes", {}],
]

var _scroll: ScrollContainer
var _page: Control
var _poster: Control
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
	_build()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep


func _dims() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x, maxf(vp.y - UI.content_top() - UI.content_bottom(), 400.0))


# ------------------------------------------------------------------ build

func _build() -> void:
	var d := _dims()
	_built = d
	var w := minf(d.x, MAX_W)
	var ox := floorf((d.x - w) * 0.5)
	var pw := w - 32.0
	var shards := _shard_heroes()
	var skins := _owned_skins()
	var cell := floorf((pw - 40.0 - 3.0 * 12.0) / 4.0)
	var shard_rows := maxi(1, ceili(shards.size() / 4.0))
	var skin_rows := maxi(1, ceili(mini(skins.size(), 8) / 4.0))
	var cur_h := 34.0 + CURRENCIES.size() * 76.0
	var sh_h := 48.0 + shard_rows * (cell + 52.0)
	var sk_h := 48.0 + (skin_rows * (cell + 40.0) if not skins.is_empty() else 70.0)
	var ph := maxf(HEAD + 24.0 + cur_h + sh_h + sk_h + 210.0, d.y - 14.0 - 84.0)
	PK.matte(self)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = MOUSE_FILTER_IGNORE
	_page.custom_minimum_size = Vector2(d.x, 14.0 + ph + 84.0)
	_scroll = Kit.scroll(_page)
	_scroll.name = "Ledger"
	_scroll.size = d
	add_child(_scroll)
	var pr := Rect2(ox + 16, 14, pw, ph)
	_poster = PK.poster(_page, pr)
	_build_head(pw)
	var y := HEAD + 24.0
	y = _build_currency(pw, y)
	y = _build_shards(pw, y, shards, cell)
	y = _build_skins(pw, y, skins, cell)
	_build_links(pw, y)
	_build_footer(ox, w, pr)
	var back := SignalKit.back_button(func() -> void: UI.back(), false)
	back.position = Vector2(0, 4)
	_poster.add_child(back)
	add_child(SignalKit.grain(0.05, true))


## The head: the dark band with the avatar's halftone and BAG down it, the ledger block beside it.
func _build_head(pw: float) -> void:
	var p := _poster
	PK.rect(p, Rect2(0, 0, BAND, HEAD), BAND_C)
	var face := ProfileScreen.shown_avatar()
	if face != "":
		var ht := PK.halftone_print(face, Game.equipped_skin(face), Vector2(BAND, HEAD * 0.6), 6.0)
		ht.position = Vector2(0, HEAD * 0.4)
		p.add_child(ht)
	Poster.vlabel(p, "©2026 HH · INVENTORY", Vector2(24, 110), 10, Color(PAPER, 0.8))
	var title := "BAG[color=#%s].[/color]" % SIG.to_html(false)
	var fs := 210
	while fs > 80 and PK.text_w("BAG.", fs) > HEAD - 110.0:
		fs -= 4
	var gx := BAND + roundf(fs * 0.5)
	PK.giant(p, title, fs, Vector2(gx, 104), Vector2(HEAD, fs * 1.3), [[Rect2(0, 0, BAND, HEAD), PAPER],
		[Rect2(BAND, 0, gx - BAND + 6.0, HEAD), INK]], 0, "compressed", true)
	var x0 := gx + 22.0
	var tw := pw - x0 - 18.0
	PK.at(p, PK.t("INVENTORY  ·  LEDGER", 12, INK, "mono_bold"), Vector2(x0, 18))
	var no := PK.t(Poster.date_short(), 12, INK, "mono_bold")
	no.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	no.size = Vector2(tw, 16)
	PK.at(p, no, Vector2(x0, 18))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 38))
	var big := CK.deboss(Kit.format_num(int(Game.currency("gems"))), 92, PAPER, "compressed", 2.0)
	big.name = "Gems"
	PK.at(p, big, Vector2(x0 - 2, 46))
	PK.at(p, PK.t("GEMS ON HAND", 10, Color(INK, 0.72), "mono_bold"), Vector2(x0, 150))
	var lines := "%d HEROES  ·  %d WITH SHARDS\n%d SKINS  ·  %d GEAR  ·  %d PRINTS" % [Game.owned_heroes().size(), _shard_heroes().size(),
		_owned_skins().size(), Game.gear_items().size(), int(Game.print_stats().get("kept", 0))]
	PK.at(p, PK.t(lines, 10, Color(INK, 0.72), "mono"), Vector2(x0, 172))
	var bc := SignalKit.barcode(Vector2(minf(tw, 160.0), 22), INK, 4417)
	PK.at(p, bc, Vector2(x0, HEAD - 50.0))
	PK.rule(p, Vector2(BAND, HEAD - 1), Vector2(pw - BAND, 1))


## A numbered section rule: "01  CURRENCY" with a signal lead and a hairline to the edge.
func _section(pw: float, y: float, no: int, title: String, note: String = "") -> void:
	var p := _poster
	PK.at(p, PK.t("%02d" % no, 22, INK, "compressed"), Vector2(24, y - 6))
	PK.at(p, PK.t(title, 13, INK, "mono_bold"), Vector2(62, y))
	PK.rect(p, Rect2(62, y + 22, 36, 2), SIG)
	PK.rule(p, Vector2(100, y + 23), Vector2(pw - 124, 1), Color(INK, 0.45))
	if note != "":
		var n := PK.t(note, 10, Color(INK, 0.6), "mono")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.size = Vector2(pw - 48, 14)
		PK.at(p, n, Vector2(24, y + 2))


func _build_currency(pw: float, y: float) -> float:
	var p := _poster
	_section(pw, y, 1, "CURRENCY", "TAP A LINE TO SPEND OR FIND MORE")
	y += 44.0
	for c: Array in CURRENCIES:
		var id: String = c[0]
		var row := Control.new()
		row.name = "Cur_" + id
		row.mouse_filter = MOUSE_FILTER_PASS
		row.position = Vector2(20, y)
		row.size = Vector2(pw - 40, 70)
		p.add_child(row)
		var ic := Kit.currency_icon(id, 44)
		ic.position = Vector2(4, 10)
		row.add_child(ic)
		PK.at(row, PK.t(str(c[1]), 15, INK, "mono_bold"), Vector2(62, 8))
		PK.at(row, PK.t(str(c[2]), 10, Color(INK, 0.62), "mono"), Vector2(62, 30))
		var link := PK.t(str(c[3]), 11, SIG, "mono_bold")
		PK.at(row, link, Vector2(62, 46))
		# The amount between brackets, right-aligned; a dotted leader runs to it.
		var amt := Kit.format_full(int(Game.currency(id)))
		var fs := 40
		var aw := PK.text_w(amt, fs, "compressed")
		var bx := row.size.x - aw - 30.0
		var lead := Kit.PrintBits.Leader.new()
		lead.position = Vector2(62 + PK.text_w(str(c[1]), 15, "mono_bold") + 12.0, 14)
		lead.size = Vector2(maxf(bx - lead.position.x - 18.0, 0.0), 14)
		row.add_child(lead)
		PK.at(row, PK.t("[", 40, Color(INK, 0.4), "compressed_light"), Vector2(bx - 14.0, 4))
		var al := PK.t(amt, fs, INK, "compressed")
		PK.at(row, al, Vector2(bx, 4))
		PK.at(row, PK.t("]", 40, Color(INK, 0.4), "compressed_light"), Vector2(bx + aw + 4.0, 4))
		PK.rule(row, Vector2(0, 68), Vector2(row.size.x, 1), Color(INK, 0.18))
		var scr: String = c[4]
		var prm: Dictionary = c[5]
		Kit.make_tappable(row, func() -> void: UI.go(scr, prm))
		y += 76.0
	return y + 10.0


## Owned heroes holding shards, most first.
func _shard_heroes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in Game.owned_heroes():
		if int(h.get("shards", 0)) > 0:
			out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.shards) > int(b.shards) if int(a.shards) != int(b.shards) else str(a.id) < str(b.id))
	return out


func _build_shards(pw: float, y: float, list: Array[Dictionary], cell: float) -> float:
	var p := _poster
	_section(pw, y, 2, "SHARDS", "DUPLICATES BECOME SHARDS  ·  SHARDS RAISE STARS")
	y += 46.0
	if list.is_empty():
		PK.at(p, PK.t("No shards yet. Summon a hero you already have and her copy turns into shards.", 13, Color(INK, 0.7), "serif_italic"), Vector2(24, y + 6))
		return y + 60.0
	for i in list.size():
		var h: Dictionary = list[i]
		var id := str(h.id)
		var cost := Game.star_up_cost(id)
		var need := int(cost.get("shards", 0))
		var have := int(h.shards)
		var ready := Game.can_star_up(id)
		var fr := Control.new()
		fr.name = "Shard_" + id
		fr.mouse_filter = MOUSE_FILTER_PASS
		fr.position = Vector2(20 + (i % 4) * (cell + 12.0), y + floorf(i / 4.0) * (cell + 52.0))
		fr.size = Vector2(cell, cell + 46)
		p.add_child(fr)
		var bg := ColorRect.new()
		bg.color = Color("f5f4f0")
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		bg.size = Vector2(cell, cell)
		fr.add_child(bg)
		var pic := HeroArt.make_portrait(id, cell - 6, Game.equipped_skin(id))
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.position = Vector2(3, 3)
		pic.size = Vector2(cell - 6, cell - 6)
		fr.add_child(pic)
		PK.rule(fr, Vector2(0, 0), Vector2(cell, 1), Color(INK, 0.6))
		PK.rule(fr, Vector2(0, cell - 1), Vector2(cell, 1), Color(INK, 0.6))
		PK.rule(fr, Vector2(0, 0), Vector2(1, cell), Color(INK, 0.6))
		PK.rule(fr, Vector2(cell - 1, 0), Vector2(1, cell), Color(INK, 0.6))
		var nm := PK.t(str(Game.hero_def(id).get("name", id)).to_upper(), 10, INK, "mono_bold")
		nm.size = Vector2(cell, 14)
		nm.clip_text = true
		PK.at(fr, nm, Vector2(0, cell + 4))
		var cnt := PK.t(("%d / %d" % [have, need]) if need > 0 else "%d  ·  MAX" % have, 12, SIG if ready else INK, "mono_bold")
		PK.at(fr, cnt, Vector2(0, cell + 18))
		var frac := clampf(float(have) / float(need), 0.0, 1.0) if need > 0 else 1.0
		PK.rect(fr, Rect2(0, cell + 38, cell, 2), Color(INK, 0.15))
		PK.rect(fr, Rect2(0, cell + 38, cell * frac, 2), SIG if ready else INK)
		if ready:
			var led := PhysicalKit.Led.new("red", "breathe", 14.0)
			led.position = Vector2(cell - 18, 4)
			fr.add_child(led)
		Kit.make_tappable(fr, func() -> void: UI.go("hero_detail", {"hero_id": id}))
	return y + ceilf(list.size() / 4.0) * (cell + 52.0) + 8.0


## Skins the player owns: [{hero, id, name}].
func _owned_skins() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for h: Dictionary in Game.owned_heroes():
		for s: Dictionary in Game.skins_for(str(h.id)):
			if Game.owns_skin(str(s.id)):
				out.append({"hero": str(h.id), "id": str(s.id), "name": str(s.get("name", s.id))})
	return out


func _build_skins(pw: float, y: float, list: Array[Dictionary], cell: float) -> float:
	var p := _poster
	_section(pw, y, 3, "WARDROBE", ("%d OWNED" % list.size()) if not list.is_empty() else "")
	y += 46.0
	if list.is_empty():
		PK.at(p, PK.t("No skins yet. The Shop's Wardrobe has four packs for every hero.", 13, Color(INK, 0.7), "serif_italic"), Vector2(24, y + 6))
		var go := PK.t("WARDROBE  ↗", 12, SIG, "mono_bold")
		PK.at(p, go, Vector2(24, y + 32))
		var hit := Control.new()
		hit.mouse_filter = MOUSE_FILTER_PASS
		hit.position = Vector2(16, y)
		hit.size = Vector2(pw - 32, 64)
		p.add_child(hit)
		Kit.make_tappable(hit, func() -> void: UI.go("shop", {"tab": 2}))
		return y + 70.0
	for i in mini(list.size(), 8):
		var s: Dictionary = list[i]
		var hid := str(s.hero)
		var sid := str(s.id)
		var fr := Control.new()
		fr.name = "Skin_" + sid
		fr.mouse_filter = MOUSE_FILTER_PASS
		fr.position = Vector2(20 + (i % 4) * (cell + 12.0), y + floorf(i / 4.0) * (cell + 40.0))
		fr.size = Vector2(cell, cell + 34)
		p.add_child(fr)
		var pic := HeroArt.make_portrait(hid, cell, sid)
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		fr.add_child(pic)
		PK.rule(fr, Vector2(0, cell - 1), Vector2(cell, 1), Color(INK, 0.6))
		var nm := PK.t(str(s.name).to_upper(), 9, INK, "mono_bold")
		nm.size = Vector2(cell, 13)
		nm.clip_text = true
		PK.at(fr, nm, Vector2(0, cell + 4))
		PK.at(fr, PK.t(str(Game.hero_def(hid).get("name", hid)).to_upper(), 9, Color(INK, 0.6), "mono"), Vector2(0, cell + 18))
		Kit.make_tappable(fr, func() -> void: UI.go("hero_detail", {"hero_id": hid, "tab": "skins"}))
	return y + ceilf(mini(list.size(), 8) / 4.0) * (cell + 40.0) + 8.0


## 04: two printed slips side by side: the armoury (gear) and the album (prints).
func _build_links(pw: float, y: float) -> void:
	var p := _poster
	_section(pw, y, 4, "ARMOURY  ·  ALBUM")
	y += 46.0
	var items := Game.gear_items()
	var worn := 0
	for it: Dictionary in items:
		if str(it.get("hero", "")) != "":
			worn += 1
	var stats: Dictionary = Game.print_stats()
	var sw := floorf((pw - 40.0 - 12.0) / 2.0)
	var slips := [
		["GEAR", "%d PIECES" % items.size(), "%d WORN  ·  %d SPARE" % [worn, items.size() - worn], "gear", {}],
		["PRINTS", "%d IN THE ALBUM" % int(stats.get("kept", 0)), "%d MISPRINTS  ·  %d HOLO" % [int(stats.get("misprints", 0)), int(stats.get("holo", 0))], "prints", {}],
	]
	for i in slips.size():
		var sl: Array = slips[i]
		var box := Control.new()
		box.name = "Link_" + str(sl[3])
		box.mouse_filter = MOUSE_FILTER_PASS
		box.position = Vector2(20 + i * (sw + 12.0), y)
		box.size = Vector2(sw, 110)
		p.add_child(box)
		PK.rect(box, Rect2(0, 0, sw, 110), Color("f5f4f0"))
		PK.rect(box, Rect2(0, 0, 6, 110), SIG if i == 0 else INK)
		PK.at(box, PK.t(str(sl[0]), 34, INK, "compressed"), Vector2(18, 6))
		PK.at(box, PK.t(str(sl[1]), 12, INK, "mono_bold"), Vector2(18, 54))
		PK.at(box, PK.t(str(sl[2]), 10, Color(INK, 0.62), "mono"), Vector2(18, 72))
		PK.at(box, PK.t("OPEN  ↗", 11, SIG, "mono_bold"), Vector2(18, 88))
		var scr: String = sl[3]
		Kit.make_tappable(box, func() -> void: UI.go(scr))


## Under the poster: the date and the signature.
func _build_footer(ox: float, w: float, pr: Rect2) -> void:
	var fy := pr.end.y + 14.0
	PK.at(_page, PK.t(Poster.date_long(), 22, INK, "regular"), Vector2(ox + 20, fy + 8))
	var sig := PK.t("the Ledger", 40, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 46)
	PK.at(_page, sig, Vector2(ox + w - 24 - 300, fy - 6))
