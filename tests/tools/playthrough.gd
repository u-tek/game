extends SceneTree
## Pacing check (tool, not a unit test): pacing bots (tests/tools/pacing_bot.gd) play freely
## for N days with different summon luck; prints stages cleared after every session of day 1
## and after every day, next to the target from calibrate_stages.gd's TIMELINE_H.
##   tools/gd --headless --path . -s tests/tools/playthrough.gd [-- days=10 bots=4]

const Bot := preload("res://tests/tools/pacing_bot.gd")
const Cal := preload("res://tests/tools/calibrate_stages.gd")


func _init() -> void:
	var days := 10
	var nbots := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="):
			days = int(a.substr(5))
		elif a.begins_with("bots="):
			nbots = int(a.substr(5))
	var bots: Array = []
	for b in nbots:
		var bot = Bot.new()
		bot.start(b * 11)
		bots.append(bot)
	print("when          target | " + " | ".join(range(nbots).map(func(b: int) -> String: return "bot %d (cleared, level, power)" % b)))
	for day in days:
		for s in Bot.SESSIONS_H.size():
			var row := ""
			for bot in bots:
				bot.goto_session(day, s)
				bot.economy(day == 0 and s == 0)
				bot.push(2)
				var snap: Dictionary = bot.snapshot()
				row += " | %2d  L%-2d p%-6d" % [bot.g.cleared_count(), snap.level, snap.power]
			if day == 0 or s == Bot.SESSIONS_H.size() - 1:
				var h: int = Bot.session_hour(day, s)
				print("day %2d %02d:00  %2d    %s" % [day + 1, Bot.SESSIONS_H[s], target(h), row])
	for bot in bots:
		bot.finish()
	quit()


## Stages the timeline expects cleared by hour h.
func target(h: int) -> int:
	var n := 0
	for t in Cal.TIMELINE_H:
		if t <= h:
			n += 1
	return n
