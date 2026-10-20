extends SceneTree
## Regenerates the golden fixtures in data/fixtures/ from the current rules and data:
##   tools/gd --headless --path . -s tests/tools/make_fixtures.gd [-- battles summon ...]
## (no names = every file in tests/golden.gd FILES). Prints each file's size and the battle
## coverage (event kinds, flags, statuses, passives), then re-reads every file and checks it.
##
## When to regenerate: only after an INTENDED change that alters results: battle rules, hero
## kits or stats, stage data (e.g. tests/tools/calibrate_stages.gd write), economy numbers,
## RNG use, or the fixture inputs in tests/golden.gd. If tests/unit/test_fixtures.gd fails
## after a refactor that should not change behavior, fix the code instead. Review the diff
## (git diff --stat data/fixtures) and mention it in the change: a Unity port verifies
## itself against these files.

const Golden := preload("res://tests/golden.gd")
const JsonPretty := preload("res://tests/tools/json_pretty.gd")


func _init() -> void:
	var names: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if Golden.FILES.has(a):
			names.append(a)
	if names.is_empty():
		names = Golden.FILES
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/fixtures"))
	var ok := true
	for n in names:
		var path := "res://data/fixtures/%s.json" % n
		var fx: Dictionary = Golden.normalize(Golden.build(n))
		if not JsonPretty.write(path, fx):
			ok = false
			continue
		var text := FileAccess.get_file_as_string(path)
		var stored: Variant = GameData.intify(JSON.parse_string(text))
		var d := Golden.diff(stored, Golden.normalize(Golden.compute(n, stored)))
		print("%-12s %8d bytes  %s" % [n, text.length(), "ok" if d == "" else "NOT REPRODUCIBLE: " + d])
		ok = ok and d == ""
		if n == "battles":
			_coverage(fx)
	quit(0 if ok else 1)


## What the battle fixtures exercise, so a port's battle code is fully covered.
func _coverage(fx: Dictionary) -> void:
	var kinds := {}
	var flags := {}
	var statuses := {}
	var passives := {}
	var skills := {}
	for b in fx.battles:
		var stars := {}
		for u in b.setup.allies + b.setup.enemies:
			stars[u.uid] = int(u.stars)
			for p in HeroKits.active_passives(str(u.hero_id), int(u.stars), int(u.get("awaken", 0))):
				for e in p.effects:
					passives[e.type] = true
		for e in b.events:
			kinds[e.type] = int(kinds.get(e.type, 0)) + 1
			for k in ["crit", "advantage", "from_ultimate", "dot", "execute", "timeout"]:
				if e.get(k, false) == true:
					flags[k] = int(flags.get(k, 0)) + 1
			if e.type == "status":
				statuses[e.status] = true
			if e.type == "ultimate":
				skills[e.skill_id] = true
		print("  %-20s %3d steps, %4d events, winner %s" % [b.name, int(b.steps), b.events.size(), b.outcome.winner])
	print("  event kinds: ", kinds)
	print("  flags: ", flags)
	print("  statuses applied (%d/9): %s" % [statuses.size(), statuses.keys()])
	print("  passive effect types active (%d): %s" % [passives.size(), passives.keys()])
	print("  ultimates cast (%d/15): %s" % [skills.size(), skills.keys()])
