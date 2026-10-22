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
##   level_bonus(bp, L)   = bp * (L + 1) / 2 (a built building is level 1; MAX_LEVEL is x3)
##   upgrade_cost(i, L)   = {"gold": GOLD_BASE * L * L * (10000 + COST_STEP_BP * i) / 10000} to go from
##                          L to L + 1, {} at MAX_LEVEL
##   bonus(side, souls, keepers, levels) uses level_bonus(bonus_bp, levels["<i>"] or 1) before the
##                          keeper's multiplier
##   spot(i, layout)      = layout["<i>"] ([x, y]) if the player moved it, else the building's data spot
##   can_place(layout, i, x, y) = building i's w x d footprint at lot (x, y) lies inside the GRID x GRID
##                          quarter, off the road row (ROAD_ROW) and on no other building's footprint
##                          (every building holds its lot, built or not) and on no prop (decor)
##   can_decorate(layout, decor, x, y, skip = -1) = lot (x, y) is inside the quarter, off the road
##                          row, under no building and holds no other prop (decor[k] = [kind, x, y];
##                          skip: the prop being moved)
##   decor_price(kind)    = its gold price (0 when unknown)

static var _d: Dictionary = GameData.file("district")
static var BUILDINGS: Array = _d.buildings
static var KEEPER_MULT_BP: int = int(_d.keeper_mult_bp)
static var MAX_LEVEL: int = int(_d.levels.max)
static var GOLD_BASE: int = int(_d.levels.gold_base)
static var COST_STEP_BP: int = int(_d.levels.cost_step_bp)
static var GRID: int = int(_d.grid.size)
static var ROAD_ROW: int = int(_d.grid.road_row)


static func spot(i: int, layout: Dictionary) -> Vector2i:
	var v: Variant = layout.get(str(i), null)
	if v is Array and (v as Array).size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	var s: Array = (BUILDINGS[i] as Dictionary).spot
	return Vector2i(int(s[0]), int(s[1]))


static var DECOR_MAX: int = int(_d.decor.max)
static var DECOR_REFUND_BP: int = int(_d.decor.refund_bp)
static var DECOR_KINDS: Array = _d.decor.kinds


static func decor_price(kind: String) -> int:
	for k: Dictionary in DECOR_KINDS:
		if str(k.id) == kind:
			return int(k.gold)
	return 0


static func can_decorate(layout: Dictionary, decor: Array, x: int, y: int, skip: int = -1) -> bool:
	if x < 0 or y < 0 or x >= GRID or y >= GRID or y == ROAD_ROW:
		return false
	for j in BUILDINGS.size():
		var o: Dictionary = BUILDINGS[j]
		var s := spot(j, layout)
		if x >= s.x and x < s.x + int(o.w) and y >= s.y and y < s.y + int(o.d):
			return false
	for k in decor.size():
		var p: Array = decor[k]
		if k != skip and int(p[1]) == x and int(p[2]) == y:
			return false
	return true


static func can_place(layout: Dictionary, i: int, x: int, y: int, decor: Array = []) -> bool:
	if i < 0 or i >= BUILDINGS.size():
		return false
	var b: Dictionary = BUILDINGS[i]
	var w := int(b.w)
	var d := int(b.d)
	if x < 0 or y < 0 or x + w > GRID or y + d > GRID:
		return false
	if y <= ROAD_ROW and ROAD_ROW < y + d:
		return false
	for j in BUILDINGS.size():
		if j == i:
			continue
		var o: Dictionary = BUILDINGS[j]
		var s := spot(j, layout)
		if x < s.x + int(o.w) and s.x < x + w and y < s.y + int(o.d) and s.y < y + d:
			return false
	for p: Array in decor:
		if int(p[1]) >= x and int(p[1]) < x + w and int(p[2]) >= y and int(p[2]) < y + d:
			return false
	return true


static func level_bonus(bonus_bp: int, level: int) -> int:
	return bonus_bp * (clampi(level, 1, MAX_LEVEL) + 1) / 2


static func upgrade_cost(i: int, level: int) -> Dictionary:
	if level >= MAX_LEVEL or i < 0 or i >= BUILDINGS.size():
		return {}
	return {"gold": GOLD_BASE * level * level * (10000 + COST_STEP_BP * i) / 10000}


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


## The idle bonus per currency (bp). keepers: {"<building index>": hero_id}; levels: {"<i>": level}.
static func bonus(side: String, souls: int, keepers: Dictionary, levels: Dictionary = {}) -> Dictionary:
	var out := {}
	if side == "":
		return out
	for i in open(souls):
		var b: Dictionary = BUILDINGS[i]
		var bp := level_bonus(int(b.bonus_bp), int(levels.get(str(i), 1)))
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
