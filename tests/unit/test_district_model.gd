extends RefCounted
## The district maquette (src/ui/v4/district_model.gd): its lot geometry agrees with itself and with
## the buildings' renders, so dragging lands where the finger is.


func _model() -> Control:
	var m: Control = load("res://src/ui/v4/district_model.gd").new()
	m.size = Vector2(652, 530)
	var bl: Array = []
	for i in DistrictRules.BUILDINGS.size():
		var b: Dictionary = DistrictRules.BUILDINGS[i]
		bl.append({"i": i, "open": true, "keeper": "", "doubled": false, "souls": int(b.souls), "spot": b.spot, "level": 1, "max_level": 5})
	m.set("dist", {"side": "heaven", "buildings": bl, "next": {}, "decor": [{"kind": "tree", "x": 1, "y": 2}]})
	m._ready()
	return m


func test_lots_round_trip(t: TestCtx) -> void:
	var m := _model()
	var ok := true
	for y in DistrictRules.GRID:
		for x in DistrictRules.GRID:
			var c: Vector2 = m._ground(x + 0.5, y + 0.5)
			if m._lot_at(c) != Vector2i(x, y):
				ok = false
	t.ok(ok, "every lot's middle maps back to that lot")
	t.eq(m._lots(m._ground(3, 2) - m._ground(1, 1)), Vector2i(2, 1), "a drag of two lots and one")
	m.free()


func test_feet_pick_their_buildings(t: TestCtx) -> void:
	var m := _model()
	# Some visible point of each building picks it (a foot may hide behind a taller one in front).
	var ok := true
	for i in DistrictRules.BUILDINGS.size():
		var hit := false
		for q: Vector2 in [m._foot(i) + Vector2(0, -6), m.roof_point(i) + Vector2(0, 6), m._foot(i).lerp(m.roof_point(i), 0.5)]:
			if m._building_at(q) == i:
				hit = true
		if not hit:
			ok = false
			t.ok(false, "building %d can't be picked" % i)
	t.ok(ok, "every building can be picked")
	t.eq(m._building_at(m._foot(3) + Vector2(0, -6)), 3, "the tree beside the baths doesn't take their taps")
	# A rendered foot agrees with the fitted grid (the lot's middle), within a few px.
	var b0: Dictionary = DistrictRules.BUILDINGS[0]
	var mid: Vector2 = m._ground(float(b0.spot[0]) + float(b0.w) * 0.5, float(b0.spot[1]) + float(b0.d) * 0.5)
	t.ok(m._foot(0).distance_to(mid) < 4.0, "the gate's foot sits at its lot's middle")
	t.ok(m._building_at(m._ground(1.5, 2.5) + Vector2(0, -4)) >= 1000, "the tree on lot 1, 2 is picked")
	m.free()
