extends SceneTree
## Prints what the first-days bot in tests/unit/test_playthrough.gd does with each summon
## luck: stages cleared, hours of game time, retries and sessions per stage.
##   tools/gd --headless --path . -s tests/tools/playthrough_report.gd [-- stages=10]

const Playthrough := preload("res://tests/unit/test_playthrough.gd")


func _init() -> void:
	var target := Playthrough.CHAPTER_1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("stages="):
			target = int(a.substr(7))
	var bot = Playthrough.new()
	for mode in ["spends gems", "first session", "cautious (no gem summons)"]:
		print("== %s, target %d stages" % [mode, target])
		for luck in Playthrough.LUCK:
			var r: Dictionary
			match mode:
				"spends gems":
					r = bot.play(luck, target, 24 * 10)
				"first session":
					r = bot.play(luck, target, 0)
				_:
					r = bot.play(luck, target, 24 * 10, false)
			print("luck %8d  cleared %2d  hours %3d  longest wait %2d h  battles %3d" % [
				luck, r.cleared, r.hours, r.longest_wait_h, r.battles])
			print("    tries    %s" % _row(r.attempts, r.cleared))
			print("    sessions %s" % _row(r.sessions, r.cleared))
			if not (r.problems as Array).is_empty():
				print("    PROBLEMS %s" % str(r.problems))
	quit()


func _row(d: Dictionary, n: int) -> String:
	var parts: PackedStringArray = []
	for i in mini(n + 1, d.size()):
		parts.append("%d" % int(d.get(i, 0)))
	return " ".join(parts)
