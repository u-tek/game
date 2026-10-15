extends RefCounted
## An efficient free player, used by the balance tools (not shipped). Four short sessions a
## day (9:00, 13:00, 19:00, 23:00): claim idle and the free quick claim, the daily gift and
## free pull, summon with every scroll and with gems in 10-pulls, auto-arrange the team,
## star up when at least half the shards are there (dust covers the rest), level the team
## evenly, do the daily quests.
##
##   var bot = preload("res://tests/tools/pacing_bot.gd").new()
##   bot.start()
##   bot.goto_session(day, session_index)   # moves the clock
##   bot.economy()                           # everything except fighting
##   bot.push(2)                             # fight the next stages until 2 losses

const HOUR := 3600000
const DAY_START_MS := 1_702_080_000_000 # 00:00 UTC
const SESSIONS_H: Array[int] = [9, 13, 19, 23]

var g: Node


## luck: picks the summon / drop seeds, so several bots see different pulls.
func start(luck: int = 0) -> void:
	g = load("res://src/core/game.gd").new()
	g.save_path = ""
	g.tz_bias_ms = 0
	g.now_override_ms = DAY_START_MS + 9 * HOUR
	g.new_game()
	if luck != 0:
		g.state.summon.seed = SeededRng.mix(luck, 9001)
		g.state.rng_seed = SeededRng.mix(luck, 4242)


func finish() -> void:
	g.free()


## Hours of play since the very first session (day 0, 9:00).
static func session_hour(day: int, session: int) -> int:
	return day * 24 + SESSIONS_H[session] - SESSIONS_H[0]


func goto_session(day: int, session: int) -> void:
	g.now_override_ms = DAY_START_MS + (day * 24 + SESSIONS_H[session]) * HOUR


func economy(first_session: bool = false) -> void:
	g.claim_idle()
	if g.idle_status().quick_claim_cost == 0:
		g.quick_claim()
	g.buy_offer("daily_gift")
	if g.free_pull_available():
		g.summon(1, true)
	while g.currency("scrolls") >= 10:
		g.summon(10)
	while g.currency("scrolls") >= 1:
		g.summon(1)
	while g.currency("gems") >= 2700:
		g.summon(10)
	if first_session:
		while g.currency("gems") >= 300:
			g.summon(1)
	g.auto_formation()
	for h in g.owned_heroes():
		while g.can_star_up(h.id):
			var c: Dictionary = g.star_up_cost(h.id)
			if int(c.shards_have) * 2 < int(c.shards):
				break
			g.star_up(h.id)
	level_team()
	claim_quests()


func claim_quests() -> void:
	for pass_i in 2:
		for q in g.quests():
			if q.ready:
				g.claim_quest(q.id)


## Raise the lowest formation hero one level at a time while resources last.
func level_team() -> void:
	for guard in 5000:
		var low := ""
		var low_lv := 1 << 30
		for id in g.formation():
			if id != "" and int(g.hero(id).level) < low_lv and not g.level_up_cost(id).is_empty():
				low = id
				low_lv = int(g.hero(id).level)
		if low == "" or not g.level_up(low).ok:
			return


## Fight the next stages until `max_losses` losses; then replay a cleared stage for the
## "win 3 battles" quest. Returns stages cleared this call.
func push(max_losses: int = 2) -> int:
	var losses := 0
	var cleared := 0
	while losses < max_losses and not g.current_stage().is_empty():
		var i: int = g.cleared_count()
		var out := BattleSim.new(g.stage_battle_setup(i)).run_to_end()
		g.complete_stage(i, out)
		if out.victory:
			cleared += 1
			level_team()
		else:
			losses += 1
	replay_for_quests()
	return cleared


func replay_for_quests() -> void:
	for n in 5:
		var q: Dictionary = {}
		for x in g.quests():
			if x.id == "dq_win":
				q = x
		if q.is_empty() or q.ready or q.claimed or g.cleared_count() == 0:
			break
		var j: int = g.cleared_count() - 1
		g.complete_stage(j, BattleSim.new(g.stage_battle_setup(j)).run_to_end())
	claim_quests()


## The current formation: {level (average), stars {id: n}, gear [[GearItem]...] by power,
## power, heroes [ids]}.
func snapshot() -> Dictionary:
	var ids: Array = []
	var lv := 0
	var stars := {}
	var gear_sets: Array = []
	for id in g.formation():
		if id == "":
			continue
		ids.append(id)
		var h: Dictionary = g.hero(id)
		lv += int(h.level)
		stars[id] = int(h.stars)
		var items: Array = []
		for slot in h.gear:
			items.append(g.gear_item(h.gear[slot]))
		gear_sets.append(items)
	gear_sets.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return {"level": lv / maxi(1, ids.size()), "stars": stars, "gear": gear_sets,
		"power": g.team_power(), "heroes": ids, "owned": g.owned_heroes().size()}


## Average stars of the owned heroes of one rarity (0 if none).
func avg_stars(rarity: String) -> int:
	var n := 0
	var total := 0
	for h in g.owned_heroes():
		if g.hero_def(h.id).rarity == rarity:
			n += 1
			total += int(h.stars)
	return total / n if n > 0 else 0
