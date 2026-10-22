extends Control
## Screen "calling": the onboarding's intake form (the owner, 2026-10-22: "fleshed out, but in a
## subtle way"). Shown once, on the first launch, after the boot print run; replayable from
## Settings. A single printed poster, restrained: the dark band carries the lobby heroine's red print
## and CALLED. down it; beside it the form: its number (the player's ID, the same one printed later
## on their profile card), today's date and the local time, one line in the serif, 01 NAME (typed,
## optional) and 02 SIGNATURE (signed with a finger on a dotted line, an X at its start). Fine print
## that agrees to nothing. ANSWER stamps the form ACCEPTED with the date; then the heroine, in full
## colour on ink, greets the player by name with a line for the hour it really is (late night,
## morning, afternoon, evening), and the Lobby prints in. The signature is kept (Game.signature) and
## the game signs with it afterwards: the profile card, reward receipts, the oath on the front, the
## print album.
## params: answer (debug shots: fill and answer the form).

const PK := preload("res://src/ui/v4/hero_poster_kit.gd")
const PPK := preload("res://src/ui/v4/poster_kit.gd")
const Poster := preload("res://src/ui/v4/survey/poster.gd")
const Signature := preload("res://src/ui/components/signature.gd")
const HomeScreen := preload("res://src/ui/screens/home_screen.gd")

const INK := Color("101113")
const PAPER := Color("e9e8e2")
const SIG := Color("ff4b1f")
const BAND_C := Color("141517")
const BAND := 132.0

var _hero := ""
var _poster: Control
var _name: LineEdit
var _pad: SignPad
var _done := false


func setup(params: Dictionary) -> void:
	UI.set_chrome(false, false)
	_hero = HomeScreen.lobby_hero()
	_build()
	# Screenshots (debug): answer = true fills the form with a made-up name and signature and answers.
	if OS.is_debug_build() and bool(params.get("answer", false)):
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			_name.text = "Aria"
			_finish("Aria", GameModel._demo_signature()))


func _exit_tree() -> void:
	UI.set_chrome(true, true)


func _build() -> void:
	PK.matte(self)
	var vs := get_viewport_rect().size
	var top := UI.safe_top() + 24.0
	var bot := vs.y - UI.safe_bottom() - 24.0
	var pr := Rect2(18, top, vs.x - 36, bot - top)
	_poster = PK.poster(self, pr)
	var pw := pr.size.x
	var ph := pr.size.y
	var p := _poster
	# The band: her red print at the foot, CALLED. down it, micro type.
	PK.rect(p, Rect2(0, 0, BAND, ph), BAND_C)
	if _hero != "":
		var ht := PK.halftone_print(_hero, Kit.hero_look(_hero), Vector2(BAND, ph * 0.5), 6.0)
		ht.position = Vector2(0, ph * 0.5)
		p.add_child(ht)
	Poster.vlabel(p, "©2026 HH · INTAKE · PLEASE COMPLETE IN INK", Vector2(24, 26), 10, Color(PAPER, 0.8))
	var fs := 230
	while fs > 80 and PK.text_w("CALLED.", fs) * 1.3 > ph * 0.62:
		fs -= 6
	var gx := BAND + roundf(fs * 0.48)
	PK.giant(p, "CALLED[color=#%s].[/color]" % SIG.to_html(false), fs, Vector2(gx, 30), Vector2(ph, fs * 1.3),
		[[Rect2(0, 0, BAND, ph), PAPER], [Rect2(BAND, 0, gx - BAND + 6.0, ph), INK]], 0, "compressed", true)
	# The form, right of the type.
	var x0 := gx + 24.0
	var tw := pw - x0 - 22.0
	var now := Time.get_datetime_dict_from_system()
	PK.at(p, PK.t("INTAKE FORM  ·  Nº %s" % ProfileScreen.player_id(), 11, INK, "mono_bold"), Vector2(x0, 22))
	var dl := PK.t("%02d.%02d.%02d  ·  %02d:%02d" % [int(now.day), int(now.month), int(now.year) % 100, int(now.hour), int(now.minute)],
		11, Color(INK, 0.7), "mono")
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl.size = Vector2(tw, 14)
	PK.at(p, dl, Vector2(x0, 40))
	PK.at(p, Kit.tick_rule(tw, Color(INK, 0.55), {"lead": SIG}), Vector2(x0, 62))
	var line := PK.t("Somewhere between Heaven and Hell, someone has been calling your name.", 26, INK, "serif_italic")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size = Vector2(tw, 140)
	line.custom_minimum_size.x = tw
	PK.at(p, line, Vector2(x0, 84))
	var y := 250.0
	PK.at(p, PK.t("01", 22, INK, "compressed"), Vector2(x0, y - 4))
	PK.at(p, PK.t("NAME", 11, INK, "mono_bold"), Vector2(x0 + 34, y + 4))
	_name = LineEdit.new()
	_name.name = "Name"
	_name.placeholder_text = "SUMMONER"
	_name.max_length = 16
	_name.flat = true
	_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name.add_theme_font_override("font", Kit.font("mono_bold"))
	_name.add_theme_font_size_override("font_size", 28)
	_name.add_theme_color_override("font_color", INK)
	_name.add_theme_color_override("font_placeholder_color", Color(INK, 0.28))
	_name.add_theme_color_override("caret_color", SIG)
	for st: String in ["normal", "focus", "read_only"]:
		_name.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_name.position = Vector2(x0, y + 26)
	_name.size = Vector2(tw, 52)
	p.add_child(_name)
	PK.rule(p, Vector2(x0, y + 80), Vector2(tw, 1.5), INK)
	y += 120.0
	PK.at(p, PK.t("02", 22, INK, "compressed"), Vector2(x0, y - 4))
	PK.at(p, PK.t("SIGNATURE", 11, INK, "mono_bold"), Vector2(x0, y + 4) + Vector2(34, 0))
	_pad = SignPad.new()
	_pad.name = "SignPad"
	_pad.position = Vector2(x0 - 6, y + 26)
	_pad.size = Vector2(tw + 12, minf(230.0, ph - y - 330.0))
	p.add_child(_pad)
	var clear := PK.t("CLEAR", 10, Color(INK, 0.55), "mono_bold")
	clear.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clear.size = Vector2(tw, 14)
	PK.at(p, clear, Vector2(x0, y + 30 + _pad.size.y))
	var ch := Control.new()
	ch.mouse_filter = MOUSE_FILTER_PASS
	ch.position = Vector2(x0 + tw - 100, y + 14 + _pad.size.y)
	ch.size = Vector2(110, 50)
	p.add_child(ch)
	Kit.make_tappable(ch, func() -> void: _pad.clear())
	y += 70.0 + _pad.size.y
	var fine := PK.t("BY SIGNING YOU AGREE TO NOTHING.\nTHE CALLING IS ITS OWN REWARD.", 9, Color(INK, 0.55), "mono")
	PK.at(p, fine, Vector2(x0, y))
	Poster.pass_on(p, {"width": minf(tw + 10.0, 380.0), "kicker": "INTAKE  //  RETURN BY HAND", "title": "ANSWER",
		"sub": "THE CALL", "action": "ANSWER  >>>", "icon": "check"}, Vector2(pw - minf(tw + 10.0, 380.0) - 18.0, ph - 172.0),
		_answer, "Answer", "Answer")
	# A quiet way out (the form is never required).
	var skip := PK.t("SKIP", 11, Color(INK, 0.5), "mono_bold")
	skip.position = Vector2(vs.x - 70, top - 22)
	add_child(skip)
	var sh := Control.new()
	sh.name = "Skip"
	sh.mouse_filter = MOUSE_FILTER_PASS
	sh.position = Vector2(vs.x - 96, top - 40)
	sh.size = Vector2(96, 44)
	add_child(sh)
	Kit.make_tappable(sh, func() -> void: _finish("", []))
	add_child(SignalKit.grain(0.05, true))


func _answer() -> void:
	if _done:
		return
	_name.release_focus()
	_finish(_name.text, _pad.strokes())


func _finish(player_name: String, strokes: Array) -> void:
	if _done:
		return
	_done = true
	Game.complete_intake(player_name, strokes)
	UI.haptic(30)
	Kit.sfx("tap")
	# The signature as filed: the pad's ink (or the given strokes) set in ink on the dotted line.
	if not strokes.is_empty() and _pad.strokes().is_empty():
		var sg := Signature.new()
		sg.strokes = Game.signature()
		sg.position = _pad.position + Vector2(48, 6)
		sg.size = Vector2(_pad.size.x - 70, _pad.size.y * 0.66)
		_poster.add_child(sg)
		sg.write_on(0.5)
	# The form is stamped ACCEPTED, then her greeting.
	var now := Time.get_datetime_dict_from_system()
	Poster.rubber(_poster, "ACCEPTED %02d.%02d" % [int(now.day), int(now.month)], Vector2(_poster.size.x * 0.34, _poster.size.y * 0.42), SIG, 34, -0.14)
	get_tree().create_timer(0.8 if Kit.motion_ok() else 0.1).timeout.connect(_greet)


## Her line for the hour it is, with the player's name.
static func greeting(hour: int, who: String) -> String:
	if hour >= 23 or hour < 5:
		return "Up past midnight, %s? Good. The best summonings happen while the world sleeps." % who
	if hour < 12:
		return "Morning, %s. I hoped you'd answer before the bells." % who
	if hour < 18:
		return "There you are, %s. Half the day gone and you still came. I like that." % who
	return "Evening, %s. The lamps are lit. Let's see what you can do." % who


func _greet() -> void:
	if not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	var veil := Control.new()
	veil.name = "Greeting"
	veil.mouse_filter = MOUSE_FILTER_STOP
	# Over everything on the form (its pass draws raised).
	veil.z_index = 20
	veil.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(veil)
	var bg := ColorRect.new()
	bg.color = INK
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	veil.add_child(bg)
	if _hero != "":
		var ht := PK.halftone_print(_hero, Kit.hero_look(_hero), Vector2(vs.x, vs.y * 0.7), 8.0, Color(PK.PRINT, 0.3))
		ht.position = Vector2(0, vs.y * 0.08)
		veil.add_child(ht)
		var box := Control.new()
		box.clip_contents = true
		box.mouse_filter = MOUSE_FILTER_IGNORE
		box.size = vs
		veil.add_child(box)
		PPK.hero_fig(box, _hero, Kit.hero_look(_hero), Vector2(vs.x * 0.56, vs.y - UI.safe_bottom() + 40.0), vs.y * 0.82)
	var who := ProfileScreen.player_name_raw()
	var line := PK.t("“%s”" % greeting(int(Time.get_datetime_dict_from_system().hour), who), 30, PAPER, "serif_italic")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size = Vector2(vs.x * 0.62, 260)
	line.custom_minimum_size.x = vs.x * 0.62
	var lp := ColorRect.new()
	lp.color = Color(INK, 0.72)
	lp.mouse_filter = MOUSE_FILTER_IGNORE
	lp.position = Vector2(20, UI.safe_top() + 60)
	lp.size = Vector2(vs.x * 0.62 + 32, 250)
	veil.add_child(lp)
	PK.at(veil, line, Vector2(36, UI.safe_top() + 76))
	var sig := PK.t(str(Game.hero_def(_hero).get("name", "")), 44, SIG, "serif_italic")
	PK.at(veil, sig, Vector2(36, UI.safe_top() + 330))
	var tap := PK.t("TAP TO BEGIN", 11, Color(PAPER, 0.7), "mono_bold")
	tap.position = Vector2(36, vs.y - UI.safe_bottom() - 60)
	veil.add_child(tap)
	if Kit.motion_ok():
		veil.modulate.a = 0.0
		veil.create_tween().tween_property(veil, "modulate:a", 1.0, 0.35)
		line.visible_ratio = 0.0
		line.create_tween().tween_property(line, "visible_ratio", 1.0, 1.6).set_delay(0.3)
	var go := func() -> void:
		if is_inside_tree() and UI.current_name == "calling":
			UI.go("home")
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			go.call())
	get_tree().create_timer(9.0).timeout.connect(go)


## The signing pad: a dotted baseline with an X, "SIGN WITH YOUR FINGER" until the first stroke;
## strokes drawn as ink with a pen-nib width. strokes(): the strokes in 0..1000 (by the pad's width).
class SignPad:
	extends Control

	const INK := Color("101113")
	var _strokes: Array = []
	var _cur := PackedVector2Array()
	var _down := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP

	func clear() -> void:
		_strokes.clear()
		_cur = PackedVector2Array()
		queue_redraw()

	func strokes() -> Array:
		var out: Array = []
		var k := 1000.0 / maxf(size.x, 1.0)
		for s: Variant in _strokes:
			var a: Array = []
			for p: Vector2 in (s as PackedVector2Array):
				a.append(clampi(int(p.x * k), 0, 1000))
				a.append(clampi(int(p.y * k), 0, 1000))
			if a.size() >= 4:
				out.append(a)
		return out

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = true
				_cur = PackedVector2Array([mb.position])
			elif _down:
				_down = false
				if _cur.size() >= 2:
					_strokes.append(_cur)
				_cur = PackedVector2Array()
			accept_event()
			queue_redraw()
			return
		var mm := event as InputEventMouseMotion
		if mm and _down:
			var p := mm.position.clamp(Vector2.ZERO, size)
			if _cur.is_empty() or p.distance_to(_cur[_cur.size() - 1]) > 2.5:
				_cur.append(p)
			accept_event()
			queue_redraw()

	func _draw() -> void:
		var base := size.y * 0.72
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, base), Vector2(minf(x + 4.0, size.x), base), Color(INK, 0.5), 1.2)
			x += 9.0
		var f := Kit.font("compressed")
		draw_string(f, Vector2(4, base - 6), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(INK, 0.75))
		if _strokes.is_empty() and _cur.size() < 2:
			draw_string(Kit.font("mono_bold"), Vector2(46, base - 14), "SIGN WITH YOUR FINGER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.3))
		for s: Variant in _strokes + [_cur]:
			var pts := s as PackedVector2Array
			var n := pts.size()
			for i in n - 1:
				var t := float(i) / maxf(float(n - 1), 1.0)
				var w := 4.0 * (0.35 + 0.65 * sin(PI * t))
				draw_line(pts[i], pts[i + 1], INK, w, true)
				draw_circle(pts[i + 1], w * 0.5, INK, true, -1.0, true)
