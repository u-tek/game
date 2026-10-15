extends RefCounted
## SeededRng is a portable xorshift32 (src/core/rng.gd, docs/dev/unity-port.md). These reference
## values come from an independent implementation of the documented algorithm; a port (C#,
## Python...) must reproduce them exactly. More cases: data/fixtures/rng.json.

## First 10 next_u32() outputs after SeededRng.new(12345).
const SEED_12345_FIRST_10: Array[int] = [
	1330226942, 157105557, 1930860194, 2576502307, 3667822344,
	1167049943, 532296189, 1764891359, 1733563019, 1168441641,
]


func test_reference_sequence_seed_12345(t: TestCtx) -> void:
	var rng := SeededRng.new(12345)
	var got: Array[int] = []
	for i in 10:
		got.append(rng.next_u32())
	t.eq(got, SEED_12345_FIRST_10, "xorshift32 reference sequence for seed 12345")


func test_mix_reference_values(t: TestCtx) -> void:
	t.eq(SeededRng.mix(12345, 0x2545F491), 1118729316, "seeding hash of 12345")
	t.eq(SeededRng.mix(-5, 7), 1799860516, "negative inputs use the arithmetic shift")
	t.eq(SeededRng.mix((1 << 40) + 3, -9), 641788327, "inputs wider than 32 bits fold in bits 31..61")


func test_outputs_stay_in_32_bits(t: TestCtx) -> void:
	for seed_value in [0, 1, -1, 12345, 0x7FFFFFFF, 1 << 40]:
		var rng := SeededRng.new(seed_value)
		for i in 200:
			var v := rng.next_u32()
			if v <= 0 or v > 0xFFFFFFFF:
				t.ok(false, "seed %d draw %d out of range: %d" % [seed_value, i, v])
				return
		t.ok(SeededRng.mix(seed_value, seed_value) >= 0 and SeededRng.mix(seed_value, seed_value) <= 0x7FFFFFFF)


func test_helpers_draw_rules(t: TestCtx) -> void:
	# range_int with hi <= lo and chance_bp at 0 / 10000 consume no draw.
	var a := SeededRng.new(77)
	var b := SeededRng.new(77)
	t.eq(a.range_int(5, 5), 5)
	t.eq(a.range_int(9, 3), 9)
	t.eq(a.chance_bp(0), false)
	t.eq(a.chance_bp(10000), true)
	t.eq(a.next_u32(), b.next_u32(), "no draws consumed by the degenerate cases")
	var c := SeededRng.new(4242)
	var d := SeededRng.new(4242)
	t.eq(c.range_int(10, 20), 10 + d.next_u32() % 11)
	t.eq(c.chance_bp(2500), d.next_u32() % 10000 < 2500)
	t.eq(c.pick(["a", "b", "c"]), ["a", "b", "c"][d.next_u32() % 3])
