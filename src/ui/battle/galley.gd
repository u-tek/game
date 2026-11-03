extends Control
## The battle's numbers, set as type in a galley (style v4 "Signal"), instead of a floating label per
## hit. One Control draws them all:
## - a tally per foe, docked beside her HP tag like a price sticker: every blow on her within MERGE_S
##   adds into it and re-stamps it (1.12 -> 1.0); the camera's foe's is set bigger, the rest smaller
##   and a little lighter; an ultimate's carries the skill's key word on an ink chip; a KO tab when
##   she falls;
## - a crit by the camera's heroine gets its own slab above the tally (ink numerals on signal, twice a
##   tally's size: the one accent); the tally hides while it is up and shows the merged total after;
## - a burn or regen line under a foe's tally (BRN 42), re-summed each tick;
## - what lands on a heroine is never drawn on her painting: it docks on her squad card (a paper slip on
##   the card's top edge: damage, +heal, [+shield], a burn), her chips stacked above it;
## - word chips for statuses (ink chips, a signal rule on a debuff's edge; a debuff stamps in signal
##   for a moment, then settles to ink).
## Paper numerals with an ink outline and an ink plate out of register on the street; ink on paper on
## the cards. Boxes are laid out every frame (place(): unit-tested), kept inside their area and off
## each other and the foes' tags, dropped by priority when there is no room. Text that must be read is
## 20 px or more (about 11 pt on a phone).

const PAPER := Color("e9e8e2")
const INK := Color("141517")
const SIG := Color("ff5c29")
## Blows on one foe within this many real seconds merge into her tally.
const MERGE_S := 0.45
## Seconds a number holds after its last change, per battle speed; then it lifts in LIFT_S.
const HOLD_S := {1: 0.65, 2: 0.52, 4: 0.4}
const LIFT_S := 0.14
const SLAB_HOLD_S := 0.7
const CHIP_HOLD_S := 0.7
const DOT_HOLD_S := 0.5
const STAMP_S := 0.034
## A debuff's chip stamps in signal this long, then settles to ink.
const CHIP_SIG_S := 0.2
const FOCUS_FS := 34
const TALLY_FS := 24
const ULT_FS := 42
const SLAB_FS := 56
const SLIP_FS := 24
const WORD_FS := 20
const STEP_UP := 46.0
## Priorities (higher placed first): a KO's tally, a crit slab, the camera's foe, other foes, slips,
## chips, DoT lines.
const PRI := {"ko": 6, "slab": 5, "tally": 4, "heal": 3, "slip": 3, "chip": 1, "dot": 0}

## uid -> unit view (the battle screen's), read for anchors every frame.
var views: Dictionary = {}
## The area the foes' numbers may use (this Control's space): below the top strip, above the cards.
var field := Rect2(0, 0, 720, 1280)
## uid -> a heroine's squad card (this Control's space); her numbers dock on it, inside card_area.
var cards: Dictionary = {}
var card_area := Rect2()
## Rects to keep clear (the tap hint, the souls label).
var blocked: Array[Rect2] = []
var speed := 1
var motion := true
## While an ultimate holds the screen nothing ages, but anchors are still read (the camera glides).
var paused := false
## The foe the camera's heroine is hitting (her tally is set bigger and placed first).
var focus_uid := ""

var _tally := {}
var _slab := {}
var _slip := {}
var _dot := {}
var _chips: Array[Dictionary] = []
var _font_num: Font
var _font_mono: Font
var _card_layer: Control
var _her_items: Array = []


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_font_num = Kit.font("compressed")
	_font_mono = Kit.font("mono_bold")
	# The heroines' numbers dock on the squad cards, which are drawn over the field: their own layer,
	# drawn above the card strip.
	_card_layer = Control.new()
	_card_layer.name = "Cards"
	_card_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_card_layer.z_index = 10
	_card_layer.draw.connect(func() -> void:
		if card_area.size.x > 0.0 and not _her_items.is_empty():
			_draw_all(_card_layer, _her_items, place(_her_items, card_area, [])))
	add_child(_card_layer)


## A blow of `amount` on `uid`. kicker: an ultimate's key word (its tally is set bigger). big: a crit
## by the camera's heroine (it gets the slab).
func hit(uid: String, amount: int, on_ally: bool, crit: bool = false, adv: bool = false, kicker: String = "", absorbed: bool = false,
		big: bool = true) -> void:
	if on_ally:
		_slip[uid] = {"text": ("(%s)" if absorbed else "%s") % Kit.format_num(amount), "kind": "damage", "t": 0.0}
		queue_redraw()
		return
	var cur: Dictionary = _tally.get(uid, {})
	if cur.is_empty() or bool(cur.get("ko", false)) or float(cur.t) > MERGE_S:
		cur = {"total": 0, "hits": 0, "t": 0.0, "stamp": 0.0, "adv": false, "kicker": "", "ko": false, "crit": false, "slab_only": false}
	cur.total = int(cur.total) + amount
	cur.hits = int(cur.hits) + 1
	cur.t = 0.0
	cur.stamp = 0.0
	cur.adv = bool(cur.adv) or adv
	if kicker != "":
		cur.kicker = kicker
	if crit and big:
		_slab[uid] = {"value": amount, "t": 0.0}
		cur.slab_only = int(cur.hits) == 1
	else:
		cur.slab_only = false
		cur.crit = bool(cur.crit) or crit
	_tally[uid] = cur
	queue_redraw()


## A burn (or regen) tick on `uid`: its line re-sums.
func dot(uid: String, amount: int, regen: bool = false) -> void:
	var cur: Dictionary = _dot.get(uid, {})
	if cur.is_empty() or bool(cur.regen) != regen or float(cur.t) > DOT_HOLD_S:
		cur = {"total": 0, "regen": regen, "t": 0.0}
	cur.total = int(cur.total) + amount
	cur.t = 0.0
	_dot[uid] = cur
	queue_redraw()


func heal(uid: String, amount: int) -> void:
	_slip[uid] = {"text": "+%s" % Kit.format_num(amount), "kind": "heal", "t": 0.0}
	queue_redraw()


func shield(uid: String, amount: int) -> void:
	_slip[uid] = {"text": "[+%s]" % Kit.format_num(amount), "kind": "shield", "t": 0.0}
	queue_redraw()


## A word chip on `uid` (a status, SPOTLIGHT, MARKED). status: it stays while the unit has it.
func chip(uid: String, word: String, bad: bool, status: String = "") -> void:
	for c in _chips:
		if str(c.uid) == uid and str(c.word) == word:
			c.t = 0.0
			return
	_chips.append({"uid": uid, "word": word, "bad": bad, "t": 0.0, "status": status})
	if _chips.size() > 10:
		_chips.pop_front()
	queue_redraw()


## She fell: her tally freezes with a KO tab and takes no more blows.
func ko(uid: String) -> void:
	if _tally.has(uid):
		_tally[uid].ko = true
		_tally[uid].t = 0.0
		_tally[uid].slab_only = false
	_slab.erase(uid)
	_dot.erase(uid)
	queue_redraw()


func clear() -> void:
	_tally.clear()
	_slab.clear()
	_slip.clear()
	_dot.clear()
	_chips.clear()
	queue_redraw()


## Blows in `uid`'s live tally (0 when none): a press climbs with them.
func hits_on(uid: String) -> int:
	return int((_tally.get(uid, {}) as Dictionary).get("hits", 0))


## Numbers on screen now (tests).
func count() -> int:
	return _tally.size() + _slab.size() + _slip.size() + _dot.size() + _chips.size()


func _process(delta: float) -> void:
	if count() == 0:
		return
	queue_redraw()
	if paused:
		return
	var hold := float(HOLD_S.get(speed, 0.65))
	for uid: String in _slab.keys():
		var s: Dictionary = _slab[uid]
		s.t = float(s.t) + delta
		if float(s.t) >= SLAB_HOLD_S + LIFT_S:
			_slab.erase(uid)
			# The slab lifts: the merged total shows for a full hold.
			if _tally.has(uid):
				_tally[uid].t = 0.0
				_tally[uid].slab_only = false
	for pair: Array in [[_tally, hold], [_slip, hold], [_dot, DOT_HOLD_S]]:
		var d: Dictionary = pair[0]
		for uid: String in d.keys():
			var e: Dictionary = d[uid]
			if e.has("stamp"):
				e.stamp = float(e.stamp) + delta
			# A tally waits under its slab.
			if d == _tally and _slab.has(uid):
				continue
			e.t = float(e.t) + delta
			if float(e.t) >= float(pair[1]) + (0.15 if bool(e.get("ko", false)) else 0.0) + LIFT_S:
				d.erase(uid)
	var i := 0
	while i < _chips.size():
		var c := _chips[i]
		c.t = float(c.t) + delta
		var st := str(c.status)
		var v: Node2D = views.get(str(c.uid))
		if st != "" and v != null and not bool(v.get("dead")) and (v.get("statuses") as Dictionary).has(st):
			c.t = minf(float(c.t), CHIP_HOLD_S)
		if float(c.t) >= CHIP_HOLD_S + LIFT_S:
			_chips.remove_at(i)
		else:
			i += 1


# ------------------------------------------------------------------ layout

## Lays out `items` ([{box: Rect2, pri: int}], each box at its wanted place) inside `area`, off each
## other and off `keep_clear`: higher priorities first (ties in order); a box that overlaps tries one
## step up, two steps up, then sideways by 0.6 of its width each way, then one step down; one with no
## room is dropped (null). Returns the placed rects in the items' order (Rect2 or null).
static func place(items: Array, area: Rect2, keep_clear: Array) -> Array:
	var order: Array = range(items.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa := int(items[a].pri)
		var pb := int(items[b].pri)
		return pa > pb or (pa == pb and a < b))
	var placed: Array[Rect2] = []
	for r: Variant in keep_clear:
		placed.append(r as Rect2)
	var out: Array = []
	out.resize(items.size())
	for idx: int in order:
		var box: Rect2 = items[idx].box
		var tries := [Vector2.ZERO, Vector2(0, -STEP_UP), Vector2(0, -STEP_UP * 2.0), Vector2(box.size.x * 0.6, 0),
			Vector2(-box.size.x * 0.6, 0), Vector2(0, STEP_UP)]
		var got: Variant = null
		for d: Vector2 in tries:
			var b := _clamp_in(Rect2(box.position + d, box.size), area)
			if b == Rect2():
				continue
			var overlaps := false
			for q in placed:
				if q.intersects(b):
					overlaps = true
					break
			if not overlaps:
				got = b
				break
		if got != null:
			placed.append(got as Rect2)
		out[idx] = got
	return out


## `b` moved inside `area` (by its whole size); an empty Rect2 if it cannot fit.
static func _clamp_in(b: Rect2, area: Rect2) -> Rect2:
	if b.size.x > area.size.x or b.size.y > area.size.y:
		return Rect2()
	var x := clampf(b.position.x, area.position.x, area.end.x - b.size.x)
	var y := clampf(b.position.y, area.position.y, area.end.y - b.size.y)
	return Rect2(Vector2(x, y), b.size)


# ------------------------------------------------------------------ drawing

func _num_size(text: String, fs: int, font: Font) -> Vector2:
	return Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, fs * 0.92)


func _draw() -> void:
	var hold := float(HOLD_S.get(speed, 0.65))
	var foe_items: Array = []
	var her_items: Array = []
	var shown_tags := {}
	for uid: String in views:
		var tv: Node2D = views[uid]
		if str(tv.get("side")) != "ally" and not bool(tv.get("dead")):
			shown_tags[uid] = tv.call("tag_rect")
	for uid: String in _tally:
		var v: Node2D = views.get(uid)
		var e: Dictionary = _tally[uid]
		# A crit's slab stands in for her tally while it is up.
		if v == null or _slab.has(uid):
			continue
		var focus := uid == focus_uid
		var ult := str(e.kicker) != ""
		var fs := ULT_FS if ult else (FOCUS_FS if focus else TALLY_FS)
		var text := Kit.format_num(int(e.total))
		var sz := _num_size(text, fs, _font_num) * 1.12 + Vector2(10, 8)
		if bool(e.ko):
			sz.x += 48.0
		elif ult:
			sz.x += _num_size(str(e.kicker), 18, _font_mono).x + 22.0
		var tag: Rect2 = v.call("tag_rect")
		foe_items.append({"box": _dock(tag, sz), "pri": int(PRI.ko if bool(e.ko) else PRI.tally) + (1 if focus else 0), "kind": "tally",
			"fs": fs, "text": text, "a": _alpha(float(e.t), hold + (0.15 if bool(e.ko) else 0.0)) * (1.0 if focus or ult else 0.8),
			"e": e, "focus": focus})
	for uid: String in _slab:
		var v: Node2D = views.get(uid)
		if v == null:
			continue
		var se: Dictionary = _slab[uid]
		var st := Kit.format_num(int(se.value))
		var ssz := _num_size(st, SLAB_FS, _font_num) + Vector2(40, 14)
		var tag: Rect2 = v.call("tag_rect")
		var box := _dock(tag, ssz)
		box.position.y = tag.position.y - ssz.y - 6.0
		foe_items.append({"box": box, "pri": PRI.slab, "kind": "slab", "text": st, "a": _alpha(float(se.t), SLAB_HOLD_S), "t": float(se.t)})
	for uid: String in _dot:
		var v: Node2D = views.get(uid)
		if v == null:
			continue
		var e: Dictionary = _dot[uid]
		var text := ("REG +%s" if bool(e.regen) else "BRN %s") % Kit.format_num(int(e.total))
		if str(v.get("side")) == "ally":
			if cards.has(uid):
				her_items.append(_card_item(uid, text, "dot", PRI.dot, _alpha(float(e.t), DOT_HOLD_S)))
			continue
		var sz := _num_size(text, WORD_FS, _font_mono) + Vector2(12, 8)
		var tag: Rect2 = v.call("tag_rect")
		foe_items.append({"box": Rect2(Vector2(tag.get_center().x - sz.x * 0.5, tag.end.y + 6.0), sz), "pri": PRI.dot, "kind": "dot",
			"text": text, "a": _alpha(float(e.t), DOT_HOLD_S)})
	for uid: String in _slip:
		if not cards.has(uid):
			continue
		var e: Dictionary = _slip[uid]
		her_items.append(_card_item(uid, str(e.text), str(e.kind), PRI.heal if str(e.kind) == "heal" else PRI.slip, _alpha(float(e.t), hold)))
	for c in _chips:
		var v: Node2D = views.get(str(c.uid))
		if v == null:
			continue
		var word := str(c.word)
		var sz := _num_size(word, WORD_FS, _font_num) + Vector2(16 + (4 if bool(c.bad) else 0), 10)
		var item := {"pri": PRI.chip, "kind": "chip", "text": word, "bad": bool(c.bad), "a": _alpha(float(c.t), CHIP_HOLD_S), "t": float(c.t)}
		if str(v.get("side")) == "ally":
			if not cards.has(str(c.uid)):
				continue
			# Above her slip's place on the card.
			var cr: Rect2 = cards[str(c.uid)]
			item.box = Rect2(Vector2(cr.end.x - sz.x - 4.0, cr.position.y - sz.y - 30.0), sz)
			her_items.append(item)
		else:
			var tag: Rect2 = v.call("tag_rect")
			item.box = Rect2(Vector2(tag.position.x, tag.position.y - 30.0 - sz.y), sz)
			foe_items.append(item)
	# Every foe's tag stays readable: no number covers one.
	var keep: Array = blocked.duplicate()
	for uid: String in shown_tags:
		keep.append(shown_tags[uid])
	_draw_all(self, foe_items, place(foe_items, field, keep))
	_her_items = her_items
	_card_layer.queue_redraw()


## A box of `sz` docked beside a foe's tag: on its outer end (the side away from the screen's middle),
## the inner end when that leaves the field.
func _dock(tag: Rect2, sz: Vector2) -> Rect2:
	var left := tag.get_center().x < field.get_center().x
	var box := Rect2(Vector2(tag.position.x - 4.0 - sz.x if left else tag.end.x + 4.0, tag.get_center().y - sz.y * 0.5), sz)
	if not field.encloses(box):
		box.position.x = tag.end.x + 4.0 if left else tag.position.x - 4.0 - sz.x
	return box


## A paper slip on a heroine's card: right-aligned on its top edge, half over the frame line.
func _card_item(uid: String, text: String, kind: String, pri: int, a: float) -> Dictionary:
	var cr: Rect2 = cards[uid]
	var sz := _num_size(text, SLIP_FS, _font_num) + Vector2(18, 12)
	return {"box": Rect2(Vector2(cr.end.x - sz.x - 4.0, cr.position.y - sz.y * 0.5), sz), "pri": pri, "kind": "slip", "slip": kind,
		"text": text, "a": a}


func _draw_all(ci: CanvasItem, items: Array, rects: Array) -> void:
	for i in items.size():
		if rects[i] == null:
			continue
		var it: Dictionary = items[i]
		var r: Rect2 = rects[i]
		var a := float(it.a)
		if a <= 0.0:
			continue
		if a < 1.0 and str(it.kind) != "tally":
			r.position.y -= (1.0 - a) * 6.0
		match str(it.kind):
			"tally":
				_draw_tally(ci, r, it, a)
			"slab":
				_draw_slab(ci, r, it, a)
			"dot":
				_draw_plated(ci, r, str(it.text), WORD_FS, _font_mono, PAPER, INK, a)
			"slip":
				_draw_slip(ci, r, it, a)
			"chip":
				_draw_chip(ci, r, it, a)


## 1 while it holds, then down to 0 over LIFT_S.
func _alpha(t: float, hold: float) -> float:
	return clampf(1.0 - (t - hold) / LIFT_S, 0.0, 1.0)


## Type in two plates: an ink outline holds the key on any part of the street, the ink plate sits out
## of register (+3, +2) under it.
func _draw_plated(ci: CanvasItem, r: Rect2, text: String, fs: int, font: Font, key: Color, back: Color, a: float, off: Vector2 = Vector2(3, 2)) -> void:
	var base := Vector2(r.position.x + 5.0, r.end.y - fs * 0.1 - 4.0)
	ci.draw_string(font, base + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(back, a))
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 6), Color(back, a))
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(key, a))


func _draw_tally(ci: CanvasItem, r: Rect2, it: Dictionary, a: float) -> void:
	var e: Dictionary = it.e
	var fs := int(it.fs)
	# The stamp: 1.12 -> 1.0 over two drawn frames, the ink plate twice as far out until it seats.
	var k := clampf(float(e.stamp) / STAMP_S, 0.0, 1.0) if motion else 1.0
	var sc := lerpf(1.12, 1.0, k)
	var off := Vector2(3, 2) * lerpf(2.0, 1.0, k)
	ci.draw_set_transform(r.get_center() + Vector2(0, -(1.0 - a) * 6.0), 0.0, Vector2(sc, sc))
	var lr := Rect2(-r.size * 0.5, r.size)
	var num_w := _num_size(str(it.text), fs, _font_num).x
	_draw_plated(ci, Rect2(lr.position, Vector2(num_w + 10.0, lr.size.y)), str(it.text), fs, _font_num, PAPER, INK, a, off)
	var kx := lr.position.x + num_w + 14.0
	if bool(e.ko):
		var kr := Rect2(Vector2(kx, lr.get_center().y - 15.0), Vector2(42, 30))
		ci.draw_rect(kr, Color(INK, a))
		ci.draw_string(_font_mono, Vector2(kr.position.x + 8, kr.end.y - 8), "KO", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(PAPER, a))
	elif str(e.kicker) != "":
		var kw := _num_size(str(e.kicker), 18, _font_mono).x + 12.0
		var kr := Rect2(Vector2(kx, lr.get_center().y - 13.0), Vector2(kw, 26))
		ci.draw_rect(kr, Color(INK, a))
		ci.draw_string(_font_mono, Vector2(kr.position.x + 6, kr.end.y - 7), str(e.kicker), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(PAPER, a))
	if bool(e.adv) and bool(it.focus):
		ci.draw_rect(Rect2(Vector2(lr.position.x + 5.0, lr.end.y - 1.0), Vector2(num_w, 3.0)), Color(SIG, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_slab(ci: CanvasItem, r: Rect2, it: Dictionary, a: float) -> void:
	var k := clampf(float(it.t) / STAMP_S, 0.0, 1.0) if motion else 1.0
	var sc := lerpf(1.12, 1.0, k)
	ci.draw_set_transform(r.get_center(), deg_to_rad(-4.0), Vector2(sc, sc))
	var lr := Rect2(-r.size * 0.5, r.size)
	ci.draw_rect(Rect2(lr.position + Vector2(3, 3), lr.size), Color(INK, a))
	ci.draw_rect(lr, Color(SIG, a))
	ci.draw_string(_font_num, Vector2(lr.position.x + 20.0, lr.end.y - 10.0), str(it.text), HORIZONTAL_ALIGNMENT_LEFT, -1, SLAB_FS, Color(INK, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_slip(ci: CanvasItem, r: Rect2, it: Dictionary, a: float) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(INK, a))
	ci.draw_rect(r, Color(PAPER, a))
	ci.draw_string(_font_num, Vector2(r.position.x + 9.0, r.end.y - 8.0), str(it.text), HORIZONTAL_ALIGNMENT_LEFT, -1, SLIP_FS, Color(INK, a))


## An ink chip with paper type; a debuff stamps in signal, then settles to ink with a signal rule on
## its left edge.
func _draw_chip(ci: CanvasItem, r: Rect2, it: Dictionary, a: float) -> void:
	var bad := bool(it.bad)
	var t := float(it.t)
	var tilt := deg_to_rad(-4.0 if str(it.text).hash() & 1 else 4.0)
	var slide := 0.0 if not motion else 6.0 * (1.0 - minf(t / 0.05, 1.0))
	ci.draw_set_transform(r.get_center() + Vector2(slide, 0), tilt, Vector2.ONE)
	var cr := Rect2(-r.size * 0.5, r.size)
	ci.draw_rect(Rect2(cr.position + Vector2(2, 2), cr.size), Color(INK, 0.4 * a))
	ci.draw_rect(cr, Color(SIG if bad and t < CHIP_SIG_S else INK, a))
	var tx := cr.position.x + 8.0
	if bad:
		ci.draw_rect(Rect2(cr.position, Vector2(4, cr.size.y)), Color(SIG, a))
		tx += 4.0
	ci.draw_string(_font_num, Vector2(tx, cr.end.y - 7), str(it.text), HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_FS, Color(PAPER, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
