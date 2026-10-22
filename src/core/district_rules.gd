class_name DistrictRules
extends RefCounted
## The player's district (the War for Souls, docs/dev/combat-v1.md): the souls they win settle in a
## quarter on their side of the front. Buildings open as the lifetime soul count grows; each adds a
## small bonus to one idle rate; an owned heroine can keep a building, and a keeper of the side's
## faction doubles its bonus. Pure functions on data/district.json; the side, souls and keepers are
## passed in (GameModel). Port spec: docs/dev/unity-port.md section 9e. Fixture: data/fixtures/war.json.
##
##   open(souls)          = the indices of buildings with souls >= building.souls (data order)
##   kept_mult(side, f)   = keeper_mult_bp when faction f is in keeper_factions[side], else 10000
##   bonus(side, souls, keepers) = {currency: bp}: for each open building i, its bonus_bp, times
##                          kept_mult(side, keepers[i]'s faction) / 10000 when it has a keeper
##                          (keepers: {"<i>": hero_id}), summed per currency
##   apply(rates, bonus)  = each rate * (10000 + bonus[currency]) / 10000

static var _d: Dictionary = GameData.file("district")
static var BUILDINGS: Array = _d.buildings
static var KEEPER_MULT_BP: int = int(_d.keeper_mult_bp)


static func quarter_name(side: String) -> String:
	return str((_d.names as Dictionary).get(side, ""))


static func open(souls: int) -> Array[int]:
	var out: Array[int] = []
	for i in BUILDINGS.size():
		if souls >= int((BUILDINGS[i] as Dictionary).souls):
			out.append(i)
	return out


static func kept_mult(side: String, faction: String) -> int:
	var fs: Array = (_d.keeper_factions as Dictionary).get(side, [])
	return KEEPER_MULT_BP if fs.has(faction) else 10000


## The idle bonus per currency (bp). keepers: {"<building index>": hero_id}.
static func bonus(side: String, souls: int, keepers: Dictionary) -> Dictionary:
	var out := {}
	if side == "":
		return out
	for i in open(souls):
		var b: Dictionary = BUILDINGS[i]
		var bp := int(b.bonus_bp)
		var hid := str(keepers.get(str(i), ""))
		if hid != "":
			bp = bp * kept_mult(side, str(HeroData.get_def(hid).get("faction", ""))) / 10000
		var c := str(b.currency)
		out[c] = int(out.get(c, 0)) + bp
	return out


## Idle rates with the district's bonus.
static func apply(rates: Dictionary, bonus_bp: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in rates:
		out[k] = int(rates[k]) * (10000 + int(bonus_bp.get(str(k), 0))) / 10000
	return out
