extends StyleBox
## KitBox: the house StyleBox for Halo & Horn (style v2, docs/dev/ui-style-v2.md).
## A box with a gradient fill, anti-aliased border, optional inner hairline, soft shadow or
## glow, and the v2 "technical" extras: skew (parallelogram), chamfered corners, diagonal
## hatching, corner brackets and accent bars. Everything is geometry, so it stays crisp at
## any device scale. Built by Kit / UITheme. If you edit fields after first use, call
## commit() again.
##
## The static helpers (shape_points, offset_poly, hatch, fill_poly, ...) are shared with the
## Kit components that draw their own shapes (skew plates, hex badges, cards).

## Corner radius in px (clamped to half the smaller side).
var radius: float = 16.0
## Fill gradient, top to bottom (or left to right when `horizontal`). Alpha is respected.
var top_color := Color("1c1e22")
var bottom_color := Color("15171a")
var horizontal := false
## false = no fill (frame only).
var fill := true
## Outer border.
var border_width: float = 0.0
var border_color := Color.TRANSPARENT
## Inner hairline drawn `inner_inset` px inside the face.
var inner_color := Color.TRANSPARENT
var inner_inset: float = 5.0
var inner_width: float = 1.0
## Alpha of the white highlight on the upper half of the face (0 = none).
var gloss: float = 0.0
## Height in px of the darker band at the bottom (3D depth; v2 buttons use 0-3).
var lip: float = 0.0
var lip_color := Color.BLACK
## Soft drop shadow (a zero offset with a bright color makes a glow).
var shadow_color := Color(0, 0, 0, 0.4)
var shadow_size: int = 0
var shadow_offset := Vector2(0, 3)
## Small diamonds at the four corners of the inner hairline (transparent = none).
var ornament_color := Color.TRANSPARENT
var ornament_size: float = 5.0
## Shifts the body down (pressed buttons keep their bottom edge, lose lip height).
var offset_y: float = 0.0
## Optional bright line along the very top edge of the face.
var top_line_color := Color.TRANSPARENT
## Draws smaller than the control (x = left/right, y = top/bottom px): lets a control keep
## a large touch area while looking compact. Add the same amount to the content margins.
var draw_inset := Vector2.ZERO

# ---- v2 extras
## Horizontal shear as a fraction of the height: the top edge sits `skew * h` px right of
## the bottom edge (0.176 = 10 degrees, the house angle). The shape stays inside the rect.
var skew: float = 0.0
## Cut-corner size in px for the corners in `chamfer_corners` (1 TL, 2 TR, 4 BR, 8 BL).
var chamfer: float = 0.0
var chamfer_corners: int = 5
## Diagonal hatching inside the shape. hatch_from/hatch_to = horizontal band (0..1 of the
## width) that gets hatched; the lines fade in from hatch_from.
var hatch_color := Color.TRANSPARENT
var hatch_spacing: float = 9.0
var hatch_width: float = 2.0
var hatch_from: float = 0.0
var hatch_to: float = 1.0
## Solid accent bars on the left or top edge (tabs, toasts, list rows).
var accent_color := Color.TRANSPARENT
var accent_left: float = 0.0
var accent_top: float = 0.0
## Thin L-brackets at the four corners, `corner_marks_inset` px inside the edge.
var corner_marks_color := Color.TRANSPARENT
var corner_marks_size: float = 12.0
var corner_marks_inset: float = 6.0

var _shadow: StyleBoxFlat
var _committed := false


## Rebuilds cached helpers. Returns self for chaining.
func commit() -> StyleBox:
	_committed = true
	_shadow = null
	if shadow_size > 0 and shadow_color.a > 0.0 and skew == 0.0 and chamfer <= 0.0:
		_shadow = StyleBoxFlat.new()
		_shadow.draw_center = false
		_shadow.bg_color = Color(0, 0, 0, 0)
		_shadow.shadow_color = shadow_color
		_shadow.shadow_size = shadow_size
		_shadow.shadow_offset = shadow_offset
		_shadow.set_corner_radius_all(int(radius))
		_shadow.corner_detail = 8
		_shadow.anti_aliasing = true
	emit_changed()
	return self


func _draw(ci: RID, rect: Rect2) -> void:
	if not _committed:
		commit()
	var body := rect.grow_individual(-draw_inset.x, -draw_inset.y, -draw_inset.x, -draw_inset.y)
	body.position.y += offset_y
	body.size.y -= offset_y
	if body.size.x < 1.0 or body.size.y < 1.0:
		return
	var r := minf(radius, minf(body.size.x, body.size.y) * 0.5 - 0.05)
	var outline := shape_points(body, r, chamfer, chamfer_corners, skew)
	# Shadow / glow.
	if _shadow:
		_shadow.draw(ci, body)
	elif shadow_size > 0 and shadow_color.a > 0.0:
		soft_shadow(ci, outline, shadow_color, float(shadow_size), shadow_offset)
	var face_pts := outline
	if fill:
		if lip > 0.0:
			fill_poly(ci, outline, lip_color, lip_color, false)
			var face := body
			face.size.y = maxf(face.size.y - lip, 1.0)
			face_pts = shape_points(face, minf(r, minf(face.size.x, face.size.y) * 0.5 - 0.05), chamfer, chamfer_corners, skew)
		fill_poly(ci, face_pts, top_color, bottom_color, horizontal)
		if gloss > 0.0 and skew == 0.0:
			var fb := _bounds(face_pts)
			var gl := fb.grow(-maxf(border_width, 1.0) - 1.0)
			gl.size.y *= 0.46
			if gl.size.x > 4.0 and gl.size.y > 2.0:
				var gp := shape_points(Rect2(gl.position, Vector2(gl.size.x, gl.size.y * 2.0)), maxf(r - 2.0, 0.0), chamfer, chamfer_corners, 0.0)
				var clipped := PackedVector2Array()
				for p in gp:
					clipped.append(Vector2(p.x, minf(p.y, gl.end.y)))
				var cols := PackedColorArray()
				for p in clipped:
					var t := clampf((p.y - gl.position.y) / gl.size.y, 0.0, 1.0)
					cols.append(Color(1, 1, 1, gloss * (1.0 - t) * (1.0 - t)))
				_fan(ci, clipped, cols, Vector2(gl.get_center().x, gl.position.y + gl.size.y * 0.5), Color(1, 1, 1, gloss * 0.25))
		if hatch_color.a > 0.0:
			hatch(ci, face_pts, hatch_color, hatch_spacing, hatch_width, hatch_from, hatch_to)
		if accent_color.a > 0.0 and (accent_left > 0.0 or accent_top > 0.0):
			_accent(ci, face_pts)
		if top_line_color.a > 0.0:
			var fb2 := _bounds(face_pts)
			var inset := minf(r, fb2.size.x * 0.5)
			var sx := skew * fb2.size.y
			RenderingServer.canvas_item_add_line(ci, Vector2(fb2.position.x + sx + inset, fb2.position.y + 1.0),
				Vector2(fb2.end.x - inset, fb2.position.y + 1.0), top_line_color, 1.0, true)
	if inner_color.a > 0.0:
		var ip := offset_poly(face_pts, -inner_inset)
		stroke_poly(ci, ip, inner_color, inner_width)
	if corner_marks_color.a > 0.0:
		corner_marks(ci, _bounds(face_pts).grow(-corner_marks_inset), corner_marks_color, corner_marks_size, 2.0)
	if border_width > 0.0 and border_color.a > 0.0:
		stroke_poly(ci, offset_poly(outline, -border_width * 0.5), border_color, border_width)
	if ornament_color.a > 0.0:
		var orect := _bounds(face_pts).grow(-inner_inset)
		var k := ornament_size
		for p: Vector2 in [orect.position, Vector2(orect.end.x, orect.position.y), orect.end, Vector2(orect.position.x, orect.end.y)]:
			var d := PackedVector2Array([p + Vector2(0, -k), p + Vector2(k, 0), p + Vector2(0, k), p + Vector2(-k, 0)])
			RenderingServer.canvas_item_add_polygon(ci, d, PackedColorArray([ornament_color]))


func _accent(ci: RID, pts: PackedVector2Array) -> void:
	var b := _bounds(pts)
	if accent_left > 0.0:
		var band := PackedVector2Array([b.position, Vector2(b.position.x + accent_left, b.position.y),
			Vector2(b.position.x + accent_left, b.end.y), Vector2(b.position.x, b.end.y)])
		var clipped := clip_convex(band, pts)
		if clipped.size() >= 3:
			RenderingServer.canvas_item_add_polygon(ci, clipped, PackedColorArray([accent_color]))
	if accent_top > 0.0:
		var band2 := PackedVector2Array([b.position, Vector2(b.end.x, b.position.y),
			Vector2(b.end.x, b.position.y + accent_top), Vector2(b.position.x, b.position.y + accent_top)])
		var clipped2 := clip_convex(band2, pts)
		if clipped2.size() >= 3:
			RenderingServer.canvas_item_add_polygon(ci, clipped2, PackedColorArray([accent_color]))


func _get_draw_rect(rect: Rect2) -> Rect2:
	if shadow_size > 0:
		return rect.grow(float(shadow_size) + absf(shadow_offset.y) + absf(shadow_offset.x))
	return rect


# ------------------------------------------------------------------ shared geometry

static func _bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)


## Outline of a box (clockwise from the top-left): rounded corners of radius `rad`, except
## the corners in `cut_mask` (1 TL, 2 TR, 4 BR, 8 BL) which are chamfered by `cut` px when
## cut > 0. skew shears it into a parallelogram that still fits in `r`.
static func shape_points(r: Rect2, rad: float, cut: float = 0.0, cut_mask: int = 5, skew_k: float = 0.0, seg: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var sx := skew_k * r.size.y
	var base := Rect2(r.position.x + sx * 0.5, r.position.y, maxf(r.size.x - sx, 2.0), r.size.y)
	rad = clampf(rad, 0.0, minf(base.size.x, base.size.y) * 0.5 - 0.05)
	cut = clampf(cut, 0.0, minf(base.size.x, base.size.y) * 0.5)
	var corners: Array[Vector2] = [base.position, Vector2(base.end.x, base.position.y), base.end, Vector2(base.position.x, base.end.y)]
	var dirs_in: Array[Vector2] = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	var dirs_out: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		var bit := 1 << c
		var corner := corners[c]
		if cut > 0.0 and (cut_mask & bit) != 0:
			pts.append(corner + dirs_in[c] * cut)
			pts.append(corner + dirs_out[c] * cut)
		elif rad > 0.5:
			var center := corner + (dirs_in[c] + dirs_out[c]) * rad
			for i in seg + 1:
				var a: float = starts[c] + (PI * 0.5) * float(i) / seg
				pts.append(center + Vector2(cos(a), sin(a)) * rad)
		else:
			pts.append(corner)
	if skew_k != 0.0:
		var cy := r.position.y + r.size.y * 0.5
		for i in pts.size():
			pts[i].x += (cy - pts[i].y) * skew_k
	return pts


## Points of a rounded rectangle (kept for older callers).
static func rrect_points(r: Rect2, rad: float, seg: int = 8) -> PackedVector2Array:
	return shape_points(r, rad, 0.0, 0, 0.0, seg)


## Hexagon points. flat = flat top; otherwise pointy top.
static func hex_points(center: Vector2, rad: float, flat: bool = false, squash: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var off := 0.0 if flat else 30.0
	for i in 6:
		var a := deg_to_rad(off + 60.0 * i)
		pts.append(center + Vector2(cos(a) * rad, sin(a) * rad * squash))
	return pts


## Moves every vertex of a convex polygon outward (d > 0) or inward (d < 0) along the
## corner bisector.
static func offset_poly(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3 or d == 0.0:
		return pts
	var out := PackedVector2Array()
	# Orientation: positive area = clockwise in screen space (y down).
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var e1 := (p1 - p0)
		var e2 := (p2 - p1)
		if e1.length_squared() < 0.0001:
			e1 = e2
		if e2.length_squared() < 0.0001:
			e2 = e1
		var n1 := Vector2(e1.y, -e1.x).normalized() * -sgn
		var n2 := Vector2(e2.y, -e2.x).normalized() * -sgn
		var bis := (n1 + n2)
		if bis.length_squared() < 0.0001:
			bis = n1
		bis = bis.normalized()
		var cos_half := maxf(bis.dot(n1), 0.35)
		out.append(p1 + bis * (d / cos_half))
	return out


## Fills a convex polygon with a two-color gradient (vertical, or horizontal).
static func fill_poly(ci: RID, pts: PackedVector2Array, c0: Color, c1: Color, horiz: bool = false) -> void:
	if pts.size() < 3:
		return
	var b := _bounds(pts)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		var t := clampf(((pts[i].x - b.position.x) / maxf(b.size.x, 0.001)) if horiz else ((pts[i].y - b.position.y) / maxf(b.size.y, 0.001)), 0.0, 1.0)
		cols[i] = c0.lerp(c1, t)
	_fan(ci, pts, cols, b.get_center(), c0.lerp(c1, 0.5))
	var loop := pts.duplicate()
	loop.append(pts[0])
	var lc := cols.duplicate()
	lc.append(cols[0])
	RenderingServer.canvas_item_add_polyline(ci, loop, lc, 1.0, true)


## Closed anti-aliased outline.
static func stroke_poly(ci: RID, pts: PackedVector2Array, col: Color, width: float = 2.0) -> void:
	if pts.size() < 2:
		return
	var loop := pts.duplicate()
	loop.append(pts[0])
	loop.append(pts[1])
	RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([col]), width, true)


## Layered soft shadow for any convex polygon.
static func soft_shadow(ci: RID, pts: PackedVector2Array, col: Color, size: float, off: Vector2 = Vector2.ZERO) -> void:
	var steps := 6
	for i in steps:
		var t := float(steps - i) / steps
		var grown := offset_poly(pts, size * t)
		var moved := PackedVector2Array()
		for p in grown:
			moved.append(p + off)
		RenderingServer.canvas_item_add_polygon(ci, moved, PackedColorArray([Color(col, col.a * (1.0 - t) * 0.42)]))


## Clips `subject` to the convex polygon `clip` (Sutherland-Hodgman).
static func clip_convex(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	var out := subject
	var n := clip.size()
	if n < 3:
		return out
	var area := 0.0
	for i in n:
		area += clip[i].x * clip[(i + 1) % n].y - clip[(i + 1) % n].x * clip[i].y
	var sgn := 1.0 if area > 0.0 else -1.0
	for i in n:
		var a := clip[i]
		var b := clip[(i + 1) % n]
		var inp := out
		out = PackedVector2Array()
		if inp.is_empty():
			break
		var s := inp[inp.size() - 1]
		for e in inp:
			var e_in := sgn * (b - a).cross(e - a) >= 0.0
			var s_in := sgn * (b - a).cross(s - a) >= 0.0
			if e_in:
				if not s_in:
					out.append(_isect(s, e, a, b))
				out.append(e)
			elif s_in:
				out.append(_isect(s, e, a, b))
			s = e
	return out


static func _isect(p1: Vector2, p2: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var d1 := p2 - p1
	var d2 := b - a
	var den := d1.cross(d2)
	if absf(den) < 0.00001:
		return p2
	var t := (a - p1).cross(d2) / den
	return p1 + d1 * t


## Diagonal hatching (45 degrees, rising to the right) clipped to a convex polygon. from/to
## limit it to a horizontal band of the polygon's width; lines fade in over the band.
static func hatch(ci: RID, poly: PackedVector2Array, col: Color, spacing: float = 9.0, width: float = 2.0, from: float = 0.0, to: float = 1.0) -> void:
	var b := _bounds(poly)
	if b.size.x < 2.0 or b.size.y < 2.0:
		return
	var x0 := b.position.x + b.size.x * from
	var x1 := b.position.x + b.size.x * to
	var x := x0 - b.size.y
	while x < x1:
		var a := Vector2(x, b.end.y)
		var e := Vector2(x + b.size.y, b.position.y)
		var seg := _clip_segment(a, e, poly)
		if seg.size() == 2:
			# Also clip to the band.
			var s0 := seg[0]
			var s1 := seg[1]
			if s0.x < x0:
				s0 = s0.lerp(s1, clampf((x0 - s0.x) / maxf(s1.x - s0.x, 0.001), 0.0, 1.0))
			if s1.x > x1:
				s1 = s0.lerp(s1, clampf((x1 - s0.x) / maxf(s1.x - s0.x, 0.001), 0.0, 1.0))
			if s0.distance_to(s1) > 0.5:
				var k := clampf((((s0.x + s1.x) * 0.5) - x0) / maxf((x1 - x0) * 0.6, 1.0), 0.0, 1.0) if from > 0.0 else 1.0
				RenderingServer.canvas_item_add_line(ci, s0, s1, Color(col, col.a * k), width, true)
		x += spacing


## Clips segment a-b to a convex polygon (Cyrus-Beck). Returns [] or [p, q].
static func _clip_segment(a: Vector2, b: Vector2, poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var sgn := 1.0 if area > 0.0 else -1.0
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var edge := q - p
		# Inside when sgn * edge.cross(x - p) >= 0.
		var num := sgn * edge.cross(a - p)
		var den := sgn * edge.cross(d)
		if absf(den) < 0.000001:
			if num < 0.0:
				return PackedVector2Array()
			continue
		var t := -num / den
		if den > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


## Thin L-brackets at the corners of `r` (the "technical frame" mark).
static func corner_marks(ci: RID, r: Rect2, col: Color, size: float = 12.0, width: float = 2.0) -> void:
	if r.size.x < size * 2.0 or r.size.y < size * 2.0:
		return
	var cs: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dx: Array[float] = [1.0, -1.0, -1.0, 1.0]
	var dy: Array[float] = [1.0, 1.0, -1.0, -1.0]
	for i in 4:
		var c := cs[i]
		RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array([c + Vector2(0, dy[i] * size), c, c + Vector2(dx[i] * size, 0)]),
			PackedColorArray([col]), width, true)


## Triangle fan from `center` (works because the shapes are convex).
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
