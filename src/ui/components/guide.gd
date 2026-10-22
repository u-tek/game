class_name Guide
extends Control
## First-session guidance: a printer's proof mark on the one control a new player should tap next
## (style v4: the poster is a proof, the guide its editor): a loose loop in red grease pencil drawn
## round it (it draws itself on, overshooting where it closes, a little different on every
## control), and a hand-drawn arrow nudging toward it. No dialogs, nothing blocks input; it simply
## goes quiet once the player is past chapter 1.
##
##   Guide.step()                              # "claim" | "summon" | "formation" | "battle"
##                                             # | "level" | "quests" | ""
##   Guide.mark(button, Guide.step() == "claim")   # add or remove the highlight
##
## The order follows the first session: claim the free quick claim, summon (free daily pull,
## then a 10-pull with the starting scrolls), fill the team (Auto-fill when slots are empty or
## stronger heroes sit on the bench), fight 1-1, level up after the first win (and whenever
## the team is under the recommended power), claim finished quests, then keep fighting.
## Screens call mark() from their refresh (Game.changed); main.gd marks the nav tabs.
## The mark is a child of the target laid over it (it re-places itself every frame, so a
## Container target works too).

const KitBox := preload("res://src/ui/components/kit_box.gd")
const MARK_NAME := "GuideMark"
## The guide is quiet once this many stages are cleared (end of chapter 1).
const ACTIVE_UNTIL_CLEARED := 10
## "battle" (the Battle / Fight / Next Stage highlight) is suggested for the first stages only.
const BATTLE_POINTER_UNTIL := 3
## After this many level-ups the guide only suggests leveling when the team is underpowered.
const LEVEL_UPS_TAUGHT := 5
## Auto-fill is suggested when the best five heroes are this much stronger (percent).
const BENCH_GAIN_PCT := 3

## Grease pencil: the signal red, a touch darker, slightly translucent like wax on paper.
const COLOR := Color(0.86, 0.2, 0.08)

## Show the bobbing arrow (the ring always shows).
var arrow := true
## Arrow side: -1 above the target pointing down, 1 below it pointing up.
var arrow_side := -1
var _t := 0.0
## The loop's character (seeded by the target's name so each control gets its own hand).
var _seed := 0.0


## The next suggested action for a new player ("" = no suggestion).
static func step() -> String:
	var g := Kit.autoload("Game")
	if g == null or not g.has_method("cleared_count"):
		return ""
	var state: Variant = g.get("state")
	if not (state is Dictionary) or (state as Dictionary).is_empty():
		return ""
	var cleared: int = g.cleared_count()
	if cleared >= ACTIVE_UNTIL_CLEARED:
		return ""
	# 1. The free quick claim: two hours of gold and EXP right away.
	var idle: Dictionary = g.idle_status()
	if int(g.counter("quick_claims")) == 0 and int(g.counter("idle_claims")) == 0 \
			and int(idle.get("quick_claim_cost", -1)) == 0 and int(idle.get("quick_claims_left", 0)) > 0:
		return "claim"
	# 2. Summon: the free daily pull, or a full 10-pull of scrolls.
	var banner: Dictionary = g.banner()
	if g.free_pull_available() or int(g.currency("scrolls")) >= int(banner.get("scroll_cost_ten", 10)):
		return "summon"
	# 3. Team: empty slots while heroes wait on the bench, or a clearly stronger bench.
	if formation_can_improve():
		return "formation"
	# 4. The very first fight.
	if cleared == 0:
		return "battle"
	# 5. Level up: right after the first wins, and whenever the team is under the
	#    recommended power of the next stage.
	var st: Dictionary = g.current_stage()
	var under: bool = not st.is_empty() and int(g.team_power()) < int(st.get("recommended_power", 0))
	if int(g.counter("level_ups")) < LEVEL_UPS_TAUGHT or under:
		if level_target() != "":
			return "level"
	# 6. Finished quests.
	if int(g.quests_ready_count()) > 0:
		return "quests"
	# 7. Keep fighting (only pointed at for the first stages).
	if cleared < BATTLE_POINTER_UNTIL and not st.is_empty():
		return "battle"
	return ""


## True when Auto-fill would clearly help: an empty slot with a benched hero available, or
## the best five owned heroes are BENCH_GAIN_PCT stronger than the current five.
static func formation_can_improve() -> bool:
	var g := Kit.autoload("Game")
	if g == null:
		return false
	var f: Array = g.formation()
	var filled := 0
	var current := 0
	for id: Variant in f:
		if str(id) != "":
			filled += 1
			current += int(g.hero_power(str(id)))
	var owned: Array = g.owned_heroes()
	if filled < 5 and owned.size() > filled:
		return true
	var powers: Array[int] = []
	for h: Variant in owned:
		powers.append(int(g.hero_power(str((h as Dictionary).get("id", "")))))
	powers.sort()
	powers.reverse()
	var best := 0
	for i in mini(5, powers.size()):
		best += powers[i]
	return best * 100 > current * (100 + BENCH_GAIN_PCT)


## The formation hero the guide suggests leveling: the lowest level one that can level now.
static func level_target() -> String:
	var g := Kit.autoload("Game")
	if g == null:
		return ""
	var best := ""
	var best_lv := 1 << 30
	for id: Variant in g.formation():
		var hid := str(id)
		if hid == "" or int(g.affordable_levels(hid)) <= 0:
			continue
		var lv := int(g.hero(hid).get("level", 1))
		if lv < best_lv:
			best_lv = lv
			best = hid
	return best


## True when the guide wants `hero_id` leveled now: a team hero that can level and is at most
## two levels above the lowest team hero that can (so levels spread over the team in short
## bursts instead of one tap per hero).
static func should_level(hero_id: String) -> bool:
	var g := Kit.autoload("Game")
	if g == null or step() != "level":
		return false
	if not g.formation().has(hero_id) or int(g.affordable_levels(hero_id)) <= 0:
		return false
	var low := level_target()
	if low == "":
		return false
	return int(g.hero(hero_id).get("level", 1)) <= int(g.hero(low).get("level", 1)) + 2


## Adds (on = true) or removes the highlight on `target`. Safe to call on every refresh.
## arrow_side: -1 = arrow above pointing down, 1 = arrow below pointing up, 0 = ring only.
static func mark(target: Control, on: bool, arrow_side: int = -1) -> void:
	if target == null or not is_instance_valid(target):
		return
	var cur := target.get_node_or_null(MARK_NAME)
	if not on:
		if cur:
			cur.name = MARK_NAME + "_gone"
			cur.queue_free()
		return
	if cur:
		return
	var g := Guide.new()
	g.name = MARK_NAME
	g.arrow = arrow_side != 0
	g.arrow_side = -1 if arrow_side == 0 else arrow_side
	target.add_child(g)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	offset_left = -6
	offset_top = -6
	offset_right = 6
	offset_bottom = 6
	# No z_index: a raised mark would draw over popups. As the target's last child it
	# already draws over the target itself.
	var host := get_parent()
	_seed = float(absi(hash(str(host.name) if host else "mark")) % 1000) / 1000.0


func _process(delta: float) -> void:
	_t += delta
	var host := get_parent() as Control
	if host is Container:
		# Containers lay their children out; keep the mark around the whole target anyway.
		position = Vector2(-6, -6)
		size = host.size + Vector2(12, 12)
	queue_redraw()


func _draw() -> void:
	# Drawn on over 0.45 s, then a slow breath (the wax catches the light).
	var on := clampf(_t / 0.45, 0.0, 1.0) if Kit.motion_ok() else 1.0
	var breathe := 0.82 + 0.18 * sin(_t * 2.6)
	var col := Color(COLOR, 0.9 * breathe)
	var host := get_parent() as Control
	var c := size * 0.5
	var r := size * 0.5 + Vector2(10, 9)
	if host and host.has_meta("guide_hex"):
		var hv: Vector2 = host.get_meta("guide_hex")
		c = Vector2(host.size.x * 0.5, hv.x) - position
		r = Vector2(hv.y + 12.0, hv.y + 12.0)
	_loop(c, r, on, col)
	if arrow and on >= 1.0:
		_pencil_arrow(c, r, col)


## A loose pencil loop round c with radii r: a wobbly ellipse that starts a little inside, runs
## round once and overshoots past where it began (as a hand draws it), the nib heavier mid-stroke.
func _loop(c: Vector2, r: Vector2, on: float, col: Color) -> void:
	var n := 64
	var turns := 1.12
	var a0 := -2.2 + _seed * 1.4
	var pts := PackedVector2Array()
	var last := int(n * on)
	for i in last + 1:
		var t := float(i) / n
		var a := a0 + t * TAU * turns
		var wob := 1.0 + 0.045 * sin(a * 3.0 + _seed * 9.0) + 0.03 * sin(a * 5.0 + _seed * 4.0)
		var drift := 1.0 + 0.06 * t
		pts.append(c + Vector2(cos(a) * r.x * wob * drift, sin(a) * r.y * wob * drift))
	for i in pts.size() - 1:
		var t := float(i) / n
		var w := 2.2 + 2.2 * sin(PI * clampf(t / turns, 0.0, 1.0))
		draw_line(pts[i], pts[i + 1], col, w, true)


## A short hand-drawn arrow off the loop's top right (or bottom, for marks below), nudging in.
func _pencil_arrow(c: Vector2, r: Vector2, col: Color) -> void:
	var nudge := absf(sin(_t * 3.2)) * 6.0 if Kit.motion_ok() else 0.0
	var dir := Vector2(-0.6, 1.0).normalized() if arrow_side < 0 else Vector2(-0.6, -1.0).normalized()
	var tip := c + Vector2(r.x * 0.62, -r.y * 0.98 if arrow_side < 0 else r.y * 0.98) - dir * (6.0 + nudge)
	var tail := tip - dir * 54.0 + Vector2(10, 0)
	var mid := (tip + tail) * 0.5 + dir.orthogonal() * 8.0
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(tail.lerp(mid, t).lerp(mid.lerp(tip, t), t))
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], col, 3.0, true)
	var back := -dir
	draw_line(tip, tip + back.rotated(0.5) * 16.0, col, 3.4, true)
	draw_line(tip, tip + back.rotated(-0.5) * 16.0, col, 3.4, true)
