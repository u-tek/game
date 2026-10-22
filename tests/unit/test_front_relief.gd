extends RefCounted
## The War map's relief (src/ui/v4/front_relief.gd): its data image and its label points agree, so a
## tap on a sector's line picks that sector.


func test_points_pick_their_sector(t: TestCtx) -> void:
	var r: Control = load("res://src/ui/v4/front_relief.gd").new()
	r.size = Vector2(652, 640)
	r._ready()
	var ok := true
	for s in 7:
		for k: float in [0.2, 0.5, 0.8]:
			var got: int = r.sector_at(r._at(s, k))
			if got != s:
				ok = false
				t.ok(false, "sector %d at depth %.1f picked %d" % [s, k, got])
	t.ok(ok, "every sector's line picks its sector")
	t.eq(r.sector_at(Vector2(2, 2)), -1, "off the slab picks nothing")
	r.free()
