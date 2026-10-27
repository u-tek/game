class_name WarFront
extends RefCounted
## The War for Souls as GameModel sees it: where each sector's line stands, where the player's souls
## go, and who the week's Champion is. GameModel talks to the war only through this; every screen goes
## through GameModel's views and actions (war(), district(), war_claim() ...), so a server drops in
## behind this one class.
##
## WarFront itself is the offline front: the other players are simulated on the phone (WarRules on
## the player's own souls log, `state.war.log`). A server front would extend it, answer the same calls
## from its last snapshot (refreshed in the background by the Game autoload, which then emits
## `changed`) and queue `post_souls` for upload. Rules stay in WarRules: integer maths, no Time or OS
## (docs/dev/unity-port.md 9d).

## The player's souls log ({day: {sector: souls}}), kept in the save.
var _log: Dictionary


func _init(souls_log: Dictionary) -> void:
	_log = souls_log


## Each sector's control on `day` of `week` (basis points, Heaven's line; WarRules.control), seen with
## the player's souls on `side`.
func control(week: int, day: int, side: String) -> Array:
	return WarRules.control(week, day, _log, side)


## Sends n of the player's souls (for `side`) to `sector` on `day`, and forgets days no claim can
## read any more (this week and the last are kept).
func post_souls(day: int, sector: int, _side: String, n: int) -> void:
	var dk := str(day)
	if not _log.has(dk):
		_log[dk] = {}
	var sk := str(sector)
	_log[dk][sk] = int((_log[dk] as Dictionary).get(sk, 0)) + n
	var keep_from := day - WarRules.LOG_DAYS
	for k: Variant in _log.keys():
		if int(str(k)) < keep_from:
			_log.erase(k)


## Souls the player sent from day `from_day` to `to_day` (both included).
func souls_between(from_day: int, to_day: int) -> int:
	var n := 0
	for k: Variant in _log.keys():
		var d := int(str(k))
		if d >= from_day and d <= to_day:
			for s: Variant in (_log[k] as Dictionary).values():
				n += int(s)
	return n


## True if the player sent souls on any day from `from_day` to `to_day`.
func fought_between(from_day: int, to_day: int) -> bool:
	for k: Variant in _log.keys():
		var d := int(str(k))
		if d >= from_day and d <= to_day:
			return true
	return false


## The other side's heroine who leads against `side` in `week` (WarRules.champion_for).
func champion(week: int, side: String) -> String:
	return WarRules.champion_for(week, side)
