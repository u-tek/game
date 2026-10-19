extends Control
## Screen "summon" (bottom-nav Summon tab), style v4 "Signal": five summon banners, each a printed
## poster in the approved Lobby's look (docs/dev/ui-style-v4.md). Across the top, the printed banner
## index "01 STANDARD / 02 FEATURED / 03 FACTION / 04 WISH / 05 ENVOY" (the current one in signal
## with a short bar) switches the poster. Each banner is composed on its own:
##
##   01 STANDARD  The dark band down the right edge with the first Legendary as a red halftone print,
##                the banner's name set huge on its side (two-tone across the band, the last word in
##                signal), the Legendary in full colour in front, the other two as framed prints on
##                the band; the pity as a tick ruler down the left edge and a stamp on a silver disc.
##   02 FEATURED  The week's rate-up Legendary huge in full colour over a signal block carrying her
##                print in ink, "RATE UP" set giant on its side across the block's edge, her name as
##                the headline; the 50/50 as a printed table and a stamp (50%, or 100% after a miss),
##                the rotation (ends in, next hero) in micro type, the pity ruler down the right edge.
##   03 FACTION   Today's faction in its own print colours (tinted paper, a band in the faction's
##                dark, the halftone in its ink), the faction name giant on its side, its five heroes
##                as a contact strip down the right, the Legendary in front, the three-day timetable.
##   04 WISH      "I wish for" in the serif and the chosen Legendary's name in signal, her figure in
##                front of "THE WISH"; the three choices as framed prints on the band (tap one to wish
##                for her, the wished one ringed in grease pencil) and "CHANGE" opens the picker sheet;
##                the week's 30 wishes as a punch card. Without a wish the poster asks for one.
##   05 ENVOY     A cheap flyer taped to the matte: newsprint in one ink, "ENVOY'S DRAW", the Rare and
##                Epic lineup as newspaper halftones, the odds as big numbers, today's ten draws as a
##                coupon row (used ones crossed out). Paid in gold.
##
## Every pull is a printed TICKET (_ticket, the one helper for all of them, including Again on the
## results): a perforated stub with a serial number and a barcode, "ADMIT ONE" / "ADMIT TEN", the
## price, a tear line with round notches and a torn edge. Each banner prints its tickets in its own
## colours; pressing one sinks it and starts tearing the stub along the perforation. The standard x1
## ticket is the free daily pull when it is ready (else it says when the next one comes). Prices use
## scrolls first, then gems (gold on the envoy flyer); gem spending asks first. When the player can't
## pay, a signal sticker explains it and links to the Shop. Under the poster: the date and a
## signature. The bottom nav stays up on the banner and on the results; only the reveal hides it.
##
## Summoning plays the full-screen sequence (src/ui/summon/summon_sequence.gd) with the chrome
## hidden: a press run, every hero's own poster to tap through, then the results as a contact sheet
## (with the top bar and nav back) with Again (a ticket) or Done. "Skip" jumps to the results.
##
## Shot params: banner: "standard" | "featured" | "faction" | "wish" | "envoy" (which poster; the
## default is the last one seen, standard on a new run and while the guide points at the summon),
## pick: true (open the wish picker), rates: true (open the odds), pull: 1|10 (summon right away),
## skip: true (jump straight to the results). Without touching the save: demo: "ten" | "one" |
## "rare" | "epic" | "legendary" plays made-up results (hero: an id for the single ones), card: k
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
const BONE := Color("f4f3ef")
const NEWSPRINT := Color("dedbd1")
const TICKET_H := 148.0
## Print colours of each faction's poster: [paper, band, ink].
const FACTION_PRINT := {
	"celestial": [Color("efe7d2"), Color("221b0e"), Color("c08a12")],
	"infernal": [Color("ede0da"), Color("230c0c"), Color("e3242c")],
	"fallen": [Color("e3e0ec"), Color("16121f"), Color("7a58f0")],
}
const WEEKDAYS := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

## The banner shown last (the screen opens on it again during this run).
static var _last_banner := "standard"

var _bid := "standard"
var _banner: Dictionary = {}
var _main: Control
var _stage: Control
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
	var want := str(params.get("banner", _last_banner))
	# First session: the guide points at the standard banner's free pull and 10-pull.
	if Guide.step() == "summon" and not params.has("banner"):
		want = "standard"
	_bid = want if not Game.banner(want).is_empty() else "standard"
	_last_banner = _bid
	_banner = Game.banner(_bid)
	UI.set_full_bleed(true)
	_main = Control.new()
	_main.name = "Banner"
	_main.mouse_filter = MOUSE_FILTER_IGNORE
	_main.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_main)
	_reason = PK.print_button("", func() -> void: UI.go("home" if str(_banner.get("currency", "")) == "gold" else "shop"),
		{"size": Vector2(520, Kit.BUTTON_H)})
	_reason.name = "Reason"
	_reason.visible = false
	resized.connect(_compose_soon)
	Game.changed.connect(_refresh)
	_compose_soon()
	if bool(params.get("rates", false)):
		_open_rates.call_deferred()
	if bool(params.get("pick", false)):
		_open_wish_picker.call_deferred()
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
	_do_summon(count, count == 1 and _bid == "standard" and Game.free_pull_available())
	if skip and _seq:
		_seq.skip_all()


## Screenshots without touching the save: plays made-up results (see the header).
func _shot_demo(params: Dictionary) -> void:
	await get_tree().process_frame
	_results = _demo_results(str(params.get("demo", "ten")), str(params.get("hero", "")))
	var feat := str(_banner.get("featured", ""))
	for x: Variant in _results:
		if feat != "":
			(x as Dictionary)["featured"] = str((x as Dictionary).hero_id) == feat
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


# ------------------------------------------------------------------ banner switching

func _ids() -> Array[String]:
	var out: Array[String] = []
	for b: Dictionary in Game.banners():
		out.append(str(b.id))
	return out


func _kind() -> String:
	return str(_banner.get("kind", "standard"))


## The banner's number in the index ("01" for the standard one).
func _no() -> String:
	return "%02d" % (_ids().find(_bid) + 1)


func _select(i: int) -> void:
	var ids := _ids()
	if i < 0 or i >= ids.size() or ids[i] == _bid or _phase != "":
		return
	_bid = ids[i]
	_last_banner = _bid
	_recompose(true)


## Rebuilds the whole poster (a new banner, a new wish); slide: the new poster slides in.
func _recompose(slide: bool = false) -> void:
	_composed_for = Vector2.ZERO
	_compose()
	if slide and _stage and Kit.motion_ok():
		_stage.modulate.a = 0.0
		_stage.position.x = 28.0
		var tw := _stage.create_tween().set_parallel(true)
		tw.tween_property(_stage, "modulate:a", 1.0, 0.18)
		tw.tween_property(_stage, "position:x", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ the poster

func _compose_soon() -> void:
	_compose.call_deferred()


## Builds the index and the current banner's poster for the current size (again after a resize: the
## chrome can change the content area). The parts that follow the save (tickets, pity, reason) are
## rebuilt by _refresh.
func _compose() -> void:
	if not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	if _composed_for == size:
		return
	_composed_for = size
	_banner = Game.banner(_bid)
	if _reason.get_parent():
		_reason.get_parent().remove_child(_reason)
	for c in _main.get_children():
		_main.remove_child(c)
		c.queue_free()
	var w := size.x
	var top := UI.content_top()
	var bot := size.y - UI.content_bottom()
	PK.matte(_main)
	# The printed banner index.
	var items: Array = []
	for b: Dictionary in Game.banners():
		items.append(str(b.get("short", b.id)))
	var idx := PK.index_tabs(items, _ids().find(_bid), _select, w - 36)
	idx.name = "BannerIndex"
	idx.position = Vector2(18, top - 8)
	_main.add_child(idx)
	PK.rule(_main, Rect2(18, top + 70, w - 36, 1), Color(INK, 0.3))
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.size = size
	_main.add_child(_stage)
	var pr := Rect2(18, top + 86, w - 36, maxf(560.0, bot - 74 - (top + 86)))
	match _kind():
		"featured":
			_compose_featured(pr)
		"faction":
			_compose_faction(pr)
		"wish":
			_compose_wish(pr)
		"envoy":
			_compose_envoy(pr)
		_:
			_compose_standard(pr)
	# The dynamic layer (tickets, pity, reason), then the line under the poster and the grain.
	_dyn = Control.new()
	_dyn.name = "Live"
	_dyn.mouse_filter = MOUSE_FILTER_IGNORE
	_dyn.size = size
	_stage.add_child(_dyn)
	_footer(pr, w)
	PK.grain(_main, 0.06)
	_main.set_meta("poster_rect", pr)
	_sig = ""
	_refresh()
	SignalKit.relight(_main)


## Under the poster: the printed date and a signature in the serif.
func _footer(pr: Rect2, w: float) -> void:
	var foot := pr.end.y + 12.0
	var d := _date(Game.today())
	PK.at(_stage, PK.t("%d %02d/%02d" % [int(d.year), int(d.month), int(d.day)], 24, INK, "regular"), Vector2(20, foot + 18))
	var who := ""
	match _kind():
		"faction":
			who = str(Kit.FACTION_NAMES.get(str(_banner.get("faction", "")), ""))
		"wish":
			who = str(Game.hero_def(_feature).get("name", "")) if str(_banner.get("target", "")) != "" else "make a wish"
		"envoy":
			who = "the Envoy"
		_:
			who = str(Game.hero_def(_feature).get("name", _feature))
	var sig := PK.t(who, 46, INK, "serif_italic")
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.size = Vector2(320, 52)
	PK.at(_stage, sig, Vector2(w - 24 - 320, foot + 2))
	PK.rule(_stage, Rect2(w - 236, foot + 52, 210, 2), INK).rotation = -0.05


func _legends() -> Array:
	return (_banner.get("pool_by_rarity", {}) as Dictionary).get("legendary", [])


## The game's day index as a date ({year, month, day, weekday}).
static func _date(day: int) -> Dictionary:
	return Time.get_date_dict_from_unix_time(day * 86400)


## "19.10.26" for a day index.
static func _short_date(day: int) -> String:
	var d := _date(day)
	return "%02d.%02d.%02d" % [int(d.day), int(d.month), int(d.year) % 100]


## RATES (opens the odds) and the rates as printed micro type at pos; returns the y under them.
func _rates_block(parent: Control, pos: Vector2, ink: Color = INK, accent: Color = SIG, align_right: bool = false) -> float:
	var rates_btn := PK.print_button("RATES  ↗", _open_rates, {"size": Vector2(150, 60), "text_size": 13, "color": ink,
		"align": "right" if align_right else "left"})
	rates_btn.name = "Rates"
	PK.at(parent, rates_btn, pos + Vector2(-150 if align_right else 0, 28))
	var rates: Dictionary = _banner.get("rates", {})
	var ry := pos.y + 86.0
	for r: String in ["legendary", "epic", "rare"]:
		if int(rates.get(r, 0)) <= 0:
			continue
		var row := PK.t("%-10s %6s" % [str(Kit.RARITY_NAMES[r]).to_upper(), _pct(float(int(rates.get(r, 0))))], 11,
			accent if r == "legendary" else ink, "mono_bold")
		if align_right:
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.size = Vector2(200, 16)
			PK.at(parent, row, Vector2(pos.x - 200, ry))
		else:
			PK.at(parent, row, Vector2(pos.x, ry))
		ry += 16.0
	var guarantee := str(_banner.get("ten_pull_guarantee", "epic"))
	var gl := PK.t("x10: %s OR BETTER" % str(Kit.RARITY_NAMES.get(guarantee, guarantee)).to_upper(), 10, Color(ink, 0.7), "mono")
	if align_right:
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gl.size = Vector2(200, 16)
		PK.at(parent, gl, Vector2(pos.x - 200, ry + 2))
	else:
		PK.at(parent, gl, Vector2(pos.x, ry + 2))
	return ry + 20.0


## A hero in full colour, feet at `feet`, `fig_h` tall, clipped to `clip` (poster px); tap her for
## her page (unless tappable is false).
func _figure(clip: Rect2, id: String, feet: Vector2, fig_h: float, tappable: bool = true) -> void:
	var box := Control.new()
	box.clip_contents = true
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.position = clip.position
	box.size = clip.size
	_poster.add_child(box)
	var local := feet - clip.position
	PK.hero_fig(box, id, "", local, fig_h)
	if not tappable:
		return
	var hit := Control.new()
	hit.name = "Hit_" + id
	hit.mouse_filter = MOUSE_FILTER_PASS
	hit.position = Vector2(local.x - 130, local.y - fig_h * 0.92)
	hit.size = Vector2(260, fig_h * 0.62)
	box.add_child(hit)
	Kit.make_tappable(hit, func() -> void: UI.go("hero_detail", {"hero_id": id}))


## A small framed print of a hero (portrait in a hairline frame, a caption under it), tappable.
func _framed_print(parent: Control, id: String, pos: Vector2, s: float, caption: String, frame: Color, on_tap: Callable) -> Control:
	var fr := Control.new()
	fr.name = "Print_" + id
	fr.mouse_filter = MOUSE_FILTER_PASS
	fr.position = pos
	fr.size = Vector2(s, s + 26)
	parent.add_child(fr)
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.size = Vector2(s, s)
	fr.add_child(bg)
	var pic := HeroArt.make_portrait(id, s - 4, "")
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.position = Vector2(2, 2)
	pic.size = Vector2(s - 4, s - 4)
	fr.add_child(pic)
	PK.hairbox(fr, Rect2(0, 0, s, s), frame)
	PK.at(fr, PK.t(caption, 10, frame, "mono_bold"), Vector2(0, s + 4))
	Kit.make_tappable(fr, on_tap)
	return fr


# ------------------------------------------------------------------ 01 standard

func _compose_standard(pr: Rect2) -> void:
	_poster = PK.poster(_stage, pr)
	var pw := pr.size.x
	var ph := pr.size.y
	var bx := pw - BAND_W
	var legends := _legends()
	_feature = str(legends[0]) if not legends.is_empty() else "seraphiel"
	var def := Game.hero_def(_feature)
	# The band: the first Legendary as a red halftone print, micro type in paper white.
	var band := PK.band(_poster, Rect2(bx, 0, BAND_W, ph), _feature, "", {"from": 0.2, "cell": 7.0})
	PK.vt(band, "©2026 HH, ALL RIGHTS RESERVED.", 10, Color(PAPER, 0.75), Vector2(BAND_W - 6, ph * 0.62))
	PK.at(band, PK.t("No.\n001", 12, Color(PAPER, 0.85), "mono_bold"), Vector2(14, ph * 0.46))
	PK.at(band, PK.t(_short_date(Game.today()), 12, Color(PAPER, 0.85), "mono_bold"), Vector2(14, ph * 0.46 + 40))
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
	_rates_block(_poster, Vector2(64, 16))
	# Left edge: a hairline and vertical micro type (the pity ruler is live, in _refresh).
	PK.rule(_poster, Rect2(48, 0, 1, ph), Color(INK, 0.55))
	PK.vt(_poster, "©2026 · PORTAL Nº 01 · EVERY HERO CAN ANSWER", 12, INK, Vector2(36, 14))
	# The Legendary in full colour, in front of the type (tap her for her page).
	_figure(Rect2(49, 0, pw - 49, ph), _feature, Vector2(bx * 0.46 + 10.0, ph - 4.0), ph * 0.95)
	# The other Legendaries: small framed prints stuck on the band.
	var fy := ph * 0.56
	for i in range(1, mini(3, legends.size())):
		var id := str(legends[i])
		var d := Game.hero_def(id)
		var fr := _framed_print(_poster, id, Vector2(bx + 22, fy), 92.0, "%02d %s" % [i + 1, str(d.get("name", id)).to_upper()], Color(PAPER, 0.8),
			func() -> void: UI.go("hero_detail", {"hero_id": id}))
		fr.name = "Feature_" + id
		fy += 132.0


func _live_standard(pr: Rect2) -> void:
	var ph := pr.size.y
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(_banner.get("pity", 0))
	var left := maxi(1, pity_max - pity)
	var tk := PK.ticks(pity_max, pity, Vector2(ph * 0.46, 18), INK, SIG)
	tk.rotation = PI * 0.5
	tk.position = pr.position + Vector2(40, ph * 0.3)
	_dyn.add_child(tk)
	PK.vt(_dyn, "PITY %02d / %d" % [pity, pity_max], 12, INK, pr.position + Vector2(38, ph * 0.3 - 112))
	PK.at(_dyn, PK.t("LEGENDARY GUARANTEED\nWITHIN %d PULL%s" % [left, "" if left == 1 else "S"], 10, INK, "mono_bold"), pr.position + Vector2(64, 186))
	PK.rule(_dyn, Rect2(pr.position + Vector2(64, 180), Vector2(130, 1)), Color(INK, 0.5))
	var st := PK.stamp_disc(_dyn, pr.position + Vector2(64, ph - 316), 112, "LEGENDARY · WITHIN · PULLS · ", "%02d" % left)
	st.name = "Pity"
	if bool(Game.free_pull_available()):
		PK.led(_dyn, pr.position + Vector2(24, ph * 0.3 - 136), "blink")


# ------------------------------------------------------------------ 02 featured

func _compose_featured(pr: Rect2) -> void:
	_poster = PK.poster(_stage, pr)
	var pw := pr.size.x
	var ph := pr.size.y
	var sw := 250.0
	_feature = str(_banner.get("featured", "mordessa"))
	var def := Game.hero_def(_feature)
	# The signal block with her print in ink dots.
	PK.band(_poster, Rect2(0, 0, sw, ph), _feature, "", {"color": SIG, "ink": Color(INK, 0.9), "light_dots": false,
		"from": 0.36, "cell": 8.0, "gain": 1.1})
	# RATE UP, giant on its side across the block's edge: paper white on the block, signal on the paper.
	var fs := 236
	while fs > 120 and Kit.font("compressed").get_string_size("RATE UP", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > ph * 0.94:
		fs -= 6
	PK.giant(_poster, "RATE UP", fs, [[0.0, sw, PAPER], [sw, pw - sw, SIG]], Vector2(sw + fs * 0.5, ph * 0.02), Vector2(ph * 1.2, fs * 1.3))
	# Micro type down the block's left edge: the run and the rotation.
	var week := SummonRules.period_index(Game.today(), EconomyData.BANNER_EPOCH_DAY, int(_banner.get("rotation_days", 7))) + 1
	var next_day := int(_banner.get("next_change_day", Game.today() + 7))
	var next_id := SummonRules.featured_for(EconomyData.banner_def(_bid), next_day, EconomyData.BANNER_EPOCH_DAY)
	PK.vt(_poster, "PORTAL Nº %s · RATE UP · WEEK %02d · UNTIL %s · NEXT: %s" % [_no(), week, _short_date(next_day - 1),
		str(Game.hero_def(next_id).get("name", next_id)).to_upper()], 11, INK, Vector2(24, 14))
	# Top right: the rates (RATES opens the odds), right-aligned on the paper.
	_rates_block(_poster, Vector2(pw - 18, -14), INK, SIG, true)
	# Her name as the headline across the block's edge (two-tone, behind her), her title under it.
	var name_up := str(def.get("name", _feature)).to_upper()
	var nfs := 150
	while nfs > 70 and Kit.font("compressed").get_string_size(name_up, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x > pw - 30:
		nfs -= 4
	var ncap := PK.caps(Kit.font("compressed"), nfs)
	PK.giant(_poster, name_up, nfs, [[0.0, sw, PAPER], [sw, pw - sw, INK]], Vector2(14, ph - 236 - ncap.y), Vector2(pw + 40, nfs * 1.3), 0.0)
	var tl := PK.t("%s  ·  %s  ·  %s" % [str(def.get("title", "")).to_upper(), str(Kit.FACTION_NAMES.get(str(def.get("faction", "")), "")).to_upper(),
		str(Kit.ROLE_NAMES.get(str(def.get("role", "")), "")).to_upper()], 11, INK, "mono_bold")
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl.size = Vector2(pw - sw - 24, 16)
	PK.at(_poster, tl, Vector2(sw + 4, ph - 222))
	# Her, huge, in front of the type.
	_figure(Rect2(0, 0, pw, ph), _feature, Vector2(pw * 0.5, ph - 2.0), ph * 0.98)
	# The others she shares the Legendary slot with.
	var others: Array = []
	for id: Variant in _legends():
		if str(id) != _feature:
			others.append(str(Game.hero_def(str(id)).get("name", id)).to_upper())
	var also := PK.t("ON A MISS: %s" % " / ".join(others), 10, INK, "mono_bold")
	PK.at(_poster, also, Vector2(14, ph - 186))


func _live_featured(pr: Rect2) -> void:
	var ph := pr.size.y
	var pw := pr.size.x
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(_banner.get("pity", 0))
	var left := maxi(1, pity_max - pity)
	var lost := bool(_banner.get("lost", false))
	var fbp := int(_banner.get("featured_bp", 5000))
	# The 50/50 as a printed table on the signal block.
	var rows: Array = [
		["RATE UP", _pct(float(fbp))],
		["AFTER A MISS", "100%"],
		["NEXT LEGENDARY", "HERS" if lost else "50 / 50", true],
		["GUARANTEED IN", "%d PULL%s" % [left, "" if left == 1 else "S"]],
	]
	# Printed on a paper slip stuck to the block, so the dots behind don't eat the type.
	var slip := ColorRect.new()
	slip.mouse_filter = MOUSE_FILTER_IGNORE
	slip.color = BONE
	slip.position = pr.position + Vector2(6, ph * 0.42 - 6)
	slip.size = Vector2(238, rows.size() * 26.0 + 12)
	slip.pivot_offset = slip.size * 0.5
	slip.rotation = -0.015
	_dyn.add_child(slip)
	var tb := PK.data_table(rows, 232.0, {"size": 12, "row_h": 26.0, "bar": Color(SIG, 0.18)})
	tb.position = Vector2(3, 6)
	slip.add_child(tb)
	var st := PK.stamp_disc(_dyn, pr.position + Vector2(58, ph * 0.42 - 140), 118,
		("NEXT ONE · IS HERS · " if lost else "FEATURED · LEGENDARY · "), "100%" if lost else _pct(float(fbp)), -0.1)
	st.name = "Pity"
	# Pity: a printed tick ruler down the poster's right edge.
	var tk := PK.ticks(pity_max, pity, Vector2(ph * 0.42, 16), INK, SIG)
	tk.rotation = PI * 0.5
	tk.position = pr.position + Vector2(pw - 10, ph * 0.3)
	_dyn.add_child(tk)
	PK.vt(_dyn, "PITY %02d / %d" % [pity, pity_max], 12, INK, pr.position + Vector2(pw - 12, ph * 0.3 - 112))
	if lost:
		var tag := PK.sticker([["GUARANTEED", 14, "wide_black"], ["THE NEXT LEGENDARY IS %s" % str(Game.hero_def(_feature).get("name", "")).to_upper(), 10, "mono_bold"]],
			{"fill": "ink", "rotation": 0.04})
		tag.position = pr.position + Vector2(10, ph * 0.42 + rows.size() * 26.0 + 22)
		_dyn.add_child(tag)


# ------------------------------------------------------------------ 03 faction

func _faction_print(fac: String) -> Array:
	return FACTION_PRINT.get(fac, [PAPER, PK.BAND, SIG])


func _compose_faction(pr: Rect2) -> void:
	var fac := str(_banner.get("faction", "celestial"))
	var fp := _faction_print(fac)
	var paper: Color = fp[0]
	var dark: Color = fp[1]
	var ink: Color = fp[2]
	_poster = PK.poster(_stage, pr, paper)
	var pw := pr.size.x
	var ph := pr.size.y
	var bw := 200.0
	var legends := _legends()
	var pool: Array = _banner.get("pool", [])
	_feature = str(legends[0]) if not legends.is_empty() else (str(pool[0]) if not pool.is_empty() else "seraphiel")
	# The band in the faction's dark, its Legendary printed in the faction's ink.
	var band := PK.band(_poster, Rect2(0, 0, bw, ph), _feature, "", {"color": dark, "ink": Color(ink, 0.95), "from": 0.32, "cell": 7.0})
	PK.vt(band, "FACTION FOCUS · PORTAL Nº %s · %s ONLY · ©2026 HH" % [_no(), fac.to_upper()], 10, Color(PAPER, 0.8), Vector2(bw - 6, 14))
	# The faction's name, giant on its side: paper on the band, the faction's ink on the paper.
	var word := str(Kit.FACTION_NAMES.get(fac, fac)).to_upper()
	var fs := 250
	while fs > 120 and Kit.font("compressed").get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > ph * 0.94:
		fs -= 6
	PK.giant(_poster, word, fs, [[0.0, bw, PAPER], [bw, pw - bw, ink]], Vector2(bw + fs * 0.4, ph * 0.02), Vector2(ph * 1.2, fs * 1.3))
	# Top: the emblem in a hairline ring, the day's line and the rates.
	var ex := bw + fs * 0.2 + 18.0
	var ring := _Ring.new()
	ring.color = INK
	ring.position = Vector2(ex, 16)
	ring.size = Vector2(62, 62)
	_poster.add_child(ring)
	var em := Kit.faction_icon(fac, 40)
	em.modulate = INK
	em.position = Vector2(ex + 11, 27)
	em.mouse_filter = MOUSE_FILTER_IGNORE
	_poster.add_child(em)
	var left_ms := int(_banner.get("ms_until_change", 0))
	PK.at(_poster, PK.t("TODAY ONLY\n%s FOCUS\nCHANGES IN %s" % [word, Kit.format_time(left_ms).to_upper()], 11, INK, "mono_bold"), Vector2(ex + 74, 18))
	_rates_block(_poster, Vector2(ex, 62))
	# The faction's heroes as a contact strip down the right edge (the Legendary first).
	var ids: Array = []
	for r: String in ["legendary", "epic", "rare"]:
		for id: Variant in (_banner.get("pool_by_rarity", {}) as Dictionary).get(r, []):
			ids.append(str(id))
	var step := minf(128.0, (ph - 190.0) / maxf(1.0, float(ids.size())))
	var s := step - 30.0
	var sx := pw - s - 18.0
	PK.rule(_poster, Rect2(sx - 10, 0, 1, ph), Color(INK, 0.4))
	for i in ids.size():
		var id := str(ids[i])
		var d := Game.hero_def(id)
		var rr := str(d.get("rarity", "rare"))
		_framed_print(_poster, id, Vector2(sx, 14 + i * step), s, "%02d %s" % [i + 1, str(d.get("name", id)).to_upper()],
			ink if rr == "legendary" else Color(INK, 0.75), func() -> void: UI.go("hero_detail", {"hero_id": id}))
	# The Legendary in full colour, in front.
	_figure(Rect2(bw, 0, sx - 12 - bw, ph), _feature, Vector2(bw + (sx - bw) * 0.5, ph - 4.0), ph * 0.9)
	# The timetable on the band: today and the next two days.
	var cb := EconomyData.banner_def(_bid)
	var rows: Array = []
	var day := Game.today()
	for k in 3:
		var dd := _date(day + k)
		var f2 := SummonRules.faction_for(cb, day + k, EconomyData.BANNER_EPOCH_DAY)
		rows.append(["%s %02d" % [WEEKDAYS[int(dd.weekday)], int(dd.day)], str(Kit.FACTION_NAMES.get(f2, f2)).to_upper(), k == 0])
	var back := ColorRect.new()
	back.mouse_filter = MOUSE_FILTER_IGNORE
	back.color = Color(dark, 0.88)
	back.position = Vector2(0, ph - 324)
	back.size = Vector2(bw, 3 * 26.0 + 40)
	_poster.add_child(back)
	PK.at(_poster, PK.t("TIMETABLE", 10, Color(PAPER, 0.75), "mono_bold"), Vector2(14, ph - 316))
	var tb := PK.data_table(rows, bw - 12, {"size": 11, "row_h": 26.0, "color": PAPER, "bar": Color(1, 1, 1, 0.12)})
	tb.position = Vector2(6, ph - 296)
	_poster.add_child(tb)


func _live_faction(pr: Rect2) -> void:
	var ph := pr.size.y
	var fac := str(_banner.get("faction", "celestial"))
	var ink: Color = _faction_print(fac)[2]
	var pity_max := int(_banner.get("pity_legendary", 80))
	var pity := int(_banner.get("pity", 0))
	var left := maxi(1, pity_max - pity)
	var tk := PK.ticks(pity_max, pity, Vector2(ph * 0.4, 16), INK, ink)
	tk.rotation = PI * 0.5
	tk.position = pr.position + Vector2(222, ph * 0.36)
	_dyn.add_child(tk)
	PK.vt(_dyn, "PITY %02d / %d" % [pity, pity_max], 11, INK, pr.position + Vector2(220, ph * 0.36 - 104))
	var st := PK.stamp_disc(_dyn, pr.position + Vector2(44, ph * 0.38), 112, "%s · LEGENDARY · WITHIN · " % fac.to_upper(), "%02d" % left, 0.1)
	st.name = "Pity"


# ------------------------------------------------------------------ 04 wish

func _compose_wish(pr: Rect2) -> void:
	_poster = PK.poster(_stage, pr)
	var pw := pr.size.x
	var ph := pr.size.y
	var bx := pw - BAND_W
	var target := str(_banner.get("target", ""))
	var choices: Array = _banner.get("choices", [])
	_feature = target if target != "" else (str(choices[0]) if not choices.is_empty() else "seraphiel")
	var band := PK.band(_poster, Rect2(bx, 0, BAND_W, ph), target, "", {"from": 0.5, "cell": 7.0})
	PK.vt(band, "PORTAL Nº %s · THE WISH · ©2026 HH" % _no(), 10, Color(PAPER, 0.75), Vector2(BAND_W - 6, 14))
	# THE WISH, giant on its side (WISH in signal), two-tone across the band.
	var fs := 200
	PK.giant(_poster, "THE [color=#%s]WISH[/color]" % SIG.to_html(false), fs, [[0.0, bx, INK], [bx, BAND_W, PAPER]],
		Vector2(pw - 30, ph * 0.03), Vector2(ph * 1.1, 260))
	# The request line, top left: "I wish for" in the serif, her name in signal on a hairline.
	PK.rule(_poster, Rect2(48, 0, 1, ph), Color(INK, 0.55))
	PK.at(_poster, PK.t("I wish for", 40, INK, "serif_italic"), Vector2(64, 6))
	var nm := PK.t(str(Game.hero_def(target).get("name", "")).to_upper() if target != "" else "________", 64, SIG if target != "" else Color(INK, 0.5), "compressed")
	PK.at(_poster, nm, Vector2(64, 50))
	PK.rule(_poster, Rect2(64, 122, 240, 1), INK)
	_rates_block(_poster, Vector2(64, 100))
	# The wished hero in full colour inside reserved-slot corner marks, or the empty slot (her page
	# opens from her print on the band).
	var slot := Rect2(70, ph * 0.3, bx - 96, ph * 0.7 - 170)
	var br := PK.brackets(slot.size, Color(INK, 0.6), 22.0, 1.5)
	br.position = slot.position
	_poster.add_child(br)
	if target != "":
		_figure(Rect2(49, 0, pw - 49, ph), target, Vector2(bx * 0.5 + 6.0, ph - 4.0), ph * 0.86, false)
	else:
		var ask := PK.t("YOUR WISH\nGOES HERE", 48, Color(INK, 0.35), "compressed")
		ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ask.size = Vector2(slot.size.x, 120)
		PK.at(_poster, ask, slot.position + Vector2(0, slot.size.y * 0.3))
		var b := PK.print_button("PICK A LEGENDARY  ↗", _open_wish_picker, {"size": Vector2(slot.size.x, 70), "text_size": 15, "color": SIG, "align": "center"})
		b.name = "PickWishSlot"
		PK.at(_poster, b, slot.position + Vector2(0, slot.size.y * 0.3 + 128))
	# The choices on the band: tap one to wish for her; the wished one is ringed in grease pencil.
	var fy := ph * 0.1
	for i in choices.size():
		var id := str(choices[i])
		var d := Game.hero_def(id)
		var on := id == target
		var fr := _framed_print(_poster, id, Vector2(bx + 30, fy), 104.0, ("%02d %s" % [i + 1, str(d.get("name", id)).to_upper()]) + ("  ✓" if on else ""),
			SIG if on else Color(PAPER, 0.8), func() -> void: _wish_for(id))
		fr.name = "Wish_" + id
		if on:
			var loop := _Loop.new()
			loop.position = Vector2(-12, -12)
			loop.size = Vector2(128, 128)
			fr.add_child(loop)
		fy += 150.0
	var pick := PK.print_button("CHANGE WISH  ↗" if target != "" else "CHOOSE  ↗", _open_wish_picker,
		{"size": Vector2(BAND_W - 40, 64), "text_size": 13, "color": PAPER if target != "" else SIG})
	pick.name = "PickWish"
	PK.at(_poster, pick, Vector2(bx + 30, fy - 10))


func _live_wish(pr: Rect2) -> void:
	var ph := pr.size.y
	var pity_max := int(_banner.get("pity_legendary", 60))
	var pity := int(_banner.get("pity", 0))
	var left := maxi(1, pity_max - pity)
	var tk := PK.ticks(pity_max, pity, Vector2(ph * 0.4, 18), INK, SIG)
	tk.rotation = PI * 0.5
	tk.position = pr.position + Vector2(40, ph * 0.34)
	_dyn.add_child(tk)
	PK.vt(_dyn, "PITY %02d / %d" % [pity, pity_max], 12, INK, pr.position + Vector2(38, ph * 0.34 - 112))
	var st := PK.stamp_disc(_dyn, pr.position + Vector2(64, ph - 300), 104, "WISH · GRANTED · WITHIN · ", "%02d" % left)
	st.name = "Pity"
	# The week's wishes as a punch card: used ones punched out.
	var lim := int(_banner.get("limit_max", 30))
	var lleft := int(_banner.get("limit_left", lim))
	var card := _Punch.new()
	card.count = lim
	card.used = lim - lleft
	card.position = pr.position + Vector2(64, ph - 410)
	card.size = Vector2(212, 70)
	_dyn.add_child(card)
	PK.at(_dyn, PK.t("THIS WEEK  %d / %d WISHES LEFT  ·  RESETS IN %s" % [lleft, lim, Kit.format_time(int(_banner.get("ms_until_limit_reset", 0))).to_upper()],
		10, INK, "mono_bold"), pr.position + Vector2(64, ph - 432))


func _wish_for(id: String) -> void:
	if id == str(_banner.get("target", "")):
		UI.go("hero_detail", {"hero_id": id})
		return
	var r := Game.set_wish_target(id)
	if not bool(r.get("ok", false)):
		UI.toast(str(r.get("error", "")), "bad")
		return
	Kit.haptic(20)
	_recompose(false)


## The picker sheet: the three Legendaries as prints; tap one to wish for her.
func _open_wish_picker() -> void:
	if _kind() != "wish" or _phase != "":
		return
	var choices: Array = _banner.get("choices", [])
	var target := str(_banner.get("target", ""))
	var v := Kit.vbox(16)
	v.custom_minimum_size.x = 560
	v.add_child(Kit.body("Every Legendary from The Wish is the hero you choose. You can change your wish at any time; the pity carries over.", 21, Kit.TEXT_DIM))
	var row := Kit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var modal_ref: Array[Control] = []
	for id: Variant in choices:
		var hid := str(id)
		var d := Game.hero_def(hid)
		var on := hid == target
		var b := PK.bare_button(Vector2(176, 330))
		b.name = "Choose_" + hid
		var face := Control.new()
		face.mouse_filter = MOUSE_FILTER_IGNORE
		face.size = Vector2(176, 330)
		b.add_child(face)
		var bg := ColorRect.new()
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		bg.color = SIG if on else PAPER
		bg.size = Vector2(176, 330)
		face.add_child(bg)
		var art := TextureRect.new()
		art.mouse_filter = MOUSE_FILTER_IGNORE
		art.texture = Kit.art_crop(hid, 164.0 / 224.0, 1.0, "")
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.position = Vector2(6, 6)
		art.size = Vector2(164, 224)
		face.add_child(art)
		PK.hairbox(face, Rect2(6, 6, 164, 224), Color(INK, 0.6))
		var nl := PK.t(str(d.get("name", hid)).to_upper(), 40, INK, "compressed")
		Kit.fit_label(nl, 160, 40, 20)
		nl.position = Vector2(8, 232)
		face.add_child(nl)
		PK.at(face, PK.t(str(d.get("title", "")).to_upper(), 9, INK, "mono_bold"), Vector2(9, 280))
		PK.at(face, PK.t("✓ YOUR WISH" if on else "WISH FOR HER  >>>", 11, PAPER if on else SIG, "mono_bold"), Vector2(9, 302))
		PK.wire(b, [face], func() -> void:
			var r := Game.set_wish_target(hid)
			if not bool(r.get("ok", false)):
				UI.toast(str(r.get("error", "")), "bad")
				return
			if not modal_ref.is_empty():
				UI.close_modal(modal_ref[0])
			_recompose(false))
		row.add_child(b)
	var m := UI.popup("Choose Your Wish", Kit.margin(v, 4, 4), Callable(), 640.0, true)
	modal_ref.append(m)


# ------------------------------------------------------------------ 05 envoy

func _compose_envoy(pr: Rect2) -> void:
	# A cheap flyer taped to the matte, a little crooked.
	var fr := Rect2(pr.position + Vector2(6, 2), pr.size - Vector2(12, 4))
	_poster = PK.poster(_stage, fr, NEWSPRINT, 0.2)
	var pw := fr.size.x
	var ph := fr.size.y
	var sh: Control = _poster.get_meta("shadow")
	for c: Control in [_poster, sh]:
		c.pivot_offset = fr.size * 0.5
		c.rotation = -0.012
	for side in 2:
		var tape := ColorRect.new()
		tape.mouse_filter = MOUSE_FILTER_IGNORE
		tape.color = Color(0.96, 0.93, 0.84, 0.72)
		tape.size = Vector2(118, 30)
		tape.pivot_offset = tape.size * 0.5
		tape.position = fr.position + Vector2(-34 if side == 0 else pw - 84, -10)
		tape.rotation = -0.55 if side == 0 else 0.5
		_stage.add_child(tape)
	var pool_r: Dictionary = _banner.get("pool_by_rarity", {})
	var epics: Array = pool_r.get("epic", [])
	var rares: Array = pool_r.get("rare", [])
	_feature = str(epics[0]) if not epics.is_empty() else "cassiel"
	# Header: ENVOY'S in wide type over DRAW, huge; the price stuck on as a signal sticker.
	PK.at(_poster, PK.t("PORTAL Nº %s  ·  BY ORDER OF THE ENVOY  ·  %s" % [_no(), _short_date(Game.today())], 11, INK, "mono_bold"), Vector2(24, 18))
	PK.at(_poster, PK.stencil("ENVOY'S", 58, INK, NEWSPRINT), Vector2(22, 40))
	var draw := PK.t("DRAW", 216, INK, "compressed")
	Kit.fit_label(draw, pw - 272 - 30, 216, 110)
	PK.at(_poster, draw, Vector2(14, 64))
	var cost := PK.sticker([["%s GOLD" % Kit.format_full(int(_banner.get("cost_one", 0))), 22, "wide_black"], ["A DRAW  ·  TEN FOR %s" % Kit.format_full(int(_banner.get("cost_ten", 0))), 10, "mono_bold"]],
		{"fill": "signal", "rotation": 0.07})
	cost.position = Vector2(pw - cost.size.x - 26, 52)
	_poster.add_child(cost)
	# The odds as big printed numbers.
	var rates: Dictionary = _banner.get("rates", {})
	var ox := pw - 272.0
	for i in 2:
		var r: String = ["epic", "rare"][i]
		var n := PK.t(_pct(float(int(rates.get(r, 0)))), 56, INK, "compressed")
		Kit.fit_label(n, 124, 56, 30)
		PK.at(_poster, n, Vector2(ox + i * 134, 146))
		PK.at(_poster, PK.t(str(Kit.RARITY_NAMES[r]).to_upper(), 11, INK, "mono_bold"), Vector2(ox + i * 134 + 4, 216))
	var rb := PK.print_button("RATES  ↗", _open_rates, {"size": Vector2(150, 60), "text_size": 13})
	rb.name = "Rates"
	PK.at(_poster, rb, Vector2(ox, 240))
	# Under the headline: a barcode and the flyer's validity, like a printed coupon.
	var bc := SignalKit.barcode(Vector2(196, 34), INK, 5)
	bc.position = Vector2(24, 222)
	_poster.add_child(bc)
	PK.at(_poster, PK.t("VALID %s ONLY  ·  NO REFUNDS  ·  ONE ENVOY PER DRAW" % _short_date(Game.today()), 9, INK, "mono_bold"), Vector2(24, 262))
	var sub := PK.t("RARE & EPIC ONLY  ·  NO LEGENDARY  ·  PAID IN GOLD  ·  %d DRAWS A DAY" % int(_banner.get("limit_max", 10)), 11, INK, "mono_bold")
	PK.at(_poster, sub, Vector2(24, 306))
	PK.rule(_poster, Rect2(24, 300, pw - 48, 2), INK)
	PK.rule(_poster, Rect2(24, 326, pw - 48, 1), INK)
	# The lineup as newspaper halftones in the one ink.
	var ids: Array = epics + rares
	var top := 342.0
	var avail := ph - 236.0 - top
	var rows := 3 if avail >= 470.0 else 2
	var cols := ceili(float(ids.size()) / rows)
	var gap := 10.0
	var cw := floorf((pw - 48 - (cols - 1) * gap) / cols)
	var ch := minf(floorf((avail - (rows - 1) * gap) / rows), cw * 1.5)
	for i in ids.size():
		var id := str(ids[i])
		var cx := 24 + (i % cols) * (cw + gap)
		var cy := top + (i / cols) * (ch + gap)
		var cell := Control.new()
		cell.name = "Lineup_" + id
		cell.mouse_filter = MOUSE_FILTER_PASS
		cell.position = Vector2(cx, cy)
		cell.size = Vector2(cw, ch)
		_poster.add_child(cell)
		var ht := PK.halftone_hero(id, "", {"crop": "portrait", "ink": Color(INK, 0.95), "light_dots": false, "cell": 4.5, "gain": 1.15})
		ht.position = Vector2.ZERO
		ht.size = Vector2(cw, ch - 18)
		cell.add_child(ht)
		PK.hairbox(cell, Rect2(0, 0, cw, ch - 18), Color(INK, 0.7))
		var d := Game.hero_def(id)
		var is_epic := str(d.get("rarity", "")) == "epic"
		PK.at(cell, PK.t(str(d.get("name", id)).to_upper() + (" ·E" if is_epic else ""), 9, INK, "mono_bold"), Vector2(1, ch - 15))
		Kit.make_tappable(cell, func() -> void: UI.go("hero_detail", {"hero_id": id}))


func _live_envoy(pr: Rect2) -> void:
	var ph := pr.size.y
	var lim := int(_banner.get("limit_max", 10))
	var left := int(_banner.get("limit_left", lim))
	# Today's draws as a coupon row: used ones crossed out.
	var row := _Coupons.new()
	row.count = lim
	row.used = lim - left
	row.position = pr.position + Vector2(30, ph - 226)
	row.size = Vector2(lim * 34.0, 30)
	row.rotation = -0.012
	_dyn.add_child(row)
	PK.at(_dyn, PK.t("TODAY  %d / %d DRAWS LEFT  ·  FRESH IN %s" % [left, lim, Kit.format_time(int(_banner.get("ms_until_limit_reset", 0))).to_upper()], 10, INK, "mono_bold"),
		pr.position + Vector2(30, ph - 186))


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if not is_inside_tree() or _dyn == null or not is_instance_valid(_dyn):
		return
	_banner = Game.banner(_bid)
	var free_ready := _bid == "standard" and bool(Game.free_pull_available())
	var p1 := _price(1)
	var p10 := _price(10)
	var guide := Guide.step() == "summon" and _bid == "standard"
	var sig := "%s|%d|%s|%s|%s|%s|%d|%s|%s" % [_bid, int(_banner.get("pity", 0)), free_ready, JSON.stringify(p1), JSON.stringify(p10), guide,
		int(_banner.get("limit_left", -1)), str(_banner.get("target", "")), bool(_banner.get("lost", false))]
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
	match _kind():
		"featured":
			_live_featured(pr)
		"faction":
			_live_faction(pr)
		"wish":
			_live_wish(pr)
		"envoy":
			_live_envoy(pr)
		_:
			_live_standard(pr)
	# The tickets, stuck over the poster's bottom edge.
	var y := pr.end.y - TICKET_H
	var t1 := _ticket(_ticket_spec(1, free_ready), func() -> void:
		if free_ready:
			_do_summon(1, true)
		else:
			_try_summon(1))
	t1.name = "Summon1"
	t1.position = Vector2(pr.position.x - 6, y + 4)
	t1.rotation = -0.03
	_dyn.add_child(t1)
	var t10 := _ticket(_ticket_spec(10, false), func() -> void: _try_summon(10))
	t10.name = "Summon10"
	t10.position = Vector2(pr.end.x - t10.size.x + 8, y - 4)
	t10.rotation = 0.02
	_dyn.add_child(t10)
	if not free_ready and _bid == "standard":
		var info: Variant = t1.get_meta("info_label") if t1.has_meta("info_label") else null
		if info is Label:
			_free_timer_label = info
			_update_free_timer()
	# First session: the free x1 first, then the 10-pull the starting scrolls pay for.
	Guide.mark(t1, guide and free_ready, 0)
	Guide.mark(t10, guide and not free_ready and str(p10.currency) == "scrolls", 0)
	var limited := int(_banner.get("limit_left", -1)) == 0
	var no_wish := _kind() == "wish" and str(_banner.get("target", "")) == ""
	if (not bool(p1.ok) or not bool(p10.ok)) and not limited and not no_wish:
		var gold := str(_banner.get("currency", "")) == "gold"
		var need := ""
		if not bool(p1.ok):
			need = _need_text(1)
		else:
			need = "x10 " + _need_text(10).replace("NEED", "NEEDS")
		var tag := PK.sticker([[need, 13, "mono_bold"], ["EARN GOLD IN THE SANCTUM  >>>" if gold else "GET MORE IN THE SHOP  >>>", 11, "mono"]],
			{"fill": "signal", "rotation": -0.03})
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		_reason.size = Vector2(maxf(tag.size.x, 300.0), Kit.BUTTON_H)
		(_reason.get_meta("text_label") as Label).text = ""
		for c in _reason.get_children():
			if c is PanelContainer:
				c.queue_free()
		_reason.add_child(tag)
		tag.position = Vector2(0, (Kit.BUTTON_H - tag.size.y) * 0.5)
		_reason.position = Vector2(pr.position.x + 60, y - 84)
		_reason.visible = true
	else:
		_reason.visible = false
	_dyn.add_child(_reason)
	SignalKit.relight(_dyn)


## "NEED 300 GEMS OR 1 SCROLL" for a pull of `count` on this banner.
func _need_text(count: int) -> String:
	var cur := str(_banner.get("currency", "gems"))
	var amount := int(_banner.cost_one if count == 1 else _banner.cost_ten)
	var sc := int(_banner.scroll_cost_one if count == 1 else _banner.scroll_cost_ten)
	var t := "NEED %s %s" % [Kit.format_full(amount), cur.to_upper()]
	if sc > 0:
		t += " OR %d SCROLL%s" % [sc, "" if sc == 1 else "S"]
	return t


func _cost_text(p: Dictionary) -> String:
	match str(p.currency):
		"free":
			return "FREE TODAY"
		"scrolls":
			return "%d SCROLL%s" % [int(p.amount), "" if int(p.amount) == 1 else "S"]
		"gold":
			return "%s GOLD" % Kit.format_full(int(p.amount))
	return "%s GEMS" % Kit.format_full(int(p.amount))


## Price of a summon on the current banner: scrolls when it takes them and the player has
## enough, else gems (gold on the envoy banner). ok = affordable.
func _price(count: int) -> Dictionary:
	var sc := int(_banner.get("scroll_cost_one" if count == 1 else "scroll_cost_ten", 0))
	var cur := str(_banner.get("currency", "gems"))
	var amount := int(_banner.get("cost_one" if count == 1 else "cost_ten", 0))
	if sc > 0 and Game.currency("scrolls") >= sc:
		return {"currency": "scrolls", "amount": sc, "ok": true}
	return {"currency": cur, "amount": amount, "ok": Game.currency(cur) >= amount}


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


# ------------------------------------------------------------------ tickets

## Ticket colourways by banner and size: [body paper, body ink, stub paper, stub ink].
func _ticket_look(count: int) -> Array:
	match _kind():
		"featured":
			return [SIG, INK, INK, PAPER] if count == 10 else [BONE, INK, SIG, INK]
		"faction":
			var fp := _faction_print(str(_banner.get("faction", "")))
			return [fp[2], INK, fp[1], PAPER] if count == 10 else [fp[0], INK, fp[2], INK]
		"wish":
			return [PK.BAND, PAPER, SIG, INK] if count == 10 else [Color("efe9da"), INK, PK.BAND, PAPER]
		"envoy":
			return [NEWSPRINT, INK, Color("c7c3b6"), INK] if count == 10 else [NEWSPRINT, INK, NEWSPRINT, INK]
	return [BONE, INK, SIG, Color.WHITE] if count == 10 else [BONE, INK, BONE, SIG]


## What a pull ticket of `count` says on the current banner. again: the results' Again ticket.
func _ticket_spec(count: int, free: bool, again: bool = false) -> Dictionary:
	var p := _price(count)
	var kind := _kind()
	var short := str(_banner.get("short", "")).to_upper()
	var spec := {"count": count, "look": _ticket_look(count), "price": _cost_text(p), "disabled": not bool(p.ok),
		"kicker": "%s ×%d  ·  %s" % ["AGAIN" if again else "SUMMON", count, short],
		"serial": int(Game.state.get("summon", {}).get("total_pulls", 0)) * 13 + count * 7 + (_ids().find(_bid) + 1) * 100000}
	var guarantee := str(Kit.RARITY_NAMES.get(str(_banner.get("ten_pull_guarantee", "epic")), "Epic")).to_upper()
	match kind:
		"featured":
			spec.info = "RATE UP: %s" % str(Game.hero_def(_feature).get("name", "")).to_upper() if count == 1 else "%s OR BETTER · RATE UP INSIDE" % guarantee
		"faction":
			spec.info = "%s HEROES ONLY" % str(_banner.get("faction", "")).to_upper() if count == 1 else "%s OR BETTER INSIDE" % guarantee
		"wish":
			var tgt := str(_banner.get("target", ""))
			spec.info = ("EVERY LEGENDARY: %s" % str(Game.hero_def(tgt).get("name", "")).to_upper()) if tgt != "" else "CHOOSE YOUR WISH FIRST"
			if tgt == "":
				spec.disabled = false
				spec.stamp = "NO WISH"
		"envoy":
			spec.info = "RARE & EPIC · %d LEFT TODAY" % maxi(0, int(_banner.get("limit_left", 0)))
		_:
			spec.info = "SCROLLS FIRST, THEN GEMS" if count == 1 else "%s OR BETTER INSIDE" % guarantee
	var left := int(_banner.get("limit_left", -1))
	if left >= 0 and left < count:
		spec.disabled = true
		spec.stamp = "SOLD OUT" if left == 0 else "ONLY %d LEFT" % left
		spec.info = "BACK IN %s" % Kit.format_time(int(_banner.get("ms_until_limit_reset", 0))).to_upper() if left == 0 \
			else "%d LEFT %s · PULL ONE AT A TIME" % [left, "TODAY" if str(_banner.get("limit_period", "")) == "day" else "THIS WEEK"]
	if free:
		spec.price = "FREE"
		spec.info = "THE DAILY PULL · NO COST"
		spec.kicker = "SUMMON ×1  ·  DAILY"
		spec.free = true
		spec.disabled = false
	return spec


## A summon pull as a printed ticket: a perforated stub with a serial number and a barcode,
## "ADMIT ONE" / "ADMIT TEN", the price, a tear line with round notches and a torn far edge.
## Pressing sinks the ticket and starts tearing the stub off along the perforation; a disabled one
## shakes "no". spec: count (1 | 10), kicker, price, info, look ([body paper, body ink, stub paper,
## stub ink]), width, disabled, stamp (a rubber stamp across the face: "SOLD OUT"), serial, free
## (the daily pull: a blinking light). Every pull on every banner (and Again on the results) is
## built here. The labels belong to the Button, so tests and guide marks find them; the bottom
## line's Label is meta "info_label".
func _ticket(spec: Dictionary, on_pressed: Callable) -> Button:
	var count := int(spec.get("count", 1))
	var w: float = float(spec.get("width", 392.0 if count == 10 else 286.0))
	var h := TICKET_H
	var sw := 94.0 if count == 10 else 80.0
	var look: Array = spec.get("look", _ticket_look(count))
	var off := bool(spec.get("disabled", false))
	var ink: Color = look[1]
	var stub_ink: Color = look[3]
	var b := PK.bare_button(Vector2(w, h + 8))
	var shadow := _TicketPart.new()
	shadow.part = "shadow"
	shadow.stub_w = sw
	shadow.size = Vector2(w, h)
	shadow.position = Vector2(0, 5)
	b.add_child(shadow)
	var body := _TicketPart.new()
	body.part = "body"
	body.fill = look[0]
	body.ink = ink
	body.size = Vector2(w - sw, h)
	b.add_child(body)
	var stub := _TicketPart.new()
	stub.part = "stub"
	stub.fill = look[2]
	stub.ink = stub_ink
	stub.size = Vector2(sw, h)
	stub.position = Vector2(w - sw, 0)
	stub.pivot_offset = Vector2(0, h)
	b.add_child(stub)
	var bw := w - sw
	# The face: kicker, ADMIT ONE / TEN, a rule, the price, the info line.
	var kick := PK.t(str(spec.get("kicker", "")), 10, Color(ink, 0.8), "mono_bold")
	kick.position = Vector2(20, 10)
	kick.size = Vector2(bw - 36, 14)
	kick.clip_text = true
	body.add_child(kick)
	# ADMIT in small print over ONE / TEN set big (huge against tiny), the banner's seal beside it.
	PK.at(body, PK.t("ADMIT", 10, ink, "mono_bold"), Vector2(21, 26))
	var big := PK.t("TEN" if count == 10 else "ONE", 66, ink, "compressed")
	Kit.fit_label(big, bw - 96, 66, 36)
	# Caps from y 41 down to just over the rule.
	var cp := PK.caps(Kit.font("compressed"), big.get_theme_font_size("font_size"))
	big.position = Vector2(17, 41.0 - cp.x)
	body.add_child(big)
	var seal := _Seal.new()
	seal.ink = ink
	seal.text = "Nº%s" % _no()
	seal.position = Vector2(bw - 66, 44)
	seal.size = Vector2(42, 42)
	body.add_child(seal)
	PK.rule(body, Rect2(20, 99, bw - 40, 1), Color(ink, 0.55))
	var price := PK.t(str(spec.get("price", "")), 17, ink, "wide_black")
	Kit.fit_label(price, bw - 40, 17, 11)
	price.position = Vector2(20, 102)
	body.add_child(price)
	var info := PK.t(str(spec.get("info", "")), 9, Color(ink, 0.78), "mono")
	info.position = Vector2(20, 125)
	info.size = Vector2(bw - 34, 13)
	info.clip_text = true
	body.add_child(info)
	b.set_meta("info_label", info)
	# The stub: ADMIT, the count, the serial up the torn edge, a barcode.
	PK.at(stub, PK.t("FREE" if bool(spec.get("free", false)) else "ADMIT", 9, Color(stub_ink, 0.85), "mono_bold"), Vector2(14, 13))
	var n := PK.t("×%d" % count, 50 if count == 10 else 54, stub_ink, "compressed")
	PK.at(stub, n, Vector2(12, 24))
	PK.vt(stub, "Nº %07d" % (int(spec.get("serial", 1)) % 10000000), 9, Color(stub_ink, 0.8), Vector2(sw - 9, 12), "mono_bold")
	var bc := SignalKit.barcode(Vector2(sw - 36, 22), stub_ink, int(spec.get("serial", 289)) % 9973 + 11)
	bc.position = Vector2(14, h - 36)
	stub.add_child(bc)
	if bool(spec.get("free", false)):
		PK.led(body, Vector2(bw - 30, 13), "blink")
	if off:
		body.modulate = Color(1, 1, 1, 0.6)
		stub.modulate = Color(1, 1, 1, 0.6)
	if spec.has("stamp"):
		var st := _Stamp.new()
		st.text = str(spec.stamp)
		st.size = Vector2(minf(bw - 40, 190.0), 52)
		st.position = Vector2((bw - st.size.x) * 0.5, 36)
		st.pivot_offset = st.size * 0.5
		st.rotation = -0.16
		b.add_child(st)
	b.disabled = off
	PK.wire(b, [], on_pressed)
	var stub_x := w - sw
	b.button_down.connect(func() -> void: _tear(body, stub, shadow, stub_x, true))
	b.button_up.connect(func() -> void: _tear(body, stub, shadow, stub_x, false))
	return b


## The press: the ticket sinks and the stub starts to tear along the perforation (down), or
## springs back (up).
static func _tear(body: Control, stub: Control, shadow: Control, stub_x: float, down: bool) -> void:
	if not is_instance_valid(body) or not is_instance_valid(stub):
		return
	var tw := body.create_tween().set_parallel(true)
	if down:
		tw.tween_property(body, "position:y", 3.0, 0.05)
		tw.tween_property(stub, "position", Vector2(stub_x + 6.0, 4.0), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(stub, "rotation", 0.1, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(shadow, "modulate:a", 0.45, 0.05)
	else:
		tw.tween_property(body, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(stub, "position", Vector2(stub_x, 0.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(stub, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(shadow, "modulate:a", 1.0, 0.18)


# ------------------------------------------------------------------ rates

func _open_rates() -> void:
	var v := Kit.vbox(14)
	v.custom_minimum_size.x = 540
	var rates: Dictionary = _banner.get("rates", {})
	var pool: Dictionary = _banner.get("pool_by_rarity", {})
	var kind := _kind()
	var feat := str(_banner.get("featured", ""))
	var target := str(_banner.get("target", ""))
	v.add_child(Kit.label(str(_banner.get("name", "")).to_upper(), 16, Kit.TEXT, "mono_bold"))
	v.add_child(Kit.body("Every pull rolls a rarity first, then one hero of that rarity with equal chance.", 21, Kit.TEXT_DIM))
	for r: String in ["legendary", "epic", "rare"]:
		if int(rates.get(r, 0)) <= 0:
			continue
		var rows: Array = [[str(Kit.RARITY_NAMES[r]).to_upper(), _pct(float(int(rates.get(r, 0)))), true]]
		var ids: Array = pool.get(r, [])
		if r == "legendary" and kind == "featured" and feat != "":
			var share := int(_banner.get("featured_bp", 5000))
			var others: Array = ids.filter(func(x: Variant) -> bool: return str(x) != feat)
			rows.append([str(Game.hero_def(feat).get("name", feat)) + " (rate up)", _pct(float(int(rates.legendary)) * share / 10000.0)])
			for id: Variant in others:
				rows.append([str(Game.hero_def(str(id)).get("name", id)), _pct(float(int(rates.legendary)) * (10000 - share) / 10000.0 / maxf(1.0, others.size()))])
		elif r == "legendary" and kind == "wish":
			rows.append([str(Game.hero_def(target).get("name", target)) + " (your wish)" if target != "" else "Your wish (choose one)", _pct(float(int(rates.legendary)))])
		elif not ids.is_empty():
			var each := float(int(rates.get(r, 0))) / float(ids.size())
			for id: Variant in ids:
				rows.append([str(Game.hero_def(str(id)).get("name", id)), _pct(each)])
		v.add_child(PK.data_table(rows, 540.0, {"size": 16, "row_h": 30.0, "bar": Color(0, 0, 0, 0.06)}))
	var pity_max := int(_banner.get("pity_legendary", 0))
	var guarantee := str(_banner.get("ten_pull_guarantee", "epic"))
	var dupes := ""
	var dust := ""
	for r: String in ["rare", "epic", "legendary"]:
		dupes += ("%s %d" % [str(Kit.RARITY_NAMES[r]), Progression.dupe_shards(r)]) + (", " if r != "legendary" else "")
		dust += ("%d" % Progression.dust_per_excess_shard(r)) + (" / " if r != "legendary" else "")
	var rules: Array[Array] = []
	match kind:
		"featured":
			rules.append(["Rate up", "When you get a Legendary here, it is %s %s of the time. If it isn't her, your next Legendary on this banner is her for sure. The featured hero changes every %d days; your pity and the guarantee carry over." % [
				str(Game.hero_def(feat).get("name", feat)), _pct(float(int(_banner.get("featured_bp", 5000)))), int(_banner.get("rotation_days", 7))]])
		"faction":
			rules.append(["Faction focus", "Only %s heroes answer today. The faction changes every day at midnight (%s next). The pity carries over between factions." % [
				str(Kit.FACTION_NAMES.get(str(_banner.get("faction", "")), "")), _next_faction_name()]])
		"wish":
			rules.append(["Your wish", "Every Legendary from The Wish is the hero you choose. Change your wish at any time; the pity carries over. Up to %d wishes a week (resets in %s)." % [
				int(_banner.get("limit_max", 30)), Kit.format_time(int(_banner.get("ms_until_limit_reset", 0)))]])
		"envoy":
			rules.append(["Envoy's draw", "Rare and Epic heroes only, paid in gold. Up to %d draws a day (fresh in %s). Good for shards of the heroes you already have." % [
				int(_banner.get("limit_max", 10)), Kit.format_time(int(_banner.get("ms_until_limit_reset", 0)))]])
	if pity_max > 0:
		rules.append(["Pity", "If none of your last %d pulls on this banner was Legendary, the next pull is a guaranteed Legendary. Your counter: %d / %d. Every banner keeps its own counter; it carries over between summons and resets when you get any Legendary there." % [
			pity_max - 1, int(_banner.get("pity", 0)), pity_max]])
	rules.append(["10-pull bonus", "Every 10-pull includes at least one %s or better hero." % str(Kit.RARITY_NAMES.get(guarantee, guarantee.capitalize()))])
	rules.append(["Duplicates", "A hero you already own turns into shards of that hero: %s shards. Shards raise stars, up to %d. Shards a fully starred hero can't use become dust (Rare / Epic / Legendary: %s per shard)." % [dupes, Kit.MAX_STARS, dust]])
	var cost_line := ""
	var cur := str(_banner.get("currency", "gems"))
	if int(_banner.get("scroll_cost_one", 0)) > 0:
		cost_line = "1 pull: %d scroll%s or %s %s. 10 pulls: %d scrolls or %s %s. Scrolls are always used first." % [int(_banner.scroll_cost_one), "" if int(_banner.scroll_cost_one) == 1 else "s",
			Kit.format_full(int(_banner.cost_one)), cur, int(_banner.scroll_cost_ten), Kit.format_full(int(_banner.cost_ten)), cur]
	else:
		cost_line = "1 pull: %s %s. 10 pulls: %s %s." % [Kit.format_full(int(_banner.cost_one)), cur, Kit.format_full(int(_banner.cost_ten)), cur]
	if bool(_banner.get("free_daily", false)):
		cost_line += " The free daily summon uses the same rates."
	rules.append(["Costs", cost_line])
	for rule in rules:
		var rv := Kit.vbox(4)
		rv.add_child(Kit.label(str(rule[0]).to_upper(), 16, Kit.TEXT, "mono_bold"))
		rv.add_child(Kit.body(str(rule[1]), 21, Kit.TEXT))
		v.add_child(rv)
	var sc := Kit.scroll(Kit.margin(v, 4, 4))
	var vh: float = get_viewport_rect().size.y
	sc.custom_minimum_size = Vector2(560, minf(vh * 0.62, 1000.0))
	UI.popup("Summon Rates", sc, Callable(), 640.0, true)


func _next_faction_name() -> String:
	var f := SummonRules.faction_for(EconomyData.banner_def(_bid), Game.today() + 1, EconomyData.BANNER_EPOCH_DAY)
	return str(Kit.FACTION_NAMES.get(f, f))


## Basis points (may be fractional) as a percentage with up to 3 decimals: 200 -> "2%",
## 66.67 -> "0.667%".
static func _pct(bp: float) -> String:
	var s := "%.3f" % (bp / 100.0)
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s + "%"


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


# ------------------------------------------------------------------ summoning

func _try_summon(count: int) -> void:
	if _phase != "":
		return
	if _kind() == "wish" and str(_banner.get("target", "")) == "":
		_open_wish_picker()
		return
	var left := int(_banner.get("limit_left", -1))
	if left >= 0 and left < count:
		UI.toast("No pulls left %s" % ("today" if str(_banner.get("limit_period", "")) == "day" else "this week") if left == 0
			else "Only %d left %s" % [left, "today" if str(_banner.get("limit_period", "")) == "day" else "this week"], "bad")
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gold" if str(p.currency) == "gold" else "Not enough gems or scrolls", "bad")
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
	var r := Game.summon(count, free, _bid)
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
	_banner = Game.banner(_bid)
	var replacing := _seq != null and is_instance_valid(_seq)
	if replacing:
		_seq.queue_free()
	_seq = Sequence.new()
	_seq.name = "SummonSequence"
	add_child(_seq)
	var pity_max := int(_banner.get("pity_legendary", 0))
	_seq.setup(_results, _price, maxi(1, pity_max - int(_banner.get("pity", 0))))
	if pity_max <= 0:
		var lim := int(_banner.get("limit_max", 0))
		_seq.pity_row = ["DRAWS LEFT TODAY", "%d / %d" % [maxi(0, int(_banner.get("limit_left", 0))), lim]] if lim > 0 else ["LEGENDARY", "NOT ON THIS BANNER"]
	elif _kind() == "featured":
		var left := maxi(1, pity_max - int(_banner.get("pity", 0)))
		_seq.pity_row = ["%s GUARANTEED WITHIN" % ("FEATURED" if bool(_banner.get("lost", false)) else "LEGENDARY"), "%d PULL%s" % [left, "" if left == 1 else "S"]]
	elif _kind() == "wish":
		var left2 := maxi(1, pity_max - int(_banner.get("pity", 0)))
		_seq.pity_row = ["WISH GRANTED WITHIN", "%d PULL%s · %d LEFT THIS WEEK" % [left2, "" if left2 == 1 else "S", maxi(0, int(_banner.get("limit_left", 0)))]]
	_seq.make_ticket = func(n: int, cb: Callable) -> Button: return _ticket(_ticket_spec(n, false, true), cb)
	_seq.featured_note = "RATE UP" if _kind() == "featured" else ""
	_seq.done.connect(_finish)
	_seq.again.connect(_again)
	_seq.results_shown.connect(func() -> void: UI.set_chrome(true, true))
	_main.visible = false
	_seq.start(not replacing)


## Overlay taps (the e2e scripts call this with simulated releases too).
func _on_overlay_input(ev: InputEvent) -> void:
	if _seq != null and is_instance_valid(_seq):
		_seq.handle_input(ev)


func _again(count: int) -> void:
	if _phase != "results":
		return
	_banner = Game.banner(_bid)
	var left := int(_banner.get("limit_left", -1))
	if left >= 0 and left < count:
		UI.toast("No pulls left %s" % ("today" if str(_banner.get("limit_period", "")) == "day" else "this week"), "bad")
		return
	var p := _price(count)
	if not bool(p.ok):
		UI.toast("Not enough gold" if str(p.currency) == "gold" else "Not enough gems or scrolls", "bad")
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


# ------------------------------------------------------------------ drawn pieces

## One part of a pull ticket: "body" (the face, with a notch at the tear line top and bottom and a
## printed hairline frame), "stub" (notches, the perforation, a torn far edge) or "shadow".
class _TicketPart:
	extends Control
	const R := 11.0
	var part := "body"
	var fill := Color("f4f3ef")
	var ink := Color("101113")
	var stub_w := 90.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match part:
			"shadow":
				var bw := w - stub_w
				for k in 2:
					var c := Color(0, 0, 0, 0.13 if k == 0 else 0.09)
					var o := Vector2(0, 2.0 + k * 3.0)
					draw_colored_polygon(_body_pts(bw, h, o), c)
					draw_colored_polygon(_stub_pts(stub_w, h, o + Vector2(bw, 0)), c)
			"body":
				draw_colored_polygon(_body_pts(w, h, Vector2.ZERO), fill)
				var fr := Rect2(8, 8, w - 8 - R - 6, h - 16)
				draw_rect(fr, Color(ink, 0.28), false, 1.0)
				# Corner ticks on the printed frame.
				for cx: float in [fr.position.x, fr.end.x]:
					for cy: float in [fr.position.y, fr.end.y]:
						draw_line(Vector2(cx - 4, cy), Vector2(cx + 4, cy), Color(ink, 0.5), 1.0)
						draw_line(Vector2(cx, cy - 4), Vector2(cx, cy + 4), Color(ink, 0.5), 1.0)
			"stub":
				draw_colored_polygon(_stub_pts(w, h, Vector2.ZERO), fill)
				# The perforation: small punched holes down the tear line.
				var y := R + 6.0
				var hole := fill.darkened(0.32)
				while y < h - R - 6.0:
					draw_circle(Vector2(1.5, y), 1.6, hole)
					y += 7.0

	static func _body_pts(w: float, h: float, o: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array([o + Vector2(0, 0)])
		for i in 7:
			var a := PI - (PI * 0.5) * i / 6.0
			pts.append(o + Vector2(w + cos(a) * R, sin(a) * R))
		for i in 7:
			var a := -PI * 0.5 - (PI * 0.5) * i / 6.0
			pts.append(o + Vector2(w + cos(a) * R, h + sin(a) * R))
		pts.append(o + Vector2(0, h))
		return pts

	static func _stub_pts(w: float, h: float, o: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 7:
			var a := PI * 0.5 - (PI * 0.5) * i / 6.0
			pts.append(o + Vector2(cos(a) * R, sin(a) * R))
		# The torn far edge.
		var y := 0.0
		var k := 0
		while y < h:
			pts.append(o + Vector2(w - (3.5 if k % 2 == 1 else 0.0) - (1.5 if k % 3 == 2 else 0.0), y))
			y += 6.0
			k += 1
		pts.append(o + Vector2(w, h))
		for i in 7:
			var a := -(PI * 0.5) * i / 6.0
			pts.append(o + Vector2(cos(a) * R, h + sin(a) * R))
		return pts


## A rubber stamp across a ticket: an outlined box with the word, in signal, a little worn.
class _Stamp:
	extends Control
	var text := "VOID"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color("ff4b1f", 0.92)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), c, false, 3.0)
		draw_rect(Rect2(Vector2(7, 7), size - Vector2(14, 14)), Color(c, 0.6), false, 1.0)
		var f := Kit.font("wide_black")
		var fs := 22
		while fs > 10 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 24:
			fs -= 1
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


## The banner's seal printed on a ticket: two rings and the portal number.
class _Seal:
	extends Control
	var ink := Color("101113")
	var text := "Nº01"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, size.x * 0.5 - 1.0, 0.0, TAU, 48, Color(ink, 0.8), 1.4, true)
		draw_arc(c, size.x * 0.5 - 5.0, 0.0, TAU, 48, Color(ink, 0.45), 1.0, true)
		var f := Kit.font("mono_bold")
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2(c.x - tw * 0.5, c.y + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
		for k in 8:
			var a := TAU * k / 8.0
			draw_line(c + Vector2(cos(a), sin(a)) * (size.x * 0.5 - 5.0), c + Vector2(cos(a), sin(a)) * (size.x * 0.5 - 8.0), Color(ink, 0.5), 1.0)


## A hairline ring (the faction emblem's frame).
class _Ring:
	extends Control
	var color := Color("101113")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_arc(size * 0.5, size.x * 0.5 - 1.0, 0.0, TAU, 64, color, 1.2, true)
		draw_arc(size * 0.5, size.x * 0.5 - 5.0, 0.0, TAU, 64, Color(color, 0.4), 1.0, true)


## A grease-pencil loop around a print (the wished hero).
class _Loop:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for k in 66:
			var a := TAU * k / 60.0 - 0.6
			var wob := 1.0 + 0.03 * sin(a * 3.0 + 1.0) + 0.02 * sin(a * 7.0)
			pts.append(c + Vector2(cos(a) * size.x * 0.52, sin(a) * size.y * 0.51) * wob)
		draw_polyline(pts, Color("ff4b1f"), 3.0, true)


## The wish punch card: `count` cells in rows of ten, the first `used` punched out (a hole and a
## ring), the rest printed boxes.
class _Punch:
	extends Control
	var count := 30
	var used := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := Color("101113")
		var s := 15.0
		var gap := 6.0
		draw_rect(Rect2(Vector2(-6, -6), Vector2(10 * (s + gap) - gap + 12, ceilf(count / 10.0) * (s + gap) - gap + 12)), Color("f4f3ef"))
		for i in count:
			var r := Rect2((i % 10) * (s + gap), (i / 10) * (s + gap), s, s)
			if i < used:
				draw_circle(r.get_center(), s * 0.36, ink)
				draw_arc(r.get_center(), s * 0.5, 0.0, TAU, 20, Color(ink, 0.5), 1.0, true)
			else:
				draw_rect(r, Color(ink, 0.7), false, 1.0)


## The envoy's coupon row: `count` boxes, the first `used` crossed out in ink.
class _Coupons:
	extends Control
	var count := 10
	var used := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := Color("101113")
		var s := 26.0
		var f := Kit.font("mono_bold")
		for i in count:
			var r := Rect2(i * 34.0, 0, s, s)
			draw_rect(r, Color(ink, 0.8), false, 1.5)
			draw_string(f, r.position + Vector2(6, 17), "%02d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
			if i < used:
				draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), ink, 2.5)
				draw_line(Vector2(r.end.x - 3, r.position.y + 3), Vector2(r.position.x + 3, r.end.y - 3), ink, 2.5)
