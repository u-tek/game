extends RefCounted
## The battle's numbers (src/ui/battle/galley.gd): place() keeps every box inside the field and off
## the others and the tags, dropping what has no room; blows on one foe merge into her tally inside
## the window and start a new one after; a crit by the camera's heroine gets its slab and shows once;
## a fallen foe's tally freezes; numbers lift after their hold.

const Galley := preload("res://src/ui/battle/galley.gd")


func test_place_inside_and_apart(t: TestCtx) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var area := Rect2(12, 150, 696, 900)
	var keep := [Rect2(300, 400, 120, 27)]
	for round_i in 20:
		var items: Array = []
		for i in 30:
			items.append({"box": Rect2(Vector2(rng.randf_range(-80, 760), rng.randf_range(100, 1100)), Vector2(rng.randf_range(40, 160), rng.randf_range(24, 56))),
				"pri": rng.randi_range(0, 6)})
		var out := Galley.place(items, area, keep)
		var placed: Array[Rect2] = []
		for r: Variant in out:
			if r == null:
				continue
			var b := r as Rect2
			t.ok(area.encloses(b), "round %d: inside the field" % round_i)
			t.ok(not b.intersects(keep[0]), "round %d: off the tag" % round_i)
			for q in placed:
				t.ok(not q.intersects(b), "round %d: no two overlap" % round_i)
			placed.append(b)
		t.ok(placed.size() > 0, "round %d: something placed" % round_i)


func test_place_keeps_priorities(t: TestCtx) -> void:
	# Two boxes fighting for one slot in a field with room for one: the higher priority wins.
	var area := Rect2(0, 0, 100, 40)
	var out := Galley.place([{"box": Rect2(0, 0, 100, 40), "pri": 1}, {"box": Rect2(0, 0, 100, 40), "pri": 5}], area, [])
	t.eq(out[0], null, "the lower one is dropped")
	t.ok(out[1] != null, "the higher one stays")


func test_merge_window(t: TestCtx) -> void:
	var g := Galley.new()
	g.hit("e1", 100, false)
	g._process(0.2)
	g.hit("e1", 50, false)
	t.eq(g.hits_on("e1"), 2, "inside the window: one tally")
	t.eq(int(g._tally.e1.total), 150, "summed")
	g._process(Galley.MERGE_S + 0.05)
	g.hit("e1", 70, false)
	t.eq(g.hits_on("e1"), 1, "past the window: a new tally")
	t.eq(int(g._tally.e1.total), 70, "started again")
	g.free()


func test_crit_slab_once(t: TestCtx) -> void:
	var g := Galley.new()
	g.hit("e1", 900, false, true, false, "", false, true)
	t.ok(g._slab.has("e1"), "the camera's crit: a slab")
	t.ok(bool(g._tally.e1.slab_only), "a lone crit shows only on its slab")
	g.hit("e1", 100, false)
	t.ok(not bool(g._tally.e1.slab_only), "a second blow: the tally shows too")
	g.hit("e2", 900, false, true, false, "", false, false)
	t.ok(not g._slab.has("e2"), "another heroine's crit: no slab")
	t.ok(bool(g._tally.e2.crit), "it marks the tally")
	g.free()


func test_ko_and_lift(t: TestCtx) -> void:
	var g := Galley.new()
	g.hit("e1", 100, false)
	g.ko("e1")
	g.hit("e1", 40, false)
	t.eq(int(g._tally.e1.total), 40, "a fallen foe's tally is not added to")
	g.hit("a1", 30, true)
	t.eq(g._slip.size(), 1, "a blow on a heroine: her slip")
	t.ok(g.count() > 0, "numbers up")
	for i in 40:
		g._process(0.05)
	t.eq(g.count(), 0, "all lifted after their hold")
	g.free()
