extends Control
## A heroine's ultimate, cut in (combat v1; replaces the old close-up). Ink bars slam over the HUD
## and it hard-cuts to her poster: paper, a straight ink band down the right with her red print in it.
## The camera travels up her body as she dips and surges into the frame, lands on a cowboy shot as
## her head snaps to the lens and the skill's key word slams in behind her, holds her pose, then she
## coils and lunges. The impact frame prints the poster as its plates (paper to ink, the band to
## signal, her a hard two-tone) while an ink crown bursts where her blow lands, a beat of hit-stop in
## colour, and a hard cut back to the field (the battle screen punches in on the target, the same
## crown stamps on it and the hit lands: the contact signal). The bars hold through the landing.
## Every pose, camera move, sound and haptic is a function of the clock _t (seconds at 1x), so a tap
## (skip) and seek are exact. Tiers: "full", "repeat" (an auto cast she already showed this fight:
## starts at the cowboy shot), "still" (Reduce motion: no camera, no flip, a crossfade).
##   var c := UltCutin.new(); overlay.add_child(c)
##   c.play({"hero": id, "skin": skin, "skill_name": "Eclipse Harvest", "rate": 1.0, "tier": "full",
##           "P": target_chest_on_screen, "dir": 1, "top_h": 142.0, "bottom_h": 230.0})

signal impact
signal contact

const DeviceTier := preload("res://src/art/device_tier.gd")
const BP := preload("res://src/ui/v4/battle/battle_print.gd")
const CROWN := preload("res://assets/art/ui/ult/ink_crown.png")

## The beats (s at 1x). tools/anim/make_ult_cutin.py keys her performance to the same numbers.
const T_CUT := 0.08
const T_SNAP := 0.40
const T_GHOST := 0.48
const T_RISE_SND := 0.70
const T_COIL := 0.90
const T_STRIKE := 1.00
const T_IMPACT := 1.08
const T_COLOUR := 1.14
const T_CONTACT := 1.22
const T_BARS_OUT := 1.62
const T_END := 1.80
const REPEAT_FROM := 0.40
const STILL_CONTACT := 0.85
const BAND_X := 0.64
const CROWN_PX := 440.0
const INK := Color("141517")
const SIG := Color("ff5c29")

static var _cuts := {}
## The baked cut points (assets/art/heroes/cuts.json), by rig file base.
static var _baked := {}

var tier := "full"
var rate := 1.0
var _t := 0.0
var _contact_t := T_CONTACT
var _fired := {}
var _impact_frames := 0
var _done_contact := false
var _vs := Vector2(720, 1280)
var _y0 := 0.0
var _y1 := 0.0
var _dir := 1
var _P := Vector2.ZERO
var _cut := 0.45

var _bg_layer: CanvasLayer
var _her_layer: CanvasLayer
var _fg_layer: CanvasLayer
var _bg: Control
var _flip: ColorRect
var _band: Control
var _band_fill: ColorRect
var _print: TextureRect
var _print_base := Vector2.ZERO
## An Encore step: the partner's print on the paper and its caption.
var _partner: TextureRect
var _partner_cap: Label
var _words: Array[RichTextLabel] = []
var _ghost: Array[RichTextLabel] = []
var _mono: Label
var _crown: TextureRect
var _crown_at: AtlasTexture
var _bar_top: Control
var _bar_bot: Control
var _top_h := 140.0
var _bot_h := 220.0
var _sp: Node2D
var _rig: RigPlayer
var _f_open := {}
var _f_look := {}
var _f_strike := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## opts: hero, skin, skill_name, rate (1 / 1.5 / 2.1), tier, P (where the blow lands, screen px),
## dir (+1: she strikes to the right), top_h / bottom_h (the HUD strips the bars cover), chain (an
## Encore step: the giant word becomes the chain's numeral), partner (an Encore step: the heroine who
## passed it, whose ink print stays on the sheet behind her) and partner_skin.
func play(opts: Dictionary) -> void:
	_vs = get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var hero := str(opts.get("hero", ""))
	var skin := str(opts.get("skin", ""))
	rate = maxf(float(opts.get("rate", 1.0)), 0.1)
	tier = str(opts.get("tier", "full"))
	if not Kit.motion_ok():
		tier = "still"
	_P = opts.get("P", _vs * Vector2(0.5, 0.3))
	_dir = 1 if int(opts.get("dir", 1)) >= 0 else -1
	_top_h = float(opts.get("top_h", 140.0))
	_bot_h = float(opts.get("bottom_h", 220.0))
	_y0 = _top_h
	_y1 = _vs.y - _bot_h
	_cut = _cut_point(hero, skin)
	_contact_t = STILL_CONTACT if tier == "still" else T_CONTACT
	_build_bg(hero, skin, str(opts.get("skill_name", "Ultimate")), int(opts.get("chain", 0)))
	if int(opts.get("chain", 0)) > 0 and str(opts.get("partner", "")) != "":
		_build_partner(str(opts.partner), str(opts.get("partner_skin", "")))
	_build_her(hero, skin)
	_build_bars(hero, skin)
	if tier == "repeat":
		_seek(REPEAT_FROM)
	_apply()


## Seconds (real time, at this rate) from now to the contact frame.
func contact_time() -> float:
	return maxf(_contact_t - _t, 0.0) / rate


## A tap: before the coil it jumps to the coil (the wind-up, strike and impact still play), after it
## straight to the impact.
func skip() -> void:
	if tier == "still":
		_seek(maxf(_t, _contact_t - 0.05))
	elif _t < T_COIL:
		_seek(T_COIL)
	elif _t < T_IMPACT:
		_seek(T_IMPACT)


func _gui_input(event: InputEvent) -> void:
	var tap := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tap:
		accept_event()
		skip()


func _exit_tree() -> void:
	# Freed early (the battle left): the field must not wait for a contact that never comes.
	if not _done_contact:
		_done_contact = true
		contact.emit()


func _process(delta: float) -> void:
	var prev := _t
	var nt := _t + delta * rate
	# The impact frame shows on at least two drawn frames at any speed: the clock lands on it
	# exactly, then holds inside it for a second frame.
	if tier != "still":
		if prev < T_IMPACT and nt > T_IMPACT:
			nt = T_IMPACT
		elif prev >= T_IMPACT and prev < T_COLOUR:
			_impact_frames += 1
			if _impact_frames < 2:
				nt = minf(nt, T_COLOUR - 0.0001)
	_advance_rig(prev, nt)
	_t = nt
	_apply()
	if _t >= T_END:
		queue_free()


func _seek(t: float) -> void:
	var prev := _t
	var step := 1.0 / 30.0
	var at := prev
	while at < t:
		var nx := minf(at + step, t)
		_advance_rig(at, nx)
		at = nx
	_t = t
	# The beats jumped over stay silent (a skip doesn't replay the clacks or the riser); the cut's
	# own sound and the impact and contact still fire.
	for k: String in ["snap", "ghost", "rise"]:
		var beat: float = {"snap": T_SNAP, "ghost": T_GHOST, "rise": T_RISE_SND}[k]
		if beat < t:
			_fired[k] = true


## Her rig runs on the clock; frozen through the hit-stop.
func _advance_rig(a: float, b: float) -> void:
	if _rig == null:
		return
	var lo := a
	var hi := b
	if tier != "still":
		if lo >= T_IMPACT:
			return
		hi = minf(hi, T_IMPACT)
	if hi > lo:
		_rig.advance(hi - lo)


# ------------------------------------------------------------------ the poster

func _build_bg(hero: String, skin: String, skill_name: String, chain: int) -> void:
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = 5
	add_child(_bg_layer)
	_bg = Control.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.size = _vs
	_bg_layer.add_child(_bg)
	var paper := Control.new()
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.size = _vs
	_bg.add_child(paper)
	PhysicalKit.paper_fill(paper, BP.MATTE, 0.04, 0.2)
	_flip = BP.rect(_bg, Rect2(Vector2.ZERO, _vs), INK)
	_flip.visible = false
	var w := _vs.x
	var bx := floorf(w * BAND_X)
	var fh := _y1 - _y0
	_band = Control.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.clip_contents = true
	_band.position = Vector2(bx, _y0)
	_band.size = Vector2(w - bx, fh)
	_bg.add_child(_band)
	_band_fill = BP.rect(_band, Rect2(Vector2.ZERO, _band.size), BP.BAND)
	# Her red print in the band, hard-clipped by it (no fade into the ink), a bust crop.
	_print = BP.halftone(hero, skin, {"crop": "bust", "cell": 6.0})
	_print.size = Vector2(_band.size.x * 1.5, fh)
	_print_base = Vector2(-_band.size.x * 0.25, 0)
	_print.position = _print_base
	_band.add_child(_print)
	# The band's edge: a paper hairline and a tick rule down it.
	BP.rect(_bg, Rect2(bx - 1.0, _y0, 1.0, fh), Color(INK, 0.6))
	var tk := BP.Ticks.new()
	tk.count = int(fh / 12.0)
	tk.major = 5
	tk.color = Color(BP.PAPER, 0.45)
	tk.from_top = true
	tk.rotation = PI * 0.5
	tk.position = Vector2(bx + 8.0, _y0)
	tk.size = Vector2(fh, 7)
	_bg.add_child(tk)

	# The one giant element: the skill's key word (an Encore: the chain's numeral) set up the band's
	# edge, reading upward, two-tone where it crosses it, cut off by the bottom bar.
	var paper_r := Rect2(0, _y0, bx, fh)
	var band_r := Rect2(bx, _y0, w - bx, fh)
	if chain > 0:
		# An Encore step: the chain's numeral, upright and huge across the band's foot, signal on
		# the paper and paper on the band (the band's print is signal too), an ink ghost behind.
		var num := "×%d" % (chain + 1)
		var nfs := int(minf(fh * 0.42, 560.0))
		var nlen := Kit.font("compressed").get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x + 8.0
		var norg := Vector2(bx - nlen * 0.55, _y1 - nfs * 1.08)
		var nblock := Vector2(nlen, nfs * 1.3)
		_ghost = _turned(num, nfs, norg + Vector2(6, 6), nblock, [[Rect2(0, _y0, w, fh), Color(INK, 0.85)]], 0.0)
		_words = _turned(num, nfs, norg, nblock, [[paper_r, SIG], [band_r, BP.PAPER]], 0.0)
	else:
		var key := _key_word(skill_name)
		var fs := BP.fit(key, fh * 0.98, 460, 120)
		var cap := BP.caps(fs)
		var len_px := Kit.font("compressed").get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
		var block := Vector2(len_px, fs * 1.3)
		# Turned -90 degrees about its top-left, the block runs up from `org` and spreads right of
		# it; the caps' band straddles the ink band's edge.
		var org := Vector2(bx - (cap.x + cap.y) * 0.5, _y1 + 6.0)
		_ghost = _turned(key, fs, org + Vector2(5, 5), block, [[Rect2(0, _y0, w, fh), Color(SIG, 0.9)]])
		_words = _turned(key, fs, org, block, [[paper_r, INK], [band_r, BP.PAPER]])
	_mono = BP.t("%s  ·  %s" % [skill_name.to_upper(), str(Kit.FACTION_NAMES.get(str(_hero_def(hero).get("faction", "")), "")).to_upper()], 12, BP.PAPER, "mono_bold")
	_mono.position = Vector2(bx + 20.0, _y0 + 16.0)
	_bg.add_child(_mono)

	_crown_at = AtlasTexture.new()
	_crown_at.atlas = CROWN
	_crown_at.region = Rect2(0, 0, 512, 512)
	_crown = TextureRect.new()
	_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crown.texture = _crown_at
	_crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crown.stretch_mode = TextureRect.STRETCH_SCALE
	_crown.size = Vector2(CROWN_PX, CROWN_PX)
	_crown.position = _P - _crown.size * 0.5
	_crown.flip_h = _dir < 0
	_crown.visible = false
	_bg.add_child(_crown)


## An Encore step: the heroine who passed the Encore stays on the sheet as an ink print of her face,
## pasted in the paper's top corner above the new caster (shadows only, turned a little), captioned in mono. It flips to paper
## with the rest on the impact frame.
func _build_partner(partner: String, skin: String) -> void:
	var bx := floorf(_vs.x * BAND_X)
	var fh := _y1 - _y0
	_partner = BP.halftone(partner, skin, {"crop": "face", "cell": 4.5, "ink": Color(INK, 0.6), "light_dots": false})
	_partner.size = Vector2(bx * 0.5, fh * 0.2)
	_partner.position = Vector2(16.0, _y0 + 40.0)
	_partner.pivot_offset = _partner.size * 0.5
	_partner.rotation = -0.04
	_bg.add_child(_partner)
	_bg.move_child(_partner, 2)
	var nm := str(_hero_def(partner).get("name", partner)).to_upper()
	_partner_cap = BP.t("ENCORE FROM  ·  %s" % nm, 12, Color(INK, 0.75), "mono_bold")
	_partner_cap.position = Vector2(18.0, _y0 + 16.0)
	_bg.add_child(_partner_cap)


func _turned(text: String, fs: int, org: Vector2, block: Vector2, regions: Array, rot: float = -PI * 0.5) -> Array[RichTextLabel]:
	var out: Array[RichTextLabel] = []
	for r: Array in regions:
		var rr: Rect2 = r[0]
		var clip := Control.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.position = rr.position
		clip.size = rr.size
		_bg.add_child(clip)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = false
		rt.text = text
		rt.scroll_active = false
		rt.autowrap_mode = TextServer.AUTOWRAP_OFF
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rt.add_theme_font_override("normal_font", Kit.font("compressed"))
		rt.add_theme_font_size_override("normal_font_size", fs)
		rt.add_theme_color_override("default_color", r[1])
		rt.size = block
		rt.rotation = rot
		rt.position = org - rr.position
		rt.set_meta("base", rt.position)
		rt.set_meta("ink", r[1])
		clip.add_child(rt)
		out.append(rt)
	return out


## The skill's key word: its last word of four or more letters (never OF, ME or X).
static func _key_word(skill_name: String) -> String:
	var words := skill_name.to_upper().split(" ", false)
	for i in range(words.size() - 1, -1, -1):
		if words[i].length() >= 4:
			return words[i]
	return words[words.size() - 1] if not words.is_empty() else "ULTIMATE"


## Where her look splits into two inks on the impact frame: the median luminance of her painting
## from the face to the hips, so pale skin and dark latex both print about half and half.
static func _cut_point(hero: String, skin: String) -> float:
	var key := hero + "@" + skin
	if _cuts.has(key):
		return float(_cuts[key])
	# Baked offline (tools/art_cuts.py): reading the painting back from the GPU hitches on a phone.
	if _baked.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/heroes/cuts.json")) 			if FileAccess.file_exists("res://assets/art/heroes/cuts.json") else null
		_baked = d if d is Dictionary else {"": 0.45}
	var art := HeroArt._built_art(hero, skin)
	var bk := RigData.file_base(hero, art).trim_prefix("res://assets/art/heroes/")
	if _baked.has(bk):
		_cuts[key] = float(_baked[bk])
		return float(_cuts[key])
	var cut := 0.45
	var tex := HeroArt.texture(hero, skin)
	var img: Image = tex.get_image() if tex else null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var face := HeroArt.face_rect(hero, skin)
		var top := int(maxf(face.position.y, 0.0))
		var bot := int(minf(face.end.y + face.size.y * 4.5, float(img.get_height() - 1)))
		var ls: Array[float] = []
		var y := top
		while y < bot:
			var x := 0
			while x < img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.6:
					ls.append(c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
				x += 12
			y += 12
		if ls.size() > 40:
			ls.sort()
			cut = clampf(ls[ls.size() / 2], 0.25, 0.7)
	_cuts[key] = cut
	return cut


# ------------------------------------------------------------------ her

func _build_her(hero: String, skin: String) -> void:
	_her_layer = CanvasLayer.new()
	_her_layer.layer = 6
	add_child(_her_layer)
	_sp = HeroArt.make_sprite(hero, skin)
	_her_layer.add_child(_sp)
	_sp.set("idle_gestures", false)
	DeviceTier.light(_sp)
	_sp.scale = Vector2.ONE / HeroSprite.BASE_SCALE
	_sp.call("set_facing", _dir)
	var rp: Variant = _sp.get("rig")
	_rig = rp as RigPlayer if rp is RigPlayer else null
	var fc := Vector2(0, -1500)
	var fr := Vector2(70, 60)
	var chest := Vector2.INF
	var hips := Vector2.INF
	if _rig and _rig.rig:
		var rd := _rig.rig
		var fe := rd.face_ellipse()
		if fe != Vector4.ZERO:
			fc = Vector2(fe.x, fe.y)
			fr = Vector2(fe.z, fe.w)
		for b: String in ["chest", "hips"]:
			var i := rd.bone(b)
			if i >= 0 and i < rd.setup_world.size():
				if b == "chest":
					chest = rd.setup_world[i]
				else:
					hips = rd.setup_world[i]
		_rig.manual = true
		if tier != "still" and not _rig.play("ult_cutin", 1):
			_rig.play("ultimate", 1)
	var fh := fr.y * 2.0
	if chest == Vector2.INF:
		chest = fc + Vector2(0, 1.9 * fh)
	if hips == Vector2.INF:
		hips = fc + Vector2(0, 4.2 * fh)
	var w := _vs.x
	var frame_h := _y1 - _y0
	# LOOK: the cowboy shot (crown to upper thigh, face in the top quarter); never past about two
	# device px per texel.
	var top := fc.y - fr.y - 1.3 * fh
	var bottom := hips.y + 0.35 * (hips.y - chest.y)
	# Her shoulders and hips (about five face widths) keep left of the band, so the poster reads.
	var s_look := minf(minf(1.22, 0.8 * frame_h / maxf(bottom - top, 1.0)), w * BAND_X * 0.95 / maxf(fr.x * 2.0 * 5.0, 1.0))
	_f_look = {"pt": Vector2((fc.x + chest.x) * 0.5, (top + bottom) * 0.5), "at": Vector2(w * 0.36, _y0 + frame_h * 0.52), "s": s_look, "roll": 0.0}
	# OPEN: on her waist and hips, closer, turned -8 degrees.
	_f_open = {"pt": hips, "at": Vector2(w * 0.4, _y0 + frame_h * 0.5), "s": s_look * 2.1, "roll": deg_to_rad(-8.0)}
	# STRIKE: her whole figure (knees up if it won't fit), her blow's point placed on P.
	var ftop := fc.y - fr.y * 2.6
	var fbot := 0.0
	var s_strike := 0.95 * frame_h / maxf(fbot - ftop, 1.0)
	if s_strike < s_look * 0.55:
		fbot = hips.y * 0.45
		s_strike = 0.95 * frame_h / maxf(fbot - ftop, 1.0)
	s_strike = minf(s_strike, s_look * 0.8)
	var pt := Vector2(chest.x, (ftop + fbot) * 0.5)
	var roll := deg_to_rad(5.0) * _dir
	var blow := chest + Vector2(0.25 * absf(fc.y), 0.0)
	var at := _P - (Vector2(blow.x * _dir, blow.y) - Vector2(pt.x * _dir, pt.y)).rotated(roll) * s_strike
	# Kept to the middle of the frame: where the foe stands far off, the crown (drawn at P) is what
	# carries across the cut, not her blow.
	at.x = clampf(at.x, w * 0.32, w * 0.58)
	at.y = clampf(at.y, _y0 + frame_h * 0.42, _y1 - frame_h * 0.4)
	_f_strike = {"pt": pt, "at": at, "s": s_strike, "roll": roll}


# ------------------------------------------------------------------ the bars

func _build_bars(hero: String, skin: String) -> void:
	_fg_layer = CanvasLayer.new()
	_fg_layer.layer = 7
	add_child(_fg_layer)
	var w := _vs.x
	_bar_top = Control.new()
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.size = Vector2(w, _top_h)
	_fg_layer.add_child(_bar_top)
	BP.rect(_bar_top, Rect2(Vector2.ZERO, _bar_top.size), BP.BAND)
	BP.rect(_bar_top, Rect2(0, _top_h - 2.0, w, 1), Color(BP.PAPER, 0.7))
	var nm := str(_hero_def(hero).get("name", hero)).to_upper()
	var look_name := ""
	if skin != "":
		look_name = str(SkinData.get_def(skin).get("name", "")).to_upper()
	var slate := BP.t("ULTIMATE  ·  %s%s" % [nm, ("  ·  " + look_name) if look_name != "" else ""], 12, BP.PAPER, "mono_bold")
	slate.position = Vector2(28, _top_h - 34.0)
	_bar_top.add_child(slate)
	var tk := BP.Ticks.new()
	tk.count = int(w / 12.0)
	tk.major = 5
	tk.color = Color(BP.PAPER, 0.4)
	tk.from_top = false
	tk.position = Vector2(0, _top_h - 10.0)
	tk.size = Vector2(w, 7)
	_bar_top.add_child(tk)
	_bar_bot = Control.new()
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bot.size = Vector2(w, _bot_h)
	_bar_bot.position = Vector2(0, _vs.y - _bot_h)
	_fg_layer.add_child(_bar_bot)
	BP.rect(_bar_bot, Rect2(Vector2.ZERO, _bar_bot.size), BP.BAND)
	BP.rect(_bar_bot, Rect2(0, 1, w, 1), Color(BP.PAPER, 0.7))


# ------------------------------------------------------------------ the clock

func _apply() -> void:
	var t := _t
	var still := tier == "still"
	var shown := t >= T_CUT and t < _contact_t
	_bg_layer.visible = shown
	_her_layer.visible = shown
	# The bars: slam in (expo-out, 0.08 s), hold through the landing, slide off.
	var kin := 1.0 if tier == "repeat" else _expo_out(clampf(t / T_CUT, 0.0, 1.0))
	var kout := clampf((t - T_BARS_OUT) / (T_END - T_BARS_OUT), 0.0, 1.0)
	kout = kout * kout * kout
	_bar_top.position.y = -_top_h * (1.0 - kin) - _top_h * kout
	_bar_bot.position.y = _vs.y - _bot_h + _bot_h * (1.0 - kin) + _bot_h * kout
	if still:
		_apply_still(t)
	elif shown:
		_apply_camera(t)
		_apply_poster(t)
		_apply_light(t)
	_beats(t)


## Live Light (Pro phones): a stage light sweeps across her as she rises, drifts through the pose,
## then whips round to her upper left on the coil, and lets go to the phone's tilt on the strike.
func _apply_light(t: float) -> void:
	if _sp == null or not bool(_sp.get("live")):
		return
	var sw := Vector2.ZERO
	if t < T_SNAP:
		sw = Vector2(-0.4, -0.1).lerp(Vector2(0.35, 0.0), _sine(clampf((t - T_CUT) / (T_SNAP - T_CUT), 0.0, 1.0)))
	elif t < T_COIL:
		sw = Vector2(0.35, 0.0).lerp(Vector2(0.45, 0.05), clampf((t - T_SNAP) / (T_COIL - T_SNAP), 0.0, 1.0))
	elif t < T_STRIKE:
		sw = Vector2(0.45, 0.05).lerp(Vector2(-0.45, -0.25), _sine(clampf((t - T_COIL) / (T_STRIKE - T_COIL), 0.0, 1.0)))
	elif t < T_IMPACT:
		sw = Vector2(-0.45, -0.25).lerp(Vector2.ZERO, clampf((t - T_STRIKE) / (T_IMPACT - T_STRIKE), 0.0, 1.0))
	_sp.call("light_swing", sw)


func _apply_still(t: float) -> void:
	var a := clampf((t - T_CUT) / 0.12, 0.0, 1.0) * clampf((_contact_t - t) / 0.2, 0.0, 1.0)
	_bg.modulate.a = a
	_sp.modulate.a = a
	_set_cam(_f_look)
	_crown.visible = false
	BP.pose(_ghost, Vector2.ZERO, 1.0, 0.0)


func _apply_camera(t: float) -> void:
	var f: Dictionary
	if t < T_SNAP:
		# It lingers on her hips, glides up her and lands on the snap.
		f = _mix(_f_open, _f_look, _sine((t - T_CUT) / (T_SNAP - T_CUT)))
	elif t < T_COIL:
		f = _f_look
	elif t < T_STRIKE:
		f = _f_look.duplicate()
		f["s"] = float(f.s) * (1.0 + 0.04 * _sine((t - T_COIL) / (T_STRIKE - T_COIL)))
	elif t < T_IMPACT:
		var look := _f_look.duplicate()
		look["s"] = float(look.s) * 1.04
		f = _mix(look, _f_strike, 1.0 - pow(1.0 - (t - T_STRIKE) / (T_IMPACT - T_STRIKE), 3.0))
	else:
		# The impact's kick: along the lunge and a hair closer, held through the hit-stop.
		f = _f_strike.duplicate()
		f["at"] = (f.at as Vector2) + Vector2(14.0 * _dir, 6.0)
		f["s"] = float(f.s) * 1.03
	_set_cam(f)


func _set_cam(f: Dictionary) -> void:
	var pt: Vector2 = f.pt
	var ptl := Vector2(pt.x * _dir, pt.y)
	var s := float(f.s)
	_her_layer.transform = Transform2D(float(f.roll), Vector2(s, s), 0.0, f.at as Vector2) * Transform2D(0.0, -ptl)
	# Her bangs catch the rush up and the lunge.
	if _rig:
		_rig.wind = 1.0 + (4.0 if _t < T_SNAP and _t >= T_CUT else 0.0) + (7.0 if _t >= T_STRIKE else 0.0)


func _apply_poster(t: float) -> void:
	var flip := t >= T_IMPACT and t < T_COLOUR
	_flip.visible = flip
	_band_fill.color = SIG if flip else BP.BAND
	(_print.material as ShaderMaterial).set_shader_parameter("ink", BP.PAPER if flip else BP.RED_INK)
	_mono.visible = not flip
	if _partner:
		(_partner.material as ShaderMaterial).set_shader_parameter("ink", Color(BP.PAPER, 0.6) if flip else Color(INK, 0.6))
		_partner_cap.visible = not flip
	# Her red print: out of register until the snap, drifts against her through the pose, jumps
	# on the impact and settles.
	var reg := Vector2(14, 14) if t < T_GHOST else Vector2.ZERO
	if t >= T_GHOST and t < T_COIL:
		reg = Vector2(-8.0 * _sine((t - T_GHOST) / (T_COIL - T_GHOST)), 0)
	elif t >= T_COLOUR and t < 1.2:
		reg = Vector2(6, 6)
	_print.position = _print_base + reg
	# The key word: slams in on the snap (106% -> 100%), its signal ghost on the second clack.
	var wa := 1.0 if t >= T_SNAP else 0.0
	var ws := 1.0 + 0.06 * clampf(1.0 - (t - T_SNAP) / 0.06, 0.0, 1.0)
	BP.pose(_words, Vector2.ZERO, ws, wa)
	for rt in _words:
		rt.add_theme_color_override("default_color", BP.PAPER if flip else rt.get_meta("ink") as Color)
	var goff := Vector2(5, 5) if t < T_COLOUR or t >= 1.2 else Vector2(11, 11)
	BP.pose(_ghost, goff - Vector2(5, 5), ws, 0.0 if t < T_GHOST or flip else 1.0)
	# The ink crown where her blow lands: paper on the impact frame, signal in the hit-stop.
	_crown.visible = t >= T_IMPACT
	if _crown.visible:
		var fi := clampi(int((t - T_IMPACT) / (T_CONTACT - T_IMPACT) * 6.0), 0, 5)
		_crown_at.region = Rect2((fi % 4) * 512, (fi / 4) * 512, 512, 512)
		_crown.modulate = BP.PAPER if flip else SIG
	# Her: a hard two-tone on the impact frame.
	var two := flip
	if _sp and bool(_sp.get_meta("two", false)) != two:
		_sp.set_meta("two", two)
		_sp.call("two_tone", two, INK, SIG, _cut)


func _beats(t: float) -> void:
	_once("in", 0.0, t, func() -> void:
		_sfx("ult_in")
		_haptic(12, 0.45))
	if tier == "still":
		_once("contact", _contact_t, t, _contact)
		return
	_once("snap", T_SNAP, t, func() -> void:
		_sfx("clack", 0.62)
		_haptic(8, 0.3))
	_once("ghost", T_GHOST, t, func() -> void: _sfx("clack", 0.55))
	_once("rise", T_RISE_SND, t, func() -> void: _sfx("ult_rise", rate))
	_once("impact", T_IMPACT, t, func() -> void:
		_sfx("ult_crack")
		_haptic(30, 0.8)
		impact.emit()
		mouse_filter = Control.MOUSE_FILTER_IGNORE)
	_once("contact", _contact_t, t, _contact)


func _contact() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _sp and bool(_sp.get_meta("two", false)):
		_sp.call("two_tone", false)
	if not _done_contact:
		_done_contact = true
		contact.emit()


func _once(key: String, at: float, t: float, f: Callable) -> void:
	if t >= at and not _fired.has(key):
		_fired[key] = true
		f.call()


static func _mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var s := exp(lerpf(log(float(a.s)), log(float(b.s)), k))
	return {"pt": (a.pt as Vector2).lerp(b.pt as Vector2, k), "at": (a.at as Vector2).lerp(b.at as Vector2, k), "s": s, "roll": lerpf(float(a.roll), float(b.roll), k)}


static func _expo_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)


static func _sine(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(x, 0.0, 1.0))


# The autoloads by name, so the clock and its beats load (and test) without the game running.
static func _hero_def(id: String) -> Dictionary:
	var g := Kit.autoload("Game")
	return g.call("hero_def", id) if g else {}


static func _sfx(sound: String, pitch: float = -1.0) -> void:
	var ui := Kit.autoload("UI")
	if ui:
		ui.call("sfx", sound, pitch)


static func _haptic(ms: int, amplitude: float) -> void:
	var ui := Kit.autoload("UI")
	if ui:
		ui.call("haptic", ms, amplitude)
