extends RefCounted
## Lobby speech lines (home screen speech bubble), loaded from lobby_lines.json next to this
## file: 2-3 short in-character lines per hero, plus fallback lines for heroes without any.
## Plain JSON so a later port (or data/) can reuse the content as is.
##   const LobbyLines := preload("res://src/ui/battle/lobby_lines.gd")
##   LobbyLines.lines("seraphiel") -> Array[String]

const PATH := "res://src/ui/battle/lobby_lines.json"

static var _data: Dictionary = {}


## Every line for a hero (never empty: falls back to the generic lines).
static func lines(hero_id: String) -> Array[String]:
	_load()
	var out: Array[String] = []
	var all: Variant = _data.get("lines", {})
	var mine: Variant = (all as Dictionary).get(hero_id, []) if all is Dictionary else []
	if mine is Array:
		for l: Variant in mine:
			out.append(str(l))
	if out.is_empty():
		var fb: Variant = _data.get("fallback", [])
		if fb is Array:
			for l: Variant in fb:
				out.append(str(l))
	if out.is_empty():
		out.append("...")
	return out


## What she says after a long hold on her (the heartbeat).
static func pulse_lines() -> Array[String]:
	_load()
	var out: Array[String] = []
	var p: Variant = _data.get("pulse", [])
	if p is Array:
		for l: Variant in p:
			out.append(str(l))
	if out.is_empty():
		out.append("...")
	return out


static func _load() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("LobbyLines: cannot read %s" % PATH)
		_data = {"lines": {}}
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	_data = j if j is Dictionary else {"lines": {}}
