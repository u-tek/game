extends SceneTree
## HaloRig self-test (headless): every built rig loads, every animation parses and plays to the
## end on every rig, events and anim_finished fire, transforms stay finite, easing is sane.
##   tools/gd --headless --path . -s tools/art_selftest.gd
## Prints "art_selftest: N checks, 0 failures" and exits 1 on failure.

var fails := 0
var checks := 0


func _ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		printerr("FAIL ", msg)


func _init() -> void:
	# easing endpoints
	for e in RigAnim.EASE_NAMES.values():
		_ok(absf(RigAnim.ease_value(e, 0.0)) < 0.001, "ease %d starts at 0" % e)
		_ok(absf(RigAnim.ease_value(e, 1.0) - 1.0) < 0.001, "ease %d ends at 1" % e)
	var heroes: Array = []   # [hero id, skin art folder ("" = the base look)]
	for d in DirAccess.get_directories_at("res://assets/art/heroes/"):
		if RigData.exists(d):
			heroes.append([d, ""])
		var sk := "res://assets/art/heroes/%s/skins/" % d
		if DirAccess.dir_exists_absolute(sk):
			for art in DirAccess.get_directories_at(sk):
				if RigData.exists(d, art):
					heroes.append([d, art])
	_ok(heroes.size() > 0, "at least one built rig")
	var anims: Array[String] = []
	for dir in ["res://assets/art/anim/", "res://assets/art/anim/warp/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".anim.json") and not anims.has(f.trim_suffix(".anim.json")):
				anims.append(f.trim_suffix(".anim.json"))
	for pair in heroes:
		var hero_id: String = pair[0]
		var h: String = hero_id if pair[1] == "" else "%s@%s" % pair    # label in messages
		var r := RigData.load_rig(hero_id, pair[1])
		_ok(r != null, "%s loads" % h)
		if r == null:
			continue
		_ok(r.bone_names.size() > 0 and r.parent[0] == -1, "%s has a root bone first" % h)
		for i in r.bone_names.size():
			_ok(r.parent[i] < i, "%s bone %s parent precedes it" % [h, r.bone_names[i]])
		if r.kind == "warp":
			_ok(r.mesh != null and r.mesh.get_surface_count() == 1, "%s warp mesh built" % h)
			_ok(r.image != null, "%s warp image loads" % h)
			_ok(r.bone_names.size() <= RigPlayer.MAX_WARP_BONES, "%s within the warp bone limit" % h)
		for a in anims:
			var p := RigPlayer.new()
			p.manual = true
			p.setup(r)
			var events: Array[String] = []
			var finished: Array[String] = []
			p.anim_event.connect(func(n: String) -> void: events.append(n))
			p.anim_finished.connect(func(n: String) -> void: finished.append(n))
			var an := RigAnim.find(a, hero_id, r.kind)
			_ok(an != null, "%s/%s found" % [h, a])
			if an == null:
				p.free()
				continue
			p.play("idle", 0)
			p.play(a, 1 if not an.loop else 0)
			var t := 0.0
			while t < an.duration + 0.5:
				p.advance(1.0 / 30.0)
				t += 1.0 / 30.0
			var finite := true
			for i in r.bone_names.size():
				var o := p.get_bone_position(r.bone_names[i])
				if is_nan(o.x) or is_nan(o.y) or is_inf(o.x) or is_inf(o.y):
					finite = false
			_ok(finite, "%s/%s transforms finite" % [h, a])
			for ev in an.events:
				_ok(events.has(ev[1]), "%s/%s fired event %s" % [h, a, ev[1]])
			if not an.loop:
				_ok(finished.has(an.name), "%s/%s finished" % [h, a])
			p.free()
	# HeroArt API used by the screens (every roster hero, art or fallback)
	for id in HeroData.ids():
		var tex := HeroArt.texture(id)
		_ok(tex != null and tex.get_width() > 0, "HeroArt.texture(%s)" % id)
		var pr := HeroArt.portrait_region(id)
		_ok(tex != null and Rect2(Vector2.ZERO, tex.get_size()).encloses(pr.grow(-1.0)), "portrait_region(%s) inside the still" % id)
		var por := HeroArt.make_portrait(id, 96)
		_ok(por is TextureRect and (por as TextureRect).texture != null, "make_portrait(%s)" % id)
		por.free()
		var spr := HeroArt.make_sprite(id) as HeroSprite
		_ok(spr != null and spr.rig != null and spr.rig.rig != null, "make_sprite(%s)" % id)
		if spr and spr.rig:
			spr.rig.manual = true
			_ok(spr.play_attack(Vector2(500, 0)) != "", "%s attack" % id)
			_ok(spr.play_cast() != "", "%s cast" % id)
			spr.rig.advance(0.5)
		spr.free()
	# every installed skin through the same API
	for s in SkinData.all():
		var hid := str(s["hero"])
		var sid := str(s["id"])
		if not HeroArt.has_skin_art(hid, sid):
			continue
		var por := HeroArt.make_portrait(hid, 96, sid)
		_ok(por is TextureRect and (por as TextureRect).texture != null, "make_portrait(%s, %s)" % [hid, sid])
		por.free()
		var spr := HeroArt.make_sprite(hid, sid) as HeroSprite
		_ok(spr != null and spr.rig != null and spr.rig.rig != null, "make_sprite(%s, %s)" % [hid, sid])
		if spr and spr.rig:
			spr.rig.manual = true
			_ok(spr.play_attack(Vector2(500, 0)) != "", "%s attack" % sid)
			spr.rig.advance(0.5)
		spr.free()
	print("art_selftest: %d checks, %d failures (%d rigs, %d animations)" % [checks, fails, heroes.size(), anims.size()])
	quit(1 if fails > 0 else 0)
