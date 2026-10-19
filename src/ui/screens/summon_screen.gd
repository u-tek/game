extends Control
## Screen "summon" (bottom-nav Summon tab), style v4 "Signal": the banner as a printed poster in the
## approved Lobby's look (docs/dev/ui-style-v4.md). On the paper matte, a poster: a dark band down the
## right edge with the featured Legendary as a red halftone print, the banner's name set huge in
## compressed type and turned on its side (two-tone where it crosses the band, the last word in
## signal), the featured Legendary in full colour in front of it (tap her for her page) and the other
## two featured Legendaries as small framed prints on the band. Top left, printed micro type: the
## featured line, "RATES" (opens the odds), the rates and the pulls left to the guaranteed Legendary.
## Down the left edge, behind a hairline: the pity as a printed tick ruler with vertical micro type;
## a stamp on a silver disc gives the pulls left as a big number.
## The two summon passes (x1 and x10, OG-pass cards) are stuck over the poster's bottom edge: the x1
## pass is the free daily pull when it is ready (else it shows when the next one comes); prices use
## scrolls first, then gems, and gem spending asks first. When the player can't pay, a signal
## sticker explains it and links to the Shop. Under the poster: the date and the featured hero's
## signature.
##
## Summoning plays the full-screen sequence (src/ui/summon/summon_sequence.gd) with the chrome
## hidden: a press run (the portal charge; its ink tells the best rarity), then every hero gets her
## own printed poster that the player taps through (Epic and Legendary get a held beat and a big
## reveal), then the results as a contact sheet with Summon again or Done. "Skip" jumps to the
## results.
##
## Shot params: rates: true (open the odds), pull: 1|10 (summon right away), skip: true
## (jump straight to the results). Without touching the save: demo: "ten" | "one" | "rare" |
## "epic" | "legendary" plays made-up results (hero: an id for the single ones), card: k
## starts at hero k's reveal, summary: true shows the results, hold: t freezes the clock at
## t seconds (of the charge, or of hero k's reveal with card), autotap: s taps every s
## seconds. frames: "<abs dir>" saves `count` (default 40) PNG frames `every` (default 0.1)
## seconds apart, starting `after` seconds in, for checking motion.

const Roster := preload("res://src/ui/screens/heroes_screen.gd")
const Sequence := preload("res://src/ui/summon/summon_sequence.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")

const BAND_W := 216.0
const INK := PK.INK
const PAPER := PK.PAPER
const SIG := PK.SIGNAL

var _banner: Dictionary = {}
var _main: Control
var _poster: Control
var _dyn: Control
var _reason: Button
var _free_timer_label: Label
var _feature := ""
var _sig := ""
var _tick := 0.0
var _composed_for := Vector2.ZERO

# Summon sequence (the e2e scripts read _phase, _cards, _showcase and _results).
var _seq: Sequence
var _results: Array = []
## "" (banner), "charge", "reveal" or "results".
var _phase: String:
	get:
		return _seq.phase if _seq != null and is_instance_valid(_seq) else ""
## The result cards once the sequence shows the results.
var _cards: Array:
	get:
		return _seq.cards if _seq != null and is_instance_valid(_seq) else []
## The Legendary being revealed (its big showcase), else null.
var _showcase: Control:
	get:
		return _seq.showcase if _seq != null and is_instance_valid(_seq) else null


func setup(params: Dictionary) -> void:
	_banner = Game.banner()
	UI.set_full_bleed(true)
	var legends: Array = (_banner.get("pool_by_rarity", {}) as Dictionary).get("legendary", [])
	_feature = str(legends[0]) if not legends.is_empty() else "seraphiel"
	_main = Control.new()
	_main.name = "Banner"
	_main.mouse_filter = MOUSE_FILTER_IGNORE
	_main.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_main)
	_reason = PK.print_button("", func() -> void: UI.go("shop"), {"size": Vector2(520, Kit.BUTTON_H)})
	_reason.name = "Reason"
	_reason.visible = false
	resized.connect(_compose_soon)
	Game.changed.connect(_refresh)
	_compose_soon()
	if bool(params.get("rates", false)):
		_open_rates.call_deferred()
	if params.has("demo"):
		_shot_demo.call_deferred(params)
	elif params.has("pull"):
		_shot_pull.call_deferred(int(params["pull"]), bool(params.get("skip", false)))
	if params.has("frames"):
		_capture_frames.call_deferred(str(params["frames"]), float(params.get("every", 0.1)), int(params.get("count", 40)), float(params.get("after", 0.0)))


func _exit_tree() -> void:
	if Game.changed.is_connected(_refresh):
		Game.changed.disconnect(_refresh)


func _shot_pull(count: int, skip: bool) -> void:
	await get_tree().process_frame
	_do_summon(count, count == 1 and Game.free_pull_available())
	if skip and _seq:
		_seq.skip_all()


## Screenshots without touching the save: plays made-up results (see the header).
func _shot_demo(params: Dictionary) -> void:
	await get_tree().process_frame
	_results = _demo_results(str(params.get("demo", "ten")), str(params.get("hero", "")))
	_start_sequence()
	if bool(params.get("summary", false)):
		_seq.skip_all()
	elif params.has("card"):
		_seq.start_at(int(params["card"]), float(params.get("hold", -1.0)))
	elif params.has("hold"):
		_seq.charge_hold = float(params["hold"])
	if params.has("autotap"):
		_autotap(float(params["autotap"]))


## Screenshots: taps the sequence every `every` seconds until the results.
func _autotap(every: float) -> void:
	while _seq != null and is_instance_valid(_seq) and _phase in ["charge", "reveal"]:
		await get_tree().create_timer(every).timeout
		if _seq != null and is_instance_valid(_seq):
			_seq.tap()


static func _demo_results(kind: String, hero: String) -> Array:
	var picks: Array = []
	match kind:
		"ten":
			picks = [["uriela", true], ["kessa", false], ["cassiel", true], ["ashra", false], ["seraphiel", true],
				["imra", false], ["vesper", false], ["nuriel", true], ["lucen", false], ["sable", false]]
		"legendary":
			picks = [[hero if hero != "" else "seraphiel", true]]
		"epic":
			picks = [[hero if hero != "" else "vesper", true]]
		_:
			picks = [[hero if hero != "" else "uriela", false]]
	var out: Array = []
	for p: Array in picks:
		var id := str(p[0])
		var rarity := str(Game.hero_def(id).get("rarity", "rare"))
		var is_new := bool(p[1])
		var shards := 0 if is_new else Progression.dupe_shards(rarity)
		out.append({"hero_id": id, "rarity": rarity, "is_new": is_new, "shards": shards, "dust": 0, "pity": 0})
	return out


## Saves `count` PNG frames of the window, one every `every` seconds, starting `after`
## seconds in (motion checks).
func _capture_frames(dir: String, every: float, count: int, after: float) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if after > 0.0:
		await get_tree().create_timer(after).timeout
	for i in count:
		await get_tree().create_timer(every).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [dir, i])


# ------------------------------------------------------------------ the poster

func _compose_soon() -> void:
	_compose.call_deferred()


## Builds the poster for the current size (again after a resize: the chrome can change the
## content area). The parts that follow the save (passes, pity, reason) are rebuilt by _refresh.
func _compose() -> void:
	if not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	if _composed_for == size:
		return
	_composed_for = size
	if _reason.get_parent():
		_reason.get_parent().remove_child(_reason)
	for c in _main.get_children():
		_main.remove_child(c)
		c.queue_free()
	var w := size.x
	var top := UI.content_top()
	var bot := size.y - UI.content_bottom()
	var def := Game.hero_def(_feature)
	PK.matte(_main)
	# Above the poster: the house line and the portal's number.
	PK.at(_main, PK.t("HALO & HORN  ©2026", 13, INK, "mono_bold"), Vector2(20, top + 8))
	var pl := PK.t("PORTAL Nº 01  ·  STANDARD  ·  EVERY HERO CAN ANSWER", 11, Color(INK, 0.7), "mono")
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pl.size = Vector2(440, 16)
	PK.at(_main, pl, Vector2(w - 20 - 440, top + 10))

	var pr := Rect2(18, top + 36, w - 36, maxf(600.0, bot - 74 - (top + 36)))
	_poster = PK.poster(_main, pr)
	var pw := pr.size.x
	var ph := pr.size.y
	var bx := pw - BAND_W
	# The band: the featured Legendary as a red halftone print, the rates in paper-white micro type.
	var band := PK.band(_poster, Rect2(bx, 0, BAND_W, ph), _feature, "", {"from": 0.2, "cell": 7.0})
	PK.vt(band, "©2026 HH, ALL RIGHTS RESERVED.", 10, Color(PAPER, 0.75), Vector2(BAND_W - 6, ph * 0.62))
	PK.at(band, PK.t("No.\n001", 12, Color(PAPER, 0.85), "mono_bold"), Vector2(14, ph * 0.46))
	PK.at(band, PK.t("19.10.26", 12, Color(PAPER, 0.85), "mono_bold"), Vector2(14, ph * 0.46 + 40))

	# The banner's name, set huge and turned on its side: paper over the band, ink over the paper,
	# the last word in signal.
	var name_txt := str(_banner.get("name", "Summon")).to_upper()
	var fs := 176
	var lines: Array[String] = []
	while true:
		lines = _wrap(name_txt, Kit.font("compressed"), fs, ph * 0.66)
		if lines.size() <= 3 or fs <= 100:
			break
		fs -= 8
	var last := lines[lines.size() - 1].split(" ")
	var key := last[last.size() - 1]
	last.remove_at(last.size() - 1)
	lines[lines.size() - 1] = (" ".join(last) + " " if not last.is_empty() else "") + "[color=#%s]%s[/color]" % [SIG.to_html(false), key]
	PK.giant(_poster, "\n".join(lines), fs, [[0.0, bx, INK], [bx, BAND_W, PAPER]], Vector2(pw - 24, ph * 0.035), Vector2(ph, 560))

	# Top left: the featured line and the rates as printed micro type ("RATES" opens the odds).
	PK.at(_poster, PK.t("FEATURED LEGENDARY\n%s · %s" % [str(def.get("name", _feature)).to_upper(), str(Kit.ROLE_NAMES.get(str(def.get("role", "")), "")).to_upper()],
		11, INK, "mono_bold"), Vector2(64, 16))
	var rates_btn := PK.print_button("RATES  ↗", _open_rates, {"size": Vector2(150, 60), "text_size": 13})
	rates_btn.name = "Rates"
	PK.at(_poster, rates_btn, Vector2(64, 44))
	var rates: Dictionary = _banner.get("rates", {})
	var ry := 102.0
	for r: String in ["legendary", "epic", "rare"]:
		var row := PK.t("%-10s %5s" % [str(Kit.RARITY_NAMES[r]).to_upper(), _pct(float(int(rates.get(r, 0))))], 11,
			INK if r != "legendary" else SIG, "mono_bold")
		PK.at(_poster, row, Vector2(64, ry))
		ry += 16.0
	var guarantee := str(_banner.get("ten_pull_guarantee", "epic"))
	PK.at(_poster, PK.t("x10: %s OR BETTER" % str(Kit.RARITY_NAMES.get(guarantee, guarantee)).to_upper(), 10, Color(INK, 0.7), "mono"), Vector2(64, ry + 2))

	# Left edge: a hairline and vertical micro type (the pity ruler is live, in _refresh).
	PK.rule(_poster, Rect2(48, 0, 1, ph), Color(INK, 0.55))
	PK.vt(_poster, "©2026 · PORTAL", 12, INK, Vector2(36, 14))

	# The featured Legendary in full colour, in front of the type (tap her for her page).
	var box := Control.new()
	box.clip_contents = true
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.position = Vector2(49, 0)
	box.size = Vector2(pw - 49, ph)
	_poster.add_child(box)
	var feet := Vector2(bx * 0.46 + 10.0 - 49.0, ph - 4.0)
	var fig_h := ph * 0.95
	PK.hero_fig(box, _feature, "", feet, fig_h)
	var hit := Control.new()
	hit.name = "Hit_" + _feature
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.position = Vector2(feet.x - 130, feet.y - fig_h * 0.92)
	hit.size = Vector2(260, fig_h * 0.62)
	box.add_child(hit)
	var fid := _feature
	Kit.make_tappable(hit, func() -> void: UI.go("hero_detail", {"hero_id": fid}))

	# The other featured Legendaries: small framed prints stuck on the band.
	var legends: Array = (_banner.get("pool_by_rarity", {}) as Dictionary).get("legendary", [])
	var fy := ph * 0.56
	for i in range(1, mini(3, legends.size())):
		var id := str(legends[i])
		var d := Game.hero_def(id)
		var fr := Control.new()
		fr.name = "Feature_" + id
		fr.mouse_filter = MOUSE_FILTER_PASS
		fr.position = Vector2(bx + 22, fy)
		fr.size = Vector2(92, 120)
		_poster.add_child(fr)
		var bg := ColorRect.new()
		bg.color = PAPER
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		bg.size = Vector2(92, 92)
		fr.add_child(bg)
		var pic := HeroArt.make_portrait(id, 88, "")
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.position = Vector2(2, 2)
		fr.add_child(pic)
		PK.hairbox(fr, Rect2(0, 0, 92, 92), Color(PAPER, 0.8))
		PK.at(fr, PK.t("%02d %s" % [i + 1, str(d.get("name", id)).to_upper()], 10, PAPER, "mono_bold"), Vector2(0, 96))
		var lid := id
		Kit.make_tappable(fr, func() -> void: UI.go("hero_detail", {"hero_id": lid}))
		fy += 132.0

	# The dynamic layer (passes, pity, reason), then the line under the poster and the grain.
	_dyn = Control.new()
	_dyn.name = "Live"
	_dyn.mouse_filter = MOUSE_FILTER_IGNORE
	_dyn.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_main.add_child(_dyn)
	var foot := pr.end.y + 12.0
	PK.at(_main, PK.t("2026 10/19", 24, INK, "regular"), Vector2(20, foot + 18))
	var sig := PK.t(str(def.get("name", _feature)), 46, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(300, 52)
	PK.at(_main, sig, Vector2(w - 24 - 300, foot + 2))
	PK.rule(_main, Rect2(w - 236, foot + 52, 210, 2), INK).rotation = -0.05
	PK.grain(_main, 0.06)
	_main.set_meta("poster_rect", pr)
	_sig = ""
	_refresh()
	SignalKit.relight(_main)


## Greedy word wrap of `text` into lines no wider than `width` px in `font` at `fs`.
static func _wrap(text: String, font: Font, fs: int, width: float) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for wd in text.split(" ", false):
		var tryl := wd if cur == "" else cur + " " + wd
		if cur != "" and font.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(cur)
			cur = wd
		else:
			cur = tryl
	if cur != "" or out.is_empty():
		out.append(cur)
	return out


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _dyn == null or not is_instance_valid(_dyn):
		return
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(Game.pity_count())
	var left := maxi(1, pity_max - pity)
	var free_ready := bool(Game.free_pull_available())
	var p1 := _price(1)
	var p10 := _price(10)
	var guide := Guide.step() == "summon"
	var sig := "%d|%s|%s|%s|%s" % [pity, free_ready, JSON.stringify(p1), JSON.stringify(p10), guide]
	if sig == _sig:
		return
	_sig = sig
	if _reason.get_parent():
		_reason.get_parent().remove_child(_reason)
	for c in _dyn.get_children():
		_dyn.remove_child(c)
		c.queue_free()
	_free_timer_label = null
	var pr: Rect2 = _main.get_meta("poster_rect", Rect2(18, 200, 684, 900))
	var ph := pr.size.y

	# Pity: a printed tick ruler down the left edge, its count in vertical micro type, the stamp.
	var tk := PK.ticks(pity_max, pity, Vector2(ph * 0.46, 18), INK, SIG)
	tk.rotation = PI * 0.5
	tk.position = pr.position + Vector2(40, ph * 0.3)
	_dyn.add_child(tk)
	PK.vt(_dyn, "PITY %02d / %d" % [pity, pity_max], 12, INK, pr.position + Vector2(38, ph * 0.3 - 112))
	PK.at(_dyn, PK.t("LEGENDARY GUARANTEED\nWITHIN %d PULL%s" % [left, "" if left == 1 else "S"], 10, INK, "mono_bold"), pr.position + Vector2(64, 186))
	PK.rule(_dyn, Rect2(pr.position + Vector2(64, 180), Vector2(130, 1)), Color(INK, 0.5))
	var st := PK.stamp_disc(_dyn, pr.position + Vector2(64, ph - 316), 112, "LEGENDARY · WITHIN · PULLS · ", "%02d" % left)
	st.name = "Pity"

	# The passes, stuck over the poster's bottom edge.
	var y := pr.end.y - 166.0
	var b1: Button
	if free_ready:
		b1 = PK.pass_button({"width": 300.0, "code": false, "kicker": "SUMMON // DAILY", "title": "FREE  ×1",
			"sub": "THE DAILY PULL · NO COST", "action": "PULL  >>>", "info": "FREE TODAY"}, func() -> void: _do_summon(1, true))
		p1 = {"currency": "free", "amount": 0, "ok": true}
	else:
		b1 = PK.pass_button({"width": 300.0, "code": false, "kicker": "SUMMON // SINGLE", "title": "SUMMON ×1",
			"sub": "%d SCROLL OR %s GEMS" % [int(_banner.scroll_cost_one), Kit.format_full(int(_banner.cost_one))],
			"action": "PULL  >>>", "info": _cost_text(p1), "disabled": not bool(p1.ok)}, func() -> void: _try_summon(1))
	b1.name = "Summon1"
	b1.position = Vector2(pr.position.x - 6, y + 6)
	b1.rotation = -0.03
	_dyn.add_child(b1)
	var b10 := PK.pass_button({"width": 384.0, "kicker": "SUMMON // TEN PULLS", "title": "SUMMON ×10",
		"sub": "%s OR BETTER INSIDE" % str(Kit.RARITY_NAMES.get(str(_banner.get("ten_pull_guarantee", "epic")), "Epic")).to_upper(),
		"action": "PULL ×10  >>>", "info": _cost_text(p10), "icon": "summon", "disabled": not bool(p10.ok)}, func() -> void: _try_summon(10))
	b10.name = "Summon10"
	b10.position = Vector2(pr.end.x - 384 + 8, y)
	b10.rotation = 0.02
	_dyn.add_child(b10)
	# The free pull: a status light and a line on the paper, or when the next one comes.
	if free_ready:
		PK.led(_dyn, pr.position + Vector2(24, ph * 0.3 - 136), "blink")
	else:
		var info: Variant = b1.get_meta("info_label") if b1.has_meta("info_label") else null
		if info is Label:
			_free_timer_label = info
			_update_free_timer()
	# First session: the free x1 first, then the 10-pull the starting scrolls pay for.
	Guide.mark(b1, guide and free_ready, 0)
	Guide.mark(b10, guide and not free_ready and str(p10.currency) == "scrolls", 0)
	if not bool(p1.ok) or not bool(p10.ok):
		var need := "NEED %s GEMS OR %d SCROLL%s" % [Kit.format_full(int(_banner.cost_one)), int(_banner.scroll_cost_one), "" if int(_banner.scroll_cost_one) == 1 else "S"] if not bool(p1.ok) \
			else "x10 NEEDS %s GEMS OR %d SCROLLS" % [Kit.format_full(int(_banner.cost_ten)), int(_banner.scroll_cost_ten)]
		var tag := PK.sticker([[need, 13, "mono_bold"], ["GET MORE IN THE SHOP  >>>", 11, "mono"]], {"fill": "signal", "rotation": -0.03})
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		_reason.size = Vector2(maxf(tag.size.x, 300.0), Kit.BUTTON_H)
		(_reason.get_meta("text_label") as Label).text = ""
		_reason.add_child(tag)
		tag.position = Vector2(0, (Kit.BUTTON_H - tag.size.y) * 0.5)
		_reason.position = Vector2(pr.position.x + 60, y - 84)
		_reason.visible = true
		# Old sticker from a previous refresh.
		for c in _reason.get_children():
			if c is PanelContainer and c != tag:
				c.queue_free()
	else:
		_reason.visible = false
	_dyn.add_child(_reason)
	SignalKit.relight(_dyn)


func _cost_text(p: Dictionary) -> String:
	match str(p.currency):
		"free":
			return "FREE TODAY"
		"scrolls":
			return "%d SCROLL%s" % [int(p.amount), "" if int(p.amount) == 1 else "S"]
	return "%s GEMS" % Kit.format_full(int(p.amount))


## Price of a summon: scrolls when the player has enough, else gems. ok = affordable.
func _price(count: int) -> Dictionary:
	var sc := int(_banner.scroll_cost_one if count == 1 else _banner.scroll_cost_ten)
	var gc := int(_banner.cost_one if count == 1 else _banner.cost_ten)
	if Game.currency("scrolls") >= sc:
		return {"currency": "scrolls", "amount": sc, "ok": true}
	return {"currency": "gems", "amount": gc, "ok": Game.currency("gems") >= gc}


func _update_free_timer() -> void:
	if _free_timer_label and is_instance_valid(_free_timer_label):
		_free_timer_label.text = "FREE PULL USED. NEXT IN %s" % Kit.format_time(Game.ms_until_reset()).to_upper()


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_free_timer()
		if _phase == "" and _free_timer_label != null and Game.free_pull_available():
			_refresh()


# ------------------------------------------------------------------ rates

func _open_rates() -> void:
	var v := Kit.vbox(14)
	v.custom_minimum_size.x = 540
	var rates: Dictionary = _banner.get("rates", {})
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	v.add_child(Kit.body("Every pull rolls a rarity first, then one hero of that rarity with equal chance.", 21, Kit.TEXT_DIM))
	for r: String in ["legendary", "epic", "rare"]:
		var rows: Array = [[str(Kit.RARITY_NAMES[r]).to_upper(), _pct(float(int(rates.get(r, 0)))), true]]
		var ids: Array = pool.get(r, [])
		if not ids.is_empty():
			var each := float(int(rates.get(r, 0))) / float(ids.size())
			for id: Variant in ids:
				rows.append([str(Game.hero_def(str(id)).get("name", id)), _pct(each)])
		v.add_child(PK.data_table(rows, 540.0, {"size": 16, "row_h": 30.0, "bar": Color(0, 0, 0, 0.06)}))
	var pity_max := int(_banner.get("pity_legendary", 60))
	var guarantee := str(_banner.get("ten_pull_guarantee", "epic"))
	var dupes := ""
	var dust := ""
	for r: String in ["rare", "epic", "legendary"]:
		dupes += ("%s %d" % [str(Kit.RARITY_NAMES[r]), Progression.dupe_shards(r)]) + (", " if r != "legendary" else "")
		dust += ("%d" % Progression.dust_per_excess_shard(r)) + (" / " if r != "legendary" else "")
	var rules: Array[Array] = [
		["Pity", "If none of your last %d pulls was Legendary, the next pull is a guaranteed Legendary. Your counter: %d / %d. It carries over between summons and resets when you get any Legendary." % [pity_max - 1, Game.pity_count(), pity_max]],
		["10-pull bonus", "Every 10-pull includes at least one %s or better hero." % str(Kit.RARITY_NAMES.get(guarantee, guarantee.capitalize()))],
		["Duplicates", "A hero you already own turns into shards of that hero: %s shards. Shards raise stars, up to %d. Shards a fully starred hero can't use become dust (Rare / Epic / Legendary: %s per shard)." % [dupes, Kit.MAX_STARS, dust]],
		["Costs", "1 pull: %d scroll or %s gems. 10 pulls: %d scrolls or %s gems. Scrolls are always used first. The free daily summon uses the same rates." % [int(_banner.scroll_cost_one), Kit.format_full(int(_banner.cost_one)), int(_banner.scroll_cost_ten), Kit.format_full(int(_banner.cost_ten))]],
	]
	for rule in rules:
		var rv := Kit.vbox(4)
		rv.add_child(Kit.label(str(rule[0]).to_upper(), 16, Kit.TEXT, "mono_bold"))
		rv.add_child(Kit.body(str(rule[1]), 21, Kit.TEXT))
		v.add_child(rv)
	var sc := Kit.scroll(Kit.margin(v, 4, 4))
	var vh: float = get_viewport_rect().size.y
	sc.custom_minimum_size = Vector2(560, minf(vh * 0.62, 1000.0))
	UI.popup("Summon Rates", sc, Callable(), 640.0, true)


## Basis points (may be fractional) as a percentage with up to 3 decimals: 200 -> "2%",
## 66.67 -> "0.667%".
static func _pct(bp: float) -> String:
	var s := "%.3f" % (bp / 100.0)
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s + "%"


# ------------------------------------------------------------------ summoning

func _try_summon(count: int) -> void:
	if _phase != "":
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gems or scrolls", "bad")
		return
	if str(p.currency) == "gems":
		var rates: Dictionary = _banner.get("rates", {})
		UI.confirm("Spend %s gems on %s?\nRates: Legendary %s, Epic %s, Rare %s." % [
			Kit.format_full(int(p.amount)), "1 summon" if count == 1 else "%d summons" % count,
			_pct(float(int(rates.get("legendary", 0)))), _pct(float(int(rates.get("epic", 0)))), _pct(float(int(rates.get("rare", 0))))],
			func() -> void: _do_summon(count, false), Callable(), "Summon")
	else:
		_do_summon(count, false)


func _do_summon(count: int, free: bool) -> void:
	if _phase != "" and _phase != "results":
		return
	var r := Game.summon(count, free)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "The portal didn't answer")), "bad")
		_refresh()
		return
	_results = r.get("value", [])
	if _results.is_empty():
		return
	for x: Variant in _results:
		if x is Dictionary and bool((x as Dictionary).get("is_new", false)):
			Roster.mark_new(str((x as Dictionary).get("hero_id", "")))
	_start_sequence()


func _start_sequence() -> void:
	UI.set_chrome(false, false)
	var replacing := _seq != null and is_instance_valid(_seq)
	if replacing:
		_seq.queue_free()
	_seq = Sequence.new()
	_seq.name = "SummonSequence"
	add_child(_seq)
	var pity_max := int(_banner.get("pity_legendary", 60))
	_seq.setup(_results, _price, pity_max - Game.pity_count())
	_seq.done.connect(_finish)
	_seq.again.connect(_again)
	_main.visible = false
	_seq.start(not replacing)


## Overlay taps (the e2e scripts call this with simulated releases too).
func _on_overlay_input(ev: InputEvent) -> void:
	if _seq != null and is_instance_valid(_seq):
		_seq.handle_input(ev)


func _again(count: int) -> void:
	if _phase != "results":
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gems or scrolls", "bad")
		return
	if str(p.currency) == "gems":
		UI.confirm("Spend %s gems on %s?" % [Kit.format_full(int(p.amount)), "1 summon" if count == 1 else "%d summons" % count],
			func() -> void: _do_summon(count, false), Callable(), "Summon")
	else:
		_do_summon(count, false)


func _finish() -> void:
	if _seq != null and is_instance_valid(_seq):
		_seq.close()
	_seq = null
	_results.clear()
	UI.set_chrome(true, true)
	_main.visible = true
	_composed_for = Vector2.ZERO
	_compose_soon()
