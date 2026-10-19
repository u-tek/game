extends Control
## Glint (Kit.add_shine): a soft diagonal band of light that sweeps across its parent now
## and then, the "fresh glass" shimmer on primary and orange buttons, banners and the lobby
## call to action. The band is clipped to the parent's shape (its KitBox stylebox, or
## `shape`), it is drawn only while it moves, and it sits out while the parent is disabled,
## hidden, or the player has Reduce motion on. sweep_now() plays one at once.

const KitBox := preload("res://src/ui/components/kit_box.gd")

## () -> PackedVector2Array outline in local coordinates; invalid = the parent's stylebox.
var shape := Callable()
## Peak alpha of the white band.
var strength := 0.32
## Seconds between sweeps (random in [x, y]) and before the first one.
var every := Vector2(4.5, 8.5)
var first := Vector2(0.8, 3.5)
var duration := 0.62
## false = only sweep_now() plays it.
var auto := true

var _t := -1.0
var _tw: Tween

static var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if auto:
		_schedule(_rng.randf_range(first.x, first.y))


## Plays one sweep now (e.g. when a reward button appears).
func sweep_now(delay: float = 0.0) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if delay > 0.0:
		_schedule(delay)
	else:
		_sweep()


func _schedule(wait: float) -> void:
	if not is_inside_tree():
		return
	_tw = create_tween()
	_tw.tween_interval(wait)
	_tw.tween_callback(_sweep)


func _sweep() -> void:
	var p := get_parent()
	var ok := is_visible_in_tree() and Kit.motion_ok() and not (p is BaseButton and (p as BaseButton).disabled)
	if not ok:
		if auto:
			_schedule(_rng.randf_range(every.x, every.y))
		return
	_tw = create_tween()
	_tw.tween_method(_set_t, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(func() -> void:
		_t = -1.0
		queue_redraw()
		if auto:
			_schedule(_rng.randf_range(every.x, every.y)))


func _set_t(v: float) -> void:
	_t = v
	queue_redraw()


func _outline() -> PackedVector2Array:
	if shape.is_valid():
		var pts: Variant = shape.call()
		if pts is PackedVector2Array:
			return pts
	var p := get_parent()
	var sb: StyleBox = null
	if p is Button:
		sb = (p as Button).get_theme_stylebox("normal")
	elif p is Panel:
		sb = (p as Panel).get_theme_stylebox("panel")
	elif p is PanelContainer:
		sb = (p as PanelContainer).get_theme_stylebox("panel")
	var r := Rect2(Vector2.ZERO, size)
	if sb and sb.get_script() == KitBox:
		return sb.call("face_outline", r)
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _draw() -> void:
	if _t < 0.0:
		return
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return
	var outline := _outline()
	if outline.size() < 3:
		return
	var sk := h * 0.6
	var bw := clampf(w * 0.11, 16.0, 64.0)
	var cx := lerpf(-bw - sk, w + bw, _t)
	for half: float in [-1.0, 1.0]:
		var a := minf(cx, cx + half * bw)
		var b := maxf(cx, cx + half * bw)
		var quad := PackedVector2Array([Vector2(a, h), Vector2(a + sk, 0.0), Vector2(b + sk, 0.0), Vector2(b, h)])
		var pts := KitBox.clip_convex(quad, outline)
		if pts.size() < 3:
			continue
		var cols := PackedColorArray()
		cols.resize(pts.size())
		for i in pts.size():
			var p := pts[i]
			# Distance from the band's centre line, measured along x at that height.
			var u := clampf(absf(p.x - sk * (1.0 - p.y / h) - cx) / bw, 0.0, 1.0)
			cols[i] = Color(1, 1, 1, strength * (1.0 - u * u))
		draw_polygon(pts, cols)
