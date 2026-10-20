extends SceneTree
## The boot screen's print run (headless): BootLoader loads the Lobby hero's rig files on worker
## threads (cached afterwards), the progress rule never runs ahead of the real work, the run lifts on
## its own once the work is done (no sooner than BootScreen.RUN, not much later), calls back and frees
## itself, and reduce motion makes it short. Exit code 1 on failure.
##   tools/gd --headless --path . -s tests/tools/boot_e2e.gd -- --fresh

# Loaded at run time: these use the autoloads, which a -s script's preloads would compile before.
var BootScreen: GDScript
var BootLoader: GDScript
var HomeScreen: GDScript

var _fails: Array[String] = []


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		printerr("E2E: timed out")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://src/main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	var game: Node = root.get_node("Game")
	BootScreen = load("res://src/ui/components/boot_screen.gd")
	BootLoader = load("res://src/ui/components/boot_loader.gd")
	HomeScreen = load("res://src/ui/screens/home_screen.gd")
	var consts := BootScreen.get_script_constant_map()
	var run_s := float(consts["RUN"])
	var exit_s := float(consts["EXIT"])

	# 1. The loader.
	var id: String = HomeScreen.call("lobby_hero")
	_check(id != "", "the Lobby has a hero")
	var look: String = Kit.hero_look(id)
	var files: Array[String] = BootLoader.call("rig_files", id, look)
	_check(files.size() >= 2, "her rig files are listed (%d)" % files.size())
	for f in files:
		_check(ResourceLoader.exists(f), "rig file exists: " + f)
	var bl: RefCounted = BootLoader.new()
	bl.call("start", id, look)
	var t0 := Time.get_ticks_msec()
	while not bool(bl.call("loaded")) and Time.get_ticks_msec() - t0 < 20000:
		var p := float(bl.call("progress"))
		_check(p >= 0.0 and p <= 1.0, "loader progress in 0..1 (%f)" % p)
		await process_frame
	_check(bool(bl.call("loaded")), "the threaded loads finish")
	for f in files:
		_check(ResourceLoader.has_cached(f), "cached after the loads: " + f)
	var steps: Array[Callable] = bl.call("steps")
	_check(steps.size() >= 3, "warm-up steps (%d)" % steps.size())
	for s in steps:
		s.call()

	# 2. The run: the rule waits for the work; the sheet lifts after the run, then frees itself.
	var boot: Control = BootScreen.new()
	boot.z_index = 200
	main.add_child(boot)
	boot.call("show_print", id, look)
	boot.call("set_progress", 0.3)
	var start := Time.get_ticks_msec()
	var ahead := 0.0
	while Time.get_ticks_msec() - start < 1500:
		await process_frame
		ahead = maxf(ahead, float(boot.get("_shown")) - 0.3)
	_check(ahead <= 0.0001, "the rule never runs ahead of the work (by %.3f)" % ahead)
	var called := [false]
	boot.call("finish", func() -> void: called[0] = true)
	while is_instance_valid(boot) and Time.get_ticks_msec() - start < 12000:
		await process_frame
	var secs := float(Time.get_ticks_msec() - start) / 1000.0
	_check(bool(called[0]), "finish() calls back as the sheet lifts")
	_check(not is_instance_valid(boot), "the boot screen frees itself")
	_check(secs >= run_s and secs <= run_s + exit_s + 1.5, "the run takes %.2f s" % secs)

	# 3. Reduce motion: the poster stands printed; done in about a second.
	game.call("set_setting", "reduce_motion", true)
	var b2: Control = BootScreen.new()
	main.add_child(b2)
	b2.call("set_progress", 1.0)
	var called2 := [false]
	b2.call("finish", func() -> void: called2[0] = true)
	var s2 := Time.get_ticks_msec()
	while is_instance_valid(b2) and Time.get_ticks_msec() - s2 < 6000:
		await process_frame
	var secs2 := float(Time.get_ticks_msec() - s2) / 1000.0
	_check(bool(called2[0]) and not is_instance_valid(b2), "reduce motion: lifts and frees itself")
	_check(secs2 < 2.0, "reduce motion: short (%.2f s)" % secs2)
	game.call("set_setting", "reduce_motion", false)

	for f in _fails:
		printerr("E2E FAIL ", f)
	print("E2E boot: run %.2f s, reduce motion %.2f s, %d failures" % [secs, secs2, _fails.size()])
	var ui: Node = root.get_node("UI")
	ui.call("release_audio")
	await create_timer(0.2).timeout
	quit(1 if _fails.size() > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok and not _fails.has(what):
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
