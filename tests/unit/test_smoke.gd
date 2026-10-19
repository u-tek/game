extends RefCounted

func test_roster_has_40_heroes(t: TestCtx) -> void:
	t.eq(HeroData.all().size(), 40)
