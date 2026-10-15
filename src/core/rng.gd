class_name SeededRng
extends RefCounted
## Small deterministic RNG (xorshift32) owned by the game rules, so battles, summons and
## drops replay identically on every device for the same seed. All math stays inside
## 32 bits, so it never depends on 64-bit overflow behaviour.

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


## Hash two ints into a well-spread 31-bit seed (stable on every platform).
static func mix(a: int, b: int) -> int:
	var h := (a & 0x7FFFFFFF) ^ ((a >> 31) & 0x7FFFFFFF)
	h = ((h & 0x7FFFFFFF) * 0x9E3779B1) & MASK
	h ^= (b & 0x7FFFFFFF)
	h = ((h & 0x7FFFFFFF) * 0x85EBCA77) & MASK
	h ^= h >> 15
	h = ((h & 0x7FFFFFFF) * 0xC2B2AE3D) & MASK
	h ^= h >> 13
	return h & 0x7FFFFFFF


## Stable string hash (djb2 variant, 31 bits).
static func hash_str(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h * 33) ^ s.unicode_at(i)) & 0x7FFFFFFF
	return h


func next_u32() -> int:
	var x := _s
	x = (x ^ (x << 13)) & MASK
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & MASK
	_s = x
	return x


## Uniform int in [lo, hi] (inclusive).
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


## True with probability bp / 10000.
func chance_bp(bp: int) -> bool:
	if bp <= 0:
		return false
	if bp >= 10000:
		return true
	return next_u32() % 10000 < bp


## Random element of a non-empty array.
func pick(arr: Array) -> Variant:
	return arr[next_u32() % arr.size()]
