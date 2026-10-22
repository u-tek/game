extends RefCounted
## Shared stage helpers for the campaign, tower and battle screens: counter-faction math,
## power verdicts and a stage's enemies by slot.
##   const StageInfo := preload("res://src/ui/battle/stage_info.gd")

const SHORT_RED := Color("ff6a50")


## The faction that beats `faction` on the counter wheel ("" if none).
static func counter_of(faction: String) -> String:
	for f: String in BattleSim.BEATS:
		if str(BattleSim.BEATS[f]) == faction:
			return f
	return ""


## {faction: count} of a stage's enemies.
static func enemy_factions(st: Dictionary) -> Dictionary:
	var out := {}
	for e: Dictionary in st.get("enemies", []):
		var f := str(Game.hero_def(str(e.hero_id)).get("faction", ""))
		out[f] = int(out.get(f, 0)) + 1
	return out


## Most common enemy faction of a stage.
static func main_faction(st: Dictionary) -> String:
	var counts := enemy_factions(st)
	var best := str(st.get("enemy_faction", ""))
	var best_n := -1
	for f: String in ["celestial", "infernal", "fallen"]:
		if int(counts.get(f, 0)) > best_n:
			best_n = int(counts.get(f, 0))
			best = f
	return best


## {faction: count} in the player's formation.
static func team_factions() -> Dictionary:
	var out := {}
	for id: String in Game.formation():
		if id == "":
			continue
		var f := str(Game.hero_def(id).get("faction", ""))
		out[f] = int(out.get(f, 0)) + 1
	return out


## [label, color] comparing team power with the recommendation (colors for dark chrome).
static func verdict(team: int, rec: int) -> Array:
	if rec <= 0 or team * 100 >= rec * 130:
		return ["Easy", Kit.GOOD]
	if team >= rec:
		return ["Fair", Kit.GOOD]
	if team * 100 >= rec * 85:
		return ["Tough", Kit.ORANGE_HI]
	return ["Very hard", SHORT_RED]


## verdict() with darker colors that read on white panels.
static func verdict_light(team: int, rec: int) -> Array:
	var v := verdict(team, rec)
	var c: Color = v[1]
	if c == Kit.GOOD:
		c = Color("1f9e63")
	elif c == Kit.ORANGE_HI:
		c = Color("d9790f")
	else:
		c = Color("d63a24")
	return [v[0], c]


## Enemies of a stage as a 5-slot array (slot index -> enemy, {} = empty).
static func enemy_slots(st: Dictionary) -> Array:
	var out: Array = [{}, {}, {}, {}, {}]
	for e: Dictionary in st.get("enemies", []):
		var s := int(e.slot)
		if s >= 0 and s < 5:
			out[s] = e
	return out
