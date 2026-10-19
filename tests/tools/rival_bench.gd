extends SceneTree
## Tuning (tool): how often a player's team beats the Rival at her strength. For players at a
## range of levels (a seeded roster, stars a little over the start, gear of the stage tier on the
## team), Rue is simulated for `days` days and fought, with and without her counter-pick. Prints
## the win rate per strength_bp so data/rival.json can aim at 65-75%.
##   tools/gd --headless --path . -s tests/tools/rival_bench.gd [-- 8000 9000 10000 ...]

const BASE_MS := 1_765_000_000_000
const DAY := 86400000
## [average level, stages cleared, days she has played]
const SCENARIOS := [[12, 8, 3], [20, 14, 7], [30, 22, 14], [42, 32, 21], [55, 44, 30], [70, 55, 45]]
const SEEDS := 24


func _init() -> void:
	var strengths: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			strengths.append(int(a))
	if strengths.is_empty():
		strengths = [9000, 10000, 11000, 12000]
	for sbp in strengths:
		RivalRules.STRENGTH_BP = sbp
		var line := "strength_bp %5d:" % sbp
		var all_w := 0
		var all_n := 0
		for sc: Array in SCENARIOS:
			var w := 0
			var n := 0
			for s in SEEDS:
				for fights: int in [0, 5]:
					var m := _player(s, int(sc[0]), int(sc[1]))
					_rue(m, s, int(sc[2]), fights)
					var setup := m.rival_battle_setup()
					var out := BattleSim.new(setup).run_to_end()
					if bool(out.victory):
						w += 1
					n += 1
			all_w += w
			all_n += n
			line += "  L%d %3d%%" % [int(sc[0]), w * 100 / n]
		print("%s   all %d%%" % [line, all_w * 100 / all_n])
	quit()


## A player at `level` with 8 seeded heroes, the best 5 in formation and geared.
func _player(s: int, level: int, cleared: int) -> GameModel:
	var m := GameModel.new()
	m.tz_bias_ms = 0
	var now := BASE_MS + s * 7919 * 1000
	m.clock = func() -> int: return now
	m.new_game()
	var rng := SeededRng.new(SeededRng.mix(s, level))
	var ids := HeroData.ids()
	var pool: Array = []
	for id in ids:
		pool.append(id)
	m.state.heroes = {}
	for i in 8:
		var k := rng.range_int(0, pool.size() - 1)
		var id: String = pool[k]
		pool.remove_at(k)
		m.add_hero(id)
		var h: Dictionary = m.state.heroes[id]
		h.stars = mini(int(h.stars) + rng.range_int(0, 1 + level / 30), EconomyData.MAX_STARS)
		h.level = clampi(level + rng.range_int(-3, 3), 1, Progression.level_cap(int(h.stars)))
	m.state.campaign.cleared = cleared
	m.state.gear = []
	m.auto_formation()
	var tier := EconomyData.gear_tier_for(cleared)
	for id in m.formation():
		if id == "":
			continue
		for slot in EconomyData.GEAR_SLOTS:
			m.create_gear(slot, tier)
	m._auto_equip_team()
	return m


## Rue after `days` days of pulls (a day at a time, so nothing is skipped), with `fights` fights.
func _rue(m: GameModel, s: int, days: int, fights: int) -> void:
	var rs: Dictionary = m.state.rival
	rs.seed = SeededRng.mix(s, 4242)
	var today := m.today()
	var owns := {}
	for id in m.state.heroes:
		owns[id] = true
	rs.day = today - days - 1
	for d in range(today - days, today + 1):
		RivalRules.catch_up(rs, d, EconomyData.BANNER_EPOCH_DAY, owns)
	rs.fights = fights
