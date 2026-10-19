extends RefCounted
## Procedural sound effects (no audio files). UI.sfx(name) plays these.
## Every sound is synthesized once into a 16-bit mono AudioStreamWAV.
## Names: tap, tab, pop, close, deny, toggle, coin, sparkle (UI feel), reward, summon,
## legendary, hit, ult, victory, defeat.

const RATE := 22050
const NAMES: Array[String] = ["tap", "tab", "pop", "deny", "toggle", "coin", "sparkle", "close", "hit", "reward",
	"ult", "summon", "victory", "defeat", "legendary"]


## Builds the stream for `sound_name` (null if unknown).
static func make(sound_name: String) -> AudioStreamWAV:
	var s: PackedFloat32Array
	match sound_name:
		"tap":
			s = _tap()
		"tab":
			s = _tab()
		"pop":
			s = _pop()
		"close":
			s = _close()
		"deny":
			s = _deny()
		"toggle":
			s = _toggle()
		"coin":
			s = _coin()
		"sparkle":
			s = _sparkle()
		"hit":
			s = _hit()
		"reward":
			s = _reward()
		"summon":
			s = _summon()
		"legendary":
			s = _legendary()
		"ult":
			s = _ult()
		"victory":
			s = _victory()
		"defeat":
			s = _defeat()
		_:
			return null
	return _to_wav(s)


static func _to_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	var fade := mini(int(0.03 * RATE), s.size())
	var fade_from := s.size() - fade
	for i in s.size():
		var v := s[i] * gain
		if i >= fade_from:
			v *= float(s.size() - i) / float(fade)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b


## Adds a bell-like note (sine + inharmonic partials, exponential decay).
static func _bell(b: PackedFloat32Array, start: float, freq: float, amp: float, decay: float, dur: float) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	for i in n:
		var t := float(i) / RATE
		var att := minf(1.0, t * 400.0)
		var e := exp(-t * decay) * att
		var v := sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.0 * t) * exp(-t * decay) + 0.12 * sin(TAU * freq * 3.01 * t) * exp(-t * decay * 2.0)
		b[i0 + i] += v * e * amp


## Adds a brass-like note (few harmonics, soft attack, release at the end).
static func _brass(b: PackedFloat32Array, start: float, freq: float, amp: float, dur: float, vibrato: float = 0.0) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := freq * (1.0 + vibrato * sin(TAU * 5.5 * t) * minf(1.0, t * 3.0))
		phase += TAU * f / RATE
		var att := minf(1.0, t * 30.0)
		var rel := clampf((dur - t) * 8.0, 0.0, 1.0)
		var v := sin(phase) + 0.5 * sin(phase * 2.0) + 0.28 * sin(phase * 3.0) + 0.12 * sin(phase * 4.0)
		b[i0 + i] += v * att * rel * amp * (0.85 + 0.15 * exp(-t * 4.0))


## Button tap: a crisp glassy tick (high partial) over a soft round body, like pressing a
## glossy bubble. About 60 ms.
static func _tap() -> PackedFloat32Array:
	return _tick(0.065, 2350.0, 210.0, 0.34, 0.42, 11)


## Bottom-nav / tab switch: the same family, lower and softer.
static func _tab() -> PackedFloat32Array:
	return _tick(0.08, 1650.0, 165.0, 0.26, 0.46, 13)


## Switch flip: short and clicky (callers pitch it up for on, down for off).
static func _toggle() -> PackedFloat32Array:
	return _tick(0.05, 2900.0, 260.0, 0.4, 0.3, 17)


## Shared tick: `hi` Hz glass partial, `body` Hz thump with a quick upward bend, a 1 ms
## noise click. Amplitudes are relative.
static func _tick(dur: float, hi: float, body: float, hi_amp: float, body_amp: float, seed_v: int) -> PackedFloat32Array:
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var p_hi := 0.0
	var p_body := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var att := minf(1.0, t * 1200.0)
		p_hi += TAU * hi * (1.0 + 0.04 * exp(-t * 200.0)) / RATE
		p_body += TAU * body * (1.0 + 0.9 * (1.0 - exp(-t * 120.0))) / RATE
		var v := sin(p_hi) * exp(-t * 150.0) * hi_amp
		v += (sin(p_hi * 1.51) * 0.35) * exp(-t * 260.0) * hi_amp
		v += sin(p_body) * exp(-t * 55.0) * body_amp
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 1800.0) * 0.18
		b[i] = v * att
	return b


## Popup open: an airy upward swoosh ending in a soft bubble.
static func _pop() -> PackedFloat32Array:
	var dur := 0.2
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := sin(PI * clampf(k * 1.15, 0.0, 1.0)) * (1.0 - k * 0.4)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.04 + 0.22 * k)
		phase += TAU * (420.0 + 620.0 * k * k) / RATE
		b[i] = lp * env * 0.55 + sin(phase) * env * 0.16
	_bell(b, 0.1, 1760.0, 0.16, 22.0, 0.1)
	return b


## Popup close: a short falling swoosh (quiet).
static func _close() -> PackedFloat32Array:
	var dur := 0.14
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := sin(PI * k) * (1.0 - k * 0.3)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.22 - 0.17 * k)
		phase += TAU * (760.0 - 360.0 * k) / RATE
		b[i] = lp * env * 0.45 + sin(phase) * env * 0.12
	return b


## Not allowed / can't afford: two dull, slightly buzzy low notes.
static func _deny() -> PackedFloat32Array:
	var b := _buf(0.2)
	for nd: Array in [[0.0, 233.0], [0.095, 185.0]]:
		var i0 := int(float(nd[0]) * RATE)
		var f: float = nd[1]
		var phase := 0.0
		for i in mini(int(0.085 * RATE), b.size() - i0):
			var t := float(i) / RATE
			phase += TAU * f / RATE
			var env := minf(1.0, t * 400.0) * exp(-t * 22.0)
			var v := sin(phase) + 0.32 * sin(phase * 3.0) + 0.12 * sin(phase * 5.0)
			b[i0 + i] += v * env * 0.42
	return b


## A coin / gem landing in the wallet: a bright metallic ting.
static func _coin() -> PackedFloat32Array:
	var b := _buf(0.26)
	_bell(b, 0.0, 2637.0, 0.3, 16.0, 0.26)
	_bell(b, 0.012, 3951.0, 0.16, 24.0, 0.2)
	return b


## Reward tile pop: a small high shimmer.
static func _sparkle() -> PackedFloat32Array:
	var b := _buf(0.24)
	_bell(b, 0.0, 3136.0, 0.2, 15.0, 0.22)
	_bell(b, 0.035, 4186.0, 0.12, 18.0, 0.2)
	return b


static func _hit() -> PackedFloat32Array:
	var b := _buf(0.2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 55.0 + 150.0 * exp(-t * 30.0)
		phase += TAU * f / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		b[i] = sin(phase) * exp(-t * 22.0) * 0.8 + lp * exp(-t * 45.0) * 0.7
	return b


static func _reward() -> PackedFloat32Array:
	var b := _buf(0.9)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for k in notes.size():
		_bell(b, 0.07 * k, notes[k], 0.28, 5.5, 0.9 - 0.07 * k)
	# Sparkle tail.
	_bell(b, 0.32, 3136.0, 0.08, 9.0, 0.5)
	_bell(b, 0.38, 2637.0, 0.06, 9.0, 0.45)
	return b


static func _summon() -> PackedFloat32Array:
	var dur := 1.1
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := pow(sin(PI * clampf(k * 1.1, 0.0, 1.0)), 1.5)
		var alpha := 0.02 + 0.3 * k * k
		lp += (rng.randf_range(-1.0, 1.0) - lp) * alpha
		var f := 180.0 * pow(2.0, 2.6 * k)
		phase += TAU * f / RATE
		b[i] = lp * env * 0.9 + sin(phase) * env * 0.22 * k + sin(phase * 1.5) * env * 0.08 * k
	_bell(b, 0.78, 2093.0, 0.12, 7.0, 0.32)
	_bell(b, 0.86, 2637.0, 0.1, 7.0, 0.24)
	return b


static func _legendary() -> PackedFloat32Array:
	var dur := 2.0
	var b := _buf(dur)
	# Deep boom.
	var phase := 0.0
	for i in int(0.5 * RATE):
		var t := float(i) / RATE
		phase += TAU * (48.0 + 60.0 * exp(-t * 12.0)) / RATE
		b[i] += sin(phase) * exp(-t * 6.0) * 0.6
	# Choir-like major chord bloom with slight detune.
	var chord := [261.63, 392.0, 523.25, 659.25, 783.99]
	for f: float in chord:
		var p1 := 0.0
		var p2 := 0.0
		for i in range(int(0.05 * RATE), b.size()):
			var t := float(i) / RATE - 0.05
			var env := minf(1.0, t / 0.25) * exp(-t * 1.3)
			p1 += TAU * f * 1.003 / RATE
			p2 += TAU * f * 0.997 / RATE
			var v := sin(p1) + sin(p2) + 0.3 * sin(p1 * 2.0)
			b[i] += v * env * 0.07
	# Rising sparkle arpeggio.
	var sparkle := [2093.0, 2637.0, 3136.0, 4186.0, 3136.0, 4186.0]
	for k in sparkle.size():
		_bell(b, 0.18 + 0.09 * k, sparkle[k], 0.07, 8.0, 0.4)
	return b


static func _ult() -> PackedFloat32Array:
	var dur := 0.75
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		if t < 0.42:
			var k := t / 0.42
			var f := 260.0 * pow(2.0, 2.4 * k)
			phase += TAU * f / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.05 + 0.4 * k)
			var env := k * k
			b[i] = (sin(phase) + 0.45 * sin(phase * 2.0) + 0.25 * sin(phase * 3.0)) * env * 0.3 + lp * env * 0.35
		else:
			var u := t - 0.42
			phase += TAU * (60.0 + 120.0 * exp(-u * 25.0)) / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.6
			b[i] = sin(phase) * exp(-u * 9.0) * 0.8 + lp * exp(-u * 14.0) * 0.6
	return b


static func _victory() -> PackedFloat32Array:
	var b := _buf(1.6)
	_brass(b, 0.0, 392.0, 0.16, 0.16)
	_brass(b, 0.13, 523.25, 0.16, 0.16)
	_brass(b, 0.26, 659.25, 0.16, 0.16)
	_brass(b, 0.39, 783.99, 0.2, 1.2, 0.012)
	_brass(b, 0.39, 523.25, 0.1, 1.2)
	_brass(b, 0.39, 659.25, 0.08, 1.2)
	_bell(b, 0.39, 1568.0, 0.1, 4.0, 1.0)
	_bell(b, 0.5, 2093.0, 0.07, 5.0, 0.9)
	return b


static func _defeat() -> PackedFloat32Array:
	var b := _buf(1.5)
	var notes := [[0.0, 392.0, 0.4], [0.36, 311.13, 0.4], [0.72, 261.63, 0.78]]
	for nd: Array in notes:
		var i0 := int(float(nd[0]) * RATE)
		var dur: float = nd[2]
		var f0: float = nd[1]
		var phase := 0.0
		for i in mini(int(dur * RATE), b.size() - i0):
			var t := float(i) / RATE
			var f := f0 * (1.0 - 0.03 * t if nd == notes[2] else 1.0)
			phase += TAU * f / RATE
			var env := minf(1.0, t * 25.0) * exp(-t * 2.6)
			var v := sin(phase) + sin(phase * 3.0) / 9.0 + sin(phase * 5.0) / 25.0
			b[i0 + i] += v * env * 0.32
	return b
