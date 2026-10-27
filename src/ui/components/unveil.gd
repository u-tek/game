extends Control
## A new look's unveil (a skin bought: the Shop, the Gallery, her page), full screen in the dark
## (the studio: ink, one soft light behind her, like the battle's close-ups): the camera starts close
## on her face in the new look, travels down it (her chest, her hips) and pulls back to all of her;
## then the look's name lands huge behind her in paper, its line under it, and a HERS rubber stamp
## slams down in signal. A tap jumps to the end, the next closes it. Reduce motion shows
## the end at once.
##   UI.unveil(hero_id, skin_id)

signal closed

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")
const INK := SignalKit.INK
const PAPER := SignalKit.PAPER
const SIG := SignalKit.SIGNAL

## The camera's beats: hold on her face, then her chest, her hips, all of her (seconds, cumulative).
const T_FACE := 0.6
const T_CHEST := 1.55
const T_HIPS := 2.5
const T_ALL := 3.45
const T_NAME := 3.5
const T_STAMP := 3.95
const T_DONE := 4.4

var hero_id := ""
var skin_id := ""
var _t := 0.0
var _done := false
var _art: TextureRect
var _cams: Array[Vector3] = []
var _times: Array[float] = []
var _name: Control
var _lines: Control
var _stamp: Control
var _hint: Label
var _light: TextureRect
## The light's place on her (texture px).
var _light_at := Vector2.ZERO
var _fired := {}


func setup(hid: String, sid: String) -> void:
	hero_id = hid
	skin_id = sid
	name = "Unveil"
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _ready() -> void:
	var vs := get_viewport_rect().size
	var sd := SkinData.get_def(skin_id)
	var def := Game.hero_def(hero_id)
	var studio := ColorRect.new()
	studio.color = Kit.BAND
	studio.mouse_filter = MOUSE_FILTER_IGNORE
	studio.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(studio)
	# One soft light behind her (it follows the camera to her chest).
	var g := Gradient.new()
	g.set_color(0, Color(PAPER, 0.2))
	g.set_color(1, Color(PAPER, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	_light = TextureRect.new()
	_light.texture = gt
	_light.mouse_filter = MOUSE_FILTER_IGNORE
	_light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_light.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_light)
	# The look's name, huge and turned, behind her (she is a cut-out on the paper).
	var nm := str(sd.get("name", skin_id)).to_upper()
	var f := Kit.font("compressed")
	var fs := 240
	while fs > 120 and f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > vs.y * 0.82:
		fs -= 6
	var big := Kit.label(nm, fs, Color(PAPER, 0.9), "compressed")
	big.rotation = PI * 0.5
	big.position = Vector2(fs * 0.98 + 10.0, vs.y * 0.08)
	_name = Control.new()
	_name.mouse_filter = MOUSE_FILTER_IGNORE
	_name.add_child(big)
	add_child(_name)
	# Her, in the new look.
	var tex := HeroArt.texture(hero_id, skin_id)
	_art = TextureRect.new()
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	_art.texture = tex
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_art)
	_plan_camera(vs)
	# Its line: the kicker, the name, her signature (bottom left), and TAP TO CONTINUE.
	_lines = Control.new()
	_lines.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_lines)
	var line := str(SkinData.lines().get(str(sd.get("line", "")), ""))
	var kick := PK.t(("WARDROBE  ·  NEW LOOK" + ("  ·  " + line.to_upper() if line != "" else "")), 12, SIG, "mono_bold")
	kick.position = Vector2(28, vs.y - UI.safe_bottom() - 186)
	_lines.add_child(kick)
	var sk := PK.t(nm, 64, PAPER, "compressed")
	Kit.fit_label(sk, vs.x - 56.0, 64, 34)
	sk.position = Vector2(26, vs.y - UI.safe_bottom() - 170)
	_lines.add_child(sk)
	var sig := PK.t(str(def.get("name", hero_id)), 40, PAPER, "serif_italic")
	sig.position = Vector2(28, vs.y - UI.safe_bottom() - 96)
	_lines.add_child(sig)
	_hint = Kit.label("TAP TO CONTINUE", 12, Color(PAPER, 0.7), "mono_bold")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.size = Vector2(300, 20)
	_hint.position = Vector2(vs.x - 324, vs.y - UI.safe_bottom() - 40)
	_lines.add_child(_hint)
	# The accent: HERS, stamped once she is all there.
	var st := PrintCard.Stamp.new()
	st.text = "HERS"
	st.sub = "%s  ·  WORN EVERYWHERE" % str(def.get("name", hero_id)).to_upper()
	st.color = SIG
	st.seed_v = 77
	st.size = Vector2(250, 92)
	st.pivot_offset = st.size * 0.5
	st.position = Vector2(vs.x - 278, vs.y - UI.safe_bottom() - 200)
	st.rotation = -0.16
	add_child(st)
	_stamp = st
	PK.grain(self, 0.07)
	if not Kit.motion_ok():
		_t = T_DONE
	UI.sfx("rustle")
	UI.haptic(12)
	_apply()


## The camera's framings (window centre x, y in texture px, scale): her face, chest, hips, all of her.
func _plan_camera(vs: Vector2) -> void:
	var tex := _art.texture
	var ts := Vector2(tex.get_size()) if tex else Vector2(1024, 2048)
	var pts := HeroArt.body_points(hero_id, skin_id)
	var face: Rect2 = pts.get("face", Rect2(ts.x * 0.4, ts.y * 0.28, ts.x * 0.15, ts.x * 0.12))
	var fc := face.get_center()
	var chest: Vector2 = pts.get("chest", fc + Vector2(0, face.size.y * 2.4))
	var hips: Vector2 = pts.get("hips", fc + Vector2(0, face.size.y * 4.6))
	var feet: Vector2 = pts.get("feet", Vector2(ts.x * 0.5, ts.y * 0.97))
	var s0 := vs.x / maxf(face.size.x * 2.0, 40.0)
	var top := fc.y - face.size.y * 1.7
	# All of her: head under the top inset, feet clear of the lines at the foot, a little right of
	# the middle (the name stands on the left).
	var head_y := UI.safe_top() + 40.0
	var feet_y := vs.y - UI.safe_bottom() - 200.0
	var s3 := minf((feet_y - head_y) / maxf(feet.y - top, 100.0), vs.x * 1.1 / ts.x)
	var c3 := Vector2(chest.x - vs.x * 0.07 / s3, feet.y - (feet_y - vs.y * 0.5) / s3)
	_cams = [Vector3(fc.x, fc.y + face.size.y * 0.1, s0), Vector3(fc.x, fc.y + face.size.y * 0.1, s0 * 1.05),
		Vector3(chest.x, chest.y, s0 * 0.66), Vector3(hips.x, hips.y + face.size.y * 0.5, s0 * 0.55),
		Vector3(c3.x, c3.y, s3)]
	_light_at = chest
	_times = [0.0, T_FACE, T_CHEST, T_HIPS, T_ALL]


func _process(delta: float) -> void:
	if _t >= T_DONE:
		return
	_t = minf(_t + delta, T_DONE)
	_apply()


func _apply() -> void:
	if _art == null or _cams.is_empty():
		return
	var cam := _cams[_cams.size() - 1]
	for i in range(_times.size() - 1):
		if _t < _times[i + 1]:
			var k := Fx.smooth(Fx.k01(_t, _times[i], _times[i + 1]))
			cam = Fx.zoom_pan(_cams[i], _cams[i + 1], k)
			break
	var vs := size if size.x > 0.0 else get_viewport_rect().size
	var ts := _art.texture.get_size() if _art.texture else Vector2(1024, 2048)
	# A slow breath once she is all there.
	if _t >= T_ALL:
		cam.z *= 1.0 + 0.012 * Fx.smooth(Fx.k01(_t, T_ALL, T_DONE))
	_art.size = ts * cam.z
	_art.position = vs * 0.5 - Vector2(cam.x, cam.y) * cam.z
	_art.modulate.a = Fx.k01(_t, 0.0, 0.25)
	var lr := maxf(vs.x * 1.3, ts.x * cam.z * 0.9)
	_light.size = Vector2(lr, lr * 1.25)
	_light.position = _art.position + _light_at * cam.z - _light.size * 0.5
	# The name lands behind her, the lines slide on, the stamp slams.
	var kn := Fx.k01(_t, T_NAME, T_NAME + 0.3)
	_name.modulate.a = Fx.k01(_t, T_NAME, T_NAME + 0.08)
	_name.position = Vector2(0, -vs.y * 0.12 * (1.0 - Fx.out_cubic(kn)))
	var kl := Fx.out_cubic(Fx.k01(_t, T_NAME + 0.1, T_NAME + 0.45))
	_lines.modulate.a = kl
	_lines.position = Vector2(-30.0 * (1.0 - kl), 0)
	var ks := Fx.k01(_t, T_STAMP, T_STAMP + 0.28)
	_stamp.modulate.a = Fx.k01(_t, T_STAMP, T_STAMP + 0.05)
	var sc := lerpf(2.6, 1.0, Fx.out_back(ks, 1.3))
	_stamp.scale = Vector2(sc, sc)
	_hint.modulate.a = Fx.k01(_t, T_DONE - 0.2, T_DONE)
	_beats()


## The sounds and haptics of the beats, once each.
func _beats() -> void:
	if _t >= T_NAME and not _fired.has("name"):
		_fired["name"] = true
		if _t < T_DONE:
			UI.sfx("slam")
			UI.haptic(30)
	if _t >= T_STAMP + 0.1 and not _fired.has("stamp"):
		_fired["stamp"] = true
		if _t < T_DONE:
			UI.sfx("stamp")
			UI.haptic(45)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _t < T_DONE:
		_t = T_DONE
		_fired["name"] = true
		_fired["stamp"] = true
		_apply()
		return
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())
