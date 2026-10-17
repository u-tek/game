extends Control
## Screen "splash_view": shows the installed splash cards (assets/art/splash/, SplashCard) full screen,
## animated, with Prev / Next. A preview for the loading-screen and event cards
## (UI.go("splash_view", {"card": "celestial_trio"})).

const SplashCardScript := preload("res://src/ui/components/splash_card.gd")

var _cards: PackedStringArray = []
var _i := 0
var _holder: Control
var _label: Label


func setup(params: Dictionary) -> void:
	_cards = SplashCardScript.installed()
	var want := str(params.get("card", ""))
	if want != "" and _cards.has(want):
		_i = _cards.find(want)
	_holder = Control.new()
	_holder.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_holder.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_holder)
	var bar := Kit.hbox(12)
	bar.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = -Kit.BUTTON_H - 140
	bar.offset_bottom = -140
	bar.add_child(Kit.secondary_button("Prev", func() -> void: _step(-1)))
	_label = Kit.label("", 26, Kit.INK, "cond_bold", 4)
	_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_label)
	bar.add_child(Kit.secondary_button("Next", func() -> void: _step(1)))
	add_child(bar)
	_show()


func _step(d: int) -> void:
	if _cards.is_empty():
		return
	_i = posmod(_i + d, _cards.size())
	_show()


func _show() -> void:
	for c in _holder.get_children():
		c.queue_free()
	if _cards.is_empty():
		_label.text = "No splash cards installed"
		return
	var c := SplashCardScript.make(_cards[_i])
	if c:
		_holder.add_child(c)
		c.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_label.text = "%s  (%d/%d)" % [_cards[_i].replace("_", " ").to_upper(), _i + 1, _cards.size()]
