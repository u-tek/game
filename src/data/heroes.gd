class_name HeroData
extends RefCounted
## The hero roster: identity fields (id, name, title, faction, role, rarity, bio, look) from
## res://data/heroes.json. Identity is set by the lead designer; each record in that file also
## carries the hero's combat kit, exposed by HeroKits. Game.hero_def(id) merges both.
## Roster order is meaningful (summon pools and lists follow it). Ids never change.

const IDENTITY_KEYS: Array[String] = ["id", "name", "title", "faction", "role", "rarity", "bio", "look"]

static var _roster: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func _ensure() -> void:
	if not _roster.is_empty():
		return
	for rec in GameData.dicts(GameData.heroes().get("heroes", [])):
		var ident := {}
		for k in IDENTITY_KEYS:
			ident[k] = str(rec.get(k, ""))
		_roster.append(ident)
		_by_id[ident.id] = ident


## Identity dictionaries in roster order.
static func all() -> Array[Dictionary]:
	_ensure()
	return _roster


## Identity of one hero, or {} if unknown.
static func get_def(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func ids() -> PackedStringArray:
	_ensure()
	var out := PackedStringArray()
	for h in _roster:
		out.append(h.id)
	return out
