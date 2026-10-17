class_name SkinData
extends RefCounted
## Cosmetic hero skins from res://data/skins.json (design: docs/dev/skins.md): id, hero, line,
## tier, name, description and art (the folder under assets/art/heroes/<hero>/skins/). Cosmetic
## only: a skin never changes stats. The price comes from the skin's tier (price_gems).

static var _all: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func _ensure() -> void:
	if not _all.is_empty():
		return
	var tiers: Dictionary = GameData.skins().get("tiers", {})
	for rec in GameData.dicts(GameData.skins().get("skins", [])):
		var tier_id := str(rec.get("tier", ""))
		var s := {
			"id": str(rec.get("id", "")),
			"hero": str(rec.get("hero", "")),
			"line": str(rec.get("line", "")),
			"tier": tier_id,
			"name": str(rec.get("name", "")),
			"description": str(rec.get("description", "")),
			"art": str(rec.get("art", "")),
			"price_gems": int((tiers.get(tier_id, {}) as Dictionary).get("price_gems", 0)),
		}
		s.make_read_only()
		_all.append(s)
		_by_id[s.id] = s


## Every skin, in file order (grouped by hero).
static func all() -> Array[Dictionary]:
	_ensure()
	return _all


## One skin, or {} if unknown.
static func get_def(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


## The skins of one hero, in file order.
static func for_hero(hero_id: String) -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for s in _all:
		if s.hero == hero_id:
			out.append(s)
	return out


## Display names of the skin lines ("aqua_resort" -> "Aqua Resort"), in file order.
static func lines() -> Dictionary:
	var out := {}
	var ls: Dictionary = GameData.skins().get("lines", {})
	for k in ls:
		out[str(k)] = str((ls[k] as Dictionary).get("name", k))
	return out


static func tier_name(tier_id: String) -> String:
	return str((GameData.skins().get("tiers", {}) as Dictionary).get(tier_id, {}).get("name", tier_id))
