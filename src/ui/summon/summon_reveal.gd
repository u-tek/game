extends Control
## One hero's reveal in the summon sequence, as a poster coming off the press (the approved Lobby
## poster's look, docs/dev/ui-style-v4.md). The poster: a dark band down the left with her face as a
## halftone print, her rarity set vertically on it, the sheet number and her signature; her name set
## huge in compressed type and turned on its side, two-tone where it crosses the band; the hero
## herself; a hairline strip down the right edge with her faction, role and stars as vertical micro
## type; a stamp on a silver disc for NEW or the duplicate's shards.
##
## Every rarity has its own press (owner, 2026-10-20: "each rarity of hero to have its own reveal
## animation ... more flashy depending on rarity"), in the rarity language of src/ui/v4/rarity_kit.gd,
## all timed from one clock so a tap can fast-forward it (and a held clock freezes it for a still):
##   Rare       about 1 s, a clean quick press: the sheet slides in, one ink plate stamps her print
##              down, a small ink burst, she resolves, her name and the labels slide on.
##   Epic       about 1.8 s, a two-plate press: the sheet slides in, a violet plate prints her, then
##              a teal one out of register, then the key plate presses: a radial halftone burst, a
##              camera punch and a short shake, the plates pull into register as she resolves, and
##              her name slams in with its violet and teal plates misregistered, snapping together.
##   Legendary  about 3.5 s, the cinematic: the room drops to black, a gold foil press plate (her
##              figure as a gold die, glinting with the phone's tilt) comes down and presses with
##              sparks, a painted paper-white flash (no bloom), a heavy shake and haptic; her faction's
##              growth erupts from the poster's corners; the plate lifts off a gold foil sheet; a
##              light sweeps across her art; her giant name debosses into the foil; a LEGENDARY rubber
##              stamp slams down. Skippable like the rest: a tap jumps to the press, the next lands it.
## Reduce motion plays short static versions (the clock runs fast; no slides, shakes, slams, sparks,
## sweeps or flashes; the growth just sits there).
##
## Every hero arrives as a numbered print (Game.summon's "print"): her serial is stamped on with the
## badges ("No. 0412 / 5,000", the edition and printing). A misprint or a holo foil gets its own beat
## once she has landed: a big rubber stamp MISPRINT (with the flaw) or HOLO FOIL slams down, then the
## poster's figure flips like a card to the flawed print (misprint.gdshader on her still).
##
## The sequence (summon_sequence.gd) owns it: start() begins the clock, tap() fast-forwards
## (held beat -> press -> settled) and returns true once settled (= next hero), leave() slides it
## out and frees it. Screen-wide effects go out through the fx signal: ("flash", color, alpha),
## ("shake", _, trauma), ("punch", _, amount), ("tint", color, amount), ("darken", _, k),
## ("grain", _, amount).

signal fx(kind: String, color: Color, amount: float)
## Emitted once when every element has landed (the "tap to continue" hint can show).
signal landed

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const Burst := preload("res://src/ui/summon/summon_burst.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")
const RK := preload("res://src/ui/v4/rarity_kit.gd")

## The press (the key moment) per rarity: a Rare's one plate stamps, an Epic's key plate presses after
## its two colour plates, a Legendary's gold foil plate lands in the dark.
const BEAT := {"rare": 0.2, "epic": 0.85, "legendary": 1.25}
## Element start times after the press: rarity word, name, title, badges, stamp disc; then settle.
const SCHEDULE := {
	"rare": [0.04, 0.1, 0.16, 0.2, 0.3, 0.8],
	"epic": [0.1, 0.2, 0.36, 0.42, 0.52, 0.95],
	"legendary": [0.35, 0.8, 1.1, 1.15, 1.3, 2.25],
}
## How long the print takes to turn into her after the press, per rarity.
const RESOLVE := {"rare": 0.3, "epic": 0.38, "legendary": 0.55}
## The sheet sliding in from the right (Rare, Epic), seconds.
const SLIDE := {"rare": 0.2, "epic": 0.22, "legendary": 0.0}
## Epic: when the violet and the teal plate print.
const EPIC_PLATES := [0.22, 0.52]
## Legendary: the plate starts down at PLATE_FROM; heartbeats while it comes; after the press the
## growth erupts (GROW), the plate lifts (LIFT), the light sweeps (SWEEP) and the stamp slams (STAMP).
const PLATE_FROM := 0.1
const PULSES := [0.4, 0.75, 1.02]
const GROW := [0.02, 0.8]
const LIFT := [0.12, 0.45]
const SWEEP := [0.6, 1.3]
const STAMP := 1.6
## Under Reduce motion the clock runs this much faster.
const RM_SPEED := 3.0
## The misprint / holo beat: it starts this long after she has landed and lasts BEAT_FLAW.
const FLAW_GAP := 0.12
const BEAT_FLAW := 1.05
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
## 1 normally, 0 under Reduce motion (scales every move, slam and shake).
var _mo := 1.0
var _speed := 1.0
var _vw := 720.0

var _p: Control
var _pr := Rect2()
var _flood: Control
var _band: ColorRect
var _band_print: TextureRect
var _giant: Array[RichTextLabel] = []
var _giant_v: Array[RichTextLabel] = []
var _giant_t: Array[RichTextLabel] = []
var _deboss_m: ShaderMaterial
var _deboss_depth := 4.0
var _anchor: Node2D
var _print: TextureRect
var _print2: TextureRect
var _rar: Control
var _title: Control
var _badges: Control
var _tag: Control
var _chest := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## The print this pull made ({} for made-up results without one).
var print_data: Dictionary = {}
## Start of the misprint / holo beat (< 0: a plain print, no beat).
var _flaw_t := -1.0
var _flawed: TextureRect
var _flaw_mat: ShaderMaterial
var _flaw_stamp: Control
var _serial: Control
# Epic
var _hburst: ColorRect
# Legendary
var _veil: ColorRect
var _plate: Control
var _plate_home := Vector2.ZERO
var _foil_fig: TextureRect
var _sweep: TextureRect
var _sparks: RK.Sparks
var _growths: Array[TextureRect] = []
var _wash: ColorRect
var _legend_stamp: Control


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
	_mo = 1.0 if Kit.motion_ok() else 0.0
	_speed = 1.0 if _mo > 0.0 else RM_SPEED
	safe_top = top_inset
	safe_bottom = bottom_inset
	sheet = n
	sheets = total
	_burst_t = float(BEAT[rarity])
	_sched = SCHEDULE[rarity]
	_settle_t = _burst_t + float(_sched[5])
	print_data = res.get("print", {}) if res.get("print") is Dictionary else {}
	if str(print_data.get("flaw", "")) != "" or bool(print_data.get("holo", false)):
		_flaw_t = _settle_t + FLAW_GAP
		_settle_t = _flaw_t + BEAT_FLAW
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
	_vw = w
	var faction := str(_def.get("faction", "celestial"))
	_pr = Rect2(18, safe_top + 84, w - 36, maxf(600.0, h - safe_bottom - 100 - (safe_top + 84)))
	_p = PK.poster(self, _pr)
	var pw := _pr.size.x
	var ph := _pr.size.y
	var legend := rarity == "legendary"
	var epic := rarity == "epic"

	# The flood: a Legendary's poster turns to gold foil at the press (right of the band).
	if legend:
		_flood = RK.foil_rect(_p, Rect2(BAND_W, 0, pw - BAND_W, ph), "gold", 0, {"glint": 1.0, "sparkle": 0.8, "speed": 0.08})
		_flood.name = "FoilFlood"
		_flood.visible = false
	# The band with her face as a halftone print (gold on a Legendary's band).
	var band_ink: Color = PK.RED_INK if not legend else Color(RK.GOLD, 0.95)
	_band = PK.band(_p, Rect2(0, 0, BAND_W, ph), hero_id, skin, {"from": 0.24, "cell": 7.0, "ink": band_ink})
	_band_print = _band.get_meta("print") if _band.has_meta("print") else null
	PK.at(_band, PK.t("HH", 26, PAPER, "wide_black"), Vector2(14, 14))
	PK.at(_band, PK.t("Nº %02d / %02d\nRUN 0047" % [sheet, sheets], 11, Color(PAPER, 0.85), "mono_bold"), Vector2(14, 52))

	# Her name, huge, turned on its side, two-tone across the band. An Epic's has a violet and a teal
	# plate under it (they slam in out of register).
	var nm := str(_def.get("name", hero_id)).to_upper()
	var f := Kit.font("compressed")
	var fs := 270
	while fs > 120 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > ph * 0.86:
		fs -= 6
	var gpos := Vector2(BAND_W + fs * 0.6, ph * 0.03)
	var gbox := Vector2(ph, fs * 1.3)
	if epic:
		_giant_t = PK.giant(_p, nm, fs, [[0.0, pw, Color(RK.TEAL, 0.9)]], gpos, gbox, PI * 0.5, "compressed", -14, false)
		_giant_v = PK.giant(_p, nm, fs, [[0.0, pw, Color(RK.VIOLET, 0.9)]], gpos, gbox, PI * 0.5, "compressed", -14, false)
	_giant = PK.giant(_p, nm, fs, [[0.0, BAND_W, PAPER], [BAND_W, pw - BAND_W, INK]], gpos, gbox)
	if not _giant.is_empty():
		var host := _giant[0].get_parent().get_parent() as CanvasItem
		if host and host.material is ShaderMaterial:
			_deboss_m = host.material
			_deboss_depth = float(_deboss_m.get_shader_parameter("depth"))

	# An Epic's radial halftone burst runs on the paper, behind her.
	var feet := Vector2(0.0, ph - 4.0)
	var fig_h := ph * 0.92
	if epic:
		_hburst = RK.halftone_burst(_p, Rect2(Vector2.ZERO, Vector2(pw, ph)), Vector2(pw * 0.6, ph * 0.38), RK.VIOLET, Color(RK.TEAL, 0.85))

	# The hero: her plate prints (Rare one ink plate, Epic violet + teal) and the live figure over it.
	var box := Control.new()
	box.name = "HeroBox"
	box.clip_contents = true
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.size = Vector2(pw - 49, ph)
	_p.add_child(box)
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
	if epic:
		_print2 = _hero_print(tex, sr, Color(RK.TEAL, 0.92), 7.0, 0.2)
		box.add_child(_print2)
		_print = _hero_print(tex, sr, Color(RK.VIOLET, 0.92), 7.0, 0.5236)
		box.add_child(_print)
	elif not legend:
		_print = _hero_print(tex, sr, INK, 6.0, 0.5236)
		box.add_child(_print)
	else:
		# Her impression in the foil (the plate's die left it), fading as she resolves.
		_foil_fig = _still(tex, sr, RK.foil_material("gold", 2, {"rect_size": sr.size, "glint": 1.2}))
		_foil_fig.name = "FoilFigure"
		box.add_child(_foil_fig)
	box.add_child(_anchor)
	if legend:
		_sweep = _still(tex, sr, RK.foil_material("gold", 3, {"rect_size": sr.size, "sweep_w": 0.035, "hi": Color("fff8e4")}))
		_sweep.name = "LightSweep"
		box.add_child(_sweep)
	_chest = _pr.position + Vector2(feet.x, feet.y - fig_h * 0.62)
	if _hburst:
		(_hburst.material as ShaderMaterial).set_shader_parameter("center", Vector2(feet.x, feet.y - fig_h * 0.62))

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

	# On the band: her rarity, set vertically (it slams in; a Legendary's in shimmering gold), her
	# title, her signature.
	var rw := str(Kit.RARITY_NAMES.get(rarity, rarity)).to_upper()
	var rcol: Color = PAPER if rarity == "rare" else (Color("9d86ff") if epic else RK.GOLD_HI)
	var rar := PK.t(rw, 46, rcol, "wide_black")
	if legend:
		RK.shimmer(rar, rar.get_minimum_size().x, 0.3)
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
	if legend:
		_build_legend_stamp(pw, ph)
	_build_print_marks(tex, sr, feet, pw, ph, box)
	PK.grain(_p, 0.07)
	if legend:
		_build_press(tex, sr, faction)


## A still of her art lined up with the live figure, on `mat`.
func _still(tex: Texture2D, r: Rect2, mat: Material) -> TextureRect:
	var tr := TextureRect.new()
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.position = r.position
	tr.size = r.size
	tr.material = mat
	return tr


## The LEGENDARY rubber stamp (it slams down last), across her legs.
func _build_legend_stamp(pw: float, ph: float) -> void:
	var st := PrintCard.Stamp.new()
	st.name = "LegendStamp"
	st.text = "LEGENDARY"
	st.sub = "GOLD FOIL  ·  FIRST PRESSING  ·  RUN 0047"
	st.color = SIG
	st.seed_v = 31
	var sw := minf(pw - BAND_W - 40.0, 470.0)
	st.size = Vector2(sw, sw * 0.3)
	st.position = Vector2(BAND_W + (pw - BAND_W - 49.0 - sw) * 0.5 + 6.0, ph * 0.845)
	# Stamped on top of everything, her figure included (the relief moves it above).
	st.set_meta("above_paper", true)
	st.pivot_offset = st.size * 0.5
	st.rotation = -0.12
	st.modulate.a = 0.0
	_p.add_child(st)
	_legend_stamp = st


## The Legendary's press, over the poster: the black veil (the room in the dark), her faction's
## growths on the poster's corners (they erupt at the press), the gold foil plate (a dark brass
## slab with her figure as a gold die), its sparks and the painted flash.
func _build_press(tex: Texture2D, sr: Rect2, faction: String) -> void:
	var ppu := clampf(_pr.size.x / 11.0, 46.0, 66.0)
	var corners := {"tl": _pr.position, "tr": Vector2(_pr.end.x, _pr.position.y), "bl": Vector2(_pr.position.x, _pr.end.y), "br": _pr.end}
	var ph := 0.0
	for shape: String in ["tl", "br", "tr", "bl"]:
		var g := RK.growth(faction, shape, self, corners[shape], ppu if shape in ["tl", "br"] else ppu * 0.82,
			{"grow": 0.0, "twist": 0.06, "speed": 0.3, "breathe": 0.0, "phase": ph})
		ph += 1.7
		if g:
			g.name = "Growth_" + shape
			_growths.append(g)
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.mouse_filter = MOUSE_FILTER_IGNORE
	_veil.color = Color("0b0b0d")
	_veil.position = _pr.position - Vector2(40, 40)
	_veil.size = _pr.size + Vector2(80, 80)
	add_child(_veil)
	# The plate: the poster's size, her figure lined up with where she prints.
	var plate := Control.new()
	plate.name = "FoilPlate"
	plate.mouse_filter = MOUSE_FILTER_IGNORE
	var slab := Rect2(_pr.position - Vector2(10, 10), _pr.size + Vector2(20, 20))
	plate.position = slab.position
	plate.size = slab.size
	plate.pivot_offset = Vector2(slab.size.x * 0.5, slab.size.y * 0.55)
	_plate_home = slab.position
	var body := PlateBody.new()
	body.name = "Slab"
	body.size = slab.size
	plate.add_child(body)
	var die := TextureRect.new()
	die.name = "Die"
	die.mouse_filter = MOUSE_FILTER_IGNORE
	die.texture = tex
	die.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	die.stretch_mode = TextureRect.STRETCH_SCALE
	die.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# sr is in the poster's coordinates; the die is cut to the slab's face (inside its bevel).
	var face := Control.new()
	face.name = "DieFace"
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.clip_contents = true
	face.position = Vector2(7, 7)
	face.size = slab.size - Vector2(14, 14)
	body.add_child(face)
	die.position = _pr.position + sr.position - slab.position - face.position
	die.size = sr.size
	die.material = RK.foil_material("gold", 2, {"rect_size": sr.size, "glint": 1.4, "sparkle": 1.0})
	face.add_child(die)
	add_child(plate)
	_plate = plate
	_sparks = RK.Sparks.new()
	_sparks.name = "Sparks"
	_sparks.emit = Rect2(slab.position + Vector2(0, slab.size.y * 0.15), Vector2(slab.size.x, slab.size.y * 0.85))
	_sparks.count = 120
	_sparks.size = get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	add_child(_sparks)
	_wash = ColorRect.new()
	_wash.name = "PaintedFlash"
	_wash.mouse_filter = MOUSE_FILTER_IGNORE
	_wash.color = Color("fbfaf6")
	_wash.position = Vector2(-80, -80)
	_wash.size = (_sparks.size) + Vector2(160, 160)
	_wash.modulate.a = 0.0
	add_child(_wash)


## The print's marks: the serial stamp, and for a misprint or holo the flawed still (hidden until the
## flip) and the big rubber stamp.
func _build_print_marks(tex: Texture2D, sr: Rect2, feet: Vector2, pw: float, ph: float, box: Control) -> void:
	if print_data.is_empty():
		return
	var ss := SerialStamp.new()
	ss.name = "Serial"
	ss.print_data = print_data
	ss.size = Vector2(250, 66)
	ss.position = Vector2(pw - 48 - 262, 18)
	ss.pivot_offset = ss.size * 0.5
	ss.rotation = -0.035
	_p.add_child(ss)
	_serial = ss
	if _flaw_t < 0.0:
		return
	_flawed = TextureRect.new()
	_flawed.name = "FlawedPrint"
	_flawed.mouse_filter = MOUSE_FILTER_IGNORE
	_flawed.texture = tex
	_flawed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flawed.stretch_mode = TextureRect.STRETCH_SCALE
	_flawed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_flawed.position = sr.position
	_flawed.size = sr.size
	_flawed.pivot_offset = Vector2(feet.x - sr.position.x, sr.size.y * 0.5)
	_flaw_mat = PrintCard.material_for(print_data, Vector4(0, 0, 1, 1), 24.0)
	_flaw_mat.set_shader_parameter("on_paper", false)
	_flaw_mat.set_shader_parameter("paper", PAPER)
	_flaw_mat.set_shader_parameter("cell", 6.0)
	if bool(print_data.get("holo", false)):
		_flaw_mat.set_shader_parameter("holo", 1.5)
	_flawed.material = _flaw_mat
	_flawed.visible = false
	box.add_child(_flawed)
	var flaw := str(print_data.get("flaw", ""))
	var st := PrintCard.Stamp.new()
	st.name = "FlawStamp"
	if flaw != "":
		st.text = "MISPRINT"
		var fl := PrintRules.flaw_name(flaw).to_upper()
		if flaw == "swap":
			fl += " · %s" % PrintRules.ink_name(str(print_data.get("ink", ""))).to_upper()
		st.sub = fl + ("  ·  HOLO FOIL" if bool(print_data.get("holo", false)) else "")
		st.color = SIG
	else:
		st.text = "HOLO FOIL"
		st.sub = "A FOILED PRINT  ·  TILT IT"
		st.color = INK
	var sw := minf(pw - 120.0, 520.0)
	st.size = Vector2(sw, sw * 0.32)
	st.position = Vector2((pw - sw) * 0.5 + 30.0, ph * 0.56)
	st.pivot_offset = st.size * 0.5
	st.rotation = -0.22
	st.modulate.a = 0.0
	# Stamped over her figure, like the LEGENDARY stamp (the relief moves it above).
	st.set_meta("above_paper", true)
	_p.add_child(st)
	_flaw_stamp = st


## The misprint beat on the clock: the stamp slams (big to its size with a bounce), then the figure
## flips like a card (squash to nothing, the flawed print grows back).
func _apply_flaw(t: float, zoom: float) -> void:
	var ks := Fx.k01(t, _flaw_t, _flaw_t + 0.3)
	if _flaw_stamp:
		_flaw_stamp.modulate.a = Fx.k01(t, _flaw_t, _flaw_t + 0.05)
		var sc := lerpf(lerpf(1.0, 2.6, _mo), 1.0, Fx.out_back(ks, 1.3))
		_flaw_stamp.scale = Vector2(sc, sc)
	if _flawed == null:
		return
	var kf := Fx.k01(t, _flaw_t + 0.36, _flaw_t + 0.74)
	if kf <= 0.0:
		_flawed.visible = false
		_anchor.visible = true
		return
	if kf < 0.5:
		var sx := 1.0 - kf * 2.0
		_anchor.visible = true
		_anchor.scale = Vector2(zoom * sx, zoom)
		_flawed.visible = false
	else:
		_anchor.visible = false
		_flawed.visible = true
		var sx2 := Fx.out_back((kf - 0.5) * 2.0, 1.2)
		_flawed.scale = Vector2(sx2, 1.0)


## A halftone print of the hero's still (one ink plate), lined up with the live figure.
func _hero_print(tex: Texture2D, r: Rect2, ink: Color, cell: float, angle: float) -> TextureRect:
	var m := SignalKit.halftone_material(cell, ink, false)
	m.set_shader_parameter("angle", angle)
	m.set_shader_parameter("gain", 1.35)
	var tr := _still(tex, r, m)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	tr.set_meta("home", r.position)
	tr.pivot_offset = r.size * 0.5
	return tr


# ------------------------------------------------------------------ timeline

func _build_events() -> void:
	_events.clear()
	var p := _burst_t
	match rarity:
		"rare":
			_events.append([0.0, "slide"])
			_events.append([p, "burst"])
		"epic":
			_events.append([0.0, "beat_start"])
			_events.append([float(EPIC_PLATES[0]), "plate0"])
			_events.append([float(EPIC_PLATES[1]), "plate1"])
			_events.append([p, "burst"])
			_events.append([p + float(_sched[0]), "slam"])
			_events.append([p + float(_sched[1]) + 0.08, "name"])
		"legendary":
			_events.append([0.0, "beat_start"])
			for i in PULSES.size():
				_events.append([float(PULSES[i]), "pulse%d" % i])
			_events.append([p, "burst"])
			_events.append([p + float(_sched[0]), "slam"])
			_events.append([p + float(_sched[1]) + 0.12, "name"])
			_events.append([p + float(LIFT[1]), "lights"])
			_events.append([p + STAMP, "legend_stamp"])
	if _flaw_t >= 0.0:
		_events.append([_flaw_t, "flaw_stamp"])
		_events.append([_flaw_t + 0.36, "flip"])
	_events.append([_settle_t, "settle"])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_next_event = 0


## Starts the clock (the sequence calls it when this hero's turn comes).
func start() -> void:
	_running = true
	_t = 0.0
	fx.emit("tint", RK.ink(rarity) if rarity != "rare" else INK, {"rare": 0.15, "epic": 0.4, "legendary": 0.0}[rarity])
	_apply()


## A tap: during the held beat it jumps to the press; while things are still landing it
## settles everything at once; once settled it returns true (show the next hero).
func tap() -> bool:
	if not _running:
		return false
	if _t < _burst_t - 0.02:
		_jump(_burst_t)
		return false
	if _flaw_t >= 0.0 and _t < _flaw_t - 0.02:
		# Land everything, but let the misprint beat play: it is the moment.
		_jump(_flaw_t)
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
	# Events before `to` are skipped silently (a skipped press still lifts the dark); one exactly at
	# `to` still fires.
	while _next_event < _events.size() and float(_events[_next_event][0]) < to:
		var id := str(_events[_next_event][1])
		if id == "burst":
			_on_burst(true)
		elif id == "lights":
			fx.emit("darken", Color.BLACK, 0.0)
		_next_event += 1
	_t = to
	_fire_events()
	_apply()


func _process(delta: float) -> void:
	if not _running:
		return
	var nt := _t + delta * _speed
	_t = nt if hold < 0.0 else minf(nt, hold)
	_fire_events()
	_apply()


func _fire_events() -> void:
	while _next_event < _events.size() and float(_events[_next_event][0]) <= _t:
		_on_event(str(_events[_next_event][1]))
		_next_event += 1


## Screen shake (and the camera punch) scaled by the motion setting.
func _shake(amount: float, punch: float = 0.0) -> void:
	if _mo <= 0.0:
		return
	fx.emit("shake", Color.WHITE, amount)
	if punch > 0.0:
		fx.emit("punch", Color.WHITE, punch)


func _on_event(id: String) -> void:
	match id:
		"slide":
			UI.sfx("tell")
		"beat_start":
			if rarity == "legendary":
				# The room drops to black.
				fx.emit("darken", Color.BLACK, 1.0)
				UI.sfx("riser")
				UI.haptic(15)
			else:
				fx.emit("darken", Color.BLACK, 0.3)
				UI.sfx("tell")
				UI.haptic(10)
		"plate0", "plate1":
			var n := int(id.substr(5))
			UI.sfx("beat")
			UI.haptic(14 + 6 * n)
			_shake(0.2 + 0.06 * n)
			fx.emit("grain", Color.WHITE, 0.1)
		"pulse0", "pulse1", "pulse2":
			var n2 := int(id.substr(5))
			UI.sfx("beat")
			UI.haptic(12 + 8 * n2)
			_shake(0.16 + 0.08 * n2)
			fx.emit("grain", Color.WHITE, 0.1 + 0.04 * n2)
		"burst":
			_on_burst(false)
		"slam":
			UI.sfx("slam")
			UI.haptic(35 if rarity == "legendary" else 22)
			_shake(0.4 if rarity == "legendary" else 0.28)
			if _mo > 0.0:
				_spawn_burst(_pr.position + _band.position + _rar.position + _rar.size * 0.5, RK.ink(rarity) if rarity != "rare" else INK, 0.5)
		"name":
			UI.sfx("slam")
			UI.haptic(30 if rarity == "legendary" else 25)
			_shake(0.45 if rarity == "legendary" else 0.32, 0.4 if rarity == "epic" else 0.0)
			fx.emit("grain", Color.WHITE, 0.14)
		"lights":
			fx.emit("darken", Color.BLACK, 0.0)
		"legend_stamp":
			UI.sfx("slam")
			UI.sfx("legendary")
			UI.haptic(70)
			_shake(0.75, 0.5)
			fx.emit("grain", Color.WHITE, 0.22)
			if _legend_stamp and _mo > 0.0:
				_spawn_burst(_pr.position + _legend_stamp.position + _legend_stamp.size * 0.5, SIG, 1.1)
		"flaw_stamp":
			var is_flaw := str(print_data.get("flaw", "")) != ""
			UI.sfx("slam")
			UI.sfx("legendary" if is_flaw else "sparkle")
			UI.haptic(60)
			_shake(0.7)
			if _mo > 0.0:
				fx.emit("flash", SIG if is_flaw else Color(0.85, 0.95, 1.0), 0.35)
			fx.emit("grain", Color.WHITE, 0.25)
			if _flaw_stamp and _mo > 0.0:
				_spawn_burst(_pr.position + _flaw_stamp.position + _flaw_stamp.size * 0.5, SIG if is_flaw else INK, 1.1)
		"flip":
			UI.sfx("reveal")
			UI.haptic(25)
			fx.emit("grain", Color.WHITE, 0.18)
		"settle":
			settled = true
			landed.emit()


## The press. quiet = reached by fast-forwarding past it (keep the visuals, drop the sound).
func _on_burst(quiet: bool) -> void:
	# A Legendary's room stays dim while the sparks fly and the plate lifts ("lights", below); a skip
	# past it brings the lights straight up.
	fx.emit("darken", Color.BLACK, 0.8 if rarity == "legendary" and not quiet and _mo > 0.0 else 0.0)
	if rarity == "legendary":
		fx.emit("tint", RK.GOLD, 0.25)
	if quiet:
		return
	match rarity:
		"legendary":
			UI.sfx("legendary")
			UI.sfx("burst")
			UI.sfx("slam")
			UI.haptic(110, 1.0)
			_shake(1.0, 1.0)
			fx.emit("grain", Color.WHITE, 0.16)
			if _mo > 0.0:
				_spawn_burst(_chest, RK.GOLD_INK, 1.8)
				_spawn_burst(_chest, RK.GOLD_HI, 1.1)
		"epic":
			UI.sfx("burst")
			UI.sfx("slam")
			UI.haptic(45)
			_shake(0.55, 0.9)
			if _mo > 0.0:
				fx.emit("flash", Color(0.86, 0.82, 1.0), 0.45)
			fx.emit("grain", Color.WHITE, 0.2)
		_:
			UI.sfx("reveal")
			UI.haptic(14)
			_shake(0.16)
			if _mo > 0.0:
				fx.emit("flash", Color(1, 1, 1), 0.22)
				_spawn_burst(_chest, INK, 0.5)
			fx.emit("grain", Color.WHITE, 0.1)


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
	tw.tween_property(self, "position:x", -size.x * 0.4 * _mo, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
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
	var res: float = RESOLVE[rarity]
	var kb := Fx.k01(t, 0.0, maxf(_burst_t, 0.001))
	# The sheet slides in from the right (Rare, Epic).
	var sl := float(SLIDE[rarity])
	if sl > 0.0 and _running:
		position.x = _vw * 0.55 * (1.0 - Fx.out_cubic(Fx.k01(t, 0.0, sl))) * _mo
	match rarity:
		"rare":
			_apply_rare(t, tb, after, res)
		"epic":
			_apply_epic(t, tb, after, res, kb)
		"legendary":
			_apply_legend(t, tb, after, res, kb)
	# Her: resolves out of an overexposed glow and settles with a small push-in.
	var hero_a := Fx.k01(tb, 0.02, res * 0.8) if after else 0.0
	if rarity == "legendary":
		hero_a = Fx.k01(tb, 0.18, 0.18 + res) if after else 0.0
	var glow := (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, res + 0.35))) if after else 0.0
	var zoom := 1.0 + 0.04 * _mo * (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, res + 0.4))) if after else 1.0 + 0.04 * _mo
	var hot := Color(1.5, 1.4, 1.25) if rarity == "legendary" else Color(1.35, 1.3, 1.28)
	var m := Color.WHITE.lerp(hot, glow * (0.6 if rarity == "rare" else 1.0))
	m.a = hero_a
	_anchor.modulate = m
	_anchor.scale = Vector2(zoom, zoom)
	# The name.
	var s1 := float(_sched[1])
	match rarity:
		"legendary":
			# Debossed into the foil: it settles from a little bigger while the cut deepens.
			var pn := Fx.k01(tb, s1, s1 + 0.32)
			var sc := lerpf(1.0 + 0.1 * _mo, 1.0, Fx.out_cubic(pn))
			PK.giant_pose(_giant, Vector2.ZERO, sc, Fx.k01(tb, s1, s1 + 0.1))
			if _deboss_m:
				_deboss_m.set_shader_parameter("depth", _deboss_depth * Fx.out_cubic(Fx.k01(tb, s1 + 0.05, s1 + 0.4)))
		"epic":
			# Slams in along its reading axis with the colour plates out of register, snapping together.
			var pe := Fx.k01(tb, s1, s1 + 0.26)
			var drop := -ph * 0.3 * (1.0 - Fx.out_back(pe, 1.3)) * _mo
			var a := Fx.k01(tb, s1, s1 + 0.06)
			PK.giant_pose(_giant, Vector2(0, drop), 1.0, a)
			var reg := (1.0 - Fx.out_cubic(Fx.k01(tb, s1 + 0.06, s1 + 0.42))) * _mo
			var ca := a * (1.0 - Fx.k01(tb, s1 + 0.42, s1 + 0.62))
			PK.giant_pose(_giant_v, Vector2(26.0 * reg, drop - 30.0 * reg), 1.0, ca)
			PK.giant_pose(_giant_t, Vector2(-22.0 * reg, drop + 24.0 * reg), 1.0, ca)
		_:
			var pr := Fx.k01(tb, s1, s1 + 0.24)
			var dr := -ph * 0.1 * (1.0 - Fx.out_cubic(pr)) * _mo
			PK.giant_pose(_giant, Vector2(0, dr), 1.0, Fx.k01(tb, s1, s1 + 0.1))
	# Rarity word: slams (scale) on the band.
	var s0 := float(_sched[0])
	var p0 := Fx.k01(tb, s0, s0 + 0.3)
	_rar.modulate.a = Fx.k01(tb, s0, s0 + 0.07)
	var big := {"rare": 1.25, "epic": 1.8, "legendary": 2.3}[rarity] as float
	var sc0 := lerpf(lerpf(1.0, big, _mo), 1.0, Fx.out_back(p0, 1.2))
	_rar.scale = Vector2(sc0, sc0)
	# Title, badges (the strip) and the stamp.
	var p2 := Fx.out_cubic(Fx.k01(tb, float(_sched[2]), float(_sched[2]) + 0.3))
	_title.modulate.a = p2
	var p3 := Fx.out_cubic(Fx.k01(tb, float(_sched[3]), float(_sched[3]) + 0.3))
	_badges.modulate.a = p3
	_badges.position = Vector2(30.0 * (1.0 - p3) * _mo, 0)
	var s4 := float(_sched[4])
	var p4 := Fx.k01(tb, s4, s4 + 0.36)
	_tag.modulate.a = Fx.k01(tb, s4, s4 + 0.1)
	var sc4 := lerpf(lerpf(1.0, 0.4, _mo), 1.0, Fx.out_back(p4, 2.2))
	_tag.scale = Vector2(sc4, sc4)
	if _serial:
		var p5 := Fx.k01(tb, s4 + 0.12, s4 + 0.4)
		_serial.modulate.a = Fx.k01(tb, s4 + 0.12, s4 + 0.18)
		var sc5 := lerpf(lerpf(1.0, 1.8, _mo), 1.0, Fx.out_back(p5, 1.6))
		_serial.scale = Vector2(sc5, sc5)
	if _flaw_t >= 0.0:
		_apply_flaw(t, zoom)


## Rare: the ink plate stamps her print at the press (a small drop and settle), and she resolves
## out of it at once.
func _apply_rare(_at: float, tb: float, after: bool, res: float) -> void:
	if _print == null:
		return
	var a := 0.0
	var sc := 1.0
	if after:
		a = Fx.k01(tb, 0.0, 0.04) * (1.0 - Fx.k01(tb, res * 0.4, res))
		sc = lerpf(1.0 + 0.05 * _mo, 1.0, Fx.out_cubic(Fx.k01(tb, 0.0, 0.1)))
	_print.modulate.a = a
	_print.scale = Vector2(sc, sc)
	(_print.material as ShaderMaterial).set_shader_parameter("lift", 0.06 * (1.0 - Fx.k01(tb, 0.0, res)) if after else 0.0)


## Epic: the violet plate, then the teal one out of register; the key plate's press pulls them into
## register as she resolves, and the radial halftone burst runs out behind her.
func _apply_epic(t: float, tb: float, after: bool, res: float, kb: float) -> void:
	var e0 := float(EPIC_PLATES[0])
	var e1 := float(EPIC_PLATES[1])
	var fade := (1.0 - Fx.k01(tb, res * 0.35, res)) if after else 1.0
	var reg := (1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, 0.16))) if after else 1.0
	var jit := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 2.0 * _mo * (0.0 if after else kb)
	var a0 := Fx.k01(t, e0, e0 + 0.05)
	var s0 := lerpf(1.0 + 0.05 * _mo, 1.0, Fx.out_cubic(Fx.k01(t, e0, e0 + 0.12)))
	_print.modulate.a = a0 * fade
	_print.scale = Vector2(s0, s0)
	_print.position = (_print.get_meta("home") as Vector2) + (Vector2(14.0, -8.0) * reg * _mo + jit)
	var a1 := Fx.k01(t, e1, e1 + 0.05)
	var s1 := lerpf(1.0 + 0.05 * _mo, 1.0, Fx.out_cubic(Fx.k01(t, e1, e1 + 0.12)))
	_print2.modulate.a = a1 * fade * 0.85
	_print2.scale = Vector2(s1, s1)
	_print2.position = (_print2.get_meta("home") as Vector2) + (Vector2(-12.0, 10.0) * reg * _mo - jit)
	for pr: TextureRect in [_print, _print2]:
		(pr.material as ShaderMaterial).set_shader_parameter("lift", (-0.32 + 0.14 * kb) if not after else 0.08 * (1.0 - Fx.k01(tb, 0.0, res)))
	# The band turns deep violet with a teal print as the plates go down.
	var fe := Fx.k01(t, e0, e1 + 0.2) if not after else 1.0
	_band.color = PK.BAND.lerp(RK.VIOLET_DEEP, fe)
	if _band_print:
		(_band_print.material as ShaderMaterial).set_shader_parameter("ink", PK.RED_INK.lerp(Color(RK.TEAL, 0.95), fe))
	if _hburst:
		var kh := Fx.k01(tb, 0.0, 0.8) if after else 0.0
		_hburst.visible = after and kh < 1.0 and _mo > 0.0
		(_hburst.material as ShaderMaterial).set_shader_parameter("k", kh)


## Legendary: the dark, the plate coming down and pressing, its lift off the gold foil, the
## growths erupting, the sparks, the flash, the light sweep and the stamp.
func _apply_legend(t: float, tb: float, after: bool, res: float, _kb: float) -> void:
	var on := _mo > 0.0
	# The dark: the poster sits in it until the press lifts it.
	if _veil:
		_veil.modulate.a = (0.9 * Fx.k01(t, 0.0, 0.12)) if not after else 0.9 * (1.0 - Fx.k01(tb, 0.0, 0.22))
		_veil.visible = _veil.modulate.a > 0.002
	if _flood:
		_flood.visible = after
	# The plate: comes down (accelerating) from above and bigger, presses, lifts off toward us.
	if _plate:
		if not on:
			_plate.visible = false
		elif not after:
			var kd := Fx.k01(t, PLATE_FROM, _burst_t)
			var hgt := 1.0 - kd * kd * kd
			_plate.visible = true
			_plate.modulate.a = Fx.k01(t, PLATE_FROM, PLATE_FROM + 0.3)
			var s := 1.0 + 0.16 * hgt
			_plate.scale = Vector2(s, s)
			_plate.position = _plate_home + Vector2(0, -56.0 * hgt)
			(_plate.get_child(0) as PlateBody).height = hgt
		else:
			# Lifted off and away: up and toward us, out of the top of the screen.
			var kl := Fx.k01(tb, float(LIFT[0]), float(LIFT[1]))
			_plate.visible = kl < 1.0
			var squash := 1.0 - 0.015 * (1.0 - Fx.k01(tb, 0.0, 0.12))
			var e := Fx.in_cubic(kl)
			var s2 := squash + 0.22 * e
			_plate.scale = Vector2(s2, s2)
			_plate.position = _plate_home + Vector2(0, -(_pr.size.y + 260.0) * e)
			_plate.modulate.a = 1.0 - Fx.k01(kl, 0.75, 1.0)
			(_plate.get_child(0) as PlateBody).height = e
	if _sparks:
		_sparks.t = tb if on and after else -1.0
	# The painted flash: paper white over everything at the press, fading fast (no bloom).
	if _wash:
		_wash.modulate.a = (0.9 * exp(-tb * 10.0) if after else 0.0) * _mo
		_wash.visible = _wash.modulate.a > 0.004
	# The growths erupt out of the corners, then twist slowly (the shader's clock).
	var kg := Fx.k01(tb, float(GROW[0]), float(GROW[1])) if after else 0.0
	var gv := Fx.out_back(kg, 1.6) if on else (1.0 if after else 0.0)
	for g in _growths:
		(g.material as ShaderMaterial).set_shader_parameter("grow", gv)
		g.visible = gv > 0.001
	# Her impression in the foil fades as she resolves; the light sweeps across her.
	if _foil_fig:
		_foil_fig.modulate.a = (1.0 - Fx.k01(tb, 0.25, 0.25 + res)) if after else 0.0
	if _sweep:
		var ks := Fx.k01(tb, float(SWEEP[0]), float(SWEEP[1]))
		_sweep.visible = on and after and ks > 0.0 and ks < 1.0
		(_sweep.material as ShaderMaterial).set_shader_parameter("sweep", Fx.smooth(ks))
		(_sweep.material as ShaderMaterial).set_shader_parameter("amount", 0.7)
	# The LEGENDARY stamp slams.
	if _legend_stamp:
		var kst := Fx.k01(tb, STAMP, STAMP + 0.3)
		_legend_stamp.modulate.a = Fx.k01(tb, STAMP, STAMP + 0.05)
		var ss := lerpf(lerpf(1.0, 2.8, _mo), 1.0, Fx.out_back(kst, 1.3))
		_legend_stamp.scale = Vector2(ss, ss)
	if _band_print:
		(_band_print.material as ShaderMaterial).set_shader_parameter("lift", 0.0 if after else -0.3)


## The press plate's body: a dark brass slab with a bevel, corner screws and its die number; the
## shadow it casts grows softer and further off the higher it is (`height` 1 = up high, 0 = pressed).
class PlateBody:
	extends Control
	var height := 1.0:
		set(v):
			if absf(v - height) > 0.001:
				height = v
				queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# The shadow on the poster below (drawn first, around the slab).
		var off := Vector2(10, 18) + Vector2(18, 60) * height
		for i in 4:
			var g := 6.0 + 10.0 * i * (0.4 + height)
			draw_rect(Rect2(r.position + off - Vector2(g, g) * 0.5, r.size + Vector2(g, g)), Color(0, 0, 0, (0.16 - 0.03 * i) * (1.0 - 0.4 * height)))
		draw_rect(r, Color("2b2416"))
		# Bevel: lit top and left, dark bottom and right.
		var b := 7.0
		draw_rect(Rect2(0, 0, size.x, b), Color("7a6534"))
		draw_rect(Rect2(0, 0, b, size.y), Color("5f4e28"))
		draw_rect(Rect2(0, size.y - b, size.x, b), Color("17120a"))
		draw_rect(Rect2(size.x - b, 0, b, size.y), Color("1d170c"))
		draw_rect(r.grow(-b), Color("231d11"))
		# The die's engraved border and screws.
		draw_rect(r.grow(-b - 10.0), Color(0.82, 0.65, 0.3, 0.35), false, 1.5)
		for c: Vector2 in [Vector2(22, 22), Vector2(size.x - 22, 22), Vector2(22, size.y - 22), Vector2(size.x - 22, size.y - 22)]:
			draw_circle(c, 7.0, Color("6d5a2c"))
			draw_circle(c, 5.0, Color("3a2f17"))
			draw_line(c - Vector2(4, 1), c + Vector2(4, 1), Color("8c7440"), 1.5)
		var f := Kit.font("mono_bold")
		draw_string(f, Vector2(34, size.y - 30), "HH · FOIL DIE · Nº 0047 · 24K", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.7, 0.36, 0.7))


## The serial stamped on the poster: "No." small, the number big in mono, "/ 5,000", the edition and
## printing under it, inked by hand (specks where the ink missed); an early serial (No. 0100 or
## lower) is inked in signal.
class SerialStamp:
	extends Control
	var print_data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var p := print_data
		var early := int(p.get("serial", 9999)) <= PrintRules.EARLY_SERIAL
		var c := Color(Color("ff4b1f") if early else Color("101113"), 0.9)
		var fm := Kit.font("mono_bold")
		var fr := Kit.font("mono")
		draw_rect(Rect2(Vector2.ZERO, size), c, false, 2.0)
		draw_string(fr, Vector2(10, 24), "No.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		var num := "%04d" % int(p.get("serial", 0))
		draw_string(fm, Vector2(42, 32), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, c)
		var nw := fm.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(fr, Vector2(48 + nw, 30), "/ %s" % Kit.format_full(int(p.get("run", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
		draw_line(Vector2(8, 42), Vector2(size.x - 8, 42), Color(c, 0.6), 1.0)
		draw_string(fm, Vector2(10, 58), PrintCard.edition_line(p), HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 10, c)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(p.get("v", 7)) + 11
		var paper := Color("e9e8e2")
		for i in 90:
			draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(0.4, 1.2), Color(paper, rng.randf_range(0.5, 0.95)))
