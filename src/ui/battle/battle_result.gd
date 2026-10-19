extends Control
## Battle result overlay (style v4, the poster look: docs/dev/ui-style-v4.md section 0, built like
## the risograph prints of reference 8 / 15). The paper matte comes up over the field and a printed
## poster drops onto it, two-tone signal and ink on paper with halftone and still grain.
## show_victory(): a dark band down the left with the MVP's face as a red halftone print; VICTORY set
## huge in compressed type and turned on its side, paper where it crosses the band and signal on the
## paper over an ink plate printed out of register; the MVP in full colour, boxed by a hairline, in
## front of a misregistered riso print of herself; the report's title block (serial, stage, chapter,
## date); stars as printed pips; the MVP's line (damage, share as a tick bar, her signature); the
## rewards as a mono bracket table; vertical labels down the right-hand rule. Next Stage (Next
## Chapter, Next Floor) is the pass stuck over the poster's foot; Lobby is printed under it.
## show_defeat(): a dark band across the top with the MVP as a red and paper halftone out of register;
## DEFEAT turned on its side (paper on the band, ink on the paper) over a signal plate out of register;
## why it was lost, the power check as a bracket table and HOW TO WIN as numbered printed lines
## (level up, team, counter faction); Retry is the pass, Lobby printed under the poster.
## Buttons call on_action(name) with "home" | "next" | "retry" | "campaign" | "heroes" | "formation"
## | "level" (the team hero Guide.level_target() names). Early on, Guide marks the suggested button.

const StageInfo := preload("res://src/ui/battle/stage_info.gd")
const BP := preload("res://src/ui/v4/battle/battle_print.gd")
const PK := preload("res://src/ui/v4/poster_kit.gd")
const HPK := preload("res://src/ui/v4/hero_poster_kit.gd")

const BAND_W := 150.0
## The data section at the foot of the victory poster.
const DATA_H := 560.0
## The right-hand rule, this far from the poster's right edge.
const RULE := 48.0
## Under the poster: the printed Lobby label (the pass hangs over the poster's foot into it).
const FOOT := 110.0
const NAMES := {"gold": "GOLD", "hero_exp": "HERO EXP", "gems": "GEMS", "scrolls": "SCROLLS", "dust": "DUST"}

var on_action: Callable
var _matte: ColorRect
var _page: Control
var _poster: Control
var _pr := Rect2()
var _giant: Array[RichTextLabel] = []
var _stars: Array[Control] = []
var _fade_in: Array[Control] = []
var _hero: Node2D
var _pass: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _emit(action_name: String) -> void:
	if on_action.is_valid():
		on_action.call(action_name)


## The matte, the page (everything that drops in together) and the clipped poster on it.
func _frame(safe_top: float, safe_bottom: float) -> void:
	var vs := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	_matte = ColorRect.new()
	_matte.name = "Matte"
	_matte.color = BP.MATTE
	_matte.mouse_filter = Control.MOUSE_FILTER_STOP
	_matte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_matte)
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.size = vs
	_page.pivot_offset = vs * 0.5
	add_child(_page)
	_pr = Rect2(16, safe_top + 14, vs.x - 32, maxf(vs.y - safe_top - safe_bottom - 14 - FOOT, 900.0))
	_poster = HPK.poster(_page, _pr)
	_poster.name = "Poster"


## The report's stage line: "STAGE 1-3" / "SPIRE F12".
func _stage_title(data: Dictionary) -> String:
	if str(data.get("mode", "")) == "tower":
		return "SPIRE F%02d" % int(data.get("floor", 0))
	return "STAGE %s" % str((data.get("stage", {}) as Dictionary).get("id", ""))


func _stage_sub(data: Dictionary) -> String:
	var st: Dictionary = data.get("stage", {})
	if str(data.get("mode", "")) == "tower":
		return "THE SPIRE  ·  %s" % str(st.get("name", "")).to_upper()
	return "CH.%02d  ·  %s" % [int(st.get("chapter", 0)) + 1, str(st.get("name", "")).to_upper()]


## The title block: serial, the stage huge, chapter and name, the date at the right.
func _title_block(parent: Control, data: Dictionary, x: float, y: float, w: float, ink: Color) -> void:
	BP.at(parent, BP.t("BATTLE REPORT  ·  No.%04d" % int(data.get("report_no", 0)), 11, ink, "mono_bold"), Vector2(x, y))
	BP.at(parent, BP.t(_stage_title(data), 46, ink, "compressed"), Vector2(x - 2, y + 10))
	var sub := BP.t(_stage_sub(data), 11, Color(ink, 0.8), "mono")
	sub.clip_text = true
	sub.size = Vector2(w - 100, 16)
	BP.at(parent, sub, Vector2(x, y + 70))
	var date := BP.t(_date_long(), 11, ink, "mono_bold")
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.size = Vector2(120, 16)
	BP.at(parent, date, Vector2(x + w - 120, y))


static func _date_long() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d %02d/%02d" % [int(d.year), int(d.month), int(d.day)]


## Battle time as a clock: "0:42".
static func _clock(ms: int) -> String:
	var s := maxi(ms, 0) / 1000
	return "%d:%02d" % [s / 60, s % 60]


## Vertical micro labels with ticks down the rule at x (non-interactive print).
func _rule_labels(parent: Control, x: float, y0: float, y1: float, items: Array, ink: Color) -> void:
	BP.rect(parent, Rect2(x, y0, 1, y1 - y0), Color(ink, 0.55))
	var pitch := (y1 - y0 - 40.0) / maxf(1.0, float(items.size()))
	for i in items.size():
		var y := y0 + 20.0 + i * pitch
		var l := BP.t(str(items[i]), 12, ink, "mono_bold")
		l.rotation = PI * 0.5
		l.position = Vector2(x + 30, y + 8)
		parent.add_child(l)
		BP.rect(parent, Rect2(x - 4, y, 9, 1), ink)


## data: stage, outcome, reward, first_clear, stars (1-3), team_size, mvp {hero_id, damage, share},
## has_next (bool), next_text, back_text, safe_top, safe_bottom, mode, floor, report_no.
func show_victory(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var p := _poster
	var pw := _pr.size.x
	var ph := _pr.size.y
	var out: Dictionary = data.get("outcome", {})
	var mvp: Dictionary = data.get("mvp", {})
	var mvp_id := str(mvp.get("hero_id", ""))
	var skin := Game.equipped_skin(mvp_id) if mvp_id != "" else ""
	var team_size := maxi(1, int(data.get("team_size", 5)))
	var n_stars := clampi(int(data.get("stars", 3)), 0, 3)
	var x_end := pw - RULE - 10.0

	# The band, her red halftone face, the mark and the micro type.
	BP.rect(p, Rect2(0, 0, BAND_W, ph), BP.BAND)
	if mvp_id != "":
		var ht := BP.halftone(mvp_id, skin, {"crop": "face"})
		ht.position = Vector2(0, ph * 0.5)
		ht.size = Vector2(BAND_W, ph * 0.5)
		p.add_child(ht)
	BP.at(p, BP.t("HH", 30, BP.PAPER, "wide_black"), Vector2(18, 14))
	BP.at(p, BP.t("™", 12, BP.PAPER, "mono"), Vector2(76, 16))
	var rights := BP.t("BATTLE REPORT  ·  ©2026 HH, ALL RIGHTS RESERVED.", 10, Color(BP.PAPER, 0.8), "mono_bold")
	rights.rotation = PI * 0.5
	rights.position = Vector2(30, 70)
	p.add_child(rights)

	# VICTORY, turned and running down the poster: paper on the band, signal on the paper over an
	# ink plate out of register. Everything else sits right of its letters.
	var word := "VICTORY"
	var room := ph - 250.0
	var fs := BP.fit(word, room, 260, 150)
	var cap := BP.caps(fs)
	var cap_h := cap.y - cap.x
	var feet_x := BAND_W - cap_h * 0.55
	var pos := Vector2(feet_x + cap.y, 26.0)
	var block := Vector2(room + 80.0, fs * 1.3)
	var paper_r := Rect2(BAND_W, 0, pw - BAND_W, ph)
	_giant = BP.giant(p, word, fs, pos + Vector2(6, 5), block, [[paper_r, Color(BP.INK, 0.92)]])
	_giant.append_array(BP.giant(p, word, fs, pos, block, [[Rect2(0, 0, BAND_W, ph), BP.PAPER], [paper_r, BP.SIG]]))
	var x0 := feet_x + cap_h + 16.0
	var cw_all := x_end - x0

	# The title block over the hero box.
	_title_block(p, data, x0, 18.0, cw_all, BP.INK)

	# The MVP in full colour, boxed by a hairline, in front of a riso print of herself.
	var box := Rect2(x0, 112.0, cw_all, ph - DATA_H - 112.0 - 14.0)
	var hb := Control.new()
	hb.name = "HeroBox"
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.clip_contents = true
	hb.position = box.position
	hb.size = box.size
	p.add_child(hb)
	if mvp_id != "":
		var height := box.size.y * 0.96
		var feet := Vector2(box.size.x * 0.58, box.size.y - 6.0)
		_hero = PK.hero_fig(hb, mvp_id, skin, feet, height)
		var spr := _hero.get_child(0) as Node2D
		var sr := PK.still_rect(spr, _hero.position, height)
		var k := 1.1
		var echo := BP.riso(mvp_id, skin, "full", {"shift_b": Vector2(5, -4), "cell_a": 6.0, "cell_b": 5.0, "strength": 0.92})
		echo.position = _hero.position + (sr.position - _hero.position) * k + Vector2(-58, -10)
		echo.size = sr.size * k
		hb.add_child(echo)
		hb.move_child(echo, 0)
		if spr.has_method("play_victory"):
			spr.call("play_victory")
	HPK.rule(p, box.position, Vector2(box.size.x, 1))
	HPK.rule(p, box.position + Vector2(0, box.size.y - 1), Vector2(box.size.x, 1))
	HPK.rule(p, box.position, Vector2(1, box.size.y))
	HPK.rule(p, box.position + Vector2(box.size.x - 1, 0), Vector2(1, box.size.y))
	var fig := BP.t("FIG. 01  ·  MVP", 10, Color(BP.INK, 0.75), "mono_bold")
	BP.at(p, fig, box.position + Vector2(8, 6))

	# Down the right-hand rule.
	_rule_labels(p, pw - RULE, 0.0, ph, ["©2026 ·", "VICTORY", "CLEARED %s" % _clock(int(out.get("duration_ms", 0))),
		"%d/%d STANDING" % [int(out.get("allies_alive", 0)), team_size], "%d / 3" % n_stars], BP.INK)

	# The data section: section rule, stars and rating, the run in one mono line.
	var y0 := ph - DATA_H
	BP.rect(p, Rect2(x0, y0, cw_all, 1), Color(BP.INK, 0.8))
	var tk := BP.Ticks.new()
	tk.count = 40
	tk.major = 10
	tk.from_top = true
	tk.position = Vector2(x0, y0 + 1)
	tk.size = Vector2(cw_all, 6)
	p.add_child(tk)
	BP.at(p, BP.t("02 / RESULT", 11, BP.INK, "mono_bold"), Vector2(x0, y0 + 12))
	var first := bool(data.get("first_clear", false))
	var cl := BP.t("FIRST CLEAR" if first else "REPLAY", 11, BP.SIG if first else Color(BP.INK, 0.7), "mono_bold")
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.size = Vector2(160, 16)
	BP.at(p, cl, Vector2(x_end - 160, y0 + 12))
	for i in 3:
		var star := HPK.Stars.new()
		star.count = 1
		star.filled = 1 if i < n_stars else 0
		star.color = BP.SIG
		star.empty = Color(BP.INK, 0.35)
		star.size = Vector2(56, 56)
		star.pivot_offset = Vector2(28, 28)
		star.position = Vector2(x0 + i * 64.0, y0 + 34)
		p.add_child(star)
		_stars.append(star)
	var rx := x0 + 3 * 64.0 + 12.0
	BP.at(p, BP.t("RATING", 11, Color(BP.INK, 0.75), "mono_bold"), Vector2(rx, y0 + 32))
	BP.at(p, BP.t("%d / 3" % n_stars, 44, BP.INK, "compressed"), Vector2(rx - 2, y0 + 42))
	var run := "TIME %s  ·  %d/%d STANDING  ·  ALL ECHOES DOWN" % [_clock(int(out.get("duration_ms", 0))), int(out.get("allies_alive", 0)), team_size]
	var rl := BP.t(run, 11, BP.INK, "mono")
	rl.clip_text = true
	rl.size = Vector2(cw_all, 16)
	BP.at(p, rl, Vector2(x0, y0 + 100))
	BP.rect(p, Rect2(x0, y0 + 124, cw_all, 1), Color(BP.INK, 0.55))

	# The MVP's line and signature (left column).
	var cw := cw_all * 0.53
	var mcol := Control.new()
	mcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mcol.position = Vector2(x0, y0 + 136)
	mcol.size = Vector2(cw, 220)
	p.add_child(mcol)
	_fade_in.append(mcol)
	if mvp_id != "":
		var name_text := str(Game.hero_def(mvp_id).get("name", mvp_id))
		BP.at(mcol, BP.t("MVP  ·  %d%% OF DAMAGE" % int(mvp.get("share", 0)), 11, BP.SIG, "mono_bold"), Vector2.ZERO)
		var nfs := BP.fit(name_text.to_upper(), cw - 6.0, 54, 26)
		BP.at(mcol, BP.t(name_text.to_upper(), nfs, BP.INK, "compressed"), Vector2(-2, 12 + (54 - nfs) * 0.5))
		BP.at(mcol, BP.t("%s DAMAGE" % Kit.format_full(int(mvp.get("damage", 0))), 12, BP.INK, "mono"), Vector2(0, 76))
		var share := PK.ticks(40, clampi(int(mvp.get("share", 0)) * 40 / 100, 0, 40), Vector2(minf(cw - 12.0, 200.0), 14), BP.INK, BP.SIG)
		BP.at(mcol, share, Vector2(0, 98))
		var sig := BP.t(name_text, 44, BP.INK, "serif_italic")
		BP.at(mcol, sig, Vector2(0, 120))
		var swash := BP.rect(mcol, Rect2(48, 176, minf(cw - 56.0, 160.0), 2), BP.INK)
		swash.rotation = -0.06

	# The rewards as a mono bracket table (right column).
	var rcx := x0 + cw + 10.0
	var rw := x_end - rcx
	var rcol := Control.new()
	rcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rcol.position = Vector2(rcx, y0 + 136)
	rcol.size = Vector2(rw, 240)
	p.add_child(rcol)
	_fade_in.append(rcol)
	BP.rect(rcol, Rect2(-6, 0, 1, 210), Color(BP.INK, 0.35))
	var reward: Dictionary = data.get("reward", {})
	var rows := _reward_rows(reward) if first else []
	if not rows.is_empty():
		BP.at(rcol, BP.t("REWARDS", 11, BP.INK, "mono_bold"), Vector2(4, 0))
		var table := PK.data_table(rows, rw, {"size": 12, "row_h": 25, "bar": Color(BP.SIG, 0.14)})
		BP.at(rcol, table, Vector2(-6, 20))
		BP.at(rcol, SignalKit.barcode(Vector2(minf(rw - 10.0, 140.0), 22), BP.INK, 404), Vector2(4, 30 + rows.size() * 25))
	else:
		BP.at(rcol, BP.t("REWARDS", 11, BP.INK, "mono_bold"), Vector2(4, 0))
		var t2 := PK.data_table([["1ST CLEAR", "CLAIMED", true], ["THIS RUN", "PRACTICE"]], rw, {"size": 12, "row_h": 25, "bar": Color(BP.INK, 0.06)})
		BP.at(rcol, t2, Vector2(-6, 20))
		BP.at(rcol, SignalKit.barcode(Vector2(minf(rw - 10.0, 140.0), 22), BP.INK, 404), Vector2(4, 84))

	# First-session guidance: after the early wins, point at leveling up (with a shortcut to
	# the hero), at the Lobby when something waits there, or at the next stage.
	var step := Guide.step()
	if step == "level":
		var lid := Guide.level_target()
		var lname := str(Game.hero_def(lid).get("name", "your heroes")) if lid != "" else "your heroes"
		var tip := _tip_sticker("Level up %s" % lname, "YOUR REWARDS PAY FOR IT.", "level")
		tip.position = _pr.position + Vector2(8, ph - 214)
		_page.add_child(tip)
		Guide.mark(tip, true, 0)
	var home := _lobby_button()
	_page.add_child(home)
	Guide.mark(home, step in ["claim", "summon", "formation", "quests"], 0)
	if bool(data.get("has_next", false)):
		var nt := str(data.get("next_text", "Next Stage"))
		_pass = _make_pass(nt, "next", _next_spec(data, nt))
		Guide.mark(_pass, step == "battle", 0)
	else:
		var bt := str(data.get("back_text", "Campaign"))
		_pass = _make_pass(bt, "campaign", {"kicker": "%s // ALL CLEAR" % bt.to_upper(), "title": bt.to_upper(),
			"sub": "BACK TO THE MAP", "action": "VIEW MAP  >>>", "icon": "flag"})
	PK.grain(self, 0.06)
	_animate_in(n_stars)


## data: stage, outcome, team_power, safe_top, safe_bottom, mvp, foe {hero_id, damage}, team_size,
## mode, floor, report_no.
func show_defeat(data: Dictionary) -> void:
	_frame(float(data.get("safe_top", 0.0)), float(data.get("safe_bottom", 0.0)))
	var p := _poster
	var pw := _pr.size.x
	var ph := _pr.size.y
	var st: Dictionary = data.get("stage", {})
	var out: Dictionary = data.get("outcome", {})
	var mvp: Dictionary = data.get("mvp", {})
	var mvp_id := str(mvp.get("hero_id", ""))
	var skin := Game.equipped_skin(mvp_id) if mvp_id != "" else ""
	var band_h := roundf(ph * 0.42)

	# The band across the top: her face as a red and a paper halftone, out of register.
	BP.rect(p, Rect2(0, 0, pw, band_h), BP.BAND)
	if mvp_id != "":
		var pr_rect := Rect2(pw * 0.3, 0, pw * 0.7, band_h)
		var red := BP.halftone(mvp_id, skin, {"crop": "face", "cell": 7.0})
		red.position = pr_rect.position
		red.size = pr_rect.size
		p.add_child(red)
		var pale := BP.halftone(mvp_id, skin, {"crop": "face", "cell": 5.0, "angle": 1.25, "ink": Color(BP.PAPER, 0.3), "gain": 1.05})
		pale.position = pr_rect.position + Vector2(7, -5)
		pale.size = pr_rect.size
		p.add_child(pale)
		var fade := TextureRect.new()
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.texture = Kit.vgradient(BP.BAND, Color(BP.BAND, 0.0), true)
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.position = pr_rect.position - Vector2(2, 0)
		fade.size = Vector2(150, band_h)
		p.add_child(fade)
	_title_block(p, data, 24.0, 18.0, pw - 48.0, BP.PAPER)

	# DEFEAT, turned and cut by the left edge: paper on the band, ink on the paper, over a signal
	# plate out of register.
	var word := "DEFEAT"
	var fs := BP.fit(word, ph * 0.62, 240, 140)
	var f := Kit.font("compressed")
	var length := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cap := BP.caps(fs)
	var cap_h := cap.y - cap.x
	var feet_x := -cap_h * 0.08
	var y_top := maxf(band_h - length * 0.6, 110.0)
	var pos := Vector2(feet_x + cap.y, y_top)
	var block := Vector2(length + 60.0, fs * 1.3)
	var band_r := Rect2(0, 0, pw, band_h)
	var paper_r := Rect2(0, band_h, pw, ph - band_h)
	_giant = BP.giant(p, word, fs, pos + Vector2(7, 6), block, [[band_r, BP.SIG], [paper_r, BP.SIG]])
	_giant.append_array(BP.giant(p, word, fs, pos, block, [[band_r, BP.PAPER], [paper_r, BP.INK]]))

	var dx := feet_x + cap_h + 30.0
	var dx_end := pw - RULE - 10.0
	var dw := dx_end - dx
	_rule_labels(p, pw - RULE, band_h, ph, ["DEFEAT", "No.%04d" % int(data.get("report_no", 0)), "%d/%d STANDING" % [int(out.get("allies_alive", 0)), maxi(1, int(data.get("team_size", 5)))]], BP.INK)

	# Why, and the power check.
	var col := Control.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(dx, band_h + 22)
	col.size = Vector2(dw, ph - band_h - 22)
	p.add_child(col)
	_fade_in.append(col)
	var why := "Time ran out before the echoes fell." if bool(out.get("timeout", false)) else "Your team was overwhelmed."
	BP.at(col, BP.t("01 / WHY", 11, BP.SIG, "mono_bold"), Vector2.ZERO)
	var wl := BP.t(why.to_upper(), 16, BP.INK, "mono_bold")
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.size = Vector2(dw, 44)
	BP.at(col, wl, Vector2(0, 18))
	var team := int(data.get("team_power", 0))
	var rec := int(st.get("recommended_power", 0))
	var verdict: Array = StageInfo.verdict(team, rec)
	var rows: Array = [["TEAM POWER", Kit.format_full(team)], ["RECOMMENDED", Kit.format_full(rec)],
		["VERDICT", str(verdict[0]).to_upper(), true], ["FOES STANDING", "%d LEFT" % int(out.get("enemies_alive", 0))]]
	var foe: Dictionary = data.get("foe", {})
	if not foe.is_empty():
		rows.append(["TOP ECHO", str(Game.hero_def(str(foe.get("hero_id", ""))).get("name", "")).to_upper()])
	var table := PK.data_table(rows, minf(dw, 360.0), {"size": 13, "row_h": 26, "bar": Color(BP.SIG, 0.14)})
	BP.at(col, table, Vector2(0, 66))
	var ty := 66.0 + rows.size() * 26.0 + 18.0

	# How to win: numbered printed lines (each an 88 px target).
	BP.at(col, BP.t("02 / HOW TO WIN", 11, BP.SIG, "mono_bold"), Vector2(0, ty))
	BP.rect(col, Rect2(0, ty + 18, dw, 1), Color(BP.INK, 0.8))
	var tips: Array = [["Level up your heroes", "SPEND GOLD AND HERO EXP FROM THE SANCTUM.", "level"],
		["Change your team", "STURDY GUARDIANS IN FRONT, DAMAGE DEALERS BEHIND.", "formation"]]
	var foe_f := StageInfo.main_faction(st)
	var ctr := StageInfo.counter_of(foe_f)
	if ctr != "":
		tips.append(["Bring %s heroes" % str(Kit.FACTION_NAMES.get(ctr, ctr)), ("THEY DEAL +20%% DAMAGE TO %s ECHOES." % str(Kit.FACTION_NAMES.get(foe_f, foe_f))).to_upper(), "formation"])
	for i in tips.size():
		var tip: Array = tips[i]
		var line := _tip_line(i + 1, str(tip[0]), str(tip[1]), str(tip[2]), dw)
		line.position = Vector2(0, ty + 20 + i * 88.0)
		col.add_child(line)
		if i == 0:
			Guide.mark(line, Guide.step() == "level", 0)

	var home := _lobby_button()
	_page.add_child(home)
	Guide.mark(home, Guide.step() in ["claim", "summon", "formation", "quests"], 0)
	var stage_t := _stage_title(data)
	_pass = _make_pass("Retry", "retry", {"kicker": "%s // AGAIN" % stage_t, "title": "RETRY", "sub": "SAME FOES · CHANGE THE ODDS",
		"action": "RETRY  >>>", "icon": "refresh", "info": "REC %s · YOU %s" % [Kit.format_full(rec), Kit.format_full(team)]})
	PK.grain(self, 0.06)
	_animate_in(0)


## Rewards as mono rows; the rarest (gems, a hero) in brackets.
func _reward_rows(reward: Dictionary) -> Array:
	var rows: Array = []
	var hi_done := false
	for e: Dictionary in Kit.reward_entries(reward):
		var kind := str(e.kind)
		var id := str(e.id)
		var key := ""
		var val := ""
		match kind:
			"currency":
				key = str(NAMES.get(id, id.to_upper()))
				val = "+%s" % Kit.format_full(int(e.amount))
			"gear_drop":
				var parts := id.split(":")
				var slot := parts[0] if parts.size() > 0 else ""
				var tier := int(parts[1]) if parts.size() > 1 else 0
				key = "%s%s" % [str(Kit.GEAR_SLOT_NAMES.get(slot, "GEAR")).to_upper(), (" T" + Kit.roman(tier)) if tier > 0 else ""]
				val = "x%d" % int(e.amount)
			"hero", "shard":
				key = str(Game.hero_def(id).get("name", id)).to_upper()
				val = "HERO" if kind == "hero" else "x%d SHARDS" % int(e.amount)
			_:
				key = "GEAR"
				val = "x%d" % int(e.amount)
		var hi := not hi_done and (kind == "hero" or id == "gems")
		if hi:
			hi_done = true
		rows.append([key, val, hi])
		if rows.size() >= 6:
			break
	return rows


## The pass for the main action, stuck over the poster's foot. Its button carries `text` (tests and
## the guide look for it) and is named after it.
func _make_pass(text: String, action_name: String, spec: Dictionary) -> Control:
	var full := spec.duplicate()
	full["width"] = 400.0
	var b := PK.pass_button(full, func() -> void: _emit(action_name))
	b.name = text.replace(" ", "")
	b.text = text
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color(0, 0, 0, 0))
	b.position = Vector2(_pr.end.x - 412.0, _pr.end.y - 124.0)
	b.rotation = -0.035
	_page.add_child(b)
	SignalKit.relight(self)
	return b


## The pass text for the next stage or floor.
func _next_spec(data: Dictionary, next_text: String) -> Dictionary:
	var st: Dictionary = data.get("stage", {})
	var spec := {"title": next_text.to_upper(), "action": "ENGAGE  >>>", "icon": "flag"}
	if str(data.get("mode", "")) == "tower":
		var fl := int(data.get("floor", 0)) + 1
		spec["kicker"] = "SPIRE // NEXT"
		spec["sub"] = "FLOOR %02d" % fl
		return spec
	var nxt := Game.stage(int(st.get("index", -1)) + 1)
	spec["kicker"] = "CAMPAIGN // NEXT" + ("  ·  BOSS" if bool(nxt.get("is_boss", false)) else "")
	var sub := "STAGE %s  ·  %s" % [str(nxt.get("id", "")), str(nxt.get("name", "")).to_upper()]
	if sub.length() > 34:
		sub = sub.substr(0, 33) + "…"
	spec["sub"] = sub
	var rec := int(nxt.get("recommended_power", 0))
	if rec > 0:
		spec["info"] = "REC %s · YOU %s" % [Kit.format_full(rec), Kit.format_full(int(Game.team_power()))]
	return spec


## "← Lobby" printed under the poster (an 88 px target).
func _lobby_button() -> Button:
	var b := PK.print_button("← Lobby", func() -> void: _emit("home"), {"size": Vector2(200, 88), "text_size": 17})
	b.name = "Lobby"
	var l: Label = b.get_meta("text_label")
	if l:
		l.uppercase = true
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.position = Vector2(_pr.position.x + 2, _pr.end.y + 8)
	return b


## The victory's level-up tip: a paper sticker stuck across the band's foot (signal "NEXT →", the
## line in mono, a small barcode).
func _tip_sticker(title_text: String, sub: String, action_name: String) -> Button:
	var b := PK.bare_button(Vector2(256, 104))
	b.name = "LevelTip"
	b.rotation = -0.03
	var sp := PanelContainer.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f4f3ef")
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(1, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sp.add_theme_stylebox_override("panel", sb)
	sp.position = Vector2(0, 4)
	sp.custom_minimum_size = Vector2(256, 96)
	var v := Kit.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(BP.t("NEXT →", 12, BP.SIG, "mono_bold"))
	var tl := BP.t(title_text, 16, BP.INK, "mono_bold")
	tl.uppercase = true
	tl.clip_text = true
	tl.custom_minimum_size.x = 226
	v.add_child(tl)
	v.add_child(BP.t(sub, 10, Color(BP.INK, 0.75), "mono"))
	sp.add_child(v)
	b.add_child(sp)
	PK.wire(b, [], func() -> void: _emit(action_name), sp)
	return b


## A numbered printed line (defeat's HOW TO WIN): "01", the title in mono, a sub line, an arrow and a
## hairline under it; the whole row is an 88 px target.
func _tip_line(n: int, title_text: String, sub: String, action_name: String, w: float) -> Button:
	var b := PK.bare_button(Vector2(w, 88))
	b.name = "Tip%d" % n
	var num := BP.t("%02d" % n, 13, BP.SIG, "mono_bold")
	num.position = Vector2(0, 22)
	b.add_child(num)
	var tl := BP.t(title_text, 17, BP.INK, "mono_bold")
	tl.uppercase = true
	tl.position = Vector2(36, 18)
	tl.size = Vector2(w - 80, 22)
	tl.clip_text = true
	b.add_child(tl)
	var sl := BP.t(sub, 10, Color(BP.INK, 0.72), "mono")
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.position = Vector2(36, 44)
	sl.size = Vector2(w - 80, 32)
	b.add_child(sl)
	var arrow := HPK.Arrow.new()
	arrow.size = Vector2(28, 14)
	arrow.position = Vector2(w - 28, 26)
	arrow.scale = Vector2(-1, 1)
	arrow.position.x = w
	b.add_child(arrow)
	BP.rect(b, Rect2(0, 87, w, 1), Color(BP.INK, 0.45))
	PK.wire(b, [], func() -> void: _emit(action_name), tl)
	return b


## The matte comes up, the poster drops onto it, the giant word typesets, the hero fades in, the
## stars are stamped one by one and the pass rises onto the poster's foot.
func _animate_in(filled: int) -> void:
	if not Kit.motion_ok():
		return
	_matte.modulate.a = 0.0
	_matte.create_tween().tween_property(_matte, "modulate:a", 1.0, 0.22)
	var base := _page.position
	_page.position = base + Vector2(0, 46)
	_page.rotation = 0.022
	_page.modulate.a = 0.0
	var tw := _page.create_tween().set_parallel(true)
	tw.tween_property(_page, "position", base, 0.36).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_page, "rotation", 0.0, 0.36).set_delay(0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_page, "modulate:a", 1.0, 0.16).set_delay(0.06)
	for rt in _giant:
		rt.visible_ratio = 0.0
		rt.create_tween().tween_property(rt, "visible_ratio", 1.0, 0.45).set_delay(0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _hero and is_instance_valid(_hero):
		_hero.modulate.a = 0.0
		_hero.create_tween().tween_property(_hero, "modulate:a", 1.0, 0.4).set_delay(0.3)
	for c in _fade_in:
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.45)
	for k in _stars.size():
		var s := _stars[k]
		s.modulate.a = 0.0
		s.scale = Vector2(1.8, 1.8)
		var st := s.create_tween().set_parallel(true)
		var d := 0.5 + k * 0.18
		st.tween_property(s, "modulate:a", 1.0, 0.08).set_delay(d)
		st.tween_property(s, "scale", Vector2.ONE, 0.22).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if k < filled:
			st.tween_callback(func() -> void: Kit.haptic(14)).set_delay(d + 0.1)
	if _pass and is_instance_valid(_pass):
		Kit.offset_in(_pass, Vector2(0, 70), 0.22, 0.32)
