class_name GameData
extends RefCounted
## Loads the engine-neutral content under res://data/*.json: the single source of truth for
## heroes, kits, stages, economy, banner, quests, offers and battle tuning. Field-by-field
## schemas: docs/dev/unity-port.md. Each file is parsed once and cached; JSON numbers are
## turned back into ints (all game numbers are ints).
##
## The thin loaders (HeroData, HeroKits, StageData, EconomyData) sit on top of this and keep
## the names the rest of the code used before the data moved to JSON.
##
## Load-order rule: a `static var` initializer may call GameData (it depends on nothing) but
## never read another class's static vars. Classes reference each other in cycles (e.g.
## EconomyData -> GearRules -> StatCalc -> EconomyData), and Godot runs static initializers
## while loading, so a cross-class read can see a class that isn't initialized yet.

const DIR := "res://data/"

static var _cache: Dictionary = {}


## Parsed content of res://data/<file_name>.json ({} with an error if missing or invalid).
## Read-only (like the constants it replaces): duplicate(true) before changing a copy.
static func file(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := DIR + file_name + ".json"
	var data: Variant = null
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK:
			data = intify(json.data)
		else:
			push_error("GameData: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
	else:
		push_error("GameData: missing %s" % path)
	var d: Dictionary = data if data is Dictionary else {}
	freeze(d)
	_cache[file_name] = d
	return d


## Makes a parsed JSON value read-only, recursively.
static func freeze(v: Variant) -> void:
	if v is Dictionary:
		for k in v:
			freeze(v[k])
		(v as Dictionary).make_read_only()
	elif v is Array:
		for x in v:
			freeze(x)
		(v as Array).make_read_only()


static func heroes() -> Dictionary:
	return file("heroes")


static func stages() -> Dictionary:
	return file("stages")


static func economy() -> Dictionary:
	return file("economy")


static func banner() -> Dictionary:
	return file("banner")


static func quests() -> Dictionary:
	return file("quests")


static func offers() -> Dictionary:
	return file("offers")


static func battle() -> Dictionary:
	return file("battle")


static func skins() -> Dictionary:
	return file("skins")


static func tower() -> Dictionary:
	return file("tower")


## The campaign worlds' presentation (planet codes and flavour readouts; no rules).
static func worlds() -> Dictionary:
	return file("worlds")


## JSON numbers parse as floats: turn whole numbers back into ints, recursively.
static func intify(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = intify(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(intify(x))
		return a
	return v


## Typed copies of JSON arrays (GDScript typed arrays can't take an untyped Array directly).
static func strings(a: Variant) -> Array[String]:
	var out: Array[String] = []
	if a is Array:
		for x in a:
			out.append(str(x))
	return out


static func ints(a: Variant) -> Array[int]:
	var out: Array[int] = []
	if a is Array:
		for x in a:
			out.append(int(x))
	return out


static func dicts(a: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if a is Array:
		for x in a:
			if x is Dictionary:
				out.append(x)
	return out
