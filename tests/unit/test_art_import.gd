extends RefCounted
## Hero paintings ship compressed (tools/art_lossy.py): every hero, skin and adult look's main art
## and portrait import as lossy WebP at 90%. Godot writes a lossless .import for new art, so this
## catches art installed without running the tool.

const ROOT := "res://assets/art/heroes"


func test_hero_paintings_import_lossy(t: TestCtx) -> void:
	var bad: Array[String] = []
	var n := _scan(ROOT, bad)
	t.ok(n > 40, "found the hero paintings (%d)" % n)
	t.ok(bad.is_empty(), "lossy imports: run python tools/art_lossy.py, then import (%d not lossy: %s)"
		% [bad.size(), ", ".join(bad.slice(0, 5))])


## Checks every painting .import under `dir`; returns how many it checked, appends the lossless ones.
func _scan(dir: String, bad: Array[String]) -> int:
	var n := 0
	var files := DirAccess.get_files_at(dir)
	for f: String in files:
		if not f.ends_with(".png.import"):
			continue
		var stem := f.trim_suffix(".png.import")
		var base := stem.trim_suffix("_portrait")
		if not files.has(base + ".warp.json"):
			continue
		n += 1
		var text := FileAccess.get_file_as_string(dir.path_join(f)).replace(char(13), "")
		if not ("\ncompress/mode=1\n" in text and "\ncompress/lossy_quality=0.9\n" in text):
			bad.append(dir.path_join(f).trim_prefix(ROOT + "/"))
	for d: String in DirAccess.get_directories_at(dir):
		n += _scan(dir.path_join(d), bad)
	return n
