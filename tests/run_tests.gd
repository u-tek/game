extends SceneTree
## Headless test runner:
##   godot --headless --path . --import          (once, after adding files)
##   godot --headless --path . -s tests/run_tests.gd [-- name_filter]
## Every tests/unit/test_*.gd script (extends RefCounted) is loaded; each method whose
## name starts with "test_" is called with a TestCtx. Exit code 1 on any failure.

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests/unit"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			failed.append("%s: failed to load (parse error?)" % f)
			continue
		var inst = script.new()
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + name).contains(filter):
				continue
			var t := TestCtx.new()
			t.current = f.get_basename() + "." + name
			inst.call(name, t)
			total += 1
			failed.append_array(t.failures)
		if inst is Node:
			inst.free()
	for msg in failed:
		printerr("FAIL ", msg)
	print("%d tests, %d failures" % [total, failed.size()])
	quit(1 if failed.size() > 0 else 0)
