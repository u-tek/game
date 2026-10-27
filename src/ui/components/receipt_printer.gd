extends Control
## The reward receipt's printer (UI.show_reward): the receipt feeds up out of a thermal printer's slot
## a printed line at a time, with the stepper's buzz, then tears off: the paper hops up and tilts and
## the slot drops away. The receipt is any Control sized by its minimum (the sheet and its torn edge);
## the printer (a Cycles render, tools/blender/ui_objects.py printer) sits under its foot with the
## paper leaving its slit, where a real one is torn. Without motion it just shows the receipt.
##   var p := ReceiptPrinter.new(); p.setup(paper, 600.0); col.add_child(p); p.play(on_torn)

## Feed speed, px a second (a long receipt is capped at FEED_MAX seconds).
const FEED_PX := 900.0
const FEED_MIN := 0.5
const FEED_MAX := 1.05
## One step of the paper (a printed line), px: it moves in quick steps with a rest between.
const LINE := 34.0
const PRINTER := "res://assets/art/ui/objects/printer.png"
## The printer's slit spans the receipt's width and this much more.
const SLIT_OVER := 20.0

var paper: Control
var _clip: Control
var _slot: TextureRect
## Where the slit is in the printer's image ({slit_y, slit_x0, slit_x1}, printer.json).
var _slit := {"slit_y": 110.0, "slit_x0": 94.0, "slit_x1": 1346.0}
var _w := 600.0
## Feed progress 0..1 (0: all of it still in the printer).
var _k := 1.0


func setup(p: Control, w: float) -> void:
	paper = p
	_w = w
	mouse_filter = MOUSE_FILTER_IGNORE
	# The printer goes under the paper: the receipt covers the slit's back lip as it rises out of it.
	_slot = TextureRect.new()
	_slot.name = "Printer"
	_slot.mouse_filter = MOUSE_FILTER_IGNORE
	_slot.texture = load(PRINTER)
	_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slot.stretch_mode = TextureRect.STRETCH_SCALE
	_slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_slot.visible = false
	add_child(_slot)
	var f := FileAccess.open(PRINTER.replace(".png", ".json"), FileAccess.READ)
	if f:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_slit = j
	_clip = Control.new()
	_clip.name = "Feed"
	_clip.clip_contents = true
	_clip.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_clip)
	_clip.add_child(paper)
	paper.minimum_size_changed.connect(_fit)
	# With motion it waits in the printer for play().
	_k = 0.0 if Kit.motion_ok() else 1.0
	_fit()


## Sizes everything to the receipt (it can grow on its first frames, as its text lays out).
func _fit() -> void:
	if paper == null:
		return
	var ps := paper.get_combined_minimum_size()
	ps.x = maxf(ps.x, _w)
	paper.size = ps
	_clip.size = ps
	_clip.pivot_offset = Vector2(ps.x * 0.5, ps.y)
	# The printer, sized so its slit spans the receipt, the slit's line at the receipt's foot.
	var x0 := float(_slit.get("slit_x0", 94.0))
	var x1 := float(_slit.get("slit_x1", 1346.0))
	var k := (ps.x + SLIT_OVER) / maxf(x1 - x0, 1.0)
	var ts := Vector2(_slot.texture.get_size()) if _slot.texture else Vector2(1440, 293)
	_slot.size = ts * k
	_slot.position = Vector2(ps.x * 0.5 - (x0 + x1) * 0.5 * k, ps.y - float(_slit.get("slit_y", 110.0)) * k)
	_slot.set_meta("home_y", _slot.position.y)
	custom_minimum_size = Vector2(_w, _slot.position.y + _slot.size.y * 0.86)
	_place()


func _place() -> void:
	paper.position.y = paper.size.y * (1.0 - _stepped(_k))


## The paper's travel for feed progress k: a quick step per printed line, a short rest between.
func _stepped(k: float) -> float:
	if k >= 1.0:
		return 1.0
	var n := maxf(1.0, roundf(paper.size.y / LINE))
	var x := k * n
	var f := clampf((x - floorf(x)) / 0.62, 0.0, 1.0)
	return (floorf(x) + 1.0 - pow(1.0 - f, 3.0)) / n


func _set_k(k: float) -> void:
	_k = k
	_place()


## Prints the receipt; on_torn runs once it has torn off (at once without motion).
func play(on_torn: Callable = Callable()) -> void:
	if not Kit.motion_ok():
		_set_k(1.0)
		if on_torn.is_valid():
			on_torn.call()
		return
	_set_k(0.0)
	_slot.visible = true
	_slot.modulate.a = 0.0
	var dur := clampf(paper.size.y / FEED_PX, FEED_MIN, FEED_MAX)
	var tw := create_tween()
	tw.tween_property(_slot, "modulate:a", 1.0, 0.1)
	tw.tween_callback(func() -> void:
		UI.sfx("printer")
		UI.haptic(8))
	tw.tween_method(_set_k, 0.0, 1.0, dur)
	tw.tween_callback(_tear.bind(on_torn))


## Torn off: the paper hops up and tilts a hair, the slot drops away.
func _tear(on_torn: Callable) -> void:
	UI.sfx("tear")
	UI.haptic(20)
	var tw := create_tween().set_parallel(true)
	_clip.position = Vector2.ZERO
	tw.tween_property(_clip, "position:y", -10.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_clip, "rotation", -0.012, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_slot, "position:y", float(_slot.get_meta("home_y", _slot.position.y)) + 22.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_slot, "modulate:a", 0.0, 0.26)
	tw.chain().tween_property(_clip, "position:y", -4.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if on_torn.is_valid():
		on_torn.call()

