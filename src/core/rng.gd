class_name SeededRng
extends RefCounted
## The game's only random number generator: xorshift32 (Marsaglia's 13/17/5 triple) on an
## explicit 32-bit state, seeded through a 31-bit integer hash. Battles, summons and gear drops
## use it, never RandomNumberGenerator or randi(), so the same seed gives the same sequence on
## every device and in any language. Reference outputs: tests/unit/test_rng.gd and
## data/fixtures/rng.json. Port notes (with C#): docs/dev/unity-port.md.
##
## All values are non-negative and below 2^32, so GDScript's 64-bit signed ints never overflow
## here (the largest intermediate is a 31-bit by 32-bit product, < 2^63). In C# use ulong for
## the state and the hash, long for seeds.
##
##   mix(a, b):                         a, b: signed 64-bit; ">>" on a is arithmetic
##     h = (a & 0x7FFFFFFF) ^ ((a >> 31) & 0x7FFFFFFF)
##     h = (h * 0x9E3779B1) & 0xFFFFFFFF
##     h = h ^ (b & 0x7FFFFFFF)
##     h = ((h & 0x7FFFFFFF) * 0x85EBCA77) & 0xFFFFFFFF
##     h = h ^ (h >> 15)
##     h = ((h & 0x7FFFFFFF) * 0xC2B2AE3D) & 0xFFFFFFFF
##     h = h ^ (h >> 13)
##     return h & 0x7FFFFFFF                                  -> 0 .. 2^31-1
##   seeding:  s = mix(seed, 0x2545F491); if s == 0: s = 0x6D2B79F5; then next_u32() x3 (discarded)
##   next_u32: x = s; x = (x ^ (x << 13)) & 0xFFFFFFFF; x = x ^ (x >> 17);
##             x = (x ^ (x << 5)) & 0xFFFFFFFF; s = x; return x  -> 1 .. 2^32-1
##   range_int(lo, hi): hi <= lo -> lo (no draw); else lo + next_u32() % (hi - lo + 1)
##   chance_bp(bp):     bp <= 0 -> false, bp >= 10000 -> true (no draw); else next_u32() % 10000 < bp
##   pick(arr):         arr[next_u32() % arr.size()]

const MASK := 0xFFFFFFFF

var _s: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_s = mix(seed_value, 0x2545F491)
	if _s == 0:
		_s = 0x6D2B79F5
	for i in 3:
		next_u32()


## Hash two ints into a well-spread 31-bit seed (stable on every platform). Used to derive
## independent streams, e.g. mix(save_seed, pull_count).
static func mix(a: int, b: int) -> int:
	var h := (a & 0x7FFFFFFF) ^ ((a >> 31) & 0x7FFFFFFF)
	h = ((h & 0x7FFFFFFF) * 0x9E3779B1) & MASK
	h ^= (b & 0x7FFFFFFF)
	h = ((h & 0x7FFFFFFF) * 0x85EBCA77) & MASK
	h ^= h >> 15
	h = ((h & 0x7FFFFFFF) * 0xC2B2AE3D) & MASK
	h ^= h >> 13
	return h & 0x7FFFFFFF


## Next raw value, 1 .. 2^32-1.
func next_u32() -> int:
	var x := _s
	x = (x ^ (x << 13)) & MASK
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & MASK
	_s = x
	return x


## Uniform int in [lo, hi] (inclusive). No draw when hi <= lo.
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


## True with probability bp / 10000. No draw when bp <= 0 or bp >= 10000.
func chance_bp(bp: int) -> bool:
	if bp <= 0:
		return false
	if bp >= 10000:
		return true
	return next_u32() % 10000 < bp


## Random element of a non-empty array.
func pick(arr: Array) -> Variant:
	return arr[next_u32() % arr.size()]
