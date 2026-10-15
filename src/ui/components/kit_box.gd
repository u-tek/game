extends StyleBox
## KitBox: the house StyleBox for Halo & Horn. A rounded box with a vertical gradient fill,
## anti-aliased border, optional inner hairline (the "double gold line" look), top gloss,
## bottom 3D lip (buttons), soft drop shadow and tiny corner diamonds (ornate panels).
## Everything is geometry, so it stays crisp at any device scale.
## Built by Kit / UITheme. If you edit fields after first use, call commit() again.

## Corner radius in px (clamped to half the smaller side).
var radius: float = 16.0
## Fill gradient, top to bottom. Alpha is respected (glass panels).
var top_color := Color("2a2150")
var bottom_color := Color("1d1738")
## false = no fill (frame only).
var fill := true
## Outer border.
var border_width: int = 0
var border_color := Color.TRANSPARENT
## Inner hairline drawn `inner_inset` px inside the face.
var inner_color := Color.TRANSPARENT
var inner_inset: float = 5.0
var inner_width: int = 1
## Alpha of the white highlight on the upper half of the face (0 = none).
var gloss: float = 0.0
## Height in px of the darker band at the bottom (3D button depth).
var lip: float = 0.0
var lip_color := Color.BLACK
## Soft drop shadow.
var shadow_color := Color(0, 0, 0, 0.4)
var shadow_size: int = 0
var shadow_offset := Vector2(0, 3)
## Small diamonds at the four corners of the inner hairline (transparent = none).
var ornament_color := Color.TRANSPARENT
var ornament_size: float = 5.0
## Shifts the body down (pressed buttons keep their bottom edge, lose lip height).
var offset_y: float = 0.0
## Optional bright line along the very top edge of the face (glass sheen).
var top_line_color := Color.TRANSPARENT

var _shadow: StyleBoxFlat
var _border: StyleBoxFlat
var _inner: StyleBoxFlat
var _committed := false


## Rebuilds the cached helper boxes. Returns self for chaining.
func commit() -> StyleBox:
	_committed = true
	_shadow = null
	_border = null
	_inner = null
	if shadow_size > 0 and shadow_color.a > 0.0:
		_shadow = StyleBoxFlat.new()
		_shadow.draw_center = false
		_shadow.bg_color = Color(0, 0, 0, 0)
		_shadow.shadow_color = shadow_color
		_shadow.shadow_size = shadow_size
		_shadow.shadow_offset = shadow_offset
		_shadow.set_corner_radius_all(int(radius))
		_shadow.corner_detail = 8
		_shadow.anti_aliasing = true
	if border_width > 0 and border_color.a > 0.0:
		_border = StyleBoxFlat.new()
		_border.draw_center = false
		_border.set_border_width_all(border_width)
		_border.border_color = border_color
		_border.set_corner_radius_all(int(radius))
		_border.corner_detail = 10
		_border.anti_aliasing = true
		_border.anti_aliasing_size = 0.8
	if inner_color.a > 0.0:
		_inner = StyleBoxFlat.new()
		_inner.draw_center = false
		_inner.set_border_width_all(inner_width)
		_inner.border_color = inner_color
		_inner.set_corner_radius_all(int(maxf(radius - inner_inset, 2.0)))
		_inner.corner_detail = 8
		_inner.anti_aliasing = true
		_inner.anti_aliasing_size = 0.7
	emit_changed()
	return self


func _draw(ci: RID, rect: Rect2) -> void:
	if not _committed:
		commit()
	var body := rect
	body.position.y += offset_y
	body.size.y -= offset_y
	if body.size.x < 1.0 or body.size.y < 1.0:
		return
	var r := minf(radius, minf(body.size.x, body.size.y) * 0.5 - 0.05)
	if _shadow:
		_shadow.draw(ci, body)
	var face := body
	if fill:
		if lip > 0.0:
			_fill_rrect(ci, body, r, lip_color, lip_color)
			face.size.y = maxf(face.size.y - lip, 1.0)
		var fr := minf(r, minf(face.size.x, face.size.y) * 0.5 - 0.05)
		_fill_rrect(ci, face, fr, top_color, bottom_color)
		if gloss > 0.0:
			_draw_gloss(ci, face.grow(-maxf(float(border_width), 1.0) - 1.0), fr, gloss)
		if top_line_color.a > 0.0:
			var tl := face.grow(-float(border_width) - 1.0)
			var inset := minf(fr, tl.size.x * 0.5)
			RenderingServer.canvas_item_add_line(ci, Vector2(tl.position.x + inset, tl.position.y + 0.5),
				Vector2(tl.end.x - inset, tl.position.y + 0.5), top_line_color, 1.0, true)
	if _inner:
		var ir := face.grow(-inner_inset)
		if ir.size.x > 4.0 and ir.size.y > 4.0:
			_inner.draw(ci, ir)
	if _border:
		_border.draw(ci, body)
	if ornament_color.a > 0.0:
		var orect := face.grow(-inner_inset)
		var k := ornament_size
		for p: Vector2 in [orect.position, Vector2(orect.end.x, orect.position.y), orect.end, Vector2(orect.position.x, orect.end.y)]:
			var d := PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, 0), p + Vector2(0, k), p + Vector2(-k, 0)])
			RenderingServer.canvas_item_add_polygon(ci, d, PackedColorArray([ornament_color]))
			d.append(d[0])
			RenderingServer.canvas_item_add_polyline(ci, d, PackedColorArray([ornament_color]), 1.0, true)


## Anti-aliased rounded rectangle with a vertical gradient.
static func _fill_rrect(ci: RID, r: Rect2, rad: float, c_top: Color, c_bot: Color) -> void:
	var pts := rrect_points(r, rad)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		cols[i] = c_top.lerp(c_bot, clampf((pts[i].y - r.position.y) / r.size.y, 0.0, 1.0))
	_fan(ci, pts, cols, r.get_center(), c_top.lerp(c_bot, 0.5))
	var outline := pts.duplicate()
	outline.append(pts[0])
	var ocols := cols.duplicate()
	ocols.append(cols[0])
	RenderingServer.canvas_item_add_polyline(ci, outline, ocols, 1.0, true)


static func _draw_gloss(ci: RID, r: Rect2, rad: float, alpha: float) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var h := r.size.y * 0.46
	var rr := clampf(rad - 2.0, 0.0, minf(r.size.x * 0.5, h) - 0.05)
	var pts := PackedVector2Array()
	var seg := 6
	if rr > 0.5:
		for i in seg + 1:
			var a := PI + (PI * 0.5) * float(i) / seg
			pts.append(Vector2(r.position.x + rr, r.position.y + rr) + Vector2(cos(a), sin(a)) * rr)
		for i in seg + 1:
			var a := PI * 1.5 + (PI * 0.5) * float(i) / seg
			pts.append(Vector2(r.end.x - rr, r.position.y + rr) + Vector2(cos(a), sin(a)) * rr)
	else:
		pts.append(r.position)
		pts.append(Vector2(r.end.x, r.position.y))
	pts.append(Vector2(r.end.x, r.position.y + h))
	pts.append(Vector2(r.position.x, r.position.y + h))
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		var t := clampf((pts[i].y - r.position.y) / h, 0.0, 1.0)
		cols[i] = Color(1, 1, 1, alpha * (1.0 - t) * (1.0 - t))
	_fan(ci, pts, cols, Vector2(r.get_center().x, r.position.y + h * 0.5), Color(1, 1, 1, alpha * 0.25))



func _get_draw_rect(rect: Rect2) -> Rect2:
	if shadow_size > 0:
		return rect.grow(float(shadow_size) + absf(shadow_offset.y))
	return rect


## Triangle fan from `center` (works because rounded rects are convex).
static func _fan(ci: RID, pts: PackedVector2Array, cols: PackedColorArray, center: Vector2, center_col: Color) -> void:
	var all_pts := PackedVector2Array([center])
	all_pts.append_array(pts)
	var all_cols := PackedColorArray([center_col])
	all_cols.append_array(cols)
	var idx := PackedInt32Array()
	var n := pts.size()
	for i in n:
		idx.append(0)
		idx.append(1 + i)
		idx.append(1 + (i + 1) % n)
	RenderingServer.canvas_item_add_triangle_array(ci, idx, all_pts, all_cols)


## Points of a rounded rectangle, clockwise from the top-left arc.
static func rrect_points(r: Rect2, rad: float, seg: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5 - 0.05)
	if rad <= 0.5:
		pts.append(r.position)
		pts.append(Vector2(r.end.x, r.position.y))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		return pts
	var centers: Array[Vector2] = [
		Vector2(r.position.x + rad, r.position.y + rad), Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad), Vector2(r.position.x + rad, r.end.y - rad)]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		for i in seg + 1:
			var a: float = starts[c] + (PI * 0.5) * float(i) / seg
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * rad)
	return pts
