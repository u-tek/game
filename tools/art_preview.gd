extends SceneTree
## Renders HaloRig characters to PNG frames (pose tests, animation previews, perf numbers).
## Needs a rendering driver (not --headless):
##   flock /tmp/halo-godot.lock xvfb-run -a -s "-screen 0 1800x2400x24" godot --path . \
##     --rendering-driver opengl3 --resolution 64x64 -s tools/art_preview.gd -- jobs.json
## jobs.json: [{"hero": "seraphiel", "skin": "<skin id, optional>", "out": "dir", "size": [600, 1000], "scale": 0.45,
##   "idle_amount": 1.0 (format 2 rigs: scales the procedural idle), "auto_blink": true,
##   "feet": [300, 960], "fps": 30, "warm": 1.0, "base": "idle",
##   "frames": [{"anim": "attack_ranged", "track": 1, "t": 0.4, "look": [0, 0],
##               "flip": false, "echo": false, "label": "x"}...]          # single poses
##   or "anim": "idle", "track": 0, "count": 96                           # a sequence
## }]  Every frame is written as <out>/<label or index>.png with a transparent background.
## {"bench": 10, "hero": "seraphiel", "seconds": 3} measures rig update cost instead.

var _vp: SubViewport


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# render as the iPhone does (HDR 2D off) and tell the canvas shaders so, as main.gd does in the
	# game: the foil on Legendary heroes otherwise converts for a linear canvas (a gamma too dark)
	root.use_hdr_2d = false
	RenderingServer.global_shader_parameter_set(&"ui_linear", 0.0)
	if args.is_empty():
		printerr("usage: art_preview.gd -- jobs.json")
		quit(1)
		return
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not (jobs is Array):
		printerr("ERROR: bad jobs file")
		quit(1)
		return
	_run.call_deferred(jobs)


func _run(jobs: Array) -> void:
	for j in jobs:
		if j.has("bench"):
			await _bench(j)
		elif j.has("timeline"):
			await _timeline(j)
		else:
			await _job(j)
	quit()


## {"timeline": [[t, action], ...], "duration": s, "expression": {"eyes": "open"}, ...}
## actions: attack | cast | ultimate | hit | death | victory | idle | blink | <any animation>
func _timeline(j: Dictionary) -> void:
	var size: Array = j.get("size", [600, 1000])
	_vp = _new_vp(size)
	var feet: Array = j.get("feet", [size[0] * 0.5, size[1] * 0.96])
	var sc := float(j.get("scale", 0.45))
	var out := str(j.get("out", "/tmp/rigprev"))
	DirAccess.make_dir_recursive_absolute(out)
	var dt := 1.0 / float(j.get("fps", 30.0))
	var sprite := _make(j)
	sprite.position = Vector2(float(feet[0]), float(feet[1]))
	sprite.scale = Vector2(sc / HeroSprite.BASE_SCALE, sc / HeroSprite.BASE_SCALE)
	_vp.add_child(sprite)
	sprite.rig.manual = true
	sprite.rig.blink_enabled = bool(j.get("auto_blink", false))
	sprite.set_process(false)
	var ex: Dictionary = j.get("expression", {})
	for k in ex:
		sprite.set_expression(k, str(ex[k]))
	var tt := 0.0
	while tt < float(j.get("warm", 1.5)):
		_step(sprite, dt)
		tt += dt
	var tl: Array = j.get("timeline", [])
	var t := 0.0
	var k := 0
	var n := int(float(j.get("duration", 3.0)) / dt + 0.5)
	for i in n:
		while k < tl.size() and float(tl[k][0]) <= t + 0.0001:
			var act := str(tl[k][1])
			match act:
				"attack":
					sprite.play_attack(sprite.global_position + Vector2(float(j.get("target_dx", 700.0)), 0))
				"cast":
					sprite.play_cast()
				"ultimate":
					sprite.play_ultimate(sprite.global_position + Vector2(float(j.get("target_dx", 700.0)), 0))
				"hit":
					sprite.play_hit()
				"death":
					sprite.play_death()
				"victory":
					sprite.play_victory()
				"idle":
					sprite.play_idle()
				"blink":
					sprite.rig.blink()
				_:
					if act.begins_with("expr:"):     # expr:eyes=open  /  expr:eyes=
						var kv := act.substr(5).split("=")
						sprite.set_expression(kv[0], kv[1] if kv.size() > 1 else "")
					else:
						sprite.play(act)
			k += 1
		_step(sprite, dt if i > 0 else 0.0)
		await RenderingServer.frame_post_draw
		_save(_vp.get_texture().get_image(), out.path_join("%04d.png" % i))
		t += dt
	print("art_preview: %d frame(s) -> %s" % [n, out])
	sprite.queue_free()
	_vp.queue_free()
	await process_frame


func _job(j: Dictionary) -> void:
	var size: Array = j.get("size", [600, 1000])
	_vp = _new_vp(size)
	var holder := Node2D.new()
	_vp.add_child(holder)
	var feet: Array = j.get("feet", [size[0] * 0.5, size[1] * 0.96])
	var sc := float(j.get("scale", 0.45))
	var out := str(j.get("out", "/tmp/rigprev"))
	DirAccess.make_dir_recursive_absolute(out)
	var fps := float(j.get("fps", 30.0))
	var dt := 1.0 / fps
	var frames: Array = j.get("frames", [])
	var seq := str(j.get("anim", ""))
	if seq != "":
		for i in int(j.get("count", 60)):
			frames.append({"anim": seq, "track": int(j.get("track", 0)), "seq_index": i})
	var sprite: HeroSprite = null
	var made_for := ""
	var idx := 0
	var seq_started := false
	for fr in frames:
		var key := "%s|%s|%s" % [fr.get("flip", false), fr.get("echo", false), fr.get("boss", false)]
		var is_seq: bool = fr.has("seq_index")
		if sprite == null or (not is_seq and key != made_for) or (not is_seq and fr.get("fresh", true)):
			if sprite != null:
				sprite.queue_free()
				await process_frame
			sprite = _make(j)
			sprite.position = Vector2(float(feet[0]), float(feet[1]))
			sprite.scale = Vector2(sc / HeroSprite.BASE_SCALE, sc / HeroSprite.BASE_SCALE)
			holder.add_child(sprite)
			sprite.rig.manual = true
			sprite.set_process(false)
			# "idle_amount": scales the procedural idle (format 2 rigs; 4 shows how the parts deform)
			sprite.rig.idle_amount = float(j.get("idle_amount", 1.0))
			sprite.rig.blink_enabled = bool(j.get("auto_blink", true))
			if bool(fr.get("flip", false)):
				sprite.set_facing(-1)
			if bool(fr.get("echo", false)):
				sprite.set_echo(true)
			if bool(fr.get("boss", false)):
				sprite.set_boss(true)
			made_for = key
			seq_started = false
			# settle physics in the base animation
			var base := str(j.get("base", "idle"))
			sprite.rig.play(base, 0)
			var warm := float(j.get("warm", 1.0))
			var tt := 0.0
			while tt < warm:
				_step(sprite, dt)
				tt += dt
		var anim := str(fr.get("anim", ""))
		var track := int(fr.get("track", 1))
		sprite.rig.look_extra = Vector2(fr.get("look", [0, 0])[0], fr.get("look", [0, 0])[1])
		if is_seq:
			if not seq_started:
				if anim == "death":
					sprite.play_death()
				elif anim != str(j.get("base", "idle")) or track != 0:
					sprite.rig.play(anim, track)
				seq_started = true
				_step(sprite, 0.0)
			else:
				_step(sprite, dt)
		elif anim != "":
			if anim == "death":
				sprite.play_death()
			else:
				sprite.rig.play(anim, track, -1, 0.0)
			var t := float(fr.get("t", 0.0))
			var tt2 := 0.0
			_step(sprite, 0.0)
			while tt2 + dt <= t + 0.0001:
				_step(sprite, dt)
				tt2 += dt
		await RenderingServer.frame_post_draw
		var label := str(fr.get("label", "%04d" % idx))
		_save(_vp.get_texture().get_image(), out.path_join(label + ".png"))
		idx += 1
	print("art_preview: %d frame(s) -> %s" % [idx, out])
	_vp.queue_free()
	await process_frame


## The job's sprite. "art": a skin art folder (assets/art/heroes/<hero>/skins/<art>/), e.g. a local
## prototype that is not in data/skins.json; "skin": a catalogue skin id; neither: the base look.
func _make(j: Dictionary) -> HeroSprite:
	var hero := str(j.get("hero", "seraphiel"))
	var s: HeroSprite
	if j.has("art"):
		s = HeroSprite.new()
		s.setup(hero, str(j["art"]))
	else:
		s = HeroArt.make_sprite(hero, str(j.get("skin", ""))) as HeroSprite
	if j.has("holo"):          # "holo": false shows a Legendary hero without the foil
		s.holo = bool(j["holo"])
	return s


## The preview viewport: HDR 2D off, as on the iPhone (ui_linear 0, see _init).
func _new_vp(size: Array) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(size[0]), int(size[1]))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	vp.use_hdr_2d = false
	root.add_child(vp)
	return vp


func _save(img: Image, path: String) -> void:
	img.save_png(path)


func _step(s: HeroSprite, dt: float) -> void:
	s.rig.advance(dt)
	s._process(dt)


func _bench(j: Dictionary) -> void:
	var n := int(j.get("bench", 10))
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1280)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var sprites: Array = []
	for i in n:
		var s := _make(j)
		s.position = Vector2(80 + (i % 5) * 140, 500 + (i / 5) * 420)
		if i >= 5:
			s.set_facing(-1)
			s.set_echo(true)
		vp.add_child(s)
		s.rig.manual = true
		s.set_process(false)
		sprites.append(s)
	var dt := 1.0 / 60.0
	for s in sprites:
		(s as HeroSprite).rig.advance(dt)
	var frames := int(float(j.get("seconds", 3.0)) * 60.0)
	var t0 := Time.get_ticks_usec()
	for f in frames:
		for k in sprites.size():
			var s: HeroSprite = sprites[k]
			if f % 90 == k * 7 % 90:
				s.play_attack(s.global_position + Vector2(300, 0))
			s.rig.advance(dt)
			s._process(dt)
	var us := float(Time.get_ticks_usec() - t0) / frames
	var r: RigData = (sprites[0] as HeroSprite).rig.rig
	print("art_preview bench: %d rigs, %.3f ms per frame for all rig updates (%.3f ms per rig); %d bones, %d slots, %.2f Mpx textures" % [
		n, us / 1000.0, us / 1000.0 / n, r.bone_names.size(), r.slots.size(), r.texture_pixels() / 1000000.0])
	# render cost (software GL here, so only a rough relative number)
	var t1 := Time.get_ticks_usec()
	for f in 30:
		for s in sprites:
			(s as HeroSprite).rig.advance(dt)
		await RenderingServer.frame_post_draw
	print("art_preview bench: %.2f ms per rendered frame incl. draw (llvmpipe software GL, not representative of a phone GPU)" % [float(Time.get_ticks_usec() - t1) / 30000.0])
	vp.queue_free()
	await process_frame
