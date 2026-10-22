extends Control
## The player's signature (signed with a finger on the intake form, the onboarding's "calling"
## screen; kept in the save as strokes, GameModel.signature). Drawn as ink: each stroke a smoothed
## line whose width swells in its middle and thins at its ends like a pen nib, fitted into this
## control's rect (aspect kept, left-aligned). Used wherever the game signs for the player: the
## profile card, reward receipts, the oath on the front, the print album.
##   var s := Signature.new(); s.strokes = Game.signature(); s.ink = INK; s.size = Vector2(160, 50)
## strokes: Array of PackedInt32Array, x, y pairs in 0..1000 (the signing pad's coordinates).
## With no strokes it draws `fallback` in the slanted serif instead (the typed name).

var strokes: Array = []
var ink := Color("101113")
var fallback := ""
## Nib width at its widest (px at this control's size).
var weight := 3.2
## 0..1: how much of the signature is drawn (the signing-on animation).
var reveal := 1.0:
	set(v):
		reveal = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


## Plays the signature being written (about `secs`).
func write_on(secs: float = 0.9) -> void:
	if not Kit.motion_ok():
		reveal = 1.0
		return
	reveal = 0.0
	create_tween().tween_property(self, "reveal", 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func has_ink(s: Array) -> bool:
	for st: Variant in s:
		if (st is PackedInt32Array or st is Array) and (st as Variant).size() >= 4:
			return true
	return false


func _draw() -> void:
	if not has_ink(strokes):
		if fallback != "":
			var f := Kit.font("serif_italic")
			var fs := int(minf(size.y * 0.9, 60.0))
			draw_string(f, Vector2(0, size.y * 0.78), fallback, HORIZONTAL_ALIGNMENT_LEFT, size.x, fs, ink)
		return
	# Bounds of the ink, to fit it in the rect.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var total := 0
	for st: Variant in strokes:
		var a: Array = Array(st)
		total += a.size() / 2
		for i in range(0, a.size() - 1, 2):
			var p := Vector2(float(a[i]), float(a[i + 1]))
			lo = lo.min(p)
			hi = hi.max(p)
	var span := (hi - lo).max(Vector2(1, 1))
	var k := minf(size.x / span.x, size.y / span.y)
	var off := Vector2(0, (size.y - span.y * k) * 0.5)
	var shown := int(ceil(total * reveal))
	var drawn := 0
	for st: Variant in strokes:
		var a: Array = Array(st)
		var n := a.size() / 2
		if n < 2 or drawn >= shown:
			drawn += n
			continue
		var pts := PackedVector2Array()
		for i in n:
			if drawn + i >= shown:
				break
			pts.append(off + (Vector2(float(a[i * 2]), float(a[i * 2 + 1])) - lo) * k)
		drawn += n
		# A nib: thin at the ends, full in the middle; segments as thick lines with round joints.
		for i in pts.size() - 1:
			var tpos := float(i) / maxf(float(n - 1), 1.0)
			var w := weight * (0.35 + 0.65 * sin(PI * clampf(tpos, 0.0, 1.0)))
			draw_line(pts[i], pts[i + 1], ink, w, true)
			draw_circle(pts[i + 1], w * 0.5, ink, true, -1.0, true)
