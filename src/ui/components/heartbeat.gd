extends Control
## Her pulse, felt through the glass: hold a thumb on the Lobby heroine and the phone beats with her
## heart (a lub-dub through the haptics) while a small printed monitor strip by the thumb draws each
## beat and counts it. It starts calm and climbs the longer the thumb stays. The Lobby drives it:
## hold(seconds held) every frame while held, release() after.
##   bpm(held) = 70 + 48 * smoothstep(0, 9, held), plus a little drift (seeded by her id)

signal beat(bpm: int)

const INK := SignalKit.INK
const SIG := SignalKit.SIGNAL
const W := 150.0
const H := 54.0

var seed_value := 0
var _held := 0.0
var _phase := 0.0
var _bpm := 70.0
var _trace: PackedFloat32Array = PackedFloat32Array()   ## the strip's samples, newest last
var _since_beat := 10.0
var _dub_at := -1.0
var _fading := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	_trace.resize(64)
	_trace.fill(0.0)


static func bpm_at(held: float, drift: float = 0.0) -> float:
	return 70.0 + 48.0 * smoothstep(0.0, 9.0, held) + drift


## Called every frame while the thumb stays on her.
func hold(delta: float) -> void:
	_held += delta
	var drift := sin(_held * 0.7 + float(seed_value % 97)) * 2.0
	_bpm = bpm_at(_held, drift)
	_phase += delta * _bpm / 60.0
	_since_beat += delta
	if _phase >= 1.0:
		_phase -= 1.0
		_since_beat = 0.0
		# Lub ... dub.
		Kit.haptic(18, 0.6)
		_dub_at = 0.15
		beat.emit(int(round(_bpm)))
	if _dub_at >= 0.0:
		_dub_at -= delta
		if _dub_at < 0.0:
			Kit.haptic(10, 0.32)
	_push_sample()
	queue_redraw()


func held_seconds() -> float:
	return _held


func current_bpm() -> int:
	return int(round(_bpm))


## The thumb lifted: the strip flattens and fades.
func release() -> void:
	if _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)


## One sample of an ECG-like wave per frame: flat, a small P bump, the sharp QRS spike, a T hump.
func _push_sample() -> void:
	var t := _since_beat
	var v := 0.0
	v += 0.12 * exp(-pow((t - 0.04) / 0.025, 2.0))
	v -= 0.18 * exp(-pow((t - 0.085) / 0.008, 2.0))
	v += 1.0 * exp(-pow((t - 0.1) / 0.012, 2.0))
	v -= 0.3 * exp(-pow((t - 0.118) / 0.01, 2.0))
	v += 0.22 * exp(-pow((t - 0.3) / 0.05, 2.0))
	for i in _trace.size() - 1:
		_trace[i] = _trace[i + 1]
	_trace[_trace.size() - 1] = v


func _draw() -> void:
	# A printed strip: a hairline frame, the trace in ink with its newest point in signal, the count.
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color(1, 1, 1, 0.55), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color(INK, 0.55), false, 1.0)
	var base := H * 0.62
	var pts := PackedVector2Array()
	var n := _trace.size()
	for i in n:
		pts.append(Vector2(6.0 + (W * 0.56) * i / float(n - 1), base - _trace[i] * H * 0.42))
	draw_polyline(pts, INK, 1.6, true)
	draw_circle(pts[n - 1], 2.4, SIG)
	var f := Kit.font("mono_bold")
	var txt := "%d" % int(round(_bpm))
	draw_string(f, Vector2(W * 0.66, H * 0.56), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, SIG if _bpm >= 100.0 else INK)
	draw_string(Kit.font("mono"), Vector2(W * 0.66, H * 0.84), "BPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(INK, 0.6))
