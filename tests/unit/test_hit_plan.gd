extends RefCounted
## A blow's plan (src/ui/battle/hit_plan.gd): the camera's blows stop, flip and knock at 1x and keep
## only the print at 4x; blows off the camera print smaller and quieter; Reduce motion keeps nothing
## that moves; the governor never flips more than 3 a second, even at 4x with the whole field hitting;
## nothing is printed on a heroine and only the blows she feels make her react; signal is the camera's
## crit's alone (a cross, not the ultimate's crown); the Champion's crits keep their slab, not the stop.

const HitPlan := preload("res://src/ui/battle/hit_plan.gd")


func _ctx(speed: int, focus: bool, now: int, gov: Dictionary, motion: bool = true) -> Dictionary:
	return {"speed": speed, "focus": focus, "now": now, "gov": gov, "motion": motion, "champion": false}


func test_the_camera_blow_at_each_speed(t: TestCtx) -> void:
	var hit := {"kind": "melee", "dst_uid": "e1"}
	var p1 := HitPlan.plan(hit, _ctx(1, true, 0, HitPlan.new_gov()))
	t.eq(str(p1.impress), "slash", "a melee blow prints a stroke")
	t.eq(int(p1.flip), 2, "1x: two impact frames")
	t.near(float(p1.stop), 0.033, 0.001, "1x: a micro stop")
	t.ok(float(p1.knock) > 0.0, "1x: a knock")
	t.eq(str(p1.sounds[0][0]), "press", "a platen's press")
	var p4 := HitPlan.plan(hit, _ctx(4, true, 0, HitPlan.new_gov()))
	t.eq(int(p4.flip), 0, "4x: no impact frame on a basic blow")
	t.eq(float(p4.stop), 0.0, "4x: no stop")
	t.eq((p4.frames as Array).size(), 4, "4x: four frames of the print")
	var pr := HitPlan.plan({"kind": "ranged", "dst_uid": "e1"}, _ctx(1, true, 0, HitPlan.new_gov()))
	t.eq(str(pr.impress), "splat", "a shot prints a splat")
	t.eq(str(pr.sounds[0][0]), "splat", "and sounds like one")


func test_off_the_camera(t: TestCtx) -> void:
	var on := HitPlan.plan({"kind": "melee", "dst_uid": "e1"}, _ctx(1, true, 0, HitPlan.new_gov()))
	var off := HitPlan.plan({"kind": "melee", "dst_uid": "e1"}, _ctx(1, false, 0, HitPlan.new_gov()))
	t.ok(float(off.size) < float(on.size), "smaller")
	t.eq(float(off.stop), 0.0, "no stop")
	t.eq(int(off.flip), 0, "no impact frame")
	t.ok(float(off.sounds[0][2]) < 0.0, "quieter")
	t.ok((off.haptic as Array).is_empty(), "no haptic")


func test_reduce_motion(t: TestCtx) -> void:
	for crit in [false, true]:
		var p := HitPlan.plan({"kind": "melee", "crit": crit, "kill": true, "dst_uid": "e1"}, _ctx(1, true, 0, HitPlan.new_gov(), false))
		t.eq(float(p.stop), 0.0, "no stop (crit %s)" % crit)
		t.eq(int(p.flip), 0, "no impact frame")
		t.eq(float(p.knock), 0.0, "no knock")
		t.eq(float(p.kick) + float(p.thump), 0.0, "no kick")
		t.eq(p.frames, [5], "the print fades in at its last frame")


func test_flips_governed_at_4x(t: TestCtx) -> void:
	var gov := HitPlan.new_gov()
	var flips: Array[int] = []
	# The whole field hitting at 4x for three seconds: a blow every 25 ms on five foes, every third a crit.
	for i in 120:
		var now := i * 25
		var p := HitPlan.plan({"kind": "melee", "crit": i % 3 == 0, "dst_uid": "e%d" % (i % 5)}, _ctx(4, true, now, gov))
		if int(p.flip) > 0:
			flips.append(now)
	var worst := 0
	for a in flips:
		var n := 0
		for b in flips:
			if b >= a and b < a + 1000:
				n += 1
		worst = maxi(worst, n)
	t.ok(worst <= HitPlan.FLIPS_PER_S, "at most %d impact frames in any second (got %d)" % [HitPlan.FLIPS_PER_S, worst])
	t.ok(flips.size() > 0, "crits still flip")


func test_one_unit_flip_gap(t: TestCtx) -> void:
	var gov := HitPlan.new_gov()
	var a := HitPlan.plan({"kind": "melee", "dst_uid": "e1"}, _ctx(1, true, 0, gov))
	var b := HitPlan.plan({"kind": "melee", "dst_uid": "e1"}, _ctx(1, true, 100, gov))
	var c := HitPlan.plan({"kind": "melee", "dst_uid": "e1"}, _ctx(1, true, 400, gov))
	t.eq(int(a.flip), 2, "the first flips")
	t.eq(int(b.flip), 0, "100 ms later: not on the same foe")
	t.eq(int(c.flip), 2, "past the gap it flips again")


func test_on_a_heroine(t: TestCtx) -> void:
	var gov := HitPlan.new_gov()
	var p := HitPlan.plan({"kind": "melee", "on_ally": true, "heavy_bp": 200, "dst_uid": "a1"}, _ctx(1, false, 0, gov))
	t.eq(str(p.impress), "", "nothing printed on her painting")
	var light := HitPlan.plan({"kind": "melee", "on_ally": true, "heavy_bp": 200, "dst_uid": "a1"}, _ctx(2, false, 0, gov))
	t.eq(str(light.impress), "", "2x: a light blow leaves no print")
	var heavy := HitPlan.plan({"kind": "melee", "on_ally": true, "heavy_bp": 900, "dst_uid": "a1"}, _ctx(1, false, 0, gov))
	t.ok(bool(heavy.jolt), "a heavy blow jolts her")
	var again := HitPlan.plan({"kind": "melee", "on_ally": true, "heavy_bp": 900, "dst_uid": "a1"}, _ctx(1, false, 500, gov))
	t.ok(not bool(again.jolt), "not twice in 1.2 s")


func test_champion_crits(t: TestCtx) -> void:
	var ctx := _ctx(1, true, 0, HitPlan.new_gov())
	ctx.champion = true
	var p := HitPlan.plan({"kind": "melee", "crit": true, "dst_uid": "boss"}, ctx)
	t.ok(bool(p.slab), "the number keeps its slab")
	t.eq(float(p.stop), 0.0, "no stop: the whole team crits all the time")
	t.eq(str(p.impress), "slash", "the normal stroke, not the crown")


func test_signal_once(t: TestCtx) -> void:
	var mine := HitPlan.plan({"kind": "melee", "crit": true, "dst_uid": "e1"}, _ctx(1, true, 0, HitPlan.new_gov()))
	t.eq(str(mine.impress), "cross", "a crit crosses her (the crown is the ultimate's)")
	t.eq(mine.back, HitPlan.SIG, "the camera's crit: its second plate in signal")
	t.ok(bool(mine.slab), "and its slab")
	var other := HitPlan.plan({"kind": "melee", "crit": true, "dst_uid": "e2"}, _ctx(1, false, 0, HitPlan.new_gov()))
	t.eq(other.back, HitPlan.INK, "another heroine's crit: ink")
	t.ok(not bool(other.slab), "no slab")
	t.ok(other.flip_light != HitPlan.SIG, "no signal in its impact frame")
	var adv := HitPlan.plan({"kind": "melee", "adv": true, "dst_uid": "e3"}, _ctx(1, true, 0, HitPlan.new_gov()))
	t.eq(adv.back, HitPlan.INK, "an advantage hit only clacks")


func test_nothing_printed_on_her(t: TestCtx) -> void:
	for crit in [false, true]:
		var p := HitPlan.plan({"kind": "melee", "on_ally": true, "crit": crit, "heavy_bp": 900, "dst_uid": "a1"}, _ctx(1, true, 0, HitPlan.new_gov()))
		t.eq(str(p.impress), "", "no print on her painting (crit %s)" % crit)
	var light := HitPlan.plan({"kind": "melee", "on_ally": true, "heavy_bp": 100, "dst_uid": "a1"}, _ctx(1, true, 0, HitPlan.new_gov()))
	t.ok(not bool(light.react), "a light blow: no flinch, no ink dip")
	t.eq(float(light.knock), 0.0, "and no knock")
