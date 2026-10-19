extends Control
## One hero's reveal in the summon sequence: a full-screen splash of the animated hero
## (HeroArt.make_sprite with the equipped skin) with the rarity word, name, title, faction,
## role, stars and NEW / shards, all timed from one clock so a tap can fast-forward it.
##
## Rarity sets the drama:
##   Rare       snappy (0.7 s): a white pop, the hero slides in from the right, text follows.
##   Epic       a short held beat (a violet orb, the hero's dark silhouette), then a burst:
##              flash, shockwave, rays snap open, the silhouette floods with color, "EPIC"
##              slams in.
##   Legendary  a long held beat (1.35 s: the screen darkens, a golden orb pulses like a
##              heartbeat while light pours into it, a backlit silhouette), then the big burst:
##              full white-gold flash, double shockwave, golden rain, the hero forms out of
##              golden light (a gold-white glow that cools into her colors) with a slow
##              push-in, and "LEGENDARY" slams down.
##
## The sequence (summon_sequence.gd) owns it: start() begins the clock, tap() fast-forwards
## (held beat -> burst -> settled) and returns true once settled (= next hero), leave()
## slides it out and frees it. Screen-wide effects go out through the fx signal:
## ("flash", color, alpha), ("shake", _, trauma), ("tint", color, amount), ("darken", _, k).

signal fx(kind: String, color: Color, amount: float)
## Emitted once when every element has landed (the "tap to continue" hint can show).
signal landed

const Fx := preload("res://src/ui/summon/summon_fx.gd")
const Burst := preload("res://src/ui/summon/summon_burst.gd")
const Banner := preload("res://src/ui/summon/rarity_banner.gd")

## Burst time (end of the held beat) per rarity.
const BEAT := {"rare": 0.0, "epic": 0.6, "legendary": 1.35}
## Element start times after the burst: banner, name, title, badges, tag; then settle.
const SCHEDULE := {
	"rare": [0.06, 0.1, 0.16, 0.2, 0.28, 0.66],
	"epic": [0.12, 0.32, 0.4, 0.46, 0.58, 1.0],
	"legendary": [0.38, 0.72, 0.82, 0.9, 1.06, 1.6],
}
const ROW_DUR := 0.32
const SLAM_DUR := 0.38
const PULSES := [0.12, 0.55, 0.95]
const BANNER_SIZE := {"rare": 64, "epic": 92, "legendary": 100}
const RAY_COUNT := {"rare": 10, "epic": 14, "legendary": 18}
const TINT := {"rare": 0.35, "epic": 0.55, "legendary": 0.7}
const BACK_GLOW := {"rare": 0.22, "epic": 0.38, "legendary": 0.5}

var hero_id := ""
var rarity := "rare"
var result: Dictionary = {}
var safe_top := 0.0
var safe_bottom := 0.0
var settled := false
## Screenshots: the clock stops at this time (< 0 = never).
var hold := -1.0

var _def: Dictionary = {}
var _color := Color.WHITE
var _t := 0.0
var _running := false
var _burst_t := 0.0
var _settle_t := 0.7
var _sched: Array = []
var _events: Array[Array] = []
var _next_event := 0

var _rays: Control
var _front: Control
var _front_drawn := false
var _emblem: Control
var _shade: Control
var _anchor: Node2D
var _sprite: HeroSprite
var _fig_h := 900.0
var _feet := Vector2.ZERO
var _chest := Vector2.ZERO
var _sparkles: CPUParticles2D
var _rain: CPUParticles2D

var _banner: Control
var _name: Label
var _title: Label
var _badges: Control
var _tag: Control
var _rows: Array[Control] = []
var _row_pos: Array[Vector2] = []

# Last tint values pushed to the rig (only push changes).
var _tint_cache := {}
# Orb motes: angle, phase, size.
var _motes := PackedFloat32Array()
var _quad := PackedVector2Array()
var _qcol := PackedColorArray()


## res: one entry of Game.summon's results ({hero_id, rarity, is_new, shards, dust}).
## stars: the hero's star count to show. skin: the skin id for the art ("" = base look).
func setup(res: Dictionary, stars: int, skin: String, top_inset: float, bottom_inset: float) -> void:
	result = res
	hero_id = str(res.get("hero_id", ""))
	_def = Game.hero_def(hero_id)
	rarity = str(res.get("rarity", _def.get("rarity", "rare")))
	if not BEAT.has(rarity):
		rarity = "rare"
	_color = Kit.rarity_color(rarity)
	safe_top = top_inset
	safe_bottom = bottom_inset
	_burst_t = float(BEAT[rarity])
	_sched = SCHEDULE[rarity]
	_settle_t = _burst_t + float(_sched[5])
	name = "Reveal_" + hero_id
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_quad.resize(4)
	_qcol.resize(4)
	_motes.resize(28 * 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hero_id)
	for i in 28:
		_motes[i * 3] = rng.randf() * TAU
		_motes[i * 3 + 1] = rng.randf()
		_motes[i * 3 + 2] = rng.randf_range(6.0, 16.0)
	_build(stars, skin)
	_build_events()
	_apply()


func _ready() -> void:
	# This control's own drawing (glows, the orb) is additive; children draw normally.
	material = Fx.additive()


# ------------------------------------------------------------------ build

func _build(stars: int, skin: String) -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(720, 1280)
	var w := vp.x
	var h := vp.y
	var faction := str(_def.get("faction", "celestial"))
	_feet = Vector2(w * 0.56, h - safe_bottom - 150.0)
	_fig_h = maxf(400.0, _feet.y - (safe_top + 92.0))
	_chest = Vector2(_feet.x, _feet.y - _fig_h * 0.64)

	# Rays and a faint faction emblem behind the hero.
	_rays = Kit.rays(_color.lerp(Color.WHITE, 0.15), w * 2.3, int(RAY_COUNT[rarity]))
	_rays.position = _chest - _rays.size * 0.5
	_rays.set("speed", 0.12)
	_rays.modulate.a = 0.0
	add_child(_rays)
	_emblem = Kit.faction_icon(faction, w * 0.78)
	_emblem.size = _emblem.custom_minimum_size
	_emblem.position = Vector2(w * 0.5, _chest.y - _fig_h * 0.06) - _emblem.size * 0.5
	_emblem.modulate = Color(1, 1, 1, 0.0)
	add_child(_emblem)

	# The hero (animated rig), feet near the bottom, scaled to fill the screen height.
	_anchor = Node2D.new()
	_anchor.name = "HeroAnchor"
	add_child(_anchor)
	_sprite = HeroArt.make_sprite(hero_id, skin) as HeroSprite
	if _sprite:
		_anchor.add_child(_sprite)
		_sprite.scale = Vector2.ONE
		var hgt: float = _sprite.get_height()
		var k := _fig_h / maxf(hgt, 1.0)
		_sprite.scale = Vector2(k, k)
	# Light in front of the hero (the held beat's orb), additive.
	_front = Control.new()
	_front.name = "Front"
	_front.mouse_filter = MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_front.material = Fx.additive()
	_front.draw.connect(_draw_front)
	add_child(_front)

	# Ambient sparkles rising (Epic and Legendary) and golden rain at the burst (Legendary).
	if rarity != "rare":
		_sparkles = _particles(36 if rarity == "epic" else 56, 3.4, false)
		_sparkles.position = Vector2(w * 0.5, h * 0.92)
		_sparkles.emission_rect_extents = Vector2(w * 0.55, 60)
		_sparkles.direction = Vector2(0, -1)
		_sparkles.spread = 14.0
		_sparkles.gravity = Vector2(0, -24)
		_sparkles.initial_velocity_min = 50.0
		_sparkles.initial_velocity_max = 150.0
		add_child(_sparkles)
	if rarity == "legendary":
		_rain = _particles(70, 2.2, true)
		_rain.position = _chest
		_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_rain.emission_sphere_radius = 30.0
		_rain.direction = Vector2(0, -1)
		_rain.spread = 180.0
		_rain.gravity = Vector2(0, 520)
		_rain.initial_velocity_min = 260.0
		_rain.initial_velocity_max = 820.0
		_rain.damping_min = 40.0
		_rain.damping_max = 120.0
		add_child(_rain)

	# Shade under the text block.
	var navy := Color("020814")
	var shade := TextureRect.new()
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.texture = Kit.vgradient(Color(navy, 0.0), Color(navy, 0.94))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.position = Vector2(0, h * 0.5)
	shade.size = Vector2(w, h * 0.5 + 4.0)
	shade.modulate.a = 0.0
	add_child(shade)
	_shade = shade

	_build_text(w, h, stars, faction)


func _particles(n: int, life: float, burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.one_shot = burst
	p.explosiveness = 1.0 if burst else 0.0
	p.emitting = false
	p.local_coords = false
	p.texture = Fx.soft_dot()
	p.material = Fx.additive()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.scale_amount_min = 0.06 if not burst else 0.08
	p.scale_amount_max = 0.18 if not burst else 0.22
	var g := Gradient.new()
	var c := _color.lerp(Color.WHITE, 0.35)
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.0))
	g.add_point(0.15, Color(c, 1.0))
	g.add_point(0.7, Color(c, 0.6))
	p.color_ramp = g
	return p


func _build_text(w: float, h: float, stars: int, faction: String) -> void:
	var x0 := 34.0
	var max_w := w - x0 * 2.0
	# NEW pill or the duplicate's shards.
	var is_new := bool(result.get("is_new", false))
	if is_new:
		_tag = _pill("NEW HERO", Kit.NEW_RED, Kit.ORANGE, "")
	else:
		var shards := int(result.get("shards", 0))
		var dust := int(result.get("dust", 0))
		var txt := "+%d SHARDS" % shards
		if dust > 0:
			txt = "+%d DUST" % dust if dust == shards else txt + "  +%d DUST" % dust
		_tag = _pill(txt, Color("1d3a66"), Color("0e2244"), "shard")
	# Rarity word.
	var b := Banner.new()
	b.setup(rarity, int(BANNER_SIZE[rarity]))
	_banner = b
	# Name, title, faction / role / stars.
	_name = Kit.label(str(_def.get("name", hero_id)).to_upper(), 88, Color.WHITE, "title", 10)
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_name.add_theme_constant_override("shadow_offset_y", 4)
	_name.add_theme_constant_override("shadow_outline_size", 10)
	Kit.fit_label(_name, max_w, 88, 48)
	var tcol := Kit.faction_color(faction).lerp(Color.WHITE, 0.35)
	_title = Kit.label(str(_def.get("title", "")).to_upper(), 30, tcol, "cond_bold", 5)
	Kit.fit_label(_title, max_w, 30, 20)
	var row := Kit.hbox(14)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(Kit.faction_badge(faction, 38))
	var rb := Kit.role_badge(str(_def.get("role", "")), 34)
	rb.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(rb)
	var sr := Kit.star_row(maxi(1, stars), 0, 34)
	sr.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(sr)
	_badges = row
	for c: Control in [_tag, _banner, _name, _title, _badges]:
		add_child(c)
		c.size = c.get_combined_minimum_size()
	# Stack bottom-up above the hint line, spacing the text rows by their cap heights (the
	# label boxes carry ascender / descender room that would make the gaps uneven).
	var y := h - safe_bottom - 112.0 - _badges.size.y
	var badges_y := y
	var tc := _caps(Kit.font("cond_bold"), _title.get_theme_font_size("font_size"))
	var title_y := y - 14.0 - tc.y
	y = title_y + tc.x
	var nc := _caps(Kit.font("title"), _name.get_theme_font_size("font_size"))
	var name_y := y - 12.0 - nc.y
	y = name_y + nc.x
	var bc := _caps(Kit.font("title"), int(BANNER_SIZE[rarity]))
	var banner_y := y - 16.0 - bc.y
	y = banner_y + bc.x
	var tag_y := y - 16.0 - _tag.size.y
	# Rows in schedule order: banner, name, title, badges, tag.
	_rows = [_banner, _name, _title, _badges, _tag]
	_row_pos = [Vector2(x0 - 4.0, banner_y), Vector2(x0 - 2.0, name_y), Vector2(x0, title_y), Vector2(x0, badges_y), Vector2(x0, tag_y)]
	for i in _rows.size():
		_rows[i].position = _row_pos[i]
		_rows[i].modulate.a = 0.0
	_banner.pivot_offset = _banner.size * Vector2(0.4, 0.5)
	_tag.pivot_offset = _tag.size * Vector2(0.2, 0.5)


## Cap box of a one-line label in `font` at `fs` px: x = cap top, y = baseline (from the
## label's top edge).
static func _caps(font: Font, fs: int) -> Vector2:
	var a := font.get_ascent(fs)
	return Vector2(a - fs * 0.72, a)


## Glossy pill: NEW (red-orange) or the shard count (navy glass with the shard glyph).
func _pill(text: String, top: Color, bottom: Color, icon_name: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Kit.box(top, bottom, Color(1, 1, 1, 0.55), 22.0, 2, 0))
	var r := Kit.hbox(8)
	r.mouse_filter = MOUSE_FILTER_IGNORE
	if icon_name != "":
		r.add_child(Kit.icon(icon_name, 30))
	r.add_child(Kit.label(text, 28, Color.WHITE, "cond_black", 4))
	p.add_child(Kit.margin(r, 18, 4))
	return p


# ------------------------------------------------------------------ timeline

func _build_events() -> void:
	_events.clear()
	match rarity:
		"rare":
			_events.append([0.0, "pop"])
		"epic":
			_events.append([0.0, "beat_start"])
			_events.append([_burst_t, "burst"])
			_events.append([_burst_t + float(_sched[0]), "slam"])
		"legendary":
			_events.append([0.0, "beat_start"])
			for i in PULSES.size():
				_events.append([float(PULSES[i]), "pulse%d" % i])
			_events.append([_burst_t, "burst"])
			_events.append([_burst_t + float(_sched[0]), "slam"])
	_events.append([_settle_t, "settle"])
	_next_event = 0


## Starts the clock (the sequence calls it when this hero's turn comes).
func start() -> void:
	_running = true
	_t = 0.0
	fx.emit("tint", _color, float(TINT[rarity]))
	_apply()


## A tap: during the held beat it jumps to the burst; while things are still landing it
## settles everything at once; once settled it returns true (show the next hero).
func tap() -> bool:
	if not _running:
		return false
	if _t < _burst_t - 0.02:
		_jump(_burst_t)
		return false
	if not settled:
		_jump(_settle_t)
		return false
	return true


## Lands everything immediately without the effects (screenshots, Skip).
func finish_now() -> void:
	_running = true
	_jump(_settle_t)


func _jump(to: float) -> void:
	# Events before `to` are skipped silently; one exactly at `to` still fires.
	while _next_event < _events.size() and float(_events[_next_event][0]) < to:
		var id := str(_events[_next_event][1])
		if id == "burst":
			_on_burst(true)
		_next_event += 1
	_t = to
	_fire_events()
	_apply()


func _process(delta: float) -> void:
	if not _running:
		return
	_t = _t + delta if hold < 0.0 else minf(_t + delta, hold)
	_fire_events()
	_apply()
	queue_redraw()
	if _t - _burst_t < 0.2 or _front_drawn:
		_front.queue_redraw()


func _fire_events() -> void:
	while _next_event < _events.size() and float(_events[_next_event][0]) <= _t:
		_on_event(str(_events[_next_event][1]))
		_next_event += 1


func _on_event(id: String) -> void:
	match id:
		"pop":
			UI.sfx("reveal")
			UI.haptic(12)
			fx.emit("flash", Color(0.9, 0.97, 1.0), 0.35)
			_spawn_burst(_chest, _color, 0.6)
			fx.emit("shake", Color.WHITE, 0.25)
		"beat_start":
			fx.emit("darken", Color.BLACK, 0.75 if rarity == "legendary" else 0.4)
			if rarity == "legendary":
				UI.sfx("riser")
				UI.haptic(15)
			else:
				UI.sfx("tell")
				UI.haptic(10)
		"pulse0", "pulse1", "pulse2":
			var n := int(id.substr(5))
			UI.sfx("beat")
			UI.haptic(12 + 8 * n)
			fx.emit("shake", Color.WHITE, 0.2 + 0.1 * n)
			fx.emit("flash", Kit.LEGENDARY, 0.1 + 0.06 * n)
		"burst":
			_on_burst(false)
		"slam":
			UI.sfx("slam")
			UI.haptic(35 if rarity == "legendary" else 22)
			fx.emit("shake", Color.WHITE, 0.45 if rarity == "legendary" else 0.3)
			_spawn_burst(_banner.position + _banner.size * Vector2(0.4, 0.5), _color, 0.5)
		"settle":
			settled = true
			landed.emit()


## The burst. quiet = reached by fast-forwarding past it (keep the visuals, drop the sound).
func _on_burst(quiet: bool) -> void:
	fx.emit("darken", Color.BLACK, 0.0)
	if _sparkles:
		_sparkles.emitting = true
	if quiet:
		return
	if rarity == "legendary":
		UI.sfx("legendary")
		UI.sfx("burst")
		UI.haptic(90)
		fx.emit("flash", Color(1.0, 0.93, 0.72), 1.0)
		fx.emit("shake", Color.WHITE, 1.0)
		_spawn_burst(_chest, Kit.LEGENDARY, 2.0)
		_spawn_burst(_chest, Color(1, 0.95, 0.8), 1.0)
		if _rain:
			_rain.emitting = true
	else:
		UI.sfx("burst")
		UI.sfx("reward")
		UI.haptic(45)
		fx.emit("flash", _color.lerp(Color.WHITE, 0.6), 0.7)
		fx.emit("shake", Color.WHITE, 0.6)
		_spawn_burst(_chest, _color, 1.2)


func _spawn_burst(at: Vector2, col: Color, strength: float) -> void:
	var b := Burst.new()
	b.color = col
	b.strength = strength
	b.position = at
	add_child(b)


## Slides out to the left and frees itself (the next hero comes in from the right).
func leave() -> void:
	_running = false
	set_process(false)
	if _sparkles:
		_sparkles.emitting = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:x", -size.x * 0.4, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)


# ------------------------------------------------------------------ state from the clock

func _apply() -> void:
	var t := _t
	var tb := t - _burst_t
	var after := tb >= 0.0
	var hero_a := 1.0
	var slide := 0.0
	var zoom := 1.0
	# Silhouette: the rig's flash tint toward a near-black color (held beats only).
	var shadow := 0.0
	var shadow_col := Color("07040c")
	# Overexposure: the hero blown out to glowing light that cools into her colors (an
	# overbright modulate; the rig's own flash is multiplied by the art so it can only darken).
	var glow := 0.0
	var glow_col := Color.WHITE
	match rarity:
		"rare":
			var k := Fx.out_cubic(Fx.k01(tb, 0.0, 0.38))
			hero_a = Fx.k01(tb, 0.0, 0.16)
			slide = 110.0 * (1.0 - k)
			zoom = 1.05 - 0.05 * k + 0.025 * Fx.out_sine(Fx.k01(tb, 0.4, 6.0))
			glow = 1.0 - Fx.out_cubic(Fx.k01(tb, 0.02, 0.45))
			glow_col = Color(1.5, 1.7, 1.9)
		"epic":
			if not after:
				hero_a = 0.85 * Fx.k01(t, 0.08, 0.45)
				shadow = 1.0
				shadow_col = Color("170c2c")
				zoom = 0.96 + 0.02 * Fx.k01(t, 0.0, _burst_t)
			else:
				glow = 1.0 - Fx.out_cubic(Fx.k01(tb, 0.0, 0.65))
				glow_col = Color(2.0, 1.5, 2.4)
				zoom = 1.08 - 0.08 * Fx.out_back(Fx.k01(tb, 0.0, 0.5)) + 0.03 * Fx.out_sine(Fx.k01(tb, 0.5, 6.0))
		"legendary":
			if not after:
				hero_a = 0.55 * Fx.k01(t, 0.35, 1.25)
				shadow = 1.0
				zoom = 0.93 + 0.03 * Fx.k01(t, 0.0, _burst_t)
			else:
				# Forms out of golden light.
				hero_a = Fx.k01(tb, 0.0, 0.15)
				glow = 1.0 - Fx.out_cubic(Fx.k01(tb, 0.15, 1.3))
				glow_col = Color(3.2, 2.5, 1.4)
				zoom = 1.12 - 0.12 * Fx.out_cubic(Fx.k01(tb, 0.0, 0.7)) + 0.06 * Fx.out_sine(Fx.k01(tb, 0.7, 7.0))
	# Hero: zoom around the chest.
	if _anchor:
		_anchor.scale = Vector2(zoom, zoom)
		_anchor.position = _chest + (_feet - _chest) * zoom + Vector2(slide, 0)
		var m := Color.WHITE.lerp(glow_col, glow)
		m.a = hero_a
		_anchor.modulate = m
	_set_tint(&"flash", shadow)
	_set_tint(&"flash_color", shadow_col)
	# Rays, emblem, shade.
	var ray_a := 0.0
	var ray_s := 1.0
	match rarity:
		"rare":
			ray_a = 0.16 * Fx.k01(tb, 0.0, 0.3)
		"epic":
			ray_a = 0.12 * Fx.k01(t, 0.0, _burst_t) if not after else 0.5
			ray_s = 0.55 if not after else 0.4 + 0.6 * Fx.out_back(Fx.k01(tb, 0.0, 0.45))
		"legendary":
			ray_a = 0.14 * Fx.k01(t, 0.2, _burst_t) if not after else 0.62
			ray_s = 0.45 if not after else 0.2 + 0.8 * Fx.out_expo(Fx.k01(tb, 0.0, 0.6))
			_rays.set("speed", 0.08 if not after else lerpf(0.9, 0.12, Fx.k01(tb, 0.0, 1.5)))
	_rays.modulate.a = ray_a
	_rays.scale = Vector2(ray_s, ray_s)
	_emblem.modulate.a = 0.11 * Fx.k01(tb, 0.1, 0.7)
	_shade.modulate.a = Fx.k01(tb, 0.0, 0.3)
	# Text rows.
	for i in _rows.size():
		var row := _rows[i]
		var s := float(_sched[i])
		if row == _banner and rarity != "rare":
			var p := Fx.k01(tb, s, s + SLAM_DUR)
			row.modulate.a = Fx.k01(tb, s, s + 0.07)
			var sc := lerpf(2.4 if rarity == "legendary" else 1.9, 1.0, Fx.out_back(p, 1.2))
			row.scale = Vector2(sc, sc)
			row.position = _row_pos[i]
		elif row == _tag:
			var p2 := Fx.k01(tb, s, s + 0.36)
			row.modulate.a = Fx.k01(tb, s, s + 0.1)
			var sc2 := lerpf(0.4, 1.0, Fx.out_back(p2, 2.2))
			row.scale = Vector2(sc2, sc2)
			row.position = _row_pos[i]
		else:
			var p3 := Fx.out_cubic(Fx.k01(tb, s, s + ROW_DUR))
			row.modulate.a = p3
			row.position = _row_pos[i] + Vector2(-60.0 * (1.0 - p3), 0)
	# The glint across the rarity word: once as it lands, then every few seconds.
	var gt := tb - float(_sched[0]) - 0.3
	var sheen := -1.0
	if gt >= 0.0:
		var g := fmod(gt, 3.2)
		if g < 0.7:
			sheen = g / 0.7
	_banner.set("sheen", sheen)


func _set_tint(param: StringName, v: Variant) -> void:
	if _sprite == null or _sprite.rig == null:
		return
	if _tint_cache.get(param) == v:
		return
	_tint_cache[param] = v
	_sprite.rig.set_tint(param, v)


# ------------------------------------------------------------------ the orb and glows

## Behind the hero: the rarity glow once she is revealed.
func _draw() -> void:
	var tb := _t - _burst_t
	if tb < 0.0:
		return
	var ga := float(BACK_GLOW[rarity]) * Fx.k01(tb, 0.0, 0.25)
	var gr := size.x * 0.8
	draw_texture_rect(Fx.soft_dot(), Rect2(_chest - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(_color, ga))


## In front of the hero (the _front layer): the held beat's orb gathering light, pulsing like
## a heartbeat for a Legendary, then blowing out at the burst.
func _draw_front() -> void:
	var t := _t
	var tb := t - _burst_t
	_front_drawn = not (rarity == "rare" or tb > 0.12)
	if not _front_drawn:
		return
	var ci := _front
	var soft := Fx.soft_dot()
	var w := size.x
	var kb := Fx.k01(t, 0.0, _burst_t)
	var pulse := 1.0
	if rarity == "legendary":
		for pt: float in PULSES:
			if t >= pt:
				pulse += 0.45 * exp(-(t - pt) * 7.0)
	var implode := Fx.in_cubic(Fx.k01(t, _burst_t - 0.2, _burst_t))
	var r := (30.0 + 62.0 * kb) * pulse * (1.0 - 0.7 * implode)
	if tb > 0.0:
		r *= 1.0 + tb * 30.0
	var fade := 1.0 - Fx.k01(tb, 0.0, 0.12)
	var hot := _color.lerp(Color.WHITE, 0.5)
	var c := _chest
	# Light pouring in.
	for i in 28:
		var life := fposmod(_motes[i * 3 + 1] + t * (0.6 + 1.6 * kb), 1.0)
		var dist := w * 0.75 * (1.0 - life * life)
		var dir := Vector2.from_angle(_motes[i * 3])
		var ln := 40.0 + 120.0 * kb
		Fx.streak(_quad, c + dir * dist, c + dir * (dist + ln), 3.0 + 2.0 * kb, 0.0)
		var a := sin(PI * life) * (0.3 + 0.6 * kb) * fade
		_qcol[0] = Color(hot, a)
		_qcol[1] = Color(_color, 0.0)
		_qcol[2] = Color(_color, 0.0)
		_qcol[3] = Color(hot, a)
		ci.draw_polygon(_quad, _qcol)
	var big := r * 4.0
	ci.draw_texture_rect(soft, Rect2(c - Vector2(big, big), Vector2(big, big) * 2.0), false, Color(_color, (0.3 + 0.35 * kb) * fade))
	var mid := r * 2.0
	ci.draw_texture_rect(soft, Rect2(c - Vector2(mid, mid), Vector2(mid, mid) * 2.0), false, Color(hot, 0.85 * fade))
	ci.draw_circle(c, r * 0.5, Color(1, 1, 1, 0.95 * fade), true, -1.0, true)
	# A thin ring that tightens with each heartbeat.
	if rarity == "legendary":
		var rr := r * (2.6 - 0.8 * kb)
		ci.draw_texture_rect(Fx.ring(), Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(hot, 0.5 * kb * fade))
