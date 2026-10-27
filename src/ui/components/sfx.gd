extends RefCounted
## Procedural sound effects (no audio files). UI.sfx(name) plays these.
## Every sound is synthesized once into a 16-bit mono AudioStreamWAV.
## Names: tap, tab, pop, close, deny, toggle, coin, sparkle (UI feel), reward, summon,
## legendary, hit, ult, victory, defeat; the summon sequence (src/ui/summon/) adds portal
## (the 2.7 s charge), tell / tell_big (the portal's rarity color tells), burst (the portal
## opening), reveal (a Rare hero), riser + beat (the held beat before a Legendary) and slam
## (the rarity word landing); the Lobby adds stamp (a real day stamped), pulse (her heartbeat)
## and rustle (a holiday decoration brushed on its thread); a reward's receipt adds printer (it feeds out
## of a thermal printer) and tear (torn off).

const RATE := 22050
const NAMES: Array[String] = ["tap", "tab", "pop", "deny", "toggle", "coin", "sparkle", "close", "hit", "reward",
	"ult", "summon", "victory", "defeat", "legendary",
	"portal", "tell", "tell_big", "burst", "reveal", "riser", "beat", "slam", "stamp", "pulse", "rustle",
	"printer", "tear"]


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
		"portal":
			s = _portal()
		"tell":
			s = _tell(false)
		"tell_big":
			s = _tell(true)
		"burst":
			s = _burst()
		"reveal":
			s = _reveal()
		"riser":
			s = _riser()
		"beat":
			s = _beat()
		"slam":
			s = _slam()
		"stamp":
			s = _stamp()
		"pulse":
			s = _pulse()
		"rustle":
			s = _rustle()
		"printer":
			s = _printer()
		"tear":
			s = _tear()
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


# ------------------------------------------------------------------ summon sequence

## Adds one-pole low-passed white noise. The cutoff goes alpha0 -> alpha1 over the sound;
## swell = fade in (pow(k, env_pow)), else fade out (pow(1 - k, env_pow)).
static func _noise_into(b: PackedFloat32Array, start: float, dur: float, amp: float, seed_v: int, alpha0: float, alpha1: float, env_pow: float, swell: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var lp := 0.0
	for i in n:
		var k := float(i) / maxf(float(n), 1.0)
		var env := pow(k, env_pow) if swell else pow(1.0 - k, env_pow)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(alpha0, alpha1, k)
		b[i0 + i] += lp * env * amp


## The portal charging (2.7 s): a low drone that climbs, a whoosh that opens up and a
## shimmer that grows; no hit at the end (the burst plays then).
static func _portal() -> PackedFloat32Array:
	var dur := 2.7
	var b := _buf(dur)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var f := 55.0 * pow(2.0, 1.4 * k * k)
		p1 += TAU * f / RATE
		p2 += TAU * f * 1.503 / RATE
		p3 += TAU * (900.0 + 1700.0 * k * k) / RATE
		var drone := (sin(p1) + 0.6 * sin(p2) + 0.25 * sin(p1 * 3.0)) * (0.25 + 0.55 * k)
		var shimmer := sin(p3) * (0.5 + 0.5 * sin(TAU * (8.0 + 18.0 * k) * t)) * 0.12 * k * k
		b[i] = (drone * 0.45 + shimmer) * minf(1.0, t * 6.0)
	_noise_into(b, 0.0, dur, 0.75, 71, 0.015, 0.4, 1.8, true)
	for k in 6:
		_bell(b, 0.4 + 0.36 * k, 1046.5 * pow(2.0, float(k) / 6.0), 0.035 + 0.012 * k, 6.0, 0.5)
	return b


## The portal's rarity tell: a shimmering chord (Epic), or a brass swell with sparkle (big:
## Legendary).
static func _tell(big: bool) -> PackedFloat32Array:
	var b := _buf(1.2 if big else 0.8)
	_noise_into(b, 0.0, 0.18, 0.35, 83, 0.05, 0.5, 2.0, true)
	if big:
		_brass(b, 0.12, 392.0, 0.14, 0.95, 0.01)
		_brass(b, 0.12, 587.33, 0.1, 0.95, 0.01)
		_brass(b, 0.12, 783.99, 0.09, 0.95, 0.01)
		var sparkle := [1568.0, 2093.0, 2637.0, 3136.0, 4186.0]
		for k in sparkle.size():
			_bell(b, 0.14 + 0.06 * k, sparkle[k], 0.09, 6.0, 0.6)
	else:
		var chord := [880.0, 1108.73, 1318.51, 1760.0]
		for k in chord.size():
			_bell(b, 0.12 + 0.045 * k, chord[k], 0.12, 5.0, 0.6)
	return b


## The portal opening: a deep boom, a blast of air and a bright ring.
static func _burst() -> PackedFloat32Array:
	var b := _buf(1.1)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (38.0 + 110.0 * exp(-t * 14.0)) / RATE
		b[i] += sin(phase) * exp(-t * 4.5) * 0.85
	_noise_into(b, 0.0, 0.9, 0.9, 97, 0.6, 0.04, 2.2, false)
	_bell(b, 0.02, 2637.0, 0.1, 5.0, 0.9)
	_bell(b, 0.05, 3520.0, 0.07, 6.0, 0.8)
	return b


## A Rare hero landing: a quick whoosh and a two-note chime.
static func _reveal() -> PackedFloat32Array:
	var b := _buf(0.55)
	_noise_into(b, 0.0, 0.16, 0.5, 103, 0.08, 0.6, 1.5, true)
	_bell(b, 0.1, 1567.98, 0.2, 7.0, 0.45)
	_bell(b, 0.16, 2349.32, 0.15, 8.0, 0.39)
	return b


## The held beat before a Legendary: a rising tone and swelling air, cut off at the top.
static func _riser() -> PackedFloat32Array:
	var dur := 1.35
	var b := _buf(dur)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		phase += TAU * (180.0 * pow(2.0, 2.8 * k)) / RATE
		b[i] = (sin(phase) + 0.4 * sin(phase * 2.0) + 0.2 * sin(phase * 3.0)) * k * k * 0.22
	_noise_into(b, 0.0, dur, 0.7, 109, 0.02, 0.5, 2.5, true)
	return b


## A heartbeat thump (two low beats).
static func _beat() -> PackedFloat32Array:
	var b := _buf(0.4)
	for start: float in [0.0, 0.15]:
		var i0 := int(start * RATE)
		var phase := 0.0
		var amp := 0.9 if start == 0.0 else 0.6
		for i in mini(int(0.22 * RATE), b.size() - i0):
			var t := float(i) / RATE
			phase += TAU * (48.0 + 40.0 * exp(-t * 30.0)) / RATE
			b[i0 + i] += sin(phase) * exp(-t * 16.0) * amp * minf(1.0, t * 300.0)
	return b


## A rubber stamp coming down on paper: a dull low thud and the paper's short slap.
static func _stamp() -> PackedFloat32Array:
	var b := _buf(0.28)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (64.0 + 60.0 * exp(-t * 45.0)) / RATE
		# (harmonics so a phone's small speaker still hears the thud)
		b[i] += (sin(phase) + 0.35 * sin(phase * 2.0) + 0.18 * sin(phase * 3.0)) * exp(-t * 30.0) * 0.65 * minf(1.0, t * 600.0)
	_noise_into(b, 0.0, 0.045, 0.5, 211, 0.55, 0.12, 3.0, false)
	_noise_into(b, 0.012, 0.06, 0.18, 223, 0.08, 0.04, 2.0, false)
	return b


## Her pulse under a thumb: a soft, low lub-dub, felt more than heard.
static func _pulse() -> PackedFloat32Array:
	var b := _buf(0.36)
	for start: float in [0.0, 0.15]:
		var i0 := int(start * RATE)
		var phase := 0.0
		var amp := 0.7 if start == 0.0 else 0.4
		for i in mini(int(0.2 * RATE), b.size() - i0):
			var t := float(i) / RATE
			phase += TAU * (40.0 + 22.0 * exp(-t * 35.0)) / RATE
			b[i0 + i] += (sin(phase) + 0.3 * sin(phase * 3.0) + 0.12 * sin(phase * 5.0)) * exp(-t * 20.0) * amp * minf(1.0, t * 200.0)
	return b


## Cut paper brushed on its thread: a dry flutter of thin bright noise, a few quick flaps dying away.
static func _rustle() -> PackedFloat32Array:
	var b := _buf(0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 307
	var hp := 0.0
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1.0, 1.0)
		# High-passed (paper is all top end), flapped at ~19 Hz, dying away.
		hp = 0.86 * (hp + n - prev)
		prev = n
		var flap := 0.55 + 0.45 * sin(TAU * 19.0 * t + sin(TAU * 7.0 * t) * 1.5)
		b[i] = hp * flap * exp(-t * 11.0) * minf(1.0, t * 300.0) * 0.32
	return b


## The rarity word landing: a punchy low hit, a click and a short metallic ring.
static func _slam() -> PackedFloat32Array:
	var b := _buf(0.6)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (46.0 + 70.0 * exp(-t * 25.0)) / RATE
		b[i] += sin(phase) * exp(-t * 11.0) * 0.8
	_noise_into(b, 0.0, 0.08, 0.6, 113, 0.7, 0.2, 2.0, false)
	_bell(b, 0.0, 739.99, 0.1, 7.0, 0.55)
	_bell(b, 0.0, 1108.73 * 1.004, 0.08, 8.0, 0.5)
	_bell(b, 0.0, 1661.0, 0.05, 9.0, 0.45)
	return b


## A thermal receipt printer feeding a receipt: the stepper motor's buzz in short bursts, one a
## printed line (the paper steps), over the print head's faint hiss, stopping with the last line.
static func _printer() -> PackedFloat32Array:
	var dur := 0.9
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var lp := 0.0
	var ph := 0.0
	var lines := 13.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var lk := fmod(k * lines, 1.0)
		var gate := smoothstep(0.0, 0.06, lk) * (1.0 - smoothstep(0.55, 0.72, lk))
		var env := (0.25 + 0.75 * gate) * smoothstep(0.0, 0.02, k) * (1.0 - smoothstep(0.92, 1.0, k))
		ph += TAU * (196.0 + 24.0 * gate) / RATE
		var click := pow(maxf(sin(ph), 0.0), 10.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.45
		b[i] = (click * 0.55 * gate + lp * 0.16) * env
	return b


## Paper torn off against the printer's serrated edge: a quick dry rip, bright then gone.
static func _tear() -> PackedFloat32Array:
	var dur := 0.2
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 57
	var lp := 0.0
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		# The teeth: the noise comes in a fast flutter as the paper catches on each one.
		var teeth := 0.55 + 0.45 * absf(sin(TAU * 62.0 * t))
		var env := smoothstep(0.0, 0.05, k) * pow(1.0 - k, 1.6)
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.6
		var hp := lp - prev
		prev = lp
		b[i] = (hp * 1.4 + lp * 0.3) * env * teeth * 0.8
	return b
