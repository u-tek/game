extends Control
## One hero's reveal in the summon sequence, as a poster coming off the press (the approved Lobby
## poster's look, docs/dev/ui-style-v4.md). The poster: a dark band down the left with her face as a
## red halftone print, her rarity set vertically on it, the sheet number and her signature; her
## name set huge in compressed type and turned on its side, two-tone where it crosses the band; the
## hero herself; a hairline strip down the right edge with her faction, role and stars as vertical
## micro type; a stamp on a silver disc for NEW or the duplicate's shards.
##
## She arrives as a halftone print of herself (red ink on the paper, a black plate printed slightly
## out of register) that resolves into the full-colour animated hero as the plates come into
## register, all timed from one clock so a tap can fast-forward it. Rarity sets the drama:
##   Rare       snappy (0.7 s): the print lands, resolves at once, the name slides in.
##   Epic       a held beat (0.75 s): the band floods signal, the print shakes out of register;
##              then the burst (an ink burst, a paper-white flash) and the name slams in.
##   Legendary  a long held beat (1.6 s): the room dims, the whole poster floods signal from the
##              bottom while the black print pulses like a heartbeat and shakes harder; then the
##              big burst (flash, double ink burst, grain), she resolves out of an overexposed
##              glow, "LEGENDARY" and her name slam down.
##
## The sequence (summon_sequence.gd) owns it: start() begins the clock, tap() fast-forwards
## (held beat -> burst -> settled) and returns true once settled (= next hero), leave() slides it
## out and frees it. Screen-wide effects go out through the fx signal: ("flash", color, alpha),
## ("shake", _, trauma), ("tint", color, amount), ("darken", _, k), ("grain", _, amount).

signal fx(kind: String, color: Color, amount: float)
## Emitted once when every element has landed (the "tap to continue" hint can show).
signal landed

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const Burst := preload("res://src/ui/summon/summon_burst.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")

## Burst time (end of the held beat) per rarity.
const BEAT := {"rare": 0.0, "epic": 0.75, "legendary": 1.6}
## Element start times after the burst: rarity word, name, title, badges, stamp; then settle.
const SCHEDULE := {
	"rare": [0.06, 0.1, 0.16, 0.2, 0.28, 0.66],
	"epic": [0.12, 0.26, 0.4, 0.46, 0.58, 1.0],
	"legendary": [0.32, 0.58, 0.78, 0.86, 1.0, 1.6],
}
## How long the print takes to come into register and turn into her, per rarity.
const RESOLVE := {"rare": 0.34, "epic": 0.42, "legendary": 0.7}
const PULSES := [0.15, 0.6, 1.02, 1.36]
const BAND_W := 200.0
const INK := PK.INK
const PAPER := PK.PAPER
const SIG := PK.SIGNAL

var hero_id := ""
var rarity := "rare"
var result: Dictionary = {}
var safe_top := 0.0
var safe_bottom := 0.0
var settled := false
## Screenshots: the clock stops at this time (< 0 = never).
var hold := -1.0
## Sheet number in the run (Nº 07 / 10).
var sheet := 1
var sheets := 1

var _def: Dictionary = {}
var _t := 0.0
var _running := false
var _burst_t := 0.0
var _settle_t := 0.7
var _sched: Array = []
var _events: Array[Array] = []
var _next_event := 0

var _p: Control
var _pr := Rect2()
var _flood: ColorRect
var _band: ColorRect
var _band_print: TextureRect
var _giant: Array[RichTextLabel] = []
var _anchor: Node2D
var _print: TextureRect
var _print2: TextureRect
var _rar: Control
var _title: Control
var _badges: Control
var _tag: Control
var _chest := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


## res: one entry of Game.summon's results ({hero_id, rarity, is_new, shards, dust}).
## stars: the hero's star count to show. skin: the skin id for the art ("" = base look).
## n / total: this sheet's number in the run.
func setup(res: Dictionary, stars: int, skin: String, top_inset: float, bottom_inset: float, n: int = 1, total: int = 1) -> void:
	result = res
	hero_id = str(res.get("hero_id", ""))
	_def = Game.hero_def(hero_id)
	rarity = str(res.get("rarity", _def.get("rarity", "rare")))
	if not BEAT.has(rarity):
		rarity = "rare"
	safe_top = top_inset
	safe_bottom = bottom_inset
	sheet = n
	sheets = total
	_burst_t = float(BEAT[rarity])
	_sched = SCHEDULE[rarity]
	_settle_t = _burst_t + float(_sched[5])
	name = "Reveal_" + hero_id
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rng.seed = hash(hero_id) + n
	_build(stars, skin)
	_build_events()
	_apply()


# ------------------------------------------------------------------ build

func _build(stars: int, skin: String) -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := vp.x
	var h := vp.y
	var faction := str(_def.get("faction", "celestial"))
	_pr = Rect2(18, safe_top + 84, w - 36, maxf(600.0, h - safe_bottom - 100 - (safe_top + 84)))
	_p = PK.poster(self, _pr)
	var pw := _pr.size.x
	var ph := _pr.size.y
	var legend := rarity == "legendary"

	# The flood (signal ink rising over the paper: a Legendary's held beat).
	_flood = ColorRect.new()
	_flood.color = SIG
	_flood.mouse_filter = MOUSE_FILTER_IGNORE
	_flood.position = Vector2(BAND_W, ph)
	_flood.size = Vector2(pw - BAND_W, 0)
	_p.add_child(_flood)
	# The band with her face as a halftone print.
	_band = PK.band(_p, Rect2(0, 0, BAND_W, ph), hero_id, skin, {"from": 0.24, "cell": 7.0})
	_band_print = _band.get_meta("print") if _band.has_meta("print") else null
	PK.at(_band, PK.t("HH", 26, PAPER, "wide_black"), Vector2(14, 14))
	PK.at(_band, PK.t("Nº %02d / %02d\nRUN 0047" % [sheet, sheets], 11, Color(PAPER, 0.85), "mono_bold"), Vector2(14, 52))

	# Her name, huge, turned on its side, two-tone across the band.
	var nm := str(_def.get("name", hero_id)).to_upper()
	var f := Kit.font("compressed")
	var fs := 270
	while fs > 120 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > ph * 0.86:
		fs -= 6
	var name_col := INK
	_giant = PK.giant(_p, nm, fs, [[0.0, BAND_W, PAPER], [BAND_W, pw - BAND_W, name_col]], Vector2(BAND_W + fs * 0.6, ph * 0.03), Vector2(ph, fs * 1.3))

	# The hero: her print (red, with a black plate out of register) and the live figure over it.
	var box := Control.new()
	box.clip_contents = true
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.size = Vector2(pw - 49, ph)
	_p.add_child(box)
	var feet := Vector2(0.0, ph - 4.0)
	var fig_h := ph * 0.92
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	_anchor.position = feet
	var sprite := HeroArt.make_sprite(hero_id, skin)
	_anchor.add_child(sprite)
	var base_h: float = sprite.call("get_height")
	# Wide poses shrink to fit between the band and the right rule; the figure is centred there.
	var avail := pw - 49 - BAND_W * 0.4
	var fw := PK.figure_width(sprite, fig_h)
	if fw > avail * 1.3:
		fig_h *= avail * 1.3 / fw
	var k := fig_h / maxf(base_h, 1.0)
	sprite.scale = Vector2(k, k)
	feet.x = BAND_W + (pw - 49 - BAND_W) * 0.5 + 4.0 - PK.center_shift(sprite, fig_h)
	_anchor.position = feet
	var sr := PK.still_rect(sprite, feet, fig_h)
	var tex := HeroArt.texture(hero_id, skin)
	_print2 = _hero_print(tex, sr, INK if not legend else Color("2a0b04"), 6.0, 0.2)
	box.add_child(_print2)
	_print = _hero_print(tex, sr, SIG if not legend else INK, 6.0, 0.5236)
	box.add_child(_print)
	box.add_child(_anchor)
	_chest = _pr.position + Vector2(feet.x, feet.y - fig_h * 0.62)

	# The right strip: a hairline and her particulars as vertical micro type.
	PK.rule(_p, Rect2(pw - 48, 0, 1, ph), Color(INK, 0.55))
	var strip := Control.new()
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	_p.add_child(strip)
	PK.vt(strip, "©2026 ·", 12, INK, Vector2(pw - 38, 14))
	var labels := [str(Kit.FACTION_NAMES.get(faction, faction)).to_upper(), str(Kit.ROLE_NAMES.get(str(_def.get("role", "")), "")).to_upper(),
		"★".repeat(maxi(1, stars)), "NEW" if bool(result.get("is_new", false)) else "DUPLICATE"]
	for i in labels.size():
		var yy := ph * (0.2 + 0.15 * i)
		PK.vt(strip, str(labels[i]), 15, SIG if i == 3 and bool(result.get("is_new", false)) else INK, Vector2(pw - 16, yy))
		PK.rule(strip, Rect2(pw - 52, yy + 2, 9, 1), INK)
	PK.led(strip, Vector2(pw - 31, ph * 0.2 - 24), "breathe")
	_badges = strip

	# On the band: her rarity, set vertically (it slams in), her title, her signature.
	var rw := str(Kit.RARITY_NAMES.get(rarity, rarity)).to_upper()
	var rar := PK.t(rw, 46, PAPER if rarity == "rare" else SIG, "wide_black")
	var rbox := Control.new()
	rbox.mouse_filter = MOUSE_FILTER_IGNORE
	rbox.position = Vector2(16, ph * 0.2)
	rbox.size = Vector2(60, rar.get_minimum_size().x)
	rar.rotation = PI * 0.5
	rar.position = Vector2(58, 0)
	rbox.add_child(rar)
	rbox.pivot_offset = rbox.size * 0.5
	_band.add_child(rbox)
	_rar = rbox
	var tl := PK.t(str(_def.get("title", "")).to_upper(), 11, Color(PAPER, 0.85), "mono_bold")
	tl.rotation = PI * 0.5
	tl.position = Vector2(80, ph * 0.2)
	_band.add_child(tl)
	_title = tl
	var sig := PK.t(str(_def.get("name", hero_id)), 46, PAPER, "serif_italic")
	Kit.fit_label(sig, BAND_W - 34, 46, 24)
	sig.position = Vector2(12, ph - 74)
	sig.size = Vector2(BAND_W - 16, 54)
	_band.add_child(sig)
	PK.rule(_band, Rect2(14, ph - 20, BAND_W - 40, 2), PAPER).rotation = -0.05

	# NEW, or the duplicate's shards: a stamp on a silver disc stuck over the band's edge.
	var is_new := bool(result.get("is_new", false))
	var label := "NEW HERO · NEW HERO · "
	var value := "NEW"
	if not is_new:
		var shards := int(result.get("shards", 0))
		var dust := int(result.get("dust", 0))
		label = "DUPLICATE · SHARDS · "
		value = "+%d" % shards
		if dust > 0 and dust == shards:
			label = "DUPLICATE · DUST · "
			value = "+%d" % dust
	_tag = PK.stamp_disc(_p, Vector2(BAND_W - 64, ph - 300), 124, label, value, -0.14)
	PK.grain(_p, 0.07)


## A halftone print of the hero's still, lined up with the live figure.
func _hero_print(tex: Texture2D, r: Rect2, ink: Color, cell: float, angle: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = r.position
	tr.size = r.size
	var m := SignalKit.halftone_material(cell, ink, false)
	m.set_shader_parameter("angle", angle)
	m.set_shader_parameter("gain", 1.35)
	tr.material = m
	tr.set_meta("home", r.position)
	return tr


# ------------------------------------------------------------------ timeline

func _build_events() -> void:
	_events.clear()
	match rarity:
		"rare":
			_events.append([0.0, "pop"])
		"epic":
			_events.append([0.0, "beat_start"])
			_events.append([_burst_t, "burst"])
			_events.append([_burst_t + float(_sched[0]), "slam"])
			_events.append([_burst_t + float(_sched[1]) + 0.2, "name"])
		"legendary":
			_events.append([0.0, "beat_start"])
			for i in PULSES.size():
				_events.append([float(PULSES[i]), "pulse%d" % i])
			_events.append([_burst_t, "burst"])
			_events.append([_burst_t + float(_sched[0]), "slam"])
			_events.append([_burst_t + float(_sched[1]) + 0.24, "name"])
	_events.append([_settle_t, "settle"])
	_next_event = 0


## Starts the clock (the sequence calls it when this hero's turn comes).
func start() -> void:
	_running = true
	_t = 0.0
	fx.emit("tint", INK if rarity == "rare" else SIG, {"rare": 0.15, "epic": 0.4, "legendary": 0.6}[rarity])
	_apply()


## A tap: during the held beat it jumps to the burst; while things are still landing it
## settles everything at once; once settled it returns true (show the next hero).
func tap() -> bool:
	if not _running:
		return false
	if _t < _burst_t - 0.02:
		_jump(_burst_t)
		return false
	if not settled:
		_jump(_settle_t)
		return false
	return true


## Lands everything immediately without the effects (screenshots, Skip).
func finish_now() -> void:
	_running = true
	_jump(_settle_t)


func _jump(to: float) -> void:
	# Events before `to` are skipped silently; one exactly at `to` still fires.
	while _next_event < _events.size() and float(_events[_next_event][0]) < to:
		var id := str(_events[_next_event][1])
		if id == "burst":
			_on_burst(true)
		_next_event += 1
	_t = to
	_fire_events()
	_apply()


func _process(delta: float) -> void:
	if not _running:
		return
	_t = _t + delta if hold < 0.0 else minf(_t + delta, hold)
	_fire_events()
	_apply()


func _fire_events() -> void:
	while _next_event < _events.size() and float(_events[_next_event][0]) <= _t:
		_on_event(str(_events[_next_event][1]))
		_next_event += 1


func _on_event(id: String) -> void:
	match id:
		"pop":
			UI.sfx("reveal")
			UI.haptic(12)
			fx.emit("flash", Color(1, 1, 1), 0.3)
			fx.emit("grain", Color.WHITE, 0.12)
			_spawn_burst(_chest, INK, 0.5)
			fx.emit("shake", Color.WHITE, 0.22)
		"beat_start":
			fx.emit("darken", Color.BLACK, 0.7 if rarity == "legendary" else 0.35)
			if rarity == "legendary":
				UI.sfx("riser")
				UI.haptic(15)
			else:
				UI.sfx("tell")
				UI.haptic(10)
		"pulse0", "pulse1", "pulse2", "pulse3":
			var n := int(id.substr(5))
			UI.sfx("beat")
			UI.haptic(12 + 8 * n)
			fx.emit("shake", Color.WHITE, 0.2 + 0.1 * n)
			fx.emit("flash", SIG, 0.08 + 0.05 * n)
			fx.emit("grain", Color.WHITE, 0.1 + 0.04 * n)
		"burst":
			_on_burst(false)
		"slam":
			UI.sfx("slam")
			UI.haptic(35 if rarity == "legendary" else 22)
			fx.emit("shake", Color.WHITE, 0.45 if rarity == "legendary" else 0.3)
			_spawn_burst(_pr.position + _band.position + _rar.position + _rar.size * 0.5, SIG if rarity != "rare" else INK, 0.5)
		"name":
			UI.sfx("slam")
			UI.haptic(25)
			fx.emit("shake", Color.WHITE, 0.4 if rarity == "legendary" else 0.25)
			fx.emit("grain", Color.WHITE, 0.14)
		"settle":
			settled = true
			landed.emit()


## The burst. quiet = reached by fast-forwarding past it (keep the visuals, drop the sound).
func _on_burst(quiet: bool) -> void:
	fx.emit("darken", Color.BLACK, 0.0)
	if quiet:
		return
	if rarity == "legendary":
		UI.sfx("legendary")
		UI.sfx("burst")
		UI.haptic(90)
		fx.emit("flash", Color(1.0, 0.96, 0.9), 1.0)
		fx.emit("shake", Color.WHITE, 1.0)
		fx.emit("grain", Color.WHITE, 0.3)
		_spawn_burst(_chest, INK, 2.0)
		_spawn_burst(_chest, PAPER, 1.2)
	else:
		UI.sfx("burst")
		UI.sfx("reward")
		UI.haptic(45)
		fx.emit("flash", Color(1, 1, 1), 0.7)
		fx.emit("shake", Color.WHITE, 0.6)
		fx.emit("grain", Color.WHITE, 0.2)
		_spawn_burst(_chest, SIG, 1.2)


func _spawn_burst(at: Vector2, col: Color, strength: float) -> void:
	var b := Burst.new()
	b.color = col
	b.strength = strength
	b.position = at
	add_child(b)


## Slides out to the left and frees itself (the next poster comes in from the right).
func leave() -> void:
	_running = false
	set_process(false)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:x", -size.x * 0.4, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)


# ------------------------------------------------------------------ state from the clock

func _apply() -> void:
	if _p == null:
		return
	var t := _t
	var tb := t - _burst_t
	var after := tb >= 0.0
	var ph := _pr.size.y
	var pw := _pr.size.x
	var res: float = RESOLVE[rarity]
	var kb := Fx.k01(t, 0.0, maxf(_burst_t, 0.001))
	# Heartbeat: each pulse swells the print for a moment.
	var pulse := 0.0
	if rarity == "legendary" and not after:
		for pt: float in PULSES:
			if t >= pt:
				pulse += exp(-(t - pt) * 8.0)
	# The flood: a Legendary's poster fills with signal from the bottom; an Epic's band turns signal.
	if rarity == "legendary":
		var fl := Fx.out_cubic(Fx.k01(t, 0.05, _burst_t * 0.9)) if not after else 1.0
		_flood.size = Vector2(pw - BAND_W, ph * fl)
		_flood.position = Vector2(BAND_W, ph * (1.0 - fl))
	elif rarity == "epic":
		var fe := Fx.k01(t, 0.05, _burst_t * 0.8) if not after else 1.0
		_band.color = PK.BAND.lerp(SIG, fe)
		if _band_print:
			(_band_print.material as ShaderMaterial).set_shader_parameter("ink", PK.RED_INK.lerp(Color(INK, 0.95), fe))
	# The print: in before the burst (dots growing), then out as she resolves.
	var print_a := 1.0
	var lift := 0.0
	if not after:
		print_a = Fx.k01(t, 0.0, 0.18)
		lift = -0.5 + 0.5 * Fx.out_cubic(kb) + 0.25 * pulse
	else:
		print_a = 1.0 - Fx.k01(tb, res * 0.35, res)
		lift = 0.12 * (1.0 - Fx.k01(tb, 0.0, res))
	for pr: TextureRect in [_print, _print2]:
		(pr.material as ShaderMaterial).set_shader_parameter("lift", lift)
	_print.modulate.a = print_a
	_print2.modulate.a = print_a * (0.5 if rarity == "legendary" else 0.6)
	# Out of register: the black plate shakes off before the burst, slides home after it.
	var off := Vector2.ZERO
	if not after:
		var j := (4.0 + 16.0 * kb + 14.0 * pulse) * (1.0 if Kit.motion_ok() else 0.2)
		off = Vector2(1.0, -0.6) * j + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * j * 0.4
	else:
		off = Vector2(14.0, -8.0) * (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, res)))
	_print2.position = (_print2.get_meta("home") as Vector2) + off
	_print.position = (_print.get_meta("home") as Vector2) - off * 0.3
	# Her: resolves out of an overexposed glow and settles with a small push-in.
	var hero_a := Fx.k01(tb, 0.02, res * 0.8) if after else 0.0
	var glow := (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, res + 0.35))) if after else 0.0
	var zoom := 1.0 + 0.04 * (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, res + 0.4))) if after else 1.04
	var hot := Color(2.2, 1.9, 1.7) if rarity == "legendary" else Color(1.5, 1.45, 1.4)
	var m := Color.WHITE.lerp(hot, glow)
	m.a = hero_a
	_anchor.modulate = m
	_anchor.scale = Vector2(zoom, zoom)
	# The name: drops in along its reading axis.
	var s1 := float(_sched[1])
	var pn := Fx.k01(tb, s1, s1 + (0.42 if rarity == "legendary" else 0.32))
	var drop := -ph * (0.32 if rarity != "rare" else 0.12) * (1.0 - Fx.out_back(pn, 1.4 if rarity != "rare" else 0.6))
	PK.giant_pose(_giant, Vector2(0, drop), 1.0, Fx.k01(tb, s1, s1 + 0.08))
	# Rarity word: slams (scale) on the band.
	var s0 := float(_sched[0])
	var p0 := Fx.k01(tb, s0, s0 + 0.36)
	_rar.modulate.a = Fx.k01(tb, s0, s0 + 0.07)
	var sc := lerpf(2.2 if rarity == "legendary" else (1.8 if rarity == "epic" else 1.3), 1.0, Fx.out_back(p0, 1.2))
	_rar.scale = Vector2(sc, sc)
	# Title, badges (the strip) and the stamp.
	var p2 := Fx.out_cubic(Fx.k01(tb, float(_sched[2]), float(_sched[2]) + 0.3))
	_title.modulate.a = p2
	var p3 := Fx.out_cubic(Fx.k01(tb, float(_sched[3]), float(_sched[3]) + 0.3))
	_badges.modulate.a = p3
	_badges.position = Vector2(30.0 * (1.0 - p3), 0)
	var s4 := float(_sched[4])
	var p4 := Fx.k01(tb, s4, s4 + 0.36)
	_tag.modulate.a = Fx.k01(tb, s4, s4 + 0.1)
	var sc4 := lerpf(0.4, 1.0, Fx.out_back(p4, 2.2))
	_tag.scale = Vector2(sc4, sc4)
