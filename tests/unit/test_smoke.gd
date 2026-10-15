extends RefCounted

func test_roster_has_15_heroes(t: TestCtx) -> void:
	t.eq(HeroData.all().size(), 15)
